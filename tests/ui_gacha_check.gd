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
	# the first spin by hand: drag the coin in, turn the crank, tap it open
	var m = main.world.gacha_machine
	check(main._gacha_step == "coin" and m.coin_waiting, "a coin is waiting to go in")
	var first_owned: int = main.owned.size()
	m.hold_coin(m.coin_point() + Vector3(0.05, 0, 0)) # dragged, but let go away from the slot
	m.drop_coin()
	check(main.coins == 2 and main._gacha_step == "coin", "letting go away from the slot keeps the coin")
	main._gacha_coin_in()
	check(main.coins == 1, "in the slot: the coin's spent")
	var w := 0
	while main._gacha_step != "crank" and w < 600:
		await process_frame
		w += 1
	check(main._gacha_step == "crank", "then you turn the crank")
	for i in range(24): # a turn and a half (16 eighths a turn)
		main._gacha_crank(PI / 8.0)
	check(main._gacha_step == "crank" and not m.crank_done(), "not round enough yet")
	for i in range(8):
		main._gacha_crank(-PI / 8.0) # backwards counts too
	check(main._gacha_step == "drop", "twice round: a capsule drops")
	w = 0
	while main._gacha_step != "tap" and w < 600:
		await process_frame
		w += 1
	check(main._gacha_step == "tap", "then you tap it")
	w = 0
	while main._overlay_kind != "reveal" and w < 3000:
		if main._gacha_step == "tap":
			main._gacha_tap()
		await process_frame
		w += 1
	check(main._overlay_kind == "reveal" and main.owned.size() == first_owned + 1, "tapped open: a prize")
	main._close_overlay()
	main.show_gacha()
	await _frames(4)
	main.coins = 2
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
	check(not main._gacha_auto and main.owned.size() == 3, "no coins, no spin (%d prizes)" % main.owned.size())
	main.show_menu()
	await _frames(4)
	check(not main.world._gacha_view, "back at the menu, away from the machine")
	main.owned = keep_owned
	main.coins = keep_coins
	main._save_settings()
	print("GACHA CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
