extends SceneTree
## The gacha machine through the real screens: walk over to it, spin, watch
## the capsule drop and open, check the prize is yours and the coin is spent,
## spin again, and run out of coins.
##   godot --headless --path . -s tests/ui_gacha_check.gd

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
	Engine.time_scale = 4.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	main.profile_name = "SAM"
	var keep_owned: Dictionary = main.owned.duplicate()
	var keep_coins: int = main.coins
	main.owned = {}
	main.coins = 2
	main.show_gacha()
	await _frames(4)
	check(main.world._gacha_view, "the camera goes to the machine")
	for spin in range(2):
		var before: int = main.owned.size()
		main._spin_gacha()
		check(main._gacha_busy and main.coins == 1 - spin, "spin %d: a coin goes in" % spin)
		main._spin_gacha() # mashing SPIN does nothing while it's going
		check(main.coins == 1 - spin, "spin %d: only one coin per spin" % spin)
		var waited := 0
		while main._overlay_kind != "reveal" and waited < 4000:
			await process_frame
			waited += 1
		check(main._overlay_kind == "reveal", "spin %d: the capsule opens on a prize" % spin)
		check(main.owned.size() == before + 1, "spin %d: the prize is yours" % spin)
		check(not main.world.gacha_machine.busy, "spin %d: the machine is ready again" % spin)
		main._close_overlay()
		main.show_gacha()
		await _frames(4)
	check(main.coins == 0, "both coins spent")
	main._spin_gacha()
	check(not main._gacha_busy and main.owned.size() == 2, "no coins, no spin")
	main.show_menu()
	await _frames(4)
	check(not main.world._gacha_view, "back at the menu, away from the machine")
	main.owned = keep_owned
	main.coins = keep_coins
	main._save_settings()
	print("GACHA CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
