extends RefCounted
## Shotgun Rummy: match state and rules. Pure logic, no nodes, so it can be
## tested headless and reused later by AI players or online play.
##
## Table:
##  - 2 to 6 players, seated in order. Play goes to the left (seat + 1).
##  - One player deals each round. The player to the dealer's left goes first.
##    Next round the deal moves one seat to the right, so whoever dealt last
##    round goes first.
##
## Rummy (the classic card game):
##  - Everyone gets 7 playing cards and 2 item cards. The leftover item cards
##    are shuffled into the stock, so drawing from it can give you an item.
##  - Your turn: draw 1 card (stock or top of the discard pile), meld sets
##    (3-4 of a kind) and runs (3+ in a row, same suit), lay off onto any meld on
##    the table, then discard 1 card. You can't discard the card you just took
##    from the discard pile.
##  - Drawing an item from the stock: keep it and draw again (stock or discard
##    pile, your choice) until you get a playing card.
##  - Use as many items as you like, at any point in your turn.
##  - Empty your hand of playing cards to win the round (items don't count). You score the cards left in everyone
##    else's hand: A = 1, 2-10 = face value, J/Q/K = 10. Going out in one turn
##    without having melded before ("rummy") doubles it.
##
## Trump cards:
##  - Each round one rank is trump: aces in round 1, 2s in round 2 ... kings in
##    round 13, then back to aces. A trump card can stand in for any card, of
##    any suit, in any set or run (in round 1, 2♣ 3♣ A♦ 5♣ is a run).
##  - Swapping: if you hold the real card a trump on the table stands in for,
##    you can put it in that meld and take the trump, but only to use it
##    straight away in a new meld with 2+ cards from your hand.
##  - Nobody can put cards down (meld, lay off, swap) on their first turn of a
##    round.
##  - Trump cards can't be discarded (unless you hold nothing but trumps).
##  - Russian roulette (the Revolver item): 1 live round in 6; a hit costs 2
##    health.
##
## Shotgun:
##  - Everyone has 4 health.
##  - The round winner gets the shotgun: 1 shell, +1 per 10 points scored
##    (max 3). They pick who to shoot with each shell.
##  - 0 health and you're out. Last player standing wins.
##
## Every change is announced through the `event` signal. Event data only holds
## what everyone at the table may see; private info (a peeked card) is only
## returned to the player who caused it.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")

## kind: round_start, trump_changed, roulette, turn_start, turn_skipped, draw, meld, layoff, swap, discard,
## item_used, heal, damage, eliminated, stock_reshuffled, round_end, shot,
## gun_empty, match_end.
signal event(kind: String, data: Dictionary)


class Player:
	var seat: int
	var name: String
	var hand: Array = []
	var items: Array = []
	var hp: int = 4
	var max_hp: int = 4
	var alive: bool = true
	var cuffed: bool = false
	var sawed: bool = false
	var has_melded: bool = false
	var score: int = 0
	var rounds_won: int = 0
	var turns_taken: int = 0 # this round
	var exposed: bool = false # Spotlight: whole hand face up until their turn ends
	var ultimatum: bool = false # Revolver: put cards down next turn or play roulette
	var extra_draws: int = 0 # Double Down: cards still to draw on top of the usual 1

	func _init(p_seat: int, p_name: String) -> void:
		seat = p_seat
		name = p_name


var options := {
	"hand_size": 7,
	"items_dealt": 2,
	"items_in_stock": true,
	"max_hp": 4,
	"items_per_turn": 0, # 0 = no limit
	"rummy_bonus": true,
	"max_reshuffles": 3,
	"max_shells": 3,
	"points_per_shell": 10,
	"trump_cards": true,
	"no_placing_first_turn": true,
	"no_discarding_trumps": true,
	"roulette_chambers": 6,
	"roulette_damage": 2,
}
var rng := RandomNumberGenerator.new()
var players: Array = []
var round_num := 0
var dealer := -1
var turn := 0
var phase := "idle" # idle | draw | play | shoot | round_over | match_over
var stock: Array = []
var discard_pile: Array = []
var melds: Array = [] # { id, type, cards, owner }
var burned: Array = [] # cards out of play this round (beer, eliminated hands)
var item_deck: Array = []
var gun = null # { holder, shells, total } while someone holds the shotgun
var last_result: Dictionary = {}
var winner := -1
var trump_rank := 0 # this round's wild rank, 0 = none
var drawn_from_discard := ""
var items_used_this_turn := 0
var placed_this_turn := false

var _melded_at_turn_start := false
var _reshuffles := 0
var _meld_counter := 0
var _temp_wild: Array = [] # cards painted wild this turn (Joker Paint)


func setup(names: Array, opts: Dictionary = {}, rng_seed: int = -1) -> void:
	options.merge(opts, true)
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	players.clear()
	for i in range(names.size()):
		players.append(Player.new(i, str(names[i])))
	reset_match()


