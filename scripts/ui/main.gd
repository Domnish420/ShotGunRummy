extends Control
## Shotgun Cards UI (phone first): Shotgun Rummy and Shotgun Blackjack.
##
## Screens are built in code: main menu -> lobby (same Wi-Fi) or pass-and-play
## setup -> table, with overlays on top for "pass the phone", item reveals,
## round results, the shotgun, rules and the log.
##
## In pass-and-play the table shows whoever's turn it is (AI players play
## themselves while it waits for the next person). Online, each phone
## shows its own seat and actions go to the host's game (see session.gd).

const Game = preload("res://scripts/core/game.gd")
const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const World3DScene = preload("res://scripts/three/world3d.gd")
const Session = preload("res://scripts/net/session.gd")
const Looks = preload("res://scripts/core/looks.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Blackjack = preload("res://scripts/core/blackjack.gd")
const BlackjackBot = preload("res://scripts/core/blackjack_bot.gd")

const Games = preload("res://scripts/core/games.gd")
const Chiptune = preload("res://scripts/audio/chiptune.gd")
const DemoLessons = preload("res://scripts/ui/demo_lessons.gd")
const GoFishUI = preload("res://scripts/ui/modes/gofish_ui.gd")
const CheatUI = preload("res://scripts/ui/modes/cheat_ui.gd")
const TricksUI = preload("res://scripts/ui/modes/tricks_ui.gd")
const SnapUI = preload("res://scripts/ui/modes/snap_ui.gd")
const PresidentUI = preload("res://scripts/ui/modes/president_ui.gd")
const PokerUI = preload("res://scripts/ui/modes/poker_ui.gd")
const SnapBot = preload("res://scripts/core/snap_bot.gd")

const SETTINGS_PATH := "user://settings.cfg"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6

var game: Game
var world: World3DScene
var view3d: SubViewport
var view_rect: TextureRect
var graphics := "PS3"
var session: Session
var profile_name := ""
var my_look: Dictionary = {} # your character, from the customiser
var setup_looks: Array = [] # pass & play: each player's character
var setup_bots: Array = [] # pass & play: "" for a person, or an AI's level
var _editing: Dictionary = {} # the look being made in the creator
var _editing_index := -1 # which of your characters it is (-1: a new one)
var _picked: Dictionary = {} # highlighted on the character select screen
var custom_looks: Array = [] # characters you've made
var player_names: Array = ["PLAYER 1", "PLAYER 2"]
var hide_hands := true
var game_kind := "rummy" # which cartridge: see games.gd
var normal_mode := false # the plain game: no items, no shotgun
var tutorial := false # this game is the demo (watching it, or the practice)
var demo_stage := "" # "watch": it plays itself and explains; "practice": your go
const DEMO_ROUNDS := 3 # practice rounds after watching
var _lessons: Array = [] # [trigger, text, done] for this demo
var _lesson_queue: Array = [] # { text, then } waiting to be shown
var _lesson_panel: PanelContainer
var _lesson_text: Label
var _lesson_time := 0.0 # seconds left on the card showing
var _lesson_then := Callable()
var _demo_wait := 0.0
var played := {} # kind -> shotgun matches finished (normal mode unlocks)
var tutorial_offered := false
var mode_ui = null # the table screen for games that have their own (scripts/ui/modes)
var coach_label: Label
var _sfx: Dictionary = {} # name -> AudioStream
var _sfx_players: Array = []
var _jingle_player: AudioStreamPlayer
var _hum_player: AudioStreamPlayer
var sound_on := true
var solo_opponents := 3 # vs AI: how many AIs
var solo_level := "normal" # vs AI: easy | normal | hard | mixed
var local_mode := "pass" # the last game on this phone: "solo" (vs AI) or "pass"
var _table: Dictionary = {} # that game's players: names, looks, bots
var menu_message := ""
var _pending_cb := Callable() # waiting on the host to answer this phone's action
var _overlay_kind := ""
var _last_shot_text := ""
var _hand_hidden := false # pass-and-play: your cards stay face down until you take the phone
var _waiting_for_deal := false
var _drawing_again := false # Double Down: first of the two cards is drawn
var _viewer := 0 # pass-and-play: the person holding the phone (AIs don't)
var _ai_wait := 0.0 # seconds until the AI's next move
var _ai_memory := {} # seat -> what that AI remembers this turn
var _ai_phase := ""
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


## Plays a little sound: "tick", "swish", "clunk", "select" or
## "jingle:<cartridge>".
func _sound(name_: String) -> void:
	if not sound_on:
		return
	if not _sfx.has(name_):
		if name_.begins_with("jingle:"):
			_sfx[name_] = Chiptune.jingle(name_.trim_prefix("jingle:"))
		else:
			var made := _make_sound(name_)
			if made != null:
				_sfx[name_] = made
	var stream: AudioStream = _sfx.get(name_, null)
	if stream == null:
		return
	if name_.begins_with("jingle:"):
		if _jingle_player == null:
			_jingle_player = AudioStreamPlayer.new()
			_jingle_player.volume_db = -6.0
			add_child(_jingle_player)
		_jingle_player.stream = stream # a new tune cuts off the last one
		_jingle_player.play()
		return
	for pl in _sfx_players:
		if not pl.playing:
			pl.stream = stream
			pl.play()
			return
	if _sfx_players.size() < 6:
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -4.0
		add_child(pl)
		_sfx_players.append(pl)
		pl.stream = stream
		pl.play()


func _ready() -> void:
	theme = Palette.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()

	# the 3D table renders small, then is scaled up with crisp pixels and the
	# gritty post-processing shader
	view3d = SubViewport.new()
	view3d.own_world_3d = true
	view3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view3d.msaa_3d = Viewport.MSAA_DISABLED
	add_child(view3d)
	view_rect = TextureRect.new()
	view_rect.texture = view3d.get_texture()
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post := ShaderMaterial.new()
	post.shader = load("res://shaders/post.gdshader")
	view_rect.material = post
	add_child(_full(view_rect))
	_fit_view()
	world = World3DScene.new()
	view3d.add_child(world)
	world.deal_finished.connect(_on_deal_finished)
	world.sfx.connect(_sound)

	screen = _full(Control.new())
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	overlay_layer = _full(Control.new())
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

	_build_lesson_panel()

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

	get_tree().root.size_changed.connect(_fit_window)
	_fit_window()
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = Chiptune.hum()
	_hum_player.volume_db = -20.0
	add_child(_hum_player)
	if sound_on:
		_hum_player.play()
	show_menu()


func _make_sound(name_: String) -> AudioStream:
	return Chiptune.make(name_)


func _toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	if sound_on:
		_hum_player.play()
		_sound("select")
	else:
		_hum_player.stop()
		if _jingle_player != null:
			_jingle_player.stop()


## How sharp the 3D is: a share of the screen's resolution.
const GRAPHICS := {"PS2": 0.42, "PS3": 0.6, "SHARP": 1.0}


func _fit_view() -> void:
	var s := get_viewport_rect().size
	var scale: float = GRAPHICS.get(graphics, 0.6)
	view3d.size = Vector2i(maxi(64, int(s.x * scale)), maxi(64, int(s.y * scale)))
	var post := view_rect.material as ShaderMaterial
	# full-resolution play needs less grit to look right
	post.set_shader_parameter("dither", 0.0 if graphics == "SHARP" else 1.0)
	post.set_shader_parameter("levels", 64.0 if graphics == "SHARP" else 28.0)


## A point on screen, in the 3D view's (smaller) pixels.
func _to_view(screen_pos: Vector2) -> Vector2:
	return screen_pos * Vector2(view3d.size) / view_rect.size


func _cycle_graphics() -> void:
	var order := GRAPHICS.keys()
	graphics = order[(order.find(graphics) + 1) % order.size()]
	_save_settings()
	_fit_view()
	if game == null:
		show_menu()
	else:
		_show_menu()


## Phones in portrait lay out at 720x1280; wide screens (PC, a phone on its
## side) at 1280x720 so buttons and text stay a sensible size.
func _fit_window() -> void:
	var win := get_tree().root
	var s := win.size
	var want := Vector2i(1280, 720) if s.x > s.y else Vector2i(720, 1280)
	if win.content_scale_size != want:
		win.content_scale_size = want
	if view3d != null:
		_fit_view.call_deferred()


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
	var b := _plain_button(text, on_press, font_size)
	b.pressed.connect(_sound.bind("tick"))
	return b


## A soft blip for each key typed into a name box.
func _typing_sounds(edit: LineEdit) -> void:
	edit.text_changed.connect(func(_t: String) -> void: _sound("type"))
	edit.text_submitted.connect(func(_t: String) -> void: _sound("select"))


func _plain_button(text: String, on_press: Callable, font_size: int = 30) -> Button:
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
	if game != null and not game.options.get("shotgun", true):
		# normal mode: round wins instead of health
		row.add_child(_tag("WINS %d/%d" % [p.rounds_won, game.options["rounds_to_win"]], int(seg.y * 1.6), Palette.GOLD))
		return row
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
		# the game used to be called Shotgun Rummy: on a computer its settings
		# (and your characters) were saved in a folder by that name
		var old := OS.get_user_data_dir().get_base_dir().path_join("Shotgun Rummy").path_join("settings.cfg")
		if not FileAccess.file_exists(old) or cfg.load(old) != OK:
			return
	player_names = cfg.get_value("setup", "names", player_names)
	hide_hands = cfg.get_value("setup", "hide_hands", true)
	setup_bots = cfg.get_value("setup", "bots", [])
	game_kind = str(cfg.get_value("setup", "game", "rummy"))
	if not Games.has(game_kind):
		game_kind = "rummy"
	played = cfg.get_value("progress", "played", {})
	sound_on = cfg.get_value("audio", "on", true)
	tutorial_offered = cfg.get_value("progress", "tutorial_offered", false)
	normal_mode = cfg.get_value("setup", "normal", false) and _normal_unlocked(game_kind)
	solo_opponents = clampi(int(cfg.get_value("solo", "opponents", 3)), 1, MAX_PLAYERS - 1)
	solo_level = str(cfg.get_value("solo", "level", "normal"))
	profile_name = cfg.get_value("profile", "name", "")
	graphics = cfg.get_value("video", "graphics", "PS3")
	my_look = Looks.clean(cfg.get_value("profile", "look", Looks.preset(1)))
	custom_looks = []
	for c in cfg.get_value("profile", "customs", []):
		custom_looks.append(Looks.clean(c))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "names", player_names)
	cfg.set_value("setup", "hide_hands", hide_hands)
	cfg.set_value("setup", "bots", setup_bots)
	cfg.set_value("setup", "game", game_kind)
	cfg.set_value("setup", "normal", normal_mode)
	cfg.set_value("progress", "played", played)
	cfg.set_value("audio", "on", sound_on)
	cfg.set_value("progress", "tutorial_offered", tutorial_offered)
	cfg.set_value("solo", "opponents", solo_opponents)
	cfg.set_value("solo", "level", solo_level)
	cfg.set_value("profile", "name", profile_name)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("profile", "look", my_look)
	cfg.set_value("profile", "customs", custom_looks)
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
	mode_ui = null
	tutorial = false
	demo_stage = ""
	_lesson_queue = []
	if _lesson_panel != null:
		_lesson_panel.visible = false
	world.hide_carousel()
	world.set_menu_mode(true)
	var box := _paper()
	box.add_child(_label("SHOTGUN\nCARDS", 76, Color(0.36, 0.06, 0.05), true))
	box.add_child(_paper_button("CARTRIDGES: %s  ▸" % _game_title(game_kind, normal_mode), show_cartridges, 26))
	world.set_cartridge(game_kind)
	if menu_message != "":
		box.add_child(_label(menu_message, 24, Palette.CARD_RED, true))
		menu_message = ""
	var row := HBoxContainer.new()
	row.add_child(_tag("NAME", 30, Palette.CARD_INK))
	_name_edit = LineEdit.new()
	_typing_sounds(_name_edit)
	_name_edit.text = profile_name
	_name_edit.placeholder_text = "SIGN HERE"
	_name_edit.max_length = 10
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)
	box.add_child(row)
	box.add_child(_paper_button("CHARACTER: %s" % str(my_look.get("name", "CUSTOM")), _open_customiser, 28))
	if OS.has_feature("web"):
		# browsers can't open the connections lobbies use
		box.add_child(_label("Lobbies with friends need the download version. Here you can play on this device.", 22, Palette.CARD_INK, true))
	else:
		box.add_child(_paper_button("HOST A LOBBY", _on_host_pressed))
		box.add_child(_paper_button("JOIN A LOBBY", _on_join_pressed))
	box.add_child(_paper_button("PLAY ON THIS PHONE", _on_this_phone_pressed, 28))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	for b in [_paper_button("GRAPHICS: %s" % graphics, _cycle_graphics, 24), _paper_button("SOUND: %s" % ("ON" if sound_on else "OFF"), _menu_sound, 24)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(b)
	box.add_child(row2)
	box.add_child(_label("Lobbies work between phones on the same Wi-Fi.", 20, Palette.CARD_INK, true))
	if not tutorial_offered:
		tutorial_offered = true
		_save_settings()
		_offer_tutorial()


## "SHOTGUN GO FISH", or just "GO FISH" in normal mode.
static func _game_title(kind: String, normal: bool) -> String:
	return Games.label(kind) if normal else Games.title(kind)


## A new, empty game of `kind`.
static func new_game(kind: String, normal: bool = false) -> Game:
	return Games.make(kind, normal)


func _normal_unlocked(kind: String) -> bool:
	return int(played.get(kind, 0)) >= Games.UNLOCK_NORMAL_AFTER


# ================================================================ cartridges

## The cartridges: swipe through them (each plays its little tune), then
## PLAY or DEMO. The words float; there are no boxes here.
func show_cartridges() -> void:
	if _name_edit != null and is_instance_valid(_name_edit) and _name_edit.is_inside_tree():
		var typed := _name_edit.text.strip_edges().to_upper().left(10)
		if typed != "":
			profile_name = typed
	_close_overlay()
	_clear(screen)
	var kinds := Games.kinds()
	var at := maxi(0, kinds.find(game_kind))
	if world._carousel.is_empty():
		world.show_carousel(kinds, at)
		_sound("jingle:" + game_kind)
	else:
		world.carousel_to(at)
	# swipes anywhere move the carousel
	var swipe := _full(Control.new())
	swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	swipe.gui_input.connect(_on_carousel_input)
	screen.add_child(swipe)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	screen.add_child(_full(col))
	var gap_top := Control.new()
	gap_top.custom_minimum_size = Vector2(0, 60)
	gap_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap_top)
	var title := _label(_game_title(game_kind, normal_mode), 40, Palette.GOLD, true)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	var mode_row := HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 40)
	mode_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_row.add_child(_bubble("SHOTGUN", _set_normal.bind(false), Palette.RED if not normal_mode else Palette.DIM, 34))
	var plain := _bubble("NORMAL" if _normal_unlocked(game_kind) else "NORMAL 🔒%d/%d" % [int(played.get(game_kind, 0)), Games.UNLOCK_NORMAL_AFTER], _set_normal.bind(true), Palette.AMBER if normal_mode else Palette.DIM, 34)
	plain.disabled = not _normal_unlocked(game_kind)
	mode_row.add_child(plain)
	col.add_child(mode_row)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer) # the cartridges show through here
	var arrows := HBoxContainer.new()
	arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrows.add_child(_bubble("◀", _scroll_cartridges.bind(-1), Palette.INK, 60))
	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrows.add_child(mid)
	arrows.add_child(_bubble("▶", _scroll_cartridges.bind(1), Palette.INK, 60))
	col.add_child(arrows)
	var words := HBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 70)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_bubble("PLAY", _cartridge_play, Palette.GOLD, 72))
	words.add_child(_bubble("DEMO", _start_demo, Color(0.55, 0.85, 1.0), 72))
	col.add_child(words)
	col.add_child(_bubble("BACK", _leave_cartridges, Palette.DIM, 36))
	var gap_bottom := Control.new()
	gap_bottom.custom_minimum_size = Vector2(0, 40)
	gap_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap_bottom)


