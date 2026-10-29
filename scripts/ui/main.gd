extends Control
## Shotgun Rummy UI (phone first).
##
## Screens are built in code: main menu -> lobby (same Wi-Fi) or pass-and-play
## setup -> table, with overlays on top for "pass the phone", item reveals,
## round results, the shotgun, rules and the log.
##
## In pass-and-play the table shows whoever's turn it is. Online, each phone
## shows its own seat and actions go to the host's game (see session.gd).

const Game = preload("res://scripts/core/game.gd")
const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const World3DScene = preload("res://scripts/three/world3d.gd")
const Session = preload("res://scripts/net/session.gd")

const SETTINGS_PATH := "user://settings.cfg"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6

var game: Game
var world: World3DScene
var session: Session
var profile_name := ""
var player_names: Array = ["PLAYER 1", "PLAYER 2"]
var hide_hands := true
var menu_message := ""
var _pending_cb := Callable() # waiting on the host to answer this phone's action
var _overlay_kind := ""
var _last_shot_text := ""
var _hand_hidden := false # pass-and-play: your cards stay face down until you take the phone
var _waiting_for_deal := false
var _drawing_again := false # Double Down: first of the two cards is drawn
var _ip_edit: LineEdit
var _name_edit: LineEdit

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
var hud: Control
var round_label: Label
var trump_label: Label
var go_out_label: Label
var me_name: Label
var me_hp: HBoxContainer
var deadwood_label: Label
var status_label: Label
var meld_btn: Button
var use_btn: Button
var discard_btn: Button
var sort_btn: Button
var hint_btn: Button


func _ready() -> void:
	theme = Palette.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = World3DScene.new()
	add_child(world)
	world.deal_finished.connect(_on_deal_finished)

	screen = _full(Control.new())
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.roster_changed.connect(_on_roster_changed)
	session.lobbies_changed.connect(_on_lobbies_changed)
	session.match_started.connect(_on_online_match_started)
	session.updated.connect(_on_net_update)
	session.ended.connect(_on_session_ended)

	_load_settings()
	get_tree().root.size_changed.connect(_fit_window)
	_fit_window()
	show_menu()


## Phones in portrait lay out at 720x1280; wide screens (PC, a phone on its
## side) at 1280x720 so buttons and text stay a sensible size.
func _fit_window() -> void:
	var win := get_tree().root
	var s := win.size
	var want := Vector2i(1280, 720) if s.x > s.y else Vector2i(720, 1280)
	if win.content_scale_size != want:
		win.content_scale_size = want


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
	if p.ultimatum:
		f += " 🔫"
	if p.extra_draws > 0:
		f += " 🎲"
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
	world.shake()
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
	profile_name = cfg.get_value("profile", "name", "")


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "names", player_names)
	cfg.set_value("setup", "hide_hands", hide_hands)
	cfg.set_value("profile", "name", profile_name)
	cfg.save(SETTINGS_PATH)


# ================================================================ main menu

func _paper(width: float = 620.0) -> VBoxContainer:
	_close_overlay()
	_clear(screen)
	var center := CenterContainer.new()
	screen.add_child(_full(center))
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", Palette.box(Palette.WAIVER, Color(0, 0, 0, 0), 0, 2, 28))
	paper.custom_minimum_size = Vector2(width, 0)
	paper.rotation_degrees = -1.0
	center.add_child(paper)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	paper.add_child(box)
	return box


func _paper_button(text: String, on_press: Callable, font_size: int = 32) -> Button:
	var b := _button(text, on_press, font_size)
	b.add_theme_stylebox_override("normal", Palette.box(Palette.CARD_INK, Palette.CARD_INK, 2, 2, 10))
	return b


func show_menu() -> void:
	session.leave()
	session.stop_scan()
	game = null
	round_label = null
	world.set_menu_mode(true)
	var box := _paper()
	box.add_child(_label("SHOTGUN\nRUMMY", 76, Color(0.36, 0.06, 0.05), true))
	if menu_message != "":
		box.add_child(_label(menu_message, 24, Palette.CARD_RED, true))
		menu_message = ""
	var row := HBoxContainer.new()
	row.add_child(_tag("NAME", 30, Palette.CARD_INK))
	_name_edit = LineEdit.new()
	_name_edit.text = profile_name
	_name_edit.placeholder_text = "SIGN HERE"
	_name_edit.max_length = 10
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)
	box.add_child(row)
	var character := _paper_button("CHARACTER (COMING SOON)", _noop, 28)
	character.disabled = true
	box.add_child(character)
	box.add_child(_paper_button("HOST A LOBBY", _on_host_pressed))
	box.add_child(_paper_button("JOIN A LOBBY", _on_join_pressed))
	box.add_child(_paper_button("PASS & PLAY (ONE PHONE)", _on_pass_and_play_pressed, 28))
	box.add_child(_label("Lobbies work between phones on the same Wi-Fi.", 20, Palette.CARD_INK, true))


