extends "res://scripts/ui/modes/table_mode.gd"
## Darts at the board. On your throw a red line crosses the board through the
## bull with a dot running along it: tap to stop the dot. A second line then
## crosses through that spot at another angle: tap again and the dart flies
## to wherever that dot is. Each dart of your visit, the dots get quicker.
## The AIs aim the same way, and you see their lines too.
##
## No buttons: the whole screen is the tap. Scores float over the board.

const Darts = preload("res://scripts/core/darts.gd")
const DartsAim = preload("res://scripts/ui/darts_aim.gd")

const BASE_PERIOD := 1.9 # seconds end to end and back, for the first dart
const QUICKER := 0.8 # each dart after that

var aim: Control # darts_aim.gd
var _board_words: VBoxContainer # the scoreboard, floating at the top
var _pop: Label # "TREBLE 20!" over the board
var _clear_at := 0 # msec: the last visit's darts come out of the board then
var _ghosting := false
var _wait := 0.0 # a beat after each dart before the next aim


func _init(m) -> void:
	super(m)
	aim = DartsAim.new()
	aim.to_screen = _to_screen
	aim.visible = false
	main.add_child(aim)
	main.move_child(aim, main.settings_layer.get_index())
	_board_words = VBoxContainer.new()
	_board_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_words.add_theme_constant_override("separation", -4)
	main.add_child(_board_words)
	main.move_child(_board_words, main.settings_layer.get_index())
	_pop = main._label("", 64, main.FLOAT_YELLOW, true)
	_pop.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01))
	_pop.add_theme_constant_override("outline_size", 14)
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop.modulate.a = 0.0
	main.add_child(_pop)
	main.move_child(_pop, main.settings_layer.get_index())
	aim.set_process(true)
	main.get_tree().process_frame.connect(_tick)


func buttons() -> Array:
	return [] # the screen is the button


func _to_screen(p: Vector2) -> Vector2:
	var v: Vector2 = main.world.board_to_view(p)
	return v * main.view_rect.size / Vector2(main.view3d.size)


func clear() -> void:
	if main.get_tree().process_frame.is_connected(_tick):
		main.get_tree().process_frame.disconnect(_tick)
	for n in [aim, _board_words, _pop]:
		if n != null and is_instance_valid(n):
			n.queue_free()


func _my_throw() -> bool:
	var g = main.game
	return g != null and g.phase == "play" and main._my_turn() and not main._is_bot(g.turn)


## Every frame: start aiming when it's your throw and the board's ready.
func _tick() -> void:
	if main.game == null or not is_instance_valid(aim) or main.mode_ui != self or main.round_label == null or not is_instance_valid(main.round_label) or not is_instance_valid(main.meld_btn):
		return # the table's gone (back to the room)
	var w = main.world
	var ready: bool = w.darts_viewing() and not w.camera_moving() and not w.fx_busy and main.overlay_layer.get_child_count() == 0 and not main._lesson_showing() and not main._settings_open()
	if _clear_at > 0 and Time.get_ticks_msec() >= _clear_at:
		_clear_at = 0
		main.world.clear_darts()
		main._sound("flick")
	if _wait > 0.0:
		_wait -= main.get_process_delta_time()
		return
	if _my_throw() and ready and aim.stage == "" and not _ghosting:
		var g = main.game
		aim.begin(randf() * PI, BASE_PERIOD * pow(QUICKER, g.dart_index()))
		main._refresh()
	elif not _my_throw() and aim.stage != "" and not aim.ghost:
		aim.hide_aim()


## A tap anywhere on the table while you're aiming.
func table_tap(_at: Vector2) -> bool:
	if aim.stage == "" or aim.ghost or not _my_throw():
		return false
	var a2: float = aim.a1 + deg_to_rad(randf_range(45.0, 135.0)) * (1.0 if randf() < 0.5 else -1.0)
	if aim.stop(a2):
		var land: Vector2 = aim.landing()
		main._sound("whoosh")
		main._act("throw", [land.x, land.y], main._after_simple)
	else:
		main._sound("lock")
		main._refresh()
	return true