func reset_match() -> void:
	for p in players:
		p.hp = int(options["max_hp"])
		p.max_hp = int(options["max_hp"])
		p.alive = true
		p.cuffed = false
		p.sawed = false
		p.score = 0
		p.rounds_won = 0
		p.hand = []
		p.items = []
	round_num = 0
	dealer = -1
	turn = 0
	phase = "idle"
	stock = []
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	winner = -1


# ---------------------------------------------------------------- queries

func current() -> Player:
	return players[turn]


func alive_players() -> Array:
	var out := []
	for p in players:
		if p.alive:
			out.append(p)
	return out


func alive_count() -> int:
	return alive_players().size()


## Living players other than `seat`.
func others(seat: int) -> Array:
	var out := []
	for p in players:
		if p.alive and p.seat != seat:
			out.append(p)
	return out


## Next living seat to the left (clockwise).
func next_alive(seat: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var s := (seat + k) % n
		if players[s].alive:
			return s
	return seat


## Next living seat to the right.
func prev_alive(seat: int) -> int:
	var n := players.size()
	for k in range(1, n + 1):
		var s := posmod(seat - k, n)
		if players[s].alive:
			return s
	return seat


## Trump rank for a round: 1 (aces) in round 1 up to 13 (kings), then again.
static func trump_for_round(round_number: int) -> int:
	return posmod(round_number - 1, 13) + 1


func is_trump(card: Dictionary) -> bool:
	return not card.has("item") and Cards.is_wild(card, trump_rank)


## Could the current player go out this turn with the cards they hold?
## { "can": bool, "rummy": bool (going out now would score double) }
func go_out_check(seat: int) -> Dictionary:
	if not is_turn_of(seat) or phase != "play" or not can_place(seat):
		return {"can": false, "rummy": false}
	var best: Dictionary = Cards.best_partition(players[seat].hand, trump_rank)
	var table := []
	for m in melds:
		table.append({"type": m["type"], "cards": m["cards"].duplicate()})
	for meld_cards in best["melds"]:
		table.append({"type": Cards.meld_type(meld_cards, trump_rank), "cards": meld_cards.duplicate()})
	# lay off whatever's left, as long as something still fits
	var left: Array = best["deadwood"].duplicate()
	var progress := true
	while progress:
		progress = false
		for c in left:
			for t in table:
				var kind: String = Cards.lay_off_type(t, [c], trump_rank)
				if kind != "":
					t["type"] = kind
					t["cards"].append(c)
					left.erase(c)
					progress = true
					break
			if progress:
				break
	var can := left.is_empty() or (left.size() == 1 and can_discard(seat, left[0]["id"]))
	return {"can": can, "rummy": can and options["rummy_bonus"] and not _melded_at_turn_start}


func top_discard() -> Dictionary:
	return discard_pile.back() if not discard_pile.is_empty() else {}


func is_turn_of(seat: int) -> bool:
	return (phase == "draw" or phase == "play") and turn == seat


func can_discard(seat: int, card_id: String) -> bool:
	return discard_blocker(seat, card_id) == ""


## Why `card_id` can't be discarded, or "" if it can.
func discard_blocker(seat: int, card_id: String) -> String:
	var hand: Array = players[seat].hand
	if card_id == drawn_from_discard and hand.size() > 1:
		return "You can't discard the card you just picked up."
	if trump_rank > 0 and options["no_discarding_trumps"]:
		var card := {}
		for c in hand:
			if c["id"] == card_id:
				card = c
		if not card.is_empty() and Cards.is_wild(card, trump_rank):
			# allowed only when you're holding nothing but trumps
			for c in hand:
				if not Cards.is_wild(c, trump_rank):
					return "You can't discard a trump card. Meld it or lay it off."
	return ""


# ---------------------------------------------------------------- rounds

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	if int(options["hand_size"]) * alive_count() + 1 > 52:
		return _fail("Too many players for that hand size.")

	round_num += 1
	# The deal moves one seat to the right each round, so last round's dealer
	# sits to the new dealer's left and goes first.
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = trump_for_round(round_num) if options["trump_cards"] else 0

	for p in players:
		p.hand = []
		p.items = []
		p.has_melded = false
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0

	var order := _seats_from(next_alive(dealer))
	var deck := _shuffle(Cards.create_deck())
	var items := _shuffle(Items.create_item_deck())
	for i in range(int(options["hand_size"])):
		for s in order:
			players[s].hand.append(deck.pop_back())
	for i in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())

	discard_pile = [deck.pop_back()]
	# the rest of the item cards are shuffled into the stock, so a draw can
	# give you either a playing card or an item
	if options["items_in_stock"]:
		stock = _shuffle(deck + items)
		item_deck = []
	else:
		stock = deck
		item_deck = items
	melds = []
	burned = []
	gun = null
	last_result = {}
	_reshuffles = 0
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_begin_turn()
	return _ok()


func _seats_from(start: int) -> Array:
	var order := []
	var s := start
	for i in range(players.size()):
		if players[s].alive:
			order.append(s)
		s = (s + 1) % players.size()
	return order