const BubbleWord = preload("res://scripts/ui/bubble_word.gd")


func _bubble(word: String, on_press: Callable, color: Color, font_size: int = 52) -> Button:
	var b := BubbleWord.new()
	b.setup(word, on_press, color, font_size)
	b.pressed.connect(_sound.bind("tick"))
	return b


var _swipe_from := Vector2.ZERO


func _on_carousel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_swipe_from = event.position
		else:
			var dx: float = event.position.x - _swipe_from.x
			if absf(dx) > 50.0:
				_scroll_cartridges(-1 if dx > 0 else 1)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT:
			_scroll_cartridges(-1)
		elif event.keycode == KEY_RIGHT:
			_scroll_cartridges(1)


func _scroll_cartridges(step: int) -> void:
	var kinds := Games.kinds()
	var at := posmod(kinds.find(game_kind) + step, kinds.size())
	_pick_cartridge(kinds[at])


func _pick_cartridge(kind: String) -> void:
	game_kind = kind
	if not _normal_unlocked(kind):
		normal_mode = false
	_save_settings()
	world.carousel_to(Games.kinds().find(kind))
	_sound("swish")
	_sound("jingle:" + kind)
	show_cartridges()


func _set_normal(on: bool) -> void:
	normal_mode = on and _normal_unlocked(game_kind)
	_save_settings()
	_sound("tick")
	show_cartridges()


func _leave_cartridges() -> void:
	world.hide_carousel()
	_sound("tick")
	show_menu()


## PLAY: slot it in, then how do you want to play?
func _cartridge_play() -> void:
	world.carousel_insert()
	world.set_cartridge(game_kind)
	_sound("clunk")
	show_play_choice()


func show_play_choice() -> void:
	world.hide_carousel()
	_close_overlay()
	_clear(screen)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(_full(center))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var title := _label(_game_title(game_kind, normal_mode), 44, Palette.GOLD, true)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	col.add_child(_bubble("VS AI", show_solo, Palette.GOLD, 58))
	col.add_child(_bubble("PASS THE PHONE", _on_pass_and_play_pressed, Palette.AMBER, 44))
	if not OS.has_feature("web"): # browsers can't open the connections lobbies use
		col.add_child(_bubble("HOST A LOBBY", _on_host_pressed, Color(0.55, 0.85, 1.0), 44))
		col.add_child(_bubble("JOIN A LOBBY", _on_join_pressed, Color(0.55, 0.85, 1.0), 44))
	col.add_child(_bubble("BACK", show_cartridges, Palette.DIM, 34))


## First time in: point people at the demos.
func _offer_tutorial() -> void:
	var box := _open_overlay(0.94, false, "menu")
	box.add_child(_title("FIRST TIME HERE?"))
	box.add_child(_label("Every cartridge has a DEMO: a quick normal game against easy AIs, with tips as you go.", 26, Palette.INK, true))
	box.add_child(_button("PICK A DEMO", _closing(show_cartridges)))
	box.add_child(_button("NO THANKS", _closing(_noop)))


## DEMO: first it plays itself (the same game every time, in shotgun
## mode) and explains each rule as it comes up, then you play a few
## practice rounds with tips.
func _start_demo() -> void:
	world.carousel_insert()
	world.set_cartridge(game_kind)
	_sound("clunk")
	world.hide_carousel()
	_start_tutorial()


func _start_tutorial() -> void:
	var me := profile_name if profile_name != "" else "YOU"
	var names := [me, "DOC", "PEARL"]
	var looks := [my_look.duplicate(), Looks.preset(4), Looks.preset(9)]
	local_mode = "solo"
	demo_stage = "watch"
	_lessons = []
	for l in DemoLessons.for_game(game_kind):
		_lessons.append([l[0], l[1], false])
	_lesson_queue = []
	# everyone, you too, is played for you; the same shuffle every time
	_table = {"names": names, "looks": looks, "bots": ["normal", "normal", "normal"], "kind": game_kind, "normal": false, "tutorial": true, "seed": absi(hash(game_kind)) % 100000}
	start_match()
	for l in _lessons:
		if l[0] == "start":
			l[2] = true
			_lesson_queue.append({"text": l[1]})


