extends "res://scripts/core/game.gd"
## Shotgun Crazy Eights. Same table: a rotating dealer, items, health and the
## shotgun.
##
## - 7 cards each (5 with 5 or 6 players). The rest is the stock, with the
##   round's few items shuffled in. One card is turned up to start the pile.
## - On your turn play one card that matches the top card's suit or rank.
##   Can't (or won't)? DRAW one. Then play, or PASS.
## - Eights are wild (WHISKEY): play one on anything and call the suit.
## - The saloon cards:
##     2  +2             the next player draws 2, unless they stack a 2 (or
##                       the Ace of Spades) on it and pass the lot along
##     A♠ LAST ORDERS    the next player draws 4 (stacks the same way)
##     J  CUFFED         the next player is skipped
##     Q  KICK BACK      play turns round (with 2 players: a skip)
## - Down to one card? Call LAST SHOT! as you play your second-last card.
##   Forget, and the table catches you: draw 2.
## - First out wins the round and gets the shotgun: 1 shell, or 2 for going
##   out on a saloon card or an eight.

const ACTIONS := {2: "+2", 11: "CUFFED", 12: "KICK BACK", 8: "WHISKEY"}

var called_suit := "" # the suit an eight called, until the next card
var direction := 1 # 1 = to the left, -1 = back round the other way
var pending_draw := 0 # Double Barrel / Last Orders stacked on the next player
var drew := false # drew this turn: play or pass
var last_shot := {} # seat -> true: called LAST SHOT! this turn
var _dry := 0 # turns in a row with nothing left to draw


func _init() -> void:
	kind = "crazy8"
	options["trump_cards"] = false # trumps are Rummy's
	options["max_reshuffles"] = 99 # the pile goes back under all round


func table_note(seat: int) -> String:
	var n: int = players[seat].hand.size()
	return "LAST SHOT" if n == 1 else ""


static func is_last_orders(card: Dictionary) -> bool:
	return int(card["rank"]) == 1 and card["suit"] == "S"


## Does this card stack onto a Double Barrel / Last Orders?
static func stacks(card: Dictionary) -> bool:
	return int(card["rank"]) == 2 or is_last_orders(card)


static func is_action(card: Dictionary) -> bool:
	return ACTIONS.has(int(card["rank"])) or is_last_orders(card)


## The suit to match: the one an eight called, or the top card's.
func suit_to_match() -> String:
	if called_suit != "":
		return called_suit
	var top := top_discard()
	return "" if top.is_empty() else str(top["suit"])


func can_play_card(seat: int, card: Dictionary) -> bool:
	if pending_draw > 0:
		return stacks(card)
	if int(card["rank"]) == 8:
		return true
	var top := top_discard()
	if top.is_empty():
		return true
	if card["suit"] == suit_to_match():
		return true
	return called_suit == "" and int(card["rank"]) == int(top["rank"])


func playable(seat: int) -> Array:
	var out := []
	for c in players[seat].hand:
		if can_play_card(seat, c):
			out.append(c)
	return out


func can_draw(seat: int) -> bool:
	return is_turn_of(seat) and phase == "play" and not drew


func can_pass(seat: int) -> bool:
	return is_turn_of(seat) and phase == "play" and drew


## May `seat` call LAST SHOT! now? On your turn with 2 cards left.
func can_call(seat: int) -> bool:
	return is_turn_of(seat) and phase == "play" and players[seat].hand.size() == 2 and not last_shot.has(seat)


func _step(seat: int) -> int:
	return next_alive(seat) if direction > 0 else prev_alive(seat)


# ---------------------------------------------------------------- the round

func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	dealer = prev_alive(0) if dealer < 0 else prev_alive(dealer)
	trump_rank = 0
	for p in players:
		p.hand = []
		p.items = []
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0
	var order := _seats_from(next_alive(dealer))
	var size := 7 if order.size() <= 4 else 5
	var deck := _shuffle(Cards.create_deck())
	for i in range(size):
		for s in order:
			players[s].hand.append(deck.pop_back())
	# turn up a plain card to start: no saloon cards, no eights
	var start := deck.size() - 1
	while start > 0 and is_action(deck[start]):
		start -= 1
	discard_pile = [deck[start]]
	deck.remove_at(start)
	var items := _round_items()
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
	called_suit = ""
	direction = 1
	pending_draw = 0
	last_shot = {}
	_dry = 0
	_temp_wild = []
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": 0})
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	drew = false
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


