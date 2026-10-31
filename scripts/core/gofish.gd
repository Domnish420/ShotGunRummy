extends "res://scripts/core/game.gd"
## Shotgun Go Fish. Same table as Shotgun Rummy: a rotating dealer, items
## shuffled into the pond, a wild trump rank, health and the shotgun.
##
## - Everyone is dealt 7 cards (5 with 4 or more players) and 2 items. The
##   rest of the cards and items are the pond (the stock).
## - On your turn, ASK another player for a rank you hold. If they have any,
##   they hand over all of them and you go again. If not: GO FISH, draw from
##   the pond. Draw the rank you asked for and you go again; otherwise your
##   turn ends. Draw an item and you keep it and draw again.
## - Four of a kind is a BOOK, laid down in front of you. Trumps are wild for
##   books: 3 of a rank and a trump, or 2 and two trumps, make a book. Nobody
##   can ask for the trump rank, and trumps are never handed over.
## - The round ends when someone has to go fish and the pond is empty, or
##   nobody has any cards left. Most books wins (a tie goes to whoever holds
##   fewer cards, then nobody). The winner gets 1 shell for every book they're
##   ahead of the next player (at least 1, at most 3).

var known := {} # seat -> { rank: true }: ranks everyone heard that player ask for
var _asked_this_turn := false # Revolver: has this player got a card off someone yet?


func _init() -> void:
	kind = "gofish"


## Under the player's name at the table.
func table_note(seat: int) -> String:
	return "%d BOOKS" % books_of(seat).size()


func hand_size_for(n: int) -> int:
	return 7 if n <= 3 else 5


# ---------------------------------------------------------------- books

func books_of(seat: int) -> Array:
	var out := []
	for m in melds:
		if m["owner"] == seat:
			out.append(m)
	return out


## Lays down every book `p` can make. Returns how many.
func _make_books(p: Player) -> int:
	var made := 0
	var progress := true
	while progress:
		progress = false
		var by_rank := {}
		var wilds := []
		for c in p.hand:
			if Cards.is_wild(c, trump_rank):
				wilds.append(c)
			else:
				var r := int(c["rank"])
				if not by_rank.has(r):
					by_rank[r] = []
				by_rank[r].append(c)
		# four trumps make a book of their own
		var natural_trumps := wilds.filter(func(c): return int(c["rank"]) == trump_rank and not c.get("wild", false))
		if natural_trumps.size() >= 4:
			_lay_book(p, natural_trumps.slice(0, 4), trump_rank)
			made += 1
			progress = true
			continue
		for r in by_rank:
			var cards: Array = by_rank[r]
			if cards.size() >= 4 or (cards.size() >= 2 and cards.size() + wilds.size() >= 4):
				var book: Array = cards.slice(0, 4)
				while book.size() < 4:
					book.append(wilds.pop_back())
				_lay_book(p, book, r)
				made += 1
				progress = true
				break
	return made


func _lay_book(p: Player, cards: Array, rank: int) -> void:
	for c in cards:
		p.hand.erase(c)
		c.erase("shown")
	_meld_counter += 1
	var book := {"id": "B%d" % _meld_counter, "type": "book", "cards": cards, "owner": p.seat, "rank": rank}
	melds.append(book)
	_emit("book", {"seat": p.seat, "rank": rank, "cards": cards.duplicate()})


# ---------------------------------------------------------------- the round

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = trump_for_round(round_num) if options["trump_cards"] else 0
	for p in players:
		p.hand = []
		p.items = []
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0
	var order := _seats_from(next_alive(dealer))
	var deck := _shuffle(Cards.create_deck())
	var items := _shuffle(Items.create_item_deck())
	for i in range(hand_size_for(order.size())):
		for s in order:
			players[s].hand.append(deck.pop_back())
	for i in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	stock = _shuffle(deck + items) if options["items_in_stock"] else deck
	item_deck = [] if options["items_in_stock"] else items
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	known = {}
	_temp_wild = []
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	# anyone dealt a book lays it straight down
	for s in order:
		_make_books(players[s])
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	placed_this_turn = false
	_asked_this_turn = false
	var p := current()
	p.turns_taken += 1
	_emit("turn_start", {"seat": turn})
	_check_stuck()


