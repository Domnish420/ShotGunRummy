extends SceneTree
## Watches every cartridge's DEMO play itself: every rule gets explained,
## then it hands over to your practice rounds.
##   godot --headless --path . -s tests/ui_demo_check.gd [-- rummy ...]

const Games = preload("res://scripts/core/games.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _initialize() -> void:
	Engine.time_scale = 10.0
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile_name = "SAM"
	main.tutorial_offered = true
	var only := OS.get_cmdline_user_args()
	for kind in Games.kinds():
		if not only.is_empty() and not only.has(kind):
			continue
		main.show_menu()
		main.game_kind = kind
		main.show_cartridges()
		main._start_demo()
		var g = main.game
		check(main.demo_stage == "watch" and g.players[0].bot != "" and g.options["shotgun"], "%s: the demo plays itself, in shotgun mode" % kind)
		var shown := []
		var last := ""
		var at_start := 0
		for step in range(300000):
			await process_frame
			if main._lesson_showing() and main._lesson_text.text != last:
				last = main._lesson_text.text
				shown.append(last)
				if main.demo_stage == "watch":
					at_start += 1
			if main.demo_stage == "practice":
				break
		var left := 0
		for l in main._lessons:
			if not l[2]:
				left += 1
		check(main.demo_stage == "practice", "%s: hands over to practice" % kind)
		check(left == 0 and shown.size() >= main._lessons.size(), "%s: every rule explained (%d shown, %d left)" % [kind, shown.size(), left])
		check(main.game.players[0].bot == "" and main.coach_label != null, "%s: in the practice you play" % kind)
		print("%s demo: %d lessons (%d as they happened), %d rounds watched" % [kind, shown.size(), at_start, g.round_num])
	print("DEMO CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
