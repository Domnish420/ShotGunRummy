extends RefCounted
## AI players for Shotgun Poker (bot.gd hands over to this one).
##   easy:   calls most things, raises on a pair or better, folds junk now
##           and then at random.
##   normal: judges its hand (its cards before the flop, its best hand and
##           draws after) and raises strong hands, calls fair ones, folds
##           weak ones when there's a raise to answer.
##   hard:   also bluffs a raise now and then, and folds a little more when
##           the shotgun's full and it's behind.

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
	var s := strength(game, seat)
	var facing: bool = game.to_call(seat)
	var can_fold: bool = not game.must_call.has(seat)
	match level:
		"easy":
			if game.can_raise(seat) and s >= 0.6 and game.rng.randf() < 0.5:
				return ["raise", []]
			if facing and can_fold and s < 0.25 and game.rng.randf() < 0.4:
				return ["fold", []]
			return ["call", []]
		_:
			var bluff: bool = level == "hard" and game.rng.randf() < 0.12
			if game.can_raise(seat) and (s >= 0.72 or bluff):
				return ["raise", []]
			var need := 0.35 + 0.08 * (int(game.shells) - 1)
			if level == "hard" and int(game.shells) >= int(game.options["max_shells"]):
				need += 0.06
			if facing and can_fold and s < need:
				return ["fold", []]
			return ["call", []]


## Roughly how good this hand is, 0 to 1.
static func strength(game, seat: int) -> float:
	var hand: Array = game.players[seat].hand
	if hand.size() < 2:
		return 0.3
	if game.board.is_empty():
		var a: int = game._v(hand[0])
		var b: int = game._v(hand[1])
		var s := (maxi(a, b) - 2) / 24.0 + (mini(a, b) - 2) / 48.0
		if a == b:
			s = 0.5 + a / 28.0
		if str(hand[0]["suit"]) == str(hand[1]["suit"]):
			s += 0.06
		if absi(a - b) == 1:
			s += 0.04
		return clampf(s, 0.0, 1.0)
	var r: Array = game.hand_of(seat)
	var cat: int = r[0]
	var base: float = [0.12, 0.42, 0.62, 0.74, 0.82, 0.86, 0.92, 0.97, 1.0][cat]
	# a pair that's only on the board isn't ours
	if cat == 1:
		var board_only: Array = game.best_hand(game.board)
		if game.board.size() >= 5 and board_only[0] == 1 and board_only[1] == r[1]:
			base = 0.2
		else:
			base += (int(r[1]) - 7) * 0.02
	elif cat == 0:
		base += (int(r[1]) - 10) * 0.02
	# draws: four to a flush
	var suits := {}
	for c in hand + game.board:
		suits[c["suit"]] = int(suits.get(c["suit"], 0)) + 1
	for s in suits:
		if int(suits[s]) == 4 and game.board.size() < 5 and cat < 5:
			base += 0.12
	return clampf(base, 0.0, 1.0)


static func _use(game, seat: int, card: Dictionary, level: String) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var targets: Array = game.item_targets(seat, card["item"]) if Items.needs(card["item"]) == "player" else []
	var other: int = targets[game.rng.randi_range(0, targets.size() - 1)] if not targets.is_empty() else -1
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
			if not me.sawed and strength(game, seat) >= 0.8:
				return [id, -1, ""]
		"magnifier", "phone", "spotlight", "flashbang":
			if level != "easy" or game.rng.randf() < 0.3:
				if Items.needs(card["item"]) == "player":
					return [id, other, ""] if other >= 0 else []
				return [id, -1, ""]
		"double_down", "revolver":
			# keep someone in (or punish their fold) when we're strong
			if other >= 0 and strength(game, seat) >= 0.7:
				return [id, other, ""]
		"shakedown", "handcuffs":
			if other >= 0 and (level != "easy" or game.rng.randf() < 0.3):
				return [id, other, ""]
		"switcheroo", "bad_trade":
			if other >= 0 and strength(game, seat) < 0.25 and level == "hard":
				return [id, other, ""]
	return []
