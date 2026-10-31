extends "res://scripts/core/tricks.gd"
## Shotgun Hearts: don't take hearts. Trick-taking (see tricks.gd), plus:
## - Every heart you take is 1 point; the Queen of Spades is 13. Lowest
##   points wins the round.
## - Hearts can't be led until one has been played (unless you hold nothing
##   else).
## - Take the Queen of Spades and you lose 1 health on the spot.
## - Take every point card dealt and you SHOOT THE MOON: you win, with 3
##   shells. Otherwise the winner gets 1 shell, +1 if they took no points.


func _init() -> void:
	kind = "hearts"


static func points_of(card: Dictionary) -> int:
	if str(card["suit"]) == "H":
		return 1
	if str(card["suit"]) == "S" and int(card["rank"]) == 12:
		return 13
	return 0


func table_note(seat: int) -> String:
	return "%d POINTS" % points(seat)


func points(seat: int) -> int:
	var n := 0
	for c in taken.get(seat, []):
		n += points_of(c)
	return n


func _may_lead(seat: int, card: Dictionary) -> bool:
	if str(card["suit"]) != "H" or broken:
		return true
	# only hearts left: lead one anyway
	for c in players[seat].hand:
		if str(c["suit"]) != "H" and not is_wild_card(c):
			return false
	return true


func _lead_rule() -> String:
	return "Hearts can't be led until one has been played."


func _on_card_played(_seat: int, card: Dictionary) -> void:
	if str(card["suit"]) == "H" and not broken:
		broken = true
		_emit("hearts_broken", {})


func _after_trick(winner: int, cards: Array) -> void:
	for c in cards:
		if points_of(c) == 13:
			_emit("queen_taken", {"seat": winner})
			if options["shotgun"]:
				damage(winner, 1, "queen")
			return


func _finish_round() -> void:
	var dealt_points := 0
	for p in players:
		for c in taken.get(p.seat, []):
			dealt_points += points_of(c)
	var pts := {}
	for p in players:
		if p.alive:
			pts[p.seat] = points(p.seat)
	var hands := []
	for s in pts:
		hands.append({"seat": s, "name": players[s].name, "cards": [], "points": pts[s]})
	# shooting the moon
	for s in pts:
		if dealt_points > 0 and pts[s] == dealt_points:
			players[s].score += dealt_points
			_end_with(s, mini(3, int(options["max_shells"])), {"points": pts[s], "hands": hands, "moon": true, "reason": ""})
			return
	var best := 999
	var winners := []
	for s in pts:
		if pts[s] < best:
			best = pts[s]
			winners = [s]
		elif pts[s] == best:
			winners.append(s)
	if winners.size() != 1:
		_end_with(-1, 0, {"points": best, "hands": hands, "moon": false, "reason": "A tie for the fewest points. Nobody wins."})
		return
	var w: int = winners[0]
	_end_with(w, mini(int(options["max_shells"]), 1 + (1 if best == 0 else 0)), {"points": best, "hands": hands, "moon": false, "reason": ""})
