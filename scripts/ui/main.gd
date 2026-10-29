extends Control
## Shotgun Rummy: local pass-and-play UI (phone first).
##
## Screens are built in code: setup -> table, with overlays on top for
## "pass the phone", item reveals, round results, the shotgun, rules and the log.

const Game = preload("res://scripts/core/game.gd")
const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const MeldView = preload("res://scripts/ui/meld_view.gd")
const ShotgunView = preload("res://scripts/ui/shotgun_view.gd")

const SETTINGS_PATH := "user://settings.cfg"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
const CARD_SIZE := Vector2(80, 116)
const ITEM_SIZE := Vector2(86, 112)
const PILE_SIZE := Vector2(76, 110)
const LIFT := 18.0

var game: Game
var player_names: Array = ["PLAYER 1", "PLAYER 2"]
var hide_hands := true

var selected: Array = [] # playing card ids
var selected_item := ""
var lit_card := "" # the card just drawn, glows in your hand
var sort_by_rank := false
var hints := true
var message := ""
var log_lines: Array = []
var seen_upto := {} # seat -> how many log lines that player has seen
var turn_counter := 0
var shown_turn := -1
var shown_result_round := 0

# layers
var screen: Control
var overlay_layer: Control
var flash_rect: ColorRect

# table widgets
var round_label: Label
var trump_label: Label
var go_out_label: Label
var opponents_box: VBoxContainer
var stock_view: CardView
var stock_label: Label
var discard_view: CardView
var meld_flow: HFlowContainer
var me_name: Label
var me_hp: HBoxContainer
var deadwood_label: Label
var status_label: Label
var items_row: HBoxContainer
var hand_row: HBoxContainer
var meld_btn: Button
var use_btn: Button
var discard_btn: Button
var sort_btn: Button
var hint_btn: Button


func _ready() -> void:
	theme = Palette.make_theme()
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_full(bg))

	screen = _full(Control.new())
	add_child(screen)

	var vignette := _vignette()
	add_child(vignette)
	_flicker(vignette)
	overlay_layer = _full(Control.new())
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_full(flash_rect))

	_load_settings()
	show_setup()


# ================================================================ helpers

