extends "res://scripts/ui/modes/table_mode.gd"
## Crazy Eights at the table: tap a card, then tap the pile (or PLAY). Tap
## the stock to draw. An eight pops up four floating suits to call; with two
## cards left a LAST SHOT! bubble floats up to tap before you play.

const SUIT_WORDS := {"S": "♠ SPADES", "H": "♥ HEARTS", "D": "♦ DIAMONDS", "C": "♣ CLUBS"}
const SUIT_COLORS := {"S": Color(0.75, 0.8, 1.0), "H": Color(1.0, 0.35, 0.4), "D": Color(1.0, 0.55, 0.3), "C": Color(0.55, 1.0, 0.6)}

var _suit_bar: Control # the four suits, while you call one for an eight
var _shot_bubble: Control # LAST SHOT!
var _eight := "" # the eight waiting on its suit


func buttons() -> Array:
	return [["PLAY", _play_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["DRAW", _draw_pressed, Palette.RED]]


static func card_words(c: Dictionary) -> String:
	var r := int(c["rank"])
	if r == 8:
		return "WHISKEY"
	if r == 1 and c["suit"] == "S":
		return "LAST ORDERS"
	return {2: "+2", 11: "CUFFED", 12: "KICK BACK"}.get(r, "")


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = "%d CARD%s%s" % [me.hand.size(), "" if me.hand.size() == 1 else "S", " · LAST SHOT" if me.hand.size() == 1 else ""]
	var hand: Array = me.hand.duplicate()
	Cards.sort_by_suit(hand)
	var mine := []
	for id in main.selected:
		for c in hand:
			if c["id"] == id:
				mine.append(id)
	main.selected = mine.slice(0, 1)
	var fits := {}
	if my_turn and main.hints:
		for c in g.playable(seat):
			fits[c["id"]] = true
	main.world.sync({
		"game": g, "viewer": seat, "hand": hand, "selected": main.selected, "selected_item": main.selected_item,
		"meld_hints": fits, "lay_hints": {}, "lit": main.lit_card, "can_draw": my_turn and g.can_draw(seat),
		"targets": {}, "hide_hand": main._hand_hidden,
	})
	var sel := _selected_card()
	main.meld_btn.disabled = not (my_turn and not sel.is_empty() and g.can_play_card(seat, sel))
	main.discard_btn.disabled = not (my_turn and (g.can_draw(seat) or g.can_pass(seat)))
	main.discard_btn.text = "PASS" if g.can_pass(seat) else ("DRAW %d" % g.pending_draw if g.pending_draw > 0 else "DRAW")
	main.use_btn.disabled = not (my_turn and main.selected_item != "" and g.item_blocker(seat, main.selected_item) == "")
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false
	_show_shot_bubble(my_turn and g.can_call(seat) and not main.world.dealing and main.overlay_layer.get_child_count() == 0)
	if not my_turn or g.phase != "play":
		_hide_suits()


func _selected_card() -> Dictionary:
	if main.selected.is_empty():
		return {}
	for c in main.game.players[main._me()].hand:
		if c["id"] == main.selected[0]:
			return c
	return {}


func _match_text() -> String:
	var g = main.game
	var top: Dictionary = g.top_discard()
	if top.is_empty():
		return "ANYTHING"
	if g.called_suit != "":
		return SUIT_WORDS[g.called_suit] + " (CALLED)"
	return "%s OR A %s" % [SUIT_WORDS[top["suit"]], Cards.rank_label(int(top["rank"]))]


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
	if g.pending_draw > 0:
		return "+%d COMING: STACK A 2 ON IT, OR DRAW %d" % [g.pending_draw, g.pending_draw]
	if g.players[main._me()].ultimatum:
		return "REVOLVER: PLAY A CARD THIS TURN, OR DRAW AND SPIN THE CYLINDER"
	if g.drew:
		return "PLAY ON %s, OR PASS" % _match_text()
	return "MATCH %s, OR TAP THE STOCK" % _match_text()


func on_pick(hit: Dictionary) -> void:
	var g = main.game
	match hit.get("kind", ""):
		"item":
			main._toggle_item(hit["id"])
		"hand":
			main._sound("tap")
			if not main._my_turn():
				main.message = "It's %s's turn." % main._name(g.turn)
			elif main.selected.has(hit["id"]):
				_play_pressed() # tap it twice to play it
				return
			else:
				main.selected = [hit["id"]]
				main.message = ""
			main._refresh()
		"stock":
			_draw_pressed()
		"discard":
			if not main.selected.is_empty():
				_play_pressed()


func _play_pressed() -> void:
	if not main._my_turn() or main.selected.is_empty():
		return
	var card := _selected_card()
	if card.is_empty():
		return
	if not main.game.can_play_card(main._me(), card):
		main.message = "That doesn't match: play the same suit or rank, an eight, or draw."
		main._refresh()
		return
	if int(card["rank"]) == 8:
		_eight = card["id"]
		_show_suits()
		return
	_play(card["id"], "")


func _play(id: String, suit: String) -> void:
	_hide_suits()
	main._act("play", [id, suit], main._after_simple)


func _draw_pressed() -> void:
	var g = main.game
	var seat: int = main._me()
	if not main._my_turn():
		return
	if g.can_pass(seat):
		main._act("pass", [], main._after_simple)
	elif g.can_draw(seat):
		main._act("draw", [], main._after_simple)


func _call_pressed() -> void:
	main._act("last_shot", [], main._after_simple)


# ---------------------------------------------------------------- floating words

func _float_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(box)
	main.move_child(box, main.settings_layer.get_index()) # under the settings, over the table
	var vs: Vector2 = main.get_viewport_rect().size
	box.position = Vector2(16, vs.y * 0.2)
	box.size = Vector2(vs.x - 32, 0)
	box.custom_minimum_size = Vector2(vs.x - 32, 0)
	return box


func _show_suits() -> void:
	_hide_suits()
	_suit_bar = _float_box()
	var head: Label = main._label("WHISKEY! CALL A SUIT", 38, main.FLOAT_YELLOW, true)
	head.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01))
	head.add_theme_constant_override("outline_size", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_suit_bar.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in Cards.SUITS:
		grid.add_child(main._bubble(SUIT_WORDS[s], _play.bind(_eight, s), SUIT_COLORS[s], 44))
	_suit_bar.add_child(grid)
	var cancel: Control = main._bubble("CANCEL", _hide_suits, Palette.RED, 34)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_suit_bar.add_child(cancel)
	main.world.set_tags_shown(false)
	main._sound("open")


func _hide_suits() -> void:
	if _suit_bar != null and is_instance_valid(_suit_bar):
		_suit_bar.queue_free()
		if main.world != null:
			main.world.set_tags_shown(true)
	_suit_bar = null


func _show_shot_bubble(on: bool) -> void:
	if on == (_shot_bubble != null and is_instance_valid(_shot_bubble)):
		return
	if not on:
		_shot_bubble.queue_free()
		_shot_bubble = null
		return
	_shot_bubble = _float_box()
	_shot_bubble.position.y = main.get_viewport_rect().size.y * 0.52
	var b: Control = main._bubble("LAST SHOT!", _call_pressed, main.FLOAT_YELLOW, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_shot_bubble.add_child(b)


## Leaving the table: take the floating words with us.
func clear() -> void:
	_hide_suits()
	if _shot_bubble != null and is_instance_valid(_shot_bubble):
		_shot_bubble.queue_free()
	_shot_bubble = null


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"crazy8_play":
			var c: Dictionary = d["card"]
			main._log("%s plays %s." % [main._name(d["seat"]), Cards.card_name(c)])
			var words := card_words(c)
			if int(c["rank"]) == 8:
				main.world.announce("WHISKEY! %s" % SUIT_WORDS[d["suit"]])
			elif int(d.get("stack", 0)) > 0:
				var n := int(d["stack"])
				main.world.announce(("+%d!" % n) if n <= 2 or (n == 4 and int(c["rank"]) == 1) else "STACKED: +%d!" % n)
			elif words != "":
				main.world.announce(words + "!")
		"took_stack":
			main._log("%s takes the lot: %d cards." % [main._name(d["seat"]), d["count"]])
		"pass":
			main._log("%s passes." % main._name(d["seat"]))
		"reverse":
			main._log("Kick back! Play turns round.")
		"last_shot_called":
			main._log("%s: LAST SHOT!" % main._name(d["seat"]))
			main.world.announce("%s: LAST SHOT!" % main._name(d["seat"]))
			main._sound("rack")
		"last_shot_caught":
			main._log("%s forgot to call LAST SHOT! Caught: draw 2." % main._name(d["seat"]))
			main.world.announce("CAUGHT! DRAW 2")
		"stock_reshuffled":
			main._log("The pile goes back under: the stock is shuffled.")


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	box.add_child(main._label("LAST SHOT", 64, Palette.GOLD, true))
	box.add_child(main._title("%s IS OUT FIRST" % main._name(w), Palette.AMBER))
	if g.options["shotgun"]:
		box.add_child(main._label("%d shell%s in the shotgun. (1, or 2 for going out on a saloon card or an eight)" % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	for h in r["hands"]:
		if h["seat"] == w:
			continue
		box.add_child(main._label("%s: left holding %d" % [h["name"], h["points"]], 24, Palette.INK))


func rules() -> Array:
	return [
		"THE TABLE. 2 to 6 players. One player deals each round and the player to their left goes first. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. 7 cards each (5 with 5 or 6 players). The rest is the stock, and one card is turned up to start the pile. A few items are shuffled into the stock: draw one and you keep it and draw again.",
		"PLAYING. On your turn, play one card on the pile that matches the top card's SUIT or RANK. Can't, or would rather not? Tap the stock to DRAW one, then play or PASS.",
		"WHISKEY. Eights are wild: play one on anything and call the suit the next player must match.",
		"SALOON CARDS. 2 is +2: the next player draws 2, unless they stack a 2 of their own on it, and it keeps going round in turn: +4, +6, +8... until someone can't stack and draws the lot. The Ace of Spades is LAST ORDERS: draw 4 (it stacks the same way). A Jack is CUFFED: the next player is skipped. A Queen is KICK BACK: play turns round (with two players it's a skip).",
		"LAST SHOT! Down to your last card? Tap LAST SHOT! before you play your second-last one. Forget, and the table catches you: draw 2.",
		"THE SHOTGUN. First out wins and gets 1 shell, or 2 for going out on a saloon card or an eight, and picks who to shoot. Everyone has 4 health. Last one standing walks out.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	if not main._my_turn():
		return "Keep an eye on who's down to a card or two: a 2 or a Jack can stop them."
	if g.pending_draw > 0:
		return "Got a 2? Stack it and the +%d goes on to the next player. If not, DRAW." % (g.pending_draw + 2)
	if g.playable(main._me()).is_empty():
		return "Nothing fits: tap the stock to draw."
	return "Glowing cards fit. Save your eights for when nothing else does."
