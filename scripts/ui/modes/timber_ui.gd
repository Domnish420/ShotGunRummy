extends "res://scripts/ui/modes/table_mode.gd"
## TIMBER at the party room table.
##
## Your turn: tap a block (not in the top two layers). The camera swings round
## to its end and the hand comes up to it. Then your thumb drives the
## fingertip, level with that block: slide up the screen to push in, down to
## pull back, left and right to move across. The fingertip follows your thumb
## on a spring, so a steady thumb is a steady push and a twitchy one shoves.
## A faint ghost shows where your thumb wants it; the line from the ghost to
## the finger goes red, the hand trembles and the phone buzzes when the block
## fights back. A round view from above shows how far it's out.
##
## Tools (floating words, or just do it): POKE, TWO fingers (firmer), PINCH
## (pinch two fingers on the screen: grips the end that sticks out; drag to
## pull, let go to let go, yank too hard and it slips) and SWIPE (the flat
## hand: flick across to sweep a whole layer out. Thins the tower for
## everyone after you, if it stands).
##
## Push or pull it clear and it's laid on top for you. Bring the tower down
## and the player on your right shoots you.

const Driver = preload("res://scripts/three/timber_driver.gd")
const TopView = preload("res://scripts/ui/timber_top_view.gd")

const TOOL_WORDS := [["poke", "POKE"], ["two", "TWO"], ["pinch", "PINCH"], ["flat", "SWIPE"]]
const FOLLOW := 0.6 # how fast the fingertip can chase your thumb (m/s)
const THUMB := 0.0006 # metres of push per pixel of thumb: 300 px is a whole block
const SIDEWAYS := 0.035 # how far off-centre a finger can drift

var state := "" # choose | work | sweep | carry | settle | down | bot | ""
var block: RigidBody3D = null
var _seat := -1 # whose turn we're running
var _round := -1
var _pad: Control # takes the touches over the table
var _tools: HBoxContainer # the tool words
var _orbit: HBoxContainer # ◀ ▶
var _top_view: Control # the round view from above (timber_top_view.gd)
var _driver # timber_driver.gd, for an AI's turn
var _timer := 0.0
var _touches := {} # finger -> position (screen)
var _down_at := Vector2.ZERO # where the drag started (screen)
var _across_sign := 1.0 # +1 when the block's "across" points right on screen
var _target_at := Vector3.ZERO # the fingertip's target when the drag started
var _desired := Vector3.ZERO # where your thumb wants the fingertip
var _dragging := false
var _moved := 0.0
var _pinch_gap := 0.0
var _axis := Vector3.ZERO # the block's length, pointing the way a push goes
var _y := 0.0 # the level the hand works on
var _buzz := 0.0
var _sweep_from := Vector3.ZERO
var _sweep_dir := Vector3.ZERO
var _sweep_speed := 0.0
var _sweep_went := 0.0
var _last_drag := []  # [time, screen pos] samples for the flick


func _init(m) -> void:
	super(m)
	main.get_tree().physics_frame.connect(_physics_tick)
	main.get_tree().process_frame.connect(_tick)


func buttons() -> Array:
	return [] # the table is the controller


func clear() -> void:
	for sig in [[main.get_tree().physics_frame, _physics_tick], [main.get_tree().process_frame, _tick]]:
		if sig[0].is_connected(sig[1]):
			sig[0].disconnect(sig[1])
	for n in [_pad, _tools, _orbit, _top_view]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_pad = null


# ---------------------------------------------------------------- building the screen

