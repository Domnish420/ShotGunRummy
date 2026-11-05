extends "res://scripts/ui/modes/table_mode.gd"

const Session = preload("res://scripts/net/session.gd")
## Snap at the table: FLIP on your turn (or tap your pile), and SNAP! any
## time the top two cards in the middle match.


func buttons() -> Array:
	return [["FLIP", _flip_pressed, Palette.AMBER], ["USE ITEM", main._use_selected_item, Palette.PURPLE], ["SNAP!", _snap_pressed, Palette.RED]]


func refresh() -> void:
	var g = main.game
	var seat: int = main._me()
	var me = g.players[seat]
	var my_turn: bool = main._my_turn()
	main.round_label.text = "ROUND %d · %s DEALS" % [g.round_num, main._name(g.dealer)]
	main.me_name.text = me.name + main._flags(me)
	main._clear(main.me_hp)
	main.me_hp.add_child(main._hp_bar(me))
	main.deadwood_label.text = "WON %d" % g.won.get(seat, []).size()
	main.world.sync({
		"game": g, "viewer": seat, "hand": [], "selected": [], "selected_item": main.selected_item,
		"meld_hints": {}, "lay_hints": {}, "lit": "", "can_draw": my_turn, "targets": {},
		"hide_hand": false,
	})
	main.meld_btn.text = "COUNT UP" if g.last_call else "FLIP"
	main.meld_btn.disabled = not my_turn
	main.discard_btn.disabled = g.phase != "play" or not me.alive
	main.use_btn.disabled = not (my_turn and main.selected_item != "" and g.item_blocker(seat, main.selected_item) == "")
	main.status_label.add_theme_color_override("font_color", Palette.PINK if main.message != "" else Palette.AMBER)
	main.status_label.text = main.message.to_upper() if main.message != "" else status()
	main.go_out_label.visible = false
	_flip_view()


# ---------------------------------------------------------------- the flip view
# The middle pile isn't on the table, where it's too small to see: each card
# flipped shows big, floating over the table. The new card turns over next to
# the one it lands on, overlapping it so both corners show (a 2 next to a 2),
# and after a couple of seconds the old one fades and the new one stays.

const FLIP_TIME := 0.45 # the card turning over
const COMPARE_TIME := 2.0 # how long both cards show
var _view: Control
var _shown_top := ""


