extends RefCounted
## AI players for Shotgun Cheat (bot.gd hands over to this one).
##   easy:   tells the truth when it can, lies with a random card, and calls
##           CHEAT! now and then at random.
##   normal: calls when a claim can't be true (it holds too many of that
##           rank), when someone's about to win, and more often the more
##           cards someone claims. Lies with cards it won't need soon.
##   hard:   also slips an extra lie in with true cards when it's safe, and
##           uses the magnifier before deciding.

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
	if game.pending_win >= 0:
		if not game.can_call(seat) or (level == "easy" and game.rng.randf() < 0.3):
			return ["let_go", []]
		return ["call", []]
	if game.can_call(seat) and not memory.get("decided", false):
		memory["decided"] = true
		if should_call(game, seat, level, memory):
			return ["call", []]
	return ["play", [choose_play(game, seat, level)]]


static func _naturals(game, seat: int, rank: int) -> Array:
	var out := []
	for c in game.players[seat].hand:
		if int(c["rank"]) == rank and not Cards.is_wild(c, game.trump_rank):
			out.append(c)
	return out


static func should_call(game, seat: int, level: String, memory: Dictionary) -> bool:
	var lp: Dictionary = game.last_play
	var rank: int = lp["rank"]
	var count: int = lp["count"]
	var liar = game.players[int(lp["seat"])]
	if memory.get("peek_lie", false):
		return true
	if memory.get("peek_true", false):
		return false
	var mine := _naturals(game, seat, rank).size()
	if level != "easy" and rank != game.trump_rank and mine + count > 4:
		return true # there aren't that many
	var chance := 0.12
	if level != "easy":
		# a wrong call means picking up the pile: only call when it smells
		chance = 0.02 + 0.07 * (count - 1) + 0.05 * mine
		if liar.hand.size() <= 2:
			chance += 0.2
		chance -= 0.01 * game.discard_pile.size()
	return game.rng.randf() < chance


## The ranks this player will be asked for on their next few turns.
static func _upcoming(game, seat: int) -> Array:
	var n: int = game.alive_count()
	var out := []
	for k in range(1, 4):
		out.append(posmod(game.required - 1 + k * n, 13) + 1)
	return out


static func choose_play(game, seat: int, level: String) -> Array:
	var me = game.players[seat]
	var rank: int = game.required
	var need: int = game.min_play(seat)
	var truth := _naturals(game, seat, rank)
	var wilds := []
	for c in me.hand:
		if Cards.is_wild(c, game.trump_rank):
			wilds.append(c)
	var pick := []
	for c in truth:
		if pick.size() < 4:
			pick.append(c)
	if pick.is_empty() and not wilds.is_empty():
		pick.append(wilds[0])
	# lie cards: ones we won't need soon, highest first
	var keep := _upcoming(game, seat)
	var spare := []
	for c in me.hand:
		if pick.has(c) or Cards.is_wild(c, game.trump_rank):
			continue
		spare.append(c)
	if level != "easy":
		spare.sort_custom(func(a, b): return (1 if keep.has(int(a["rank"])) else 0) < (1 if keep.has(int(b["rank"])) else 0))
	else:
		# shuffle with the game's own dice, so a game can be replayed
		for i in range(spare.size() - 1, 0, -1):
			var j: int = game.rng.randi_range(0, i)
			var tmp = spare[i]
			spare[i] = spare[j]
			spare[j] = tmp
	while pick.size() < need and not spare.is_empty():
		pick.append(spare.pop_front())
	for c in me.hand: # still short (Double Down): anything will do
		if pick.size() >= need:
			break
		if not pick.has(c):
			pick.append(c)
	if pick.is_empty() and not spare.is_empty():
		pick.append(spare.pop_front())
	# hard: an extra lie hidden among true cards, while the pile is small
	if level == "hard" and not truth.is_empty() and pick.size() < 4 and game.discard_pile.size() < 6 and not spare.is_empty():
		if not keep.has(int(spare[0]["rank"])) and game.rng.randf() < 0.5:
			pick.append(spare.pop_front())
	if pick.is_empty():
		pick.append(me.hand[0])
	return Cards.ids_of(pick)


# ================================================================ items

static func _fewest(game, targets: Array) -> int:
	var best := -1
	for t in targets:
		if best < 0 or game.players[t].hand.size() < game.players[best].hand.size():
			best = t
	return best


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
			_peek(game, memory)
		return pick
	return []


## The magnifier shows a lie if there is one: remember what it said.
static func _peek(game, memory: Dictionary) -> void:
	var lie := false
	for c in game.discard_pile:
		if game.last_play.get("ids", []).has(c["id"]) and int(c["rank"]) != int(game.last_play["rank"]) and not Cards.is_wild(c, game.trump_rank):
			lie = true
	memory["peek_lie"] = lie
	memory["peek_true"] = not lie


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
	var targets: Array = game.item_targets(seat, item_id) if Items.needs(item_id) == "player" else []
	var leader := _fewest(game, targets)
	match item_id:
		"cigarettes":
			if me.hp < me.max_hp:
				return [id, -1, ""]
		"medicine":
			if me.hp >= 2 and me.hp <= me.max_hp - 2:
				return [id, -1, ""]
		"saw":
			if not me.sawed and me.hand.size() <= 4:
				return [id, -1, ""]
		"magnifier":
			if game.can_call(seat) and not memory.has("peek_lie"):
				return [id, -1, ""]
		"garbage_day":
			if leader >= 0 and game.discard_pile.size() >= 6:
				return [id, leader, ""]
		"shakedown", "handcuffs", "spotlight", "phone":
			if leader >= 0 and game.players[leader].hand.size() <= 6:
				return [id, leader, ""]
		"switcheroo":
			if leader >= 0 and game.players[leader].hand.size() + 3 <= me.hand.size():
				return [id, leader, ""]
		"revolver":
			var low := -1
			for t in targets:
				if low < 0 or game.players[t].hp < game.players[low].hp:
					low = t
			if low >= 0:
				return [id, low, ""]
		"adrenaline":
			var richest := -1
			for t in targets:
				if richest < 0 or game.players[t].items.size() > game.players[richest].items.size():
					richest = t
			if richest >= 0:
				return [id, richest, ""]
		"joker_paint":
			# paint a card we'd otherwise have to lie with
			var keep := _upcoming(game, seat)
			keep.append(game.required)
			for c in me.hand:
				if not Cards.is_wild(c, game.trump_rank) and not keep.has(int(c["rank"])):
					return [id, -1, c["id"]]
		"flashbang":
			return [id, -1, ""]
		"bad_trade", "chaos":
			if level == "hard" and me.hand.size() >= 10:
				var pick := [id, -1, ""]
				if item_id == "bad_trade":
					if leader < 0:
						return []
					pick[1] = leader
				return pick
	return []