func _noop() -> void:
	pass


## Reads the name box; returns "" (and complains) if it's empty.
func _take_name() -> String:
	var n := _name_edit.text.strip_edges().to_upper().left(10)
	if n == "":
		menu_message = "Sign your name first."
		show_menu()
		return ""
	profile_name = n
	_save_settings()
	return n


func _on_pass_and_play_pressed() -> void:
	var n := _name_edit.text.strip_edges().to_upper()
	if n != "":
		profile_name = n.left(10)
		player_names[0] = profile_name
		_save_settings()
	show_setup()


func _on_host_pressed() -> void:
	var n := _take_name()
	if n == "":
		return
	var err := session.host(n)
	if err != "":
		menu_message = err
		show_menu()
		return
	show_lobby()


func _on_join_pressed() -> void:
	if _take_name() == "":
		return
	session.start_scan()
	show_join()


func show_join() -> void:
	var box := _paper()
	box.add_child(_label("JOIN A LOBBY", 52, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label("LOBBIES ON THIS WI-FI", 24, Palette.CARD_INK, true))
	if session.lobbies.is_empty():
		box.add_child(_label("Looking... (the host needs to be on the HOST A LOBBY screen)", 22, Palette.CARD_INK, true))
	for ip in session.lobbies:
		var l: Dictionary = session.lobbies[ip]
		box.add_child(_paper_button("%s  (%d/%d)" % [l["name"], l["players"], l["max"]], _join_ip.bind(ip), 28))
	box.add_child(_label("OR JOIN BY IP (shown on the host's screen)", 22, Palette.CARD_INK, true))
	var row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	row.add_child(_paper_button("JOIN", _join_typed_ip, 28))
	box.add_child(row)
	box.add_child(_paper_button("BACK", show_menu, 28))


func _on_lobbies_changed() -> void:
	if session.mode == "offline" and _ip_edit != null and is_instance_valid(_ip_edit) and _ip_edit.is_inside_tree():
		var typed := _ip_edit.text
		var had_focus := _ip_edit.has_focus()
		show_join()
		_ip_edit.text = typed
		if had_focus:
			_ip_edit.grab_focus()


func _join_typed_ip() -> void:
	_join_ip(_ip_edit.text)


func _join_ip(ip: String) -> void:
	if ip.strip_edges() == "":
		return
	var err := session.join(ip, profile_name)
	if err != "":
		menu_message = err
		show_menu()
		return
	var box := _paper()
	box.add_child(_label("CONNECTING TO %s..." % ip.strip_edges(), 30, Palette.CARD_INK, true))
	box.add_child(_paper_button("CANCEL", show_menu, 28))


func show_lobby() -> void:
	var box := _paper()
	if session.is_host():
		box.add_child(_label("%s'S TABLE" % profile_name, 48, Color(0.36, 0.06, 0.05), true))
		box.add_child(_label("Friends on the same Wi-Fi: tap JOIN A LOBBY.", 22, Palette.CARD_INK, true))
		var ips := Session.local_addresses()
		if not ips.is_empty():
			box.add_child(_label("Or join by IP: %s" % ", ".join(ips), 24, Palette.CARD_INK, true))
	else:
		box.add_child(_label("IN THE LOBBY", 48, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label("PLAYERS (%d/%d)" % [session.names.size(), Session.MAX_PLAYERS], 26, Palette.CARD_INK))
	for i in range(session.names.size()):
		var who: String = session.names[i]
		box.add_child(_label("%d. %s%s" % [i + 1, who, " (HOST)" if i == 0 else ""], 30, Palette.CARD_INK))
	if session.is_host():
		var start := _paper_button("START THE GAME", session.start_match)
		start.disabled = session.names.size() < 2
		box.add_child(start)
		if session.names.size() < 2:
			box.add_child(_label("Waiting for at least one more player...", 22, Palette.CARD_INK, true))
	else:
		box.add_child(_label("Waiting for the host to start...", 24, Palette.CARD_INK, true))
	box.add_child(_paper_button("LEAVE", show_menu, 28))


func _on_roster_changed() -> void:
	if not session.in_match:
		show_lobby()


func _on_session_ended(reason: String) -> void:
	menu_message = reason
	show_menu()


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
	box.add_child(_paper_button("BACK", show_menu, 28))


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
	session.leave()
	game = Game.new()
	game.setup(player_names)
	game.event.connect(_on_game_event)
	_reset_match_view()
	_build_table()
	game.start_round()
	_after_action()


func _reset_match_view() -> void:
	world.reset_rounds()
	_hand_hidden = false
	log_lines = []
	seen_upto = {}
	turn_counter = 0
	shown_turn = -1
	shown_result_round = 0
	selected = []
	selected_item = ""
	message = ""
	_pending_cb = Callable()


func _online() -> bool:
	return session != null and session.is_online()


## The seat this screen belongs to: whoever's turn it is in pass-and-play,
## or this phone's own seat online.
func _me() -> int:
	return session.my_seat if _online() else game.turn


func _my_turn() -> bool:
	return game.is_turn_of(_me())


func _on_online_match_started() -> void:
	game = session.game
	_reset_match_view()
	_build_table()


## The host's game changed. Replay the public events for the log and effects,
## then either finish this phone's own action or just redraw.
func _on_net_update(events: Array, result: Dictionary) -> void:
	if game == null or round_label == null:
		return
	for e in events:
		_on_game_event(e[0], e[1])
	if not result.is_empty() and _pending_cb.is_valid():
		var cb := _pending_cb
		_pending_cb = Callable()
		cb.call(result)
	else:
		_after_action()


## Does `action` for this screen's player: straight on the game for
## pass-and-play, or as a request to the host online. `then` gets the result.
func _act(action: String, args: Array, then: Callable) -> void:
	if _online():
		if _pending_cb.is_valid():
			return # still waiting on the last one
		_pending_cb = then
		session.act(action, args)
		return
	var seat := game.turn
	if action == "shoot" and game.gun != null:
		seat = game.gun["holder"]
	then.call(Session.perform(game, seat, action, args, true))


func _ignore_result(_res: Dictionary) -> void:
	_after_action()


func _on_game_event(kind: String, d: Dictionary) -> void:
	match kind:
		"roulette":
			var who := _name(d["seat"])
			if d["hit"]:
				_log("%s spins the revolver... BANG. -%d health." % [who, d["damage"]])
				world.announce("BANG!\n%s LOSES %d" % [who, d["damage"]])
				_flash(Palette.RED)
				_shake()
			else:
				_log("%s spins the revolver... click. They live." % who)
				world.announce("CLICK.\n%s LIVES" % who)
		"trump_changed":
			var to_name := trump_name(int(d["to"]))
			_log("The trump changes: %s are wild now." % to_name.to_lower().capitalize())
			world.announce("TRUMP CHANGES\nTO %s" % to_name)
		"round_start":
			if d["round"] == 1 and _online():
				_reset_match_view()
				_close_overlay()
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
		"swap":
			_log("%s swaps %s in for the trump %s and melds %s." % [_name(d["seat"]), Cards.card_name(d["natural"]), Cards.card_name(d["trump"]), Cards.cards_text(d["new_meld"]["cards"])])
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
			if _online():
				# every phone feels it; the target's phone most of all
				world.fire(d["shooter"], d["target"])
				if d["target"] == _me():
					_flash(Palette.RED)
					_shake()
				else:
					_flash(Color.WHITE)
				_last_shot_text = "BANG. %s shoots %s." % [_name(d["shooter"]), _name(d["target"])]
		"match_end":
			if d["winner"] >= 0:
				_log("%s WALKS OUT." % _name(d["winner"]))


func _log(text: String) -> void:
	log_lines.append(text)


## Decides what to show after anything happens.
func _after_action() -> void:
	if game == null:
		return
	if _online():
		_after_action_online()
		return
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
				_drawing_again = false
				if hide_hands:
					_hand_hidden = true
					_refresh()
					_pass_after_deal()
					return
				_mark_turn_seen()
	_refresh()


func _after_action_online() -> void:
	# don't yank away rules, the log, a reveal or a target picker; they
	# re-check when closed
	var busy_overlay := _overlay_kind in ["rules", "log", "menu", "reveal", "target"]
	match game.phase:
		"draw", "play":
			if _overlay_kind in ["result", "gun", "match"]:
				_close_overlay()
			if shown_turn != turn_counter:
				shown_turn = turn_counter
				selected = []
				selected_item = ""
				lit_card = ""
				message = ""
				_drawing_again = false
				if _my_turn():
					Input.vibrate_handheld(60)
		"shoot", "round_over":
			if busy_overlay:
				pass
			elif shown_result_round != game.round_num:
				shown_result_round = game.round_num
				_refresh()
				_show_round_result()
				return
			elif _overlay_kind == "gun":
				_refresh()
				_show_gun(_last_shot_text)
				return
		"match_over":
			if not busy_overlay:
				_refresh()
				if _overlay_kind == "gun":
					_show_gun(_last_shot_text)
				elif _overlay_kind != "match":
					_show_match_end()
				return
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
	world.set_menu_mode(false)

	# taps that don't land on a button go to the 3D table
	var catcher := _full(Control.new())
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_table_input)
	screen.add_child(catcher)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 20)
	screen.add_child(_full(margin))
	hud = margin
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	# top bar
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	status_label = _label("", 26, Palette.AMBER, true)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 8)
	status_label.custom_minimum_size = Vector2(0, 62)
	col.add_child(status_label)

	go_out_label = _label("", 30, Palette.GOLD, true)
	go_out_label.add_theme_color_override("font_outline_color", Color.BLACK)
	go_out_label.add_theme_constant_override("outline_size", 8)
	go_out_label.visible = false
	col.add_child(go_out_label)

	# the 3D table, your items and your hand show through here
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)

	var me_row := HBoxContainer.new()
	me_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_row.add_theme_constant_override("separation", 12)
	me_name = _label("", 30)
	me_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	me_row.add_child(me_name)
	me_hp = HBoxContainer.new()
	me_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_row.add_child(me_hp)
	deadwood_label = _label("", 22, Palette.DIM)
	deadwood_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deadwood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	me_row.add_child(deadwood_label)
	col.add_child(me_row)

	var buttons := HBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	minor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minor.alignment = BoxContainer.ALIGNMENT_CENTER
	minor.add_theme_constant_override("separation", 16)
	sort_btn = _button("SORT: SUIT", _toggle_sort, 22)
	hint_btn = _button("HINTS: ON", _toggle_hints, 22)
	for b in [sort_btn, hint_btn]:
		b.custom_minimum_size = Vector2(200, 46)
		minor.add_child(b)
	col.add_child(minor)


