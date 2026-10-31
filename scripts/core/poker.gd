extends "res://scripts/core/game.gd"
## Shotgun Poker: Texas Hold'em where you bet shells instead of chips.
##
## - Everyone gets 2 cards face down (no items: they turn up as loot). Five cards are dealt face up
##   in the middle over the round: three (the flop), then one (the turn), then
##   one (the river), with a betting round before each and after the last.
## - Betting starts left of the dealer. CHECK (or CALL a raise), RAISE, or
##   FOLD. Every raise loads another shell into the shotgun (max 3); once
##   someone raises, everyone else still in must call it or fold.
## - FOLD and you can't win, but you're safe: the winner can't shoot you.
## - Best five-card hand from your two and the five in the middle wins (if
##   everyone else folds, the last one in wins). They fire every shell that was
##   loaded (1, plus 1 per raise), but only at players who stayed in.

const STREETS := ["preflop", "flop", "turn", "river"]
const HAND_NAMES := ["HIGH CARD", "A PAIR", "TWO PAIR", "THREE OF A KIND", "A STRAIGHT", "A FLUSH", "A FULL HOUSE", "FOUR OF A KIND", "A STRAIGHT FLUSH"]

var street := 0 # index in STREETS
var board: Array = [] # the cards in the middle
var shells := 1 # loaded so far
var folded := {} # seat -> true
var raised_by := -1 # who raised this street (-1: nobody)
var _to_act: Array = [] # seats still to act this street, in order
var must_call := {} # Double Down: seat -> true (can't fold this hand)


func _init() -> void:
	kind = "poker"
	options["trump_cards"] = false # trumps are Rummy's


func table_note(seat: int) -> String:
	if folded.has(seat):
		return "FOLDED"
	if phase == "round_over" or phase == "shoot":
		return ""
	return "IN"


# ---------------------------------------------------------------- hands

static func _v(card: Dictionary) -> int:
	var r := int(card["rank"])
	return 14 if r == 1 else r


## How strong five cards are: [category, tiebreakers...], higher is better.
static func rank5(cards: Array) -> Array:
	var vals := []
	var suits := {}
	var counts := {}
	for c in cards:
		var v := _v(c)
		vals.append(v)
		suits[c["suit"]] = true
		counts[v] = int(counts.get(v, 0)) + 1
	vals.sort()
	vals.reverse()
	var flush := suits.size() == 1
	var uniq := counts.keys()
	uniq.sort()
	uniq.reverse()
	var straight_high := 0
	if uniq.size() == 5:
		if int(uniq[0]) - int(uniq[4]) == 4:
			straight_high = uniq[0]
		elif uniq == [14, 5, 4, 3, 2]:
			straight_high = 5 # A-2-3-4-5
	# group by count, then value: [[count, value], ...]
	var groups := []
	for v in uniq:
		groups.append([counts[v], v])
	groups.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var by_group := []
	for gr in groups:
		by_group.append(gr[1])
	if straight_high > 0 and flush:
		return [8, straight_high]
	if groups[0][0] == 4:
		return [7] + by_group
	if groups[0][0] == 3 and groups.size() > 1 and groups[1][0] == 2:
		return [6] + by_group
	if flush:
		return [5] + vals
	if straight_high > 0:
		return [4, straight_high]
	if groups[0][0] == 3:
		return [3] + by_group
	if groups[0][0] == 2 and groups[1][0] == 2:
		return [2] + by_group
	if groups[0][0] == 2:
		return [1] + by_group
	return [0] + vals


