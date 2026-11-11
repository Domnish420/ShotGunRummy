extends RefCounted
## An AI player's hand in TIMBER. It plays like a person does: picks a block,
## nudges it with a finger, and feels for trouble. If the block won't give or
## the tower starts to sway, it backs off and tries another. A loose one it
## pushes on through until it drops out the far side. How careful it is
## depends on its level:
##   easy:   pushes fast, barely checks, gives up on nothing
##   normal: probes gently, backs off when the tower moves
##   hard:   slow and fussy, tries more blocks, favours middles low down
## The same driver steps every physics frame (step) until the block's out.

const LEVEL := {
	"easy": {"speed": 0.2, "probe": 0.012, "tolerance": 0.03, "tries": 1, "strain": 0.03},
	"normal": {"speed": 0.11, "probe": 0.02, "tolerance": 0.009, "tries": 4, "strain": 0.016},
	"hard": {"speed": 0.07, "probe": 0.025, "tolerance": 0.005, "tries": 7, "strain": 0.012},
}

var tower # tower3d.gd
var hand # hand3d.gd
var level := "normal"
var rng := RandomNumberGenerator.new()
var state := "pick" # pick | approach | push | retract | done
var block: RigidBody3D = null
var _tried := {} # block -> how much the tower moved when it was tried
var _tries := 0
var _from := Vector3.ZERO # where the fingertip started
var _axis := Vector3.ZERO
var _depth := 0.0 # how far in the fingertip has gone
var _top0 := Vector3.ZERO # the top block when this push began
var _wait := 0.0
var _forced := false # out of patience: this one's going whatever


func _init(t, h, lvl: String, seed_value: int = -1) -> void:
	tower = t
	hand = h
	level = lvl if LEVEL.has(lvl) else "normal"
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func start_turn() -> void:
	state = "pick"
	block = null
	_tried = {}
	_tries = 0
	_forced = false
	_wait = 0.5


func _cfg(k: String) -> float:
	return float(LEVEL[level][k])


## Which block next: middles first (they're the loose ones more often), the
## hard AI low down where the tower's heaviest above (looser middles), the
## easy one anywhere.
func _pick() -> RigidBody3D:
	var options := []
	for b in tower.blocks:
		if tower.takeable(b) and not _tried.has(b):
			options.append(b)
	if options.is_empty():
		return null
	options.shuffle()
	if level == "easy":
		return options[rng.randi() % options.size()]
	var best: RigidBody3D = null
	var best_score := -1e9
	for b in options:
		var score := rng.randf() * 3.0
		if int(b.get_meta("slot")) == 1:
			score += 5.0
		if level == "hard":
			score -= int(b.get_meta("layer")) * 0.15
		if score > best_score:
			best_score = score
			best = b
	return best


## The least troublesome block it's tried (when it's out of patience).
func _least_bad() -> RigidBody3D:
	var best: RigidBody3D = null
	for b in _tried:
		if is_instance_valid(b) and tower.takeable(b) and (best == null or _tried[b] < _tried[best]):
			best = b
	return best


## One physics frame. Returns "out" when the block's clear of the tower.
func step(delta: float) -> String:
	if _wait > 0.0:
		_wait -= delta
		return ""
	match state:
		"pick":
			block = null
			if _tries >= int(_cfg("tries")):
				block = _least_bad()
				_forced = true
			if block == null:
				block = _pick()
			if block == null:
				block = _least_bad()
				_forced = true
			if block == null:
				return ""
			_tries += 1
			hand.boost = 1.0
			tower.set_active(block)
			_axis = tower.block_axis(block)
			# push from whichever end is nearer the front, like you would
			if rng.randf() < 0.5:
				_axis = -_axis
			_from = block.global_position - _axis * (tower.L * 0.5 + 0.025)
			hand.set_tool("poke" if level != "easy" or rng.randf() < 0.6 else "two")
			hand.show_hand()
			hand.jump_to(_from, _axis)
			_depth = 0.0
			_top0 = _top()
			state = "push"
			_wait = 0.3
		"push":
			var speed := _cfg("speed")
			if _depth < _cfg("probe"):
				speed *= 0.6 # feeling it out
			_depth += speed * delta
			hand.target = _from + _axis * _depth
			if tower.is_out(block):
				hand.target = _from + _axis * (_depth - 0.05)
				state = "done"
				return "out"
			var moved := _top().distance_to(_top0)
			var strain: float = (hand.target - hand.tip.global_position).length()
			var committed: bool = _depth > tower.L * 0.5 # more than halfway: finish it
			if not _forced and not committed and _depth > 0.006 and (moved > _cfg("tolerance") or strain > _cfg("strain")):
				# it's tight, or the tower's going with it: ease off
				_tried[block] = moved + strain
				state = "retract"
			elif _forced and strain > _cfg("strain"):
				# no good options left: lean on it harder and hope
				hand.boost = minf(hand.boost + delta * 1.0, 3.0)
				_depth -= speed * delta * 0.7 # don't let the target run away
			elif _depth > tower.L + 0.06:
				# pushed right through and it's still hanging on: lift off
				_tried[block] = 1.0
				state = "retract"
		"retract":
			if tower.is_out(block):
				# it fell out after all (pushed far enough before we let go)
				state = "done"
				return "out"
			_depth -= 0.15 * delta
			hand.target = _from + _axis * _depth
			if _depth <= 0.0:
				tower.set_active(null)
				state = "pick"
				_wait = 0.25
	return ""


func _top() -> Vector3:
	var best := Vector3.ZERO
	for b in tower.blocks:
		if not tower.removed.has(b) and b != block and b.global_position.y > best.y:
			best = b.global_position
	return best
