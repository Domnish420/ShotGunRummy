extends "res://scripts/core/game.gd"
## Shotgun Snap. Same table: a rotating dealer, items, a wild trump rank,
## health and the shotgun.
##
## - All the cards are dealt face down into everyone's own pile, with the
##   items shuffled in. Nobody looks at their pile.
## - On your turn, FLIP the top card of your pile onto the pile in the middle.
##   Flip an item and you keep it and flip again.
## - When the top two cards in the middle match (same rank, or either one is
##   a trump), anyone can SNAP! at any time, not just on their turn. The first
##   to snap wins every card in the middle.
## - Snap when they don't match and it costs you 1 health (in normal mode you
##   put 2 cards from your pile in the middle instead).
## - When everyone's pile has run out, whoever won the most cards wins the
##   round, with 1 shell, +1 for every 10 cards they're ahead (max 3).

var won := {} # seat -> cards won by snapping
var flips := 0 # counts flips, so the table and the AI notice new ones
var last_call := false # every pile is empty: snap now or never


func _init() -> void:
	kind = "snap"


func table_note(seat: int) -> String:
	return "WON %d" % won.get(seat, []).size()


## Nothing private in Snap: nobody looks at their own pile.
func has_private_hands() -> bool:
	return false


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
	var items := _shuffle(Items.create_item_deck())
	for k in range(int(options["items_dealt"])):
		for s in order:
			if not items.is_empty():
				players[s].items.append(items.pop_back())
	var deck := _shuffle(Cards.create_deck() + (items if options["items_in_stock"] else []))
	var i := 0
	while not deck.is_empty():
		players[order[i % order.size()]].hand.append(deck.pop_back())
		i += 1
	item_deck = [] if options["items_in_stock"] else items
	stock = []
	discard_pile = []
	melds = []
	burned = []
	gun = null
	last_result = {}
	won = {}
	for s in order:
		won[s] = []
	flips = 0
	last_call = false
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": trump_rank})
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


func _next_turn() -> void:
	if phase != "play":
		return
	for i in range(players.size()):
		turn = next_alive(turn)
		var p: Player = players[turn]
		if p.hand.is_empty():
			continue
		if p.cuffed:
			p.cuffed = false
			_emit("turn_skipped", {"seat": turn})
			continue
		_begin_turn()
		return
	# nobody has anything left to flip
	last_call = true
	_begin_turn()


## Do the top two cards in the middle match?
func snap_ready() -> bool:
	if discard_pile.size() < 2:
		return false
	var a: Dictionary = discard_pile[-1]
	var b: Dictionary = discard_pile[-2]
	return int(a["rank"]) == int(b["rank"]) or Cards.is_wild(a, trump_rank) or Cards.is_wild(b, trump_rank)


