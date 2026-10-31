extends "res://scripts/core/game.gd"
## Shotgun President. Same table: a rotating dealer, items, a wild trump
## rank, health and the shotgun.
##
## - All the cards are dealt out, plus 2 items each.
## - 3 is low, then up to K, A, and 2 is high.
## - The player left of the dealer leads a single, a pair, three or four of a
##   kind. Going round, each player must beat it with the same number of a
##   higher rank, or PASS (and sit out until the pile clears). When everyone
##   else has passed, the pile clears and the last player to play leads again.
## - Trumps are wild: they fill in any set (a 9 and a trump is a pair of 9s).
##   Trumps on their own beat everything.
## - First to get rid of their cards is PRESIDENT and wins the round, with 1
##   shell for every 2 other players (at least 1, at most 3). Whoever is left
##   holding the most cards is the SCUM: next round they hand the President
##   their best card and get the President's worst one back.

var pile_top := {} # { seat, ids, count, value }: the play to beat
var passed := {} # seat -> true: out until the pile clears
var president := -1 # last round's winner
var scum := -1 # last round's most cards


func _init() -> void:
	kind = "president"
	options["trump_cards"] = false # trumps are Rummy's


func table_note(seat: int) -> String:
	var tags := []
	if seat == president:
		tags.append("PRESIDENT")
	if seat == scum:
		tags.append("SCUM")
	if passed.has(seat):
		tags.append("PASSED")
	return " · ".join(tags)


## 3 lowest ... K, A, 2 highest; a wild alone above everything.
static func card_value(card: Dictionary) -> int:
	var r := int(card["rank"])
	if r == 1:
		return 14
	if r == 2:
		return 15
	return r


## The value of a play, or 0 if those cards aren't a set.
func play_value(cards: Array) -> int:
	if cards.is_empty() or cards.size() > 4:
		return 0
	var v := 0
	for c in cards:
		if Cards.is_wild(c, trump_rank):
			continue
		var cv := card_value(c)
		if v != 0 and cv != v:
			return 0
		v = cv
	return v if v != 0 else 16 # all trumps


# ---------------------------------------------------------------- the round

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	if round_num == 1:
		president = -1
		scum = -1
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = trump_for_round(round_num) if options["trump_cards"] else 0
	for p in players:
		p.hand = []
		p.items = []
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0
	var order := _seats_from(next_alive(dealer))
	var deck := _shuffle(Cards.create_deck())
	var i := 0
	while not deck.is_empty():
		players[order[i % order.size()]].hand.append(deck.pop_back())
		i += 1
	var items := _shuffle(Items.create_item_deck())
	for k in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	item_deck = items
	stock = []
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	pile_top = {}
	passed = {}
	_temp_wild = []
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_exchange()
	_begin_turn()
	return _ok()


## The Scum hands over their best card; the President gives back their worst.
func _exchange() -> void:
	if president < 0 or scum < 0 or president == scum or not players[president].alive or not players[scum].alive:
		return
	var s: Player = players[scum]
	var p: Player = players[president]
	var best: Dictionary = s.hand[0]
	for c in s.hand:
		if _sort_value(c) > _sort_value(best):
			best = c
	s.hand.erase(best)
	p.hand.append(best)
	var worst: Dictionary = p.hand[0]
	for c in p.hand:
		if c != best and _sort_value(c) < _sort_value(worst):
			worst = c
	p.hand.erase(worst)
	s.hand.append(worst)
	_emit("exchange", {"president": president, "scum": scum})


func _sort_value(c: Dictionary) -> int:
	return 16 if Cards.is_wild(c, trump_rank) else card_value(c)


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


func _next_turn() -> void:
	if phase != "play":
		return
	_end_reveals(current())
	for i in range(players.size()):
		turn = next_alive(turn)
		var p: Player = players[turn]
		if p.hand.is_empty():
			continue
		if not pile_top.is_empty() and turn == int(pile_top["seat"]):
			# everyone else passed: the pile clears, they lead again
			_clear_pile()
			_begin_turn()
			return
		if passed.has(turn):
			continue
		if p.cuffed:
			p.cuffed = false
			passed[turn] = true
			_emit("turn_skipped", {"seat": turn})
			continue
		_begin_turn()
		return
	# only the last player is left in: clear and let them lead
	if not pile_top.is_empty():
		turn = int(pile_top["seat"]) if players[int(pile_top["seat"])].alive and not players[int(pile_top["seat"])].hand.is_empty() else next_alive(turn)
	_clear_pile()
	_begin_turn()