func _begin_turn() -> void:
	_clear_temp_wild()
	phase = "draw"
	drawn_from_discard = ""
	items_used_this_turn = 0
	_melded_at_turn_start = current().has_melded
	placed_this_turn = false
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


## Spotlight and Flashbang wear off when the revealed player's turn ends.
func _end_reveals(p: Player) -> void:
	p.exposed = false
	for c in p.hand:
		c.erase("shown")


## Joker Paint wears off at the end of the turn, unless the card was melded.
func _clear_temp_wild() -> void:
	for c in _temp_wild:
		var melded := false
		for m in melds:
			if m["cards"].has(c):
				melded = true
		if not melded:
			c.erase("wild")
	_temp_wild = []


## May `seat` put cards on the table this turn? Not on their first turn.
func can_place(seat: int) -> bool:
	return not (options["no_placing_first_turn"] and players[seat].turns_taken <= 1)


func _place_guard(seat: int) -> String:
	var err := _guard(seat, "play")
	if err != "":
		return err
	if not can_place(seat):
		return "No putting cards down on your first turn. Draw and discard."
	return ""


func _next_turn() -> void:
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


func _guard(seat: int, need_phase: String = "") -> String:
	if phase != "draw" and phase != "play":
		return "The round is over."
	if turn != seat:
		return "It's not your turn."
	if need_phase != "" and phase != need_phase:
		return "You already drew this turn." if need_phase == "draw" else "Draw a card first."
	return ""


# ---------------------------------------------------------------- rummy

func draw_stock(seat: int) -> Dictionary:
	var err := _guard(seat, "draw")
	if err != "":
		return _fail(err)
	if stock.is_empty() and not _reshuffle_stock():
		_end_round(-1, "The deck ran dry.")
		return _ok({"round_over": true})
	var card: Dictionary = stock.pop_back()
	if card.has("item"):
		# keep the item and draw again, from the stock or the discard pile,
		# until you get a playing card
		current().items.append(card)
		_emit("draw", {"seat": seat, "source": "stock", "item": true})
		return _ok({"card": card, "item": true})
	current().hand.append(card)
	var again := _after_draw()
	# which card you drew stays secret
	_emit("draw", {"seat": seat, "source": "stock", "item": false, "again": again})
	return _ok({"card": card, "item": false, "again": again})


## After a playing card is drawn: on to playing, unless Double Down means
## drawing another. Returns true if there's another draw to make.
func _after_draw() -> bool:
	var p := current()
	if p.extra_draws > 0:
		p.extra_draws -= 1
		return true
	phase = "play"
	return false


func draw_discard(seat: int) -> Dictionary:
	var err := _guard(seat, "draw")
	if err != "":
		return _fail(err)
	if discard_pile.is_empty():
		return _fail("The discard pile is empty.")
	var card: Dictionary = discard_pile.pop_back()
	current().hand.append(card)
	drawn_from_discard = card["id"]
	var again := _after_draw()
	_emit("draw", {"seat": seat, "source": "discard", "card": card, "again": again})
	return _ok({"card": card, "again": again})


func _reshuffle_stock() -> bool:
	if discard_pile.size() <= 1 or _reshuffles >= int(options["max_reshuffles"]):
		return false
	var top: Dictionary = discard_pile.pop_back()
	stock = _shuffle(discard_pile)
	discard_pile = [top]
	_reshuffles += 1
	_emit("stock_reshuffled", {"size": stock.size()})
	return true


func meld(seat: int, card_ids: Array) -> Dictionary:
	var err := _place_guard(seat)
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Those cards are not in your hand.")
	var kind: String = Cards.meld_type(cards, trump_rank)
	if kind == "":
		return _fail("Not a set (3-4 of a kind) or a run (3+ in a row, same suit).")
	_remove_cards(p, cards)
	_meld_counter += 1
	var m := {"id": "m%d" % _meld_counter, "type": kind, "cards": Cards.sorted_meld(cards, kind, trump_rank), "owner": seat}
	melds.append(m)
	p.has_melded = true
	placed_this_turn = true
	_emit("meld", {"seat": seat, "meld": m})
	_check_gone_out(p)
	return _ok({"meld": m})


func lay_off(seat: int, card_ids: Array, meld_id: String) -> Dictionary:
	var err := _place_guard(seat)
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Those cards are not in your hand.")
	var m := find_meld(meld_id)
	if m.is_empty():
		return _fail("That meld doesn't exist.")
	var kind: String = Cards.lay_off_type(m, cards, trump_rank)
	if kind == "":
		return _fail("Those cards don't fit on that meld.")
	_remove_cards(p, cards)
	m["type"] = kind
	m["cards"] = Cards.sorted_meld(m["cards"] + cards, kind, trump_rank)
	p.has_melded = true
	placed_this_turn = true
	_emit("layoff", {"seat": seat, "meld": m, "cards": cards})
	_check_gone_out(p)
	return _ok({"meld": m})