func flip(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if last_call:
		return _fail("Every pile is empty. COUNT UP to end the round.")
	var p := current()
	var times := 2 if p.extra_draws > 0 else 1
	p.extra_draws = 0
	var card := {}
	for t in range(times):
		while not p.hand.is_empty():
			var c: Dictionary = p.hand.pop_back()
			if c.has("item"):
				p.items.append(c)
				_emit("draw", {"seat": seat, "source": "stock", "item": true})
				continue
			discard_pile.append(c)
			card = c
			flips += 1
			_emit("flip", {"seat": seat, "card": c, "ready": snap_ready()})
			break
	_next_turn()
	return _ok({"card": card})


## SNAP! Anyone, any time in the round.
func snap(seat: int) -> Dictionary:
	if phase != "play":
		return _fail("The round is over.")
	if seat < 0 or seat >= players.size() or not players[seat].alive:
		return _fail("You're out.")
	var p: Player = players[seat]
	if snap_ready():
		var n := discard_pile.size()
		won[seat] = won.get(seat, []) + discard_pile
		discard_pile = []
		_emit("snap", {"seat": seat, "good": true, "count": n})
		return _ok({"good": true, "count": n})
	_emit("snap", {"seat": seat, "good": false, "count": 0})
	if options["shotgun"]:
		damage(seat, 1, "snap")
		if p.ultimatum and p.alive:
			p.ultimatum = false
			_russian_roulette(p)
	else:
		for i in range(mini(2, p.hand.size())):
			var c: Dictionary = p.hand.pop_back()
			if c.has("item"):
				p.items.append(c)
			else:
				discard_pile.insert(0, c)
	return _ok({"good": false})


## After the last flip: count up.
func finish(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not last_call:
		return _fail("There are still cards to flip.")
	_finish_round()
	return _ok()


func _finish_round() -> void:
	var counts := {}
	for p in players:
		if p.alive:
			counts[p.seat] = won.get(p.seat, []).size()
	var best := -1
	var second := 0
	var winners := []
	for s in counts:
		var c: int = counts[s]
		if c > best:
			second = maxi(second, best)
			best = c
			winners = [s]
		elif c == best:
			winners.append(s)
		else:
			second = maxi(second, c)
	var hands := []
	for s in counts:
		hands.append({"seat": s, "name": players[s].name, "cards": [], "points": counts[s]})
	var w: int = winners[0] if winners.size() == 1 and best > 0 else -1
	var result := {"round": round_num, "winner": w, "points": best, "shells": 0, "rummy": false, "hands": hands,
		"reason": "" if w >= 0 else "A tie for the most cards. Nobody wins."}
	if w >= 0:
		players[w].rounds_won += 1
		players[w].score += best
		result["shells"] = mini(int(options["max_shells"]), 1 + int((best - second) / 10))
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
		"flip":
			return flip(seat)
		"snap":
			return snap(seat)
		"finish":
			return finish(seat)
	return _fail("That didn't work.")


# none of Rummy's moves exist here
func draw_stock(seat: int) -> Dictionary:
	return flip(seat)


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Flip, or snap.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("There's no melding in Snap.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("There's no laying off in Snap.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("There's no swapping in Snap.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Flip, or snap.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


# ---------------------------------------------------------------- items

func item_targets(seat: int, item_id: String) -> Array:
	var out := []
	match item_id:
		"sticky_fingers":
			for p in others(seat):
				if not won.get(p.seat, []).is_empty():
					out.append(p.seat)
			return out
		"phone", "switcheroo", "bad_trade", "double_down", "handcuffs":
			for p in others(seat):
				if not p.hand.is_empty() and (item_id != "double_down" or p.extra_draws == 0) and (item_id != "handcuffs" or not p.cuffed):
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
	if not card.is_empty() and card["item"] in ["magnifier", "joker_paint"]:
		var err := _guard(seat)
		if err != "":
			return err
		if card["item"] == "magnifier" and players[seat].hand.is_empty():
			return "Your pile is empty."
		if card["item"] == "joker_paint" and discard_pile.is_empty():
			return "There's nothing in the middle to paint."
		return ""
	return super.item_blocker(seat, item_card_id, target, choice)


func _apply_item(p: Player, item_id: String, target: int, choice: String) -> Dictionary:
	match item_id:
		"phone":
			var called: Player = players[target]
			return {"text": "%s makes a call about %s's next card" % [p.name, called.name], "reveal": _next_card(called), "private": true}
		"magnifier":
			return {"text": "%s peeks at their next card" % p.name, "reveal": _next_card(p), "private": true}
		"sticky_fingers":
			var mark: Player = players[target]
			var theirs: Array = won[target]
			var n := mini(3, theirs.size())
			for i in range(n):
				won[p.seat] = won.get(p.seat, []) + [theirs.pop_back()]
			return {"text": "%s steals %d of %s's won cards" % [p.name, n, mark.name]}
		"double_down":
			var loaded: Player = players[target]
			loaded.extra_draws = 1
			return {"text": "%s doubles down on %s: they flip 2 cards next turn" % [p.name, loaded.name]}
		"revolver":
			var marked: Player = players[target]
			marked.ultimatum = true
			return {"text": "%s slides the revolver to %s: snap wrong and spin it" % [p.name, marked.name]}
		"joker_paint":
			var top: Dictionary = discard_pile[-1]
			top["wild"] = true
			flips += 1
			_emit("flip", {"seat": p.seat, "card": top, "ready": snap_ready()})
			return {"text": "%s paints the top card wild. SNAP!" % p.name}
	return super._apply_item(p, item_id, target, choice)


## The next playing card in a pile (items are skipped over).
func _next_card(p: Player) -> Dictionary:
	for i in range(p.hand.size() - 1, -1, -1):
		if not p.hand[i].has("item"):
			return p.hand[i]
	return {}


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	# nobody sees any pile, their own included
	for pd in d["players"]:
		pd["hand"] = _hidden(pd["hand"].size(), "h%d" % pd["seat"])
	var counts := {}
	for s in won:
		counts[s] = won[s].size()
	d["won_counts"] = counts
	d["flips"] = flips
	d["last_call"] = last_call
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	won = {}
	for s in d.get("won_counts", {}):
		won[s] = _hidden(int(d["won_counts"][s]), "w%d" % s)
	flips = int(d.get("flips", 0))
	last_call = d.get("last_call", false)