## A tap on the table: find the card under it in 3D.
func _on_table_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if game == null or overlay_layer.get_child_count() > 0 or world.dealing:
		return
	var hit: Dictionary = world.pick(event.position)
	match hit.get("kind", ""):
		"hand":
			_toggle_card(hit["id"])
		"item":
			_toggle_item(hit["id"])
		"stock":
			_draw_stock()
		"discard":
			_draw_discard()
		"meld":
			if selected.is_empty():
				message = "Select cards from your hand first, then tap the meld."
				_refresh()
			else:
				_lay_off_on(hit["id"])


func _refresh() -> void:
	if game == null or round_label == null:
		return
	var seat := _me()
	var me = game.players[seat]
	var my_turn := _my_turn()

	round_label.text = "ROUND %d · %s DEALS" % [game.round_num, _name(game.dealer)]
	trump_label.text = "TRUMP: %s  " % trump_name(game.trump_rank) if game.trump_rank > 0 else ""

	var can_draw := my_turn and game.phase == "draw"
	var sel_cards := _selected_cards()
	var can_play := my_turn and game.phase == "play"

	# current player
	me_name.text = me.name + _flags(me)
	_clear(me_hp)
	me_hp.add_child(_hp_bar(me))
	var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank)
	deadwood_label.text = "DEADWOOD %d" % best["points"]

	var hand: Array = me.hand.duplicate()
	if sort_by_rank:
		Cards.sort_by_rank(hand)
	else:
		Cards.sort_by_suit(hand)
	# hints: gold outline = makes a meld in your hand, gold + = fits a meld
	# already on the table
	var meld_ids := {}
	var lay_ids := {}
	if hints:
		for meld_cards in best["melds"]:
			for c in meld_cards:
				meld_ids[c["id"]] = true
		for c in best["deadwood"]:
			for m in game.melds:
				if Cards.can_lay_off(m, [c], game.trump_rank):
					lay_ids[c["id"]] = true
	var targets := {}
	if can_play and game.can_place(seat) and not sel_cards.is_empty():
		for m in game.melds:
			if Cards.can_lay_off(m, sel_cards, game.trump_rank) or not game.find_swap(seat, m["id"], selected).is_empty():
				targets[m["id"]] = true
	world.sync({
		"game": game, "viewer": seat, "hand": hand, "selected": selected, "selected_item": selected_item,
		"meld_hints": meld_ids, "lay_hints": lay_ids, "lit": lit_card, "can_draw": can_draw, "targets": targets,
		"hide_hand": _hand_hidden,
	})

	# buttons
	var valid_meld := can_play and game.can_place(seat) and sel_cards.size() >= 3 and Cards.meld_type(sel_cards, game.trump_rank) != ""
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
	var seat := _me()
	if world.dealing:
		return "SHUFFLING AND DEALING..."
	if not _my_turn():
		return "WAITING FOR %s..." % _name(game.turn)
	if selected_item != "":
		var item := game.find_item(seat, selected_item)
		if not item.is_empty():
			var def := Items.def(item["item"])
			var blocker := game.item_blocker(seat, selected_item)
			return "%s: %s%s" % [str(def["name"]).to_upper(), def["text"], " (%s)" % blocker if blocker != "" else ""]
	var first := not game.can_place(seat)
	var me = game.players[seat]
	if game.phase == "draw" and me.extra_draws > 0:
		return "DOUBLE DOWN: DRAW 2 CARDS THIS TURN"
	if game.phase == "draw" and _drawing_again:
		return "DOUBLE DOWN: DRAW 1 MORE CARD"
	if game.phase == "draw":
		if first:
			return "%s, YOUR FIRST TURN: DRAW, THEN DISCARD (NO MELDING YET)" % _name(seat)
		return "%s, DRAW: TAP THE STOCK OR THE DISCARD PILE" % _name(seat)
	if first:
		return "FIRST TURN: NO MELDING YET. DISCARD 1 CARD TO END YOUR TURN" if sel_cards.size() != 1 else "PRESS DISCARD TO END YOUR TURN"
	if sel_cards.is_empty() and me.ultimatum and not game.placed_this_turn:
		return "REVOLVER: PUT CARDS DOWN THIS TURN OR SPIN THE CYLINDER"
	if sel_cards.is_empty():
		return "MELD, LAY OFF, USE ITEMS, THEN DISCARD 1 CARD"
	if valid_meld:
		return "VALID MELD. PRESS MELD"
	for m in game.melds:
		if Cards.can_lay_off(m, sel_cards, game.trump_rank):
			return "TAP A GLOWING MELD TO LAY OFF"
	for m in game.melds:
		if not game.find_swap(seat, m["id"], selected).is_empty():
			return "TAP THE GLOWING MELD TO SWAP FOR ITS TRUMP AND MELD IT"
	if sel_cards.size() == 1:
		var blocked := game.discard_blocker(seat, sel_cards[0]["id"])
		return blocked.to_upper() if blocked != "" else "PRESS DISCARD TO END YOUR TURN"
	return "NOT A VALID MELD"