## Finds a trump swap in `card_ids` (cards selected from the hand) for the
## table meld `meld_id`: one card replaces a trump in that meld, and the rest
## make a new meld with the trump. Returns { natural, trump, rest } as ids,
## or {} if there's no swap.
func find_swap(seat: int, meld_id: String, card_ids: Array) -> Dictionary:
	if trump_rank <= 0 or card_ids.size() < 3:
		return {}
	var m := find_meld(meld_id)
	var cards := _cards_from(players[seat].hand, card_ids)
	if m.is_empty() or cards.is_empty():
		return {}
	for t in m["cards"]:
		if not Cards.is_wild(t, trump_rank):
			continue
		for natural in cards:
			if Cards.is_wild(natural, trump_rank):
				continue
			var rest := cards.duplicate()
			rest.erase(natural)
			if _swap_meld_type(m, t, natural) != "" and Cards.meld_type(rest + [t], trump_rank) != "":
				return {"natural": natural["id"], "trump": t["id"], "rest": Cards.ids_of(rest)}
	return {}


## The table meld's type with `trump` replaced by `natural`, or "".
func _swap_meld_type(m: Dictionary, trump: Dictionary, natural: Dictionary) -> String:
	var swapped: Array = m["cards"].duplicate()
	swapped.erase(trump)
	swapped.append(natural)
	var kind: String = Cards.meld_type(swapped, trump_rank)
	var was: String = m["type"]
	if kind == "":
		return ""
	if was == "any":
		return kind
	if kind == "any" or kind == was:
		return was
	return ""


## Swaps `natural_id` from your hand into `meld_id` for its trump `trump_id`,
## then melds that trump with `rest_ids` from your hand, all in one go.
func swap_trump(seat: int, meld_id: String, natural_id: String, trump_id: String, rest_ids: Array) -> Dictionary:
	var err := _place_guard(seat)
	if err != "":
		return _fail(err)
	var p := current()
	var m := find_meld(meld_id)
	if m.is_empty():
		return _fail("That meld doesn't exist.")
	var naturals := _cards_from(p.hand, [natural_id])
	var rest := _cards_from(p.hand, rest_ids)
	if naturals.is_empty() or rest.size() < 2 or rest_ids.has(natural_id):
		return _fail("Pick the card to swap in plus 2 or more cards to meld with the trump.")
	var natural: Dictionary = naturals[0]
	var trump := {}
	for c in m["cards"]:
		if c["id"] == trump_id and Cards.is_wild(c, trump_rank):
			trump = c
	if trump.is_empty() or Cards.is_wild(natural, trump_rank):
		return _fail("There's no trump to swap there.")
	var table_kind := _swap_meld_type(m, trump, natural)
	if table_kind == "":
		return _fail("%s doesn't take the trump's place in that meld." % Cards.card_name(natural))
	var new_kind: String = Cards.meld_type(rest + [trump], trump_rank)
	if new_kind == "":
		return _fail("You have to meld the trump straight away with 2 or more of your cards.")
	_remove_cards(p, naturals + rest)
	var swapped: Array = m["cards"].duplicate()
	swapped.erase(trump)
	swapped.append(natural)
	m["type"] = table_kind
	m["cards"] = Cards.sorted_meld(swapped, table_kind, trump_rank)
	_meld_counter += 1
	var fresh := {"id": "m%d" % _meld_counter, "type": new_kind, "cards": Cards.sorted_meld(rest + [trump], new_kind, trump_rank), "owner": seat}
	melds.append(fresh)
	p.has_melded = true
	placed_this_turn = true
	_emit("swap", {"seat": seat, "meld": m, "natural": natural, "trump": trump, "new_meld": fresh})
	_check_gone_out(p)
	return _ok({"meld": fresh})


func find_meld(meld_id: String) -> Dictionary:
	for m in melds:
		if m["id"] == meld_id:
			return m
	return {}


func discard(seat: int, card_id: String) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, [card_id])
	if cards.is_empty():
		return _fail("That card is not in your hand.")
	var blocked := discard_blocker(seat, card_id)
	if blocked != "":
		return _fail(blocked)
	_remove_cards(p, cards)
	discard_pile.append(cards[0])
	_emit("discard", {"seat": seat, "card": cards[0]})
	if _check_gone_out(p):
		return _ok({"card": cards[0]})
	if p.ultimatum and can_place(seat):
		p.ultimatum = false
		if not placed_this_turn and _russian_roulette(p):
			return _ok({"card": cards[0]}) # they didn't survive it
	_next_turn()
	return _ok({"card": cards[0]})


## Revolver: one live round in six. Returns true if the player was knocked
## out (their turn has already moved on).
func _russian_roulette(p: Player) -> bool:
	var chambers := int(options["roulette_chambers"])
	var hit := rng.randi_range(1, chambers) == 1
	var dmg := int(options["roulette_damage"]) if hit else 0
	_emit("roulette", {"seat": p.seat, "hit": hit, "damage": dmg})
	if hit:
		damage(p.seat, dmg, "roulette")
	return not p.alive or phase == "match_over"


