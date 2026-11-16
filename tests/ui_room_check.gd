extends SceneTree
## The room (the menu): look round, tap each station, and come back.
##   godot --headless --path . -s tests/ui_room_check.gd

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _frames(n: int = 4) -> void:
	for i in range(n):
		await process_frame


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	main.profile_name = "SAM"
	main.tutorial_offered = true
	main.show_menu()
	await _frames(50)
	var w = main.world
	check(w.in_room() and w._focus == "", "the menu is the room")
	main.sound_on = true
	main.music_on = true
	main._play_music("room", true)
	await _frames(30)
	check(main._music_id == "room" and main._music_player.playing, "the saloon tune plays in the room")
	for k in w.STATIONS:
		check(w._signs[k].visible == w._here(k), "%s has its sign up (only in its own room)" % k)
	# look round: drag left, the view turns
	var before: float = w._yaw
	w.room_look(Vector2(-120, 0))
	check(w._yaw > before, "dragging turns you round")
	w.room_look(Vector2(-100000, 0))
	check(w._yaw <= 2.3, "only so far round")
	w._yaw = 0.0
	await _frames(40)
	# each station: aim at it, tap its sign, and you go there
	var aims := {"table": 0.0, "door": -0.2, "bar": 0.9, "gacha": -0.75, "wardrobe": -1.45, "computer": 1.34}
	var expect := {"table": "table", "door": "door", "bar": "bar", "gacha": "gacha", "wardrobe": "wardrobe", "computer": "computer"}
	for k in aims:
		w._yaw = aims[k]
		w._view_yaw = aims[k] # no slow turn round: straight there
		w._room_hold = 0.0
		if w._cam_tween != null and w._cam_tween.is_valid():
			w._cam_tween.kill() # the walk back from the last station
		w._pitch = -0.1
		await _frames(40)
		var sign_at: Vector2 = w.camera.unproject_position(w.STATIONS[k]["sign"])
		var picked: String = w.room_pick(sign_at)
		check(picked == k, "tapping the %s sign picks it (got '%s')" % [k, picked])
		main._go_station(picked)
		await _frames(20)
		check(w._focus == expect[k], "%s: you go to it (focus '%s')" % [k, w._focus])
		check(not w._signs[k].visible, "%s: the signs go off while you're there" % k)
		main.show_menu()
		await _frames(30)
		check(w.in_room() and w._focus == "", "%s: BACK brings you to the room" % k)
	# a tap on nothing does nothing
	w._yaw = 0.0
	await _frames(40)
	check(w.room_pick(Vector2(2, 2)) == "", "tapping the ceiling goes nowhere")
	# starting a game leaves the room
	main.game_kind = "rummy"
	main.normal_mode = false
	main.solo_opponents = 2
	main._start_solo()
	await _frames(10)
	check(not w.in_room(), "at the table, the room's signs are gone")
	await _frames(60)
	check(main._music_id == "rummy" and main._music_player.playing, "the table plays the game's own twist on the tune (%s)" % main._music_id)
	main._toggle_music()
	check(not main._music_player.playing, "MUSIC off stops it")
	main._toggle_music()
	await _frames(30)
	check(main._music_player.playing, "and back on")
	print("ROOM CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
