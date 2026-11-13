extends "res://scripts/ui/modes/table_mode.gd"
## Poker at the table: CHECK / CALL, RAISE (load a shell) or FOLD (stay
## safe). Tap an item and the first button uses it.


func buttons() -> Array:
	return [["CHECK", _first_pressed, Palette.AMBER], ["RAISE", _raise_pressed, Palette.RED], ["FOLD", _fold_pressed, Palette.PURPLE]]


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	var r: Array = g.hand_of(seat) if g.board.size() >= 3 else [-1]
	main.deadwood_label.text = "FOLDED" if g.folded.has(seat) else (g.hand_name(r) if int(r[0]) >= 0 else "")
	main.world.sync({
		"game": g, "viewer": seat, "hand": me.hand.duplicate(), "selected": [], "selected_item": main.selected_item,
		"meld_hints": {}, "lay_hints": {}, "lit": "", "can_draw": false, "targets": {},
		"hide_hand": main._hand_hidden,
	})
	var playing: bool = my_turn and g.phase == "play"
	if main.selected_item != "":
		main.meld_btn.text = "USE ITEM"
		main.meld_btn.disabled = not (my_turn and g.item_blocker(seat, main.selected_item) == "")
	else:
		main.meld_btn.text = "CALL" if g.to_call(seat) else "CHECK"
		main.meld_btn.disabled = not playing
	main.use_btn.text = "RAISE"
	main.use_btn.disabled = not (playing and g.can_raise(seat))
	main.discard_btn.disabled = not (playing and not g.must_call.has(seat))
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false
	if main._settings_open() and _book_open() and my_rank() != _book_rank:
		_build_book.call_deferred() # new cards out: show what you've got now


## The hands, best first, with an example of each.
const BOOK := [
	["STRAIGHT FLUSH", "5 in a row, all one suit", "9♥ 10♥ J♥ Q♥ K♥"],
	["FOUR OF A KIND", "4 of the same rank", "7 7 7 7"],
	["FULL HOUSE", "3 of a kind and a pair", "Q Q Q 4 4"],
	["FLUSH", "any 5 of one suit", "2♠ 6♠ 9♠ J♠ K♠"],
	["STRAIGHT", "5 in a row, any suits", "5 6 7 8 9"],
	["THREE OF A KIND", "3 of the same rank", "8 8 8"],
	["TWO PAIR", "2 pairs", "J J 3 3"],
	["A PAIR", "2 of the same rank", "10 10"],
	["HIGH CARD", "none of the above: your top card counts", "A"],
]


## Your best hand right now, as a rank (0 high card .. 8 straight flush), or
## -1 when you've folded. Before the flop it's just your two cards.
func my_rank() -> int:
	var g = main.game
	var seat: int = main._me()
	if g.folded.has(seat):
		return -1
	var cards: Array = g.players[seat].hand + g.board
	if cards.size() >= 5:
		return int(g.best_hand(cards)[0])
	var counts := {}
	for c in cards:
		counts[c["rank"]] = int(counts.get(c["rank"], 0)) + 1
	var most := 0
	for k in counts:
		most = maxi(most, counts[k])
	return 3 if most >= 3 else (1 if most == 2 else 0)


## The little hand book: floats over the table and doesn't stop the game.
## Tap HAND BOOK again (or CLOSE) to put it away.
func book() -> void:
	if main._settings_open():
		main._hide_settings()
		return
	main._sound("open")
	_build_book()


var _book_rank := -2 # what the book showed you holding


func _build_book() -> void:
	main._clear(main.settings_layer)
	var vs: Vector2 = main.get_viewport_rect().size
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.02, 0.02, 0.7)
	st.set_corner_radius_all(24)
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main.settings_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var title: Label = main._label("HAND BOOK", 40, main.FLOAT_YELLOW, true)
	title.add_theme_constant_override("outline_size", 12)
	col.add_child(title)
	col.add_child(main._label("Best at the top. Make your best 5 from your 2 cards and the 5 on the table.", 18, Palette.DIM, true))
	var mine := my_rank()
	_book_rank = mine
	for i in range(BOOK.size()):
		var rank := 8 - i
		var entry: Array = BOOK[i]
		var you := rank == mine
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_l: Label = main._tag(("▶ " if you else "") + entry[0], 26, Palette.GOLD if you else Palette.INK)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(main._tag(entry[2], 24, Palette.GOLD if you else Color(0.75, 0.75, 0.72)))
		col.add_child(row)
		col.add_child(main._label(entry[1] + ("  ◀ YOU HAVE THIS" if you else ""), 17, Palette.GOLD if you else Palette.DIM))
	if mine < 0:
		col.add_child(main._label("You folded this round.", 20, Palette.PINK, true))
	var close: Button = main._bubble("CLOSE", main._hide_settings, Palette.RED, 34)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	var w := minf(vs.x - 24.0, 620.0)
	panel.custom_minimum_size = Vector2(w, 0)
	var sz: Vector2 = panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2((vs.x - sz.x) * 0.5, maxf(60.0, (vs.y - sz.y) * 0.32))


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "ROUND OVER"
	if main.world.dealing:
		return "SHUFFLING AND DEALING..."
	var seat: int = main._me()
	if g.folded.has(seat):
		return "YOU FOLDED: YOU'RE SAFE THIS ROUND. " + waiting_text()
	if not main._my_turn():
		return waiting_text()
	var it := item_text()
	if it != "":
		return it
	var loaded := "%d SHELL%s LOADED" % [g.shells, "" if g.shells == 1 else "S"]
	if g.to_call(seat):
		return "%s RAISED: %s. CALL OR FOLD" % [main._name(g.raised_by), loaded]
	return "%s. CHECK, OR RAISE TO LOAD ANOTHER" % loaded


