extends SceneTree
## Walks into the party room and plays darts through the real screens: each
## game (shootout, around the clock, 301) as a shotgun match against AIs,
## tapping to stop the dots like a person, then the demo.
##   godot --headless --path . -s tests/ui_darts_check.gd [-- shootout ...]

const Darts = preload("res://scripts/core/darts.gd")

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
	Engine.time_scale = 6.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile_name = "SAM"
	main.tutorial_offered = true
	main.show_menu()
	check(main.world.room_pick(Vector2(-1, -1)) == "" and main.world.room_id == "bar", "you start in the bar")
	main._go_station("party")
	for i in range(240):
		await process_frame
		if main.world.room_id == "party":
			break
	check(main.world.room_id == "party" and main.world._party_set.visible and not main.world._bar_set.visible, "through the purple door: the party room")
	var only := OS.get_cmdline_user_args()
	for m in Darts.MODES:
		if not only.is_empty() and not only.has(m):
			continue
		main._go_station("darts")
		main._set_darts_mode(m)
		check(main.game_kind == "darts" and main.darts_mode == m, "%s: picked at the board" % m)
		main.normal_mode = false
		main.solo_opponents = 2
		main.solo_level = "mixed"
		main._start_solo()
		check(main.game.kind == "darts" and main.game.mode() == m, "%s: the match is that game" % m)
		await _play(m)
		main.show_menu()
		check(main.world.room_id == "party", "%s: back in the party room after" % m)
	if only.is_empty() or only.has("demo"):
		main._go_station("darts")
		main._start_tutorial()
		var g = main.game
		var shown := 0
		var last := ""
		for step in range(200000):
			await process_frame
			if main._lesson_showing() and main._lesson_text.text != last:
				last = main._lesson_text.text
				shown += 1
			if main.demo_stage == "practice":
				break
		var left := 0
		for l in main._lessons:
			if not l[2]:
				left += 1
		check(main.demo_stage == "practice" and left == 0, "demo: every rule explained, then over to you (%d left)" % left)
		print("darts demo: %d lessons, %d rounds watched" % [shown, g.round_num])
	main._go_station("back")
	for i in range(240):
		await process_frame
		if main.world.room_id == "bar":
			break
	check(main.world.room_id == "bar" and main.world._bar_set.visible, "and back to the bar")
	print("DARTS CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)


func _play(m: String) -> void:
	var g = main.game
	var throws := 0
	var ai_lines := 0
	var was_ghost := false
	for step in range(400000):
		await process_frame
		if (g.phase == "match_over" or main._humans_out) and main._overlay_kind == "match":
			break
		if main.mode_ui != null and main.mode_ui._ghosting and not was_ghost:
			ai_lines += 1
		was_ghost = main.mode_ui != null and main.mode_ui._ghosting
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
			if main._overlay_kind == "gun" and g.gun != null and g.players[g.gun["holder"]].bot != "":
				pick = null
			if pick != null and step % 5 == 0:
				pick.pressed.emit()
			continue
		var aim = main.mode_ui.aim
		# tap when the dot's somewhere near the middle of the board, like a person would try to
		if aim.stage != "" and not aim.ghost and aim.dot.length() < 0.6 and step % 2 == 0:
			if aim.stage == "line2":
				throws += 1
			check(main.mode_ui.table_tap(Vector2(360, 640)), "%s: a tap stops the dot" % m)
	check(g.phase == "match_over" or main._humans_out, "%s: the match finishes (round %d, phase %s)" % [m, g.round_num, g.phase])
	check(throws > 0, "%s: you threw" % m)
	check(ai_lines > 0, "%s: the AIs' aim was shown" % m)
	print("darts %s: %d rounds, %d of your darts, %d AI aims shown, winner %s" % [m, g.round_num, throws, ai_lines, g.players[g.winner].name if g.winner >= 0 else "-"])