## A lesson's moment came: queue it (each one only once).
func _demo_event(kind: String, d: Dictionary) -> void:
	if demo_stage != "watch":
		return
	for l in _lessons:
		if not l[2] and DemoLessons.matches(l[0], kind, d):
			l[2] = true
			_lesson_queue.append({"text": l[1]})


## The watched round is over: whatever didn't come up, then over to you.
func _end_watch() -> void:
	demo_stage = "recap"
	for l in _lessons:
		if not l[2]:
			l[2] = true
			_lesson_queue.append({"text": l[1]})
	_lesson_queue.append({"text": DemoLessons.PRACTICE % DEMO_ROUNDS, "then": _start_practice})


func _start_practice() -> void:
	demo_stage = "practice"
	_table["bots"] = ["", "easy", "easy"]
	_table.erase("seed")
	start_match()


## The card at the top that explains a rule. The game waits while it's up;
## it moves on by itself after a few seconds, or tap NEXT.
func _build_lesson_panel() -> void:
	var layer := _full(MarginContainer.new())
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		layer.add_theme_constant_override("margin_" + side, 24)
	layer.add_theme_constant_override("margin_top", 110)
	add_child(layer) # above the table and the pop-ups
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(col)
	_lesson_panel = PanelContainer.new()
	_lesson_panel.add_theme_stylebox_override("panel", Palette.box(Color(0.06, 0.05, 0.04, 0.92), Palette.GOLD, 3, 2, 10))
	_lesson_panel.visible = false
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	_lesson_panel.add_child(inner)
	inner.add_child(_label("DEMO", 20, Palette.GOLD, true))
	_lesson_text = _label("", 26, Palette.INK, true)
	inner.add_child(_lesson_text)
	var next := _button("NEXT ▸", _next_lesson, 24)
	next.custom_minimum_size = Vector2(0, 50)
	inner.add_child(next)
	col.add_child(_lesson_panel)


func _drive_lessons(delta: float) -> void:
	if _lesson_panel == null or not is_instance_valid(_lesson_panel) or game == null:
		return
	if _lesson_panel.visible:
		_lesson_time -= delta
		if _lesson_time <= 0.0:
			_next_lesson()
		return
	if _lesson_queue.is_empty() or world.dealing:
		return
	var l: Dictionary = _lesson_queue.pop_front()
	_lesson_text.text = l["text"]
	_lesson_then = l.get("then", Callable())
	_lesson_time = 3.0 + l["text"].length() * 0.045
	_lesson_panel.visible = true
	_sound("pick_item")


func _next_lesson() -> void:
	if _lesson_panel == null or not _lesson_panel.visible:
		return
	_lesson_panel.visible = false
	var then := _lesson_then
	_lesson_then = Callable()
	if then.is_valid():
		then.call()


func _lesson_showing() -> bool:
	return _lesson_panel != null and is_instance_valid(_lesson_panel) and _lesson_panel.visible


## While watching: press the buttons for you (watch the shotgun, then on to
## your practice).
func _drive_demo(delta: float) -> void:
	if demo_stage != "watch" or game == null or _lesson_showing():
		return
	if overlay_layer.get_child_count() == 0 or (_overlay_kind != "result" and _overlay_kind != "gun"):
		_demo_wait = 2.5
		return
	_demo_wait -= delta
	if _demo_wait > 0.0:
		return
	_demo_wait = 2.5
	if game.gun != null and _overlay_kind == "result":
		_show_gun()
	elif game.gun == null and (game.phase == "round_over" or game.phase == "match_over"):
		_close_overlay()
		_end_watch()


## Practice over: well done.
func _finish_demo() -> void:
	demo_stage = ""
	var box := _open_overlay(0.96, false, "match")
	box.add_child(_title("YOU'VE GOT IT", Palette.GOLD))
	box.add_child(_label("That's %s. Ready to play it for real?" % Games.label(game.kind), 28, Palette.INK, true))
	box.add_child(_button("PLAY %s" % Games.label(game.kind), _closing(show_play_choice)))
	box.add_child(_button("WATCH THE DEMO AGAIN", _closing(_start_tutorial)))
	box.add_child(_button("MAIN MENU", show_menu))


func _blackjack() -> bool:
	return game != null and game.kind == "blackjack"


func _menu_sound() -> void:
	_toggle_sound()
	show_menu()


func _noop() -> void:
	pass


## Reads the name box; returns "" (and complains) if it's empty.
func _take_name() -> String:
	var n := profile_name
	if _name_edit != null and is_instance_valid(_name_edit) and _name_edit.is_inside_tree():
		n = _name_edit.text.strip_edges().to_upper().left(10)
	if n == "":
		menu_message = "Sign your name first."
		show_menu()
		return ""
	profile_name = n
	_save_settings()
	return n


## Keeps the name typed on the main menu, if there is one.
func _keep_menu_name() -> void:
	if _name_edit == null or not is_instance_valid(_name_edit):
		return
	var n := _name_edit.text.strip_edges().to_upper()
	if n != "":
		profile_name = n.left(10)
		player_names[0] = profile_name
		_save_settings()


func _on_this_phone_pressed() -> void:
	_keep_menu_name()
	show_this_phone()


func _on_pass_and_play_pressed() -> void:
	_keep_menu_name()
	show_setup()


