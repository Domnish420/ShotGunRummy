extends SceneTree
## Plays a whole 4-player LAN match: one host, two players and an AI the host
## runs. Each phone is a full copy of the game with its own network
## connection, all inside this one process.
##   godot --headless --path . -s tests/net_test.gd
##
## Checks along the way that every phone sees its own hand exactly as the host
## has it, and never sees anyone else's.

const Cards = preload("res://scripts/core/cards.gd")
const Bot = preload("res://scripts/core/bot.gd")

var phones: Array = [] # Main nodes: [host, player 1, player 2]
var failures := 0


func _initialize() -> void:
	Engine.time_scale = 6.0 # the AI and the animations run at speed
	for tag in ["Host", "Alex", "Jo"]:
		var holder := Node.new()
		holder.name = tag
		root.add_child(holder)
		set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + tag))
		var main: Node = load("res://scenes/main.tscn").instantiate()
		holder.add_child(main)
		phones.append(main)
	_run()


func _frames(n: int = 2) -> void:
	for i in range(n):
		await process_frame


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


func _overlay_buttons(main) -> Array:
	var out := []
	var stack: Array = [main.overlay_layer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and not n.disabled:
			out.append(n)
		stack.append_array(n.get_children())
	out.reverse()
	return out


func _run() -> void:
	await _frames(4)
	var host = phones[0]
	host.game_kind = "rummy" # settings may remember another game
	host.normal_mode = false
	host._name_edit.text = "sam"
	host._on_host_pressed()
	check(host.session.is_host(), "host is hosting")

	var p1 = phones[1]
	p1._name_edit.text = "alex"
	p1._on_join_pressed()
	for i in range(120):
		await _frames(1)
		if not p1.session.lobbies.is_empty():
			break
	print("lobby discovery: %s" % ("found %s" % [p1.session.lobbies.keys()] if not p1.session.lobbies.is_empty() else "nothing (broadcast blocked here), joining by IP"))
	p1._ip_edit.text = "127.0.0.1"
	p1._join_typed_ip()

	var p2 = phones[2]
	p2._name_edit.text = "jo"
	p2._on_join_pressed()
	p2._ip_edit.text = "127.0.0.1"
	p2._join_typed_ip()

	for i in range(300):
		await _frames(1)
		if host.session.names.size() == 3 and p2.session.names.size() == 3:
			break
	check(host.session.names == ["SAM", "ALEX", "JO"], "lobby has everyone: %s" % [host.session.names])
	check(p1.session.names == host.session.names, "players see the same lobby")
	host.session.add_bot("hard")
	await _frames(6)
	check(p1.session.names.size() == 4 and p1.session.bots[3] == "hard", "everyone sees the AI player: %s %s" % [p1.session.names, p1.session.bots])

	host.session.start_match()
	await _frames(10)
	check(p1.game.players[3].bot == "hard", "the AI seat is marked")
	check(p1.session.my_seat == 1 and p2.session.my_seat == 2, "seats assigned")
	check(p1.game != null and p1.game.players.size() == 4, "player 1 has the table")
	check(p1.game.players[0].look.get("name", "") == host.my_look.get("name", "?"), "everyone sees the host's character")

	await _play_match()
	await _test_blackjack()
	await _test_leaving()
	print("%d failures" % failures)
	quit(1 if failures > 0 else 0)


## Plays the match on every phone until all of them show the end screen.
func _play_match() -> void:
	var host = phones[0]
	var steps := 0
	var rounds_seen := {}
	while steps < 40000:
		steps += 1
		await _frames(1)
		var real = host.session.game
		if real == null:
			check(false, "host game vanished")
			break
		_check_views(real)
		rounds_seen[real.round_num] = true
		var all_done := true
		for main in phones:
			if main.game == null or main.game.phase != "match_over" or main._overlay_kind != "match":
				all_done = false
		if all_done:
			print("NET OK: %s match finished after %d rounds, winner %s" % [real.kind, real.round_num, real.players[real.winner].name])
			break
		for main in phones:
			_drive(main)
	if steps >= 40000:
		check(false, "match didn't finish")


## A lobby set to Blackjack plays Blackjack on every phone.
func _test_blackjack() -> void:
	var host = phones[0]
	host.show_menu()
	await _frames(4)
	host._name_edit.text = "sam"
	host._on_host_pressed()
	host._cycle_lobby_game()
	check(host.session.game_kind == "blackjack", "the host picks Blackjack")
	for main in [phones[1], phones[2]]:
		main.show_menu()
		main._name_edit.text = "x"
		main._on_join_pressed()
		main._ip_edit.text = "127.0.0.1"
		main._join_typed_ip()
	for i in range(300):
		await _frames(1)
		if host.session.names.size() == 3 and phones[2].session.names.size() == 3:
			break
	check(phones[1].session.game_kind == "blackjack", "players see the lobby is Blackjack")
	host.session.add_bot("normal")
	await _frames(6)
	host.session.start_match()
	await _frames(10)
	check(phones[1].game != null and phones[1].game.kind == "blackjack", "player 1's table is Blackjack")
	await _play_match()
	host.game_kind = "rummy"


## A player walking out mid-game sends everyone back to the menu with a note.
func _test_leaving() -> void:
	var host = phones[0]
	host.show_menu()
	await _frames(4)
	host._name_edit.text = "sam"
	host._on_host_pressed()
	for main in [phones[1], phones[2]]:
		main.show_menu()
		main._name_edit.text = "x"
		main._on_join_pressed()
		main._ip_edit.text = "127.0.0.1"
		main._join_typed_ip()
	for i in range(300):
		await _frames(1)
		if host.session.names.size() == 3:
			break
	host.session.start_match()
	await _frames(20)
	check(phones[2].session.in_match, "second match started")
	phones[2].show_menu() # walks out
	for i in range(300):
		await _frames(1)
		if host.session.mode == "offline" and phones[1].session.mode == "offline":
			break
	check(host.session.mode == "offline" and phones[1].session.mode == "offline", "everyone is back at the menu")
	check(host.round_label == null and phones[1].round_label == null, "the table is gone")
	print("leaving: host and other player returned to the menu")


## Every phone's mirror must match the host for its own seat, and hide the rest.
func _check_views(real) -> void:
	for seat in range(1, phones.size()):
		var g = phones[seat].game
		if g == null or g.players.is_empty() or phones[seat]._pending_cb.is_valid():
			continue
		if phones[seat].session.version != phones[0].session.version:
			continue # an update is on its way
		check(g.round_num == real.round_num and g.phase == real.phase and g.turn == real.turn, "seat %d agrees on round, phase and turn" % seat)
		check(Cards.ids_of(g.players[seat].hand) == Cards.ids_of(real.players[seat].hand), "seat %d sees its own hand" % seat)
		for other in range(g.players.size()):
			if other == seat:
				continue
			for c in g.players[other].hand:
				var revealed: bool = c.get("shown", false) or real.players[other].exposed # Flashbang, Spotlight
				if not c.get("hidden", false) and not revealed:
					check(false, "seat %d can see seat %d's %s" % [seat, other, c["id"]])
					return
			check(g.players[other].hand.size() == real.players[other].hand.size(), "card counts match")
		for c in g.stock:
			if not c.get("hidden", false):
				check(false, "seat %d can see the stock" % seat)
				return


## Plays this phone's part: answer its overlays, take its turn.
func _drive(main) -> void:
	if main.game == null or main._pending_cb.is_valid():
		return
	if main.overlay_layer.get_child_count() > 0:
		var pick = null
		for b in _overlay_buttons(main):
			var t: String = b.text
			if t.begins_with("LEAVE") or t == "MAIN MENU" or t.begins_with("BACK TO"):
				continue
			if t.begins_with("PLAY AGAIN"):
				continue
			if pick == null or t.begins_with("SHOOT"):
				pick = b
		if pick != null:
			pick.pressed.emit()
		return
	var game = main.game
	var seat: int = main._me()
	if not game.is_turn_of(seat):
		return
	var me = game.players[seat]
	if game.kind == "blackjack":
		if game.hand_total(seat) < 16:
			main._hit()
		else:
			main._stand()
		return
	if game.phase == "draw":
		var top: Dictionary = game.top_discard()
		if not top.is_empty() and Bot.helps(game, me.hand, top):
			main._draw_discard()
		else:
			main._draw_stock()
		return
	var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank) if game.can_place(seat) else {"melds": []}
	if not best["melds"].is_empty():
		main.selected = Cards.ids_of(best["melds"][0])
		main._meld_selected()
		return
	for c in (me.hand if game.can_place(seat) else []):
		for m in game.melds:
			if Cards.can_lay_off(m, [c], game.trump_rank):
				main.selected = [c["id"]]
				main._lay_off_on(m["id"])
				return
	main.selected = [Bot.choose_discard(game, seat)]
	main._discard_selected()
