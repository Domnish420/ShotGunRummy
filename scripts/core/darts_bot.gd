extends RefCounted
## AI players for Shotgun Darts (bot.gd hands over to this one).
##
## An AI aims like a person does: it picks a spot, then stops the dot on two
## lines through the board, a little early or late each time. How early or
## late is down to its level, and the dot gets quicker with each dart of the
## visit, just as it does for you.
##   easy:   aims at the big beds, and its timing is loose.
##   normal: goes for the treble 20 and checks out sensibly in 301.
##   hard:   tight timing, and it plays the checkout and the clock smartly.

const Darts = preload("res://scripts/core/darts.gd")

const WOBBLE := {"easy": 0.3, "normal": 0.16, "hard": 0.085}


static func next_action(game, seat: int, level: String, _memory: Dictionary) -> Array:
	var aim := choose_aim(game, seat, level)
	var land := wobble(game, aim, level)
	return ["throw", [land.x, land.y]]


## Where it's aiming (board radii).
static func choose_aim(game, seat: int, level: String) -> Vector2:
	var score: int = int(game.scores.get(seat, 0))
	match game.mode():
		"clock":
			if score > 20:
				return Vector2.ZERO
			if level == "hard" and score <= 18:
				return Darts.spot(score, "treble")
			return Darts.spot(score, "single")
		"301":
			if level != "easy":
				var out := checkout(score)
				if out != Vector2.INF:
					return out
			if score < 60 and level != "easy":
				# set up a finish: something that leaves an easy number
				return Darts.spot(mini(20, maxi(1, score - 20)), "single")
			return Darts.spot(20, "treble") if level != "easy" else Darts.spot(20, "single")
	# shootout
	if level == "easy":
		return Darts.spot(20, "single")
	if level == "hard" and game.dart_index() == 2 and _behind(game, seat) > 30:
		return Vector2.ZERO # need a big one: go for the bull
	return Darts.spot(20, "treble")


## A spot that finishes `left` in one dart, or Vector2.INF.
static func checkout(left: int) -> Vector2:
	if left == 50:
		return Vector2.ZERO
	if left == 25:
		return Vector2(0, 0.1)
	if left <= 20 and left > 0:
		return Darts.spot(left, "single")
	if left <= 40 and left % 2 == 0:
		return Darts.spot(left / 2, "double")
	if left <= 60 and left % 3 == 0:
		return Darts.spot(left / 3, "treble")
	return Vector2.INF


## Shootout: how far behind the best visit so far.
static func _behind(game, seat: int) -> int:
	var best := 0
	for s in game.thrown:
		if game.contenders.has(s):
			best = maxi(best, int(game.scores[s]))
	return best - int(game.scores.get(seat, 0))


## Where the dart lands: two lines through the aim at random angles, and on
## each the dot stopped a bit off. Quicker dots, bigger misses.
static func wobble(game, aim: Vector2, level: String) -> Vector2:
	var sigma: float = WOBBLE.get(level, 0.16) * (1.0 + 0.22 * game.dart_index())
	var a1: float = game.rng.randf() * PI
	var a2: float = a1 + deg_to_rad(game.rng.randf_range(40.0, 140.0))
	var e1: float = game.rng.randfn(0.0, sigma)
	var e2: float = game.rng.randfn(0.0, sigma)
	return aim + Vector2(cos(a1), sin(a1)) * e1 + Vector2(cos(a2), sin(a2)) * e2