## Solo against AIs, or everyone passing the phone around.
func show_this_phone() -> void:
	var box := _paper()
	box.add_child(_label("ON THIS PHONE", 52, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label(_game_title(game_kind, normal_mode), 26, Palette.CARD_INK, true))
	box.add_child(_paper_button("VS AI (SOLO)", show_solo))
	box.add_child(_label("Just you against AI players.", 22, Palette.CARD_INK, true))
	box.add_child(_paper_button("PASS THE PHONE", _on_pass_and_play_pressed))
	box.add_child(_label("Friends share this phone and take turns. You can add AIs too.", 22, Palette.CARD_INK, true))
	box.add_child(_paper_button("BACK", show_menu, 28))


# ================================================================ solo vs AI

const SOLO_LEVELS := ["easy", "normal", "hard", "mixed"]


func show_solo() -> void:
	var box := _paper()
	box.add_child(_label("VS AI", 60, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label(_game_title(game_kind, normal_mode), 26, Palette.CARD_INK, true))
	box.add_child(_label("%s, PLAYING AS %s" % [profile_name if profile_name != "" else "YOU", _short_name(my_look)], 24, Palette.CARD_INK, true))
	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.add_theme_constant_override("separation", 16)
	count_row.add_child(_tag("OPPONENTS", 30, Palette.CARD_INK))
	count_row.add_child(_button(" - ", _change_solo_count.bind(-1)))
	count_row.add_child(_tag(str(solo_opponents), 40, Palette.CARD_INK))
	count_row.add_child(_button(" + ", _change_solo_count.bind(1)))
	box.add_child(count_row)
	box.add_child(_label("DIFFICULTY", 26, Palette.CARD_INK, true))
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 6)
	for level in SOLO_LEVELS:
		var b := _paper_button(str(level).to_upper(), _set_solo_level.bind(level), 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if level == solo_level:
			Palette.accent(b, Palette.RED)
		level_row.add_child(b)
	box.add_child(level_row)
	var about := {
		"easy": "Sloppy players who throw items around.",
		"normal": "Solid players who use items when they help.",
		"hard": "Sharks: they hold out for Rummy and shoot the leader.",
		"mixed": "A bit of everything: easy, normal and hard at one table.",
	}
	box.add_child(_label(about.get(solo_level, ""), 22, Palette.CARD_INK, true))
	var go := _button("DEAL ME IN", _start_solo, 34)
	go.add_theme_stylebox_override("normal", Palette.box(Palette.CARD_INK, Palette.CARD_INK, 2, 2, 10))
	box.add_child(go)
	box.add_child(_paper_button("BACK", show_this_phone, 28))


func _change_solo_count(delta: int) -> void:
	solo_opponents = clampi(solo_opponents + delta, 1, MAX_PLAYERS - 1)
	show_solo()


func _set_solo_level(level: String) -> void:
	solo_level = level
	show_solo()


## You plus AIs, each with its own name and character.
func _start_solo() -> void:
	var me := profile_name if profile_name != "" else "YOU"
	var names := [me]
	var looks := [my_look.duplicate()]
	var bots := [""]
	var used_looks := [str(my_look.get("name", ""))]
	var name_pool: Array = Bot.NAMES.duplicate()
	name_pool.shuffle()
	var look_pool := range(Looks.PRESETS.size())
	look_pool.shuffle()
	for i in range(solo_opponents):
		var n: String = name_pool[i]
		while names.has(n):
			n += "*"
		names.append(n)
		var look := {}
		for k in look_pool:
			look = Looks.preset(k)
			if not used_looks.has(str(look.get("name", ""))):
				break
		used_looks.append(str(look.get("name", "")))
		looks.append(look)
		bots.append(Bot.LEVELS[i % Bot.LEVELS.size()] if solo_level == "mixed" else solo_level)
	_save_settings()
	local_mode = "solo"
	_table = {"names": names, "looks": looks, "bots": bots, "kind": game_kind, "normal": normal_mode}
	start_match()


## NEW PLAYERS after a game on this phone: back to whichever setup it came from.
func _new_players() -> void:
	if local_mode == "solo":
		show_solo()
	else:
		show_setup()


func _on_host_pressed() -> void:
	var n := _take_name()
	if n == "":
		return
	var err := session.host(n, my_look)
	session.game_kind = game_kind
	session.normal = normal_mode
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
		var kind_name: String = Games.label(str(l.get("kind", "rummy")))
		box.add_child(_paper_button("%s · %s (%d/%d)" % [l["name"], kind_name, l["players"], l["max"]], _join_ip.bind(ip), 26))
	box.add_child(_label("OR JOIN BY IP (shown on the host's screen)", 22, Palette.CARD_INK, true))
	var row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_typing_sounds(_ip_edit)
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
	var err := session.join(ip, profile_name, my_look)
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
	if session.is_host():
		box.add_child(_paper_button("CARTRIDGE: %s  ▸" % _game_title(session.game_kind, session.normal), _cycle_lobby_game, 24))
		if _normal_unlocked(session.game_kind):
			box.add_child(_paper_button("MODE: %s" % ("NORMAL" if session.normal else "SHOTGUN"), _toggle_lobby_normal, 22))
	else:
		box.add_child(_label("CARTRIDGE: %s" % _game_title(session.game_kind, session.normal), 26, Palette.CARD_INK, true))
	box.add_child(_label("PLAYERS (%d/%d)" % [session.names.size(), Session.MAX_PLAYERS], 26, Palette.CARD_INK))
	for i in range(session.names.size()):
		var who: String = session.names[i]
		var look_name := ""
		if i < session.looks.size() and session.looks[i] is Dictionary:
			look_name = "  " + _short_name(session.looks[i])
		var level: String = str(session.bots[i]) if i < session.bots.size() else ""
		var line := _label("%d. %s%s%s" % [i + 1, who, " (HOST)" if i == 0 else "", look_name], 28, Palette.CARD_INK)
		if level == "":
			box.add_child(line)
			continue
		var row := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.text = "%d. %s (AI)%s" % [i + 1, who, look_name]
		row.add_child(line)
		if session.is_host():
			var lvl := _paper_button(Bot.level_label(level), session.cycle_bot.bind(i), 20)
			lvl.custom_minimum_size = Vector2(110, 48)
			row.add_child(lvl)
			var drop := _paper_button("X", session.remove_bot.bind(i), 20)
			drop.custom_minimum_size = Vector2(48, 48)
			row.add_child(drop)
		else:
			row.add_child(_tag(Bot.level_label(level), 22, Palette.CARD_INK))
		box.add_child(row)
	if session.is_host():
		if session.names.size() < Session.MAX_PLAYERS:
			box.add_child(_paper_button("+ ADD AN AI PLAYER", session.add_bot.bind("normal"), 26))
		var start := _paper_button("START THE GAME", session.start_match)
		start.disabled = session.names.size() < 2
		box.add_child(start)
		if session.names.size() < 2:
			box.add_child(_label("Waiting for at least one more player (or add an AI)...", 22, Palette.CARD_INK, true))
	else:
		box.add_child(_label("Waiting for the host to start...", 24, Palette.CARD_INK, true))
	box.add_child(_paper_button("LEAVE", show_menu, 28))


func _cycle_lobby_game() -> void:
	var kinds := Games.kinds()
	game_kind = kinds[(kinds.find(session.game_kind) + 1) % kinds.size()]
	_save_settings()
	session.set_game(game_kind, session.normal and _normal_unlocked(game_kind))


func _toggle_lobby_normal() -> void:
	session.set_game(session.game_kind, not session.normal)


var _roster_size := 0


func _on_roster_changed() -> void:
	if session.names.size() != _roster_size:
		_sound("join" if session.names.size() > _roster_size else "leave")
		_roster_size = session.names.size()
	if not session.in_match:
		show_lobby()


func _on_session_ended(reason: String) -> void:
	menu_message = reason
	show_menu()


# ================================================================ characters

## Presets first, then the player's own creations.
func _all_characters() -> Array:
	var out := []
	for i in range(Looks.PRESETS.size()):
		out.append(Looks.preset(i))
	for c in custom_looks:
		out.append(c)
	return out


func _open_customiser() -> void:
	var n := _name_edit.text.strip_edges().to_upper().left(10)
	if n != "":
		profile_name = n
	_picked = my_look.duplicate()
	show_character_select()


## A 3D preview of the picked character up top; underneath, every character
## as a tile, with a + tile at the end to make your own.
func show_character_select() -> void:
	var box := _character_screen(_picked)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 330)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	box.add_child(scroll)
	var all := _all_characters()
	var picked_tile: Control = null
	for i in range(all.size()):
		var look: Dictionary = all[i]
		var tile := _button(_short_name(look), _pick_character.bind(look), 20)
		tile.custom_minimum_size = Vector2(0, 58)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.clip_text = true
		var mine: bool = i >= Looks.PRESETS.size()
		if look.get("name", "") == _picked.get("name", "") and look.get("base", "") == _picked.get("base", ""):
			Palette.accent(tile, Palette.AMBER)
			picked_tile = tile
		elif mine:
			Palette.accent(tile, Palette.PURPLE)
		grid.add_child(tile)
	var plus := _button("+", _create_character, 40)
	plus.custom_minimum_size = Vector2(0, 58)
	plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.accent(plus, Palette.GOLD)
	grid.add_child(plus)
	# keep the highlighted character in view
	if picked_tile != null:
		scroll.ensure_control_visible.call_deferred(picked_tile)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var choose := _button("PLAY AS %s" % _short_name(_picked), _choose_character, 24)
	Palette.accent(choose, Palette.AMBER)
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(choose)
	if _custom_index(_picked) >= 0:
		var edit := _button("EDIT", _edit_character, 24)
		var del := _button("DELETE", _delete_character, 24)
		Palette.accent(del, Palette.RED)
		for b in [edit, del]:
			b.custom_minimum_size = Vector2(110, 64)
			buttons.add_child(b)
	box.add_child(buttons)
	var back := _button("BACK", _leave_customiser, 24)
	back.custom_minimum_size = Vector2(0, 52)
	box.add_child(back)


## The shared layout: title, the 3D preview showing through, and a panel at
## the bottom. Returns the panel's box.
func _character_screen(look: Dictionary) -> VBoxContainer:
	_close_overlay()
	_clear(screen)
	world.set_menu_mode(false)
	world.show_preview(look)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 24)
	screen.add_child(_full(margin))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var title := _label(str(look.get("name", "CUSTOM")), 44, Palette.AMBER, true)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(gap)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.box(Color(0.03, 0.03, 0.025, 0.88), Palette.BUTTON_EDGE, 2, 4, 14))
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


func _pick_character(look: Dictionary) -> void:
	_picked = look.duplicate()
	show_character_select()


func _choose_character() -> void:
	my_look = Looks.clean(_picked)
	if not setup_looks.is_empty():
		setup_looks[0] = my_look.duplicate()
	_save_settings()
	_leave_customiser()


## Which of your own characters this is (-1: a preset).
func _custom_index(look: Dictionary) -> int:
	for i in range(custom_looks.size()):
		if custom_looks[i].get("name", "") == look.get("name", ""):
			return i
	return -1


func _create_character() -> void:
	_editing = _picked.duplicate()
	_editing["name"] = _fresh_custom_name()
	_editing_index = -1
	show_creator()


func _edit_character() -> void:
	_editing = _picked.duplicate()
	_editing_index = _custom_index(_picked)
	show_creator()


func _delete_character() -> void:
	var i := _custom_index(_picked)
	if i >= 0:
		custom_looks.remove_at(i)
		if my_look.get("name", "") == _picked.get("name", ""):
			my_look = Looks.preset(1)
		_picked = my_look.duplicate()
		_save_settings()
	show_character_select()


func _fresh_custom_name() -> String:
	var n := 1
	while true:
		var candidate := "MY CHARACTER %d" % n
		if _custom_index({"name": candidate}) < 0:
			return candidate
		n += 1
	return "MY CHARACTER"


var _creator_name: LineEdit


## Make (or change) one of your own characters.
func show_creator() -> void:
	var box := _character_screen(_editing)
	var name_row := HBoxContainer.new()
	name_row.add_child(_tag("NAME", 24, Palette.DIM))
	_creator_name = LineEdit.new()
	_typing_sounds(_creator_name)
	_creator_name.text = str(_editing.get("name", ""))
	_creator_name.max_length = 20
	_creator_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator_name.add_theme_color_override("font_color", Palette.INK)
	_creator_name.add_theme_stylebox_override("normal", Palette.box(Color(0, 0, 0, 0.4), Palette.BUTTON_EDGE, 2, 2, 6))
	_creator_name.add_theme_stylebox_override("focus", Palette.box(Color(0, 0, 0, 0.5), Palette.AMBER, 2, 2, 6))
	_creator_name.text_changed.connect(func(t: String) -> void: _editing["name"] = t.strip_edges().to_upper())
	name_row.add_child(_creator_name)
	box.add_child(name_row)
	for part in [["BODY", "base", Looks.BASES], ["HAT", "hat", Looks.HATS], ["FACE", "face", Looks.FACES]]:
		var names: Dictionary = part[2]
		box.add_child(_choice_row(part[0], names[_editing[part[1]]], _step_part.bind(-1, part[1], names.keys()), _step_part.bind(1, part[1], names.keys())))
	# where the face piece sits
	var face: String = _editing.get("face", "none")
	if face != "none":
		if face != "shades":
			var side_word := "THEIR LEFT" if _editing.get("face_side", "left") == "left" else "THEIR RIGHT"
			var which := "EYE" if face == "eyepatch" else "MOUTH"
			box.add_child(_choice_row("  " + which, side_word, _flip_face_side, _flip_face_side))
		var angle_word: String = {"cigarette": "DROOP", "cigar": "DROOP", "eyepatch": "STRAP", "shades": "TILT"}.get(face, "ANGLE")
		box.add_child(_choice_row("  " + angle_word, _step_word(int(_editing.get("face_angle", 0))), _nudge_face.bind("face_angle", -1), _nudge_face.bind("face_angle", 1)))
		box.add_child(_choice_row("  HEIGHT", _step_word(int(_editing.get("face_height", 0))), _nudge_face.bind("face_height", -1), _nudge_face.bind("face_height", 1)))
	box.add_child(_tag("OUTFIT: %s" % Looks.OUTFITS[int(_editing["outfit"])]["name"], 24, Palette.DIM))
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	for i in range(Looks.OUTFITS.size()):
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(0, 52)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col_c: Color = Looks.OUTFITS[i]["color"]
		var edge := Palette.AMBER if i == int(_editing["outfit"]) else Palette.BUTTON_EDGE
		sw.add_theme_stylebox_override("normal", Palette.box(col_c.darkened(0.35) if i > 0 else Color(0.2, 0.18, 0.16), edge, 3, 2, 4))
		sw.add_theme_stylebox_override("hover", Palette.box(col_c.darkened(0.2) if i > 0 else Color(0.25, 0.22, 0.2), edge, 3, 2, 4))
		sw.text = "-" if i == 0 else ""
		sw.pressed.connect(_sound.bind("part"))
		sw.pressed.connect(_set_part.bind("outfit", i))
		swatches.add_child(sw)
	box.add_child(swatches)
	var eyes := _button("GLOWING EYES: %s" % ("ON" if _editing["eyes"] else "OFF"), _set_part.bind("eyes", not _editing["eyes"]), 24)
	eyes.custom_minimum_size = Vector2(0, 52)
	box.add_child(eyes)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var save := _button("SAVE", _save_creation)
	Palette.accent(save, Palette.AMBER)
	var cancel := _button("CANCEL", show_character_select)
	for b in [save, cancel]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	box.add_child(buttons)