func _flip_view() -> void:
	var g = main.game
	if _view == null or not is_instance_valid(_view) or not _view.is_inside_tree():
		_view = Control.new()
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main.screen.add_child(main._full(_view))
		_shown_top = ""
	var pile: Array = g.discard_pile
	var top: Dictionary = pile[-1] if not pile.is_empty() else {}
	var top_id: String = str(top.get("id", ""))
	if top_id == _shown_top:
		return
	_shown_top = top_id
	main._clear(_view)
	if top.is_empty() or main.world.dealing:
		return
	var prev: Dictionary = pile[-2] if pile.size() >= 2 else {}
	var vs: Vector2 = main.get_viewport_rect().size
	var w := clampf(vs.x * 0.27, 110.0, 210.0)
	var size := Vector2(w, w * 1.42)
	var center := Vector2(vs.x * 0.5, vs.y * 0.3)
	var step := w * 0.4 # how much of the old card shows
	var home := center - size * 0.5 # where a lone card sits
	var old_card: CardView = null
	if not prev.is_empty():
		old_card = _card_view(prev, size, false)
		old_card.position = home - Vector2(step * 0.5, 0)
	var new_card := _card_view(top, size, true)
	new_card.position = home + Vector2(step * 0.5 if old_card != null else 0.0, 0)
	var count: Label = main._label("PILE %d" % pile.size(), 26, Palette.INK, true)
	count.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.01))
	count.add_theme_constant_override("outline_size", 10)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.position = Vector2(0, center.y + size.y * 0.5 + 6)
	count.size = Vector2(vs.x, 30)
	_view.add_child(count)
	# turn it over: squash to nothing, show its face, open back out
	var t := new_card.create_tween()
	t.tween_property(new_card, "scale:x", 0.0, FLIP_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func() -> void:
		new_card.face_down = false
		new_card.queue_redraw())
	t.tween_property(new_card, "scale:x", 1.0, FLIP_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	if old_card != null:
		# both side by side for a bit, then down to the one on top
		t.tween_interval(COMPARE_TIME - FLIP_TIME)
		t.tween_property(old_card, "modulate:a", 0.0, 0.35)
		t.parallel().tween_property(new_card, "position", home, 0.35).set_trans(Tween.TRANS_SINE)
		t.tween_callback(old_card.queue_free)


func _card_view(card: Dictionary, size: Vector2, face_down: bool) -> CardView:
	var cv := CardView.new()
	cv.setup(card, size, 0.0, face_down)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.size = size
	cv.pivot_offset = size * 0.5
	_view.add_child(cv)
	return cv


func status() -> String:
	var g = main.game
	if g.phase != "play":
		return "ROUND OVER"
	if main.world.dealing:
		return "SHUFFLING AND DEALING..."
	if g.snap_ready():
		return "THEY MATCH! SNAP!"
	if g.last_call:
		return "EVERY PILE IS EMPTY. LAST CHANCE TO SNAP, THEN COUNT UP"
	if not main._my_turn():
		return waiting_text() + " WATCH FOR A MATCH"
	var it := item_text()
	if it != "":
		return it
	if g.players[main._me()].extra_draws > 0:
		return "DOUBLE DOWN: YOU FLIP 2 CARDS"
	return "YOUR FLIP: TAP YOUR PILE OR FLIP"


func on_pick(hit: Dictionary) -> void:
	match hit.get("kind", ""):
		"item":
			main._toggle_item(hit["id"])
		"stock":
			_flip_pressed()


func _flip_pressed() -> void:
	var g = main.game
	if not main._my_turn():
		return
	main._act("finish" if g.last_call else "flip", [], main._after_simple)


func _snap_pressed() -> void:
	var g = main.game
	if g.phase != "play":
		return
	if not main._online() and _local_people() > 1:
		_who_snapped()
		return
	main._act("snap", [], main._after_simple)


func _local_people() -> int:
	var n := 0
	for p in main.game.players:
		if p.alive and p.bot == "":
			n += 1
	return n


## Pass the phone: whoever grabs it says who they are.
func _who_snapped() -> void:
	var g = main.game
	var box: VBoxContainer = main._open_overlay(0.9, false, "target")
	box.add_child(main._title("WHO SNAPPED?", Palette.RED))
	for p in g.players:
		if p.alive and p.bot == "":
			box.add_child(main._button(p.name, main._closing(_snap_as.bind(p.seat)), 30))
	box.add_child(main._button("CANCEL", main._closing(main._after_action)))


func _snap_as(seat: int) -> void:
	main._after_simple(Session.perform(main.game, seat, "snap", [], true))


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"snap":
			if d["good"]:
				main._log("%s SNAPS and wins %d cards." % [main._name(d["seat"]), d["count"]])
				main.world.announce("SNAP!\n%s +%d" % [main._name(d["seat"]), d["count"]])
				main._flash(Palette.GOLD)
			else:
				main._log("%s snaps at nothing.%s" % [main._name(d["seat"]), " -1 health." if main.game.options["shotgun"] else " 2 cards to the middle."])
				main.world.announce("WRONG!\n%s" % main._name(d["seat"]))
				main._flash(Palette.RED)


func show_result(box: VBoxContainer) -> void:
	var g = main.game
	var r: Dictionary = g.last_result
	var w: int = r["winner"]
	if w < 0:
		box.add_child(main._title("NOBODY WINS"))
		box.add_child(main._label(str(r.get("reason", "")), 26, Palette.INK, true))
	else:
		box.add_child(main._title("%s WON %d CARDS" % [main._name(w), r["points"]], Palette.AMBER))
		if g.options["shotgun"]:
			box.add_child(main._label("%d shell%s in the shotgun. (1, or 2 for winning more than half the deck)" % [r["shells"], "" if r["shells"] == 1 else "s"], 24, Palette.INK, true))
	for h in r["hands"]:
		box.add_child(main._label("%s: %d cards won" % [h["name"], h["points"]], 24, Palette.GOLD if h["seat"] == w else Palette.INK))


func rules() -> Array:
	return [
		"THE TABLE. 2 to 6 players. One player deals each round and the player to their left flips first. Play goes round to the left, and next round the deal moves one seat to the right.",
		"THE DEAL. All the cards are dealt face down into everyone's own pile, with a random few rare items shuffled in. Nobody looks at their pile.",
		"YOUR TURN. FLIP the top card of your pile onto the pile in the middle (tap your pile or press FLIP). Flip an item and you keep it and flip again.",
		"SNAP! When the top two cards in the middle match, anyone can press SNAP! at any time. The first to snap wins every card in the middle.",
		"WRONG SNAPS. Snap when they don't match and you lose 1 health (in normal mode, 2 cards from your pile go in the middle).",
		"THE END. When everyone's pile has run out, whoever won the most cards wins: 1 shell, or 2 for winning more than half the deck.",
		"ON ONE PHONE. With more than one person, whoever grabs the phone first presses SNAP! and says who they are.",
	]


func coach() -> String:
	var g = main.game
	if g.phase != "play":
		return ""
	if g.snap_ready():
		return "The top two cards match! Press SNAP! before the AIs do."
	if main._my_turn():
		return "Your turn: FLIP your top card onto the middle. Then watch for two in a row that match."
	return "Watch the middle. Same rank twice in a row and you SNAP!"
