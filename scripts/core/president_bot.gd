extends RefCounted
## AI players for Shotgun President (bot.gd hands over to this one).
##   easy:   plays the first set it finds that beats the pile, or passes.
##   normal: leads its lowest cards (as big a set as it has) and beats the
##           pile as cheaply as it can, keeping trumps for when it needs them.
##   hard:   also holds back 2s and trumps until it's close to going out.

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
		# lead: our lowest rank, all of it
		if values.is_empty():
			return Cards.ids_of(wilds.slice(0, mini(4, wilds.size())))
		var v: int = values[0]
		return Cards.ids_of(by[v].slice(0, 4))
	var need: int = top["count"]
	var to_beat: int = top["value"]
	var near_end: bool = hand.size() <= need + 2
	for v in values:
		if v <= to_beat:
			continue
		if level == "hard" and v == 15 and not near_end:
			continue # keep the 2s back
		var naturals: Array = by[v]
		var use_wilds := maxi(0, need - naturals.size())
		if use_wilds > wilds.size():
			continue
		if use_wilds > 0 and level != "easy" and not near_end and v < 13:
			continue # don't spend a trump on a small card
		var pick: Array = naturals.slice(0, mini(need, naturals.size()))
		pick.append_array(wilds.slice(0, use_wilds))
		return Cards.ids_of(pick)
	# only trumps can beat it
	if to_beat < 16 and wilds.size() >= need and (level == "easy" or near_end or to_beat >= 14):
		return Cards.ids_of(wilds.slice(0, need))
	return []


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