## On to the next player (`skip` more get jumped).
func _next_turn(skip: int = 0) -> void:
	if phase != "play":
		return
	_end_reveals(current())
	last_shot.erase(turn)
	for i in range(players.size() * 2):
		turn = _step(turn)
		var p: Player = players[turn]
		if skip > 0:
			skip -= 1
			_emit("turn_skipped", {"seat": turn, "cuffed": true})
			continue
		if p.cuffed:
			p.cuffed = false
			_emit("turn_skipped", {"seat": turn})
			continue
		break
	_begin_turn()


## Draws `n` cards for `p` (items you draw are kept and you draw again).
## Returns how many playing cards they got.
func _deal_to(p: Player, n: int) -> int:
	var got := 0
	var guard := 0
	while got < n and guard < 60:
		guard += 1
		if stock.is_empty() and not _reshuffle_stock():
			break
		var card: Dictionary = stock.pop_back()
		if card.has("item"):
			p.items.append(card)
			_emit("draw", {"seat": p.seat, "source": "stock", "item": true})
			continue
		p.hand.append(card)
		got += 1
		_emit("draw", {"seat": p.seat, "source": "stock", "item": false})
	return got


func _reshuffle_stock() -> bool:
	if discard_pile.size() <= 1:
		return false
	var top: Dictionary = discard_pile.pop_back()
	stock = _shuffle(discard_pile)
	discard_pile = [top]
	_reshuffles += 1
	_emit("stock_reshuffled", {"size": stock.size()})
	return true


func play(seat: int, card_id: String, suit: String = "") -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, [card_id])
	if cards.is_empty():
		return _fail("Pick a card to play.")
	var card: Dictionary = cards[0]
	if not can_play_card(seat, card):
		if pending_draw > 0:
			return _fail("Stack a 2 (or the Ace of Spades), or DRAW %d." % pending_draw)
		return _fail("Match the suit or the rank, play an eight, or DRAW.")
	var eight := int(card["rank"]) == 8
	if eight and not Cards.SUITS.has(suit):
		return _fail("Pick a suit for the eight.")
	p.hand.erase(card)
	card.erase("shown")
	discard_pile.append(card)
	called_suit = suit if eight else ""
	p.ultimatum = false
	_dry = 0
	_emit("crazy8_play", {"seat": seat, "card": card, "suit": called_suit, "eight": eight, "barrel": stacks(card), "stack": pending_draw + (4 if is_last_orders(card) else 2) if stacks(card) else 0})
	if p.hand.is_empty():
		_finish_round(seat, is_action(card))
		return _ok()
	if p.hand.size() == 1 and not last_shot.has(seat):
		# forgot to call it: the table catches you
		_emit("last_shot_caught", {"seat": seat})
		_deal_to(p, 2)
	elif p.hand.size() == 1:
		_emit("last_shot", {"seat": seat})
	var skip := 0
	if stacks(card):
		pending_draw += 4 if is_last_orders(card) else 2
	elif int(card["rank"]) == 11:
		skip = 1
	elif int(card["rank"]) == 12:
		if alive_count() == 2:
			skip = 1
		else:
			direction = -direction
			_emit("reverse", {"seat": seat, "direction": direction})
	_next_turn(skip)
	return _ok()