## AIs aim the same way: their lines play out, then the dart goes.
func preview_bot(seat: int, act: Array) -> bool:
	if act.is_empty() or act[0] != "throw" or not main.world.darts_viewing():
		return false
	_ghosting = true
	var g = main.game
	var land := Vector2(float(act[1][0]), float(act[1][1]))
	var speed: float = BASE_PERIOD * pow(QUICKER, g.dart_index()) * (0.7 if main.demo_stage != "watch" else 1.0)
	aim.play_ghost(land, speed, func() -> void:
		_ghosting = false
		main._sound("whoosh"))
	return true


func revealing() -> bool:
	return _ghosting or _clear_at > 0 or main.world.camera_moving()


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	main.round_label.text = "ROUND %d · %s" % [g.round_num, Darts.MODE_NAMES[g.mode()]]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = _score_text(g, seat)
	main.world.sync({
		"game": g, "viewer": seat, "hand": [], "selected": [], "selected_item": "",
		"meld_hints": {}, "lay_hints": {}, "lit": "", "can_draw": false, "targets": {},
		"hide_hand": true,
	})
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false
	_draw_scores(g)


func _score_text(g, seat: int) -> String:
	if not g.scores.has(seat):
		return ""
	match g.mode():
		"301":
			return "%d LEFT" % g.scores[seat]
		"clock":
			return "ON %s" % ("THE BULL" if int(g.scores[seat]) > 20 else str(g.scores[seat]))
	return "%d" % g.scores[seat]


## The scoreboard: everyone's score in floating words over the top.
func _draw_scores(g) -> void:
	if not is_instance_valid(_board_words):
		return
	for c in _board_words.get_children():
		c.queue_free()
	_board_words.visible = g.phase == "play"
	var vs: Vector2 = main.get_viewport_rect().size
	_board_words.position = Vector2(20, 150)
	_board_words.size = Vector2(vs.x - 40, 0)
	for p in g.players:
		if not p.alive or not g.scores.has(p.seat):
			continue
		var up: bool = p.seat == g.turn
		var out: bool = g.mode() == "shootout" and not g.contenders.has(p.seat)
		var text := "%s%s  %s" % ["► " if up else "   ", p.name, _score_text(g, p.seat)]
		if up:
			text += "   " + "● ".repeat(g.darts_left).strip_edges()
		var l: Label = main._label(text, 30 if up else 24, main.FLOAT_YELLOW if up else (Palette.DIM if out else Palette.INK))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_board_words.add_child(l)


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "ROUND OVER"
	if not main._my_turn() or main._is_bot(g.turn):
		return "%s IS THROWING..." % main._name(g.turn)
	match aim.stage:
		"line1":
			return "DART %d: TAP TO STOP THE DOT" % (g.dart_index() + 1)
		"line2":
			return "DART %d: TAP TO THROW" % (g.dart_index() + 1)
	return "YOUR THROW: DART %d OF 3" % (g.dart_index() + 1)


func on_pick(_hit: Dictionary) -> void:
	pass


