extends SceneTree
## Taps the 3D table where the stock, discard pile, a hand card and a meld are
## drawn, and checks each tap finds the right thing.
##   godot --headless --path . -s tests/ui_pick_check.gd

const Cards = preload("res://scripts/core/cards.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player_names = ["SAM", "ALEX"]
	main.setup_bots = [] # everyone a person (settings may remember AIs)
	main.game_kind = "rummy" # settings may remember another game
	main.normal_mode = false
	main.hide_hands = false
	main._start_from_setup()
	var g = main.game
	for p in g.players:
		p.turns_taken = 2
	# the meld's cards come out of the deck first, so no card is in two places
	var meld_cards := Cards.parse_many("2C 3C 4C")
	var taken := Cards.ids_of(meld_cards)
	for pile in [g.stock, g.discard_pile] + g.players.map(func(p): return p.hand):
		for c in pile.duplicate():
			if c.has("id") and taken.has(c["id"]):
				pile.erase(c)
	if g.discard_pile.is_empty():
		for c in g.stock:
			if not c.has("item"):
				g.stock.erase(c)
				g.discard_pile.append(c)
				break
	g.melds.append({"id": "mx", "type": "run", "cards": meld_cards, "owner": 1})
	main._refresh()
	if main.world.dealing:
		await main.world.deal_finished
	for i in range(30):
		await physics_frame
	var world = main.world
	var cam: Camera3D = world.camera
	var hits := {}
	for id in world._cards:
		var c = world._cards[id]
		if c.pick_kind == "":
			continue
		var screen: Vector2 = cam.unproject_position(c.global_position)
		var hit: Dictionary = world.pick(screen)
		if hit.get("kind", "") == c.pick_kind:
			hits[c.pick_kind] = true
	for kind in ["stock", "discard", "hand", "item", "meld"]:
		check(hits.has(kind), "tapping a %s card finds it" % kind)
	# a real tap through the UI: the stock draws a card
	var stock_card = null
	for id in world._cards:
		if world._cards[id].pick_kind == "stock":
			stock_card = world._cards[id]
	var before: int = g.players[0].hand.size() + g.players[0].items.size()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	# the 3D view is smaller than the screen: scale its pixels back up
	ev.position = cam.unproject_position(stock_card.global_position) * main.view_rect.size / Vector2(main.view3d.size)
	main._on_table_input(ev)
	check(g.players[0].hand.size() + g.players[0].items.size() > before, "tapping the stock draws")
	print("PICK %s" % ("OK" if fails == 0 else "FAILED"))
	quit(0 if fails == 0 else 1)
