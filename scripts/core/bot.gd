extends RefCounted
## AI players. `next_action` picks one move at a time (use an item, draw,
## meld, lay off, discard, shoot) so the table can play each one out with its
## animation. It returns the same [action, args] that `Session.perform` takes.
##
## Three levels:
##   easy:   draws without much thought, often throws the wrong card, uses
##           items at random.
##   normal: plays the cards well and uses items when they help.
##   hard:   also holds its melds back to go out all at once for Rummy, won't
##           feed the next player cards that fit the table, and aims at
##           whoever is closest to going out.
##
## The AI only knows what its own seat would know (its hand, the table, and
## what it peeked at with the magnifier).

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const BlackjackBot = preload("res://scripts/core/blackjack_bot.gd")
const GoFishBot = preload("res://scripts/core/gofish_bot.gd")
const CheatBot = preload("res://scripts/core/cheat_bot.gd")
const TricksBot = preload("res://scripts/core/tricks_bot.gd")
const SnapBot = preload("res://scripts/core/snap_bot.gd")
const PresidentBot = preload("res://scripts/core/president_bot.gd")
const PokerBot = preload("res://scripts/core/poker_bot.gd")

const LEVELS := ["easy", "normal", "hard"]
const ITEMS_PER_TURN := {"easy": 1, "normal": 2, "hard": 3}


## The next move for `seat`, or [] if it has nothing to do right now.
## `memory` is a Dictionary the caller keeps for this seat between calls.
static func next_action(game, seat: int, level: String = "normal", memory: Dictionary = {}) -> Array:
	if game.phase == "shoot" and game.gun != null and int(game.gun["holder"]) == seat:
		return ["shoot", [choose_target(game, seat, level)]]
	if not game.is_turn_of(seat):
		return []
	match game.kind:
		"blackjack":
			return BlackjackBot.next_action(game, seat, level, memory)
		"gofish":
			return GoFishBot.next_action(game, seat, level, memory)
		"cheat":
			return CheatBot.next_action(game, seat, level, memory)
		"hearts", "spades":
			return TricksBot.next_action(game, seat, level, memory)
		"snap":
			return SnapBot.next_action(game, seat, level, memory)
		"president":
			return PresidentBot.next_action(game, seat, level, memory)
		"poker":
			return PokerBot.next_action(game, seat, level, memory)
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

	if game.phase == "draw":
		return _choose_draw(game, seat, level, memory)

	if game.can_place(seat):
		var meld := _choose_meld(game, seat, level, memory)
		if not meld.is_empty():
			return ["meld", [meld]]
		var lay := _choose_lay_off(game, seat, level, memory)
		if not lay.is_empty():
			return ["lay_off", lay]
	var discard := choose_discard(game, seat, level)
	if discard == "":
		return []
	return ["discard", [discard]]


## Call after a move from `next_action` was refused, so it isn't tried again
## this turn.
static func note_failure(memory: Dictionary, action: Array) -> void:
	if not memory.has("failed"):
		memory["failed"] = {}
	memory["failed"][var_to_str(action)] = true


static func _failed(memory: Dictionary, action: Array) -> bool:
	return memory.get("failed", {}).has(var_to_str(action))


## Plays one full turn at once for whoever's turn it is (used by the tests).
static func play_turn(game, level: String = "normal") -> void:
	var seat: int = game.turn
	var memory := {}
	for i in range(80):
		if not game.is_turn_of(seat):
			return
		var act := next_action(game, seat, level, memory)
		if act.is_empty():
			break
		if not _apply(game, seat, act)["ok"]:
			note_failure(memory, act)
	# fallback so a turn can never hang
	if game.is_turn_of(seat) and game.kind == "blackjack":
		game.stand(seat)
	elif game.is_turn_of(seat) and game.kind != "rummy":
		pass # the other games always have a move
	elif game.is_turn_of(seat):
		if game.phase == "draw":
			game.draw_stock(seat)
		if game.is_turn_of(seat) and game.phase == "play":
			game.discard(seat, choose_discard(game, seat))