## Draw: one card, or the whole Double Barrel stack (which ends your turn).
func draw(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if drew:
		return _fail("You've drawn: play a card, or PASS.")
	var p := current()
	if pending_draw > 0:
		var n := pending_draw
		pending_draw = 0
		var got := _deal_to(p, n)
		_emit("took_stack", {"seat": seat, "count": got})
		_next_turn()
		return _ok({"count": got})
	drew = true
	var got := _deal_to(p, 1)
	if p.ultimatum:
		p.ultimatum = false
		if _russian_roulette(p):
			return _ok()
	if got == 0:
		# nothing left to draw anywhere: your turn just passes. Once nobody
		# can do anything, fewest cards takes the round
		_dry += 1
		_emit("pass", {"seat": seat})
		if _dry >= alive_count():
			var best := seat
			for q in alive_players():
				if q.hand.size() < players[best].hand.size():
					best = q.seat
			_finish_round(best, false)
			return _ok()
		_next_turn()
	else:
		_dry = 0
	return _ok({"count": got})


func pass_turn(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not drew:
		return _fail("Draw a card first.")
	_emit("pass", {"seat": seat})
	_next_turn()
	return _ok()


func call_last_shot(seat: int) -> Dictionary:
	if not can_call(seat):
		return _fail("Call it with two cards left, on your turn.")
	last_shot[seat] = true
	_emit("last_shot_called", {"seat": seat})
	return _ok()


func _finish_round(w: int, instant: bool) -> void:
	var hands := []
	for p in players:
		if not p.alive:
			continue
		hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": p.hand.size()})
	var result := {"round": round_num, "winner": w, "points": 0, "shells": 0, "rummy": false, "hands": hands, "reason": "", "instant": instant}
	players[w].rounds_won += 1
	result["shells"] = _shells(instant) # 2 for going out on a saloon card or an eight
	last_result = result
	pending_draw = 0
	if options["shotgun"]:
		phase = "shoot"
		gun = {"holder": w, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
		gun = null
	_emit("round_end", result)
	_check_normal_match()


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	match action:
		"play":
			if args.size() >= 1:
				return play(seat, str(args[0]), str(args[1]) if args.size() > 1 else "")
		"draw":
			return draw(seat)
		"pass":
			return pass_turn(seat)
		"last_shot":
			return call_last_shot(seat)
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(seat: int) -> Dictionary:
	return draw(seat)


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Draw from the stock.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in Crazy Eights.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Crazy Eights.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Crazy Eights.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Play a card, or draw.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"sticky_fingers", "garbage_day":
			for p in others(seat):
				if not p.hand.is_empty():
					out.append(p.seat)
			return out
		"double_down":
			return others(seat).map(func(p): return p.seat)
	return super.item_targets(seat, item_id)


func item_blocker(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> String:
	var card := find_item(seat, item_card_id)
	if not card.is_empty() and card["item"] in ["sticky_fingers", "dumpster_dive", "garbage_day", "double_down"]:
		var err := _basic_item_blocker(seat, item_card_id, target, choice)
		if err != "":
			return err
		match card["item"]:
			"dumpster_dive", "garbage_day":
				if discard_pile.size() <= 1:
					return "There's nothing under the top card."
		return ""
	return super.item_blocker(seat, item_card_id, target, choice)


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"shakedown":
			var mark: Player = players[target]
			var dropped: Dictionary = _random_card(mark.hand)
			mark.hand.erase(dropped)
			discard_pile.insert(0, dropped) # under the pile: the top card stays
			return {"text": "%s shakes down %s, who drops %s under the pile" % [p.name, mark.name, Cards.card_name(dropped)], "reveal": dropped, "private": false}
		"double_down":
			var loaded: Player = players[target]
			var got := _deal_to(loaded, 2)
			return {"text": "%s doubles down on %s: they draw %d" % [p.name, loaded.name, got]}
		"sticky_fingers":
			var mark: Player = players[target]
			var took: Dictionary = _random_card(mark.hand)
			mark.hand.erase(took)
			p.hand.append(took)
			return {"text": "%s pinches a card off %s" % [p.name, mark.name], "reveal": took, "private": true}
		"dumpster_dive":
			var top: Dictionary = discard_pile.pop_back()
			var grabbed := []
			for i in range(mini(2, discard_pile.size())):
				grabbed.append(discard_pile.pop_back())
			discard_pile.append(top)
			p.hand.append_array(grabbed)
			return {"text": "%s digs %s out from under the pile" % [p.name, Cards.cards_text(grabbed)]}
		"garbage_day":
			var dumped: Player = players[target]
			var top: Dictionary = discard_pile.pop_back()
			var n := discard_pile.size()
			dumped.hand.append_array(discard_pile)
			discard_pile = [top]
			return {"text": "%s makes %s pick up the pile under the top card (%d card%s)" % [p.name, dumped.name, n, "" if n == 1 else "s"]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: draw next turn and spin it" % [p.name, marked.name]}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["called_suit"] = called_suit
	d["direction"] = direction
	d["pending_draw"] = pending_draw
	d["drew"] = drew
	d["last_shot"] = last_shot.duplicate()
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	called_suit = str(d.get("called_suit", ""))
	direction = int(d.get("direction", 1))
	pending_draw = int(d.get("pending_draw", 0))
	drew = bool(d.get("drew", false))
	last_shot = d.get("last_shot", {})
