extends RefCounted
## Shotgun Rummy: match state and rules. Pure logic, no nodes, so it can be
## tested headless and reused later by AI players or online play.
##
## Table:
##  - 2 to 6 players, seated in order. Play goes to the left (seat + 1).
##  - One player deals each round. The player to the dealer's left goes first.
##    Next round the deal moves one seat to the right, so whoever dealt last
##    round goes first.
##
## Rummy (the classic card game):
##  - Everyone gets 7 playing cards and 2 item cards. The leftover item cards
##    are shuffled into the stock, so drawing from it can give you an item.
##  - Your turn: draw 1 card (stock or top of the discard pile), meld sets
##    (3-4 of a kind) and runs (3+ in a row, same suit), lay off onto any meld on
##    the table, then discard 1 card. You can't discard the card you just took
##    from the discard pile.
##  - Drawing an item from the stock: keep it and draw again, until you get a
##    playing card.
##  - Use as many items as you like, at any point in your turn.
##  - Empty your hand of playing cards to win the round (items don't count). You score the cards left in everyone
##    else's hand: A = 1, 2-10 = face value, J/Q/K = 10. Going out in one turn
##    without having melded before ("rummy") doubles it.
##
## Shotgun:
##  - Everyone has 4 health.
##  - The round winner gets the shotgun: 1 shell, +1 per 10 points scored
##    (max 3). They pick who to shoot with each shell.
##  - 0 health and you're out. Last player standing wins.
##
## Every change is announced through the `event` signal. Event data only holds
## what everyone at the table may see; private info (a peeked card) is only
## returned to the player who caused it.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")

## kind: round_start, turn_start, turn_skipped, draw, meld, layoff, discard,
## item_used, heal, damage, eliminated, stock_reshuffled, round_end, shot,
## gun_empty, match_end.
signal event(kind: String, data: Dictionary)


class Player:
	var seat: int
	var name: String
	var hand: Array = []
	var items: Array = []
	var hp: int = 4
	var max_hp: int = 4
	var alive: bool = true
	var cuffed: bool = false
	var sawed: bool = false
	var has_melded: bool = false
	var score: int = 0
	var rounds_won: int = 0

	func _init(p_seat: int, p_name: String) -> void:
		seat = p_seat
		name = p_name


var options := {
	"hand_size": 7,
	"items_dealt": 2,
	"items_in_stock": true,
	"max_hp": 4,
	"items_per_turn": 0, # 0 = no limit
	"rummy_bonus": true,
	"max_reshuffles": 3,
	"max_shells": 3,
	"points_per_shell": 10,
}
var rng := RandomNumberGenerator.new()
var players: Array = []
var round_num := 0
var dealer := -1
var turn := 0
var phase := "idle" # idle | draw | play | shoot | round_over | match_over
var stock: Array = []
var discard_pile: Array = []
var melds: Array = [] # { id, type, cards, owner }
var burned: Array = [] # cards out of play this round (beer, eliminated hands)
var item_deck: Array = []
var gun = null # { holder, shells, total } while someone holds the shotgun
var last_result: Dictionary = {}
var winner := -1
var drawn_from_discard := ""
var items_used_this_turn := 0

var _melded_at_turn_start := false
var _reshuffles := 0
var _meld_counter := 0


func setup(names: Array, opts: Dictionary = {}, rng_seed: int = -1) -> void:
	options.merge(opts, true)
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	players.clear()
	for i in range(names.size()):
		players.append(Player.new(i, str(names[i])))
	reset_match()


func reset_match() -> void:
	for p in players:
		p.hp = int(options["max_hp"])
		p.max_hp = int(options["max_hp"])
		p.alive = true
		p.cuffed = false
		p.sawed = false
		p.score = 0
		p.rounds_won = 0
		p.hand = []
		p.items = []
	round_num = 0
	dealer = -1
	turn = 0
	phase = "idle"
	stock = []
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	winner = -1


# ---------------------------------------------------------------- queries