func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _label(text: String, font_size: int = 30, color: Color = Palette.INK, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A single-line label for use inside rows.
func _tag(text: String, font_size: int = 30, color: Color = Palette.INK) -> Label:
	var l := _label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _button(text: String, on_press: Callable, font_size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(on_press)
	return b


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _hp_bar(p, seg: Vector2 = Vector2(26, 14)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in range(p.max_hp):
		var s := ColorRect.new()
		s.custom_minimum_size = seg
		s.color = Palette.RED if i < p.hp else Palette.HP_EMPTY
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(s)
	return row


func _flags(p) -> String:
	var f := ""
	if p.cuffed:
		f += " ⛓️"
	if p.sawed:
		f += " 🪚"
	return f


func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.15, 1.1)
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(r)
	return r


## The overhead light flickers now and then.
func _flicker(r: Control) -> void:
	var t := r.create_tween().set_loops()
	t.tween_interval(6.0)
	t.tween_property(r, "modulate:a", 1.6, 0.05)
	t.tween_property(r, "modulate:a", 1.0, 0.08)
	t.tween_property(r, "modulate:a", 1.4, 0.05)
	t.tween_property(r, "modulate:a", 1.0, 0.1)


func _flash(color: Color) -> void:
	flash_rect.color = Color(color, 0.9)
	var t := create_tween()
	t.tween_property(flash_rect, "color:a", 0.0, 0.45)


func _shake() -> void:
	var t := create_tween()
	for i in range(6):
		t.tween_property(screen, "position", Vector2(randf_range(-14, 14), randf_range(-10, 10)), 0.04)
	t.tween_property(screen, "position", Vector2.ZERO, 0.05)
	Input.vibrate_handheld(250)


func _name(seat: int) -> String:
	return game.players[seat].name


# ================================================================ settings

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	player_names = cfg.get_value("setup", "names", player_names)
	hide_hands = cfg.get_value("setup", "hide_hands", true)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "names", player_names)
	cfg.set_value("setup", "hide_hands", hide_hands)
	cfg.save(SETTINGS_PATH)


# ================================================================ setup screen

var _name_edits: Array = []


func show_setup() -> void:
	_close_overlay()
	_clear(screen)
	var center := CenterContainer.new()
	screen.add_child(_full(center))

	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", Palette.box(Palette.WAIVER, Color(0, 0, 0, 0), 0, 2, 28))
	paper.custom_minimum_size = Vector2(620, 0)
	paper.rotation_degrees = -1.0
	center.add_child(paper)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	paper.add_child(box)
	box.add_child(_label("SHOTGUN\nRUMMY", 76, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label("GENERAL RELEASE OF LIABILITY", 24, Palette.CARD_INK, true))
	box.add_child(_label("The undersigned agree to a game of Rummy. Strange things are dealt with the cards. Whoever goes out gets the shotgun. Everyone has 4 lives. Only one leaves.", 24, Palette.CARD_INK))

	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.add_theme_constant_override("separation", 16)
	box.add_child(count_row)
	count_row.add_child(_tag("PLAYERS", 30, Palette.CARD_INK))
	count_row.add_child(_button(" - ", _change_count.bind(-1)))
	count_row.add_child(_tag(str(player_names.size()), 40, Palette.CARD_INK))
	count_row.add_child(_button(" + ", _change_count.bind(1)))

	_name_edits = []
	for i in range(player_names.size()):
		var row := HBoxContainer.new()
		row.add_child(_tag("%d." % (i + 1), 30, Palette.CARD_INK))
		var edit := LineEdit.new()
		edit.text = str(player_names[i])
		edit.placeholder_text = "SIGN HERE"
		edit.max_length = 10
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		box.add_child(row)
		_name_edits.append(edit)

	var hide_box := CheckBox.new()
	hide_box.text = "HIDE HANDS BETWEEN TURNS"
	hide_box.button_pressed = hide_hands
	hide_box.add_theme_color_override("font_color", Palette.CARD_INK)
	hide_box.add_theme_color_override("font_pressed_color", Palette.CARD_INK)
	hide_box.add_theme_color_override("font_hover_color", Palette.CARD_INK)
	hide_box.add_theme_color_override("font_hover_pressed_color", Palette.CARD_INK)
	hide_box.add_theme_font_size_override("font_size", 26)
	hide_box.toggled.connect(_on_hide_toggled)
	box.add_child(hide_box)

	var sign_btn := _button("SIGN THE WAIVER", _start_from_setup, 34)
	sign_btn.add_theme_stylebox_override("normal", Palette.box(Palette.CARD_INK, Palette.CARD_INK, 2, 2, 10))
	box.add_child(sign_btn)


func _on_hide_toggled(on: bool) -> void:
	hide_hands = on


func _read_names() -> void:
	for i in range(_name_edits.size()):
		player_names[i] = _name_edits[i].text


func _change_count(delta: int) -> void:
	_read_names()
	var n := clampi(player_names.size() + delta, MIN_PLAYERS, MAX_PLAYERS)
	while player_names.size() < n:
		player_names.append("PLAYER %d" % (player_names.size() + 1))
	while player_names.size() > n:
		player_names.pop_back()
	show_setup()


func _start_from_setup() -> void:
	_read_names()
	var used := {}
	for i in range(player_names.size()):
		var n := str(player_names[i]).strip_edges().to_upper()
		if n == "":
			n = "PLAYER %d" % (i + 1)
		while used.has(n):
			n += "*"
		used[n] = true
		player_names[i] = n
	_save_settings()
	start_match()


# ================================================================ match flow

func start_match() -> void:
	game = Game.new()
	game.setup(player_names)
	game.event.connect(_on_game_event)
	log_lines = []
	seen_upto = {}
	turn_counter = 0
	shown_turn = -1
	shown_result_round = 0
	_build_table()
	game.start_round()
	_after_action()


func _on_game_event(kind: String, d: Dictionary) -> void:
	match kind:
		"round_start":
			_log("— ROUND %d — %s deals. %s goes first." % [d["round"], _name(d["dealer"]), _name(d["first"])])
		"turn_start":
			turn_counter += 1
		"turn_skipped":
			_log("%s is in handcuffs and skips a turn." % _name(d["seat"]))
		"draw":
			if d["source"] == "discard":
				_log("%s takes %s from the discard pile." % [_name(d["seat"]), Cards.card_name(d["card"])])
			else:
				if d.get("item", false):
					_log("%s draws an item from the stock and draws again." % _name(d["seat"]))
				else:
					_log("%s draws from the stock." % _name(d["seat"]))
		"meld":
			_log("%s melds %s." % [_name(d["seat"]), Cards.cards_text(d["meld"]["cards"])])
		"layoff":
			_log("%s lays off %s." % [_name(d["seat"]), Cards.cards_text(d["cards"])])
		"discard":
			_log("%s discards %s." % [_name(d["seat"]), Cards.card_name(d["card"])])
		"item_used":
			_log(str(d["text"]) + ".")
		"damage":
			_log("%s is down to %d health." % [_name(d["seat"]), d["hp"]])
		"eliminated":
			_log("%s IS OUT." % _name(d["seat"]))
		"stock_reshuffled":
			_log("The discard pile is shuffled into a new stock.")
		"round_end":
			if d["winner"] < 0:
				_log("The deck ran dry. Nobody scores.")
			else:
				_log("%s goes out%s: %d points, %d shell%s." % [_name(d["winner"]), " with RUMMY" if d["rummy"] else "", d["points"], d["shells"], "" if d["shells"] == 1 else "s"])
		"shot":
			_log("%s shoots %s." % [_name(d["shooter"]), _name(d["target"])])
		"match_end":
			if d["winner"] >= 0:
				_log("%s WALKS OUT." % _name(d["winner"]))


func _log(text: String) -> void:
	log_lines.append(text)


## Decides what to show after anything happens.
func _after_action() -> void:
	match game.phase:
		"shoot", "round_over":
			if shown_result_round != game.round_num:
				shown_result_round = game.round_num
				_refresh()
				_show_round_result()
				return
		"match_over":
			_refresh()
			if overlay_layer.get_child_count() == 0:
				_show_match_end()
			return
		"draw", "play":
			if shown_turn != turn_counter:
				selected = []
				selected_item = ""
				lit_card = ""
				message = ""
				if hide_hands:
					_refresh()
					_show_pass_screen()
					return
				_mark_turn_seen()
	_refresh()


func _mark_turn_seen() -> void:
	shown_turn = turn_counter
	seen_upto[game.turn] = log_lines.size()


func _handle(res: Dictionary) -> bool:
	if not res["ok"]:
		message = res["error"]
		_refresh()
		return false
	message = ""
	selected = []
	return true


# ================================================================ table

func _build_table() -> void:
	_close_overlay()
	_clear(screen)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 20)
	screen.add_child(_full(margin))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	# top bar
	var top := HBoxContainer.new()
	round_label = _label("", 24, Palette.DIM)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	round_label.clip_text = true
	top.add_child(round_label)
	trump_label = _tag("", 24, Palette.GOLD)
	top.add_child(trump_label)
	for b in [_button("LOG", _show_log, 22), _button("RULES", _show_rules, 22), _button("MENU", _show_menu, 22)]:
		b.custom_minimum_size = Vector2(0, 46)
		top.add_child(b)
	col.add_child(top)

	opponents_box = VBoxContainer.new()
	opponents_box.add_theme_constant_override("separation", 4)
	col.add_child(opponents_box)

	# felt: piles + melds
	var felt := PanelContainer.new()
	felt.add_theme_stylebox_override("panel", Palette.box(Palette.FELT, Palette.WOOD, 8, 18, 12))
	felt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(felt)
	var felt_row := HBoxContainer.new()
	felt_row.add_theme_constant_override("separation", 12)
	felt.add_child(felt_row)
	var piles := VBoxContainer.new()
	piles.add_theme_constant_override("separation", 4)
	felt_row.add_child(piles)
	stock_view = CardView.new()
	stock_view.setup({}, PILE_SIZE, 0.0, true)
	stock_view.tapped.connect(func(_id: String) -> void: _draw_stock())
	piles.add_child(stock_view)
	stock_label = _label("STOCK", 18, Palette.DIM, true)
	piles.add_child(stock_label)
	discard_view = CardView.new()
	discard_view.setup({}, PILE_SIZE)
	discard_view.tapped.connect(func(_id: String) -> void: _draw_discard())
	piles.add_child(discard_view)
	piles.add_child(_label("DISCARD", 18, Palette.DIM, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	felt_row.add_child(scroll)
	meld_flow = HFlowContainer.new()
	meld_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meld_flow.add_theme_constant_override("h_separation", 8)
	meld_flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(meld_flow)

	# current player
	var me_row := HBoxContainer.new()
	me_row.add_theme_constant_override("separation", 12)
	me_name = _label("", 30)
	me_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	me_row.add_child(me_name)
	me_hp = HBoxContainer.new()
	me_row.add_child(me_hp)
	deadwood_label = _label("", 22, Palette.DIM)
	deadwood_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deadwood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	me_row.add_child(deadwood_label)
	col.add_child(me_row)

	status_label = _label("", 26, Palette.AMBER, true)
	status_label.custom_minimum_size = Vector2(0, 62)
	col.add_child(status_label)

	go_out_label = _label("", 30, Palette.GOLD, true)
	go_out_label.visible = false
	col.add_child(go_out_label)

	items_row = HBoxContainer.new()
	items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	items_row.add_theme_constant_override("separation", 10)
	col.add_child(items_row)

	hand_row = HBoxContainer.new()
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_row.custom_minimum_size = Vector2(0, CARD_SIZE.y + LIFT)
	col.add_child(hand_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	meld_btn = _button("MELD", _meld_selected)
	use_btn = _button("USE ITEM", _use_selected_item)
	discard_btn = _button("DISCARD", _discard_selected)
	Palette.accent(use_btn, Palette.PURPLE)
	Palette.accent(discard_btn, Palette.RED)
	for b in [meld_btn, use_btn, discard_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	col.add_child(buttons)

	var minor := HBoxContainer.new()
	minor.alignment = BoxContainer.ALIGNMENT_CENTER
	minor.add_theme_constant_override("separation", 16)
	sort_btn = _button("SORT: SUIT", _toggle_sort, 22)
	hint_btn = _button("HINTS: ON", _toggle_hints, 22)
	for b in [sort_btn, hint_btn]:
		b.custom_minimum_size = Vector2(200, 46)
		minor.add_child(b)
	col.add_child(minor)


func _refresh() -> void:
	if game == null or round_label == null:
		return
	var seat := game.turn
	var me = game.players[seat]
	var my_turn := game.phase == "draw" or game.phase == "play"

	round_label.text = "ROUND %d · %s DEALS" % [game.round_num, _name(game.dealer)]
	trump_label.text = "TRUMP: %s  " % trump_name(game.trump_rank) if game.trump_rank > 0 else ""

	# other players, in turn order after the current one
	_clear(opponents_box)
	for i in range(game.players.size()):
		var p = game.players[(seat + 1 + i) % game.players.size()]
		if p.seat == seat:
			continue
		opponents_box.add_child(_opponent_row(p))

	# piles
	var can_draw := my_turn and game.phase == "draw"
	stock_view.glow = can_draw
	stock_view.face_down = not game.stock.is_empty()
	stock_view.queue_redraw()
	stock_label.text = "STOCK %d" % game.stock.size() if not game.stock.is_empty() else "SHUFFLE"
	discard_view.card = game.top_discard()
	discard_view.trump = not discard_view.card.is_empty() and game.is_trump(discard_view.card)
	discard_view.glow = can_draw and not game.discard_pile.is_empty()
	discard_view.queue_redraw()

	# melds
	var sel_cards := _selected_cards()
	var can_play := my_turn and game.phase == "play"
	_clear(meld_flow)
	for m in game.melds:
		var mv := MeldView.new()
		mv.setup(m, _name(m["owner"]), can_play and not sel_cards.is_empty() and Cards.can_lay_off(m, sel_cards, game.trump_rank), game.trump_rank)
		mv.tapped.connect(_lay_off_on)
		meld_flow.add_child(mv)

	# current player
	me_name.text = me.name + _flags(me)
	_clear(me_hp)
	me_hp.add_child(_hp_bar(me))
	var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank)
	deadwood_label.text = "DEADWOOD %d" % best["points"]

	_clear(items_row)
	if me.items.is_empty():
		items_row.add_child(_tag("NO ITEMS", 20, Palette.DIM))
	for item in me.items:
		var iv := CardView.new()
		iv.setup(item, ITEM_SIZE, 0.0)
		iv.selected = item["id"] == selected_item
		iv.locked = my_turn and game.item_blocker(seat, item["id"]) != ""
		iv.tapped.connect(_toggle_item)
		items_row.add_child(iv)

	_clear(hand_row)
	var hand: Array = me.hand.duplicate()
	if sort_by_rank:
		Cards.sort_by_rank(hand)
	else:
		Cards.sort_by_suit(hand)
	# hints: gold outline = makes a meld in your hand, gold underline = fits
	# a meld already on the table
	var meld_ids := {}
	var lay_ids := {}
	for meld_cards in best["melds"]:
		for c in meld_cards:
			meld_ids[c["id"]] = true
	for c in best["deadwood"]:
		for m in game.melds:
			if Cards.can_lay_off(m, [c], game.trump_rank):
				lay_ids[c["id"]] = true
	var avail := get_viewport_rect().size.x - 32.0
	var n := hand.size()
	var sep := 6
	if n > 1:
		sep = mini(6, int((avail - n * CARD_SIZE.x) / (n - 1)))
	hand_row.add_theme_constant_override("separation", sep)
	for c in hand:
		var cv := CardView.new()
		cv.setup(c, CARD_SIZE, LIFT)
		cv.selected = selected.has(c["id"])
		cv.hint = hints and meld_ids.has(c["id"])
		cv.lay_hint = hints and lay_ids.has(c["id"])
		cv.trump = game.is_trump(c)
		cv.glow = c["id"] == lit_card
		cv.locked = can_play and not game.can_discard(seat, c["id"])
		cv.tapped.connect(_toggle_card)
		hand_row.add_child(cv)

	# buttons
	var valid_meld := can_play and sel_cards.size() >= 3 and Cards.meld_type(sel_cards, game.trump_rank) != ""
	meld_btn.disabled = not valid_meld
	use_btn.disabled = not (my_turn and selected_item != "" and game.item_blocker(seat, selected_item) == "")
	discard_btn.disabled = not (can_play and sel_cards.size() == 1 and game.can_discard(seat, sel_cards[0]["id"]))
	sort_btn.text = "SORT: RANK" if sort_by_rank else "SORT: SUIT"
	hint_btn.text = "HINTS: ON" if hints else "HINTS: OFF"

	status_label.add_theme_color_override("font_color", Palette.PINK if message != "" else Palette.AMBER)
	status_label.text = _status_text(sel_cards, valid_meld)

	# tell the player when they can go out, and shout when it's rummy
	var out: Dictionary = game.go_out_check(seat)
	go_out_label.visible = hints and out["can"]
	if out["rummy"]:
		go_out_label.text = "RUMMY IS ON! GO OUT NOW FOR DOUBLE POINTS"
	else:
		go_out_label.text = "YOU CAN GO OUT THIS TURN"


## "ACES", "SEVENS", "KINGS"...
static func trump_name(rank: int) -> String:
	const NAMES := ["", "ACES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "SEVENS", "EIGHTS", "NINES", "TENS", "JACKS", "QUEENS", "KINGS"]
	return NAMES[rank] if rank >= 1 and rank <= 13 else ""


func _status_text(sel_cards: Array, valid_meld: bool) -> String:
	if message != "":
		return message.to_upper()
	if game.phase != "draw" and game.phase != "play":
		return "ROUND OVER"
	var seat := game.turn
	if selected_item != "":
		var item := game.find_item(seat, selected_item)
		if not item.is_empty():
			var def := Items.def(item["item"])
			var blocker := game.item_blocker(seat, selected_item)
			return "%s: %s%s" % [str(def["name"]).to_upper(), def["text"], " (%s)" % blocker if blocker != "" else ""]
	if game.phase == "draw":
		return "%s, DRAW: TAP THE STOCK OR THE DISCARD PILE" % _name(seat)
	if sel_cards.is_empty():
		return "MELD, LAY OFF, USE ITEMS, THEN DISCARD 1 CARD"
	if valid_meld:
		return "VALID MELD. PRESS MELD"
	for m in game.melds:
		if Cards.can_lay_off(m, sel_cards, game.trump_rank):
			return "TAP A GLOWING MELD TO LAY OFF"
	if sel_cards.size() == 1:
		return "PRESS DISCARD TO END YOUR TURN"
	return "NOT A VALID MELD"


func _opponent_row(p) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag := "D " if p.seat == game.dealer else "  "
	var name_label := _label(tag + p.name + _flags(p), 26, Palette.INK if p.alive else Palette.DIM)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.clip_text = true
	row.add_child(name_label)
	if not p.alive:
		row.add_child(_tag("OUT", 24, Palette.RED))
		return row
	row.add_child(_hp_bar(p, Vector2(20, 12)))
	var counts := _label("%d CARDS · %d ITEMS" % [p.hand.size(), p.items.size()], 22, Palette.DIM)
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counts.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(counts)
	return row


func _selected_cards() -> Array:
	var out := []
	if game == null:
		return out
	for c in game.current().hand:
		if selected.has(c["id"]):
			out.append(c)
	return out


# ================================================================ actions

func _draw_stock() -> void:
	if game.phase != "draw":
		return
	var res := game.draw_stock(game.turn)
	if not _handle(res):
		return
	if res.get("round_over", false):
		_after_action()
		return
	var card: Dictionary = res["card"]
	_refresh()
	if res["item"]:
		var text := "%s It's yours. Now draw again: the stock or the discard pile." % Items.def(card["item"])["text"]
		_show_reveal("YOU DREW AN ITEM", card, text, _after_action)
	else:
		lit_card = card["id"]
		_show_reveal("YOU DREW", card, Cards.card_name(card) + (" (TRUMP)" if game.is_trump(card) else ""), _after_action)


func _draw_discard() -> void:
	if game.phase != "draw" or game.discard_pile.is_empty():
		return
	var res := game.draw_discard(game.turn)
	if _handle(res):
		lit_card = res["card"]["id"]
		_after_action()


func _toggle_card(id: String) -> void:
	if game.phase == "draw":
		message = "Draw a card first. (You can use an item before drawing.)"
	elif game.phase == "play":
		if selected.has(id):
			selected.erase(id)
		else:
			selected.append(id)
		message = ""
	_refresh()


func _toggle_item(id: String) -> void:
	if game.phase != "draw" and game.phase != "play":
		return
	selected_item = "" if selected_item == id else id
	message = ""
	_refresh()


func _meld_selected() -> void:
	if _handle(game.meld(game.turn, selected)):
		_after_action()


func _lay_off_on(meld_id: String) -> void:
	if game.phase != "play" or selected.is_empty():
		return
	if _handle(game.lay_off(game.turn, selected, meld_id)):
		_after_action()


func _discard_selected() -> void:
	if selected.size() != 1:
		return
	if _handle(game.discard(game.turn, selected[0])):
		_after_action()


func _use_selected_item() -> void:
	if selected_item == "":
		return
	var item := game.find_item(game.turn, selected_item)
	if item.is_empty():
		return
	if Items.needs_target(item["item"]):
		_show_target_picker(item)
	else:
		_use_item(item, -1)


func _use_item(item: Dictionary, target: int) -> void:
	var seat := game.turn
	var res := game.use_item(seat, item["id"], target)
	if not res["ok"]:
		message = res["error"]
		_refresh()
		return
	selected_item = ""
	message = ""
	var shown: Dictionary = res.get("reveal", {})
	var text := str(res["text"]) + "."
	match item["item"]:
		"magnifier":
			text = "Top of the stock:"
		"phone":
			text = "%s is holding:" % _name(target)
		"adrenaline":
			text = "You stole:"
	if shown.is_empty():
		shown = item
	_refresh()
	_show_reveal("%s USES %s" % [_name(seat), str(Items.def(item["item"])["name"]).to_upper()], shown, text, _after_action)


func _toggle_sort() -> void:
	sort_by_rank = not sort_by_rank
	_refresh()


func _toggle_hints() -> void:
	hints = not hints
	_refresh()


# ================================================================ overlays

## Opens a full-screen overlay. Returns the content box; add buttons with
## _overlay_buttons. Scrolls when the content is long.
func _open_overlay(opacity: float = 0.94, scroll: bool = false) -> VBoxContainer:
	_close_overlay()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, opacity)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_layer.add_child(_full(bg))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 32)
	bg.add_child(_full(margin))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	if scroll:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		margin.add_child(sc)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(box)
	else:
		var center := CenterContainer.new()
		margin.add_child(center)
		box.custom_minimum_size = Vector2(minf(660.0, get_viewport_rect().size.x - 56.0), 0)
		center.add_child(box)
	return box


func _close_overlay() -> void:
	if overlay_layer != null:
		_clear(overlay_layer)


func _closing(then: Callable) -> Callable:
	return func() -> void:
		_close_overlay()
		if then.is_valid():
			then.call()


func _title(text: String, color: Color = Palette.INK) -> Label:
	return _label(text, 46, color, true)


func _show_pass_screen() -> void:
	var seat := game.turn
	var box := _open_overlay(1.0)
	box.add_child(_label("PASS THE PHONE TO", 28, Palette.DIM, true))
	box.add_child(_title(_name(seat), Palette.AMBER))
	var hp_row := _hp_bar(game.players[seat])
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hp_row)
	if game.trump_rank > 0:
		box.add_child(_label("TRUMP THIS ROUND: %s" % trump_name(game.trump_rank), 26, Palette.GOLD, true))
	var start: int = seen_upto.get(seat, 0)
	var news := log_lines.slice(maxi(start, log_lines.size() - 8))
	if not news.is_empty():
		box.add_child(_label("SINCE YOUR LAST TURN", 22, Palette.DIM, true))
		for line in news:
			box.add_child(_label(line, 22, Palette.INK, true))
	box.add_child(_button("I'M %s. SHOW MY CARDS" % _name(seat), _closing(_on_pass_ready), 30))


func _on_pass_ready() -> void:
	_mark_turn_seen()
	_refresh()


func _show_reveal(title: String, card: Dictionary, text: String, then: Callable) -> void:
	var box := _open_overlay()
	box.add_child(_title(title, Palette.AMBER))
	var holder := CenterContainer.new()
	var cv := CardView.new()
	cv.setup(card, Vector2(150, 216))
	cv.trump = not card.is_empty() and game.is_trump(card)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cv)
	box.add_child(_label(text, 28, Palette.INK, true))
	box.add_child(holder)
	box.add_child(_button("CONTINUE", _closing(then)))


func _show_target_picker(item: Dictionary) -> void:
	var def := Items.def(item["item"])
	var box := _open_overlay()
	box.add_child(_title(str(def["name"]).to_upper(), Palette.PURPLE.lightened(0.3)))
	box.add_child(_label(def["text"], 26, Palette.INK, true))
	box.add_child(_label("WHO?", 26, Palette.DIM, true))
	for target in game.item_targets(game.turn, item["item"]):
		box.add_child(_button(_name(target), _closing(_use_item.bind(item, target))))
	box.add_child(_button("CANCEL", _closing(_refresh)))


func _show_round_result() -> void:
	var r := game.last_result
	var box := _open_overlay(0.94, true)
	var w: int = r["winner"]
	if w < 0:
		box.add_child(_title("DEAD DECK"))
		box.add_child(_label("The stock ran out. Nobody gets the shotgun.", 26, Palette.INK, true))
	else:
		if r["rummy"]:
			box.add_child(_label("RUMMY!", 96, Palette.GOLD, true))
		box.add_child(_title("%s GOES OUT" % _name(w), Palette.AMBER))
		if r["rummy"]:
			box.add_child(_label("Out in a single turn. Points doubled.", 26, Palette.GOLD, true))
		box.add_child(_label("%d points = %d shell%s in the shotgun." % [r["points"], r["shells"], "" if r["shells"] == 1 else "s"], 28, Palette.INK, true))
		box.add_child(_label("(1 shell, +1 for every 10 points, max 3)", 20, Palette.DIM, true))
	for h in r["hands"]:
		if h["seat"] == w:
			continue
		box.add_child(_label("%s was left holding %d:" % [h["name"], h["points"]], 24, Palette.INK))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		for c in h["cards"]:
			var cv := CardView.new()
			cv.setup(c, Vector2(52, 76))
			cv.trump = game.is_trump(c)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flow.add_child(cv)
		box.add_child(flow)
	if game.gun != null:
		var b := _button("%s, PICK UP THE SHOTGUN" % _name(w), _closing(_show_gun))
		Palette.accent(b, Palette.RED)
		box.add_child(b)
	else:
		box.add_child(_button("NEXT ROUND", _closing(_next_round)))


func _next_round() -> void:
	game.start_round()
	_after_action()


func _show_gun(last_text: String = "") -> void:
	var holder := -1
	var shells := 0
	var total: int = game.last_result.get("shells", 0)
	if game.gun != null:
		holder = game.gun["holder"]
		shells = game.gun["shells"]
	var box := _open_overlay(0.97)
	var shooter: int = game.last_result["winner"]
	box.add_child(_title("%s HAS THE SHOTGUN" % _name(shooter), Palette.RED))
	var gun_holder := CenterContainer.new()
	var gun := ShotgunView.new()
	gun_holder.add_child(gun)
	box.add_child(gun_holder)
	var shell_row := HBoxContainer.new()
	shell_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shell_row.add_theme_constant_override("separation", 10)
	for i in range(total):
		var sh := ColorRect.new()
		sh.custom_minimum_size = Vector2(18, 40)
		sh.color = Palette.RED if i < shells else Palette.HP_EMPTY
		shell_row.add_child(sh)
	box.add_child(shell_row)
	if last_text != "":
		box.add_child(_label(last_text, 34, Palette.PINK, true))

	if holder >= 0:
		var note := "Choose who to shoot."
		if game.players[holder].sawed:
			note = "Sawn-off barrel: the next shell hits for 2. Choose who to shoot."
		box.add_child(_label(note, 26, Palette.INK, true))
		for p in game.others(holder):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var b := _button("SHOOT %s" % p.name, _fire.bind(holder, p.seat))
			Palette.accent(b, Palette.RED)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
			var hp := _hp_bar(p, Vector2(20, 18))
			hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(hp)
			box.add_child(row)
	else:
		for p in game.players:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 12)
			row.add_child(_tag(p.name, 26, Palette.INK if p.alive else Palette.DIM))
			if p.alive:
				row.add_child(_hp_bar(p, Vector2(20, 14)))
			else:
				row.add_child(_tag("OUT", 26, Palette.RED))
			box.add_child(row)
		if game.phase == "match_over":
			box.add_child(_button("CONTINUE", _closing(_show_match_end)))
		else:
			box.add_child(_label("The shotgun goes back on the wall.", 24, Palette.DIM, true))
			box.add_child(_button("NEXT ROUND", _closing(_next_round)))
	if last_text != "":
		gun.call_deferred("kick")


