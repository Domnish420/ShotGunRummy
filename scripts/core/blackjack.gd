extends "res://scripts/core/game.gd"
## Shotgun Blackjack. Same table as Shotgun Rummy: a rotating dealer, items
## shuffled into the stock, trump cards, health and the shotgun.
##
## Everyone plays against the dealer, who is one of the players:
## - Everyone is dealt 2 cards (one face down, one face up) and 2 items.
## - Starting left of the dealer and going round to the left, each player
##   HITs (takes a card) as often as they like, then STANDs. The dealer plays
##   last. Use items any time on your turn. Draw an item and you keep it and
##   draw again. The deal moves one seat to the right each round.
## - Go over 21 and you're bust.
## - 2-10 count their number, J/Q/K 10, an ace 1 or 11. This round's trump is
##   wild: it counts as whatever you need (1 to 11).
## - Each player is compared with the dealer: bust loses; if the dealer is
##   bust, everyone still in wins; otherwise the higher hand wins (a Blackjack,
##   21 with your first 2 cards, beats a five-card Charlie, which beats the
##   highest total). The same hand is a push.
## - The dealer gets 1 shell for each player who lost (max 3), and can only
##   shoot players who lost.
## - The moment a player has a Blackjack, they shoot the dealer, free.

func _init() -> void:
	kind = "blackjack"
	options["trump_cards"] = false # trumps are Rummy's
	options.merge({
		"hand_size": 2,
		"items_dealt": 2,
		"charlie_cards": 5,
	}, true)


var _order: Array = [] # seats in turn order this round (the dealer last)
var _shooters: Array = [] # [seat, shells, targets] still waiting for the shotgun this round
var _shot_dealer := {} # seats that have had their free Blackjack shot this round
var _hit_this_turn := false


# ---------------------------------------------------------------- totals

## Best total for a hand: aces are 1 or 11, trumps anything from 1 to 11.
static func total(hand: Array, trump: int) -> int:
	var sum := 0
	var aces := 0
	var wilds := 0
	for c in hand:
		if c.has("item") or c.get("hidden", false):
			continue
		if Cards.is_wild(c, trump):
			wilds += 1
			sum += 1
		elif int(c["rank"]) == 1:
			aces += 1
			sum += 1
		else:
			sum += mini(10, int(c["rank"]))
	if sum > 21:
		return sum
	for i in range(wilds):
		sum += mini(10, 21 - sum)
	for i in range(aces):
		if sum + 10 <= 21:
			sum += 10
	return sum


func hand_total(seat: int) -> int:
	return total(players[seat].hand, trump_rank)


## What everyone else can see of a hand: its face-up cards.
func showing_total(seat: int) -> int:
	var up := []
	for c in players[seat].hand:
		if c.get("shown", false) or players[seat].exposed:
			up.append(c)
	return total(up, trump_rank)


func is_blackjack(seat: int) -> bool:
	return players[seat].hand.size() == 2 and hand_total(seat) == 21


func is_charlie(seat: int) -> bool:
	var p: Player = players[seat]
	return p.hand.size() >= int(options["charlie_cards"]) and hand_total(seat) <= 21


## Has every player except the dealer gone bust? Then the dealer wins
## without playing.
func _all_bust_but_dealer() -> bool:
	for p in players:
		if p.alive and p.seat != dealer and not p.bust:
			return false
	return true


## Players still in this round: alive and not bust.
func in_round() -> Array:
	var out := []
	for p in players:
		if p.alive and not p.bust:
			out.append(p)
	return out


# ---------------------------------------------------------------- the round

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = trump_for_round(round_num) if options["trump_cards"] else 0
	for p in players:
		p.hand = []
		p.items = []
		p.has_melded = false
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0
		p.stood = false
		p.bust = false

	_order = _seats_from(next_alive(dealer))
	var deck := _shuffle(Cards.create_deck())
	var items := _shuffle(Items.create_item_deck())
	# first card face down, second face up
	for i in range(int(options["hand_size"])):
		for s in _order:
			var c: Dictionary = deck.pop_back()
			if i > 0:
				c["shown"] = true
			players[s].hand.append(c)
	for i in range(int(options["items_dealt"])):
		for s in _order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	stock = _shuffle(deck + items) if options["items_in_stock"] else deck
	item_deck = [] if options["items_in_stock"] else items
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	_shooters = []
	_shot_dealer = {}
	turn = _order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_blackjack_shots()
	if phase == "match_over":
		return _ok()
	if not players[dealer].alive:
		_finish_round() # a Blackjack finished the dealer off before anyone played
		return _ok()
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	drawn_from_discard = ""
	items_used_this_turn = 0
	placed_this_turn = false
	_hit_this_turn = false
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