func current() -> Player:
	return players[turn]


func alive_players() -> Array:
	var out := []
	for p in players:
		if p.alive:
			out.append(p)
	return out


func alive_count() -> int:
	return alive_players().size()


## Living players other than `seat`.
func others(seat: int) -> Array:
	var out := []
	for p in players:
		if p.alive and p.seat != seat:
			out.append(p)
	return out


## Next living seat to the left (clockwise).
func next_alive(seat: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var s := (seat + k) % n
		if players[s].alive:
			return s
	return seat


## Next living seat to the right.
func prev_alive(seat: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var s := posmod(seat - k, n)
		if players[s].alive:
			return s
	return seat


func top_discard() -> Dictionary:
	return discard_pile.back() if not discard_pile.is_empty() else {}


func is_turn_of(seat: int) -> bool:
	return (phase == "draw" or phase == "play") and turn == seat


func can_discard(seat: int, card_id: String) -> bool:
	return not (card_id == drawn_from_discard and players[seat].hand.size() > 1)


# ---------------------------------------------------------------- rounds

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	if int(options["hand_size"]) * alive_count() + 1 > 52:
		return _fail("Too many players for that hand size.")

	round_num += 1
	# The deal moves one seat to the right each round, so last round's dealer
	# sits to the new dealer's left and goes first.
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)

	for p in players:
		p.hand = []
		p.items = []
		p.has_melded = false
		p.cuffed = false

	var order := _seats_from(next_alive(dealer))
	var deck := _shuffle(Cards.create_deck())
	var items := _shuffle(Items.create_item_deck())
	for i in range(int(options["hand_size"])):
		for s in order:
			players[s].hand.append(deck.pop_back())
	for i in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())

	discard_pile = [deck.pop_back()]
	# the rest of the item cards are shuffled into the stock, so a draw can
	# give you either a playing card or an item
	if options["items_in_stock"]:
		stock = _shuffle(deck + items)
		item_deck = []
	else:
		stock = deck
		item_deck = items
	melds = []
	burned = []
	gun = null
	last_result = {}
	_reshuffles = 0
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn})
	_begin_turn()
	return _ok()


func _seats_from(start: int) -> Array:
	var order := []
	var s := start
	for i in range(players.size()):
		if players[s].alive:
			order.append(s)
		s = (s + 1) % players.size()
	return order


func _begin_turn() -> void:
	phase = "draw"
	drawn_from_discard = ""
	items_used_this_turn = 0
	_melded_at_turn_start = current().has_melded
	_emit("turn_start", {"seat": turn})


func _next_turn() -> void:
	for i in range(players.size()):
		turn = next_alive(turn)
		var p: Player = players[turn]
		if p.cuffed:
			p.cuffed = false
			_emit("turn_skipped", {"seat": turn})
			continue
		break
	_begin_turn()


func _guard(seat: int, need_phase: String = "") -> String:
	if phase != "draw" and phase != "play":
		return "The round is over."
	if turn != seat:
		return "It's not your turn."
	if need_phase != "" and phase != need_phase:
		return "You already drew this turn." if need_phase == "draw" else "Draw a card first."
	return ""


# ---------------------------------------------------------------- rummy

func draw_stock(seat: int) -> Dictionary:
	var err := _guard(seat, "draw")
	if err != "":
		return _fail(err)
	# items you draw are yours to keep, and you draw again until you get a
	# playing card
	var items_drawn := []
	while true:
		if stock.is_empty() and not _reshuffle_stock():
			_end_round(-1, "The deck ran dry.")
			return _ok({"round_over": true, "items_drawn": items_drawn})
		var card: Dictionary = stock.pop_back()
		if card.has("item"):
			current().items.append(card)
			items_drawn.append(card)
			continue
		current().hand.append(card)
		phase = "play"
		# what was drawn stays secret; everyone can see how many items you got
		_emit("draw", {"seat": seat, "source": "stock", "items": items_drawn.size()})
		return _ok({"card": card, "items_drawn": items_drawn})
	return _fail("unreachable")


