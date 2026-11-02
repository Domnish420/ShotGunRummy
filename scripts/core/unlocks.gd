extends RefCounted
## What's yours. Some character parts, the classic cards and the standard
## shotgun are free; everything else comes out of the gacha machine (see
## gacha.gd). `owned` is the set of gacha keys you've won.
##
## Your stats are still counted (saved with your settings, for your seat
## only, never in a demo):
##   matches      matches finished
##   match_wins   matches won (last one standing)
##   round_wins   rounds won
##   shells_hit   shotgun shells you fired that hit
##   knockouts    players you took out with the shotgun
##   games_tried  different cartridges you've finished a match of

const Looks = preload("res://scripts/core/looks.gd")
const Gacha = preload("res://scripts/core/gacha.gd")

const STATS := ["matches", "match_wins", "round_wins", "shells_hit", "knockouts", "games_tried"]

## Before the gacha machine, parts unlocked from your stats. Anyone who had
## earned one keeps it (see legacy_owned): part -> value -> [stat, how many].
const LEGACY := {
	"base": {
		"Mage": ["matches", 3],
		"Rogue_Hooded": ["match_wins", 1],
		"Skeleton_Warrior": ["round_wins", 10],
		"Skeleton_Rogue": ["shells_hit", 10],
		"Skeleton_Mage": ["match_wins", 5],
	},
	"hat": {
		"flat_cap": ["matches", 2],
		"beanie": ["round_wins", 3],
		"cowboy": ["match_wins", 3],
		"top_hat": ["games_tried", 5],
	},
	"face": {
		"shades": ["round_wins", 5],
		"cigar": ["match_wins", 2],
		"eyepatch": ["knockouts", 5],
	},
	"outfit": {
		4: ["matches", 5],
		5: ["round_wins", 15],
		6: ["knockouts", 10],
		7: ["match_wins", 8],
	},
	"eyes": {
		true: ["shells_hit", 25],
	},
	"card": {
		"felt": ["matches", 1],
		"blood": ["shells_hit", 5],
		"pumpkin": ["games_tried", 3],
		"bone": ["knockouts", 3],
		"noir": ["round_wins", 8],
		"rave": ["match_wins", 4],
		"gold": ["match_wins", 10],
		"candy": ["round_wins", 3],
		"wire": ["shells_hit", 15],
		"midnight": ["matches", 10],
		"blueprint": ["matches", 20],
		"wanted": ["knockouts", 15],
		"web": ["round_wins", 25],
		"hazard": ["shells_hit", 50],
		"gameboy": ["games_tried", 9],
		"overworld": ["matches", 2],
		"paddle": ["matches", 5],
		"missing": ["games_tried", 4],
		"diamond": ["round_wins", 12],
		"lava": ["knockouts", 8],
		"dust": ["knockouts", 20],
		"teams": ["match_wins", 6],
		"bricks": ["round_wins", 20],
		"test": ["matches", 15],
		"cheat": ["round_wins", 30],
		"crowbar": ["shells_hit", 30],
		"rings": ["matches", 25],
		"maze": ["games_tried", 6],
		"lineclear": ["matches", 30],
		"goldcart": ["match_wins", 15],
		"shareware": ["shells_hit", 75],
		"dungeon": ["knockouts", 30],
		"invaders": ["shells_hit", 100],
	},
}


static func is_unlocked(part: String, value, owned: Dictionary) -> bool:
	return Gacha.owns(part, value, owned)


## "GACHA · RARE", or "" if it's yours.
static func need_text(part: String, value, owned: Dictionary) -> String:
	if is_unlocked(part, value, owned):
		return ""
	return "GACHA · %s" % Gacha.RARITY_NAMES[Gacha.rarity(part, value)]


## The parts of `look` you don't own yet, as [part, value] pairs.
static func locked_parts(look: Dictionary, owned: Dictionary) -> Array:
	var out := []
	for part in ["base", "hat", "face", "outfit"]:
		if not is_unlocked(part, look.get(part), owned):
			out.append([part, look.get(part)])
	if bool(look.get("eyes", false)) and not is_unlocked("eyes", true, owned):
		out.append(["eyes", true])
	return out


static func look_unlocked(look: Dictionary, owned: Dictionary) -> bool:
	return locked_parts(look, owned).is_empty()


## What a part is called on screen.
static func part_name(part: String, value) -> String:
	return Gacha.prize_name(Gacha.key(part, value))


## The gacha keys someone's old stats had already unlocked.
static func legacy_owned(stats: Dictionary) -> Dictionary:
	var out := {}
	for part in LEGACY:
		for value in LEGACY[part]:
			var r: Array = LEGACY[part][value]
			if int(stats.get(r[0], 0)) >= int(r[1]):
				out[Gacha.key(part, value)] = true
	return out


## A stats dictionary with every stat present.
static func clean_stats(raw) -> Dictionary:
	var out := {}
	for s in STATS:
		out[s] = maxi(0, int(raw.get(s, 0))) if raw is Dictionary else 0
	return out