## On to the next player who still has a turn, or the end of the round.
func _next_turn() -> void:
	if phase != "play":
		return
	if _all_bust_but_dealer():
		_finish_round()
		return
	var at := _order.find(turn)
	for i in range(at + 1, _order.size()):
		var p: Player = players[_order[i]]
		if not p.alive or p.bust or p.stood:
			continue
		if p.cuffed:
			p.cuffed = false
			p.stood = true
			_emit("turn_skipped", {"seat": p.seat})
			continue
		turn = p.seat
		_begin_turn()
		return
	_finish_round()


## A Blackjack shoots the dealer straight away, free: no shells used.
## Checked after the deal and whenever an item reshuffles hands.
func _blackjack_shots() -> void:
	if not options["shotgun"]:
		return
	for s in _order:
		var p: Player = players[s]
		var d: Player = players[dealer]
		if s == dealer or not p.alive or not d.alive or _shot_dealer.has(s) or not is_blackjack(s):
			continue
		_shot_dealer[s] = true
		_emit("blackjack_shot", {"shooter": s, "target": dealer, "damage": 1})
		damage(dealer, 1, "blackjack")
		if phase == "match_over":
			return
		if not d.alive:
			if phase == "play":
				_finish_round() # no dealer, no round
			return


## How strong a hand is, to compare it with the dealer's.
func _rank(seat: int) -> Array:
	return [1 if is_blackjack(seat) else 0, 1 if is_charlie(seat) else 0, hand_total(seat)]


func _finish_round() -> void:
	var d: Player = players[dealer]
	var dealer_out: bool = not d.alive or d.bust
	var hands := []
	for p in players:
		if p.alive:
			for c in p.hand:
				c["shown"] = true # everything is turned over at the end
	var losers := []
	_shooters = []
	var duels := []
	for s in _order:
		var p: Player = players[s]
		if not p.alive or s == dealer:
			continue
		var outcome := "push"
		if p.bust:
			outcome = "lose"
		elif dealer_out or _beats(_rank(s), _rank(dealer)):
			outcome = "win"
		elif _beats(_rank(dealer), _rank(s)):
			outcome = "lose"
		if outcome == "win":
			p.rounds_won += 1
			p.score += hand_total(s)
		elif outcome == "lose":
			losers.append(s)
		duels.append({"seat": s, "outcome": outcome, "shells": 0})
	var dealer_shells := 0
	if d.alive and not losers.is_empty():
		dealer_shells = mini(int(options["max_shells"]), losers.size())
		d.rounds_won += 1
		d.score += hand_total(dealer)
		_shooters.append([dealer, dealer_shells, losers.duplicate()])
	for p in players:
		if p.alive:
			var note := ""
			for duel in duels:
				if duel["seat"] == p.seat:
					note = duel["outcome"]
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": hand_total(p.seat), "bust": p.bust, "outcome": note if p.seat != dealer else "dealer", "blackjack": is_blackjack(p.seat), "charlie": is_charlie(p.seat)})
	var first: int = _shooters[0][0] if not _shooters.is_empty() else -1
	var result := {
		"round": round_num, "winner": first, "dealer": dealer, "dealer_bust": d.bust, "dealer_total": hand_total(dealer),
		"dealer_shells": dealer_shells, "duels": duels, "shooters": _shooters.duplicate(true),
		"points": hand_total(first) if first >= 0 else 0, "shells": _shooters[0][1] if first >= 0 else 0,
		"rummy": false, "blackjack": first >= 0 and is_blackjack(first), "charlie": first >= 0 and is_charlie(first),
		"losers": losers, "hands": hands,
		"reason": "" if first >= 0 else ("The dealer is out. Nobody shoots." if not d.alive else "Nobody lost to the dealer. Nobody gets shot."),
	}
	last_result = result
	phase = "round_over"
	gun = null
	_emit("round_end", result)
	if options["shotgun"]:
		_pass_gun()
	else:
		_shooters = []
		_check_normal_match()


