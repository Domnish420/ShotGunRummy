extends "res://scripts/ui/modes/table_mode.gd"
## Hearts and Spades at the table: tap a card, then PLAY it to the trick.
## Spades starts each round with a BID.

const SUIT_WORDS := {"S": "SPADES", "H": "HEARTS", "D": "DIAMONDS", "C": "CLUBS"}


func buttons() -> Array:
	return [["PLAY", _first_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["", Callable(), null]]


func _bidding() -> bool:
	var g = main.game
	return g.kind == "spades" and g.bidding


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = g.table_note(seat)
	var hand: Array = me.hand.duplicate()
	Cards.sort_by_suit(hand)
	var legal := {}
	if my_turn and not _bidding():
		for c in g.legal_cards(seat):
			legal[c["id"]] = true
	var keep := []
	for id in main.selected:
		if legal.has(id):
			keep.append(id)
	main.selected = keep
	main.world.sync({
		"game": g, "viewer": seat, "hand": hand, "selected": main.selected, "selected_item": main.selected_item,
		"meld_hints": legal if main.hints else {}, "lay_hints": {}, "lit": main.lit_card, "can_draw": false, "targets": {},
		"hide_hand": main._hand_hidden,
	})
	if _bidding():
		main.meld_btn.text = "BID"
		main.meld_btn.disabled = not my_turn
	else:
		main.meld_btn.text = "PLAY"
		main.meld_btn.disabled = not (my_turn and main.selected.size() == 1)
	main.use_btn.disabled = not (my_turn and main.selected_item != "" and g.item_blocker(seat, main.selected_item) == "")
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "ROUND OVER"
	if main.world.dealing:
		return "SHUFFLING AND DEALING..."
	if not main._my_turn():
		return waiting_text()
	var it := item_text()
	if it != "":
		return it
	var seat: int = main._me()
	if _bidding():
		return "BID: HOW MANY TRICKS WILL YOU TAKE? PRESS BID"
	if g.players[seat].extra_draws > 0:
		return "DOUBLE DOWN: PLAY YOUR HIGHEST CARD"
	if g.trick.is_empty():
		return "YOUR LEAD: TAP A GOLD CARD, THEN PLAY"
	return "FOLLOW %s IF YOU CAN: TAP A GOLD CARD, THEN PLAY" % SUIT_WORDS.get(g.led_suit(), "")


func on_pick(hit: Dictionary) -> void:
	var g = main.game
	match hit.get("kind", ""):
		"item":
			main._toggle_item(hit["id"])
		"hand":
			if not main._my_turn() or _bidding():
				main.message = "It's %s's turn." % main._name(g.turn) if not main._my_turn() else "Bid first."
			else:
				var legal: Array = Cards.ids_of(g.legal_cards(main._me()))
				if not legal.has(hit["id"]):
					main.message = "You can't play that card now: the gold ones are the ones you can play."
				else:
					main.selected = [] if main.selected == [hit["id"]] else [hit["id"]]
					main.message = ""
			main._refresh()


func _first_pressed() -> void:
	var g = main.game
	if not main._my_turn():
		return
	if _bidding():
		_show_bids()
		return
	if main.selected.size() != 1:
		return
	main._act("play", [main.selected[0]], main._after_simple)


func _show_bids() -> void:
	var g = main.game
	var box: VBoxContainer = main._open_overlay(0.94, false, "target")
	box.add_child(main._title("YOUR BID", Palette.AMBER))
	box.add_child(main._label("How many tricks will you take? 0 is nil: +50 if you take none.", 24, Palette.INK, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for n in range(g.players[main._me()].hand.size() + 1):
		var b: Button = main._button(str(n) if n > 0 else "NIL", main._closing(_bid.bind(n)), 28)
		b.custom_minimum_size = Vector2(90, 64)
		flow.add_child(b)
	box.add_child(flow)
	box.add_child(main._button("CANCEL", main._closing(main._after_action)))


func _bid(n: int) -> void:
	main._act("bid", [n], main._after_simple)


func on_event(kind: String, d: Dictionary) -> void:
	var g = main.game
	match kind:
		"bid":
			main._log("%s bids %s." % [main._name(d["seat"]), str(d["bid"]) if int(d["bid"]) > 0 else "nil"])
		"trick_won":
			var note := ""
			if g.kind == "hearts":
				var pts := 0
				for c in d["cards"]:
					pts += g.points_of(c)
				note = " (%d point%s)" % [pts, "" if pts == 1 else "s"] if pts > 0 else ""
			main._log("%s takes the trick: %s%s." % [main._name(d["seat"]), Cards.cards_text(d["cards"]), note])
		"hearts_broken":
			main._log("Hearts are broken.")
		"spades_broken":
			main._log("Spades are broken.")
		"queen_taken":
			main._log("%s takes the Queen of Spades." % main._name(d["seat"]))
			main.world.announce("QUEEN OF SPADES\n%s" % main._name(d["seat"]))
			if g.options["shotgun"]:
				main._flash(Palette.RED)


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	if w < 0:
		box.add_child(main._title("NOBODY WINS"))
		box.add_child(main._label(str(r.get("reason", "")), 26, Palette.INK, true))
	elif g.kind == "hearts" and r.get("moon", false):
		box.add_child(main._label("SHOT THE MOON!", 64, Palette.GOLD, true))
		box.add_child(main._title("%s TOOK EVERY POINT" % main._name(w), Palette.AMBER))
	elif g.kind == "hearts":
		box.add_child(main._title("%s WINS WITH %d POINT%s" % [main._name(w), r["points"], "" if r["points"] == 1 else "S"], Palette.AMBER))
	else:
		box.add_child(main._title("%s WINS WITH %d" % [main._name(w), r["points"]], Palette.AMBER))
	if w >= 0 and g.options["shotgun"]:
		box.add_child(main._label("%d shell%s in the shotgun." % [r["shells"], "" if r["shells"] == 1 else "s"], 26, Palette.INK, true))
	for h in r["hands"]:
		var line := ""
		if g.kind == "hearts":
			line = "%s: %d point%s" % [h["name"], h["points"], "" if h["points"] == 1 else "s"]
		else:
			var bid_text := str(h["bid"]) if int(h["bid"]) > 0 else "NIL"
			line = "%s: bid %s, took %d: %+d" % [h["name"], bid_text, h["tricks"], h["points"]]
		box.add_child(main._label(line, 24, Palette.GOLD if h["seat"] == w else Palette.INK))


func rules() -> Array:
	var g = main.game
	var common := [
		"THE TABLE. One player deals each round and the player to their left leads the first trick. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. The cards are dealt out evenly (any left over are set aside), plus 2 item cards each.",
		"TRICKS. Everyone plays one card. Follow the suit that was led if you can (the cards you can play glow gold). The highest card of the led suit wins the trick (aces high), and the winner leads the next one.",
	]
	if g.kind == "hearts":
		return ["HEARTS: DON'T TAKE HEARTS. 3 to 6 players."] + common + [
			"POINTS. Each heart you take is 1 point. The Queen of Spades is 13. Hearts can't be led until one has been played.",
			"THE QUEEN. Take the Queen of Spades and you lose 1 health on the spot.",
			"WINNING. Fewest points wins the round. Take every point card and you SHOOT THE MOON: you win with 3 shells.",
			"THE SHOTGUN. The winner gets 1 shell, +1 if they took no points at all. Everyone has 4 health. Last one standing walks out.",
		]
	return ["SPADES: EVERYONE FOR THEMSELVES. 2 to 6 players."] + common + [
		"BIDDING. Before the first trick everyone bids how many tricks they'll take. 0 is NIL.",
		"SPADES ARE TRUMPS. A spade beats any other suit. Spades can't be led until one has been played.",
		"SCORING. Make your bid: 10 per trick bid, +1 for each extra. Miss it: -10 per trick bid. Nil: +50 if you take none, -50 if you take any.",
		"THE SHOTGUN. Best score this round wins, with 1 shell, +1 for making your bid exactly, +1 for making nil. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	var seat: int = main._me()
	if not main._my_turn():
		return "Watch which suits people run out of: they can throw anything on those." if g.kind == "hearts" else "Count how many tricks each player has won against their bid."
	if _bidding():
		return "Count your aces, kings and high spades: that's roughly how many tricks you'll take. Press BID."
	if g.kind == "hearts":
		if g.trick.is_empty():
			return "Lead a low card. Low cards rarely win the trick, so they rarely take hearts."
		if not g.legal_cards(seat).any(func(c): return str(c["suit"]) == g.led_suit()):
			return "You can't follow suit: throw away the Queen of Spades or a high heart onto someone else's trick!"
		return "Play a card lower than the best one in the trick, so you don't win it."
	if int(g.bids.get(seat, 0)) == 0:
		return "You bid nil: don't win a single trick. Play low."
	var need: bool = int(g.tricks_won.get(seat, 0)) < int(g.bids.get(seat, 0))
	return "You still need tricks: play a card that can win this one." if need else "You've made your bid. Extra tricks still score +1 each."