func _ensure_screen() -> void:
	if _pad != null and is_instance_valid(_pad):
		return
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_on_pad)
	main.screen.add_child(_pad)
	main.screen.move_child(_pad, 1) # over the table's own catcher, under the words
	var vs: Vector2 = main.get_viewport_rect().size
	_tools = HBoxContainer.new()
	_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	_tools.add_theme_constant_override("separation", 26)
	_tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.screen.add_child(_tools)
	_tools.position = Vector2(0, vs.y - 230)
	_tools.size = Vector2(vs.x, 60)
	_orbit = HBoxContainer.new()
	_orbit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.screen.add_child(_orbit)
	_orbit.position = Vector2(12, vs.y * 0.5 - 40)
	_orbit.size = Vector2(vs.x - 24, 80)
	_orbit.add_child(main._bubble("◀", _walk.bind(-1), Palette.INK, 64))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orbit.add_child(gap)
	_orbit.add_child(main._bubble("▶", _walk.bind(1), Palette.INK, 64))
	# the view from above: a little map of the layer
	_top_view = TopView.new()
	_top_view.position = Vector2(vs.x - 236, 168)
	main.screen.add_child(_top_view)
	_top_view.visible = false
	_show_tools(false)


func _show_tools(on: bool) -> void:
	if _tools == null:
		return
	for c in _tools.get_children():
		c.queue_free()
	_tools.visible = on
	if not on:
		return
	var current: String = main.world.hand.tool
	for pair in TOOL_WORDS:
		var t: String = pair[0]
		_tools.add_child(main._bubble(pair[1], _pick_tool.bind(t), main.FLOAT_YELLOW if t == current else Palette.DIM, 40 if t == current else 32))
	_tools.add_child(main._bubble("✕", _let_go_block, Palette.RED, 32))


# ---------------------------------------------------------------- the turn

func _my_turn() -> bool:
	var g = main.game
	return g != null and g.phase == "play" and main._my_turn() and not main._is_bot(g.turn)


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	main.round_label.text = "TOWER %d · %d BLOCKS TAKEN" % [g.round_num, g.turns]
	main.me_name.text = me.name + ("" if me.alive else " · OUT")
	main._clear(main.me_hp)
	main.deadwood_label.text = "YOU HAVE THE GUN" if g.turn == seat and g.phase == "play" else ""
	main.world.sync({
		"game": g, "viewer": seat, "hand": [], "selected": [], "selected_item": "",
		"meld_hints": {}, "lay_hints": {}, "lit": "", "can_draw": false, "targets": {},
		"hide_hand": true,
	})
	_ensure_screen()
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false
	_orbit.visible = g.phase == "play" and state in ["choose", "work", "bot", "settle"]


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "TIMBER!" if g.phase == "shoot" else "ROUND OVER"
	if state == "down":
		return "TIMBER!"
	if not _my_turn():
		return "%s IS PULLING A BLOCK..." % main._name(g.turn)
	match state:
		"choose":
			return "YOUR TURN: TAP A BLOCK"
		"work":
			match main.world.hand.tool:
				"pinch":
					return "PINCH AND DRAG TO PULL IT OUT"
				"flat":
					return "FLICK ACROSS TO SWIPE THE LAYER"
			return "THUMB UP TO PUSH IN, DOWN TO EASE OFF"
		"sweep":
			return "PRAY..."
		"carry", "settle":
			return "STEADY..."
	return ""


## Every frame: start the right thing for whoever's turn it is.
func _tick() -> void:
	var g = main.game
	if g == null or main.mode_ui != self or main.round_label == null or not is_instance_valid(main.round_label):
		return
	var w = main.world
	if w.tower == null:
		return
	var delta: float = main.get_process_delta_time()
	if g.round_num != _round:
		_round = g.round_num
		state = ""
		_seat = -1
		_timer = 1.8 # the new tower settles first
	if g.phase != "play":
		if state != "":
			state = ""
			_end_work()
		return
	if _timer > 0.0 and state in ["", "settle", "carry", "down"]:
		_timer -= delta
		if _timer <= 0.0:
			_timer_done()
		return
	if state == "" or g.turn != _seat:
		if main._lesson_showing() or main.overlay_layer.get_child_count() > 0 or main._settings_open():
			return
		_start_turn()
	if state == "work":
		_drive_hand(delta)
	_update_top_view()