## Hands the shotgun to the next player waiting to shoot this round.
func _pass_gun() -> void:
	while not _shooters.is_empty():
		var next: Array = _shooters.pop_front()
		if not players[next[0]].alive:
			continue
		phase = "shoot"
		gun = {"holder": next[0], "shells": next[1], "total": next[1], "targets": next[2]}
		_emit("gun_passed", {"seat": next[0], "shells": next[1]})
		return
	if phase != "match_over":
		phase = "round_over"
		gun = null


func shoot(shooter: int, target: int) -> Dictionary:
	if gun != null and gun.has("targets") and int(gun["holder"]) == shooter and not gun["targets"].has(target):
		return _fail("The dealer can only shoot players who lost.")
	var res := super.shoot(shooter, target)
	if res["ok"] and phase == "shoot" and gun != null and gun.has("targets"):
		var anyone := false
		for t in gun["targets"]:
			if players[t].alive:
				anyone = true
		if not anyone:
			# everyone who lost is already dead: put the gun down
			_emit("gun_empty", {"seat": shooter})
			phase = "round_over"
			gun = null
	if res["ok"] and phase == "round_over":
		_pass_gun() # this one's empty: next shooter
	return res


static func _beats(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


# ---------------------------------------------------------------- moves

## Take a card. Items go to your items and you draw again. Bust, 21 or a
## five-card Charlie ends your turn.
func hit(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var card := _deal_to(p)
	if card.is_empty():
		return stand(seat) # nothing left to draw
	_hit_this_turn = true
	p.ultimatum = false
	var t := hand_total(seat)
	_emit("hit", {"seat": seat, "card": card, "total": t})
	if t > 21:
		_go_bust(p)
	elif t == 21 or is_charlie(seat):
		p.stood = true
		_emit("stand", {"seat": seat, "total": t})
		_next_turn()
	return _ok({"card": card, "total": t, "bust": p.bust})


## Deals the next playing card face up to `p`, keeping any items on the way.
func _deal_to(p: Player) -> Dictionary:
	while true:
		if stock.is_empty():
			if discard_pile.is_empty() and burned.is_empty():
				return {}
			stock = _shuffle(discard_pile + burned)
			for c in stock:
				c.erase("wild")
			discard_pile = []
			burned = []
			_emit("stock_reshuffled", {"size": stock.size()})
		var card: Dictionary = stock.pop_back()
		if card.has("item"):
			p.items.append(card)
			_emit("draw", {"seat": p.seat, "source": "stock", "item": true})
			continue
		card["shown"] = true
		p.hand.append(card)
		return card
	return {}


func _go_bust(p: Player) -> void:
	p.bust = true
	_emit("bust", {"seat": p.seat, "total": hand_total(p.seat)})
	if is_turn_of(p.seat):
		_next_turn()
	elif _all_bust_but_dealer() and phase == "play":
		_finish_round()


func stand(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	if p.ultimatum and not _hit_this_turn:
		p.ultimatum = false
		if _russian_roulette(p):
			return _ok({"total": 0}) # they didn't survive it
	p.stood = true
	_emit("stand", {"seat": seat, "total": hand_total(seat)})
	_next_turn()
	return _ok({"total": hand_total(seat)})


# none of Rummy's moves exist here
func draw_stock(seat: int) -> Dictionary:
	return hit(seat)


func draw_discard(_seat: int) -> Dictionary:
	return _fail("There's no drawing from the discard pile in Blackjack.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in Blackjack.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Blackjack.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Blackjack.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("There's no discarding in Blackjack. HIT or STAND.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


## Reveals last the whole round in Blackjack.
func _end_reveals(_p: Player) -> void:
	pass


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	for p in others(seat):
		var waiting: bool = not p.bust and not p.stood and p.turns_taken == 0
		match item_id:
			"handcuffs":
				if waiting and not p.cuffed:
					out.append(p.seat)
			"revolver":
				if waiting and not p.ultimatum:
					out.append(p.seat)
			"phone":
				if _face_down(p) != {}:
					out.append(p.seat)
			"spotlight":
				if not p.exposed and _face_down(p) != {}:
					out.append(p.seat)
			"adrenaline":
				if not p.items.is_empty():
					out.append(p.seat)
			"shakedown":
				if not p.bust and p.hand.size() >= 3:
					out.append(p.seat)
			"switcheroo", "bad_trade", "double_down":
				if not p.bust and not p.hand.is_empty():
					out.append(p.seat)
			_:
				out.append(p.seat)
	return out


func item_choices(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"sticky_fingers":
			for p in others(seat):
				if p.bust or p.hand.size() < 2:
					continue
				for c in p.hand:
					if c.get("shown", false) or p.exposed:
						out.append(c["id"])
		"joker_paint":
			for c in players[seat].hand:
				if not Cards.is_wild(c, trump_rank):
					out.append(c["id"])
	return out


func _face_down(p: Player) -> Dictionary:
	for c in p.hand:
		if not c.get("shown", false):
			return c
	return {}


func use_item(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> Dictionary:
	var res := super.use_item(seat, item_card_id, target, choice)
	if res["ok"]:
		_recheck_hands()
	return res


## After an item moves cards around: anyone over 21 is bust, anyone back
## under it is back in (standing on what they have).
func _recheck_hands() -> void:
	if phase != "play":
		return
	var me := turn
	for p in players:
		if not p.alive:
			continue
		var over := hand_total(p.seat) > 21
		if over and not p.bust:
			p.bust = true
			_emit("bust", {"seat": p.seat, "total": hand_total(p.seat)})
		elif not over and p.bust:
			p.bust = false
			p.stood = true
	if phase != "play":
		return
	_blackjack_shots()
	if phase != "play":
		return
	if players[me].bust:
		_next_turn()
	elif _all_bust_but_dealer():
		_finish_round()


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"phone":
			var called: Player = players[target]
			return {"text": "%s makes a call about %s's face-down card" % [p.name, called.name], "reveal": _face_down(called), "private": true}
		"handcuffs":
			var cuffed: Player = players[target]
			cuffed.cuffed = true
			return {"text": "%s handcuffs %s. They'll stand on what they have" % [p.name, cuffed.name]}
		"shakedown":
			var mark: Player = players[target]
			var dropped: Dictionary = mark.hand.pop_back()
			discard_pile.append(dropped)
			return {"text": "%s shakes down %s, who throws away %s" % [p.name, mark.name, Cards.card_name(dropped)], "reveal": dropped, "private": false}
		"bad_trade":
			var partner: Player = players[target]
			var give: Dictionary = _random_card(p.hand)
			var take: Dictionary = _random_card(partner.hand)
			var i := p.hand.find(give)
			var j := partner.hand.find(take)
			p.hand[i] = take
			partner.hand[j] = give
			return {"text": "%s trades a random card with %s" % [p.name, partner.name]}
		"spotlight":
			var lit: Player = players[target]
			var down := _face_down(lit)
			down["shown"] = true
			return {"text": "%s shines a spotlight on %s's face-down card: %s" % [p.name, lit.name, Cards.card_name(down)]}
		"flashbang":
			var shown := []
			for o in others(p.seat):
				var down := _face_down(o)
				if not down.is_empty():
					down["shown"] = true
					shown.append("%s: %s" % [o.name, Cards.card_name(down)])
			return {"text": "%s sets off a flashbang. %s" % [p.name, ", ".join(shown) if not shown.is_empty() else "Nothing to see"]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: take a card on your turn, or spin it" % [p.name, marked.name]}
		"double_down":
			var hit_p: Player = players[target]
			var card := _deal_to(hit_p)
			if card.is_empty():
				return {"text": "%s doubles down on %s, but the deck is empty" % [p.name, hit_p.name]}
			return {"text": "%s doubles down on %s, who gets %s" % [p.name, hit_p.name, Cards.card_name(card)], "reveal": card, "private": false}
		"sticky_fingers":
			for o in players:
				for c in o.hand:
					if c["id"] == choice:
						o.hand.erase(c)
						c["shown"] = true
						p.hand.append(c)
						return {"text": "%s steals %s from %s" % [p.name, Cards.card_name(c), o.name], "reveal": c, "private": false}
		"dumpster_dive":
			var grabbed: Dictionary = discard_pile.pop_back()
			grabbed["shown"] = true
			p.hand.append(grabbed)
			return {"text": "%s digs %s out of the discard pile" % [p.name, Cards.card_name(grabbed)], "reveal": grabbed, "private": false}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true # for the rest of the round: the deck is new each round
					return {"text": "%s paints a card wild" % p.name, "reveal": c, "private": true}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["order"] = _order.duplicate()
	d["shooters"] = _shooters.duplicate(true)
	d["shot_dealer"] = _shot_dealer.duplicate()
	d["hit_this_turn"] = _hit_this_turn
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	_order = d.get("order", [])
	_shooters = d.get("shooters", [])
	_shot_dealer = d.get("shot_dealer", {})
	_hit_this_turn = d.get("hit_this_turn", false)