static func better(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## The best five of any cards (up to 7).
static func best_hand(cards: Array) -> Array:
	if cards.size() <= 5:
		return rank5(cards) if cards.size() == 5 else [-1]
	var best := [-1]
	var n := cards.size()
	for a in range(n):
		for b in range(a + 1, n):
			# leave out cards a and b
			var five := []
			for i in range(n):
				if i != a and i != b:
					five.append(cards[i])
			if five.size() == 5:
				var r := rank5(five)
				if better(r, best):
					best = r
			elif n == 6:
				pass
	if n == 6:
		for a in range(n):
			var five := []
			for i in range(n):
				if i != a:
					five.append(cards[i])
			var r := rank5(five)
			if better(r, best):
				best = r
	return best


func hand_of(seat: int) -> Array:
	return best_hand(players[seat].hand + board)


func hand_name(rank: Array) -> String:
	return HAND_NAMES[int(rank[0])] if int(rank[0]) >= 0 else ""


# ---------------------------------------------------------------- the round

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = 0
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
	for i in range(2):
		for s in order:
			players[s].hand.append(deck.pop_back())
	var items := _round_items()
	for k in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	item_deck = items
	stock = deck # the rest of the deck, for the middle
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	board = []
	shells = 1
	folded = {}
	must_call = {}
	street = 0
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": 0})
	_start_street()
	return _ok()


func _in_hand() -> Array:
	var out := []
	for s in _seats_from(next_alive(dealer)):
		if not folded.has(s) and players[s].alive:
			out.append(s)
	return out


func _start_street() -> void:
	raised_by = -1
	_to_act = _in_hand()
	_next_actor()


func _next_actor() -> void:
	if phase == "match_over":
		return
	if _in_hand().size() <= 1:
		_showdown()
		return
	while not _to_act.is_empty():
		var s: int = _to_act.pop_front()
		if folded.has(s) or not players[s].alive:
			continue
		var p: Player = players[s]
		if p.cuffed:
			# handcuffed: checks if they can, or calls
			p.cuffed = false
			_emit("turn_skipped", {"seat": s})
			continue
		turn = s
		phase = "play"
		items_used_this_turn = 0
		p.turns_taken += 1
		_emit("turn_start", {"seat": s})
		return
	# everyone has acted: the next card(s), or the showdown
	street += 1
	if street >= STREETS.size():
		_showdown()
		return
	var n := 3 if street == 1 else 1
	for i in range(n):
		if not stock.is_empty():
			var c: Dictionary = stock.pop_back()
			c["shown"] = true
			board.append(c)
	_emit("board", {"street": STREETS[street], "cards": board.duplicate(true)})
	# now and then an item comes out with the cards, to someone still in
	var live := _in_hand()
	if not live.is_empty():
		_loot(players[live[rng.randi_range(0, live.size() - 1)]], 0.25)
	_start_street()


func to_call(seat: int) -> bool:
	return raised_by >= 0 and raised_by != seat


func can_raise(seat: int) -> bool:
	return is_turn_of(seat) and shells < int(options["max_shells"]) and raised_by != seat


func check_call(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var calling := to_call(seat)
	_emit("bet", {"seat": seat, "action": "call" if calling else "check", "shells": shells})
	_next_actor()
	return _ok()


func raise(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not can_raise(seat):
		return _fail("The shotgun's full: %d shells is the most." % int(options["max_shells"]) if shells >= int(options["max_shells"]) else "You can't raise yourself.")
	shells += 1
	raised_by = seat
	_emit("bet", {"seat": seat, "action": "raise", "shells": shells})
	# everyone else still in has to answer it
	_to_act = []
	for s in _seats_from(next_alive(seat)):
		if s != seat and not folded.has(s) and players[s].alive:
			_to_act.append(s)
	_next_actor()
	return _ok()


func fold(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if must_call.has(seat):
		return _fail("Double Down: you can't fold this hand.")
	var p := current()
	folded[seat] = true
	_emit("bet", {"seat": seat, "action": "fold", "shells": shells})
	if p.ultimatum:
		p.ultimatum = false
		if _russian_roulette(p):
			return _ok()
	_next_actor()
	return _ok()


func _showdown() -> void:
	var live := _in_hand()
	var best := [-1]
	var winners := []
	for s in live:
		for c in players[s].hand:
			c["shown"] = true
		var r: Array = hand_of(s) if live.size() > 1 else [-1]
		if winners.is_empty() or better(r, best):
			best = r
			winners = [s]
		elif r == best:
			winners.append(s)
	var w: int = winners[0] if winners.size() == 1 else -1
	var hands := []
	for p in players:
		if p.alive:
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": 0,
				"folded": folded.has(p.seat), "hand": hand_name(hand_of(p.seat)) if not folded.has(p.seat) and board.size() >= 3 else ""})
	var targets := []
	for s in live:
		if s != w:
			targets.append(s)
	var result := {"round": round_num, "winner": w, "points": 0, "shells": shells, "rummy": false, "hands": hands,
		"hand": hand_name(best), "board": board.duplicate(true), "targets": targets,
		"reason": "" if w >= 0 else "A split pot. Nobody shoots."}
	if w >= 0:
		players[w].rounds_won += 1
		players[w].score += shells
	last_result = result
	if options["shotgun"] and w >= 0 and not targets.is_empty():
		phase = "shoot"
		gun = {"holder": w, "shells": shells, "total": shells, "targets": targets}
	else:
		phase = "round_over"
		gun = null
		if w >= 0 and targets.is_empty():
			result["reason"] = "Everyone else folded: they're safe."
	_emit("round_end", result)
	_check_normal_match()


func shoot(shooter: int, target: int) -> Dictionary:
	if gun != null and gun.has("targets") and int(gun["holder"]) == shooter and not gun["targets"].has(target):
		return _fail("They folded: they're safe this round.")
	var res := super.shoot(shooter, target)
	if res["ok"] and phase == "shoot" and gun != null:
		var anyone := false
		for t in gun["targets"]:
			if players[t].alive:
				anyone = true
		if not anyone:
			_emit("gun_empty", {"seat": shooter})
			phase = "round_over"
			gun = null
	return res


func _next_turn() -> void:
	# someone was knocked out on their turn: on to the next player
	if phase == "play":
		_next_actor()


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	match action:
		"call":
			return check_call(seat)
		"raise":
			return raise(seat)
		"fold":
			return fold(seat)
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Check, raise or fold.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Check, raise or fold.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in Poker.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Poker.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Poker.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Check, raise or fold.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


func _end_reveals(_p: Player) -> void:
	pass # shown cards stay shown for the hand


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	for p in others(seat):
		if folded.has(p.seat):
			continue
		match item_id:
			"handcuffs":
				if not p.cuffed:
					out.append(p.seat)
			"revolver":
				if not p.ultimatum:
					out.append(p.seat)
			"double_down":
				if not must_call.has(p.seat):
					out.append(p.seat)
			"spotlight":
				if not p.exposed:
					out.append(p.seat)
			"adrenaline":
				if not p.items.is_empty():
					out.append(p.seat)
			_:
				out.append(p.seat)
	return out


func item_blocker(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> String:
	var card := find_item(seat, item_card_id)
	if not card.is_empty() and card["item"] in ["magnifier", "beer"]:
		var err := _guard(seat)
		if err != "":
			return err
		if board.size() >= 5 or stock.is_empty():
			return "All the cards in the middle are out."
		return ""
	return super.item_blocker(seat, item_card_id, target, choice)


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"magnifier":
			return {"text": "%s peeks at the next card for the middle" % p.name, "reveal": stock.back(), "private": true}
		"beer":
			var burnt: Dictionary = stock.pop_back()
			burned.append(burnt)
			return {"text": "%s burns the next card for the middle: %s" % [p.name, Cards.card_name(burnt)], "reveal": burnt, "private": false}
		"phone":
			var called: Player = players[target]
			return {"text": "%s makes a call about %s's cards" % [p.name, called.name], "reveal": _random_card(called.hand), "private": true}
		"spotlight":
			var lit: Player = players[target]
			lit.exposed = true
			for c in lit.hand:
				c["shown"] = true
			return {"text": "%s shines a spotlight on %s's cards: %s" % [p.name, lit.name, Cards.cards_text(lit.hand)]}
		"flashbang":
			var shown := []
			for o in others(p.seat):
				if folded.has(o.seat) or o.hand.is_empty():
					continue
				var c: Dictionary = _random_card(o.hand)
				c["shown"] = true
				shown.append("%s: %s" % [o.name, Cards.card_name(c)])
			return {"text": "%s sets off a flashbang. %s" % [p.name, ", ".join(shown)]}
		"shakedown":
			var mark: Player = players[target]
			var old: Dictionary = _random_card(mark.hand)
			mark.hand.erase(old)
			burned.append(old)
			mark.hand.append(stock.pop_back() if not stock.is_empty() else old)
			return {"text": "%s shakes down %s, who throws away %s and gets a new card" % [p.name, mark.name, Cards.card_name(old)], "reveal": old, "private": false}
		"handcuffs":
			var cuffed: Player = players[target]
			cuffed.cuffed = true
			return {"text": "%s handcuffs %s: they skip their next go (they stay in)" % [p.name, cuffed.name]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: fold and spin it" % [p.name, marked.name]}
		"double_down":
			must_call[target] = true
			return {"text": "%s doubles down on %s: they can't fold this hand" % [p.name, players[target].name]}
		"bad_trade":
			var partner: Player = players[target]
			var give: Dictionary = _random_card(p.hand)
			var take: Dictionary = _random_card(partner.hand)
			p.hand[p.hand.find(give)] = take
			partner.hand[partner.hand.find(take)] = give
			return {"text": "%s trades a random card with %s" % [p.name, partner.name]}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["street"] = street
	d["board"] = board.duplicate(true)
	d["shells_loaded"] = shells
	d["folded"] = folded.duplicate()
	d["raised_by"] = raised_by
	d["to_act"] = _to_act.duplicate()
	d["must_call"] = must_call.duplicate()
	d["stock"] = _hidden(stock.size(), "s")
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	street = int(d.get("street", 0))
	board = d.get("board", [])
	shells = int(d.get("shells_loaded", 1))
	folded = d.get("folded", {})
	raised_by = int(d.get("raised_by", -1))
	_to_act = d.get("to_act", [])
	must_call = d.get("must_call", {})
