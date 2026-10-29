extends RefCounted
## A simple greedy player. The tests use it to play whole matches; it's also a
## starting point for AI players later.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")


## Plays one full turn for whoever's turn it is.
static func play_turn(game) -> void:
	var seat: int = game.turn
	var me = game.players[seat]

	# use the first item that works, on the weakest valid target
	for card in me.items.duplicate():
		var item_id: String = card["item"]
		var target := -1
		if Items.needs_target(item_id):
			var targets: Array = game.item_targets(seat, item_id)
			if targets.is_empty():
				continue
			target = targets[0]
		if game.item_blocker(seat, card["id"], target) == "":
			game.use_item(seat, card["id"], target)
			break
	if not game.is_turn_of(seat):
		return

	# items drawn from the stock mean drawing again
	while game.is_turn_of(seat) and game.phase == "draw":
		var top: Dictionary = game.top_discard()
		if not top.is_empty() and helps(game, me.hand, top):
			game.draw_discard(seat)
		else:
			game.draw_stock(seat)
	if not game.is_turn_of(seat):
		return

	# meld everything possible, then lay off
	while game.is_turn_of(seat):
		var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank)
		if best["melds"].is_empty():
			break
		if not game.meld(seat, Cards.ids_of(best["melds"][0]))["ok"]:
			break
	var laid := true
	while laid and game.is_turn_of(seat):
		laid = false
		for card in me.hand:
			for m in game.melds:
				if Cards.can_lay_off(m, [card], game.trump_rank):
					laid = game.lay_off(seat, [card["id"]], m["id"])["ok"]
					break
			if laid:
				break
	if game.is_turn_of(seat):
		game.discard(seat, choose_discard(game, seat))


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
static func choose_discard(game, seat: int) -> String:
	var hand: Array = game.players[seat].hand
	var best_id := ""
	var best_score := 1 << 30
	for card in hand:
		if not game.can_discard(seat, card["id"]):
			continue
		var rest: Array = hand.duplicate()
		rest.erase(card)
		var score: int = int(Cards.best_partition(rest, game.trump_rank)["points"]) * 100 - Cards.card_points(card)
		if score < best_score:
			best_score = score
			best_id = card["id"]
	return best_id


## Shoot the living opponent with the least health.
static func choose_target(game, seat: int) -> int:
	var best := -1
	var best_hp := 1 << 30
	for p in game.others(seat):
		if p.hp < best_hp:
			best_hp = p.hp
			best = p.seat
	return best