func draw_discard(seat: int) -> Dictionary:
	var err := _guard(seat, "draw")
	if err != "":
		return _fail(err)
	if discard_pile.is_empty():
		return _fail("The discard pile is empty.")
	var card: Dictionary = discard_pile.pop_back()
	current().hand.append(card)
	drawn_from_discard = card["id"]
	phase = "play"
	_emit("draw", {"seat": seat, "source": "discard", "card": card})
	return _ok({"card": card})


func _reshuffle_stock() -> bool:
	if discard_pile.size() <= 1 or _reshuffles >= int(options["max_reshuffles"]):
		return false
	var top: Dictionary = discard_pile.pop_back()
	stock = _shuffle(discard_pile)
	discard_pile = [top]
	_reshuffles += 1
	_emit("stock_reshuffled", {"size": stock.size()})
	return true


func meld(seat: int, card_ids: Array) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Those cards are not in your hand.")
	var kind: String = Cards.meld_type(cards)
	if kind == "":
		return _fail("Not a set (3-4 of a kind) or a run (3+ in a row, same suit).")
	_remove_cards(p, cards)
	_meld_counter += 1
	var m := {"id": "m%d" % _meld_counter, "type": kind, "cards": Cards.sorted_meld(cards, kind), "owner": seat}
	melds.append(m)
	p.has_melded = true
	_emit("meld", {"seat": seat, "meld": m})
	_check_gone_out(p)
	return _ok({"meld": m})


func lay_off(seat: int, card_ids: Array, meld_id: String) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Those cards are not in your hand.")
	var m := find_meld(meld_id)
	if m.is_empty():
		return _fail("That meld doesn't exist.")
	if not Cards.can_lay_off(m, cards):
		return _fail("Those cards don't fit on that meld.")
	_remove_cards(p, cards)
	m["cards"] = Cards.sorted_meld(m["cards"] + cards, m["type"])
	p.has_melded = true
	_emit("layoff", {"seat": seat, "meld": m, "cards": cards})
	_check_gone_out(p)
	return _ok({"meld": m})


func find_meld(meld_id: String) -> Dictionary:
	for m in melds:
		if m["id"] == meld_id:
			return m
	return {}


func discard(seat: int, card_id: String) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, [card_id])
	if cards.is_empty():
		return _fail("That card is not in your hand.")
	if not can_discard(seat, card_id):
		return _fail("You can't discard the card you just picked up.")
	_remove_cards(p, cards)
	discard_pile.append(cards[0])
	_emit("discard", {"seat": seat, "card": cards[0]})
	if not _check_gone_out(p):
		_next_turn()
	return _ok({"card": cards[0]})


func _cards_from(pool: Array, ids: Array) -> Array:
	var out := []
	var seen := {}
	for id in ids:
		if seen.has(id):
			return []
		seen[id] = true
		var found := false
		for c in pool:
			if c["id"] == id:
				out.append(c)
				found = true
				break
		if not found:
			return []
	return out


func _remove_cards(p: Player, cards: Array) -> void:
	for c in cards:
		p.hand.erase(c)


func _check_gone_out(p: Player) -> bool:
	if not p.hand.is_empty() or phase == "match_over":
		return false
	_end_round(p.seat)
	return true


