extends "res://scripts/ui/modes/table_mode.gd"
## TIMBER at the party room table.
##
## On your turn you have a free hand in 3D. It's solid (fingertip, finger and
## fist) and it touches everything: every block, and the table.
##
##   one finger on the screen   moves the hand up, down, left and right, as
##                              you see it
##   the PUSH / PULL strip      (right edge) moves it away from you and back
##   two fingers                the camera: drag to walk round the tower and
##                              look up and down it, pinch to zoom. The hand
##                              always points away from you, so walking round
##                              turns it.
##   on a computer              left-drag the hand, wheel pushes and pulls,
##                              right-drag the camera
##
## The hand follows on a short lead with a limited push: a steady thumb is a
## steady push, a twitch is a shove, and a tight block fights back (the line
## from the ghost to the finger goes red, the hand shakes, the phone buzzes).
##
## POKE, TWO and FLAT are hand shapes. GRAB closes the hand on the block in
## reach: one still in the tower is pulled (yank and it slips); one that's
## out is picked up from above. The fist won't follow the finger into the
## tower, so a poke gets a block about halfway: walk round and GRAB the end.
## Your block is the first one out. Carry it over the top, TURN it, LET GO to
## set it down, then DONE. Bring the tower down and the player on your right
## shoots you. (AIs place theirs for themselves.)

const Driver = preload("res://scripts/three/timber_driver.gd")

const TOOL_WORDS := [["poke", "POKE"], ["two", "TWO"], ["flat", "FLAT"]]
const FOLLOW := 0.6 # how fast the hand can chase your thumb (m/s)
const THUMB := 0.0006 # metres per pixel of thumb: 300 px is a whole block
const REACH := 0.04 # GRAB takes a block this close to the fingertip
const CARRY_CLEAR := 0.06 # a carried block stays this far off the table: room for the fingers under it
const CLEAR := 0.25 # the fingertip this far from the middle of the tower: the whole hand's clear of it
const COLUMN := 0.13 # half the width of the space the tower takes up (a carried block goes round it)

var state := "" # work | placed | carry | settle | down | bot | ""
var block: RigidBody3D = null # the block out this turn (yours, or the AI's)
var _seat := -1 # whose turn we're running
var _round := -1
var _pad: Control # takes the touches over the table
var _strip: Control # PUSH / PULL
var _tools: HBoxContainer # the tool words
var _orbit: HBoxContainer # ◀ ▶
var _top_view: TextureRect # the round view over the hand's shoulder
var _sub: SubViewport
var _sub_cam: Camera3D
var _driver # timber_driver.gd, for an AI's turn
var _timer := 0.0
var _buzz := 0.0
var _scrape := 0.0
var _cam_manual := false # you've moved the camera this turn

# your hand
var _want := Vector3.ZERO # where your thumb wants the hand
var _touched := {} # block -> seconds since the hand last touched it (they slide while touched)
var _home := {} # block -> its height when first touched (to tell when it's dropped out)
var _phys: RigidBody3D = null # a block in the tower, gripped and being pulled
var _lifted := false # your block's in your hand, off the table
var _turn_yaw := 0.0 # which way the held block's turned
var _spot := {} # tower3d.next_spot() for the block out

# touches
var _touches := {} # finger -> position, on the pad
var _strip_touches := {}
var _cam_mid := Vector2.ZERO
var _cam_gap := 0.0
var _left_drag := false
var _right_drag := false


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
	for n in [_pad, _strip, _tools, _orbit, _top_view, _sub]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_pad = null
	if main.world != null and main.world.tower != null and main.world.tower.dropped.is_connected(_on_dropped):
		main.world.tower.dropped.disconnect(_on_dropped)


# ---------------------------------------------------------------- building the screen

