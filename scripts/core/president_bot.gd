extends RefCounted
## AI players for Shotgun President (bot.gd hands over to this one).
##   easy:   leads its lowest card and plays the first set that beats the
##           pile, or passes.
##   normal: leads its biggest set (the most cards gone at once) and beats
##           the pile as cheaply as it can: no trumps spent if it can help it,
##           and without breaking up a bigger set.
##   hard:   also plays anything that beats the pile when it's nearly out.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")


static func next_action(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var key := "%d-%d-%d" % [game.round_num, seat, me.turns_taken]
	if memory.get("turn", "") != key:
		memory.clear()
		memory["turn"] = key
		memory["items"] = 0
		memory["failed"] = {}
	if int(memory["items"]) < (1 if level != "hard" else 2):
		for card in me.items:
			var pick := _use(game, seat, card, level)
			if pick.is_empty() or memory["failed"].has(var_to_str(["use_item", pick])):
				continue
			if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
				continue
			memory["items"] = int(memory["items"]) + 1
			return ["use_item", pick]
	var ids := choose_play(game, seat, level)
	if ids.is_empty() or memory["failed"].has(var_to_str(["play", [ids]])):
		return ["pass", []] if game.can_pass(seat) else ["play", [[game.players[seat].hand[0]["id"]]]]
	return ["play", [ids]]


## Every set this player could play: { value: [natural cards] } plus wilds.
static func _groups(game, seat: int) -> Dictionary:
	var by := {}
	for c in game.players[seat].hand:
		if Cards.is_wild(c, game.trump_rank):
			continue
		var v: int = game.card_value(c)
		if not by.has(v):
			by[v] = []
		by[v].append(c)
	return by


static func choose_play(game, seat: int, level: String) -> Array:
	var hand: Array = game.players[seat].hand
	var wilds := hand.filter(func(c): return Cards.is_wild(c, game.trump_rank))
	var by := _groups(game, seat)
	var values := by.keys()
	values.sort()
	var top: Dictionary = game.pile_top
	if top.is_empty():
		if values.is_empty():
			return Cards.ids_of(wilds.slice(0, mini(4, wilds.size())))
		if level == "easy":
			return Cards.ids_of(by[values[0]].slice(0, 4))
		# two sets left and one can't be beaten (2s, or trumps)? Play that
		# first to keep the lead, then go out with the other
		var sets := values.size() + (1 if not wilds.is_empty() else 0)
		if sets == 2:
			if not wilds.is_empty():
				return Cards.ids_of(wilds.slice(0, 4))
			if int(values[-1]) == 15:
				return Cards.ids_of(by[15].slice(0, 4))
		# lead the biggest set we have (the most cards gone at once), lowest first
		var best: int = values[0]
		for v in values:
			if by[v].size() > by[best].size():
				best = v
		return Cards.ids_of(by[best].slice(0, 4))
	var need: int = top["count"]
	var to_beat: int = top["value"]
	var options := [] # [value, naturals used, wilds used, breaks a bigger set]
	for v in values:
		if v <= to_beat:
			continue
		var naturals: Array = by[v]
		var use_wilds := maxi(0, need - naturals.size())
		if use_wilds > wilds.size():
			continue
		options.append([v, naturals.slice(0, mini(need, naturals.size())), use_wilds, naturals.size() > need])
	if options.is_empty():
		# only trumps can beat it
		if to_beat < 16 and wilds.size() >= need:
			return Cards.ids_of(wilds.slice(0, need))
		return []
	if level == "easy":
		var pick: Array = options[0]
		return Cards.ids_of(pick[1] + wilds.slice(0, pick[2]))
	# cheapest first: no trumps spent, an exact set, then the lowest rank
	var best: Array = options[0]
	for o in options:
		var cost: int = o[2] * 100 + (10 if o[3] else 0) + int(o[0])
		var best_cost: int = best[2] * 100 + (10 if best[3] else 0) + int(best[0])
		if level == "hard" and hand.size() <= need * 2 + 1:
			# nearly out: whatever beats it soonest is fine
			cost = int(o[0])
			best_cost = int(best[0])
		if cost < best_cost:
			best = o
	return Cards.ids_of(best[1] + wilds.slice(0, best[2]))


static func _use(game, seat: int, card: Dictionary, level: String) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var targets: Array = game.item_targets(seat, card["item"]) if Items.needs(card["item"]) == "player" else []
	var leader := -1
	for t in targets:
		if leader < 0 or game.players[t].hand.size() < game.players[leader].hand.size():
			leader = t
	match card["item"]:
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
			if not me.sawed and me.hand.size() <= 4:
				return [id, -1, ""]
		"shakedown", "handcuffs", "spotlight", "phone":
			if leader >= 0 and (level != "easy" or game.rng.randf() < 0.3):
				return [id, leader, ""]
		"switcheroo":
			if leader >= 0 and game.players[leader].hand.size() + 3 <= me.hand.size():
				return [id, leader, ""]
		"revolver", "adrenaline":
			if not targets.is_empty() and (level != "easy" or game.rng.randf() < 0.3):
				return [id, targets[game.rng.randi_range(0, targets.size() - 1)], ""]
	return []
