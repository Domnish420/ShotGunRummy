extends "res://scripts/ui/modes/table_mode.gd"
## Go Fish at the table: tap a card to pick its rank, then ASK a player.

const RANK_NAMES := ["", "ACES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "SEVENS", "EIGHTS", "NINES", "TENS", "JACKS", "QUEENS", "KINGS"]

var rank := 0 # the rank you've picked to ask for


func buttons() -> Array:
	return [["ASK", _ask_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["", Callable(), null]]


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.trump_label.text = "TRUMP: %s  " % main.trump_name(g.trump_rank) if g.trump_rank > 0 else ""
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = "BOOKS %d" % g.books_of(seat).size()
	if not g.askable_ranks(seat).has(rank):
		rank = 0
	var hand: Array = me.hand.duplicate()
	Cards.sort_by_rank(hand)
	var picked := []
	var close := {}
	var counts := {}
	for c in hand:
		if not Cards.is_wild(c, g.trump_rank):
			counts[int(c["rank"])] = counts.get(int(c["rank"]), 0) + 1
	for c in hand:
		if rank > 0 and int(c["rank"]) == rank and not Cards.is_wild(c, g.trump_rank):
			picked.append(c["id"])
		elif main.hints and counts.get(int(c["rank"]), 0) >= 3:
			close[c["id"]] = true # one away from a book
	main.world.sync({
		"game": g, "viewer": seat, "hand": hand, "selected": picked, "selected_item": main.selected_item,
		"meld_hints": close, "lay_hints": {}, "lit": main.lit_card, "can_draw": false, "targets": {},
		"hide_hand": main._hand_hidden,
	})
	main.meld_btn.disabled = not (my_turn and rank > 0)
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
	if g.players[main._me()].ultimatum:
		return "REVOLVER: GET A CARD OFF SOMEONE THIS TURN, OR SPIN THE CYLINDER"
	if rank > 0:
		return "ASK SOMEONE FOR %s: PRESS ASK" % RANK_NAMES[rank]
	return "TAP A CARD TO PICK ITS RANK, THEN ASK SOMEONE FOR IT"


func on_pick(hit: Dictionary) -> void:
	var g = main.game
	match hit.get("kind", ""):
		"item":
			main._toggle_item(hit["id"])
		"hand":
			if not main._my_turn():
				main.message = "It's %s's turn." % main._name(g.turn)
			else:
				for c in g.players[main._me()].hand:
					if c["id"] == hit["id"]:
						if Cards.is_wild(c, g.trump_rank):
							main.message = "Trumps are wild: they fill in books. Nobody can ask for them."
						else:
							var r := int(c["rank"])
							rank = 0 if rank == r else r
							main.message = ""
			main._refresh()


func _ask_pressed() -> void:
	var g = main.game
	if not main._my_turn() or rank <= 0:
		return
	var box: VBoxContainer = main._open_overlay(0.94, false, "target")
	box.add_child(main._title("ASK FOR %s" % RANK_NAMES[rank], Palette.AMBER))
	box.add_child(main._label("Who do you think has them?", 26, Palette.INK, true))
	for t in g.ask_targets(main._me()):
		var p = g.players[t]
		var note := "%d CARDS · %d BOOKS" % [p.hand.size(), g.books_of(t).size()]
		if g.known.get(t, {}).has(rank):
			note += " · ASKED FOR THEM"
		box.add_child(main._button("%s  (%s)" % [p.name, note], main._closing(_ask.bind(t)), 26))
	box.add_child(main._button("CANCEL", main._closing(main._after_action)))


func _ask(target: int) -> void:
	var asked := rank
	main._act("ask", [target, asked], _after_ask.bind(target, asked))


func _after_ask(res: Dictionary, target: int, asked: int) -> void:
	if not main._handle(res):
		return
	if res.get("count", 0) > 0:
		main.message = ""
		main._after_action()
		return
	var card: Dictionary = res.get("card", {})
	if card.is_empty():
		main._after_action()
		return
	main.lit_card = card["id"]
	var text := "%s had no %s." % [main._name(target), RANK_NAMES[asked].to_lower()]
	if res.get("lucky", false):
		text += " But you fished one! Go again."
	main._show_reveal("GO FISH", card, text, main._after_action)


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"ask":
			var what: String = RANK_NAMES[int(d["rank"])].to_lower()
			if int(d["count"]) > 0:
				main._log("%s asks %s for %s and gets %d." % [main._name(d["seat"]), main._name(d["target"]), what, d["count"]])
			else:
				main._log("%s asks %s for %s. GO FISH." % [main._name(d["seat"]), main._name(d["target"]), what])
				if d["seat"] != main._me():
					main.world.announce("GO FISH")
		"go_fish":
			if d.get("forced", false):
				main._log("%s can't ask anyone, so they fish." % main._name(d["seat"]))
			elif d.get("lucky", false):
				main._log("%s fishes the card they asked for and goes again." % main._name(d["seat"]))
			elif d.get("empty", false):
				main._log("The pond is empty.")
		"book":
			main._log("%s lays down a book of %s." % [main._name(d["seat"]), RANK_NAMES[int(d["rank"])].to_lower()])
			main.world.announce("BOOK!\n%s" % RANK_NAMES[int(d["rank"])])


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	if w < 0:
		box.add_child(main._title("NOBODY WINS"))
		box.add_child(main._label(str(r.get("reason", "")), 26, Palette.INK, true))
	else:
		box.add_child(main._title("%s WINS WITH %d BOOKS" % [main._name(w), r["points"]], Palette.AMBER))
		if g.options["shotgun"]:
			box.add_child(main._label("%d shell%s in the shotgun. (1 for every book ahead of the next player, max 3)" % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	for h in r["hands"]:
		var books: Array = g.books_of(h["seat"])
		var names := []
		for b in books:
			names.append(Cards.rank_label(int(b["rank"])))
		box.add_child(main._label("%s: %d book%s%s" % [h["name"], books.size(), "" if books.size() == 1 else "s", " (%s)" % " ".join(names) if not names.is_empty() else ""], 24, Palette.GOLD if h["seat"] == w else Palette.INK))


func rules() -> Array:
	return [
		"THE TABLE. 2 to 6 players. One player deals each round and the player to their left goes first. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. Everyone gets 7 cards (5 with 4 or more players) and 2 item cards. The rest of the cards and the items are the POND.",
		"YOUR TURN. Tap a card to pick its rank, then ASK a player for that rank. If they have any, they hand them all over and you go again. If not, GO FISH: you draw from the pond. If you draw the rank you asked for, you go again. Otherwise your turn ends. Draw an item and you keep it and draw again.",
		"BOOKS. Four of a kind is a BOOK, and goes down in front of you by itself.",
		"THE END. The round ends when someone has to fish and the pond is empty, or nobody has any cards. Most books wins (a tie goes to whoever holds fewer cards).",
		"THE SHOTGUN. The winner gets 1 shell for every book they're ahead of the next player (at least 1, at most 3) and picks who to shoot. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play" or not main._my_turn():
		return "Watch the others. When someone asks for a rank, they must be holding it: remember that."
	var seat: int = main._me()
	for t in g.ask_targets(seat):
		for r in g.askable_ranks(seat):
			if g.known.get(t, {}).has(r):
				return "%s asked for %s earlier, so they have some. Tap one of yours and ASK them." % [main._name(t), RANK_NAMES[r].to_lower()]
	if rank == 0:
		return "Tap a card in your hand. You'll ask someone for that rank. Gold-outlined cards are one away from a book."
	return "Now press ASK and pick who to ask. If they don't have any, you go fish."