## [◀] LABEL: value [▶]
func _choice_row(label: String, value: String, on_prev: Callable, on_next: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var prev := _button(" < ", on_prev, 28)
	prev.custom_minimum_size = Vector2(64, 52)
	row.add_child(prev)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	mid.add_child(_label(label, 18, Palette.DIM, true))
	mid.add_child(_label(value, 28, Palette.INK, true))
	row.add_child(mid)
	var nxt := _button(" > ", on_next, 28)
	nxt.custom_minimum_size = Vector2(64, 52)
	row.add_child(nxt)
	return row


func _step_part(delta: int, part: String, options: Array) -> void:
	_sound("part")
	var at := options.find(_editing[part])
	_set_part(part, options[posmod(at + delta, options.size())])


## -2..2 shown as a little bar: "-- ·" ... "· ++".
static func _step_word(v: int) -> String:
	return ["--", "-", "MIDDLE", "+", "++"][clampi(v + 2, 0, 4)]


func _flip_face_side() -> void:
	_sound("part")
	_set_part("face_side", "right" if _editing.get("face_side", "left") == "left" else "left")


func _nudge_face(key: String, delta: int) -> void:
	_sound("part")
	_set_part(key, clampi(int(_editing.get(key, 0)) + delta, -2, 2))


func _set_part(part: String, value) -> void:
	_editing[part] = value
	show_creator()


func _save_creation() -> void:
	_sound("save")
	var char_name := str(_editing.get("name", "")).strip_edges().to_upper().left(20)
	if char_name == "":
		char_name = _fresh_custom_name()
	# a preset's name, or another of yours: make it unique
	var taken := func(n: String) -> bool:
		for p in Looks.PRESETS:
			if p["name"] == n:
				return true
		var i := _custom_index({"name": n})
		return i >= 0 and i != _editing_index
	while taken.call(char_name):
		char_name += "*"
	_editing["name"] = char_name
	var look := Looks.clean(_editing)
	look["name"] = char_name
	if _editing_index >= 0:
		custom_looks[_editing_index] = look
	else:
		custom_looks.append(look)
	_picked = look.duplicate()
	_save_settings()
	show_character_select()


func _leave_customiser() -> void:
	world.hide_preview()
	show_menu()


# ================================================================ setup screen

var _name_edits: Array = []


func show_setup() -> void:
	_fit_setup_looks()
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
	box.add_child(_label("SHOTGUN\nCARDS", 76, Color(0.36, 0.06, 0.05), true))
	box.add_child(_label("GENERAL RELEASE OF LIABILITY", 24, Palette.CARD_INK, true))
	box.add_child(_label("The undersigned agree to a game of %s." % ("Blackjack" if game_kind == "blackjack" else "Rummy") + " Strange things are dealt with the cards. Whoever wins a hand gets the shotgun. Everyone has 4 lives. Only one leaves.", 24, Palette.CARD_INK))

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
		_typing_sounds(edit)
		edit.text = str(player_names[i])
		edit.placeholder_text = "SIGN HERE"
		edit.max_length = 10
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)
		var who := _paper_button(_short_name(setup_looks[i]), _cycle_setup_look.bind(i), 20)
		who.custom_minimum_size = Vector2(170, 56)
		row.add_child(who)
		var kind := _paper_button(_seat_kind(i), _cycle_setup_bot.bind(i), 20)
		kind.custom_minimum_size = Vector2(130, 56)
		kind.disabled = i == 0 # player 1 is you
		row.add_child(kind)
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
	hide_box.toggled.connect(func(_on: bool) -> void: _sound("tick"))
	box.add_child(hide_box)

	var sign_btn := _button("SIGN THE WAIVER", _start_from_setup, 34)
	sign_btn.add_theme_stylebox_override("normal", Palette.box(Palette.CARD_INK, Palette.CARD_INK, 2, 2, 10))
	box.add_child(sign_btn)
	box.add_child(_paper_button("BACK", show_this_phone, 28))


func _on_hide_toggled(on: bool) -> void:
	hide_hands = on


## Everyone at a pass & play table has a character: player 1 is you.
func _fit_setup_looks() -> void:
	while setup_looks.size() < player_names.size():
		var i := setup_looks.size()
		setup_looks.append(my_look.duplicate() if i == 0 else Looks.for_seat(i))
	while setup_looks.size() > player_names.size():
		setup_looks.pop_back()
	while setup_bots.size() < player_names.size():
		setup_bots.append("")
	while setup_bots.size() > player_names.size():
		setup_bots.pop_back()
	setup_bots[0] = ""


func _seat_kind(i: int) -> String:
	var level: String = setup_bots[i] if i < setup_bots.size() else ""
	return "PERSON" if level == "" else "AI: %s" % Bot.level_label(level)


## Person -> AI easy -> AI normal -> AI hard -> person. An AI gets a name of
## its own unless someone typed one in.
func _cycle_setup_bot(i: int) -> void:
	_read_names()
	var order := [""] + Bot.LEVELS
	setup_bots[i] = order[(order.find(setup_bots[i]) + 1) % order.size()]
	var current := str(player_names[i]).strip_edges().to_upper()
	if setup_bots[i] != "" and (current == "" or current.begins_with("PLAYER")):
		for n in Bot.NAMES:
			if not player_names.has(n):
				player_names[i] = n
				break
	elif setup_bots[i] == "" and Bot.NAMES.has(current):
		player_names[i] = "PLAYER %d" % (i + 1)
	show_setup()


func _short_name(look: Dictionary) -> String:
	return str(look.get("name", "CUSTOM")).trim_prefix("THE ")


func _cycle_setup_look(i: int) -> void:
	_read_names()
	var all := _all_characters()
	var at := -1
	for k in range(all.size()):
		if all[k].get("name", "") == setup_looks[i].get("name", ""):
			at = k
	setup_looks[i] = all[(at + 1) % all.size()].duplicate()
	show_setup()


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
	_fit_setup_looks()
	local_mode = "pass"
	_table = {"names": player_names.duplicate(), "looks": setup_looks.duplicate(true), "bots": setup_bots.duplicate(), "kind": game_kind, "normal": normal_mode}
	start_match()


# ================================================================ match flow

## Starts (or restarts) a game on this phone with the players in `_table`.
func start_match() -> void:
	session.leave()
	world.hide_carousel()
	game = new_game(str(_table.get("kind", "rummy")), bool(_table.get("normal", false)))
	tutorial = bool(_table.get("tutorial", false))
	if not tutorial:
		demo_stage = ""
	game.setup(_table["names"], {}, int(_table.get("seed", -1)))
	for i in range(game.players.size()):
		game.players[i].look = _table["looks"][i]
		game.players[i].bot = _table["bots"][i]
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
	_viewer = 0
	_ai_memory = {}
	_ai_wait = 1.0
	_ai_phase = ""


func _online() -> bool:
	return session != null and session.is_online()


## The seat this screen belongs to: whoever's turn it is in pass-and-play
## (or the last person to play while an AI has its turn), or this phone's own
## seat online.
func _me() -> int:
	if _online():
		return session.my_seat
	return _viewer if _is_bot(game.turn) else game.turn


func _is_bot(seat: int) -> bool:
	return game != null and seat >= 0 and seat < game.players.size() and game.players[seat].bot != ""


## People still in the game at this table (pass-and-play).
func _people_alive() -> int:
	var n := 0
	for p in game.players:
		if p.alive and p.bot == "":
			n += 1
	return n


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
	if world.dealing or world.fx_busy:
		if action != "next_round" and action != "shoot" and action != "play_again":
			return # wait for the animation
	if _online():
		if _pending_cb.is_valid():
			return # still waiting on the last one
		_pending_cb = then
		session.act(action, args)
		return
	var seat := game.turn
	if action == "shoot" and game.gun != null:
		seat = game.gun["holder"]
	if action == "snap":
		seat = _me() # Snap: anyone, any time
	if _is_bot(seat) and action != "next_round" and action != "play_again":
		return # the AI is playing this one
	then.call(Session.perform(game, seat, action, args, true))


func _ignore_result(_res: Dictionary) -> void:
	_after_action()


