extends "res://scripts/core/game.gd"
## Shotgun Cheat. Same table as Shotgun Rummy: a rotating dealer, items, a
## wild trump rank, health and the shotgun.
##
## - All 52 cards are dealt out, plus 2 items each. The other items wait in a
##   pile of their own.
## - Cards go down in rank order: aces first, then twos, up to kings, then
##   round again. On your turn put 1 to 4 cards face down on the pile and say
##   they're the rank that's due. They might not be.
## - Before you play, you can call CHEAT! on the player before you. The cards
##   are turned over: if any of them isn't the rank they said, the liar picks
##   up the whole pile and you get an item. If they told the truth, you pick
##   it up. Either way you then play your turn.
## - Trumps are wild: a trump always counts as the rank you said.
## - Play your last card and you win, unless the next player calls CHEAT! and
##   catches you. The winner gets 1 shell, +1 for every 15 cards the others
##   are left holding (max 3).

var required := 1 # the rank due next
var last_play := {} # { seat, ids, count, rank, revolver }: the play that can be called
var pending_win := -1 # played their last card; wins unless caught
var caught := {} # seat -> times caught lying this round


func _init() -> void:
	kind = "cheat"
	options["trump_cards"] = false # trumps are Rummy's


func rank_name(rank: int) -> String:
	const NAMES := ["", "ACES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "SEVENS", "EIGHTS", "NINES", "TENS", "JACKS", "QUEENS", "KINGS"]
	return NAMES[rank] if rank >= 1 and rank <= 13 else ""


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
	var i := 0
	while not deck.is_empty():
		players[order[i % order.size()]].hand.append(deck.pop_back())
		i += 1
	for k in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	item_deck = items
	stock = []
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	last_play = {}
	pending_win = -1
	caught = {}
	required = 1
	_temp_wild = []
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	placed_this_turn = false
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


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


## Can `seat` call CHEAT! right now?
func can_call(seat: int) -> bool:
	return is_turn_of(seat) and not last_play.is_empty() and int(last_play["seat"]) != seat


## The fewest cards `seat` may play this turn (Double Down makes it 2).
func min_play(seat: int) -> int:
	var p: Player = players[seat]
	return mini(2, p.hand.size()) if p.extra_draws > 0 else 1


func play(seat: int, card_ids: Array) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if pending_win >= 0:
		return _fail("%s played their last card. Call CHEAT! or let it go." % players[pending_win].name)
	var p := current()
	var cards := _cards_from(p.hand, card_ids)
	if cards.is_empty():
		return _fail("Pick the cards to put down.")
	if cards.size() > 4:
		return _fail("Put down 1 to 4 cards.")
	if cards.size() < min_play(seat):
		return _fail("Double Down: put down at least 2 cards this turn.")
	for c in cards:
		p.hand.erase(c)
		c.erase("shown")
		discard_pile.append(c)
	p.extra_draws = 0
	last_play = {"seat": seat, "ids": Cards.ids_of(cards), "count": cards.size(), "rank": required, "revolver": p.ultimatum}
	p.ultimatum = false
	_emit("play", {"seat": seat, "count": cards.size(), "rank": required})
	required = required % 13 + 1
	if p.hand.is_empty():
		pending_win = seat
	_next_turn()
	return _ok({"count": cards.size()})


## Was the last play a lie?
func _was_lie() -> bool:
	for c in discard_pile:
		if last_play["ids"].has(c["id"]):
			if int(c["rank"]) != int(last_play["rank"]) and not Cards.is_wild(c, trump_rank):
				return true
	return false


func call_cheat(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not can_call(seat):
		return _fail("There's nothing to call.")
	var liar: int = last_play["seat"]
	var shown := []
	for c in discard_pile:
		if last_play["ids"].has(c["id"]):
			shown.append(c.duplicate())
	var lie := _was_lie()
	var loser: int = liar if lie else seat
	var revolver: bool = last_play.get("revolver", false)
	var pile := discard_pile.size()
	players[loser].hand.append_array(discard_pile)
	discard_pile = []
	last_play = {}
	_emit("called", {"seat": seat, "liar": liar, "lie": lie, "cards": shown, "picked_up": loser, "count": pile})
	var reward := {}
	if lie:
		caught[liar] = int(caught.get(liar, 0)) + 1
		if pending_win == liar:
			pending_win = -1
		if not item_deck.is_empty():
			reward = item_deck.pop_back()
			current().items.append(reward)
		if revolver:
			if _russian_roulette(players[liar]):
				return _ok({"lie": lie})
	elif pending_win == liar:
		_finish_round(liar)
		return _ok({"lie": lie})
	return _ok({"lie": lie, "cards": shown, "item": reward})


## Let a last card go: the player who played it wins.
func let_go(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if pending_win < 0:
		return _fail("Nobody's about to win.")
	_emit("let_go", {"seat": seat, "winner": pending_win})
	_finish_round(pending_win)
	return _ok()


func _finish_round(w: int) -> void:
	var left := 0
	var hands := []
	for p in players:
		if p.alive:
			if p.seat != w:
				left += p.hand.size()
			hands.append({"seat": p.seat, "name": p.name, "cards": p.hand.duplicate(true), "points": p.hand.size()})
	pending_win = -1
	var result := {"round": round_num, "winner": w, "points": left, "shells": 0, "rummy": false, "hands": hands, "caught": caught.duplicate(), "reason": ""}
	if w >= 0:
		players[w].rounds_won += 1
		players[w].score += left
		result["shells"] = mini(int(options["max_shells"]), 1 + int(left / 15))
	last_result = result
	if options["shotgun"] and w >= 0:
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
			if args.size() == 1 and args[0] is Array:
				return play(seat, args[0])
		"call":
			return call_cheat(seat)
		"let_go":
			return let_go(seat)
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("There's no drawing in Cheat.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("There's no drawing in Cheat.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in Cheat.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Cheat.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Cheat.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Put cards on the pile with PLAY.")


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
				if not p.ultimatum:
					out.append(p.seat)
			return out
	return super.item_targets(seat, item_id)


func item_blocker(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> String:
	var card := find_item(seat, item_card_id)
	if not card.is_empty():
		match card["item"]:
			"magnifier", "sticky_fingers":
				var err := _guard(seat)
				if err != "":
					return err
				if card["item"] == "magnifier" and last_play.is_empty():
					return "Nothing's been played to look at."
				if discard_pile.is_empty():
					return "The pile is empty."
				return ""
	return super.item_blocker(seat, item_card_id, target, choice)


func use_item(seat: int, item_card_id: String, target: int = -1, choice: String = "") -> Dictionary:
	var res := super.use_item(seat, item_card_id, target, choice)
	if res["ok"]:
		if discard_pile.is_empty():
			last_play = {}
		if pending_win >= 0 and not players[pending_win].hand.is_empty():
			pending_win = -1 # they're holding cards again
	return res


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"magnifier":
			# a card from the last play: a lie, if there is one
			var pick := {}
			for c in discard_pile:
				if last_play["ids"].has(c["id"]):
					if pick.is_empty() or (int(c["rank"]) != int(last_play["rank"]) and not Cards.is_wild(c, trump_rank)):
						pick = c
			return {"text": "%s peeks at the last play" % p.name, "reveal": pick, "private": true}
		"shakedown":
			var mark: Player = players[target]
			var n := mini(3, discard_pile.size())
			for i in range(n):
				mark.hand.append(discard_pile.pop_front())
			return {"text": "%s shakes down %s, who takes %d card%s from the bottom of the pile" % [p.name, mark.name, n, "" if n == 1 else "s"]}
		"sticky_fingers":
			var top: Dictionary = discard_pile.pop_back()
			p.hand.append(top)
			return {"text": "%s slips the top card of the pile into their hand" % p.name, "reveal": top, "private": true}
		"double_down":
			var loaded: Player = players[target]
			loaded.extra_draws = 1
			return {"text": "%s doubles down on %s: they put down at least 2 cards next turn" % [p.name, loaded.name]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: lie next turn and get caught, and spin it" % [p.name, marked.name]}
		"joker_paint":
			for c in p.hand:
				if c["id"] == choice:
					c["wild"] = true # for the rest of the round
					return {"text": "%s paints a card wild" % p.name, "reveal": c, "private": true}
	return super._apply_item(p, item_id, target, choice)


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["discard_pile"] = _hidden(discard_pile.size(), "p") # the pile is face down
	var lp := last_play.duplicate()
	lp.erase("ids")
	d["last_play"] = lp
	d["required"] = required
	d["pending_win"] = pending_win
	d["caught"] = caught.duplicate()
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	last_play = d.get("last_play", {})
	required = int(d.get("required", 1))
	pending_win = int(d.get("pending_win", -1))
	caught = d.get("caught", {})