func _start_turn() -> void:
	var g = main.game
	_seat = g.turn
	block = null
	_end_work()
	var n: int = g.players.size()
	# walk round to the side of the table they sit at
	var spot: Vector3 = main.world.seat_position(_seat, main._me(), n)
	main.world.tower_yaw = atan2(spot.x, spot.z)
	main.world.tower_focus = Vector3(0, main.world.tower.height() * 0.48, 0)
	main.world.tower_dist = 0.8
	main.world.tower_rise = 0.12
	if main._is_bot(_seat):
		state = "bot"
		_driver = Driver.new(main.world.tower, main.world.hand, g.players[_seat].bot)
		_driver.start_turn()
	else:
		state = "choose"
	main._refresh()


func _physics_tick() -> void:
	var g = main.game
	if g == null or main.mode_ui != self or main.world.tower == null:
		return
	var tower = main.world.tower
	if g.phase == "play" and tower.down and state not in ["down", ""]:
		_tower_down()
		return
	if state == "bot" and _driver != null:
		var r: String = _driver.step(main.get_physics_process_delta_time())
		if _driver.block != null:
			_look_at_block(_driver.block, _driver._axis)
			main.world.show_strain(true)
		if r == "out":
			block = _driver.block
			_carry()
	elif state == "sweep":
		_sweep_step(main.get_physics_process_delta_time())


func _timer_done() -> void:
	match state:
		"carry":
			state = "settle"
			_timer = 1.4
			main._refresh()
		"settle":
			_turn_over()
		"down":
			var seat := _seat
			state = ""
			_act(seat, "toppled")


func _act(seat: int, action: String) -> void:
	var g = main.game
	if g == null or g.phase != "play" or g.turn != seat:
		return
	if main._is_bot(seat) or main._online():
		main._after_simple(main.Session.perform(g, seat, action, [], true))
	else:
		main._act(action, [], main._after_simple)


func _turn_over() -> void:
	var seat := _seat
	state = ""
	block = null
	main.world.tower.set_active(null)
	_act(seat, "placed")


func _tower_down() -> void:
	state = "down"
	_timer = 1.6
	_end_work()
	main.world.announce("TIMBER!")
	main._sound("blast")
	main._shake()
	main._log("%s brought the tower down." % main._name(_seat))
	main._refresh()


# ---------------------------------------------------------------- the camera

func _walk(step: int) -> void:
	main.world.tower_yaw += step * PI * 0.5
	main._sound("tick")


## Stand off to one side of the block's end, a little above: you see the
## end and which way it's going in.
func _look_at_block(b: RigidBody3D, push: Vector3) -> void:
	var w = main.world
	var back := -push # the camera's on the side the push comes from
	var yaw := atan2(back.x, back.z) + 0.6
	w.tower_yaw = lerp_angle(w.tower_yaw, yaw, 0.08)
	w.tower_focus = w.tower_focus.lerp(b.global_position, 0.1)
	w.tower_dist = lerpf(w.tower_dist, 0.62, 0.1)
	w.tower_rise = lerpf(w.tower_rise, 0.22, 0.1)


# ---------------------------------------------------------------- touches

func _view(at: Vector2) -> Vector2:
	return main._to_view(at)