func _ensure_screen() -> void:
	if _pad != null and is_instance_valid(_pad):
		return
	var vs: Vector2 = main.get_viewport_rect().size
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_on_pad)
	main.screen.add_child(_pad)
	main.screen.move_child(_pad, 1) # over the table's own catcher, under the words
	# PUSH / PULL: a strip down the right edge for the other thumb
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.position = Vector2(vs.x - 120, vs.y * 0.44)
	_strip.size = Vector2(120, vs.y * 0.34)
	_strip.gui_input.connect(_on_strip)
	_strip.draw.connect(_draw_strip)
	main.screen.add_child(_strip)
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
	_orbit.position = Vector2(12, vs.y * 0.3)
	_orbit.size = Vector2(vs.x - 24, 80)
	_orbit.add_child(main._bubble("◀", _walk.bind(-1), Palette.INK, 64))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orbit.add_child(gap)
	_orbit.add_child(main._bubble("▶", _walk.bind(1), Palette.INK, 64))
	# the hand cam: its own little camera, just behind and above the hand
	_sub = SubViewport.new()
	_sub.size = Vector2i(256, 256)
	_sub.world_3d = main.world.get_world_3d()
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_cam = Camera3D.new()
	_sub_cam.fov = 48.0
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
	_top_view.custom_minimum_size = Vector2(230, 230)
	_top_view.size = Vector2(230, 230)
	_top_view.position = Vector2(vs.x - 246, 160)
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
	_strip.visible = false
	_show_tools()


func _draw_strip() -> void:
	var s: Vector2 = _strip.size
	var x := s.x * 0.5
	var col := Color(1.0, 0.86, 0.25, 0.9)
	var dark := Color(0, 0, 0, 0.7)
	_strip.draw_line(Vector2(x, 44), Vector2(x, s.y - 44), dark, 16.0)
	_strip.draw_line(Vector2(x, 44), Vector2(x, s.y - 44), col, 8.0)
	for dir in [-1.0, 1.0]:
		var tip := Vector2(x, 14 if dir < 0 else s.y - 14)
		var base: float = tip.y - dir * 34.0
		_strip.draw_colored_polygon(PackedVector2Array([tip, Vector2(x - 30, base), Vector2(x + 30, base)]), col)
	var font: Font = main.get_theme_default_font()
	for pair in [["PUSH", 70.0], ["PULL", s.y - 52.0]]:
		_strip.draw_string_outline(font, Vector2(0, pair[1]), pair[0], HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, 8, Color.BLACK)
		_strip.draw_string(font, Vector2(0, pair[1]), pair[0], HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, col)


func _show_tools() -> void:
	if _tools == null:
		return
	for c in _tools.get_children():
		c.queue_free()
	var mine := _my_turn() and state in ["work", "placed"]
	_tools.visible = mine
	if not mine:
		return
	if state == "placed":
		_tools.add_child(main._bubble("DONE", _done, Palette.GOLD, 60))
		return
	if _lifted:
		_tools.add_child(main._bubble("TURN", turn_block, main.FLOAT_YELLOW, 40))
		_tools.add_child(main._bubble("LET GO", grab, Palette.GOLD, 44))
		return
	if _phys != null:
		_tools.add_child(main._bubble("LET GO", grab, Palette.GOLD, 44))
		return
	var current: String = main.world.hand.tool
	for pair in TOOL_WORDS:
		var t: String = pair[0]
		_tools.add_child(main._bubble(pair[1], pick_tool.bind(t), main.FLOAT_YELLOW if t == current else Palette.DIM, 40 if t == current else 32))
	_tools.add_child(main._bubble("GRAB", grab, Palette.GOLD, 40))


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
	_orbit.visible = g.phase == "play" and state in ["work", "placed", "bot", "settle"]
	_strip.visible = _my_turn() and state == "work"
	_show_tools()


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "TIMBER!" if g.phase == "shoot" else "ROUND OVER"
	if state == "down":
		return "TIMBER!"
	if not _my_turn():
		return "%s IS PULLING A BLOCK..." % main._name(g.turn)
	match state:
		"work":
			if _lifted:
				return "CARRY IT OVER THE TOP · TURN · LET GO TO SET IT DOWN"
			if _phys != null:
				return "PULL IT OUT (EASY...) · LET GO TO RELEASE"
			if block != null:
				return "IT'S OUT: GRAB IT AND PUT IT ON TOP"
			return "DRAG: MOVE THE HAND · STRIP: PUSH / PULL · 2 FINGERS: CAMERA"
		"placed":
			return "HAPPY WITH IT? PRESS DONE"
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
	elif state == "bot" and _driver != null and _driver.block != null and is_instance_valid(_driver.block):
		block = _driver.block
		if not _cam_manual:
			_look_at_block(_driver.block, _driver._axis, delta)
		w.show_strain(_driver.state == "push")
		_top_view.visible = w.hand.visible
		_slide_sound(block, delta)
	if w.landing != null and not (state == "work" and _lifted):
		w.landing.visible = false
	_update_top_view()
	if _top_view != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _top_view.visible else SubViewport.UPDATE_DISABLED


