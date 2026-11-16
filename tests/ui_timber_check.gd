extends SceneTree
## TIMBER through the real screens: into the party room, the board game
## shelf, then a match against two AIs. On your turns a thumb taps a block
## and drags up the screen to push it, backs off (✕) if it won't go, and
## tries another. Plays till the match is over (or you're out), then the demo.
##   godot --headless --path . -s tests/ui_timber_check.gd [-- nodemo]

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _buttons(node: Node) -> Array:
	var out := []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and not n.disabled and n.is_visible_in_tree():
			out.append(n)
		stack.append_array(n.get_children())
	out.reverse()
	return out


func _initialize() -> void:
	Engine.time_scale = float(OS.get_environment("TS")) if OS.get_environment("TS") != "" else 3.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile_name = "SAM"
	main.tutorial_offered = true
	main.world.goto_room("party")
	main.show_menu()
	main._go_station("boxes")
	check(main.game_kind == "timber", "the shelf is TIMBER's")
	main.normal_mode = false
	main.solo_opponents = 2
	main.solo_level = "normal"
	main._start_solo()
	check(main.game != null and main.game.kind == "timber" and main.mode_ui != null, "a TIMBER match starts")
	await _play()
	if not OS.get_cmdline_user_args().has("nodemo"):
		main._go_station("boxes")
		main._start_tutorial()
		for step in range(200000):
			await process_frame
			if main.demo_stage == "practice":
				break
		var left := 0
		for l in main._lessons:
			if not l[2]:
				left += 1
		check(main.demo_stage == "practice" and left == 0, "demo: every rule explained, then over to you (%d left)" % left)
	print("TIMBER CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)


func _play() -> void:
	var g = main.game
	var ui = main.mode_ui
	var n := {"placed": 0, "toppled": 0, "mine": 0} # (a lambda can't change plain locals)
	g.event.connect(func(k, d):
		if k == "placed":
			n["placed"] += 1
			if int(d["seat"]) == 0:
				n["mine"] += 1
		elif k == "timber":
			n["toppled"] += 1
			print("  TIMBER on seat %d after %d blocks at %.1fs: %s (ui state %s)" % [d["seat"], d["turns"], Time.get_ticks_msec() / 1000.0, main.world.tower.fall_reason, ui.state])
		elif k == "turn_start":
			print("  turn: seat %d at %.1fs" % [d["seat"], Time.get_ticks_msec() / 1000.0]))
	var vs: Vector2 = main.get_viewport_rect().size
	var tried := {}
	var busy := [false] # your hand's mid-turn
	var push_frames := 0
	var lift_y := 0.0
	var top_at := Vector3.ZERO
	var thumb_y := 0.0
	for step in range(600000):
		await process_frame
		if (g.phase == "match_over" or main._humans_out) and main._overlay_kind == "match":
			break
		if main.overlay_layer.get_child_count() > 0:
			if main._aiming:
				var ts: Array = main._gun_targets()
				if not ts.is_empty() and step % 5 == 0:
					main._shoot_seat(ts[0])
				continue
			var pick = null
			for b in _buttons(main.overlay_layer):
				var t: String = b.text
				if t in ["MAIN MENU", "BACK TO THE ROOM", "NEW PLAYERS", "PLAY AGAIN", "RESTART MATCH", "CANCEL"]:
					continue
				if pick == null or t.begins_with("SHOOT") or t.begins_with("WATCH") or t.ends_with("SHOTGUN"):
					pick = b
			if pick != null and step % 5 == 0:
				pick.pressed.emit()
			continue
		if ui.state == "work" and ui._my_turn() and not busy[0]:
			busy[0] = true
			_take_turn(ui, busy)
	check(g.phase == "match_over" or main._humans_out, "the match finishes (tower %d, phase %s)" % [g.round_num, g.phase])
	check(n["placed"] > 0, "blocks came out and went on top (%d)" % n["placed"])
	check(n["toppled"] > 0, "towers came down (%d)" % n["toppled"])
	print("timber: %d towers, %d blocks placed (%d yours), %d came down, winner %s" % [g.round_num, n["placed"], n["mine"], n["toppled"], g.players[g.winner].name if g.winner >= 0 else "-"])


## Your turn, played like a person with the free hand: poke a middle block
## that holds nothing up about halfway, take the hand back out, walk round,
## GRAB the end (or the block, if it's dropped out), pull it out, carry it up
## and over the top, let go, DONE.
func _take_turn(ui, busy: Array) -> void:
	var w = main.world
	var t = w.tower
	var h = w.hand
	var b = null
	var best := 1e9
	for o in t.blocks:
		if not t.takeable(o):
			continue
		var left := {}
		for q in t.blocks:
			if q != o and not t.removed.has(q) and int(q.get_meta("layer")) == int(o.get_meta("layer")):
				left[int(q.get_meta("slot"))] = true
		var safe: bool = left.has(1) or (left.has(0) and left.has(2))
		var score: float = int(o.get_meta("layer")) + (0.0 if safe else 100.0)
		if score < best:
			best = score
			b = o
	if b == null:
		busy[0] = false
		return
	var axis: Vector3 = t.block_axis(b)
	w.tower_yaw = atan2(-axis.x, -axis.z)
	for i in range(10): await process_frame
	var start: Vector3 = b.global_position - axis * (t.L * 0.5 + 0.03)
	ui._want = start
	h.jump_to(start, axis)
	for i in range(200):
		if ui.state != "work": break
		ui.push_hand(4.0)
		await process_frame
	for i in range(120):
		if ui.state != "work": break
		ui.push_hand(-5.0)
		await process_frame
	if ui.state != "work":
		busy[0] = false
		return
	w.tower_yaw += PI
	for i in range(20): await process_frame
	var at: Vector3 = b.global_position + axis * (t.L * 0.5 + 0.012)
	if ui.block != null: # it's dropped out already: reach for it where it lies
		var outward: Vector3 = ui.block.global_position - t.tower_center()
		outward.y = 0.0
		at = ui.block.global_position + outward.normalized() * 0.09 + Vector3(0, 0.02, 0)
	ui._want = at
	h.jump_to(at, -axis)
	for i in range(10): await process_frame
	ui.grab()
	for i in range(500):
		if ui.state != "work" or ui._lifted: break
		ui.push_hand(-2.5)
		await process_frame
	if ui.state != "work" or not ui._lifted:
		busy[0] = false # slipped, or it came down: the main loop tries again
		return
	var blk = ui.block
	for i in range(600):
		if ui.state != "work" or h.target.y > t.height() + 0.12: break
		ui.move_hand(Vector2(0, -6))
		await process_frame
	for i in range(400):
		if ui.state != "work": break
		# over the first free place in the top layer
		var goal: Vector3 = ui._spot["start"]
		var f: Vector3 = ui._forward()
		var right := Vector3(-f.z, 0, f.x)
		var side: float = (goal - blk.global_position).dot(right)
		var ahead: float = (goal - blk.global_position).dot(f)
		if absf(side) > 0.008:
			ui.move_hand(Vector2(signf(side) * 4.0, 0))
		elif absf(ahead) > 0.008:
			ui.push_hand(signf(ahead) * 4.0)
		else:
			break
		await process_frame
	for i in range(20): await process_frame
	if OS.get_environment("V") != "":
		print("    you set it down at %s (spot %s, layer %d), state %s lifted %s" % [blk.global_position, ui._spot["start"], ui._spot["layer"], ui.state, ui._lifted])
	if ui.state == "work" and ui._lifted:
		ui.grab() # let go
	for i in range(60): await process_frame
	if ui.state == "placed":
		ui._done()
	for i in range(30): await process_frame
	busy[0] = false
