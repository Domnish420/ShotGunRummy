extends "res://scripts/core/game.gd"
## What Hearts and Spades share: trick-taking on the Shotgun table.
##
## - The cards are dealt out evenly (any left over are set aside face down),
##   plus 2 items each.
## - The player left of the dealer leads the first trick. Everyone plays one
##   card in turn; follow the suit that was led if you can. The highest card of
##   the led suit wins (aces high), and the winner leads the next trick.
## - The round's trump rank is wild: a trump can be played at any time, even
##   when you could follow suit, and beats everything. If more than one is
##   played, the first one wins.
## Hearts and Spades fill in the scoring (and Spades the bidding).

var trick: Array = [] # [{ seat, card }] in the order played
var leader := -1 # who led this trick
var tricks_won := {} # seat -> tricks taken this round
var taken := {} # seat -> cards taken this round
var broken := false # Hearts: hearts played; Spades: spades played
var last_trick := {} # { winner, cards } for the table to show
var _expected: Array = [] # seats playing this trick, from the leader
var _settling := false # a trick is being settled (someone may be knocked out mid-way)

const SUIT_WORDS := {"S": "spade", "H": "heart", "D": "diamond", "C": "club"}


## Ace high.
static func value(card: Dictionary) -> int:
	var r := int(card["rank"])
	return 14 if r == 1 else r


func is_wild_card(card: Dictionary) -> bool:
	return Cards.is_wild(card, trump_rank)


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
	var each := int(deck.size() / order.size())
	for i in range(each):
		for s in order:
			players[s].hand.append(deck.pop_back())
	burned = deck # left over: set aside face down
	var items := _shuffle(Items.create_item_deck())
	for k in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	item_deck = items
	stock = []
	discard_pile = []
	melds = []
	gun = null
	last_result = {}
	trick = []
	tricks_won = {}
	taken = {}
	for s in order:
		tricks_won[s] = 0
		taken[s] = []
	broken = false
	last_trick = {}
	_temp_wild = []
	leader = order[0]
	turn = leader
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_before_play()
	return _ok()


## Spades bids first; Hearts goes straight to the first trick.
func _before_play() -> void:
	_start_trick(leader)


func _start_trick(seat: int) -> void:
	trick = []
	leader = seat
	_expected = []
	for s in _seats_from(seat):
		if not players[s].hand.is_empty():
			_expected.append(s)
	turn = seat
	_begin_turn()


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


func led_suit() -> String:
	return str(trick[0]["card"]["suit"]) if not trick.is_empty() else ""


## The cards `seat` may play right now.
func legal_cards(seat: int) -> Array:
	var hand: Array = players[seat].hand
	var out := []
	if trick.is_empty():
		for c in hand:
			if is_wild_card(c) or _may_lead(seat, c):
				out.append(c)
		if out.is_empty():
			out = hand.duplicate()
	else:
		var suit := led_suit()
		for c in hand:
			if is_wild_card(c) or str(c["suit"]) == suit:
				out.append(c)
		var follows := out.filter(func(c): return str(c["suit"]) == suit and not is_wild_card(c))
		if follows.is_empty():
			out = hand.duplicate()
	# Double Down: your highest legal card
	if players[seat].extra_draws > 0 and out.size() > 1:
		var top: Dictionary = out[0]
		for c in out:
			if _strength(c) > _strength(top):
				top = c
		out = [top]
	return out


## How hard a card hits, for "highest card": wilds over everything.
func _strength(c: Dictionary) -> int:
	return 100 if is_wild_card(c) else value(c)


## Hearts and Spades: can't lead the broken suit until it's broken.
func _may_lead(_seat: int, _card: Dictionary) -> bool:
	return true


func play_card(seat: int, card_id: String) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	var p := current()
	var cards := _cards_from(p.hand, [card_id])
	if cards.is_empty():
		return _fail("That card isn't in your hand.")
	var card: Dictionary = cards[0]
	if not legal_cards(seat).has(card):
		if p.extra_draws > 0:
			return _fail("Double Down: play your highest card.")
		if not trick.is_empty():
			return _fail("Follow suit: play a %s if you have one." % SUIT_WORDS.get(led_suit(), led_suit()))
		return _fail(_lead_rule())
	p.hand.erase(card)
	card.erase("shown")
	p.extra_draws = 0
	trick.append({"seat": seat, "card": card})
	_on_card_played(seat, card)
	_emit("trick_card", {"seat": seat, "card": card})
	_advance()
	return _ok({"card": card})


func _lead_rule() -> String:
	return "You can't lead that yet."


func _on_card_played(_seat: int, _card: Dictionary) -> void:
	pass


