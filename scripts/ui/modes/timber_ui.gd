extends "res://scripts/ui/modes/table_mode.gd"
## TIMBER at the party room table.
##
## Your turn: tap a block. The camera goes round to its end once and the hand
## comes up to it; then the camera's yours: two fingers drag to walk round and
## look up and down, pinch to come closer (right-drag and the wheel on a
## computer). One finger drives the hand, level with the block, as you see
## it: up the screen is away from you, sideways is sideways. The fingertip
## follows on a spring, with a limited push: a steady thumb is a steady push,
## a twitch is a shove, and a tight block fights back (the line from the ghost
## to the finger goes red, the hand trembles, the phone buzzes). The round
## window up top is a camera over the hand's shoulder.
##
## Tools: POKE, TWO (firmer), PINCH (grips the end that sticks out: hold and
## drag back; yank and it slips) and SWIPE (the flat hand: drag it across the
## layer yourself; let go and whatever's out of that layer is out of the
## game). Push or pull a block clear and it's laid on top for you. Bring the
## tower down and the player on your right shoots you.

const Driver = preload("res://scripts/three/timber_driver.gd")

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
var _top_view: TextureRect # the round view over the hand's shoulder
var _sub: SubViewport
var _sub_cam: Camera3D
var _driver # timber_driver.gd, for an AI's turn
var _timer := 0.0
var _touches := {} # finger -> position (screen)
var _down_at := Vector2.ZERO # where the drag started (screen)
var _target_at := Vector3.ZERO # the fingertip's target when the drag started
var _desired := Vector3.ZERO # where your thumb wants the fingertip
var _dragging := false
var _moved := 0.0
var _pinch_gap := 0.0
var _axis := Vector3.ZERO # the block's length, pointing the way a push goes
var _y := 0.0 # the level the hand works on
var _buzz := 0.0


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
	for n in [_pad, _tools, _orbit, _top_view, _sub]:
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
	# the hand cam: its own little camera, just behind and above the hand,
	# looking where the fingers are going
	_sub = SubViewport.new()
	_sub.size = Vector2i(256, 256)
	_sub.world_3d = main.world.get_world_3d()
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_cam = Camera3D.new()
	_sub_cam.fov = 55.0
	_sub_cam.near = 0.01
	_sub_cam.far = 8.0
	_sub.add_child(_sub_cam)
	main.add_child(_sub)
	_sub_cam.current = true
	_top_view = TextureRect.new()
	_top_view.texture = _sub.get_texture()
	_top_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_top_view.stretch_mode = TextureRect.STRETCH_SCALE
	_top_view.custom_minimum_size = Vector2(250, 250)
	_top_view.size = Vector2(250, 250)
	_top_view.position = Vector2(vs.x - 266, 160)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5));
	if (d > 0.5) { discard; }
	vec4 c = texture(TEXTURE, UV);
	if (d > 0.47) { c = vec4(0.95, 0.85, 0.4, 1.0); }
	COLOR = vec4(c.rgb, 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_top_view.material = mat
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
			return "YOUR TURN: TAP A BLOCK · TWO FINGERS: CAMERA"
		"work":
			match main.world.hand.tool:
				"pinch":
					return "HOLD AND DRAG BACK TO PULL IT OUT · TWO FINGERS: CAMERA"
				"flat":
					return "DRAG THE FLAT HAND ACROSS THE LAYER · TWO FINGERS: CAMERA"
			return "DRAG TO PUSH · TWO FINGERS: CAMERA"
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
	if _top_view != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _top_view.visible else SubViewport.UPDATE_DISABLED


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


## An AI's turn: the camera keeps an eye on what it's doing.
func _look_at_block(b: RigidBody3D, push: Vector3) -> void:
	var w = main.world
	var back := -push # the camera's on the side the push comes from
	var yaw := atan2(back.x, back.z) + 0.6
	w.tower_yaw = lerp_angle(w.tower_yaw, yaw, 0.08)
	w.tower_focus = w.tower_focus.lerp(b.global_position, 0.1)
	w.tower_dist = lerpf(w.tower_dist, 0.62, 0.1)
	w.tower_rise = lerpf(w.tower_rise, 0.22, 0.1)


## Your block: the camera goes round to its end once; after that it's yours
## (two fingers) and stays put.
func _aim_camera(b: RigidBody3D, push: Vector3) -> void:
	var w = main.world
	var back := -push
	w.tower_yaw = atan2(back.x, back.z) + 0.4
	w.tower_focus = b.global_position
	w.tower_dist = 0.62
	w.tower_rise = 0.18


## Two fingers (or right-drag, and the wheel, on a computer): drag to walk
## round the tower and look up or down it, pinch to come closer or back off.
func _turn_camera(move: Vector2, zoom: float) -> void:
	var w = main.world
	w.tower_yaw -= move.x * 0.007
	w.tower_rise = clampf(w.tower_rise + move.y * 0.0025, -0.05, 0.9)
	w.tower_dist = clampf(w.tower_dist * zoom, 0.3, 1.6)
	if state == "choose":
		# looking round for a block: aim up and down the tower too
		w.tower_focus.y = clampf(w.tower_focus.y + move.y * 0.0012, 0.08, w.tower.height())


# ---------------------------------------------------------------- touches

func _view(at: Vector2) -> Vector2:
	return main._to_view(at)


var _two := false # two fingers have been down (the camera): ignore the one-finger moves till they're all up
var _cam_mid := Vector2.ZERO
var _cam_gap := 0.0
var _right_drag := false


func _on_pad(event: InputEvent) -> void:
	if not _my_turn():
		return
	# real fingers: two or more move the camera
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			if not _two:
				_two = true
				_cancel_drag()
			_cam_mid = _mid()
			_cam_gap = _gap()
		elif _touches.is_empty():
			_two = false
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var mid := _mid()
			var gap := _gap()
			_turn_camera(mid - _cam_mid, _cam_gap / maxf(gap, 1.0) if _cam_gap > 1.0 else 1.0)
			_cam_mid = mid
			_cam_gap = gap
		return
	# one finger (it comes as the mouse) or the mouse: the hand
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _two:
					return
				if event.pressed:
					_press(event.position)
				else:
					_release(event.position)
			MOUSE_BUTTON_RIGHT:
				_right_drag = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_turn_camera(Vector2.ZERO, 0.92)
			MOUSE_BUTTON_WHEEL_DOWN:
				_turn_camera(Vector2.ZERO, 1.08)
	elif event is InputEventMouseMotion:
		if _right_drag:
			_turn_camera(event.relative, 1.0)
		elif _dragging and not _two:
			_drag(event.position)


func _mid() -> Vector2:
	var m := Vector2.ZERO
	for p in _touches.values():
		m += p
	return m / maxf(1.0, _touches.size())


func _gap() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0


## A second finger came down mid-push: the hand stops where it is.
func _cancel_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	var hand = main.world.hand
	_desired = hand.target
	if state == "work" and hand.tool == "pinch":
		main.world.tower.release()
		hand.grip = 0.0


func _press(at: Vector2) -> void:
	_dragging = true
	_moved = 0.0
	_down_at = at
	if state == "work":
		var hand = main.world.hand
		_target_at = hand.target
		_desired = hand.target
		if hand.tool == "pinch":
			_grip()


## One finger drags the hand round on the block's level, as you see it: up
## the screen is away from you, sideways is sideways.
func _drag(at: Vector2) -> void:
	_moved = maxf(_moved, at.distance_to(_down_at))
	if state != "work":
		return
	var d := at - _down_at
	var cam: Camera3D = main.world.camera
	var right := cam.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var away := -cam.global_basis.z
	away.y = 0.0
	away = away.normalized()
	var want := _target_at + (right * d.x + away * (-d.y)) * THUMB
	want.y = _y
	# don't let it wander far from the block
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
		_swiped()


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
	_aim_camera(b, _axis)
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
			var from: Vector3 = center - across * (tower.L * 0.5 + 0.05)
			hand.set_tool("flat")
			hand.show_hand()
			hand.jump_to(from, axis)
			_desired = from
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
	hand.target = hand.target.move_toward(_desired, FOLLOW * delta * (1.6 if hand.tool == "flat" else 1.0))
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
	if hand.tool != "flat" and tower.is_out(block):
		_carry()


## You've swept with the flat hand and let go: whatever's out of that layer
## is out of the game. Nothing out? Keep going.
func _swiped() -> void:
	var w = main.world
	var tower = w.tower
	var took := 0
	for o in tower.moving.keys():
		if tower.is_out(o):
			tower.discard(o)
			took += 1
	if took == 0:
		return
	main._log("%s swipes %d block%s out." % [main._name(_seat), took, "" if took == 1 else "s"])
	w.announce("SWIPED %d!" % took)
	tower.set_active(null)
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
	var hand = main.world.hand
	var tip: Vector3 = hand.tip.global_position
	var f: Vector3 = hand.facing
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)
	var side := Vector3(-f.z, 0, f.x)
	# over the shoulder: behind the hand, up a bit, off to the side
	var from := tip - f * 0.32 + Vector3.UP * 0.13 + side * 0.07
	_sub_cam.global_transform = Transform3D(Basis.looking_at((tip + f * 0.06) - from, Vector3.UP), from)


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
		"YOUR TURN. Tap a block (not the bottom layer, the top layer, nor the one under it while the top's unfinished). ONE finger drives the hand, level with the block: drag up the screen to push away from you, sideways to move across. Push it out the other side, or pull it out, and it's laid on top for you.",
		"THE CAMERA. TWO fingers: drag to walk round the tower and look up and down it, pinch to come closer or back off. ◀ ▶ step round a quarter at a time. The round window is a camera over the hand's shoulder.",
		"FEEL IT. A faint ghost shows where your finger wants the hand. The line from it to the real finger goes red, the hand shakes and the phone buzzes when the block fights back.",
		"THE HAND. POKE (one finger), TWO (firmer), PINCH (grips the end that sticks out: hold and drag back; yank too hard and it slips) and SWIPE (the flat hand: drag it across the layer yourself; let go and whatever's out of that layer is gone for good. It thins the tower for everyone after you, if it stands).",
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
