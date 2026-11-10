extends "res://scripts/core/game.gd"
## Shotgun Darts, the first party game (it lives on the party room wall, not
## on a cartridge). Same players, health and shotgun as the card games; no
## cards and no items. Three ways to play, each with its own stakes:
##
##   SHOOTOUT          3 darts each, highest total wins. 1 shell, or 2 if the
##                     winner hit a bullseye. A tie goes to sudden death: the
##                     tied players throw again.
##   AROUND THE CLOCK  hit 1, then 2, ... up to 20, then the bull. A double
##                     moves you on 2, a treble 3. 2 shells.
##   301               count down from 301 to exactly 0. Go under and you bust:
##                     the visit doesn't count. It's long, so it's worth 4
##                     shells: enough to finish someone off.
##
## The board is measured in board radii: (0, 0) is the bull, 1.0 the outer
## edge of the double ring, +y up. A throw is just where the dart lands; the
## aiming (two lines and a moving dot) is the table screen's job.

const NUMBERS := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5] # clockwise from the top
const BULL := 0.06
const OUTER_BULL := 0.13
const TREBLE_IN := 0.55
const TREBLE_OUT := 0.62
const DOUBLE_IN := 0.92
const MODES := ["shootout", "clock", "301"]
const MODE_NAMES := {"shootout": "SHOOTOUT", "clock": "AROUND THE CLOCK", "301": "301"}
const STAKES := {"shootout": 1, "clock": 2, "301": 4} # shells for a win
const DARTS := 3
const MAX_VISITS := 30 # each, in the long games: then closest wins

var scores := {} # seat -> 301: what's left; clock: the number to hit (21 = the bull); shootout: this visit
var darts_left := 0
var visit: Array = [] # this visit's darts: { x, y, value, num, mult, label }
var visit_start := 0 # 301: the score to go back to on a bust
var contenders: Array = [] # shootout: who's still in (a tie throws again)
var thrown := {} # shootout: who has thrown this pass
var bulls := {} # shootout: seat -> true, hit a bullseye
var visits := {} # seat -> visits thrown this round


func _init() -> void:
	kind = "darts"
	options["trump_cards"] = false
	options["items_per_round"] = 0
	options["items_in_stock"] = false
	options["mode"] = "shootout"


func mode() -> String:
	return str(options.get("mode", "shootout"))


func has_private_hands() -> bool:
	return false


func table_note(seat: int) -> String:
	if not scores.has(seat):
		return ""
	match mode():
		"301":
			return "%d LEFT" % scores[seat]
		"clock":
			return "ON %s" % ("BULL" if int(scores[seat]) > 20 else str(scores[seat]))
	return "%d" % scores[seat] if thrown.has(seat) or seat == turn else ""


## What a dart at (x, y) scores.
static func score_at(x: float, y: float) -> Dictionary:
	var r := sqrt(x * x + y * y)
	if r <= BULL:
		return {"value": 50, "num": 25, "mult": 2, "label": "BULL"}
	if r <= OUTER_BULL:
		return {"value": 25, "num": 25, "mult": 1, "label": "25"}
	if r > 1.0:
		return {"value": 0, "num": 0, "mult": 0, "label": "MISS"}
	var a := fposmod(rad_to_deg(atan2(x, y)) + 9.0, 360.0)
	var num: int = NUMBERS[int(a / 18.0) % 20]
	var mult := 1
	if r >= TREBLE_IN and r <= TREBLE_OUT:
		mult = 3
	elif r >= DOUBLE_IN:
		mult = 2
	return {"value": num * mult, "num": num, "mult": mult, "label": ["", "", "D", "T"][mult] + str(num)}


## The middle of a bed on the board: `ring` is "single" (the fat outer
## single), "inner" (the inner single), "double" or "treble".
static func spot(num: int, ring: String = "single") -> Vector2:
	if num == 25:
		return Vector2.ZERO
	var i := NUMBERS.find(num)
	var a := deg_to_rad(i * 18.0)
	var r: float = {"single": 0.78, "inner": 0.34, "double": 0.96, "treble": 0.585}.get(ring, 0.78)
	return Vector2(sin(a), cos(a)) * r


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
	options["max_shells"] = 2 if mode() == "shootout" else int(STAKES[mode()])
	for p in players:
		p.hand = []
		p.items = []
		p.turns_taken = 0
		p.cuffed = false
		p.exposed = false
		p.ultimatum = false
		p.extra_draws = 0
	stock = []
	discard_pile = []
	melds = []
	burned = []
	item_deck = []
	gun = null
	last_result = {}
	scores = {}
	bulls = {}
	thrown = {}
	visits = {}
	var order := _seats_from(next_alive(dealer))
	for s in order:
		scores[s] = {"301": 301, "clock": 1}.get(mode(), 0)
		visits[s] = 0
	contenders = order.duplicate()
	turn = order[0]
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": 0, "mode": mode()})
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	darts_left = DARTS
	visit = []
	visit_start = int(scores.get(turn, 0))
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


## Which dart of the visit is next: 0, 1 or 2.
func dart_index() -> int:
	return DARTS - darts_left


