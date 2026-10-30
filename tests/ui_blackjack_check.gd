extends SceneTree
## Shotgun Blackjack, solo against two AIs, played through the real screens:
## HIT and STAND, the AIs' turns, the shotgun and the dealer chip.
##   godot --headless --path . -s tests/ui_blackjack_check.gd

const Blackjack = preload("res://scripts/core/blackjack.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _buttons(node: Node) -> Array:
	var out := []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and not n.disabled:
			out.append(n)
		stack.append_array(n.get_children())
	out.reverse()
	return out


func _initialize() -> void:
	Engine.time_scale = 8.0
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile_name = "SAM"
	main.game_kind = "blackjack"
	main.show_menu()
	main.show_this_phone()
	main.solo_opponents = 2
	main._set_solo_level("mixed")
	main._start_solo()
	var g = main.game
	check(g is Blackjack and g.kind == "blackjack", "solo deals blackjack")
	check(main.meld_btn.text == "HIT" and main.discard_btn.text == "STAND", "HIT and STAND buttons")
	if main.world.dealing:
		await main.world.deal_finished
	await process_frame
	check(main.world._dealer_chip.visible, "the dealer chip is on the table")

	var my_hits := 0
	var my_stands := 0
	var rounds := {}
	var last_dealer: int = g.dealer
	var chip_moves := 0
	for step in range(200000):
		await process_frame
		if g.phase == "match_over" and main._overlay_kind == "match":
			break
		rounds[g.round_num] = true
		if step % 2000 == 0 and OS.get_cmdline_user_args().has("--progress"):
			print("step %d: round %d phase %s turn %d overlay %s status '%s' dealing %s fx %s" % [step, g.round_num, g.phase, g.turn, main._overlay_kind if main.overlay_layer.get_child_count() > 0 else "-", main.status_label.text, main.world.dealing, main.world.fx_busy])
		if g.dealer != last_dealer:
			last_dealer = g.dealer
			chip_moves += 1
		if main.overlay_layer.get_child_count() > 0:
			var pick = null
			for b in _buttons(main.overlay_layer):
				var t: String = b.text
				if t in ["MAIN MENU", "NEW PLAYERS", "PLAY AGAIN", "RESTART MATCH"]:
					continue
				if pick == null or t.begins_with("SHOOT") or t.begins_with("WATCH") or t.ends_with("SHOTGUN"):
					pick = b
			if main._overlay_kind == "gun" and g.gun != null and g.players[g.gun["holder"]].bot != "":
				pick = null
			if pick != null and step % 5 == 0:
				pick.pressed.emit()
			continue
		if not g.is_turn_of(0) or main.world.dealing or main.world.fx_busy or step % 3 != 0:
			continue
		if g.hand_total(0) < 16:
			main._meld_selected() # the HIT button
			my_hits += 1
		else:
			main._discard_selected() # the STAND button
			my_stands += 1
	check(g.phase == "match_over", "the blackjack match finishes (round %d, phase %s)" % [g.round_num, g.phase])
	check(my_hits > 0 and my_stands > 0, "you hit and stood (%d, %d)" % [my_hits, my_stands])
	check(chip_moves >= 1 or rounds.size() == 1, "the deal moved round the table")
	print("BLACKJACK CHECK: %d rounds, winner %s, chip moved %d times" % [g.round_num, g.players[g.winner].name if g.winner >= 0 else "-", chip_moves])
	print("BLACKJACK CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