func _selected_cards() -> Array:
	var out := []
	if game == null:
		return out
	for c in game.players[_me()].hand:
		if selected.has(c["id"]):
			out.append(c)
	return out


# ================================================================ actions

func _draw_stock() -> void:
	if not _my_turn() or game.phase != "draw":
		return
	_act("draw_stock", [], _after_draw_stock)


func _after_draw_stock(res: Dictionary) -> void:
	if not _handle(res):
		return
	if res.get("round_over", false):
		_after_action()
		return
	var card: Dictionary = res["card"]
	_drawing_again = res.get("again", _drawing_again) # items don't use up a Double Down draw
	_refresh()
	if res["item"]:
		var text := "%s It's yours. Now draw again: the stock or the discard pile." % Items.def(card["item"])["text"]
		_show_reveal("YOU DREW AN ITEM", card, text, _after_action)
	else:
		lit_card = card["id"]
		_show_reveal("YOU DREW", card, Cards.card_name(card) + (" (TRUMP)" if game.is_trump(card) else ""), _after_action)


func _draw_discard() -> void:
	if not _my_turn() or game.phase != "draw" or game.discard_pile.is_empty():
		return
	_act("draw_discard", [], _after_draw_discard)


func _after_draw_discard(res: Dictionary) -> void:
	if _handle(res):
		_drawing_again = res.get("again", false)
		lit_card = res["card"]["id"]
		_after_action()


