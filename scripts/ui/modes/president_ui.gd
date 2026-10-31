extends "res://scripts/ui/modes/table_mode.gd"
## President at the table: tap a set (same rank, trumps fill in) and PLAY it
## over the pile, or PASS.

const RANK_WORDS := {3: "3s", 4: "4s", 5: "5s", 6: "6s", 7: "7s", 8: "8s", 9: "9s", 10: "10s", 11: "JACKS", 12: "QUEENS", 13: "KINGS", 14: "ACES", 15: "2s", 16: "TRUMPS"}


func buttons() -> Array:
	return [["PLAY", _play_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["PASS", _pass_pressed, Palette.RED]]


func _describe(top: Dictionary) -> String:
	var n: int = top["count"]
	var what: String = RANK_WORDS.get(int(top["value"]), "?")
	return ["", "A SINGLE %s" % what.trim_suffix("S").trim_suffix("s"), "A PAIR OF %s" % what, "THREE %s" % what, "FOUR %s" % what][n]


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
	var note: String = g.table_note(seat)
	main.deadwood_label.text = "%d CARDS%s" % [me.hand.size(), " · " + note if note != "" else ""]
	var hand: Array = me.hand.duplicate()
	hand.sort_custom(func(a, b): return g._sort_value(a) < g._sort_value(b))
	var mine := []
	for id in main.selected:
		for c in hand:
			if c["id"] == id:
				mine.append(id)
	main.selected = mine
	var sel: Array = []
	for c in hand:
		if main.selected.has(c["id"]):
			sel.append(c)
	main.world.sync({
		"game": g, "viewer": seat, "hand": hand, "selected": main.selected, "selected_item": main.selected_item,
		"meld_hints": {}, "lay_hints": {}, "lit": main.lit_card, "can_draw": false, "targets": {},
		"hide_hand": main._hand_hidden,
	})
	var v: int = g.play_value(sel)
	var ok: bool = v > 0 and (g.pile_top.is_empty() or (sel.size() == int(g.pile_top["count"]) and v > int(g.pile_top["value"])))
	main.meld_btn.disabled = not (my_turn and ok)
	main.discard_btn.disabled = not g.can_pass(seat)
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
	if g.pile_top.is_empty():
		return "YOUR LEAD: PLAY A SINGLE, PAIR, THREE OR FOUR OF A KIND"
	return "BEAT %s (%s), OR PASS" % [_describe(g.pile_top), main._name(int(g.pile_top["seat"]))]


func on_pick(hit: Dictionary) -> void:
	match hit.get("kind", ""):
		"item":
			main._toggle_item(hit["id"])
		"hand":
			if main.selected.size() >= 4 and not main.selected.has(hit["id"]):
				main.message = "Four cards at most."
				main._refresh()
				return
			main._toggle_card(hit["id"])


func _play_pressed() -> void:
	if not main._my_turn():
		return
	main._act("play", [main.selected.duplicate()], main._after_simple)


func _pass_pressed() -> void:
	if not main.game.can_pass(main._me()):
		return
	main._act("pass", [], main._after_simple)


func on_event(kind: String, d: Dictionary) -> void:
	var g = main.game
	match kind:
		"president_play":
			main._log("%s plays %s." % [main._name(d["seat"]), Cards.cards_text(d["cards"])])
		"pass":
			main._log("%s passes." % main._name(d["seat"]))
		"pile_cleared":
			main._log("Everyone passed. %s leads." % main._name(d["seat"]))
		"exchange":
			main._log("%s (Scum) hands their best card to %s (President) and gets their worst back." % [main._name(d["scum"]), main._name(d["president"])])
			main.world.announce("THE SCUM PAYS UP")


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	box.add_child(main._label("PRESIDENT", 64, Palette.GOLD, true))
	box.add_child(main._title("%s IS OUT FIRST" % main._name(w), Palette.AMBER))
	if g.options["shotgun"]:
		box.add_child(main._label("%d shell%s in the shotgun. (1 for every 2 other players, max 3)" % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	for h in r["hands"]:
		if h["seat"] == w:
			continue
		var tag := " (SCUM: pays the President next round)" if h["seat"] == int(r.get("scum", -1)) else ""
		box.add_child(main._label("%s: left holding %d%s" % [h["name"], h["points"], tag], 24, Palette.PINK if tag != "" else Palette.INK))


func rules() -> Array:
	return [
		"THE TABLE. 2 to 6 players. One player deals each round and the player to their left leads. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. All the cards are dealt out, plus 2 item cards each.",
		"RANKS. 3 is lowest, then up to K, then A, and 2 is the highest.",
		"PLAYING. The leader plays a single, a pair, three or four of a kind. Going round, each player must beat it with the same number of cards of a higher rank, or PASS. Once you pass you sit out until the pile clears. When everyone else has passed, the pile clears and the last player to play leads again.",
		"TRUMP CARDS. Each round one rank is trump: aces in round 1, twos in round 2, up to kings. Trumps are wild: they fill in any set (a 9 and a trump is a pair of 9s). Trumps on their own beat everything.",
		"PRESIDENT AND SCUM. First to play their last card is PRESIDENT and wins. Whoever is left holding the most cards is the SCUM: next round they hand the President their best card and get the President's worst back.",
		"THE SHOTGUN. The President gets 1 shell for every 2 other players (at least 1, at most 3) and picks who to shoot. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	if not main._my_turn():
		return "Watch which big cards (aces, 2s, trumps) have been played already."
	if g.pile_top.is_empty():
		return "You're leading: get rid of your lowest cards. Pairs and threes of the same rank go together."
	return "Beat %s with the same number of higher cards, or PASS to save your good cards." % _describe(g.pile_top).to_lower()
