extends RefCounted
## AI players for Shotgun Go Fish (bot.gd hands over to this one).
##   easy:   asks for a random rank it holds, from a random player.
##   normal: remembers who asked for what (they must hold it) and asks them;
##           otherwise asks for the rank it holds most of, from the biggest
##           hand. Uses items when they help.
##   hard:   also avoids asking for a rank it just showed everyone it wants
##           when nobody is known to hold it, and uses items harder.

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
	var ask := choose_ask(game, seat, level)
	if ask.is_empty():
		return []
	return ["ask", ask]


## [target, rank] to ask for.
static func choose_ask(game, seat: int, level: String) -> Array:
	var ranks: Array = game.askable_ranks(seat)
	var targets: Array = game.ask_targets(seat)
	if ranks.is_empty() or targets.is_empty():
		return []
	if level == "easy":
		return [targets[game.rng.randi_range(0, targets.size() - 1)], ranks[game.rng.randi_range(0, ranks.size() - 1)]]
	# someone asked for a rank we hold: they have it
	var best_rank := -1
	var best_target := -1
	var best_count := -1
	for t in targets:
		var k: Dictionary = game.known.get(t, {})
		for r in ranks:
			if k.has(r):
				var n := _count(game, seat, r)
				if n > best_count:
					best_count = n
					best_rank = r
					best_target = t
	if best_rank >= 0:
		return [best_target, best_rank]
	# otherwise the rank we're closest to a book on, from the biggest hand
	var counts := {}
	for r in ranks:
		counts[r] = _count(game, seat, r)
	var pick: int = ranks[0]
	for r in ranks:
		var better: bool = counts[r] > counts[pick]
		if level == "hard" and counts[r] == counts[pick]:
			# don't keep advertising the same rank: prefer one not yet asked
			var asked: Dictionary = game.known.get(seat, {})
			better = asked.has(pick) and not asked.has(r)
		if better:
			pick = r
	var biggest: int = targets[0]
	for t in targets:
		if game.players[t].hand.size() > game.players[biggest].hand.size():
			biggest = t
	return [biggest, pick]


static func _count(game, seat: int, rank: int) -> int:
	var n := 0
	for c in game.players[seat].hand:
		if int(c["rank"]) == rank and not Cards.is_wild(c, game.trump_rank):
			n += 1
	return n


## Who's winning: most books, then most cards.
static func _leader(game, targets: Array) -> int:
	var best := -1
	for t in targets:
		if best < 0:
			best = t
			continue
		var bt: int = game.books_of(t).size()
		var bb: int = game.books_of(best).size()
		if bt > bb or (bt == bb and game.players[t].hand.size() > game.players[best].hand.size()):
			best = t
	return best


# ================================================================ items

static func _pick_item(game, seat: int, level: String, memory: Dictionary) -> Array:
	if int(memory.get("items", 0)) >= int(ITEMS_PER_TURN.get(level, 2)):
		return []
	for card in game.players[seat].items:
		var pick := []
		if level == "easy":
			pick = _random_use(game, seat, card) if game.rng.randf() < 0.3 else []
		else:
			pick = _smart_use(game, seat, card)
		if pick.is_empty() or memory["failed"].has(var_to_str(["use_item", pick])):
			continue
		if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
			continue
		memory["items"] = int(memory.get("items", 0)) + 1
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


static func _smart_use(game, seat: int, card: Dictionary) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var item_id: String = card["item"]
	var targets: Array = game.item_targets(seat, item_id) if Items.needs(item_id) == "player" else []
	var leader := _leader(game, targets)
	var my_books: int = game.books_of(seat).size()
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
			if not me.sawed and my_books >= 3:
				return [id, -1, ""]
		"handcuffs", "spotlight", "phone":
			if leader >= 0:
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
		"shakedown":
			if leader >= 0 and game.players[leader].hand.size() >= 4:
				return [id, leader, ""]
		"flashbang":
			return [id, -1, ""]
		"switcheroo":
			# swap a short hand for a long one: more to ask with
			for t in targets:
				if game.players[t].hand.size() >= me.hand.size() + 3:
					return [id, t, ""]
		"sticky_fingers":
			# take a card from a book of a rank we hold 2+ of: then ask for the rest
			for cid in game.item_choices(seat, item_id):
				for m in game.melds:
					for c in m["cards"]:
						if c["id"] == cid and int(m["rank"]) != game.trump_rank and _count(game, seat, int(m["rank"])) >= 2:
							return [id, -1, cid]
		"joker_paint":
			# paint the card that completes a book
			for cid in game.item_choices(seat, item_id):
				for c in me.hand:
					if c["id"] == cid:
						for r in game.askable_ranks(seat):
							if r != int(c["rank"]) and _count(game, seat, r) >= 3:
								return [id, -1, cid]
		"magnifier", "beer":
			pass
	return []