func _after_simple(res: Dictionary) -> void:
	if _handle(res):
		_after_action()


func _toggle_card(id: String) -> void:
	if not _my_turn():
		message = "It's %s's turn." % _name(game.turn)
	elif game.phase == "draw":
		message = "Draw a card first. (You can use an item before drawing.)"
	elif game.phase == "play":
		if selected.has(id):
			selected.erase(id)
		else:
			selected.append(id)
		message = ""
	_refresh()


func _toggle_item(id: String) -> void:
	if not _my_turn():
		message = "It's %s's turn." % _name(game.turn)
		_refresh()
		return
	selected_item = "" if selected_item == id else id
	message = ""
	_refresh()


func _meld_selected() -> void:
	if _my_turn():
		_act("meld", [selected.duplicate()], _after_simple)


func _lay_off_on(meld_id: String) -> void:
	if not _my_turn() or game.phase != "play" or selected.is_empty():
		return
	var m := game.find_meld(meld_id)
	if not m.is_empty() and not Cards.can_lay_off(m, _selected_cards(), game.trump_rank):
		var swap := game.find_swap(_me(), meld_id, selected)
		if not swap.is_empty():
			_act("swap", [meld_id, swap["natural"], swap["trump"], swap["rest"]], _after_simple)
			return
	_act("lay_off", [selected.duplicate(), meld_id], _after_simple)