func _can_ask(seat: int) -> bool:
	return not askable_ranks(seat).is_empty() and not ask_targets(seat).is_empty()


func _anyone_can_ask() -> bool:
	for p in players:
		if p.alive and _can_ask(p.seat):
			return true
	return false


## The player whose turn it is can't ask anyone anything (no cards, only
## trumps, or nobody else has cards): they draw from the pond. Out of cards
## they draw and carry on; otherwise the draw ends their turn.
func _check_stuck() -> void:
	if phase != "play" or _can_ask(turn):
		return
	var p := current()
	if stock.is_empty():
		if _anyone_can_ask():
			_next_turn()
		else:
			_finish_round()
		return
	var was_empty := p.hand.is_empty()
	_fish(p)
	_emit("go_fish", {"seat": turn, "rank": 0, "lucky": false, "empty": false, "forced": true})
	_make_books(p)
	if was_empty and _can_ask(turn):
		return
	_next_turn()


func _next_turn() -> void:
	if phase != "play":
		return
	_end_reveals(current())
	for i in range(players.size()):
		turn = next_alive(turn)
		var p: Player = players[turn]
		if p.cuffed:
			p.cuffed = false
			_emit("turn_skipped", {"seat": turn})
			continue
		break
	_begin_turn()


## Draws from the pond for `p`, keeping items on the way. {} if it's empty.
func _fish(p: Player) -> Dictionary:
	while not stock.is_empty():
		var card: Dictionary = stock.pop_back()
		if card.has("item"):
			p.items.append(card)
			_emit("draw", {"seat": p.seat, "source": "stock", "item": true})
			continue
		p.hand.append(card)
		return card
	return {}


## Ranks `seat` may ask for: ones they hold (not wild), never the trump rank.
func askable_ranks(seat: int) -> Array:
	var out := []
	for c in players[seat].hand:
		if Cards.is_wild(c, trump_rank):
			continue
		var r := int(c["rank"])
		if r != trump_rank and not out.has(r):
			out.append(r)
	out.sort()
	return out


func ask_targets(seat: int) -> Array:
	var out := []
	for p in others(seat):
		if not p.hand.is_empty():
			out.append(p.seat)
	return out