func _on_game_event(kind: String, d: Dictionary) -> void:
	if mode_ui != null:
		mode_ui.on_event(kind, d)
	_event_sound(kind, d)
	_demo_event(kind, d)
	match kind:
		"roulette":
			world.roulette(d["seat"], d["hit"])
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
		"loot":
			_log("%s finds an item." % _name(d["seat"]))
		"hit":
			_log("%s hits: %s." % [_name(d["seat"]), Cards.card_name(d["card"])])
		"stand":
			_log("%s stands%s." % [_name(d["seat"]), " on %d" % d["total"] if d["seat"] == _me() else ""])
		"bust":
			_log("%s GOES BUST." % _name(d["seat"]))
			world.announce("%s\nGOES BUST" % _name(d["seat"]))
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
			world.play_item(d["item"], d["seat"], d["target"])
			if d["item"] == "flashbang":
				get_tree().create_timer(0.95).timeout.connect(_flash.bind(Color.WHITE))
		"damage":
			_log("%s is down to %d health." % [_name(d["seat"]), d["hp"]])
		"eliminated":
			_log("%s IS OUT." % _name(d["seat"]))
		"blackjack_shot":
			_log("BLACKJACK! %s shoots the dealer, %s." % [_name(d["shooter"]), _name(d["target"])])
			_blackjack_shot_fx(int(d["shooter"]), int(d["target"]))
		"gun_passed":
			_log("%s picks up the shotgun: %d shell%s." % [_name(d["seat"]), d["shells"], "" if d["shells"] == 1 else "s"])
		"stock_reshuffled":
			_log("The discard pile is shuffled into a new stock.")
		"round_end":
			if _blackjack():
				for sh in d.get("shooters", []):
					world.cheer(sh[0])
				_log("%s the dealer has %s." % [_name(d["dealer"]), "BUST" if d["dealer_bust"] else str(d["dealer_total"])])
				for duel in d.get("duels", []):
					var verdict: String = {"win": "beats the dealer", "lose": "loses to the dealer", "push": "pushes"}.get(duel["outcome"], "")
					_log("%s %s%s." % [_name(duel["seat"]), verdict, " (%d shell%s)" % [duel["shells"], "" if duel["shells"] == 1 else "s"] if duel["shells"] > 0 else ""])
				if d["dealer_shells"] > 0:
					_log("The dealer gets %d shell%s." % [d["dealer_shells"], "" if d["dealer_shells"] == 1 else "s"])
			elif d["winner"] >= 0:
				world.cheer(d["winner"])
			if _blackjack():
				pass
			elif d["winner"] < 0:
				_log("The deck ran dry. Nobody scores.")
			else:
				_log("%s goes out%s: %d points, %d shell%s." % [_name(d["winner"]), " with RUMMY" if d["rummy"] else "", d["points"], d["shells"], "" if d["shells"] == 1 else "s"])
		"shot":
			_log("%s shoots %s.%s" % [_name(d["shooter"]), _name(d["target"]), " CLICK: a blank." if d.get("blank", false) else ""])
			if _online() and d.get("blank", false):
				world.fire(d["shooter"], d["target"], true)
				_last_shot_text = "CLICK. A BLANK. %s lives." % _name(d["target"])
			elif _online():
				# every phone feels it; the target's phone most of all
				world.fire(d["shooter"], d["target"])
				if d["target"] == _me():
					_flash(Palette.RED)
					_shake()
				else:
					_flash(Color.WHITE)
				_last_shot_text = "BANG. %s shoots %s." % [_name(d["shooter"]), _name(d["target"])]
		"match_end":
			if game.options["shotgun"] and not tutorial:
				played[game.kind] = int(played.get(game.kind, 0)) + 1
				_save_settings()
				if int(played[game.kind]) == Games.UNLOCK_NORMAL_AFTER:
					_log("NORMAL MODE UNLOCKED for %s." % Games.label(game.kind))
			if d["winner"] >= 0:
				_log("%s WALKS OUT." % _name(d["winner"]))


## Every game event's sound.
func _event_sound(kind: String, d: Dictionary) -> void:
	match kind:
		"round_start":
			_sound("shuffle")
		"turn_start":
			if game != null and int(d.get("seat", -1)) == _me() and not _is_bot(int(d.get("seat", -1))):
				get_tree().create_timer(0.25).timeout.connect(_sound.bind("your_turn"))
		"turn_skipped":
			_sound("item_handcuffs")
		"loot":
			_sound("pick_item")
		"draw", "hit", "flip", "trick_card", "board":
			_sound("flick")
		"discard", "play", "president_play":
			_sound("slap" if kind == "president_play" else "flick")
		"meld", "layoff", "book", "trick_won":
			_sound("slap")
		"swap":
			_sound("item_switcheroo")
		"stock_reshuffled":
			_sound("shuffle")
		"trump_changed":
			_sound("item_tarot")
		"item_used":
			_sound("item_" + str(d.get("item", "")))
		"heal":
			_sound("heal")
		"damage":
			_sound("hurt")
		"eliminated":
			get_tree().create_timer(0.3).timeout.connect(_sound.bind("eliminated"))
		"round_end":
			_sound("cheer" if int(d.get("winner", -1)) >= 0 else "buzzer")
			if d.get("shells", 0) > 0 and game != null and game.options["shotgun"]:
				get_tree().create_timer(0.8).timeout.connect(_sound.bind("rack"))
		"gun_passed":
			_sound("rack")
		"gun_empty":
			_sound("close")
		"shot":
			_sound("click" if d.get("blank", false) else "blast")
		"roulette":
			_sound("spin")
			get_tree().create_timer(0.55).timeout.connect(_sound.bind("blast" if d.get("hit", false) else "click"))
			if not d.get("hit", false):
				get_tree().create_timer(0.9).timeout.connect(_sound.bind("survive"))
		"blackjack_shot":
			_sound("sparkle")
			get_tree().create_timer(0.3).timeout.connect(_sound.bind("blast"))
		"match_end":
			_sound("fanfare")
		# Blackjack
		"stand":
			_sound("knock")
		"bust":
			_sound("buzzer")
		# Go Fish
		"ask":
			_sound("slap" if int(d.get("count", 0)) > 0 else "tap")
		"go_fish":
			_sound("sparkle" if d.get("lucky", false) else "splash")
		# Cheat
		"called":
			_sound("sting")
			get_tree().create_timer(0.5).timeout.connect(_sound.bind("buzzer" if d.get("lie", false) else "ding"))
		"let_go":
			_sound("tap")
		# Hearts and Spades
		"hearts_broken", "spades_broken":
			_sound("crack")
		"queen_taken":
			_sound("doom")
		"bid":
			_sound("chips")
		# Snap
		"snap":
			_sound("pop" if d.get("good", false) else "buzzer")
			if d.get("good", false):
				_sound("slap")
		# President
		"pass":
			_sound("knock")
		"pile_cleared":
			_sound("sweep")
		"exchange":
			_sound("coin")
		# Poker
		"bet":
			match str(d.get("action", "")):
				"check":
					_sound("knock")
				"call":
					_sound("chips")
				"raise":
					_sound("rack")
				"fold":
					_sound("close")


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
			if overlay_layer.get_child_count() == 0:
				# something closed the results: bring back what's next
				_refresh()
				if game.gun != null:
					_show_gun(_last_shot_text)
				else:
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
				var private := hide_hands and _people_alive() > 1 and game.has_private_hands()
				if _is_bot(game.turn):
					# the AI plays while the phone waits for the next person
					shown_turn = turn_counter
					if private:
						_hand_hidden = true
				else:
					var new_hands := game.turn != _viewer
					_viewer = game.turn
					if private and (new_hands or _hand_hidden):
						_hand_hidden = true
						_refresh()
						_pass_after_deal()
						return
					_hand_hidden = false
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
			elif _overlay_kind == "gun" or overlay_layer.get_child_count() == 0:
				_refresh()
				if game.gun != null or _overlay_kind == "gun":
					_show_gun(_last_shot_text)
				else:
					_show_round_result()
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
		_sound("error")
		message = res["error"]
		_refresh()
		return false
	message = ""
	selected = []
	return true


# ================================================================ blackjack

const BLACKJACK_RULES := [
	"THE TABLE. 2 to 6 players, on one phone or in a lobby. One player is the dealer, and everyone else plays against them. The player to the dealer's left goes first, play goes round to the left, and the dealer plays last. Next round the deal moves one seat to the right.",
	"THE DEAL. Everyone gets 2 cards, one face down and one face up. Items are rare: only 3 are shuffled into the stock each round. The deck is shuffled fresh every round.",
	"YOUR TURN. HIT to take a card (tap the stock or press HIT), as often as you like, then STAND. Use items any time in your turn. If you draw an item, keep it and draw again. 21 or 5 cards stands for you.",
	"COUNTING. 2 to 10 count their number, J Q K count 10, an ace counts 1 or 11. Go over 21 and you're BUST.",
	"AGAINST THE DEALER. Bust and you lose. If the dealer goes bust, everyone still in wins. Otherwise the better hand wins: a BLACKJACK (21 with your first 2 cards) beats a FIVE-CARD CHARLIE (5 cards without going bust), which beats the higher total. The same hand is a push. If every player goes bust, the dealer wins without playing.",
	"BLACKJACK SHOOTS. The moment you have a Blackjack, you shoot the dealer, free.",
	"THE SHOTGUN. The dealer gets 1 shell for every player who lost (max 3) and picks who to shoot, but only players who lost. Beat the dealer or push and you're safe. Each shell takes 1 health. Everyone starts with 4, and health carries over. Hit 0 and you're out. Last one standing walks out.",
]


## A Blackjack's free shot at the dealer, played once the cards are dealt.
func _blackjack_shot_fx(shooter: int, target: int) -> void:
	if world.dealing:
		await world.deal_finished
	if game == null:
		return
	world.announce("BLACKJACK!\n%s SHOOTS THE DEALER" % _name(shooter))
	world.fire(shooter, target)
	if target == _me():
		_flash(Palette.RED)
		_shake()
	else:
		_flash(Color.WHITE)


## The tutorial's tip line.
func _refresh_coach() -> void:
	if coach_label == null:
		return
	coach_label.visible = tutorial and demo_stage == "practice" and not _hand_hidden
	if not coach_label.visible:
		return
	var tip := ""
	if mode_ui != null:
		tip = mode_ui.coach()
	elif _blackjack():
		tip = _coach_blackjack()
	else:
		tip = _coach_rummy()
	coach_label.text = "TIP: " + tip if tip != "" else ""


func _coach_rummy() -> String:
	if game.phase != "draw" and game.phase != "play":
		return ""
	if not _my_turn():
		return "Watch what the others pick up from the discard pile: it tells you what they're collecting."
	var seat := _me()
	if game.phase == "draw":
		var top: Dictionary = game.top_discard()
		if not top.is_empty() and Bot.helps(game, game.players[seat].hand, top):
			return "The top of the discard pile helps you: tap it to take it."
		return "Start by drawing: tap the stock (face down) or the discard pile."
	if not game.can_place(seat):
		return "First turn: you can't put cards down yet. Tap one card you don't need, then DISCARD."
	if game.go_out_check(seat)["can"]:
		return "You can go out! Meld everything, then discard your last card."
	var best: Dictionary = Cards.best_partition(game.players[seat].hand, game.trump_rank)
	if not best["melds"].is_empty():
		return "Gold-outlined cards make a meld. Tap them, then MELD."
	return "Nothing to meld. Tap your least useful card (a high one), then DISCARD."