func _start_turn() -> void:
	var g = main.game
	var w = main.world
	_seat = g.turn
	block = null
	_end_work()
	var n: int = g.players.size()
	# walk round to the side of the table they sit at
	var spot: Vector3 = w.seat_position(_seat, main._me(), n)
	w.tower_yaw = atan2(spot.x, spot.z)
	w.tower_focus = Vector3(0, w.tower.height() * 0.48, 0)
	w.tower_dist = 0.8
	w.tower_rise = 0.12
	_cam_manual = false
	var any := false
	for b in w.tower.blocks:
		if w.tower.takeable(b):
			any = true
			break
	if not any:
		# nothing left that may be taken: the turn passes
		w.announce("NO BLOCK TO TAKE")
		state = "settle"
		_timer = 1.0
		main._refresh()
		return
	if main._is_bot(_seat):
		state = "bot"
		w.hand.solid = false
		_driver = Driver.new(w.tower, w.hand, g.players[_seat].bot)
		_driver.start_turn()
	else:
		_begin_free()
	main._refresh()


func _physics_tick() -> void:
	var g = main.game
	if g == null or main.mode_ui != self or main.world.tower == null:
		return
	var tower = main.world.tower
	if g.phase == "play" and tower.down and state != "down":
		# it can come down between turns too: then it's on whoever's go it is
		_seat = g.turn
		_tower_down()
		return
	if state == "bot" and _driver != null:
		var r: String = _driver.step(main.get_physics_process_delta_time())
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
	main.world.landing.visible = false
	main._sound("clatter")
	main._shake()
	main._log("%s brought the tower down." % main._name(_seat))
	main._refresh()


## The hand's put away and nothing's being worked on.
func _end_work() -> void:
	var w = main.world
	if w.tower != null:
		w.tower.release()
		w.tower.set_free_hand(false)
	if w.hand != null:
		w.hand.park()
		w.hand.grip = 0.0
		w.hand.boost = 1.0
		w.hand.soft = false
	_phys = null
	_lifted = false
	_touched = {}
	_home = {}
	_left_drag = false
	w.show_strain(false)
	if _strip != null:
		_strip.visible = false
	if _top_view != null:
		_top_view.visible = false
	_show_tools()


# ---------------------------------------------------------------- the camera

func _walk(step: int) -> void:
	main.world.tower_yaw += step * PI * 0.5
	_cam_manual = true
	main._sound("tick")


## An AI's turn: the camera keeps an eye on what it's doing.
func _look_at_block(b: RigidBody3D, push: Vector3, delta: float) -> void:
	var w = main.world
	var back := -push # the camera's on the side the push comes from
	var yaw := atan2(back.x, back.z) + 0.6
	var k := minf(1.0, delta * 2.5)
	w.tower_yaw = lerp_angle(w.tower_yaw, yaw, k)
	w.tower_focus = w.tower_focus.lerp(b.global_position, k)
	w.tower_dist = lerpf(w.tower_dist, 0.7, k)
	w.tower_rise = lerpf(w.tower_rise, 0.22, k)


## Two fingers (or right-drag on a computer): drag to walk round the tower
## and look up or down it, pinch to come closer or back off.
func turn_camera(move: Vector2, zoom: float) -> void:
	var w = main.world
	_cam_manual = true # yours now: it stops following the AI's hand this turn
	w.tower_yaw -= move.x * 0.007
	w.tower_rise = clampf(w.tower_rise + move.y * 0.0025, -0.05, 0.9)
	w.tower_dist = clampf(w.tower_dist * zoom, 0.3, 1.6)
	if state == "bot":
		w.tower_focus.y = clampf(w.tower_focus.y + move.y * 0.0012, 0.08, w.tower.height())


## The way you're looking, flat: away from you. The hand points that way.
func _forward() -> Vector3:
	var yaw: float = main.world.tower_yaw
	return -Vector3(sin(yaw), 0, cos(yaw))


# ---------------------------------------------------------------- touches