func _discard_selected() -> void:
	if not _my_turn() or selected.size() != 1:
		return
	lit_card = ""
	_act("discard", [selected[0]], _after_simple)


func _use_selected_item() -> void:
	if selected_item == "" or not _my_turn():
		return
	var item := game.find_item(_me(), selected_item)
	if item.is_empty():
		return
	match Items.needs(item["item"]):
		"player":
			_show_target_picker(item)
		"meld_card", "hand_card":
			_show_card_picker(item)
		_:
			_use_item(item, -1)


func _use_item(item: Dictionary, target: int, choice: String = "") -> void:
	_act("use_item", [item["id"], target, choice], _after_use_item.bind(item, target))


func _after_use_item(res: Dictionary, item: Dictionary, target: int) -> void:
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
		"joker_paint":
			text = "Wild until your turn ends. Meld it to keep it wild."
		"sticky_fingers":
			text = str(res["text"]) + ". It's in your hand."
	if shown.is_empty():
		shown = item
	_refresh()
	_show_reveal("%s USES %s" % [_name(_me()), str(Items.def(item["item"])["name"]).to_upper()], shown, text, _after_action)


func _toggle_sort() -> void:
	sort_by_rank = not sort_by_rank
	_refresh()


func _toggle_hints() -> void:
	hints = not hints
	_refresh()


# ================================================================ overlays

## Opens a full-screen overlay. Returns the content box; add buttons with
## _overlay_buttons. Scrolls when the content is long.
func _open_overlay(opacity: float = 0.94, scroll: bool = false, kind: String = "", bottom: bool = false) -> VBoxContainer:
	_close_overlay()
	_overlay_kind = kind
	if hud != null and is_instance_valid(hud):
		hud.visible = not bottom
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
	elif bottom:
		# docked at the bottom so the 3D table stays in view
		box.alignment = BoxContainer.ALIGNMENT_END
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(box)
	else:
		var center := CenterContainer.new()
		margin.add_child(center)
		box.custom_minimum_size = Vector2(minf(660.0, get_viewport_rect().size.x - 56.0), 0)
		center.add_child(box)
	return box


func _close_overlay() -> void:
	if overlay_layer != null:
		_clear(overlay_layer)
	_overlay_kind = ""
	if hud != null and is_instance_valid(hud):
		hud.visible = true


func _closing(then: Callable) -> Callable:
	return func() -> void:
		_close_overlay()
		if then.is_valid():
			then.call()


func _title(text: String, color: Color = Palette.INK) -> Label:
	return _label(text, 46, color, true)


func _show_pass_screen() -> void:
	var seat := game.turn
	var box := _open_overlay(1.0, false, "pass")
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
	_hand_hidden = false
	_mark_turn_seen()
	_refresh()


## The pass screen waits until the cards have been dealt, so everyone sees
## the shuffle and the deal.
func _pass_after_deal() -> void:
	if _waiting_for_deal:
		return
	if world.dealing:
		_waiting_for_deal = true
		await world.deal_finished
		_waiting_for_deal = false
	if game != null and (game.phase == "draw" or game.phase == "play") and shown_turn != turn_counter:
		_show_pass_screen()


func _on_deal_finished() -> void:
	if game != null and round_label != null and overlay_layer.get_child_count() == 0:
		_refresh()


func _show_reveal(title: String, card: Dictionary, text: String, then: Callable) -> void:
	var box := _open_overlay(0.94, false, "reveal")
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
	var box := _open_overlay(0.94, false, "target")
	box.add_child(_title(str(def["name"]).to_upper(), Palette.PURPLE.lightened(0.3)))
	box.add_child(_label(def["text"], 26, Palette.INK, true))
	box.add_child(_label("WHO?", 26, Palette.DIM, true))
	for target in game.item_targets(_me(), item["item"]):
		box.add_child(_button(_name(target), _closing(_use_item.bind(item, target))))
	box.add_child(_button("CANCEL", _closing(_after_action)))


