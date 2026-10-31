extends RefCounted
## AI players for Shotgun Snap (bot.gd hands over to this one for their
## turn; main.gd asks `reaction` when a snap is on).
##   easy:   slow to snap, and sometimes snaps when it shouldn't.
##   normal: snaps in about a second.
##   hard:   snaps fast, and uses its items to set up snaps.

const Items = preload("res://scripts/core/items.gd")


static func next_action(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var key := "%d-%d-%d" % [game.round_num, seat, me.turns_taken]
	if memory.get("turn", "") != key:
		memory.clear()
		memory["turn"] = key
		memory["items"] = 0
		memory["failed"] = {}
	if game.last_call:
		return ["finish", []]
	if int(memory["items"]) < (2 if level == "hard" else 1):
		for card in me.items:
			var pick := _use(game, seat, card, level)
			if pick.is_empty() or memory["failed"].has(var_to_str(["use_item", pick])):
				continue
			if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
				continue
			memory["items"] = int(memory["items"]) + 1
			return ["use_item", pick]
	return ["flip", []]


## Seconds this AI takes to snap a match.
static func reaction(game, level: String) -> float:
	match level:
		"easy":
			return game.rng.randf_range(1.1, 2.0)
		"hard":
			return game.rng.randf_range(0.45, 0.8)
	return game.rng.randf_range(0.75, 1.3)


## The chance this AI snaps at a flip that doesn't match.
static func false_snap_chance(level: String) -> float:
	return 0.06 if level == "easy" else 0.0


static func _use(game, seat: int, card: Dictionary, level: String) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var targets: Array = game.item_targets(seat, card["item"]) if Items.needs(card["item"]) == "player" else []
	var leader := -1
	for t in targets:
		if leader < 0 or game.won.get(t, []).size() > game.won.get(leader, []).size():
			leader = t
	match card["item"]:
		"cigarettes":
			if me.hp < me.max_hp:
				return [id, -1, ""]
		"medicine":
			if me.hp >= 2 and me.hp <= me.max_hp - 2:
				return [id, -1, ""]
		"saw":
			if not me.sawed:
				return [id, -1, ""]
		"sticky_fingers", "handcuffs":
			if leader >= 0:
				return [id, leader, ""]
		"revolver", "adrenaline":
			if not targets.is_empty() and (level != "easy" or game.rng.randf() < 0.3):
				return [id, targets[game.rng.randi_range(0, targets.size() - 1)], ""]
		"joker_paint":
			# a wild top card is a snap for whoever's quickest: worth it if we're quick
			if level == "hard" and not game.discard_pile.is_empty():
				return [id, -1, ""]
	return []
