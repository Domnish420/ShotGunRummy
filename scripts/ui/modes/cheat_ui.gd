extends "res://scripts/ui/modes/table_mode.gd"
## Cheat at the table: tap 1 to 4 cards and PLAY them as the rank that's due,
## or call CHEAT! on the player before you.


func buttons() -> Array:
	return [["PLAY", _first_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["CHEAT!", _call_pressed, Palette.RED]]


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = "%d CARDS" % me.hand.size()
	var hand: Array = me.hand.duplicate()
	Cards.sort_by_rank(hand)
	var mine := []
	for id in main.selected:
		for c in hand:
			if c["id"] == id:
				mine.append(id)
	main.selected = mine
	var truthful := {}
	if main.hints:
		for c in hand:
			if int(c["rank"]) == g.required or Cards.is_wild(c, g.trump_rank):
				truthful[c["id"]] = true # these are the truth
	main.world.sync({
		"game": g, "viewer": seat, "hand": hand, "selected": main.selected, "selected_item": main.selected_item,
		"meld_hints": truthful, "lay_hints": {}, "lit": main.lit_card, "can_draw": false, "targets": {},
		"hide_hand": main._hand_hidden,
	})
	var pending: bool = g.pending_win >= 0
	var n: int = main.selected.size()
	if pending:
		main.meld_btn.text = "LET IT GO"
		main.meld_btn.disabled = not my_turn
	else:
		main.meld_btn.text = "PLAY %d AS %s" % [n, g.rank_name(g.required)] if n > 0 else "PLAY"
		main.meld_btn.disabled = not (my_turn and n >= g.min_play(seat) and n <= 4)
	main.discard_btn.disabled = not g.can_call(seat)
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
	if g.pending_win >= 0:
		return "%s PLAYED THEIR LAST CARD. CALL CHEAT! OR LET IT GO" % main._name(g.pending_win)
	var lead := ""
	if g.can_call(seat):
		var lp: Dictionary = g.last_play
		lead = "%s SAID %d × %s. " % [main._name(int(lp["seat"])), lp["count"], g.rank_name(int(lp["rank"]))]
	if g.min_play(seat) > 1:
		return lead + "DOUBLE DOWN: PUT DOWN AT LEAST 2 CARDS AS %s" % g.rank_name(g.required)
	return lead + "PUT DOWN 1-4 CARDS AS %s (OR LIE)" % g.rank_name(g.required)


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


func _first_pressed() -> void:
	var g = main.game
	if not main._my_turn():
		return
	if g.pending_win >= 0:
		main._act("let_go", [], main._after_simple)
		return
	var ids: Array = main.selected.duplicate()
	main._act("play", [ids], main._after_simple)


func _call_pressed() -> void:
	if not main.game.can_call(main._me()):
		return
	main._act("call", [], _after_call)


func _after_call(res: Dictionary) -> void:
	if not main._handle(res):
		return
	main._after_action()


func on_event(kind: String, d: Dictionary) -> void:
	var g = main.game
	match kind:
		"play":
			main._log("%s puts down %d × %s." % [main._name(d["seat"]), d["count"], g.rank_name(int(d["rank"]))])
		"called":
			var verdict := "CAUGHT LYING" if d["lie"] else "TOLD THE TRUTH"
			main._log("%s calls CHEAT! on %s: %s (%s). %s picks up %d cards." % [main._name(d["seat"]), main._name(d["liar"]), verdict, Cards.cards_text(d["cards"]), main._name(d["picked_up"]), d["count"]])
			main.world.announce("CHEAT!\n%s %s" % [main._name(d["liar"]), "LIED" if d["lie"] else "WAS HONEST"])
			main._flash(Palette.RED if d["lie"] else Color.WHITE)
			_show_call(d)
		"let_go":
			main._log("%s lets it go." % main._name(d["seat"]))


## Everyone sees the called cards turned over.
func _show_call(d: Dictionary) -> void:
	await main.get_tree().create_timer(0.6).timeout
	if main.game == null or main.overlay_layer.get_child_count() > 0:
		return
	var box: VBoxContainer = main._open_overlay(0.9, false, "reveal")
	box.add_child(main._title("CHEAT!", Palette.RED))
	box.add_child(main._label("%s called %s." % [main._name(d["seat"]), main._name(d["liar"])], 26, Palette.INK, true))
	var holder := CenterContainer.new()
	holder.add_child(card_row(d["cards"], Vector2(96, 138)))
	box.add_child(holder)
	if d["lie"]:
		box.add_child(main._label("A LIE. %s picks up the pile (%d cards)." % [main._name(d["picked_up"]), d["count"]], 28, Palette.PINK, true))
	else:
		box.add_child(main._label("THE TRUTH. %s picks up the pile (%d cards)." % [main._name(d["picked_up"]), d["count"]], 28, Palette.AMBER, true))
	box.add_child(main._button("CONTINUE", main._closing(main._after_action)))


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	box.add_child(main._title("%s GETS RID OF EVERY CARD" % main._name(w), Palette.AMBER))
	if g.options["shotgun"]:
		box.add_child(main._label("%d shell%s in the shotgun. (1, +1 for every 15 cards the others are left holding, max 3)" % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	for h in r["hands"]:
		if h["seat"] == w:
			continue
		var times: int = int(r.get("caught", {}).get(h["seat"], 0))
		box.add_child(main._label("%s: left holding %d%s" % [h["name"], h["points"], ", caught lying %d time%s" % [times, "" if times == 1 else "s"] if times > 0 else ""], 24, Palette.INK))


func rules() -> Array:
	return [
		"THE TABLE. 2 to 6 players. One player deals each round and the player to their left goes first. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. All 52 cards are dealt out. Nobody starts with items: catch a liar and you get one (only 3 turn up each round).",
		"YOUR TURN. Cards go down in order: aces, then twos, then threes, up to kings, then round again. Tap 1 to 4 cards and PLAY them face down as the rank that's due. You can lie.",
		"CHEAT! Before you play, you can call CHEAT! on the player before you. Their cards are turned over. If any of them isn't what they said, they pick up the whole pile and you get an item. If they told the truth, you pick it up.",
		"WINNING. Play your last card and you win, unless the next player calls CHEAT! and catches you.",
		"THE SHOTGUN. The winner gets 1 shell, +1 for every 15 cards the others are left holding (max 3), and picks who to shoot. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	if not main._my_turn():
		return "Watch how many cards each player claims. Three or four of a kind is rare."
	var seat: int = main._me()
	if g.pending_win >= 0:
		return "If they lied with their last card, CHEAT! stops them winning. If not, you pick up the pile."
	if g.can_call(seat):
		var lp: Dictionary = g.last_play
		var mine := 0
		for c in g.players[seat].hand:
			if int(c["rank"]) == int(lp["rank"]) and not Cards.is_wild(c, g.trump_rank):
				mine += 1
		if mine + int(lp["count"]) > 4:
			return "They said %d %s, but you're holding %d. There aren't that many: call CHEAT!" % [lp["count"], g.rank_name(int(lp["rank"])).to_lower(), mine]
	var honest := 0
	for c in g.players[seat].hand:
		if int(c["rank"]) == g.required or Cards.is_wild(c, g.trump_rank):
			honest += 1
	if honest > 0:
		return "Gold cards are the truth. Tap them and PLAY."
	return "You have no %s. Lie: tap one card you won't need soon and PLAY it." % g.rank_name(g.required).to_lower()