## Pick a card for Sticky Fingers (from a meld) or Joker Paint (from your hand).
func _show_card_picker(item: Dictionary) -> void:
	var def := Items.def(item["item"])
	var box := _open_overlay(0.94, true, "target")
	box.add_child(_title(str(def["name"]).to_upper(), Palette.PURPLE.lightened(0.3)))
	box.add_child(_label(def["text"], 26, Palette.INK, true))
	var choices: Array = game.item_choices(_me(), item["item"])
	if Items.needs(item["item"]) == "meld_card":
		box.add_child(_label("WHICH CARD?", 26, Palette.DIM, true))
		for m in game.melds:
			var mine := []
			for c in m["cards"]:
				if choices.has(c["id"]):
					mine.append(c)
			if mine.is_empty():
				continue
			var note := " (falls apart)" if m["cards"].size() <= 3 else ""
			box.add_child(_label("%s'S MELD: %s%s" % [_name(m["owner"]), Cards.cards_text(m["cards"]), note], 22, Palette.DIM))
			box.add_child(_card_buttons(mine, item))
	else:
		box.add_child(_label("WHICH CARD BECOMES A TRUMP?", 26, Palette.DIM, true))
		var cards := []
		for c in game.players[_me()].hand:
			if choices.has(c["id"]):
				cards.append(c)
		box.add_child(_card_buttons(cards, item))
	box.add_child(_button("CANCEL", _closing(_after_action)))


func _card_buttons(cards: Array, item: Dictionary) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for c in cards:
		var b := _button(Cards.card_name(c), _closing(_use_item.bind(item, -1, c["id"])))
		b.custom_minimum_size = Vector2(110, 64)
		flow.add_child(b)
	return flow


func _show_round_result() -> void:
	var r := game.last_result
	var box := _open_overlay(0.94, true, "result")
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
		var mine: bool = not _online() or int(game.gun["holder"]) == _me()
		var b := _button("%s, PICK UP THE SHOTGUN" % _name(w) if mine else "WATCH %s SHOOT" % _name(w), _show_gun)
		Palette.accent(b, Palette.RED)
		box.add_child(b)
	elif game.phase == "match_over":
		box.add_child(_button("CONTINUE", _show_match_end))
	else:
		_add_next_round(box)


## NEXT ROUND button, or a waiting note on phones that aren't the host.
func _add_next_round(box: VBoxContainer) -> void:
	if not _online() or session.is_host():
		box.add_child(_button("NEXT ROUND", _next_round))
	else:
		box.add_child(_label("Waiting for the host to deal the next round...", 24, Palette.DIM, true))
		box.add_child(_button("BACK TO THE TABLE", _closing(_refresh)))


func _next_round() -> void:
	_close_overlay()
	_act("next_round", [], _ignore_result)


func _show_gun(last_text: String = "") -> void:
	var holder := -1
	var shells := 0
	var total: int = game.last_result.get("shells", 0)
	if game.gun != null:
		holder = game.gun["holder"]
		shells = game.gun["shells"]
	var box := _open_overlay(0.2, false, "gun", true)
	var shooter: int = game.last_result["winner"]
	box.add_child(_title("%s HAS THE SHOTGUN" % _name(shooter), Palette.RED))
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

	if holder >= 0 and _online() and holder != _me():
		box.add_child(_label("Waiting for %s to pick a target..." % _name(holder), 26, Palette.INK, true))
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
	elif holder >= 0:
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
			box.add_child(_button("CONTINUE", _show_match_end))
		else:
			box.add_child(_label("The shotgun goes back on the wall.", 24, Palette.DIM, true))
			_add_next_round(box)


func _fire(shooter: int, target: int) -> void:
	_act("shoot", [target], _after_fire.bind(shooter, target))


func _after_fire(res: Dictionary, shooter: int, target: int) -> void:
	if not res["ok"]:
		return
	if not _online():
		world.fire(shooter, target)
		_flash(Color.WHITE)
		_shake()
	var text := "BANG. %s takes %d." % [_name(target), res["damage"]]
	if not game.players[target].alive:
		text = "BANG. %s is out." % _name(target)
	_last_shot_text = text
	_refresh()
	_show_gun(text)


func _show_match_end() -> void:
	var box := _open_overlay(0.97, true, "match")
	if game.winner >= 0:
		box.add_child(_title("%s WALKS OUT" % _name(game.winner), Palette.AMBER))
		box.add_child(_label("Everyone else signed the waiver for nothing.", 26, Palette.INK, true))
	else:
		box.add_child(_title("NOBODY WALKS OUT", Palette.RED))
	box.add_child(_label("Rounds played: %d" % game.round_num, 24, Palette.DIM, true))
	for p in game.players:
		box.add_child(_label("%s: %d rounds won, %d points%s" % [p.name, p.rounds_won, p.score, "" if p.alive else " (out)"], 24, Palette.INK, true))
	if _online():
		if session.is_host():
			box.add_child(_button("PLAY AGAIN", _play_again_online))
		else:
			box.add_child(_label("The host can start another game.", 24, Palette.DIM, true))
		box.add_child(_button("LEAVE", show_menu))
	else:
		box.add_child(_button("PLAY AGAIN", _closing(start_match)))
		box.add_child(_button("NEW PLAYERS", _closing(show_setup)))
		box.add_child(_button("MAIN MENU", show_menu))