func _coach_blackjack() -> String:
	if game.phase != "play" or not _my_turn():
		return "Everyone plays against the dealer. Beat their total without going over 21."
	var seat := _me()
	var t: int = game.hand_total(seat)
	if seat == game.dealer:
		return "You're the dealer: you play last and can see everyone's face-up cards. Try to beat them."
	if t <= 11:
		return "%d can't go bust with one more card. HIT." % t
	if t >= 17:
		return "%d is strong. STAND and let the dealer try to beat it." % t
	return "%d is in the middle. If the dealer shows 7 or more, HIT; if 2 to 6, STAND and hope they bust." % t


func _refresh_blackjack() -> void:
	var seat := _me()
	var me = game.players[seat]
	var my_turn := _my_turn()
	round_label.text = "ROUND %d · %s DEALS" % [game.round_num, _name(game.dealer)]
	me_name.text = me.name + _flags(me)
	_clear(me_hp)
	me_hp.add_child(_hp_bar(me))
	var t: int = game.hand_total(seat)
	deadwood_label.text = ("BUST %d" % t if me.bust else "TOTAL %d" % t) if not me.hand.is_empty() else ""
	var can_play: bool = my_turn and game.phase == "play"
	world.sync({
		"game": game, "viewer": seat, "hand": me.hand.duplicate(), "selected": [], "selected_item": selected_item,
		"meld_hints": {}, "lay_hints": {}, "lit": lit_card, "can_draw": can_play, "targets": {},
		"hide_hand": _hand_hidden,
	})
	meld_btn.disabled = not can_play
	discard_btn.disabled = not can_play
	use_btn.disabled = not (my_turn and selected_item != "" and game.item_blocker(seat, selected_item) == "")
	status_label.add_theme_color_override("font_color", Palette.PINK if message != "" else Palette.AMBER)
	status_label.text = _status_text([], false)
	go_out_label.visible = can_play and t == 21
	go_out_label.text = "BLACKJACK!" if game.is_blackjack(seat) else "21! STAND ON IT"


func _status_blackjack() -> String:
	if game.phase != "play":
		return "ROUND OVER"
	if world.dealing:
		return "SHUFFLING AND DEALING..."
	var seat := _me()
	var me = game.players[seat]
	if not _my_turn():
		var who := "%s IS THINKING..." % _name(game.turn) if _is_bot(game.turn) else "WAITING FOR %s..." % _name(game.turn)
		if me.bust:
			return "YOU'RE BUST. " + who
		if me.stood:
			return "YOU STAND ON %d. %s" % [game.hand_total(seat), who]
		return who
	if selected_item != "":
		var item := game.find_item(seat, selected_item)
		if not item.is_empty():
			var def := Items.def(item["item"])
			var blocker := game.item_blocker(seat, selected_item)
			return "%s: %s%s" % [str(def["name"]).to_upper(), def["text"], " (%s)" % blocker if blocker != "" else ""]
	if me.ultimatum:
		return "REVOLVER: TAKE A CARD THIS TURN, OR STAND AND SPIN THE CYLINDER"
	if seat == game.dealer:
		return "YOU'RE THE DEALER. YOU HAVE %d. HIT OR STAND" % game.hand_total(seat)
	return "YOU HAVE %d. DEALER SHOWS %d. HIT OR STAND" % [game.hand_total(seat), game.showing_total(game.dealer)]


func _hit() -> void:
	if not _my_turn() or game.phase != "play":
		return
	_act("hit", [], _after_hit)


func _after_hit(res: Dictionary) -> void:
	if not _handle(res):
		return
	lit_card = res.get("card", {}).get("id", "")
	_after_action()


func _stand() -> void:
	if not _my_turn() or game.phase != "play":
		return
	lit_card = ""
	_act("stand", [], _after_simple)


func _show_blackjack_result() -> void:
	var r := game.last_result
	var box := _open_overlay(0.94, true, "result")
	var dealer_seat: int = r["dealer"]
	box.add_child(_title("%s DEALT: %s" % [_name(dealer_seat), "BUST" if r["dealer_bust"] else str(r["dealer_total"])], Palette.AMBER))
	for h in r["hands"]:
		var line := ""
		var color := Palette.INK
		var total_text := "BUST (%d)" % h["points"] if h.get("bust", false) else str(h["points"])
		if h.get("blackjack", false) and not h.get("bust", false):
			total_text = "BLACKJACK"
		elif h.get("charlie", false) and not h.get("bust", false):
			total_text = "%d, FIVE-CARD CHARLIE" % h["points"]
		match h.get("outcome", ""):
			"dealer":
				line = "%s (DEALER): %s" % [h["name"], total_text]
				color = Palette.AMBER
			"win":
				line = "%s: %s. BEATS THE DEALER, SAFE" % [h["name"], total_text]
				color = Palette.GOLD
			"lose":
				line = "%s: %s. LOSES" % [h["name"], total_text]
				color = Palette.PINK
			_:
				line = "%s: %s. PUSH" % [h["name"], total_text]
		box.add_child(_label(line, 24, color))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		for c in h["cards"]:
			var cv := CardView.new()
			cv.setup(c, Vector2(52, 76))
			cv.trump = game.is_trump(c)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flow.add_child(cv)
		box.add_child(flow)
	var shooters: Array = r.get("shooters", [])
	if shooters.is_empty():
		box.add_child(_label(str(r.get("reason", "Nobody shoots.")), 26, Palette.INK, true))
	else:
		var losers := []
		for s in r.get("losers", []):
			losers.append(_name(s))
		var n: int = shooters[0][1]
		box.add_child(_label("THE DEALER GETS %d SHELL%s TO SHOOT %s" % [n, "" if n == 1 else "S", ", ".join(losers)], 28, Palette.RED.lightened(0.3), true))
		box.add_child(_label("(1 shell for each player who lost, max 3. Only players who lost can be shot.)", 20, Palette.DIM, true))
	_add_result_buttons(box, int(game.gun["holder"]) if game.gun != null else -1)


# ================================================================ AI players

## Seconds the AI waits after each kind of move, so you can follow along.
const AI_PACE := {"use_item": 1.3, "draw_stock": 0.9, "draw_discard": 1.0, "meld": 1.1, "lay_off": 1.0, "discard": 1.4, "shoot": 2.2, "flip": 1.5, "finish": 1.5}


func _process(delta: float) -> void:
	_drive_lessons(delta)
	_drive_demo(delta)
	_drive_ai(delta)


## The AI seat that has a move to make right now, or -1.
func _ai_seat() -> int:
	if game == null or round_label == null:
		return -1
	if game.phase == "shoot" and game.gun != null:
		var holder := int(game.gun["holder"])
		return holder if _is_bot(holder) else -1
	if (game.phase == "draw" or game.phase == "play") and _is_bot(game.turn):
		return game.turn
	return -1


## Plays the AIs, one move at a time. In pass-and-play this phone runs them;
## online the host does, and everyone sees the moves like anyone else's.
func _drive_ai(delta: float) -> void:
	if game == null or round_label == null or (_online() and not session.is_host()):
		return
	if game.kind == "snap":
		_drive_snaps(delta)
	var seat := _ai_seat()
	if game.phase != _ai_phase:
		_ai_phase = game.phase
		if game.phase == "shoot":
			# let everyone read the result first
			_ai_wait = 3.5 if _online() else 1.2
	if seat < 0:
		_ai_wait = maxf(_ai_wait, 0.8)
		return
	if world.dealing or world.fx_busy or _pending_cb.is_valid() or _lesson_showing():
		return
	if not _online():
		# wait while the rules, log or menu are open, and for the gun to come out
		if game.phase == "shoot":
			if _overlay_kind != "gun" or overlay_layer.get_child_count() == 0:
				return
		elif overlay_layer.get_child_count() > 0:
			return
	_ai_wait -= delta
	if _ai_wait > 0.0:
		return
	var memory: Dictionary = _ai_memory.get_or_add(seat, {})
	var act := Bot.next_action(game, seat, game.players[seat].bot, memory)
	if act.is_empty():
		_ai_wait = 0.5
		return
	_ai_wait = float(AI_PACE.get(act[0], 1.0))
	if demo_stage == "watch":
		_ai_wait *= 1.5 # slow enough to follow
	elif _people_alive() == 0:
		_ai_wait *= 0.4 # nobody left to watch closely
	var res: Dictionary
	if _online():
		res = session.act_as(seat, act[0], act[1])
	else:
		res = Session.perform(game, seat, act[0], act[1], true)
	if not res.get("ok", false):
		Bot.note_failure(memory, act)
		_ai_wait = 0.1
		if not _online():
			_after_action()
		return
	if _online():
		return # the update has already redrawn everything
	if act[0] == "shoot":
		_after_fire(res, seat, int(act[1][0]))
	else:
		_after_action()


var _snap_flips := -1
var _snap_timers := {} # AI seat -> seconds until it snaps