## Next player in this trick, or settle it.
func _advance() -> void:
	if phase != "play":
		return
	var played := {}
	for t in trick:
		played[t["seat"]] = true
	for s in _expected:
		if not played.has(s) and players[s].alive and not players[s].hand.is_empty():
			turn = s
			_begin_turn()
			return
	_settle_trick()


func trick_winner() -> int:
	var best: Dictionary = {}
	for t in trick:
		if is_wild_card(t["card"]):
			return t["seat"] # the first trump played
	var suit := led_suit()
	for t in trick:
		if _beats(t, best, suit):
			best = t
	return best["seat"]


## Does trick entry `a` beat the best so far? Spades adds its trump suit.
func _beats(a: Dictionary, best: Dictionary, suit: String) -> bool:
	if best.is_empty():
		return true
	if str(a["card"]["suit"]) != suit:
		return false
	return str(best["card"]["suit"]) != suit or value(a["card"]) > value(best["card"])


func _settle_trick() -> void:
	_settling = true
	_settle()
	_settling = false


func _settle() -> void:
	var w := trick_winner()
	var cards := []
	for t in trick:
		cards.append(t["card"])
	tricks_won[w] = int(tricks_won.get(w, 0)) + 1
	if not taken.has(w):
		taken[w] = []
	taken[w].append_array(cards)
	last_trick = {"winner": w, "cards": trick.duplicate(true)}
	_end_reveals_all()
	_emit("trick_won", {"seat": w, "cards": cards, "tricks": tricks_won[w]})
	var winner_p: Player = players[w]
	if winner_p.ultimatum:
		winner_p.ultimatum = false
		_russian_roulette(winner_p)
	_after_trick(w, cards)
	if phase != "play" and phase != "draw":
		return
	trick = []
	var anyone := false
	for p in players:
		if p.alive and not p.hand.is_empty():
			anyone = true
	if not anyone:
		_finish_round()
		return
	var next_lead := w if players[w].alive and not players[w].hand.is_empty() else next_alive(w)
	_start_trick(next_lead)


func _end_reveals_all() -> void:
	for p in players:
		if p.exposed or p.hand.any(func(c): return c.get("shown", false)):
			# Spotlight and Flashbang last one trick
			_end_reveals(p)


## Hearts: points (and the Queen of Spades). Spades: nothing extra.
func _after_trick(_winner: int, _cards: Array) -> void:
	pass


func _finish_round() -> void:
	pass


## Ends the round with `w` (or -1) taking `shells`.
func _end_with(w: int, shells: int, result: Dictionary) -> void:
	result["round"] = round_num
	result["winner"] = w
	result["shells"] = shells
	result["rummy"] = false
	if w >= 0:
		players[w].rounds_won += 1
	last_result = result
	if options["shotgun"] and w >= 0 and shells > 0:
		phase = "shoot"
		gun = {"holder": w, "shells": shells, "total": shells}
	else:
		phase = "round_over"
		gun = null
	_emit("round_end", result)
	_check_normal_match()


func _next_turn() -> void:
	# someone was knocked out on their turn: carry on with the trick
	if not _settling:
		_advance()


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	if action == "play" and args.size() == 1 and args[0] is String:
		return play_card(seat, args[0])
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Play a card to the trick.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Play a card to the trick.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding here.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off here.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping here.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Play a card to the trick.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"double_down":
			for p in others(seat):
				if p.extra_draws == 0 and p.hand.size() >= 2:
					out.append(p.seat)
			return out
		"revolver":
			for p in others(seat):
				if not p.ultimatum and not p.hand.is_empty():
					out.append(p.seat)
			return out
	return super.item_targets(seat, item_id)


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"double_down":
			var loaded: Player = players[target]
			loaded.extra_draws = 1
			return {"text": "%s doubles down on %s: they play their highest card next" % [p.name, loaded.name]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: win the next trick and spin it" % [p.name, marked.name]}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true # for the rest of the round
					return {"text": "%s paints a card wild" % p.name, "reveal": c, "private": true}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["trick"] = trick.duplicate(true)
	d["leader"] = leader
	d["tricks_won"] = tricks_won.duplicate()
	d["taken"] = taken.duplicate(true)
	d["broken"] = broken
	d["last_trick"] = last_trick.duplicate(true)
	d["expected"] = _expected.duplicate()
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	trick = d.get("trick", [])
	leader = int(d.get("leader", -1))
	tricks_won = d.get("tricks_won", {})
	taken = d.get("taken", {})
	broken = d.get("broken", false)
	last_trick = d.get("last_trick", {})
	_expected = d.get("expected", [])