func ask(seat: int, target: int, rank: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not ask_targets(seat).has(target):
		return _fail("Ask someone who has cards.")
	if not askable_ranks(seat).has(rank):
		return _fail("You can only ask for a rank you hold (and never the trump).")
	var p := current()
	var them: Player = players[target]
	var got := []
	for c in them.hand.duplicate():
		if int(c["rank"]) == rank and not Cards.is_wild(c, trump_rank):
			them.hand.erase(c)
			c.erase("shown")
			got.append(c)
	_note_known(seat, rank, target)
	if not got.is_empty():
		p.hand.append_array(got)
		_asked_this_turn = true
		p.ultimatum = false
		_emit("ask", {"seat": seat, "target": target, "rank": rank, "count": got.size(), "cards": got})
		_make_books(p)
		_after_move()
		return _ok({"count": got.size(), "again": phase == "play" and turn == seat})
	_emit("ask", {"seat": seat, "target": target, "rank": rank, "count": 0, "cards": []})
	if p.ultimatum and not _asked_this_turn:
		p.ultimatum = false
		if _russian_roulette(p):
			return _ok({"count": 0, "again": false})
	var card := _fish(p)
	if card.is_empty():
		_emit("go_fish", {"seat": seat, "rank": rank, "lucky": false, "empty": true})
		_finish_round()
		return _ok({"count": 0, "again": false, "round_over": true})
	var lucky := int(card["rank"]) == rank and not Cards.is_wild(card, trump_rank)
	_emit("go_fish", {"seat": seat, "rank": rank, "lucky": lucky, "empty": false})
	_make_books(p)
	if lucky:
		_after_move()
	else:
		_next_turn()
	return _ok({"count": 0, "card": card, "lucky": lucky, "again": lucky and phase == "play" and turn == seat})


## After a turn that carries on: can they still ask?
func _after_move() -> void:
	_check_stuck()


## Everyone heard `seat` ask for `rank`: they hold it now. `target` doesn't.
func _note_known(seat: int, rank: int, target: int) -> void:
	if not known.has(seat):
		known[seat] = {}
	known[seat][rank] = true
	if known.has(target):
		known[target].erase(rank)


func _finish_round() -> void:
	var counts := {}
	for p in players:
		if p.alive:
			counts[p.seat] = books_of(p.seat).size()
	var best := -1
	var best_cards := 999
	var second := 0
	var winners := []
	for s in counts:
		var b: int = counts[s]
		var cards: int = players[s].hand.size()
		if b > best or (b == best and cards < best_cards):
			if best >= 0:
				second = maxi(second, best)
			best = b
			best_cards = cards
			winners = [s]
		elif b == best and cards == best_cards:
			winners.append(s)
		else:
			second = maxi(second, b)
	var w: int = winners[0] if winners.size() == 1 and best > 0 else -1
	var hands := []
	for p in players:
		if p.alive:
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": counts[p.seat]})
	var result := {"round": round_num, "winner": w, "points": best, "shells": 0, "rummy": false, "hands": hands, "books": counts,
		"reason": "" if w >= 0 else "A tie for the most books. Nobody wins."}
	if w >= 0:
		players[w].rounds_won += 1
		players[w].score += best
		result["shells"] = clampi(best - second, 1, int(options["max_shells"]))
	last_result = result
	if options["shotgun"] and w >= 0:
		phase = "shoot"
		gun = {"holder": w, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
		gun = null
	_emit("round_end", result)
	_check_normal_match()


# none of Rummy's moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Ask someone for a card. You only go fish when they don't have it.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("There's no discard pile in Go Fish.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("Books go down by themselves when you have four.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Go Fish.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Go Fish.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("There's no discarding in Go Fish.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	if action == "ask" and args.size() == 2 and args[0] is int and args[1] is int:
		return ask(seat, args[0], args[1])
	return _fail("That didn't work.")


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	if item_id == "revolver":
		var out := []
		for p in others(seat):
			if not p.ultimatum:
				out.append(p.seat)
		return out
	return super.item_targets(seat, item_id)


func item_choices(seat: int, item_id: String) -> Array:
	if item_id == "sticky_fingers":
		var out := []
		for m in melds:
			if m["owner"] != seat and players[m["owner"]].alive:
				for c in m["cards"]:
					out.append(c["id"])
		return out
	return super.item_choices(seat, item_id)


func use_item(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> Dictionary:
	var res := super.use_item(seat, item_card_id, target, choice)
	if res["ok"] and phase == "play":
		# cards moved around: lay down any books that formed
		for p in players:
			if p.alive:
				_make_books(p)
		_after_move()
	return res


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"shakedown":
			var mark: Player = players[target]
			var dropped: Dictionary = _random_card(mark.hand)
			mark.hand.erase(dropped)
			dropped.erase("shown")
			stock.insert(rng.randi_range(0, stock.size()), dropped)
			return {"text": "%s shakes down %s, who throws %s back in the pond" % [p.name, mark.name, Cards.card_name(dropped)], "reveal": dropped, "private": false}
		"sticky_fingers":
			for m in melds:
				for c in m["cards"]:
					if c["id"] == choice:
						var owner: Player = players[m["owner"]]
						m["cards"].erase(c)
						c.erase("wild")
						p.hand.append(c)
						for rest in m["cards"]:
							rest.erase("wild")
							owner.hand.append(rest)
						melds.erase(m)
						return {"text": "%s steals %s from %s's book. The rest goes back in their hand" % [p.name, Cards.card_name(c), owner.name], "reveal": c, "private": false}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true # for the rest of the round
					return {"text": "%s paints a card wild" % p.name, "reveal": c, "private": true}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["known"] = known.duplicate(true)
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	known = d.get("known", {})