## Touches come as real touch events on a phone (so two thumbs can work the
## screen and the strip at once) and as the mouse on a computer. The mouse
## events a phone makes up from the first finger are ignored.
func _made_up(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


func _on_pad(event: InputEvent) -> void:
	var g = main.game
	if g == null or g.phase != "play":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.index == 0:
				_touches.clear() # a first finger: nothing else can still be down
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			_cam_mid = _mid()
			_cam_gap = _gap()
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var mid := _mid()
			var gap := _gap()
			turn_camera(mid - _cam_mid, _cam_gap / maxf(gap, 1.0) if _cam_gap > 1.0 else 1.0)
			_cam_mid = mid
			_cam_gap = gap
		else:
			move_hand(event.relative)
		return
	if _made_up(event):
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_left_drag = event.pressed
			MOUSE_BUTTON_RIGHT:
				_right_drag = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				push_hand(40.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				push_hand(-40.0)
	elif event is InputEventMouseMotion:
		if _right_drag:
			turn_camera(event.relative, 1.0)
		elif _left_drag:
			move_hand(event.relative)


func _on_strip(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_strip_touches[event.index] = true
		else:
			_strip_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		push_hand(-event.relative.y)
	elif not _made_up(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_strip_touches[-1] = event.pressed
		elif event is InputEventMouseMotion and _strip_touches.get(-1, false):
			push_hand(-event.relative.y)


func _mid() -> Vector2:
	var m := Vector2.ZERO
	for p in _touches.values():
		m += p
	return m / maxf(1.0, _touches.size())


func _gap() -> float:
	var pts: Array = _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0


# ---------------------------------------------------------------- your hand

## Your turn: the hand comes up in front of the tower, on your side.
func _begin_free() -> void:
	var w = main.world
	var tower = w.tower
	var hand = w.hand
	state = "work"
	tower.set_touchable([])
	tower.set_free_hand(true)
	tower.active = null
	if not tower.dropped.is_connected(_on_dropped):
		tower.dropped.connect(_on_dropped)
	_touched = {}
	_home = {}
	_phys = null
	_lifted = false
	hand.solid = true
	hand.set_tool("poke")
	hand.show_hand()
	var c: Vector3 = tower.tower_center()
	_want = Vector3(c.x, tower.height() * 0.5, c.z) - _forward() * 0.3
	hand.jump_to(_want, _forward())
	w.set_tags_shown(false)
	_top_view.visible = true


## One finger: the hand goes up, down, left and right, as you see it.
func move_hand(rel: Vector2) -> void:
	if state != "work" or not _my_turn():
		return
	var f := _forward()
	var right := Vector3(-f.z, 0, f.x)
	_want += (right * rel.x + Vector3.UP * (-rel.y)) * THUMB
	_limit()


## The strip (or the wheel): away from you, and back.
func push_hand(px: float) -> void:
	if state != "work" or not _my_turn():
		return
	_want += _forward() * px * THUMB
	_limit()


## The hand stays over the table, and never far from the tower.
func _limit() -> void:
	var tower = main.world.tower
	var c: Vector3 = tower.tower_center()
	var off := Vector3(_want.x - c.x, 0, _want.z - c.z).limit_length(0.5)
	_want = Vector3(c.x + off.x, clampf(_want.y, tower.TOP_Y + 0.015, tower.height() + 0.4), c.z + off.z)
	# and it can't get far ahead of the real hand (which may be held up by a block)
	var lead: Vector3 = _want - main.world.hand.target
	_want = main.world.hand.target + lead.limit_length(0.12)


func pick_tool(t: String) -> void:
	if state != "work" or _lifted or _phys != null:
		return
	main.world.hand.set_tool(t)
	main._refresh()


## Every frame of your turn: the hand chases your thumb, the blocks it
## touches slide, and the first block out is yours.
func _drive_hand(delta: float) -> void:
	var w = main.world
	var hand = w.hand
	var tower = w.tower
	var f := _forward()
	hand.target = hand.target.move_toward(_want, FOLLOW * delta)
	if not _lifted and _phys == null:
		# held up by a block, the hand doesn't wind up a long way ahead of itself
		var tip_at: Vector3 = hand.tip.global_position
		hand.target = tip_at + (hand.target - tip_at).limit_length(0.05)
		_want = tip_at + (_want - tip_at).limit_length(0.12)
	# keep the camera level with the hand, so you can reach the top and the table
	w.tower_focus.y = lerpf(w.tower_focus.y, clampf(hand.target.y, 0.1, tower.height() + 0.1), minf(1.0, delta * 2.0))
	if _lifted:
		_carry_block()
		return
	# it turns to point away from you, but only once it's clear of the tower:
	# walk round with a finger still in there and it stays as it is (a fist
	# swinging through the blocks would be the end of the tower)
	var c0: Vector3 = tower.tower_center()
	var tip0: Vector3 = hand.tip.global_position
	if Vector2(tip0.x - c0.x, tip0.z - c0.z).length() > CLEAR and _phys == null:
		hand.set_facing(f)
	if _phys != null:
		if tower._held == null:
			# yanked too hard: it slipped out of your fingers
			_phys = null
			hand.grip = 0.0
			hand.set_tool("poke")
			w.announce("SLIPPED!")
			main._sound("flick")
			main._refresh()
		else:
			tower.hold_to(hand.target)
			_touched[_phys] = 0.0
			if tower.clear_of(_phys):
				# pulled right out and still in your fingers: it's yours
				var b := _phys
				_phys = null
				tower.release()
				if block == null:
					_take(b)
				_lift(b)
				return
	# what the hand's touching slides; let go and it grips again
	# (only the block at the fingertip: the fist leaning on the tower doesn't
	# loosen what it's leaning on. The flat hand works a whole layer.)
	# up against anything else (the fist on the tower's face, a block that may
	# not be taken), the hand rests there: it doesn't shove the tower over
	var blocked := false
	for body in hand.tip.get_colliding_bodies():
		if body is RigidBody3D and tower.blocks.has(body) and not _touched.has(body) and body != block:
			blocked = true
	hand.soft = blocked and hand.tool != "flat"
	if block == null:
		var at_tip: Array = []
		var nearest := 0.02
		for body in hand.tip.get_colliding_bodies():
			if body is RigidBody3D and tower.blocks.has(body) and not tower.removed.has(body) and tower.takeable(body):
				if hand.tool == "flat":
					at_tip.append(body)
				else:
					var d: float = tower.surface_dist(body, hand.tip.global_position)
					if d < nearest:
						nearest = d
						at_tip = [body]
		for body in at_tip:
			if not _touched.has(body):
				_home[body] = body.global_position.y
				tower.set_slide(body, true)
			_touched[body] = 0.0
	for b in _touched.keys():
		_touched[b] += delta
		var p: Vector3 = b.global_position
		var off: Vector3 = p - tower.tower_center()
		off.y = 0.0
		if p.y < tower.TOP_Y - 0.15:
			# it went off the table: back onto it, beside the tower
			b.global_position = tower.tower_center() + off.normalized() * 0.3 + Vector3(0, tower.H, 0)
			b.linear_velocity = Vector3.ZERO
			b.angular_velocity = Vector3.ZERO
		elif off.length() > tower.L * 0.6 and p.y < float(_home[b]) - tower.H * 0.6 and b.linear_velocity.length() < 0.2:
			# right out, and it's dropped onto the table
			_touched.erase(b)
			if block == null:
				_take(b)
			else:
				tower.set_slide(b, false)
				tower.discard(b) # a second one out: it's out of the game
		elif _touched[b] > 0.6 and b != _phys:
			_touched.erase(b)
			tower.set_slide(b, false)
	_slide_sound(_phys if _phys != null else _fastest(), delta)
	var strain: float = w.show_strain(true)
	# trembling fingers and a buzz when it's fighting back
	if strain > 0.45:
		hand.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.002 * strain
		_buzz -= delta
		if _buzz <= 0.0:
			_buzz = 0.18
			main._sound("tick")
			Input.vibrate_handheld(int(15 + 25 * strain))


## The quickest of the blocks you're touching (for the scrape).
func _fastest() -> RigidBody3D:
	var best: RigidBody3D = null
	for b in _touched:
		if best == null or b.linear_velocity.length() > best.linear_velocity.length():
			best = b
	return best


## This is your block: the first one out of the tower this turn.
func _take(b: RigidBody3D) -> void:
	var tower = main.world.tower
	block = b
	tower.removed.erase(b)
	tower.active = b # it's not part of the tower till it's set down on top
	tower.set_slide(b, false)
	_spot = tower.next_spot(b)
	main._sound("knock")
	main._refresh()


## A lone block the tower let slip counts as out too.
func _on_dropped(b: RigidBody3D) -> void:
	if state == "work" and _my_turn() and block == null:
		_take(b)


## GRAB: close the hand on the block in reach. LET GO: open it.
func grab() -> void:
	if state != "work" or not _my_turn():
		return
	var w = main.world
	var tower = w.tower
	var hand = w.hand
	main.message = ""
	if _lifted:
		_let_go()
		return
	if _phys != null:
		tower.release()
		_phys = null
		hand.grip = 0.0
		hand.set_tool("poke")
		main._refresh()
		return
	var tip: Vector3 = hand.tip.global_position
	var best: RigidBody3D = null
	var best_d := REACH
	for b in tower.blocks:
		if tower.removed.has(b) and b != block:
			continue
		var d: float = tower.surface_dist(b, tip)
		if b == block:
			d -= 0.08 # your own block's the easy one to pick up
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		main.message = "Nothing in reach to grab. Bring the hand up to a block."
	elif block != null and best != block:
		main.message = "You've already got your block out: grab that one."
	elif best == block or tower.clear_of(best):
		if block == null:
			_take(best)
		_lift(best)
		return
	elif not tower.takeable(best):
		main.message = "Not the bottom layer, the top layer, or the one under it till the top's finished."
	else:
		# still in the tower: grip it and pull
		_phys = best
		if not _touched.has(best):
			_home[best] = best.global_position.y
		_touched[best] = 0.0
		tower.set_slide(best, true)
		tower.hold(best, tip)
		hand.set_tool("pinch")
		hand.grip = 1.0
		main._sound("tap")
	main._refresh()


## Up it comes, held from above.
func _lift(b: RigidBody3D) -> void:
	var w = main.world
	var tower = w.tower
	tower.lift(b)
	_lifted = true
	_spot = tower.next_spot(b)
	var axis: Vector3 = tower.block_axis(b)
	_turn_yaw = atan2(-axis.z, axis.x)
	b.global_basis = Basis(Vector3.UP, _turn_yaw) # level in your hand
	var h := float(b.get_meta("height"))
	var top: Vector3 = b.global_position + Vector3(0, h * 0.5 + 0.004, 0)
	top.y = maxf(top.y, tower.TOP_Y + h + 0.004 + CARRY_CLEAR) # straight off the table
	_want = top
	w.hand.set_tool("carry")
	w.hand.show_hand()
	w.hand.jump_to(top, _forward())
	w.show_strain(false)
	main._sound("tap")
	main._refresh()


## The block goes where the hand goes: round the tower, not through it.
func _carry_block() -> void:
	var w = main.world
	var tower = w.tower
	var hand = w.hand
	var h := float(block.get_meta("height"))
	var grip := h * 0.5 + 0.004 # the palm sits this far above the block's middle
	var p: Vector3 = hand.target
	p.y = maxf(p.y, tower.TOP_Y + h + 0.004 + CARRY_CLEAR)
	var c: Vector3 = tower.tower_center()
	var top: float = float(_spot["top"]) + 0.012 # just clear of the top of the tower
	var bottom := p.y - grip - h * 0.5
	var dx := p.x - c.x
	var dz := p.z - c.z
	if absf(dx) < COLUMN and absf(dz) < COLUMN and bottom < top:
		if top - bottom < 0.06:
			p.y += top - bottom # nearly over: it slides onto the top
		elif absf(dx) > absf(dz):
			p.x = c.x + signf(dx) * COLUMN # it stops at the tower's side
		else:
			p.z = c.z + (signf(dz) if dz != 0.0 else 1.0) * COLUMN
	_want += p - hand.target # the thumb doesn't run on ahead of where it's stopped
	block.global_position = p - Vector3(0, grip, 0)
	var axis: Vector3 = tower.block_axis(block)
	var across := Vector3(-axis.z, 0, axis.x)
	if across.dot(_forward()) < 0.0:
		across = -across
	hand.jump_to(p, across)
	# the mark where it'll come down
	var over: bool = absf(p.x - c.x) < COLUMN and absf(p.z - c.z) < COLUMN
	w.landing.visible = over
	if over:
		w.landing.global_transform = Transform3D(block.global_basis, Vector3(block.global_position.x, tower.rest_height(block) + 0.003, block.global_position.z))


func turn_block() -> void:
	if state != "work" or not _lifted:
		return
	_turn_yaw += PI * 0.5 # always a clean quarter, however fast it's tapped
	var t := block.create_tween()
	t.tween_property(block, "global_basis", Basis(Vector3.UP, _turn_yaw), 0.15)
	main._sound("tick")


## Open the hand. Over the tower, that sets the block down on it; anywhere
## else it's back on the table.
func _let_go() -> void:
	var w = main.world
	var tower = w.tower
	_lifted = false
	w.landing.visible = false
	var c: Vector3 = tower.tower_center()
	var p: Vector3 = block.global_position
	var on_tower: bool = absf(p.x - c.x) < COLUMN and absf(p.z - c.z) < COLUMN and tower.rest_height(block) > tower.TOP_Y + tower.H * 0.5
	if on_tower:
		tower.set_down(block, int(_spot["layer"]))
		state = "placed"
		w.hand.park()
		_strip.visible = false
		_top_view.visible = false
	else:
		tower.drop(block)
		tower.active = block
		w.hand.set_tool("poke")
		w.hand.jump_to(w.hand.target + Vector3(0, 0.04, 0), _forward())
		_want = w.hand.target
	main._sound("knock")
	main._refresh()


func _done() -> void:
	if state != "placed":
		return
	state = "settle"
	_timer = 1.2
	_end_work()
	main._refresh()


## Wood on wood, while a block's sliding.
func _slide_sound(b: RigidBody3D, delta: float) -> void:
	_scrape -= delta
	if b == null or not is_instance_valid(b) or b.freeze:
		return
	if _scrape <= 0.0 and b.linear_velocity.length() > 0.035:
		_scrape = 0.16
		main._sound("scrape")


## An AI's block is out: up and onto the top.
func _carry() -> void:
	var w = main.world
	w.hand.park()
	w.show_strain(false)
	if _top_view != null:
		_top_view.visible = false
	state = "carry"
	_timer = w.tower.place_on_top(block) + 0.1
	main._sound("slap")
	main._refresh()


# ---------------------------------------------------------------- the hand cam

func _update_top_view() -> void:
	if _top_view == null or not _top_view.visible:
		return
	var hand = main.world.hand
	if not hand.visible:
		return
	var tip: Vector3 = hand.tip.global_position
	var f: Vector3 = hand.facing if state == "bot" else _forward()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)
	var side := Vector3(-f.z, 0, f.x)
	# close in, just behind and above the fingers, looking where they go
	var from := tip - f * 0.13 + Vector3.UP * 0.06 + side * 0.03
	var goal := Transform3D(Basis.looking_at((tip + f * 0.05) - from, Vector3.UP), from)
	_sub_cam.global_transform = _sub_cam.global_transform.interpolate_with(goal, 0.25)


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
		"THE TOWER. 18 layers of 3 wooden blocks. Some slide easily; some are tight. A layer stands on its middle block, or on both its sides: take anything else out from under the tower and down it comes.",
		"YOUR HAND. It's a real hand in the room: solid, and it touches everything. ONE finger on the screen moves it up, down, left and right. The PUSH / PULL strip on the right moves it away from you and back. It always points away from you.",
		"THE CAMERA. TWO fingers: drag to walk round the tower and look up and down it, pinch to zoom. ◀ ▶ step round a quarter. Walking round turns the hand with you. The round window is a camera over the hand's shoulder.",
		"TAKING A BLOCK. Not from the bottom layer, the top layer, nor the one under it while the top's unfinished. POKE it with a finger (TWO fingers push firmer; FLAT is the edge of your hand). Your fist won't go into the tower, so a poke gets a block about halfway: walk round and GRAB the end sticking out, and pull. Yank and it slips.",
		"PUTTING IT ON TOP. The first block out is yours. If it's dropped on the table, GRAB it. Carry it up and over the top (it goes round the tower, not through it), TURN it if you like, LET GO to set it down where the gold mark is, then DONE.",
		"FEEL IT. A faint ghost shows where your thumb wants the hand. The line from it to the real finger goes red, the hand shakes and the phone buzzes when a block fights back.",
		"THE SHOTGUN. Whoever's turn it is has the gun in front of them; it moves left with the turn. Bring the tower down and the player on your right shoots you: one shot and you're out. The tower's built again and the player on your left goes first. Always. Last one standing wins.",
	]


func coach() -> String:
	if not _my_turn():
		return "Watch the AIs: they test a block, and back off if the tower moves."
	if state == "work":
		if _lifted:
			return "Up and over the top. The gold mark shows where it'll land."
		if block != null:
			return "Bring the hand to your block and GRAB it."
		return "Middles are loose more often. Poke one halfway, walk round (two fingers), and GRAB the end."
	return ""