func _end_round(winner_seat: int, reason: String = "") -> void:
	var hands := []
	for p in players:
		if p.alive:
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(), "points": Cards.hand_points(p.hand)})
	var result := {"round": round_num, "winner": winner_seat, "points": 0, "shells": 0, "rummy": false, "hands": hands, "reason": reason}
	if winner_seat >= 0:
		var pts := 0
		for h in hands:
			if h["seat"] != winner_seat:
				pts += int(h["points"])
		if options["rummy_bonus"] and not _melded_at_turn_start:
			result["rummy"] = true
			pts *= 2
		var w: Player = players[winner_seat]
		w.score += pts
		w.rounds_won += 1
		result["points"] = pts
		result["shells"] = mini(int(options["max_shells"]), 1 + int(pts / float(options["points_per_shell"])))
	last_result = result
	if winner_seat >= 0 and int(result["shells"]) > 0:
		phase = "shoot"
		gun = {"holder": winner_seat, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
	_emit("round_end", result)


# ---------------------------------------------------------------- items

func find_item(seat: int, item_card_id: String) -> Dictionary:
	for c in players[seat].items:
		if c["id"] == item_card_id:
			return c
	return {}


## Seats that `item_id` can be used on (only for items that take a target).
func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	for p in others(seat):
		match item_id:
			"handcuffs":
				if not p.cuffed:
					out.append(p.seat)
			"phone":
				if not p.hand.is_empty():
					out.append(p.seat)
			"adrenaline":
				if not p.items.is_empty():
					out.append(p.seat)
			_:
				out.append(p.seat)
	return out


## Why this item can't be used right now, or "" if it can.
## Leave `target` at -1 to ask "could I use this on anyone?".
func item_blocker(seat: int, item_card_id: String, target: int = -1) -> String:
	var err := _guard(seat)
	if err != "":
		return err
	var card := find_item(seat, item_card_id)
	if card.is_empty():
		return "That item isn't yours."
	var limit := int(options["items_per_turn"])
	if limit > 0 and items_used_this_turn >= limit:
		return "You've already used an item this turn."
	var item_id: String = card["item"]
	var p: Player = players[seat]
	if Items.needs_target(item_id):
		var targets := item_targets(seat, item_id)
		if targets.is_empty():
			return "Nobody to use it on."
		if target >= 0 and not targets.has(target):
			return "You can't use it on them."
		return ""
	match item_id:
		"cigarettes":
			if p.hp >= p.max_hp:
				return "You're already at full health."
		"beer":
			if stock.is_empty() and discard_pile.size() <= 1:
				return "The stock is empty."
		"magnifier":
			if stock.is_empty():
				return "The stock is empty."
		"saw":
			if p.sawed:
				return "The barrel is already sawn off."
	return ""


## Uses an item. The result has "text" (public), plus "reveal" (a card) and
## "private" (true if only this player may see it) when something is revealed.
func use_item(seat: int, item_card_id: String, target: int = -1) -> Dictionary:
	var blocker := item_blocker(seat, item_card_id, target)
	if blocker != "":
		return _fail(blocker)
	var card := find_item(seat, item_card_id)
	var item_id: String = card["item"]
	if Items.needs_target(item_id) and target < 0:
		return _fail("Pick a player to use it on.")
	var p := current()
	p.items.erase(card)
	items_used_this_turn += 1

	var fx := _apply_item(p, item_id, target)
	var public := {"seat": seat, "item": item_id, "target": target, "text": fx["text"]}
	if fx.has("reveal") and not fx.get("private", false):
		public["reveal"] = fx["reveal"]
	_emit("item_used", public)

	# effects that can knock someone out happen after the announcement
	var delta: int = fx.get("hp_delta", 0)
	if delta > 0:
		_heal(p, delta)
	elif delta < 0:
		damage(seat, -delta, "medicine")

	var result := _ok({"item": item_id, "text": fx["text"]})
	if fx.has("reveal"):
		result["reveal"] = fx["reveal"]
		result["private"] = fx.get("private", false)
	return result


func _apply_item(p: Player, item_id: String, target: int) -> Dictionary:
	match item_id:
		"cigarettes":
			return {"text": "%s lights a cigarette. +1 health" % p.name, "hp_delta": 1}
		"beer":
			var burnt := _burn_top()
			return {"text": "%s cracks a beer and burns %s off the stock" % [p.name, card_label(burnt)], "reveal": burnt, "private": false}
		"magnifier":
			return {"text": "%s peeks at the top of the stock" % p.name, "reveal": stock.back(), "private": true}
		"handcuffs":
			var cuffed: Player = players[target]
			cuffed.cuffed = true
			return {"text": "%s handcuffs %s. They skip their next turn" % [p.name, cuffed.name]}
		"saw":
			p.sawed = true
			return {"text": "%s saws off the barrel. Their next shell hits for 2" % p.name}
		"phone":
			var called: Player = players[target]
			var seen: Dictionary = called.hand[rng.randi_range(0, called.hand.size() - 1)]
			return {"text": "%s makes a call about %s's hand" % [p.name, called.name], "reveal": seen, "private": true}
		"adrenaline":
			var victim: Player = players[target]
			var stolen: Dictionary = victim.items[rng.randi_range(0, victim.items.size() - 1)]
			victim.items.erase(stolen)
			p.items.append(stolen)
			return {"text": "%s steals an item from %s" % [p.name, victim.name], "reveal": stolen, "private": true}
		"medicine":
			if rng.randf() < 0.5:
				return {"text": "%s swallows the expired meds. +2 health" % p.name, "hp_delta": 2}
			return {"text": "%s swallows the expired meds. Bad batch. -1 health" % p.name, "hp_delta": -1}
	return {"text": "%s uses %s" % [p.name, item_id]}


## Display name for a playing card or an item card.
static func card_label(card: Dictionary) -> String:
	if card.is_empty():
		return "nothing"
	if card.has("item"):
		return Items.item_name(card)
	return Cards.card_name(card)


func _burn_top() -> Dictionary:
	if stock.is_empty() and not _reshuffle_stock():
		return {}
	var card: Dictionary = stock.pop_back()
	burned.append(card)
	return card


# ---------------------------------------------------------------- health

func _heal(p: Player, amount: int) -> void:
	var before := p.hp
	p.hp = mini(p.max_hp, p.hp + amount)
	_emit("heal", {"seat": p.seat, "amount": p.hp - before, "hp": p.hp})


func damage(seat: int, amount: int, source: String = "") -> void:
	var p: Player = players[seat]
	p.hp = maxi(0, p.hp - amount)
	_emit("damage", {"seat": seat, "amount": amount, "hp": p.hp, "source": source})
	if p.hp <= 0:
		_eliminate(seat)


func _eliminate(seat: int) -> void:
	var p: Player = players[seat]
	if not p.alive:
		return
	p.alive = false
	burned.append_array(p.hand)
	p.hand = []
	p.items = []
	p.cuffed = false
	_emit("eliminated", {"seat": seat})
	if alive_count() <= 1:
		phase = "match_over"
		gun = null
		var left := alive_players()
		winner = left[0].seat if not left.is_empty() else -1
		_emit("match_end", {"winner": winner})
		return
	if (phase == "draw" or phase == "play") and turn == seat:
		_next_turn()


# ---------------------------------------------------------------- shotgun

func shoot(shooter: int, target: int) -> Dictionary:
	if phase != "shoot" or gun == null:
		return _fail("Nobody has the shotgun.")
	if int(gun["holder"]) != shooter:
		return _fail("It's not your gun.")
	if target == shooter:
		return _fail("Don't.")
	if target < 0 or target >= players.size() or not players[target].alive:
		return _fail("Pick a living target.")
	var s: Player = players[shooter]
	var dmg := 2 if s.sawed else 1
	s.sawed = false
	gun["shells"] = int(gun["shells"]) - 1
	_emit("shot", {"shooter": shooter, "target": target, "damage": dmg})
	damage(target, dmg, "shotgun")
	if phase != "match_over" and int(gun["shells"]) <= 0:
		gun = null
		phase = "round_over"
		_emit("gun_empty", {"seat": shooter})
	return _ok({"damage": dmg})


# ---------------------------------------------------------------- helpers

func _shuffle(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


func _emit(kind: String, data: Dictionary) -> void:
	event.emit(kind, data)


func _ok(extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": true, "error": ""}
	d.merge(extra, true)
	return d


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