func _popup(text: String, color: Color) -> void:
	if not is_instance_valid(_pop):
		return
	var vs: Vector2 = main.get_viewport_rect().size
	_pop.text = text
	_pop.add_theme_color_override("font_color", color)
	_pop.size = Vector2(vs.x, 80)
	_pop.position = Vector2(0, vs.y * 0.66)
	_pop.modulate.a = 1.0
	_pop.scale = Vector2.ONE
	var t := _pop.create_tween()
	t.tween_property(_pop, "position:y", vs.y * 0.62, 0.9)
	t.parallel().tween_property(_pop, "modulate:a", 0.0, 0.9).set_delay(0.5)


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"turn_start":
			# a beat to see where the last darts landed, then the board's cleared
			# for the next thrower (nobody aims till it is)
			_clear_at = Time.get_ticks_msec() + 900
			_wait = maxf(_wait, 0.8)
		"dart":
			main.world.throw_dart(Vector2(float(d["x"]), float(d["y"])), int(d["seat"]))
			_wait = 0.45
			var label: String = d["label"]
			var words: String = {"BULL": "BULLSEYE!", "25": "OUTER BULL", "MISS": "MISSED!"}.get(label, "")
			if words == "":
				words = ("TREBLE " if label.begins_with("T") else ("DOUBLE " if label.begins_with("D") else "")) + str(d["num"])
			var color: Color = main.FLOAT_YELLOW
			if label == "BULL":
				color = Palette.GOLD
			elif label == "MISS":
				color = Palette.DIM
			elif label.begins_with("T"):
				color = Color(1.0, 0.4, 0.35)
			if d.get("note", "") == "next":
				words += " ✓"
			_popup(words, color)
			main._log("%s: %s" % [main._name(d["seat"]), words])
		"bust":
			_popup("BUST!", Palette.RED)
			main._sound("bust")
			main._log("%s busts. Back to %d." % [main._name(d["seat"]), d["score"]])
		"visit_end":
			main._log("%s scores %d." % [main._name(d["seat"]), d["total"]])
		"sudden_death":
			main.world.announce("SUDDEN DEATH!")
			main._log("A tie on %d: sudden death." % d["score"])


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	box.add_child(main._label(Darts.MODE_NAMES[g.mode()], 56, Palette.GOLD, true))
	box.add_child(main._title("%s WINS" % main._name(w), Palette.AMBER))
	if g.options["shotgun"]:
		var why := {"shootout": "(1, or 2 with a bullseye)", "clock": "(around the clock pays 2)", "301": "(301 pays 4: enough to finish someone)"}
		box.add_child(main._label("%d shell%s in the shotgun. %s" % [r["shells"], "" if r["shells"] == 1 else "s", why[g.mode()]], 24, Palette.INK, true))
	for h in r["hands"]:
		var s := str(h["points"])
		if g.mode() == "301":
			s = "%d left" % h["points"]
		elif g.mode() == "clock":
			s = "on " + ("the bull" if int(h["points"]) > 20 else str(h["points"]))
		box.add_child(main._label("%s: %s" % [h["name"], s], 24, Palette.GOLD if h["seat"] == w else Palette.INK))


func rules() -> Array:
	var g = main.game
	var m: String = g.mode() if g != null else "shootout"
	var how := {
		"shootout": "SHOOTOUT. Everyone throws 3 darts; the highest total wins the round and the shotgun, with 1 shell, or 2 if they hit a bullseye. A tie for the lead is sudden death: the tied players throw again.",
		"clock": "AROUND THE CLOCK. Hit 1, then 2, and on round to 20, then the bull. A double moves you on 2, a treble 3. First to hit the bull wins, with 2 shells.",
		"301": "301. Everyone starts on 301 and counts down. Hit exactly 0 to win. Go under and you BUST: that visit doesn't count. It's a long game, so it pays 4 shells: enough to finish someone off.",
	}
	return [
		"THE THROW. A red line crosses the board through the bull, with a dot running along it. Tap to stop the dot. A second line crosses through that spot at another angle: tap again and the dart flies to wherever that dot is. The lines are long, so you can miss the board completely.",
		"QUICKER. Each dart of your 3, the dots move faster.",
		how[m],
		"THE BOARD. 20 at the top. The thin outer ring is double, the thin middle ring treble. The green ring round the middle is 25, the red bull 50.",
		"THE SHOTGUN. The winner picks who to shoot. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play" or not main._my_turn():
		return "Watch where the AIs' lines cross: that's where their dart goes."
	if aim.stage == "line1":
		return "Stop the dot near where you want to go: the second line runs through that spot."
	if aim.stage == "line2":
		return "Now stop it on the bed you want."
	return ""