func throw(seat: int, x: float, y: float) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	if darts_left <= 0:
		return _fail("No darts left.")
	var hit := score_at(x, y)
	hit["x"] = x
	hit["y"] = y
	visit.append(hit)
	darts_left -= 1
	var won := false
	var note := ""
	match mode():
		"shootout":
			scores[seat] = int(scores[seat]) + int(hit["value"])
			if hit["label"] == "BULL":
				bulls[seat] = true
		"301":
			var left := int(scores[seat]) - int(hit["value"])
			if left < 0:
				note = "bust"
				scores[seat] = visit_start
			else:
				scores[seat] = left
				won = left == 0
		"clock":
			var target := int(scores[seat])
			if target > 20:
				won = int(hit["num"]) == 25
			elif int(hit["num"]) == target:
				scores[seat] = mini(21, target + int(hit["mult"]))
				note = "next"
	var d := hit.duplicate()
	d["seat"] = seat
	d["dart"] = DARTS - darts_left - 1
	d["score"] = scores[seat]
	d["note"] = note
	_emit("dart", d)
	if won:
		_finish_round(seat, false)
		return _ok({"hit": hit})
	if note == "bust":
		_emit("bust", {"seat": seat, "score": scores[seat]})
		_end_visit()
		return _ok({"hit": hit})
	if darts_left == 0:
		_end_visit()
	return _ok({"hit": hit})


func _end_visit() -> void:
	var seat := turn
	visits[seat] = int(visits.get(seat, 0)) + 1
	var total := 0
	for h in visit:
		total += int(h["value"])
	_emit("visit_end", {"seat": seat, "total": total, "score": scores[seat]})
	if mode() == "shootout":
		thrown[seat] = true
		for s in _seats_from(_after(seat)):
			if contenders.has(s) and not thrown.has(s) and players[s].alive:
				turn = s
				_begin_turn()
				return
		var best := -1
		for s in contenders:
			if players[s].alive:
				best = maxi(best, int(scores[s]))
		var leaders := []
		for s in contenders:
			if players[s].alive and int(scores[s]) == best:
				leaders.append(s)
		if leaders.size() == 1:
			_finish_round(leaders[0], bulls.has(leaders[0]))
			return
		contenders = leaders
		thrown = {}
		for s in leaders:
			scores[s] = 0
			bulls.erase(s)
		_emit("sudden_death", {"seats": leaders.duplicate(), "score": best})
		turn = leaders[0]
		_begin_turn()
		return
	# the long games: on round, unless everyone's had their fill
	var done := true
	for p in alive_players():
		if int(visits.get(p.seat, 0)) < MAX_VISITS:
			done = false
	if done:
		var best_seat := -1
		for p in alive_players():
			if best_seat < 0 or _progress(p.seat) > _progress(best_seat):
				best_seat = p.seat
		_finish_round(best_seat, false)
		return
	turn = next_alive(seat)
	_begin_turn()


## The next seat after `seat` that's alive (for going round in order).
func _after(seat: int) -> int:
	return next_alive(seat)


## How close a player is to winning a long game (higher is closer).
func _progress(seat: int) -> int:
	return -int(scores[seat]) if mode() == "301" else int(scores[seat])


func _finish_round(w: int, instant: bool) -> void:
	var hands := []
	for p in players:
		if not p.alive:
			continue
		hands.append({"seat": p.seat, "name": p.name, "cards": [], "points": int(scores.get(p.seat, 0))})
	var result := {"round": round_num, "winner": w, "points": 0, "shells": 0, "rummy": false, "hands": hands, "reason": "", "mode": mode(), "instant": instant}
	players[w].rounds_won += 1
	result["shells"] = _shells(instant) if mode() == "shootout" else mini(int(options["max_shells"]), int(STAKES[mode()]))
	last_result = result
	darts_left = 0
	if options["shotgun"]:
		phase = "shoot"
		gun = {"holder": w, "shells": result["shells"], "total": result["shells"]}
	else:
		phase = "round_over"
		gun = null
	_emit("round_end", result)
	_check_normal_match()


func _next_turn() -> void:
	# someone was knocked out on their own turn (only the medicine could do
	# that, and there are no items here): move on
	if phase == "play":
		_end_visit()


func perform_action(seat: int, action: String, args: Array) -> Dictionary:
	if action == "throw" and args.size() == 2:
		return throw(seat, float(args[0]), float(args[1]))
	return _fail("That didn't work.")


# none of the card moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Throw a dart.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Throw a dart.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("Throw a dart.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("Throw a dart.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("Throw a dart.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Throw a dart.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


# ---------------------------------------------------------------- network

func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["scores"] = scores.duplicate()
	d["darts_left"] = darts_left
	d["visit"] = visit.duplicate(true)
	d["contenders"] = contenders.duplicate()
	d["thrown"] = thrown.duplicate()
	d["bulls"] = bulls.duplicate()
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	scores = {}
	for k in d.get("scores", {}):
		scores[int(k)] = int(d["scores"][k])
	darts_left = int(d.get("darts_left", 0))
	visit = d.get("visit", [])
	contenders = d.get("contenders", [])
	thrown = d.get("thrown", {})
	bulls = d.get("bulls", {})