func on_pick(hit: Dictionary) -> void:
	if hit.get("kind", "") == "item":
		main._toggle_item(hit["id"])


func _first_pressed() -> void:
	if main.selected_item != "":
		main._use_selected_item()
		return
	if main._my_turn():
		main._act("call", [], main._after_simple)


func _raise_pressed() -> void:
	if main._my_turn():
		main._act("raise", [], main._after_simple)


func _fold_pressed() -> void:
	if main._my_turn():
		main._act("fold", [], main._after_simple)


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"bet":
			match d["action"]:
				"check":
					main._log("%s checks." % main._name(d["seat"]))
				"call":
					main._log("%s calls." % main._name(d["seat"]))
				"raise":
					main._log("%s raises: %d shells loaded." % [main._name(d["seat"]), d["shells"]])
					main.world.announce("RAISE\n%d SHELLS" % d["shells"])
				"fold":
					main._log("%s folds." % main._name(d["seat"]))
		"board":
			main._log("The %s: %s." % [d["street"], Cards.cards_text(d["cards"])])


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	if w < 0:
		box.add_child(main._title("SPLIT POT"))
		box.add_child(main._label(str(r.get("reason", "")), 26, Palette.INK, true))
	else:
		box.add_child(main._title("%s WINS%s" % [main._name(w), " WITH " + str(r["hand"]) if str(r["hand"]) != "" else ""], Palette.AMBER))
		if r.get("reason", "") != "":
			box.add_child(main._label(str(r["reason"]), 24, Palette.INK, true))
		elif g.options["shotgun"]:
			box.add_child(main._label("%d shell%s loaded. Only players who stayed in can be shot." % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	if not r["board"].is_empty():
		box.add_child(main._label("THE MIDDLE", 22, Palette.DIM, true))
		var holder := CenterContainer.new()
		holder.add_child(card_row(r["board"]))
		box.add_child(holder)
	for h in r["hands"]:
		var note := "FOLDED (safe)" if h["folded"] else str(h["hand"])
		box.add_child(main._label("%s: %s" % [h["name"], note], 24, Palette.GOLD if h["seat"] == w else (Palette.DIM if h["folded"] else Palette.INK)))
		if not h["folded"]:
			box.add_child(card_row(h["cards"]))


func rules() -> Array:
	return [
		"POKER: TEXAS HOLD'EM, BETTING SHELLS. 2 to 6 players.",
		"THE TABLE. One player deals (the dealer chip) and the player to their left bets first. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. Everyone gets 2 cards face down. Nobody starts with items: each new street someone still in might find one (items are rare, and how many turn up each round is down to luck). Five cards are dealt face up in the middle: three (the flop), one (the turn), then one (the river). There's a round of betting before each and after the last.",
		"BETTING. CHECK, or RAISE to load another shell into the shotgun (2 at most). Once someone raises, everyone else still in must CALL it or FOLD.",
		"FOLDING. Fold and you can't win the round, but you're safe: the winner can't shoot you.",
		"WINNING. Best five-card hand from your two cards and the five in the middle. From best: straight flush, four of a kind, full house, flush, straight, three of a kind, two pair, a pair, high card. If everyone else folds, the last one in wins.",
		"THE SHOTGUN. The winner fires every shell that was loaded (1, plus 1 for a raise, 2 at most; a straight flush loads 2 whatever was bet), but only at players who stayed in. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	var seat: int = main._me()
	if not main._my_turn():
		return "A raise means they like their hand, or want you to think so."
	if g.board.is_empty():
		var hand: Array = g.players[seat].hand
		if hand.size() == 2 and int(hand[0]["rank"]) == int(hand[1]["rank"]):
			return "A pair in your hand is strong before the flop. RAISE to load a shell."
		return "Two high cards or two of a suit are worth seeing the flop. Junk? FOLD if someone raises: you'll be safe."
	var r: Array = g.hand_of(seat)
	if int(r[0]) >= 2:
		return "You've got %s. That's strong: RAISE." % g.hand_name(r).to_lower()
	if int(r[0]) == 1:
		return "A pair is fair. CHECK or CALL, but think about folding to a big raise."
	return "Nothing yet. CHECK if you can; FOLD to a raise and you're safe from the shotgun."


func _book_open() -> bool:
	var p: Node = main.settings_layer.get_child(0)
	if p.is_queued_for_deletion():
		return false
	var labels := p.find_children("*", "Label", true, false)
	return not labels.is_empty() and (labels[0] as Label).text == "HAND BOOK"
