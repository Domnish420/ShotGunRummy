extends "res://scripts/core/tricks.gd"
## Shotgun Spades: everyone for themselves. Trick-taking (see tricks.gd),
## plus:
## - Before the first trick everyone BIDS how many tricks they'll take (0 is
##   "nil").
## - Spades beat the other suits. They can't be led until one has been
##   played (unless you hold nothing else).
## - Make your bid: 10 per trick bid, +1 for each extra. Miss it: -10 per
##   trick bid. Nil: +50 if you take none, -50 if you take any.
## - The best score this round wins, with 1 shell, +1 for making your bid
##   exactly, +1 for making nil.

var bids := {} # seat -> tricks bid
var bidding := false


func _init() -> void:
	kind = "spades"


func _before_play() -> void:
	bids = {}
	bidding = true
	turn = leader
	_begin_turn()


func table_note(seat: int) -> String:
	if not bids.has(seat):
		return "BIDDING..." if bidding else ""
	return "BID %d · WON %d" % [bids[seat], int(tricks_won.get(seat, 0))]


func bid(seat: int, n: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if not bidding:
		return _fail("The bidding is over.")
	var size: int = players[seat].hand.size()
	if n < 0 or n > size:
		return _fail("Bid 0 to %d." % size)
	bids[seat] = n
	_emit("bid", {"seat": seat, "bid": n})
	for s in _seats_from(leader):
		if players[s].alive and not bids.has(s):
			turn = s
			_begin_turn()
			return _ok()
	bidding = false
	_start_trick(leader)
	return _ok()


func legal_cards(seat: int) -> Array:
	if bidding:
		return []
	return super.legal_cards(seat)


func play_card(seat: int, card_id: String) -> Dictionary:
	if bidding:
		return _fail("Bid first.")
	return super.play_card(seat, card_id)


func _may_lead(seat: int, card: Dictionary) -> bool:
	if str(card["suit"]) != "S" or broken:
		return true
	for c in players[seat].hand:
		if str(c["suit"]) != "S" and not is_wild_card(c):
			return false
	return true


func _lead_rule() -> String:
	return "Spades can't be led until one has been played."


func _on_card_played(_seat: int, card: Dictionary) -> void:
	if str(card["suit"]) == "S" and not broken:
		broken = true
		_emit("spades_broken", {})


## Spades beat everything but a trump.
func _beats(a: Dictionary, best: Dictionary, suit: String) -> bool:
	if best.is_empty():
		return true
	var a_spade: bool = str(a["card"]["suit"]) == "S"
	var b_spade: bool = str(best["card"]["suit"]) == "S"
	if a_spade != b_spade:
		return a_spade
	if a_spade:
		return value(a["card"]) > value(best["card"])
	return super._beats(a, best, suit)


func round_score(seat: int) -> int:
	var b: int = int(bids.get(seat, 0))
	var t: int = int(tricks_won.get(seat, 0))
	if b == 0:
		return 50 if t == 0 else -50
	if t >= b:
		return 10 * b + (t - b)
	return -10 * b


func _finish_round() -> void:
	var hands := []
	var best := -99999
	var winners := []
	for p in players:
		if not p.alive:
			continue
		var sc := round_score(p.seat)
		p.score += sc
		hands.append({"seat": p.seat, "name": p.name, "cards": [], "points": sc, "bid": int(bids.get(p.seat, 0)), "tricks": int(tricks_won.get(p.seat, 0))})
		if sc > best:
			best = sc
			winners = [p.seat]
		elif sc == best:
			winners.append(p.seat)
	if winners.size() != 1:
		_end_with(-1, 0, {"points": best, "hands": hands, "reason": "A tie for the best score. Nobody wins."})
		return
	var w: int = winners[0]
	var b: int = int(bids.get(w, 0))
	var t: int = int(tricks_won.get(w, 0))
	var shells := 1 + (1 if b > 0 and t == b else 0) + (1 if b == 0 and t == 0 else 0)
	_end_with(w, mini(int(options["max_shells"]), shells), {"points": best, "hands": hands, "reason": ""})


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	if action == "bid" and args.size() == 1 and args[0] is int:
		return bid(seat, args[0])
	return super.perform_action(seat, action, args)


func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["bids"] = bids.duplicate()
	d["bidding"] = bidding
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	bids = d.get("bids", {})
	bidding = d.get("bidding", false)