func _play_again_online() -> void:
	_close_overlay()
	_act("play_again", [], _ignore_result)


func _show_rules() -> void:
	var box := _open_overlay(0.96, true, "rules")
	box.add_child(_title("RULES"))
	var lines := [
		"THE TABLE. 2 to 6 players, either passing one phone around (PASS & PLAY) or each on their own phone in a lobby on the same Wi-Fi. One player deals each round and the player to their left goes first. Next round the deal moves one seat to the right, so whoever dealt goes first.",
		"THE DEAL. Everyone gets 7 playing cards and 2 item cards. The other item cards are shuffled into the stock, so a draw from it can give you an item instead of a playing card.",
		"YOUR TURN. Draw 1 card from the stock or the top of the discard pile. If you draw an item, keep it and draw again until you get a playing card. Meld, lay off and use items as much as you like, then discard 1 card to end your turn. You can't discard the card you just took from the discard pile.",
		"MELDS. A set is 3 or 4 cards of the same rank (7 7 7). A run is 3 or more cards in a row of the same suit (4 5 6 of hearts). Aces are low: A-2-3 counts, Q-K-A doesn't.",
		"LAYING OFF. Add cards to any meld on the table, yours or anyone's: select them, then tap the glowing meld.",
		"GOING OUT. Empty your hand of playing cards to win the round (items don't count). You score the cards everyone else is still holding: A = 1, 2-10 = face value, J/Q/K = 10. Going out in a single turn without having melded before is RUMMY and doubles it.",
		"THE SHOTGUN. The winner gets the shotgun with 1 shell, +1 for every 10 points scored (max 3), and picks who to shoot with each shell. Each shell takes 1 health. Everyone starts with 4. Health carries over between rounds. Hit 0 and you're out. Last one standing walks out.",
		"TRUMP CARDS. Each round one rank is trump: aces in round 1, twos in round 2, and so on up to kings in round 13, then back to aces. A trump card (gold star) can stand in for any card of any suit in any set or run: in round 1, 2 3 A 5 of clubs is a run.",
		"SWAPPING A TRUMP. If a meld on the table has a trump in it and you hold the real card it stands for, you can swap that card in and take the trump, but only if you meld the trump straight away with 2 or more of your own cards. Select the real card plus the cards for your new meld, then tap the glowing meld.",
		"FIRST TURN. Nobody can put cards down on their first turn of a round: just draw and discard.",
		"NO DISCARDING TRUMPS. You can't discard a trump card; meld it or lay it off. (If you're holding nothing but trumps, you may.)",
		"HINTS. A gold outline means the card makes a meld in your hand. A gold underline means it fits a meld on the table. A gold banner tells you when you can go out, and when it would be RUMMY. DEADWOOD is what you'd be caught holding if someone went out now.",
	]
	for line in lines:
		box.add_child(_label(line, 24, Palette.INK))
	box.add_child(_label("ITEMS (use as many as you like, any time in your turn)", 28, Palette.PURPLE.lightened(0.3)))
	for id in Items.DEFS:
		var d: Dictionary = Items.DEFS[id]
		box.add_child(_label("%s %s ×%d: %s" % [d["icon"], d["name"], d["copies"], d["text"]], 24, Palette.INK))
	box.add_child(_button("BACK", _closing(_after_action)))


func _show_log() -> void:
	var box := _open_overlay(0.96, true, "log")
	box.add_child(_title("LOG"))
	for i in range(log_lines.size() - 1, maxi(-1, log_lines.size() - 120), -1):
		box.add_child(_label(log_lines[i], 22, Palette.INK))
	box.add_child(_button("BACK", _closing(_after_action)))


func _show_menu() -> void:
	var box := _open_overlay(0.94, false, "menu")
	box.add_child(_title("PAUSED"))
	box.add_child(_button("RESUME", _closing(_after_action)))
	if _online():
		box.add_child(_label("Leaving ends the game for everyone.", 24, Palette.DIM, true))
		box.add_child(_button("LEAVE THE GAME", show_menu))
	else:
		box.add_child(_button("RESTART MATCH", _closing(start_match)))
		box.add_child(_button("NEW PLAYERS", _closing(show_setup)))
		box.add_child(_button("MAIN MENU", show_menu))