func _clear_pile() -> void:
	pile_top = {}
	passed = {}
	_emit("pile_cleared", {"seat": turn})


func can_pass(seat: int) -> bool:
	return is_turn_of(seat) and not pile_top.is_empty()


func play(seat: int, card_ids: Array) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Pick the cards to play.")
	var v := play_value(cards)
	if v == 0:
		return _fail("Play a single, a pair, three or four of the same rank (trumps fill in).")
	if not pile_top.is_empty():
		if cards.size() != int(pile_top["count"]):
			return _fail("Play %d card%s to beat it." % [pile_top["count"], "" if int(pile_top["count"]) == 1 else "s"])
		if v <= int(pile_top["value"]):
			return _fail("That doesn't beat it: play higher, or PASS.")
	for c in cards:
		p.hand.erase(c)
		c.erase("shown")
		discard_pile.append(c)
	p.ultimatum = false
	pile_top = {"seat": seat, "ids": Cards.ids_of(cards), "count": cards.size(), "value": v}
	_emit("president_play", {"seat": seat, "cards": cards.duplicate(), "value": v})
	if p.hand.is_empty():
		_finish_round(seat)
		return _ok()
	_next_turn()
	return _ok()


func pass_turn(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if pile_top.is_empty():
		return _fail("You're leading: play something.")
	var p := current()
	passed[seat] = true
	_emit("pass", {"seat": seat})
	if p.ultimatum:
		p.ultimatum = false
		if _russian_roulette(p):
			return _ok()
	_next_turn()
	return _ok()


func _finish_round(w: int) -> void:
	var hands := []
	var most := -1
	var worst := -1
	for p in players:
		if not p.alive:
			continue
		hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": p.hand.size()})
		if p.seat != w and p.hand.size() > most:
			most = p.hand.size()
			worst = p.seat
	president = w
	scum = worst
	var others_n := alive_count() - 1
	var result := {"round": round_num, "winner": w, "points": 0, "shells": 0, "rummy": false, "hands": hands, "scum": worst, "reason": ""}
	players[w].rounds_won += 1
	result["shells"] = clampi(int(others_n / 2), 1, int(options["max_shells"]))
	last_result = result
	if options["shotgun"]:
		phase = "shoot"
		gun = {"holder": w, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
		gun = null
	_emit("round_end", result)
	_check_normal_match()


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	match action:
		"play":
			if args.size() == 1 and args[0] is Array:
				return play(seat, args[0])
		"pass":
			return pass_turn(seat)
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Play, or pass.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Play, or pass.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in President.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in President.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in President.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Play, or pass.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"revolver":
			for p in others(seat):
				if not p.ultimatum and not p.hand.is_empty():
					out.append(p.seat)
			return out
		"handcuffs", "shakedown":
			for p in others(seat):
				if not p.hand.is_empty() and (item_id != "handcuffs" or not p.cuffed):
					out.append(p.seat)
			return out
	return super.item_targets(seat, item_id)


func item_blocker(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> String:
	var card := find_item(seat, item_card_id)
	if not card.is_empty() and card["item"] == "shakedown" and players[seat].hand.size() <= 1:
		return "You need a card to give away."
	return super.item_blocker(seat, item_card_id, target, choice)


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"shakedown":
			var mark: Player = players[target]
			var worst: Dictionary = p.hand[0]
			for c in p.hand:
				if _sort_value(c) < _sort_value(worst):
					worst = c
			p.hand.erase(worst)
			mark.hand.append(worst)
			return {"text": "%s shoves their worst card onto %s" % [p.name, mark.name]}
		"handcuffs":
			var cuffed: Player = players[target]
			cuffed.cuffed = true
			return {"text": "%s handcuffs %s: they pass their next turn" % [p.name, cuffed.name]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: pass next turn and spin it" % [p.name, marked.name]}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true # for the rest of the round
					return {"text": "%s paints a card wild" % p.name, "reveal": c, "private": true}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["pile_top"] = pile_top.duplicate()
	d["passed"] = passed.duplicate()
	d["president"] = president
	d["scum"] = scum
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	pile_top = d.get("pile_top", {})
	passed = d.get("passed", {})
	president = int(d.get("president", -1))
	scum = int(d.get("scum", -1))
