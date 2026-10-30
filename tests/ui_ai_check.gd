extends SceneTree
## Solo against the AI: one person and three AIs (easy, normal, hard) play a
## whole match through the real screens (after checking the pass & play
## setup can seat AIs too). The person's hand is never
## hidden (nobody to pass the phone to), the AIs play their own turns and
## shoot on their own, and nobody can make a move for an AI.
##   godot --headless --path . -s tests/ui_ai_check.gd

const Cards = preload("res://scripts/core/cards.gd")
const Bot = preload("res://scripts/core/bot.gd")

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
	main.player_names = ["SAM", "PLAYER 2", "PLAYER 3", "PLAYER 4"]
	main.setup_bots = [] # everyone a person (settings may remember AIs)
	main.hide_hands = true
	main.show_setup()
	main._cycle_setup_bot(1) # easy
	main._cycle_setup_bot(2)
	main._cycle_setup_bot(2) # normal
	for i in range(3):
		main._cycle_setup_bot(3) # hard
	check(main.setup_bots == ["", "easy", "normal", "hard"], "setup has the AIs: %s" % [main.setup_bots])
	check(not main.player_names[1].begins_with("PLAYER"), "an AI gets a name: %s" % [main.player_names])
	# play it through VS AI (solo): you and three AIs, one of each level
	main.profile_name = "SAM"
	main.show_this_phone()
	main.show_solo()
	main.solo_opponents = 3
	main._set_solo_level("mixed")
	main._start_solo()
	var g = main.game
	check(main.local_mode == "solo" and g.players.size() == 4, "solo deals you and 3 AIs")
	var levels := []
	for p in g.players:
		levels.append(p.bot)
	check(levels == ["", "easy", "normal", "hard"], "mixed AIs: %s" % [levels])
	check(g.players[0].name == "SAM", "you sit in seat 1")

	var ai_turns := 0
	var ai_shots := 0
	var last_turn := -1
	var poked := false
	for step in range(200000):
		await process_frame
		if g.phase == "match_over" and main._overlay_kind == "match":
			break
		if main._hand_hidden or main._overlay_kind == "pass":
			check(false, "the hand was hidden with only one person playing")
			break
		if g.is_turn_of(g.turn) and g.turn != last_turn:
			last_turn = g.turn
			if g.players[g.turn].bot != "":
				ai_turns += 1
				check(main._me() == 0, "the screen stays on SAM during an AI's turn")
				if not poked and g.phase == "draw" and not main.world.dealing:
					# tapping the stock on an AI's turn does nothing
					poked = true
					var stock: int = g.stock.size()
					main._act("draw_stock", [], main._ignore_result)
					check(g.stock.size() == stock and g.phase == "draw", "you can't play an AI's turn")
		if main.overlay_layer.get_child_count() > 0:
			var pick = null
			for b in _buttons(main.overlay_layer):
				var t: String = b.text
				if t in ["MAIN MENU", "NEW PLAYERS", "PLAY AGAIN", "RESTART MATCH"]:
					continue
				if pick == null or t.begins_with("SHOOT") or t.begins_with("WATCH") or t.ends_with("SHOTGUN"):
					pick = b
			if main._overlay_kind == "gun" and g.gun != null and g.players[g.gun["holder"]].bot != "":
				pick = null # the AI is aiming; wait for it
			if pick != null and step % 5 == 0:
				pick.pressed.emit()
			continue
		if not g.is_turn_of(0) or main.world.dealing or main.world.fx_busy:
			continue
		if step % 3 != 0:
			continue
		var me = g.players[0]
		if g.phase == "draw":
			main._draw_stock()
			continue
		var best: Dictionary = Cards.best_partition(me.hand, g.trump_rank) if g.can_place(0) else {"melds": []}
		if not best["melds"].is_empty():
			main.selected = Cards.ids_of(best["melds"][0])
			main._meld_selected()
			continue
		main.selected = [Bot.choose_discard(g, 0)]
		main._discard_selected()
	for line in main.log_lines:
		if line.contains(" shoots ") and not line.begins_with("SAM"):
			ai_shots += 1
	check(g.phase == "match_over", "the match finishes (round %d, phase %s)" % [g.round_num, g.phase])
	check(ai_turns > 5, "the AIs took turns (%d)" % ai_turns)
	print("AI CHECK: %d rounds, %d AI turns, %d AI shots, winner %s" % [g.round_num, ai_turns, ai_shots, g.players[g.winner].name if g.winner >= 0 else "-"])
	print("AI CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)