static func _apply(game, seat: int, act: Array) -> Dictionary:
	var args: Array = act[1]
	match act[0]:
		"use_item":
			return game.use_item(seat, args[0], args[1], args[2])
		"draw_stock":
			return game.draw_stock(seat)
		"draw_discard":
			return game.draw_discard(seat)
		"meld":
			return game.meld(seat, args[0])
		"lay_off":
			return game.lay_off(seat, args[0], args[1])
		"discard":
			return game.discard(seat, args[0])
		"shoot":
			return game.shoot(seat, args[0])
		"ask", "play", "call", "let_go", "bid", "flip", "snap", "finish", "pass", "raise", "fold":
			return game.perform_action(seat, act[0], args)
		"hit":
			return game.hit(seat)
		"stand":
			return game.stand(seat)
	return {"ok": false}


# ================================================================ cards

static func _choose_draw(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var top: Dictionary = game.top_discard()
	var take_discard := false
	if not top.is_empty() and not _failed(memory, ["draw_discard", []]):
		if level == "easy":
			take_discard = helps(game, me.hand, top) and game.rng.randf() < 0.5
		else:
			take_discard = helps(game, me.hand, top)
			# the magnifier showed a better card on the stock
			if take_discard and memory.get("peeked", false) and not game.stock.is_empty():
				var peek: Dictionary = game.stock.back()
				if not peek.has("item") and helps(game, me.hand, peek) and _value(game, me.hand, peek) > _value(game, me.hand, top):
					take_discard = false
	if take_discard or _failed(memory, ["draw_stock", []]):
		return ["draw_discard", []]
	memory.erase("peeked")
	return ["draw_stock", []]


## How much `card` would cut the hand's deadwood points.
static func _value(game, hand: Array, card: Dictionary) -> int:
	var before: int = Cards.best_partition(hand, game.trump_rank)["points"]
	var after: int = Cards.best_partition(hand + [card], game.trump_rank)["points"]
	return before - after


static func _choose_meld(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank)
	if best["melds"].is_empty():
		return []
	if level == "hard" and _hold_for_rummy(game, seat, best):
		return []
	for m in best["melds"]:
		var ids: Array = Cards.ids_of(m)
		if not _failed(memory, ["meld", [ids]]):
			return ids
	return []


## Hard: keep the melds in hand to go out in one turn for double points,
## while nobody else looks close to going out.
static func _hold_for_rummy(game, seat: int, best: Dictionary) -> bool:
	var me = game.players[seat]
	if me.has_melded or me.ultimatum or not game.options["rummy_bonus"]:
		return false
	if game.go_out_check(seat)["can"]:
		return false
	if me.hand.size() > 10:
		return false
	for p in game.others(seat):
		if p.hand.size() <= 3:
			return false
	return best["deadwood"].size() <= 3


static func _choose_lay_off(game, seat: int, level: String, memory: Dictionary) -> Array:
	var me = game.players[seat]
	if level == "hard" and not me.has_melded and _hold_for_rummy(game, seat, Cards.best_partition(me.hand, game.trump_rank)):
		return []
	# don't break up a meld still in hand to lay off one of its cards
	var keep := {}
	for m in Cards.best_partition(me.hand, game.trump_rank)["melds"]:
		for c in m:
			keep[c["id"]] = true
	for card in me.hand:
		if keep.has(card["id"]):
			continue
		for m in game.melds:
			if Cards.can_lay_off(m, [card], game.trump_rank):
				var act := [[card["id"]], m["id"]]
				if not _failed(memory, ["lay_off", act]):
					return act
	return []


## Would `card` end up in a meld (or fit one on the table)?
static func helps(game, hand: Array, card: Dictionary) -> bool:
	for m in game.melds:
		if Cards.can_lay_off(m, [card], game.trump_rank):
			return true
	var with_card: Array = hand + [card]
	var best: Dictionary = Cards.best_partition(with_card, game.trump_rank)
	for c in best["deadwood"]:
		if c["id"] == card["id"]:
			return false
	return true


## The discard that leaves the least deadwood (highest card on ties).
## Easy sometimes just throws anything; hard avoids feeding the next player.
static func choose_discard(game, seat: int, level: String = "normal") -> String:
	var hand: Array = game.players[seat].hand
	var allowed := []
	for card in hand:
		if game.can_discard(seat, card["id"]):
			allowed.append(card)
	if allowed.is_empty():
		return ""
	if level == "easy" and game.rng.randf() < 0.35:
		return allowed[game.rng.randi_range(0, allowed.size() - 1)]["id"]
	var next_seat: int = game.next_alive(seat)
	var best_id := ""
	var best_score := 1 << 30
	for card in allowed:
		var rest: Array = hand.duplicate()
		rest.erase(card)
		var score: int = int(Cards.best_partition(rest, game.trump_rank)["points"]) * 100 - Cards.card_points(card)
		if level == "hard":
			score += _feeds(game, next_seat, card) * 400
		if score < best_score:
			best_score = score
			best_id = card["id"]
	return best_id


## Hard: would the next player want this card? (It fits the table, or a
## card of theirs we've seen.)
static func _feeds(game, seat: int, card: Dictionary) -> int:
	if seat < 0:
		return 0
	for m in game.melds:
		if Cards.can_lay_off(m, [card], game.trump_rank):
			return 1
	var seen := []
	for c in game.players[seat].hand:
		if not c.get("hidden", false) and (c.get("shown", false) or game.players[seat].exposed):
			seen.append(c)
	if seen.size() >= 2 and helps_hand_only(game, seen, card):
		return 1
	return 0


static func helps_hand_only(game, hand: Array, card: Dictionary) -> bool:
	var best: Dictionary = Cards.best_partition(hand + [card], game.trump_rank)
	for c in best["deadwood"]:
		if c["id"] == card["id"]:
			return false
	return true


# ================================================================ the shotgun

## Who to shoot. Normal finishes off the weakest; hard goes for whoever is
## winning; easy picks anyone.
static func choose_target(game, seat: int, level: String = "normal") -> int:
	var others: Array = game.others(seat)
	if game.gun != null and game.gun.has("targets") and int(game.gun["holder"]) == seat:
		# Blackjack: the dealer may only shoot players who lost
		others = others.filter(func(p): return game.gun["targets"].has(p.seat))
	if others.is_empty():
		return -1
	if level == "easy":
		return others[game.rng.randi_range(0, others.size() - 1)].seat
	var best := -1
	var best_score := -(1 << 30)
	for p in others:
		var score: int = -p.hp * 100
		if level == "hard":
			score += p.rounds_won * 30 + p.score
			if p.hp <= (2 if game.players[seat].sawed else 1):
				score += 1000 # one shot takes them out
		if score > best_score:
			best_score = score
			best = p.seat
	return best


# ================================================================ items

## [item card id, target seat, card choice] for an item worth using now, or [].
static func _pick_item(game, seat: int, level: String, memory: Dictionary) -> Array:
	if int(memory.get("items", 0)) >= int(ITEMS_PER_TURN.get(level, 2)):
		return []
	var me = game.players[seat]
	for card in me.items:
		var item_id: String = card["item"]
		var pick := []
		if level == "easy":
			pick = _random_use(game, seat, card) if game.rng.randf() < 0.3 else []
		else:
			pick = _smart_use(game, seat, card, level)
		if pick.is_empty() or _failed(memory, ["use_item", pick]):
			continue
		if game.item_blocker(seat, pick[0], pick[1], pick[2]) != "":
			continue
		memory["items"] = int(memory.get("items", 0)) + 1
		if item_id == "magnifier":
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


static func _smart_use(game, seat: int, card: Dictionary, level: String) -> Array:
	var me = game.players[seat]
	var id: String = card["id"]
	var item_id: String = card["item"]
	var drawing: bool = game.phase == "draw"
	var deadwood: Array = Cards.best_partition(me.hand, game.trump_rank)["deadwood"]
	var targets: Array = game.item_targets(seat, item_id) if Items.needs(item_id) == "player" else []
	var nearest := _nearest_to_out(game, targets)
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
			if not me.sawed and (me.hand.size() <= 4 or game.go_out_check(seat)["can"]):
				return [id, -1, ""]
		"magnifier":
			if drawing and not game.stock.is_empty():
				return [id, -1, ""]
		"beer":
			# burn the top of the stock when the discard pile has nothing for us
			if drawing and not game.stock.is_empty():
				var top: Dictionary = game.top_discard()
				if top.is_empty() or not helps(game, me.hand, top):
					return [id, -1, ""] if game.rng.randf() < 0.4 else []
		"handcuffs", "double_down", "spotlight":
			if nearest >= 0:
				return [id, nearest, ""]
		"revolver":
			var weakest := _weakest(game, targets)
			if weakest >= 0:
				return [id, nearest if level == "hard" and nearest >= 0 else weakest, ""]
		"garbage_day":
			if nearest >= 0 and game.discard_pile.size() >= 3:
				return [id, nearest, ""]
		"shakedown":
			# it gets them closer to going out, so only on a big hand
			var biggest := _biggest_hand(game, targets)
			if biggest >= 0 and game.players[biggest].hand.size() >= 8:
				return [id, biggest, ""]
		"adrenaline":
			var richest := -1
			for t in targets:
				if richest < 0 or game.players[t].items.size() > game.players[richest].items.size():
					richest = t
			if richest >= 0:
				return [id, richest, ""]
		"switcheroo":
			if nearest >= 0 and game.players[nearest].hand.size() + 1 < me.hand.size():
				return [id, nearest, ""]
		"bad_trade":
			if deadwood.size() >= 4 and nearest >= 0:
				return [id, nearest, ""]
		"chaos":
			if deadwood.size() >= 5:
				return [id, -1, ""]
		"phone":
			if nearest >= 0:
				return [id, nearest, ""]
		"flashbang":
			return [id, -1, ""]
		"dumpster_dive":
			var helpful := 0
			for i in range(mini(3, game.discard_pile.size())):
				if helps(game, me.hand, game.discard_pile[game.discard_pile.size() - 1 - i]):
					helpful += 1
			if helpful >= 2:
				return [id, -1, ""]
		"tarot":
			if game.trump_rank > 0:
				var now: int = Cards.best_partition(me.hand, game.trump_rank)["points"]
				var after: int = Cards.best_partition(me.hand, game.trump_rank % 13 + 1)["points"]
				if after < now:
					return [id, -1, ""]
		"sticky_fingers":
			if drawing:
				return []
			var best_choice := ""
			var best_gain := 0
			for cid in game.item_choices(seat, item_id):
				var c := _table_card(game, cid)
				var gain := _value(game, me.hand, c)
				if gain > best_gain:
					best_gain = gain
					best_choice = cid
			if best_choice != "":
				return [id, -1, best_choice]
		"joker_paint":
			# it only lasts this turn, so only when we can put it straight down
			if drawing or not game.can_place(seat):
				return []
			var now: int = Cards.best_partition(me.hand, game.trump_rank)["points"]
			var best_choice := ""
			var best_after := now
			for cid in game.item_choices(seat, item_id):
				var hand: Array = []
				for c in me.hand:
					var copy: Dictionary = c.duplicate()
					if copy["id"] == cid:
						copy["wild"] = true
					hand.append(copy)
				var after: int = Cards.best_partition(hand, game.trump_rank)["points"]
				if after < best_after:
					best_after = after
					best_choice = cid
			if best_choice != "" and now - best_after >= 5:
				return [id, -1, best_choice]
	return []


static func _table_card(game, card_id: String) -> Dictionary:
	for m in game.melds:
		for c in m["cards"]:
			if c["id"] == card_id:
				var copy: Dictionary = c.duplicate()
				copy.erase("wild")
				return copy
	return {}


## The target with the fewest cards (the closest to going out).
static func _nearest_to_out(game, targets: Array) -> int:
	var best := -1
	for t in targets:
		if best < 0 or game.players[t].hand.size() < game.players[best].hand.size():
			best = t
	return best


static func _biggest_hand(game, targets: Array) -> int:
	var best := -1
	for t in targets:
		if best < 0 or game.players[t].hand.size() > game.players[best].hand.size():
			best = t
	return best


static func _weakest(game, targets: Array) -> int:
	var best := -1
	for t in targets:
		if best < 0 or game.players[t].hp < game.players[best].hp:
			best = t
	return best


## A name for an AI player at the table.
const NAMES := ["DOC", "RUSTY", "MAVIS", "SNAKE", "LEFTY", "PEARL", "BONES", "DUKE", "VERA", "SLIM", "MOE", "GINNY"]


static func level_label(level: String) -> String:
	return {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}.get(level, "")
