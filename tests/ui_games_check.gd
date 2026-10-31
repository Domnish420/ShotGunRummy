extends SceneTree
## Plays the newer cartridges solo against AIs through the real screens:
## picks the cartridge, plays a shotgun match, then the tutorial (normal mode
## with tips) to the end.
##   godot --headless --path . -s tests/ui_games_check.gd [-- gofish ...]

const Bot = preload("res://scripts/core/bot.gd")
const GoFishBot = preload("res://scripts/core/gofish_bot.gd")
const CheatBot = preload("res://scripts/core/cheat_bot.gd")
const TricksBot = preload("res://scripts/core/tricks_bot.gd")
const PresidentBot = preload("res://scripts/core/president_bot.gd")

const KINDS := ["gofish", "cheat", "hearts", "spades", "snap", "president"]

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
	Engine.time_scale = 8.0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.profile_name = "SAM"
	main.tutorial_offered = true
	var only := OS.get_cmdline_user_args()
	for kind in KINDS:
		if not only.is_empty() and not only.has(kind):
			continue
		main.show_menu()
		main.show_cartridges()
		main._pick_cartridge(kind)
		check(main.game_kind == kind and main.world._cartridge_kind == kind, "%s cartridge slotted in" % kind)
		main.normal_mode = false
		main.solo_opponents = 2
		main._set_solo_level("mixed")
		main._start_solo()
		check(main.game.kind == kind and main.mode_ui != null, "%s: the table has its own screen" % kind)
		await _play(kind, "shotgun")
		main.show_menu()
		main.show_cartridges()
		main._start_tutorial()
		check(main.tutorial and not main.game.options["shotgun"], "%s tutorial is normal mode" % kind)
		await _play(kind, "tutorial")
	print("GAMES CHECK OK" if fails == 0 else "%d failures" % fails)
	quit(1 if fails > 0 else 0)


func _play(kind: String, what: String) -> void:
	var g = main.game
	var coached := false
	var my_moves := 0
	for step in range(300000):
		await process_frame
		if g.phase == "match_over" and main._overlay_kind == "match":
			break
		if main.tutorial and main.coach_label.visible and main.coach_label.text.begins_with("TIP"):
			coached = true
		if main.overlay_layer.get_child_count() > 0:
			var pick = null
			for b in _buttons(main.overlay_layer):
				var t: String = b.text
				if t in ["MAIN MENU", "NEW PLAYERS", "PLAY AGAIN", "RESTART MATCH", "CANCEL"]:
					continue
				if pick == null or t.begins_with("SHOOT") or t.begins_with("WATCH") or t.ends_with("SHOTGUN"):
					pick = b
			if main._overlay_kind == "gun" and g.gun != null and g.players[g.gun["holder"]].bot != "":
				pick = null
			if pick != null and step % 5 == 0:
				pick.pressed.emit()
			continue
		if kind == "snap" and g.phase == "play" and g.snap_ready() and not main.world.dealing and step % 9 == 0 and g.flips % 2 == 0:
			main.mode_ui._snap_pressed() # race the AIs
			continue
		if not g.is_turn_of(0) or main.world.dealing or main.world.fx_busy or step % 3 != 0:
			continue
		my_moves += 1
		match kind:
			"gofish":
				var ask: Array = GoFishBot.choose_ask(g, 0, "normal")
				if ask.is_empty():
					continue
				main.mode_ui.rank = ask[1]
				main.mode_ui._ask(ask[0])
			"cheat":
				if g.pending_win >= 0:
					if my_moves % 2 == 0:
						main.mode_ui._call_pressed()
					else:
						main.mode_ui._first_pressed()
				elif g.can_call(0) and my_moves % 5 == 0:
					main.mode_ui._call_pressed()
				else:
					main.selected = CheatBot.choose_play(g, 0, "normal")
					main.mode_ui._first_pressed()
			"hearts", "spades":
				if g.kind == "spades" and g.bidding:
					main.mode_ui._bid(TricksBot.choose_bid(g, 0, "normal"))
				else:
					var legal: Array = g.legal_cards(0)
					if legal.is_empty():
						continue
					main.selected = [TricksBot.choose_card(g, 0, "normal", legal)["id"]]
					main.mode_ui._first_pressed()
			"snap":
				main.mode_ui._flip_pressed()
			"president":
				var ids: Array = PresidentBot.choose_play(g, 0, "normal")
				if ids.is_empty():
					main.mode_ui._pass_pressed()
				else:
					main.selected = ids
					main.mode_ui._play_pressed()
	check(g.phase == "match_over", "%s %s: the match finishes (round %d, phase %s)" % [kind, what, g.round_num, g.phase])
	check(my_moves > 0, "%s %s: you played" % [kind, what])
	if what == "tutorial":
		check(coached, "%s tutorial: tips showed" % kind)
	if kind == "snap":
		var ai_snaps := 0
		for line in main.log_lines:
			if line.contains(" SNAPS ") and not line.begins_with("SAM"):
				ai_snaps += 1
		check(ai_snaps > 0, "snap %s: the AIs snap out of turn" % what)
	print("%s %s: %d rounds, winner %s" % [kind, what, g.round_num, g.players[g.winner].name if g.winner >= 0 else "-"])