func _fire(shooter: int, target: int) -> void:
	var res := game.shoot(shooter, target)
	if not res["ok"]:
		return
	_flash(Color.WHITE)
	_shake()
	var text := "BANG. %s takes %d." % [_name(target), res["damage"]]
	if not game.players[target].alive:
		text = "BANG. %s is out." % _name(target)
	_refresh()
	_show_gun(text)


func _show_match_end() -> void:
	var box := _open_overlay(0.97, true)
	if game.winner >= 0:
		box.add_child(_title("%s WALKS OUT" % _name(game.winner), Palette.AMBER))
		box.add_child(_label("Everyone else signed the waiver for nothing.", 26, Palette.INK, true))
	else:
		box.add_child(_title("NOBODY WALKS OUT", Palette.RED))
	box.add_child(_label("Rounds played: %d" % game.round_num, 24, Palette.DIM, true))
	for p in game.players:
		box.add_child(_label("%s: %d rounds won, %d points%s" % [p.name, p.rounds_won, p.score, "" if p.alive else " (out)"], 24, Palette.INK, true))
	box.add_child(_button("PLAY AGAIN", _closing(start_match)))
	box.add_child(_button("NEW PLAYERS", _closing(show_setup)))


func _show_rules() -> void:
	var box := _open_overlay(0.96, true)
	box.add_child(_title("RULES"))
	var lines := [
		"THE TABLE. 2 to 6 players pass one phone around. One player deals each round and the player to their left goes first. Next round the deal moves one seat to the right, so whoever dealt goes first.",
		"THE DEAL. Everyone gets 7 playing cards and 2 item cards. The other item cards are shuffled into the stock, so a draw from it can give you an item instead of a playing card.",
		"YOUR TURN. Draw 1 card from the stock or the top of the discard pile. If you draw an item, keep it and draw again until you get a playing card. Meld, lay off and use items as much as you like, then discard 1 card to end your turn. You can't discard the card you just took from the discard pile.",
		"MELDS. A set is 3 or 4 cards of the same rank (7 7 7). A run is 3 or more cards in a row of the same suit (4 5 6 of hearts). Aces are low: A-2-3 counts, Q-K-A doesn't.",
		"LAYING OFF. Add cards to any meld on the table, yours or anyone's: select them, then tap the glowing meld.",
		"GOING OUT. Empty your hand of playing cards to win the round (items don't count). You score the cards everyone else is still holding: A = 1, 2-10 = face value, J/Q/K = 10. Going out in a single turn without having melded before is RUMMY and doubles it.",
		"THE SHOTGUN. The winner gets the shotgun with 1 shell, +1 for every 10 points scored (max 3), and picks who to shoot with each shell. Each shell takes 1 health. Everyone starts with 4. Health carries over between rounds. Hit 0 and you're out. Last one standing walks out.",
		"TRUMP CARDS. Each round one rank is trump: aces in round 1, twos in round 2, and so on up to kings in round 13, then back to aces. A trump card (gold star) can stand in for any card of any suit in any set or run: in round 1, 2 3 A 5 of clubs is a run.",
		"HINTS. A gold outline means the card makes a meld in your hand. A gold underline means it fits a meld on the table. A gold banner tells you when you can go out, and when it would be RUMMY. DEADWOOD is what you'd be caught holding if someone went out now.",
	]
	for line in lines:
		box.add_child(_label(line, 24, Palette.INK))
	box.add_child(_label("ITEMS (use as many as you like, any time in your turn)", 28, Palette.PURPLE.lightened(0.3)))
	for id in Items.DEFS:
		var d: Dictionary = Items.DEFS[id]
		box.add_child(_label("%s %s ×%d: %s" % [d["icon"], d["name"], d["copies"], d["text"]], 24, Palette.INK))
	box.add_child(_button("BACK", _closing(_refresh)))


func _show_log() -> void:
	var box := _open_overlay(0.96, true)
	box.add_child(_title("LOG"))
	for i in range(log_lines.size() - 1, maxi(-1, log_lines.size() - 120), -1):
		box.add_child(_label(log_lines[i], 22, Palette.INK))
	box.add_child(_button("BACK", _closing(_refresh)))


func _show_menu() -> void:
	var box := _open_overlay()
	box.add_child(_title("PAUSED"))
	box.add_child(_button("RESUME", _closing(_refresh)))
	box.add_child(_button("RESTART MATCH", _closing(start_match)))
	box.add_child(_button("NEW PLAYERS", _closing(show_setup)))
