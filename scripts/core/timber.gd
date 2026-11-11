extends "res://scripts/core/game.gd"
## TIMBER: the tower game, at the party room table. The first board game, so
## the first with the board-game rule: no health, no items. Bring the tower
## down and you're shot, and one shot puts you out. Last one standing wins.
##
## - Players take turns round to the left. Whoever's turn it is has the
##   shotgun in front of them; it moves left with the turn.
## - On your turn, take one block from anywhere below the top (not the top
##   layer, nor the one under it while the top's unfinished) and it's laid
##   on top. Then it's the next player's go.
## - Bring the tower down and the shotgun goes to the player on your right,
##   who shoots you. You're out. The tower's built again and the player on
##   your left goes first. Always.
##
## The physics (the tower, the hand) live in the 3D scene; this only keeps
## the turns and the shotgun. The table screen reports what happened with
## "placed" (the block's out and laid on top) or "toppled".

var turns := 0 # blocks taken this round
var next_first := -1 # who starts the next round (left of whoever brought it down)
var last_toppler := -1


func _init() -> void:
	kind = "timber"
	options["trump_cards"] = false
	options["items_per_round"] = 0
	options["items_in_stock"] = false
	options["max_hp"] = 1 # board games: one shot and you're out
	options["max_shells"] = 1


func has_private_hands() -> bool:
	return false


func table_note(seat: int) -> String:
	return "HAS THE GUN" if seat == turn and phase == "play" else ""


func setup(names: Array, opts: Dictionary = {}, rng_seed: int = -1) -> void:
	super.setup(names, opts, rng_seed)
	for p in players:
		p.max_hp = 1
		p.hp = 1


func reset_match() -> void:
	super.reset_match()
	next_first = -1
	last_toppler = -1
	for p in players:
		p.max_hp = 1
		p.hp = 1


func start_round() -> Dictionary:
	if phase == "match_over":
		return _fail("The match is over.")
	if phase != "idle" and phase != "round_over":
		return _fail("A round is already in progress.")
	Items.mode = kind
	round_num += 1
	dealer = prev_alive(0) if dealer < 0 else dealer
	trump_rank = 0
	for p in players:
		p.hand = []
		p.items = []
		p.turns_taken = 0
		p.cuffed = false
	stock = []
	discard_pile = []
	melds = []
	burned = []
	item_deck = []
	gun = null
	last_result = {}
	turns = 0
	if next_first >= 0 and players[next_first].alive:
		turn = next_first
	elif next_first >= 0:
		turn = next_alive(next_first)
	else:
		turn = next_alive(dealer)
	_emit("round_start", {"round": round_num, "dealer": dealer, "first": turn, "trump": 0})
	_begin_turn()
	return _ok()


func _begin_turn() -> void:
	phase = "play"
	items_used_this_turn = 0
	current().turns_taken += 1
	_emit("turn_start", {"seat": turn})


## The block's out and laid on top, and the tower stood: next player.
func placed(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	turns += 1
	_emit("placed", {"seat": seat, "turns": turns})
	turn = next_alive(seat)
	_begin_turn()
	return _ok()


## The tower came down on `seat`'s turn.
func toppled(seat: int) -> Dictionary:
	var err := _guard(seat, "play")
	if err != "":
		return _fail(err)
	last_toppler = seat
	var shooter := prev_alive(seat) # the player on their right
	next_first = next_alive(seat) # the player on their left goes next. Always.
	var result := {"round": round_num, "winner": shooter, "loser": seat, "points": 0, "shells": 1, "rummy": false, "hands": [], "reason": "toppled", "turns": turns}
	last_result = result
	_emit("timber", {"seat": seat, "shooter": shooter, "turns": turns})
	if options["shotgun"]:
		phase = "shoot"
		gun = {"holder": shooter, "shells": 1, "total": 1, "targets": [seat]}
		_emit("round_end", result)
	else:
		# no shotgun: you're just out
		phase = "round_over"
		gun = null
		_emit("round_end", result)
		damage(seat, players[seat].hp, "timber")
	return _ok()


## Only the one who brought it down can be shot.
func shoot(shooter: int, target: int) -> Dictionary:
	if gun != null and gun.has("targets") and not gun["targets"].has(target):
		return _fail("Only %s brought the tower down." % players[int(gun["targets"][0])].name)
	return super.shoot(shooter, target)


func perform_action(seat: int, action: String, _args: Array) -> Dictionary:
	match action:
		"placed":
			return placed(seat)
		"toppled":
			return toppled(seat)
	return _fail("That didn't work.")


# none of the card moves exist here
func draw_stock(_seat: int) -> Dictionary:
	return _fail("Take a block.")


func draw_discard(_seat: int) -> Dictionary:
	return _fail("Take a block.")


func meld(_seat: int, _ids: Array) -> Dictionary:
	return _fail("Take a block.")


func lay_off(_seat: int, _ids: Array, _meld_id: String) -> Dictionary:
	return _fail("Take a block.")


func swap_trump(_seat: int, _meld_id: String, _natural_id: String, _trump_id: String, _rest_ids: Array) -> Dictionary:
	return _fail("Take a block.")


func discard(_seat: int, _card_id: String) -> Dictionary:
	return _fail("Take a block.")


func can_place(_seat: int) -> bool:
	return false


func go_out_check(_seat: int) -> Dictionary:
	return {"can": false, "rummy": false}


func _next_turn() -> void:
	# someone was knocked out on their own turn: on to the next
	if phase == "play":
		turn = next_alive(turn)
		_begin_turn()


func snapshot(view_seat: int) -> Dictionary:
	var d := super.snapshot(view_seat)
	d["turns"] = turns
	d["next_first"] = next_first
	return d


func load_snapshot(d: Dictionary) -> void:
	super.load_snapshot(d)
	turns = int(d.get("turns", 0))
	next_first = int(d.get("next_first", -1))