func _on_pad(event: InputEvent) -> void:
	if not _my_turn():
		return
	# two fingers pinching together: grip with the hand
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_gap = (pts[0] as Vector2).distance_to(pts[1])
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2 and state == "work" and main.world.hand.tool != "pinch":
			var pts: Array = _touches.values()
			var gap: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch_gap > 0.0 and gap < _pinch_gap * 0.8:
				_pick_tool("pinch")
				if main.world.hand.tool == "pinch":
					_press(event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag(event.position)


func _press(at: Vector2) -> void:
	_dragging = true
	_moved = 0.0
	_down_at = at
	_last_drag = [[Time.get_ticks_msec(), at]]
	if state == "work":
		var hand = main.world.hand
		_target_at = hand.target
		var across := Vector3(-_axis.z, 0, _axis.x)
		var cam: Camera3D = main.world.camera
		var p: Vector3 = block.global_position
		_across_sign = 1.0 if cam.unproject_position(p + across * 0.05).x >= cam.unproject_position(p).x else -1.0
		_desired = hand.target
		if hand.tool == "pinch":
			_grip()


func _drag(at: Vector2) -> void:
	_moved += at.distance_to(_down_at) if _moved == 0.0 else 0.0
	_moved = maxf(_moved, at.distance_to(_down_at))
	_last_drag.append([Time.get_ticks_msec(), at])
	if _last_drag.size() > 6:
		_last_drag.pop_front()
	if state != "work":
		return
	# thumb up pushes in, down pulls back; sideways drifts the finger a little
	var d := at - _down_at
	var across := Vector3(-_axis.z, 0, _axis.x)
	var want := _target_at + _axis * (-d.y * THUMB) + across * clampf(d.x * THUMB * 0.6 * _across_sign, -SIDEWAYS, SIDEWAYS)
	want.y = _y
	# don't let it wander far from the block's end
	var from: Vector3 = block.global_position
	var off := want - from
	off.y = 0.0
	if off.length() > 0.45:
		want = from + off.normalized() * 0.45 + Vector3(0, want.y - from.y, 0)
	_desired = want


func _release(at: Vector2) -> void:
	_dragging = false
	var hand = main.world.hand
	if state == "choose" or (state == "work" and _moved < 12.0 and hand.tool != "pinch"):
		# a tap: pick (or switch) a block
		if _moved < 12.0:
			_tap_block(at)
		return
	if state == "work" and hand.tool == "pinch":
		main.world.tower.release()
		hand.grip = 0.0
	elif state == "work" and hand.tool == "flat":
		_flick(at)


func _tap_block(at: Vector2) -> void:
	var b: RigidBody3D = main.world.pick_block(_view(at))
	if b == null:
		return
	if not main.world.tower.takeable(b):
		main.message = "Not the bottom layer, the top layer, or the one under it till the top's finished."
		main._refresh()
		return
	main.message = ""
	_choose(b)


func _choose(b: RigidBody3D) -> void:
	var w = main.world
	var tower = w.tower
	block = b
	tower.set_active(b)
	var axis: Vector3 = tower.block_axis(b)
	# push from the end nearer the camera
	var to_cam: Vector3 = w.camera.global_position - b.global_position
	_axis = -axis if axis.dot(to_cam) > 0.0 else axis
	_y = b.global_position.y
	state = "work"
	w.set_tags_shown(false)
	_set_hand(w.hand.tool if w.hand.tool != "pinch" else "poke")
	main._sound("tap")
	main._refresh()


func _let_go_block() -> void:
	if state != "work":
		return
	main.world.tower.release()
	main.world.tower.set_active(null)
	_end_work()
	block = null
	state = "choose"
	main._refresh()


func _end_work() -> void:
	var w = main.world
	if w.hand != null:
		w.hand.park()
		w.hand.grip = 0.0
		w.hand.boost = 1.0
	w.show_strain(false)
	_show_tools(false)
	if _top_view != null:
		_top_view.visible = false


# ---------------------------------------------------------------- the hand

func _pick_tool(t: String) -> void:
	if state != "work":
		return
	_set_hand(t)
	main._refresh()


func _set_hand(t: String) -> void:
	var w = main.world
	var tower = w.tower
	var hand = w.hand
	tower.release()
	hand.grip = 0.0
	match t:
		"pinch":
			# grip the end that sticks out
			var out: Array = tower.protrusion(block)
			var axis: Vector3 = tower.block_axis(block)
			var side := 1.0 if out[1] >= out[0] else -1.0
			if maxf(out[0], out[1]) < 0.025:
				main.message = "Push it out a bit first: there's nothing to grip."
				t = "poke"
			else:
				_axis = -axis * side # pulling is the way back from that end
				var grip_at: Vector3 = block.global_position + axis * side * (tower.L * 0.5 - 0.012)
				tower.set_touchable([block])
				hand.set_tool("pinch")
				hand.show_hand()
				hand.jump_to(grip_at, -axis * side)
				_desired = grip_at
				_show_tools(true)
				_top_view.visible = true
				return
		"flat":
			# the whole layer: sweep across the blocks from the near side
			var layer: Array = tower.layer_blocks()[int(block.get_meta("layer"))]
			tower.set_touchable(layer)
			var axis: Vector3 = tower.block_axis(block)
			var across := Vector3(-axis.z, 0, axis.x)
			var center := Vector3.ZERO
			for o in layer:
				center += o.global_position
			center /= layer.size()
			if across.dot(main.world.camera.global_position - center) > 0.0:
				across = -across
			_sweep_dir = across
			_sweep_from = center - across * (tower.L * 0.5 + 0.05)
			hand.set_tool("flat")
			hand.show_hand()
			hand.jump_to(_sweep_from, axis)
			_desired = _sweep_from
			_axis = across
			_show_tools(true)
			_top_view.visible = true
			return
	if t == "poke" or t == "two":
		tower.set_touchable([block])
		var start: Vector3 = block.global_position - _axis * (tower.L * 0.5 + 0.025)
		start.y = _y
		hand.set_tool(t)
		hand.show_hand()
		hand.jump_to(start, _axis)
		_desired = start
	_show_tools(true)
	_top_view.visible = true


func _grip() -> void:
	var hand = main.world.hand
	var tower = main.world.tower
	hand.grip = 1.0
	tower.hold(block, hand.tip.global_position)
	main._sound("tap")


## The fingertip chases your thumb (not instantly: on a spring, so it's
## smooth, and so a jerk is a jerk), and shows the strain.
func _drive_hand(delta: float) -> void:
	var w = main.world
	var hand = w.hand
	var tower = w.tower
	if block == null:
		return
	_look_at_block(block, _axis)
	hand.target = hand.target.move_toward(_desired, FOLLOW * delta * (3.0 if hand.tool == "flat" else 1.0))
	if hand.tool == "pinch":
		if hand.grip > 0.0:
			if tower._held == null:
				# yanked too hard: it slipped out of your fingers
				hand.grip = 0.0
				main.world.announce("SLIPPED!")
				main._sound("flick")
			else:
				tower.hold_to(hand.target)
	var strain: float = w.show_strain(hand.tool != "flat")
	# trembling fingers and a buzz when it's fighting back
	if strain > 0.45:
		hand.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.002 * strain
		_buzz -= delta
		if _buzz <= 0.0:
			_buzz = 0.18
			if main.sound_on:
				main._sound("tick")
			Input.vibrate_handheld(int(15 + 25 * strain))
	if tower.is_out(block):
		_carry()


func _flick(at: Vector2) -> void:
	if _last_drag.size() < 2:
		return
	var a: Array = _last_drag[0]
	var b: Array = _last_drag[-1]
	var dt := maxf(0.016, (int(b[0]) - int(a[0])) / 1000.0)
	var px_speed: float = (at - (a[1] as Vector2)).length() / dt
	var speed := px_speed / 600.0
	if px_speed < 350.0:
		main.message = "Flick fast across the screen to swipe the layer."
		main._refresh()
		return
	_sweep_speed = clampf(speed, 0.8, 4.0)
	_sweep_went = 0.0
	state = "sweep"
	_show_tools(false)
	main._sound("swish")
	main._refresh()


func _sweep_step(delta: float) -> void:
	var w = main.world
	var tower = w.tower
	_sweep_went += _sweep_speed * delta
	w.hand.target = _sweep_from + _sweep_dir * minf(_sweep_went, tower.L + 0.25)
	if _sweep_went > tower.L + 0.25 + _sweep_speed * 1.0:
		# what came out is out of the game
		var took := 0
		for o in tower.moving.keys():
			if tower.is_out(o):
				tower.discard(o)
				took += 1
		w.hand.park()
		tower.set_active(null)
		if took == 0:
			main.message = "Nothing came out. Try again."
			state = "choose"
			_end_work()
		else:
			main._log("%s swipes %d block%s out." % [main._name(_seat), took, "" if took == 1 else "s"])
			main.world.announce("SWIPED %d!" % took)
			state = "settle"
			_timer = 1.6
			_end_work()
		main._refresh()


## Out it comes: up and onto the top.
func _carry() -> void:
	var w = main.world
	w.hand.park()
	w.show_strain(false)
	_show_tools(false)
	if _top_view != null:
		_top_view.visible = false
	state = "carry"
	_timer = w.tower.place_on_top(block) + 0.1
	main._sound("slap")
	main._refresh()


# ---------------------------------------------------------------- the view from above

func _update_top_view() -> void:
	if _top_view == null or not _top_view.visible or block == null or not is_instance_valid(block):
		return
	_top_view.tower = main.world.tower
	_top_view.hand = main.world.hand
	_top_view.block = block
	_top_view.layer = int(block.get_meta("layer"))
	_top_view.forward = _axis if main.world.hand.tool != "pinch" else -_axis


# ---------------------------------------------------------------- events, results, rules

func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"placed":
			main._log("%s takes a block. %d out." % [main._name(d["seat"]), d["turns"]])
		"turn_start":
			main.world.announce("%s HAS THE GUN" % main._name(d["seat"]))


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	box.add_child(main._label("TIMBER!", 64, Palette.GOLD, true))
	box.add_child(main._title("%s BROUGHT IT DOWN" % main._name(r["loser"]), Palette.AMBER))
	if g.options["shotgun"]:
		box.add_child(main._label("%s, on their right, has the gun. One shot and they're out." % main._name(r["winner"]), 24, Palette.INK, true))
	else:
		box.add_child(main._label("%s is out." % main._name(r["loser"]), 24, Palette.INK, true))
	box.add_child(main._label("The tower stood for %d block%s. %s starts the next one." % [r["turns"], "" if r["turns"] == 1 else "s", main._name(g.next_first)], 22, Palette.DIM, true))


func rules() -> Array:
	return [
		"THE TOWER. 18 layers of 3 wooden blocks. Some are loose and slide right out; some carry the weight and drag the tower with them.",
		"YOUR TURN. Tap a block (not in the top layer, nor the one under it while the top's unfinished). Your thumb drives the fingertip, level with the block: slide up to push in, down to ease off, sideways to move across. Push it out the other side, or pull it out, and it's laid on top for you.",
		"FEEL IT. A faint ghost shows where your thumb wants the finger. The line from it to the real finger goes red, the hand shakes and the phone buzzes when the block fights back. The round view from above shows how far it's out. ◀ ▶ walk you round the tower.",
		"THE HAND. POKE (one finger), TWO (firmer), PINCH (pinch two fingers on the screen: grips the end sticking out; drag to pull; yank too hard and it slips) and SWIPE (flick across to sweep a whole layer out: thins the tower for everyone after you, if it stands).",
		"THE SHOTGUN. Whoever's turn it is has the gun in front of them; it moves left with the turn. Bring the tower down and the player on your right shoots you: one shot and you're out. The tower's built again and the player on your left goes first. Always. Last one standing wins.",
	]


func coach() -> String:
	if not _my_turn():
		return "Watch the AIs: they test a block, and back off if the tower moves."
	match state:
		"choose":
			return "Middles are loose more often. Tap one."
		"work":
			return "Slow and steady. If the line goes red and the tower moves, tap ✕ and try another."
	return ""