func _cards_from(pool: Array, ids: Array) -> Array:
	var out := []
	var seen := {}
	for id in ids:
		if seen.has(id):
			return []
		seen[id] = true
		var found := false
		for c in pool:
			if c["id"] == id:
				out.append(c)
				found = true
				break
		if not found:
			return []
	return out


func _remove_cards(p: Player, cards: Array) -> void:
	for c in cards:
		p.hand.erase(c)


func _check_gone_out(p: Player) -> bool:
	if not p.hand.is_empty() or phase == "match_over":
		return false
	_end_round(p.seat)
	return true


func _end_round(winner_seat: int, reason: String = "") -> void:
	var hands := []
	for p in players:
		if p.alive:
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(), "points": Cards.hand_points(p.hand)})
	var result := {"round": round_num, "winner": winner_seat, "points": 0, "shells": 0, "rummy": false, "hands": hands, "reason": reason}
	if winner_seat >= 0:
		var pts := 0
		for h in hands:
			if h["seat"] != winner_seat:
				pts += int(h["points"])
		if options["rummy_bonus"] and not _melded_at_turn_start:
			result["rummy"] = true
			pts *= 2
		var w: Player = players[winner_seat]
		w.score += pts
		w.rounds_won += 1
		result["points"] = pts
		result["shells"] = mini(int(options["max_shells"]), 1 + int(pts / float(options["points_per_shell"])))
	last_result = result
	if winner_seat >= 0 and int(result["shells"]) > 0:
		phase = "shoot"
		gun = {"holder": winner_seat, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
	_emit("round_end", result)


# ---------------------------------------------------------------- items

func find_item(seat: int, item_card_id: String) -> Dictionary:
	for c in players[seat].items:
		if c["id"] == item_card_id:
			return c
	return {}


## Seats that `item_id` can be used on (only for items that take a target).
func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	for p in others(seat):
		match item_id:
			"handcuffs":
				if not p.cuffed:
					out.append(p.seat)
			"phone", "switcheroo", "bad_trade":
				if not p.hand.is_empty():
					out.append(p.seat)
			"adrenaline":
				if not p.items.is_empty():
					out.append(p.seat)
			"shakedown":
				# never strip someone's last card: that would hand them the round
				if p.hand.size() >= 2:
					out.append(p.seat)
			"spotlight":
				if not p.exposed and not p.hand.is_empty():
					out.append(p.seat)
			"revolver":
				if not p.ultimatum:
					out.append(p.seat)
			"double_down":
				if p.extra_draws == 0:
					out.append(p.seat)
			_:
				out.append(p.seat)
	return out


## Card ids that `item_id` can be used on, for items that need a card picked:
## a meld card (Sticky Fingers) or a card in your hand (Joker Paint).
func item_choices(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"sticky_fingers":
			for m in melds:
				for c in m["cards"]:
					if _can_steal(m, c):
						out.append(c["id"])
		"joker_paint":
			for c in players[seat].hand:
				if not Cards.is_wild(c, trump_rank):
					out.append(c["id"])
	return out


## A card can be stolen from a meld if what's left is still a meld, or is
## down to 2 cards (which then go to the discard pile).
func _can_steal(m: Dictionary, card: Dictionary) -> bool:
	var rest: Array = m["cards"].duplicate()
	rest.erase(card)
	return rest.size() <= 2 or Cards.meld_type(rest, trump_rank) != ""


func _meld_with_card(card_id: String) -> Dictionary:
	for m in melds:
		for c in m["cards"]:
			if c["id"] == card_id:
				return m
	return {}


## Why this item can't be used right now, or "" if it can.
## Leave `target` / `choice` empty to ask "could I use this at all?".
func item_blocker(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> String:
	var err := _guard(seat)
	if err != "":
		return err
	var card := find_item(seat, item_card_id)
	if card.is_empty():
		return "That item isn't yours."
	var limit := int(options["items_per_turn"])
	if limit > 0 and items_used_this_turn >= limit:
		return "You've already used an item this turn."
	var item_id: String = card["item"]
	var p: Player = players[seat]
	match Items.needs(item_id):
		"player":
			var targets := item_targets(seat, item_id)
			if targets.is_empty():
				return "Nobody to use it on."
			if target >= 0 and not targets.has(target):
				return "You can't use it on them."
		"meld_card", "hand_card":
			var choices := item_choices(seat, item_id)
			if choices.is_empty():
				return "Nothing to use it on." if item_id == "joker_paint" else "There's nothing on the table you can take."
			if choice != "" and not choices.has(choice):
				return "You can't use it on that card."
	match item_id:
		"cigarettes":
			if p.hp >= p.max_hp:
				return "You're already at full health."
		"beer":
			if stock.is_empty() and discard_pile.size() <= 1:
				return "The stock is empty."
		"magnifier":
			if stock.is_empty():
				return "The stock is empty."
		"saw":
			if p.sawed:
				return "The barrel is already sawn off."
		"dumpster_dive", "garbage_day":
			if discard_pile.is_empty():
				return "The discard pile is empty."
		"bad_trade":
			if p.hand.is_empty():
				return "You have no cards to trade."
		"tarot":
			if trump_rank <= 0:
				return "There's no trump this round."
		"flashbang":
			var anyone := false
			for o in others(seat):
				if not o.hand.is_empty():
					anyone = true
			if not anyone:
				return "Nobody has any cards to show."
	return ""


## Uses an item. The result has "text" (public), plus "reveal" (a card) and
## "private" (true if only this player may see it) when something is revealed.
func use_item(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> Dictionary:
	var blocker := item_blocker(seat, item_card_id, target, choice)
	if blocker != "":
		return _fail(blocker)
	var card := find_item(seat, item_card_id)
	var item_id: String = card["item"]
	var needs: String = Items.needs(item_id)
	if needs == "player" and target < 0:
		return _fail("Pick a player to use it on.")
	if (needs == "meld_card" or needs == "hand_card") and choice == "":
		return _fail("Pick a card to use it on.")
	var p := current()
	p.items.erase(card)
	items_used_this_turn += 1

	var fx := _apply_item(p, item_id, target, choice)
	var public := {"seat": seat, "item": item_id, "target": target, "text": fx["text"]}
	if fx.has("reveal") and not fx.get("private", false):
		public["reveal"] = fx["reveal"]
	_emit("item_used", public)

	# effects that can knock someone out happen after the announcement
	var delta: int = fx.get("hp_delta", 0)
	if delta > 0:
		_heal(p, delta)
	elif delta < 0:
		damage(seat, -delta, "medicine")

	var result := _ok({"item": item_id, "text": fx["text"]})
	if fx.has("reveal"):
		result["reveal"] = fx["reveal"]
		result["private"] = fx.get("private", false)
	return result


func _random_card(cards: Array) -> Dictionary:
	return cards[rng.randi_range(0, cards.size() - 1)]


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"cigarettes":
			return {"text": "%s lights a cigarette. +1 health" % p.name, "hp_delta": 1}
		"beer":
			var burnt := _burn_top()
			return {"text": "%s cracks a beer and burns %s off the stock" % [p.name, card_label(burnt)], "reveal": burnt, "private": false}
		"magnifier":
			return {"text": "%s peeks at the top of the stock" % p.name, "reveal": stock.back(), "private": true}
		"handcuffs":
			var cuffed: Player = players[target]
			cuffed.cuffed = true
			return {"text": "%s handcuffs %s. They skip their next turn" % [p.name, cuffed.name]}
		"saw":
			p.sawed = true
			return {"text": "%s saws off the barrel. Their next shell hits for 2" % p.name}
		"phone":
			var called: Player = players[target]
			return {"text": "%s makes a call about %s's hand" % [p.name, called.name], "reveal": _random_card(called.hand), "private": true}
		"adrenaline":
			var victim: Player = players[target]
			var stolen: Dictionary = _random_card(victim.items)
			victim.items.erase(stolen)
			p.items.append(stolen)
			return {"text": "%s steals an item from %s" % [p.name, victim.name], "reveal": stolen, "private": true}
		"medicine":
			if rng.randf() < 0.5:
				return {"text": "%s swallows the expired meds. +2 health" % p.name, "hp_delta": 2}
			return {"text": "%s swallows the expired meds. Bad batch. -1 health" % p.name, "hp_delta": -1}
		"shakedown":
			var mark: Player = players[target]
			# a random card that isn't a trump, if they have one
			var pool := []
			for c in mark.hand:
				if not Cards.is_wild(c, trump_rank):
					pool.append(c)
			if pool.is_empty():
				pool = mark.hand
			var dropped: Dictionary = _random_card(pool)
			mark.hand.erase(dropped)
			discard_pile.append(dropped)
			return {"text": "%s shakes down %s, who drops %s on the discard pile" % [p.name, mark.name, Cards.card_name(dropped)], "reveal": dropped, "private": false}
		"switcheroo":
			var other: Player = players[target]
			var mine := p.hand
			p.hand = other.hand
			other.hand = mine
			drawn_from_discard = ""
			return {"text": "%s swaps hands with %s" % [p.name, other.name]}
		"bad_trade":
			var partner: Player = players[target]
			var n := mini(2, mini(p.hand.size(), partner.hand.size()))
			var give := []
			var take := []
			var mine_left: Array = p.hand.duplicate()
			var theirs_left: Array = partner.hand.duplicate()
			for i in range(n):
				var g: Dictionary = _random_card(mine_left)
				mine_left.erase(g)
				give.append(g)
				var t: Dictionary = _random_card(theirs_left)
				theirs_left.erase(t)
				take.append(t)
			for c in give:
				p.hand.erase(c)
				partner.hand.append(c)
			for c in take:
				partner.hand.erase(c)
				p.hand.append(c)
			if give.any(func(c): return c["id"] == drawn_from_discard):
				drawn_from_discard = ""
			return {"text": "%s trades %d random card%s with %s" % [p.name, n, "" if n == 1 else "s", partner.name]}
		"chaos":
			var passing := []
			for q in alive_players():
				passing.append(_random_card(q.hand) if not q.hand.is_empty() else {})
			var alive := alive_players()
			for i in range(alive.size()):
				var c: Dictionary = passing[i]
				if c.is_empty():
					continue
				var from_p: Player = alive[i]
				var to_p: Player = players[next_alive(from_p.seat)]
				from_p.hand.erase(c)
				to_p.hand.append(c)
				if c["id"] == drawn_from_discard:
					drawn_from_discard = ""
			return {"text": "%s causes chaos: everyone passes a random card to their left" % p.name}
		"sticky_fingers":
			var m := _meld_with_card(choice)
			var taken := {}
			for c in m["cards"]:
				if c["id"] == choice:
					taken = c
			m["cards"].erase(taken)
			taken.erase("wild")
			p.hand.append(taken)
			var owner_name: String = players[m["owner"]].name
			var text := "%s steals %s from %s's meld" % [p.name, Cards.card_name(taken), owner_name]
			if m["cards"].size() <= 2:
				for c in m["cards"]:
					c.erase("wild")
					discard_pile.append(c)
				melds.erase(m)
				text += ". The meld falls apart onto the discard pile"
			else:
				m["type"] = Cards.meld_type(m["cards"], trump_rank)
				m["cards"] = Cards.sorted_meld(m["cards"], m["type"], trump_rank)
			return {"text": text, "reveal": taken, "private": false}
		"dumpster_dive":
			var n := mini(3, discard_pile.size())
			var grabbed := []
			for i in range(n):
				grabbed.append(discard_pile.pop_back())
			p.hand.append_array(grabbed)
			return {"text": "%s digs %s out of the discard pile" % [p.name, Cards.cards_text(grabbed)]}
		"garbage_day":
			var dumped_on: Player = players[target]
			var n := discard_pile.size()
			dumped_on.hand.append_array(discard_pile)
			discard_pile = []
			return {"text": "%s makes %s take the whole discard pile (%d card%s)" % [p.name, dumped_on.name, n, "" if n == 1 else "s"]}
		"tarot":
			# melds on the table keep their trumps wild
			for m in melds:
				for c in m["cards"]:
					if Cards.is_wild(c, trump_rank):
						c["wild"] = true
			var old := trump_rank
			trump_rank = trump_rank % 13 + 1
			_emit("trump_changed", {"from": old, "to": trump_rank})
			return {"text": "%s turns a tarot card: trumps are now %s" % [p.name, Cards.rank_label(trump_rank)]}
		"spotlight":
			var lit: Player = players[target]
			lit.exposed = true
			return {"text": "%s shines a spotlight on %s's hand: %s" % [p.name, lit.name, Cards.cards_text(lit.hand)]}
		"flashbang":
			var shown := []
			for o in others(p.seat):
				var pool: Array = o.hand.duplicate()
				for i in range(mini(2, pool.size())):
					var c: Dictionary = _random_card(pool)
					pool.erase(c)
					c["shown"] = true
					shown.append("%s: %s" % [o.name, Cards.card_name(c)])
			return {"text": "%s sets off a flashbang. %s" % [p.name, ", ".join(shown)]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: put cards down next turn, or spin it" % [p.name, marked.name]}
		"double_down":
			var loaded: Player = players[target]
			loaded.extra_draws = 1
			return {"text": "%s doubles down on %s: they draw 2 cards next turn" % [p.name, loaded.name]}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true
					_temp_wild.append(c)
					return {"text": "%s paints a card wild for this turn" % p.name, "reveal": c, "private": true}
	return {"text": "%s uses %s" % [p.name, item_id]}


## Display name for a playing card or an item card.
static func card_label(card: Dictionary) -> String:
	if card.is_empty():
		return "nothing"
	if card.has("item"):
		return Items.item_name(card)
	return Cards.card_name(card)


func _burn_top() -> Dictionary:
	if stock.is_empty() and not _reshuffle_stock():
		return {}
	var card: Dictionary = stock.pop_back()
	burned.append(card)
	return card


# ---------------------------------------------------------------- health

func _heal(p: Player, amount: int) -> void:
	var before := p.hp
	p.hp = mini(p.max_hp, p.hp + amount)
	_emit("heal", {"seat": p.seat, "amount": p.hp - before, "hp": p.hp})


func damage(seat: int, amount: int, source: String = "") -> void:
	var p: Player = players[seat]
	p.hp = maxi(0, p.hp - amount)
	_emit("damage", {"seat": seat, "amount": amount, "hp": p.hp, "source": source})
	if p.hp <= 0:
		_eliminate(seat)


func _eliminate(seat: int) -> void:
	var p: Player = players[seat]
	if not p.alive:
		return
	p.alive = false
	burned.append_array(p.hand)
	p.hand = []
	p.items = []
	p.cuffed = false
	_emit("eliminated", {"seat": seat})
	if alive_count() <= 1:
		phase = "match_over"
		gun = null
		var left := alive_players()
		winner = left[0].seat if not left.is_empty() else -1
		_emit("match_end", {"winner": winner})
		return
	if (phase == "draw" or phase == "play") and turn == seat:
		_next_turn()


# ---------------------------------------------------------------- shotgun

func shoot(shooter: int, target: int) -> Dictionary:
	if phase != "shoot" or gun == null:
		return _fail("Nobody has the shotgun.")
	if int(gun["holder"]) != shooter:
		return _fail("It's not your gun.")
	if target == shooter:
		return _fail("Don't.")
	if target < 0 or target >= players.size() or not players[target].alive:
		return _fail("Pick a living target.")
	var s: Player = players[shooter]
	var dmg := 2 if s.sawed else 1
	s.sawed = false
	gun["shells"] = int(gun["shells"]) - 1
	_emit("shot", {"shooter": shooter, "target": target, "damage": dmg})
	damage(target, dmg, "shotgun")
	if phase != "match_over" and int(gun["shells"]) <= 0:
		gun = null
		phase = "round_over"
		_emit("gun_empty", {"seat": shooter})
	return _ok({"damage": dmg})


# ---------------------------------------------------------------- network

## Everything `view_seat` is allowed to know, as plain data that can be sent
## over the network. Other players' hands and items, and the stock, are
## replaced by face-down placeholders so only their counts are known.
func snapshot(view_seat: int) -> Dictionary:
	var ps := []
	for p in players:
		var mine: bool = p.seat == view_seat
		ps.append({
			"seat": p.seat, "name": p.name, "hp": p.hp, "max_hp": p.max_hp, "alive": p.alive,
			"cuffed": p.cuffed, "sawed": p.sawed, "has_melded": p.has_melded,
			"score": p.score, "rounds_won": p.rounds_won, "turns_taken": p.turns_taken,
			"hand": p.hand.duplicate(true) if mine or p.exposed else _hidden_hand(p),
			"exposed": p.exposed, "ultimatum": p.ultimatum, "extra_draws": p.extra_draws,
			"items": p.items.duplicate(true) if mine else _hidden(p.items.size(), "i%d" % p.seat),
		})
	return {
		"options": options.duplicate(true), "players": ps, "round_num": round_num, "dealer": dealer,
		"turn": turn, "phase": phase, "stock": _hidden(stock.size(), "s"),
		"discard_pile": discard_pile.duplicate(true), "melds": melds.duplicate(true),
		"burned": _hidden(burned.size(), "b"), "gun": gun.duplicate() if gun != null else null,
		"last_result": last_result.duplicate(true), "winner": winner, "trump_rank": trump_rank,
		"drawn_from_discard": drawn_from_discard, "items_used_this_turn": items_used_this_turn,
		"placed_this_turn": placed_this_turn,
		"melded_at_turn_start": _melded_at_turn_start,
	}


## Turns this game into a read-only mirror of a snapshot (used on players'
## phones; only the host's game is real).
func load_snapshot(d: Dictionary) -> void:
	options = d["options"]
	players.clear()
	for pd in d["players"]:
		var p := Player.new(int(pd["seat"]), str(pd["name"]))
		p.hp = pd["hp"]
		p.max_hp = pd["max_hp"]
		p.alive = pd["alive"]
		p.cuffed = pd["cuffed"]
		p.sawed = pd["sawed"]
		p.has_melded = pd["has_melded"]
		p.score = pd["score"]
		p.rounds_won = pd["rounds_won"]
		p.turns_taken = pd["turns_taken"]
		p.exposed = pd["exposed"]
		p.ultimatum = pd["ultimatum"]
		p.extra_draws = pd["extra_draws"]
		p.hand = pd["hand"]
		p.items = pd["items"]
		players.append(p)
	round_num = d["round_num"]
	dealer = d["dealer"]
	turn = d["turn"]
	phase = d["phase"]
	stock = d["stock"]
	discard_pile = d["discard_pile"]
	melds = d["melds"]
	burned = d["burned"]
	gun = d["gun"]
	last_result = d["last_result"]
	winner = d["winner"]
	trump_rank = d["trump_rank"]
	drawn_from_discard = d["drawn_from_discard"]
	items_used_this_turn = d["items_used_this_turn"]
	placed_this_turn = d["placed_this_turn"]
	_melded_at_turn_start = d["melded_at_turn_start"]


## Someone else's hand: face-down placeholders, except cards a Flashbang
## turned face up.
func _hidden_hand(p: Player) -> Array:
	var out := _hidden(p.hand.size(), "h%d" % p.seat)
	for i in range(p.hand.size()):
		if p.hand[i].get("shown", false):
			out[i] = p.hand[i].duplicate()
	return out


func _hidden(count: int, tag: String) -> Array:
	var out := []
	for i in range(count):
		out.append({"id": "?%s-%d" % [tag, i], "hidden": true, "rank": 0, "suit": ""})
	return out


# ---------------------------------------------------------------- helpers

func _shuffle(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


func _emit(kind: String, data: Dictionary) -> void:
	event.emit(kind, data)


func _ok(extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": true, "error": ""}
	d.merge(extra, true)
	return d


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
