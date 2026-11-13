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
		if ui.state == "choose" and ui._my_turn():
			# pick a block: a middle one we haven't tried this tower
			# like a person: a middle block from low down first (they're often loose)
			var b = null
			var best := 1e9
			for o in main.world.tower.blocks:
				if main.world.tower.takeable(o) and not tried.has(o):
					var score: float = int(o.get_meta("layer")) + (0.0 if int(o.get_meta("slot")) == 1 else 30.0)
					if score < best:
						best = score
						b = o
			if b == null:
				tried.clear()
				continue
			tried[b] = true
			if OS.get_environment("V") != "":
				print("  you pick L%d s%d" % [b.get_meta("layer"), b.get_meta("slot")])
			ui._choose(b)
			push_frames = 0
			thumb_y = vs.y * 0.75
			top_at = main.world.tower.blocks[-1].global_position
			ui._press(Vector2(vs.x * 0.5, thumb_y))
		elif ui.state == "pickup" and ui._my_turn():
			if step % 20 == 0:
				ui._pick_up()
				lift_y = vs.y * 0.8
				ui._press(Vector2(vs.x * 0.5, lift_y))
		elif ui.state == "lift" and ui._my_turn():
			lift_y -= 6.0 # carry it up
			if lift_y < 20.0:
				ui._release(Vector2(vs.x * 0.5, lift_y))
				lift_y = vs.y * 0.8
				ui._press(Vector2(vs.x * 0.5, lift_y))
			ui._drag(Vector2(vs.x * 0.5, lift_y))
		elif ui.state == "place" and ui._my_turn():
			# it's out: slide it a touch, turn it twice (back the same way), set it down
			if step % 30 == 0:
				# slide it over the free place first, like you would
				var spot: Vector3 = ui._spot["start"]
				ui.block.global_position = Vector3(spot.x, ui.block.global_position.y, spot.z)
				ui._set_it_down()
		elif ui.state == "placed" and ui._my_turn():
			if step % 30 == 0:
				ui._done()
		elif ui.state == "work" and ui._my_turn():
			push_frames += 1
			thumb_y -= 2.0 # a slow, steady thumb
			ui._drag(Vector2(vs.x * 0.5, thumb_y))
			var strain: float = (main.world.hand.target - main.world.hand.tip.global_position).length()
			if OS.get_environment("V") != "" and push_frames % 20 == 0:
				print("    f%d target %s tip %s blk %s strain %.3f top %s" % [push_frames, main.world.hand.target, main.world.hand.tip.global_position, ui.block.global_position, strain, main.world.tower.blocks[-1].global_position])
			# watching the tower: if the top moves, or it won't go, back off
			var sway: float = main.world.tower.blocks[-1].global_position.distance_to(top_at)
			if push_frames > 20 and (strain > 0.015 or sway > 0.008) or push_frames > 900:
				# it won't go: let go and try another
				ui._release(Vector2(vs.x * 0.5, thumb_y))
				ui._let_go_block()
	check(g.phase == "match_over" or main._humans_out, "the match finishes (tower %d, phase %s)" % [g.round_num, g.phase])
	check(n["placed"] > 0, "blocks came out and went on top (%d)" % n["placed"])
	check(n["toppled"] > 0, "towers came down (%d)" % n["toppled"])
	print("timber: %d towers, %d blocks placed (%d yours), %d came down, winner %s" % [g.round_num, n["placed"], n["mine"], n["toppled"], g.players[g.winner].name if g.winner >= 0 else "-"])
