extends RefCounted
## AI players for Shotgun Hearts and Spades (bot.gd hands over to this one).
##   easy:   plays a random legal card (and bids roughly in Spades).
##   normal: Hearts: ducks under tricks with points, dumps the Queen of
##           Spades and high hearts when it can't follow. Spades: bids from
##           its high cards and spades, then wins tricks until it has its bid
##           and ducks after.
##   hard:   also saves its trumps for when they matter and plays last in a
##           trick to win it as cheaply as possible.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")

const ITEMS_PER_TURN := {"easy": 1, "normal": 1, "hard": 2}


static func next_action(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var key := "%d-%d-%d" % [game.round_num, seat, me.turns_taken]
	if memory.get("turn", "") != key:
		memory.clear()
		memory["turn"] = key
		memory["items"] = 0
		memory["failed"] = {}
	if game.kind == "spades" and game.bidding:
		return ["bid", [choose_bid(game, seat, level)]]
	var item := _pick_item(game, seat, level, memory)
	if not item.is_empty():
		return ["use_item", item]
	var legal: Array = game.legal_cards(seat)
	if legal.is_empty():
		return []
	return ["play", [choose_card(game, seat, level, legal)["id"]]]


static func choose_bid(game, seat: int, level: String) -> int:
	var hand: Array = game.players[seat].hand
	var est := 0.0
	var spades := 0
	for c in hand:
		var v: int = game.value(c)
		if game.is_wild_card(c):
			est += 1.0
		elif str(c["suit"]) == "S":
			spades += 1
			if v >= 12:
				est += 1.0
		elif v == 14:
			est += 0.9
		elif v == 13:
			est += 0.6
	est += maxf(0.0, spades - 3) * 0.8
	var n := int(round(est))
	if level == "easy":
		n += game.rng.randi_range(-1, 1)
	return clampi(n, 0, hand.size())


## Would `card` win the trick as it stands?
static func _would_win(game, card: Dictionary) -> bool:
	if game.is_wild_card(card):
		for t in game.trick:
			if game.is_wild_card(t["card"]):
				return false
		return true
	if game.trick.is_empty():
		return true # can't tell yet
	var fake: Array = game.trick.duplicate()
	fake.append({"seat": -1, "card": card})
	var saved: Array = game.trick
	game.trick = fake
	var w: int = game.trick_winner()
	game.trick = saved
	return w == -1


static func _trick_points(game) -> int:
	if game.kind != "hearts":
		return 0
	var n := 0
	for t in game.trick:
		n += game.points_of(t["card"])
	return n


static func _last_to_play(game, seat: int) -> bool:
	var left := 0
	var played := {}
	for t in game.trick:
		played[t["seat"]] = true
	for s in game._expected:
		if not played.has(s) and game.players[s].alive and s != seat:
			left += 1
	return left == 0


static func _by_strength(game, cards: Array) -> Array:
	var out: Array = cards.duplicate()
	out.sort_custom(func(a, b): return game._strength(a) < game._strength(b))
	return out


static func choose_card(game, seat: int, level: String, legal: Array) -> Dictionary:
	if level == "easy":
		return legal[game.rng.randi_range(0, legal.size() - 1)]
	var sorted := _by_strength(game, legal)
	var winners := sorted.filter(func(c): return _would_win(game, c))
	var losers := sorted.filter(func(c): return not _would_win(game, c))
	var plain := sorted.filter(func(c): return not game.is_wild_card(c))
	if game.kind == "hearts":
		return _hearts_card(game, seat, level, sorted, winners, losers, plain)
	return _spades_card(game, seat, level, sorted, winners, losers, plain)


static func _hearts_card(game, seat: int, level: String, sorted: Array, winners: Array, losers: Array, plain: Array) -> Dictionary:
	if game.trick.is_empty():
		# lead low, never the Queen of Spades or a trump
		var safe := plain.filter(func(c): return game.points_of(c) != 13)
		return safe[0] if not safe.is_empty() else sorted[0]
	var suit: String = game.led_suit()
	var following: bool = sorted.any(func(c): return str(c["suit"]) == suit and not game.is_wild_card(c))
	if not following:
		# can't follow: get rid of trouble
		for c in sorted:
			if game.points_of(c) == 13:
				return c
		var hearts := plain.filter(func(c): return str(c["suit"]) == "H")
		if not hearts.is_empty():
			return hearts[-1]
		return plain[-1] if not plain.is_empty() else sorted[0]
	# following: duck under the winner, as high as possible
	if not losers.is_empty():
		var low_risk := losers.filter(func(c): return not game.is_wild_card(c))
		if not low_risk.is_empty():
			return low_risk[-1]
	if level == "hard" and _last_to_play(game, seat) and _trick_points(game) == 0:
		var cheap := plain.filter(func(c): return game.points_of(c) == 0)
		if not cheap.is_empty():
			return cheap[-1] # we take it anyway: unload a high card
	return plain[0] if not plain.is_empty() else sorted[0]


static func _spades_card(game, seat: int, level: String, sorted: Array, winners: Array, losers: Array, plain: Array) -> Dictionary:
	var need: bool = int(game.tricks_won.get(seat, 0)) < int(game.bids.get(seat, 0))
	if need:
		if game.trick.is_empty():
			# lead our strongest plain card
			return plain[-1] if not plain.is_empty() else sorted[-1]
		if not winners.is_empty():
			var cheap_plain := winners.filter(func(c): return not game.is_wild_card(c))
			if level == "hard" and not cheap_plain.is_empty():
				return cheap_plain[0] # win as cheaply as possible
			return winners[0]
		return sorted[0]
	# bid made: stay out of trouble
	if game.trick.is_empty():
		return plain[0] if not plain.is_empty() else sorted[0]
	if not losers.is_empty():
		return losers[-1]
	return sorted[0]


# ================================================================ items

static func _pick_item(game, seat: int, level: String, memory: Dictionary) -> Array:
	if int(memory.get("items", 0)) >= int(ITEMS_PER_TURN.get(level, 1)):
		return []
	var me = game.players[seat]
	for card in me.items:
		var id: String = card["id"]
		var item_id: String = card["item"]
		var pick := []
		var targets: Array = game.item_targets(seat, item_id) if Items.needs(item_id) == "player" else []
		var other: int = targets[game.rng.randi_range(0, targets.size() - 1)] if not targets.is_empty() else -1
		match item_id:
			"cigarettes":
				if me.hp < me.max_hp:
					pick = [id, -1, ""]
			"medicine":
				if me.hp >= 2 and me.hp <= me.max_hp - 2:
					pick = [id, -1, ""]
			"saw":
				if not me.sawed and me.hand.size() <= 3:
					pick = [id, -1, ""]
			"spotlight", "flashbang", "adrenaline", "bad_trade":
				if level != "easy" or game.rng.randf() < 0.3:
					pick = [id, other, ""] if Items.needs(item_id) == "player" else [id, -1, ""]
			"revolver", "double_down":
				if other >= 0 and (level != "easy" or game.rng.randf() < 0.3):
					pick = [id, other, ""]
		if pick.is_empty() or (pick[1] == -1 and Items.needs(item_id) == "player"):
			continue
		if memory["failed"].has(var_to_str(["use_item", pick])) or game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
			continue
		memory["items"] = int(memory.get("items", 0)) + 1
		return pick
	return []