## Snap: the AIs snap out of turn. Each flip gives every AI a reaction time;
## the quickest one snaps (easy ones sometimes snap at nothing).
func _drive_snaps(delta: float) -> void:
	if game.phase != "play" or world.dealing or _pending_cb.is_valid():
		return
	if not _online() and overlay_layer.get_child_count() > 0:
		return
	if game.flips != _snap_flips:
		_snap_flips = game.flips
		_snap_timers = {}
		for p in game.players:
			if not p.alive or p.bot == "":
				continue
			if game.snap_ready():
				_snap_timers[p.seat] = SnapBot.reaction(game, p.bot)
			elif game.rng.randf() < SnapBot.false_snap_chance(p.bot):
				_snap_timers[p.seat] = game.rng.randf_range(0.4, 1.0)
	if not game.snap_ready() and game.discard_pile.size() < 2:
		_snap_timers = {}
	for s in _snap_timers.keys():
		_snap_timers[s] -= delta
		if _snap_timers[s] <= 0.0:
			_snap_timers = {}
			if _online():
				session.act_as(s, "snap", [])
			else:
				Session.perform(game, s, "snap", [], true)
				_after_action()
			return


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

	# tutorial tips
	coach_label = _label("", 24, Palette.INK, true)
	coach_label.add_theme_color_override("font_outline_color", Color.BLACK)
	coach_label.add_theme_constant_override("outline_size", 8)
	coach_label.visible = false
	col.add_child(coach_label)

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
	if _blackjack():
		meld_btn.text = "HIT"
		discard_btn.text = "STAND"
		minor.visible = false
	mode_ui = _make_mode_ui()
	if not game.options["shotgun"]:
		use_btn.visible = false # normal mode has no items
	if mode_ui != null:
		minor.visible = false
		var specs: Array = mode_ui.buttons()
		var btns := [meld_btn, use_btn, discard_btn]
		for i in range(btns.size()):
			var b: Button = btns[i]
			var spec: Array = specs[i] if i < specs.size() else ["", Callable(), null]
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c["callable"])
			b.text = spec[0]
			b.visible = spec[0] != "" and (b != use_btn or game.options["shotgun"])
			b.pressed.connect(_sound.bind("tick"))
			if spec[1].is_valid():
				b.pressed.connect(spec[1])
			if spec[2] != null:
				Palette.accent(b, spec[2])


## The table screen for games that bring their own (scripts/ui/modes).
func _make_mode_ui():
	match game.kind:
		"gofish":
			return GoFishUI.new(self)
		"cheat":
			return CheatUI.new(self)
		"hearts", "spades":
			return TricksUI.new(self)
		"snap":
			return SnapUI.new(self)
		"president":
			return PresidentUI.new(self)
		"poker":
			return PokerUI.new(self)
	return null


## A tap on the table: find the card under it in 3D.
func _on_table_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if game == null or overlay_layer.get_child_count() > 0 or world.dealing or world.fx_busy:
		return
	var hit: Dictionary = world.pick(_to_view(event.position))
	if mode_ui != null:
		mode_ui.on_pick(hit)
		return
	if _blackjack():
		match hit.get("kind", ""):
			"item":
				_toggle_item(hit["id"])
			"stock":
				_hit()
		return
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
	_refresh_coach()
	if mode_ui != null:
		mode_ui.refresh()
		return
	if _blackjack():
		_refresh_blackjack()
		return
	var seat := _me()
	var me = game.players[seat]
	var my_turn := _my_turn()

	round_label.text = "ROUND %d · %s DEALS" % [game.round_num, _name(game.dealer)]

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
	if mode_ui != null:
		return mode_ui.status()
	if _blackjack():
		return _status_blackjack()
	if game.phase != "draw" and game.phase != "play":
		return "ROUND OVER"
	var seat := _me()
	if world.dealing:
		return "SHUFFLING AND DEALING..."
	if not _my_turn():
		if _is_bot(game.turn):
			return "%s IS THINKING..." % _name(game.turn)
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
	_sound("tap")
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
	_sound("pick_item")
	if not _my_turn():
		message = "It's %s's turn." % _name(game.turn)
		_refresh()
		return
	selected_item = "" if selected_item == id else id
	message = ""
	_refresh()


func _meld_selected() -> void:
	if _blackjack():
		_hit()
	elif _my_turn():
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
	if _blackjack():
		_stand()
		return
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
		"meld_card", "hand_card", "table_card":
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
			text = ("%s's face-down card:" if _blackjack() else "%s is holding:") % _name(target)
		"adrenaline":
			text = "You stole:"
		"joker_paint":
			text = "A trump for the rest of the round: it's worth whatever you need." if _blackjack() else "Wild until your turn ends. Meld it to keep it wild."
		"sticky_fingers":
			text = str(res["text"]) + ". It's in your hand."
	if shown.is_empty():
		shown = item
	_refresh()
	# let the item's animation play before the pop-up
	await get_tree().create_timer(1.4).timeout
	if game == null:
		return
	if overlay_layer.get_child_count() > 0 or not (game.phase == "draw" or game.phase == "play"):
		_after_action() # the round moved on while the animation played
		return
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
	if kind != "pass" and kind != "gun":
		_sound("open")
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
	_sound("pass_phone")
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
	if Items.needs(item["item"]) == "table_card":
		box.add_child(_label("WHICH CARD?", 26, Palette.DIM, true))
		for p in game.others(_me()):
			var theirs := []
			for c in p.hand:
				if choices.has(c["id"]):
					theirs.append(c)
			if theirs.is_empty():
				continue
			box.add_child(_label("%s:" % p.name, 22, Palette.DIM))
			box.add_child(_card_buttons(theirs, item))
	elif Items.needs(item["item"]) == "meld_card":
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
	if _blackjack():
		_show_blackjack_result()
		return
	if mode_ui != null:
		var mbox := _open_overlay(0.94, true, "result")
		mode_ui.show_result(mbox)
		_add_result_buttons(mbox, int(game.gun["holder"]) if game.gun != null else int(game.last_result.get("winner", -1)))
		return
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
	_add_result_buttons(box, w)


## The shotgun (or what's next) under a round's result.
func _add_result_buttons(box: VBoxContainer, w: int) -> void:
	if game.gun != null:
		var mine: bool = (not _online() or int(game.gun["holder"]) == _me()) and not _is_bot(int(game.gun["holder"]))
		var b := _button("%s, PICK UP THE SHOTGUN" % _name(w) if mine else "WATCH %s SHOOT" % _name(w), _show_gun)
		Palette.accent(b, Palette.RED)
		box.add_child(b)
	elif game.phase == "match_over":
		box.add_child(_button("CONTINUE", _show_match_end))
	else:
		_add_next_round(box)


## NEXT ROUND button, or a waiting note on phones that aren't the host.
func _add_next_round(box: VBoxContainer) -> void:
	if demo_stage == "practice" and game.round_num >= DEMO_ROUNDS:
		box.add_child(_button("FINISH THE DEMO", _closing(_finish_demo)))
		return
	if demo_stage == "watch":
		box.add_child(_label("The demo carries on by itself...", 24, Palette.DIM, true))
		return
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
		total = int(game.gun.get("total", total))
	var box := _open_overlay(0.2, false, "gun", true)
	var shooter: int = holder if holder >= 0 else int(game.last_result["winner"])
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

	if holder >= 0 and ((_online() and holder != _me()) or _is_bot(holder)):
		var waiting := "%s is picking a target..." % _name(holder) if _is_bot(holder) else "Waiting for %s to pick a target..." % _name(holder)
		box.add_child(_label(waiting, 26, Palette.INK, true))
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
		var allowed: Array = game.gun.get("targets", []) if game.gun != null else []
		if not allowed.is_empty():
			box.add_child(_label("You can only shoot players who stayed in." if game.kind == "poker" else "You can only shoot players who lost to you.", 22, Palette.DIM, true))
		for p in game.others(holder):
			if not allowed.is_empty() and not allowed.has(p.seat):
				continue
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
	var blank: bool = int(res["damage"]) == 0
	if not _online():
		world.fire(shooter, target, blank)
		if not blank:
			_flash(Color.WHITE)
			_shake()
	var text := "BANG. %s takes %d." % [_name(target), res["damage"]]
	if blank:
		text = "CLICK. A BLANK. %s lives." % _name(target)
	if not game.players[target].alive:
		text = "BANG. %s is out." % _name(target)
	_last_shot_text = text
	_refresh()
	_show_gun(text)


func _show_match_end() -> void:
	if demo_stage == "practice":
		_finish_demo()
		return
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
		box.add_child(_button("NEW PLAYERS", _closing(_new_players)))
		box.add_child(_button("MAIN MENU", show_menu))


func _play_again_online() -> void:
	_close_overlay()
	_act("play_again", [], _ignore_result)


func _show_rules() -> void:
	var box := _open_overlay(0.96, true, "rules")
	box.add_child(_title("RULES"))
	var lines: Array = mode_ui.rules() if mode_ui != null else (BLACKJACK_RULES if _blackjack() else [
		"THE TABLE. 2 to 6 players, either passing one phone around (PASS & PLAY) or each on their own phone in a lobby on the same Wi-Fi. One player deals each round and the player to their left goes first. Next round the deal moves one seat to the right, so whoever dealt goes first.",
		"THE DEAL. Everyone gets 7 playing cards. Nobody starts with items: just 3 item cards are shuffled into the stock each round, so a draw from it can now and then give you an item instead of a playing card.",
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
	])
	box.add_child(_title(_game_title(game.kind, not game.options["shotgun"])))
	if not game.options["shotgun"]:
		lines = lines.duplicate()
		lines.append("NORMAL MODE. No items and no shotgun: win the round to score, and the first to %d rounds wins the match." % game.options["rounds_to_win"])
	for line in lines:
		box.add_child(_label(line, 24, Palette.INK))
	if not game.options["shotgun"]:
		box.add_child(_button("BACK", _closing(_after_action)))
		return
	box.add_child(_label("ITEMS (use as many as you like, any time in your turn)", 28, Palette.PURPLE.lightened(0.3)))
	for id in Items.DEFS:
		var d: Dictionary = Items.def(id)
		if int(d["copies"]) <= 0:
			continue
		box.add_child(_label("%s %s ×%d: %s" % [d["icon"], d["name"], d["copies"], d["text"]], 24, Palette.INK))
	box.add_child(_button("BACK", _closing(_after_action)))


func _pause_sound() -> void:
	_toggle_sound()
	_close_overlay()
	_show_menu()


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
	box.add_child(_button("GRAPHICS: %s" % graphics, _cycle_graphics))
	box.add_child(_button("SOUND: %s" % ("ON" if sound_on else "OFF"), _pause_sound))
	if _online():
		box.add_child(_label("Leaving ends the game for everyone.", 24, Palette.DIM, true))
		box.add_child(_button("LEAVE THE GAME", show_menu))
	else:
		box.add_child(_button("RESTART MATCH", _closing(start_match)))
		box.add_child(_button("NEW PLAYERS", _closing(_new_players)))
		box.add_child(_button("MAIN MENU", show_menu))
