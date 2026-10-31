extends RefCounted
## AI players for Shotgun Blackjack (bot.gd hands over to this one).
##   easy:   hits below about 15 and uses items at random.
##   normal: hits below 17 (12 when the dealer shows a weak card); as dealer
##           it hits until it beats the players still in. Uses items when
##           they help.
##   hard:   also counts the cards it has seen to judge the chance of going
##           bust, and uses items to knock out the leader's hand.
## It only knows what its seat would know: its own hand, face-up cards, and
## the top of the stock after using a magnifier.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")

const ITEMS_PER_TURN := {"easy": 1, "normal": 2, "hard": 3}


static func next_action(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var key := "%d-%d-%d" % [game.round_num, seat, me.turns_taken]
	if memory.get("turn", "") != key:
		memory.clear()
		memory["turn"] = key
		memory["items"] = 0
		memory["failed"] = {}
	var item := _pick_item(game, seat, level, memory)
	if not item.is_empty():
		return ["use_item", item]
	return ["hit", []] if should_hit(game, seat, level, memory) else ["stand", []]


## What the AI guesses `seat` holds: their face-up cards plus an average
## card for each face-down one.
static func estimate(game, seat: int) -> int:
	var p = game.players[seat]
	var known := []
	var unknown := 0
	for c in p.hand:
		if c.get("hidden", false) or not (c.get("shown", false) or p.exposed):
			unknown += 1
		else:
			known.append(c)
	return game.total(known, game.trump_rank) + unknown * 7


## The total we need to reach. A player is up against the dealer: if the
## dealer hasn't played, count their face-down card as a 10-ish and assume
## they'll draw to 17. The dealer wants to beat the players still in.
static func to_beat(game, seat: int) -> int:
	if seat != game.dealer:
		var d = game.players[game.dealer]
		if d.bust or not d.alive:
			return 0 # the dealer's out: anything not bust wins
		var est := estimate(game, game.dealer)
		if not d.stood:
			est = maxi(est + 3, 17) if est < 17 else est
		return mini(est, 21)
	var best := 0
	for p in game.others(seat):
		if not p.bust:
			best = maxi(best, mini(estimate(game, p.seat), 21))
	return best


## Is the dealer showing a weak card (2 to 6)? Then a player can sit tight
## and let the dealer go bust.
static func dealer_weak(game, seat: int) -> bool:
	if seat == game.dealer:
		return false
	var d = game.players[game.dealer]
	var up: int = game.showing_total(game.dealer)
	return d.hand.size() == 2 and up >= 2 and up <= 6


static func should_hit(game, seat: int, level: String, memory: Dictionary) -> bool:
	var me = game.players[seat]
	var t: int = game.hand_total(seat)
	if t >= 21:
		return false
	if me.ultimatum and not memory.get("hit", false):
		# the revolver: take a card unless that's sure to bust
		if t < 20:
			memory["hit"] = true
			return true
	var hit := false
	match level:
		"easy":
			hit = t < 13 + game.rng.randi_range(0, 4)
		"normal":
			if dealer_weak(game, seat):
				hit = t < 12
			else:
				hit = t < 17 or (t < to_beat(game, seat) and t < 20)
		_:
			var bust := bust_chance(game, seat)
			var need := to_beat(game, seat)
			if t <= 11:
				hit = true
			elif dealer_weak(game, seat) and t >= 12:
				hit = false # let the dealer bust
			elif t < need:
				hit = bust < 0.85 # behind: worth the risk
			else:
				hit = t < 17 and bust < 0.45
			# the magnifier showed what's coming
			if memory.get("peeked", false) and not game.stock.is_empty():
				var next: Dictionary = game.stock.back()
				if not next.has("item"):
					hit = game.total(me.hand + [next], game.trump_rank) <= 21 and (t < need or t < 17)
	if hit:
		memory["hit"] = true
		memory.erase("peeked")
	return hit


## The chance the next card busts us, from the cards we haven't seen.
static func bust_chance(game, seat: int) -> float:
	var me = game.players[seat]
	var seen := {}
	for p in game.players:
		for c in p.hand:
			if not c.get("hidden", false) and (p.seat == seat or c.get("shown", false) or p.exposed):
				seen[c["id"]] = true
	for c in game.discard_pile + game.burned:
		if not c.get("hidden", false) and c.has("id"):
			seen[c["id"]] = true
	var busts := 0
	var left := 0
	for c in Cards.create_deck():
		if seen.has(c["id"]):
			continue
		left += 1
		if game.total(me.hand + [c], game.trump_rank) > 21:
			busts += 1
	return busts / float(left) if left > 0 else 1.0


# ================================================================ items

static func _pick_item(game, seat: int, level: String, memory: Dictionary) -> Array:
	if int(memory.get("items", 0)) >= int(ITEMS_PER_TURN.get(level, 2)):
		return []
	for card in game.players[seat].items:
		var pick := []
		if level == "easy":
			pick = _random_use(game, seat, card) if game.rng.randf() < 0.3 else []
		else:
			pick = _smart_use(game, seat, card, level, memory)
		if pick.is_empty() or memory["failed"].has(var_to_str(["use_item", pick])):
			continue
		if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
			continue
		memory["items"] = int(memory.get("items", 0)) + 1
		if card["item"] == "magnifier":
			memory["peeked"] = true
		return pick
	return []


static func _random_use(game, seat: int, card: Dictionary) -> Array:
	var item_id: String = card["item"]
	var target := -1
	var choice := ""
	match Items.needs(item_id):
		"player":
			var targets: Array = game.item_targets(seat, item_id)
			if targets.is_empty():
				return []
			target = targets[game.rng.randi_range(0, targets.size() - 1)]
		"meld_card", "hand_card", "table_card":
			var choices: Array = game.item_choices(seat, item_id)
			if choices.is_empty():
				return []
			choice = choices[game.rng.randi_range(0, choices.size() - 1)]
	return [card["id"], target, choice]


static func _smart_use(game, seat: int, card: Dictionary, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var item_id: String = card["item"]
	var t: int = game.hand_total(seat)
	var targets: Array = game.item_targets(seat, item_id) if Items.needs(item_id) == "player" else []
	# the dealer is up against everyone; a player only against the dealer
	var foes: Array = targets if seat == game.dealer else targets.filter(func(x): return x == game.dealer)
	var leader := _leader(game, foes)
	match item_id:
		"cigarettes":
			if me.hp < me.max_hp:
				return [id, -1, ""]
		"blank":
			if me.hp <= 2:
				return [id, -1, ""]
		"medicine":
			if me.hp >= 2 and me.hp <= me.max_hp - 2:
				return [id, -1, ""]
		"saw":
			if not me.sawed and t >= 19:
				return [id, -1, ""]
		"magnifier":
			if not game.stock.is_empty() and t >= 12 and t < 21:
				return [id, -1, ""]
		"beer":
			# burn a card we saw coming that would bust us
			if memory.get("peeked", false) and game.stock.size() > 1:
				var next: Dictionary = game.stock.back()
				if not next.has("item") and game.total(me.hand + [next], game.trump_rank) > 21:
					return [id, -1, ""]
		"double_down":
			# deal one more to a strong hand that has stood: it may bust
			var best := -1
			for s in foes:
				var p = game.players[s]
				if p.stood and estimate(game, s) >= 17 and (best < 0 or estimate(game, s) > estimate(game, best)):
					best = s
			if best >= 0:
				return [id, best, ""]
		"shakedown":
			if leader >= 0 and game.players[leader].stood and estimate(game, leader) >= t:
				return [id, leader, ""]
		"handcuffs":
			# make someone stand on a weak hand
			var weakest := -1
			for s in foes:
				if weakest < 0 or estimate(game, s) < estimate(game, weakest):
					weakest = s
			if weakest >= 0 and estimate(game, weakest) <= 14:
				return [id, weakest, ""]
		"revolver":
			var low := -1
			for s in targets:
				if low < 0 or game.players[s].hp < game.players[low].hp:
					low = s
			if low >= 0:
				return [id, low, ""]
		"switcheroo":
			# take a better hand that has already stood
			for s in targets:
				var p = game.players[s]
				var theirs: int = game.total(p.hand, game.trump_rank) if level == "hard" and p.exposed else estimate(game, s)
				if p.stood and theirs <= 21 and theirs > t + 2:
					return [id, s, ""]
		"bad_trade", "chaos":
			if t <= 13:
				var pick := [id, -1, ""]
				if item_id == "bad_trade":
					if leader < 0:
						return []
					pick[1] = leader
				return pick
		"phone", "spotlight":
			if leader >= 0:
				return [id, leader, ""]
		"flashbang":
			return [id, -1, ""]
		"adrenaline":
			var richest := -1
			for s in targets:
				if richest < 0 or game.players[s].items.size() > game.players[richest].items.size():
					richest = s
			if richest >= 0:
				return [id, richest, ""]
		"dumpster_dive":
			if not game.discard_pile.is_empty():
				var top: Dictionary = game.discard_pile.back()
				var after: int = game.total(me.hand + [top], game.trump_rank)
				if after <= 21 and after > t and after >= 17:
					return [id, -1, ""]
		"sticky_fingers":
			var best_choice := ""
			var best_total := t
			for cid in game.item_choices(seat, item_id):
				var c := _card_in_hands(game, cid)
				var after: int = game.total(me.hand + [c], game.trump_rank)
				if after <= 21 and after > best_total:
					best_total = after
					best_choice = cid
			if best_choice != "" and best_total >= 18:
				return [id, -1, best_choice]
		"joker_paint":
			var best_choice := ""
			var best_total := t
			for cid in game.item_choices(seat, item_id):
				var hand := []
				for c in me.hand:
					var copy: Dictionary = c.duplicate()
					if copy["id"] == cid:
						copy["wild"] = true
					hand.append(copy)
				var after: int = game.total(hand, game.trump_rank)
				if after <= 21 and after > best_total:
					best_total = after
					best_choice = cid
			if best_choice != "" and best_total >= 19:
				return [id, -1, best_choice]
		"tarot":
			if game.trump_rank > 0:
				var after: int = game.total(me.hand, game.trump_rank % 13 + 1)
				if after <= 21 and after > t:
					return [id, -1, ""]
	return []


## The target who looks most likely to win the round.
static func _leader(game, targets: Array) -> int:
	var best := -1
	for s in targets:
		if best < 0 or estimate(game, s) > estimate(game, best):
			best = s
	return best


static func _card_in_hands(game, card_id: String) -> Dictionary:
	for p in game.players:
		for c in p.hand:
			if c["id"] == card_id:
				var copy: Dictionary = c.duplicate()
				copy.erase("wild")
				return copy
	return {}
