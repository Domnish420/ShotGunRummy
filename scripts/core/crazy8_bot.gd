extends RefCounted
## AI players for Shotgun Crazy Eights (bot.gd hands over to this one).
##   easy:   plays the first card that fits, often forgets LAST SHOT!, and
##           throws eights away early.
##   normal: keeps its eights for when nothing else fits, calls the suit it
##           holds most of, and always remembers LAST SHOT!
##   hard:   also saves its saloon cards for when the next player is close
##           to going out, and goes out on one for the extra shell.

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
		memory["forgot"] = level == "easy" and game.rng.randf() < 0.35
	if int(memory["items"]) < (1 if level != "hard" else 2):
		for card in me.items:
			var pick := _use(game, seat, card, level)
			if pick.is_empty() or memory["failed"].has(var_to_str(["use_item", pick])):
				continue
			if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
				continue
			memory["items"] = int(memory["items"]) + 1
			return ["use_item", pick]
	var card := choose_card(game, seat, level)
	if card.is_empty():
		if game.can_draw(seat):
			return ["draw", []]
		return ["pass", []]
	if game.can_call(seat) and not memory["forgot"]:
		return ["last_shot", []]
	var suit := best_suit(game, seat, card["id"]) if int(card["rank"]) == 8 else ""
	return ["play", [card["id"], suit]]


## The suit we hold most of (leaving out the card about to be played).
static func best_suit(game, seat: int, leaving: String) -> String:
	var counts := {"S": 0, "H": 0, "D": 0, "C": 0}
	for c in game.players[seat].hand:
		if c["id"] != leaving and int(c["rank"]) != 8:
			counts[c["suit"]] += 1
	var best := "S"
	for s in counts:
		if counts[s] > counts[best]:
			best = s
	return best


static func choose_card(game, seat: int, level: String) -> Dictionary:
	var options: Array = game.playable(seat)
	if options.is_empty():
		return {}
	if level == "easy":
		return options[0]
	var hand: Array = game.players[seat].hand
	var next_seat: int = game._step(seat)
	var threat: bool = game.players[next_seat].hand.size() <= 2
	var best := {}
	var best_score := -999
	for c in options:
		var score := 0
		var r := int(c["rank"])
		if r == 8:
			score -= 20 # the get-out-of-jail card: keep it
		if game.is_action(c) and r != 8:
			if level == "hard" and not threat and hand.size() > 2:
				score -= 4 # save it for when it hurts
			elif threat:
				score += 10
			else:
				score += 2
		# the more of a suit we hold, the more turns it keeps us playing
		for o in hand:
			if o != c and o["suit"] == c["suit"]:
				score += 1
		if hand.size() == 1 and game.is_action(c):
			score += 30 # going out on it loads 2 shells
		if score > best_score:
			best_score = score
			best = c
	return best


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
			if not me.sawed and me.hand.size() <= 2:
				return [id, -1, ""]
		"handcuffs", "double_down", "garbage_day", "shakedown":
			if leader >= 0 and (level != "easy" or game.rng.randf() < 0.3):
				return [id, leader, ""]
		"switcheroo":
			if leader >= 0 and game.players[leader].hand.size() + 3 <= me.hand.size():
				return [id, leader, ""]
		"chaos":
			var left: int = game.prev_alive(seat)
			if game.players[left].hand.size() + 2 <= me.hand.size():
				return [id, -1, ""]
		_:
			if game.rng.randf() < 0.4:
				var any_pick: Array = Items.any_use(game, seat, card)
				if not any_pick.is_empty():
					return any_pick
	return []
