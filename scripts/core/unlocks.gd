extends RefCounted
## What you unlock by playing. Some character parts and card skins are free;
## the rest unlock as your stats grow. Everything here is data: change a
## number to make something easier or harder to get.
##
## Stats (saved with your settings, counted for your seat only, never in a
## demo):
##   matches      matches finished
##   match_wins   matches won (last one standing)
##   round_wins   rounds won
##   shells_hit   shotgun shells you fired that hit
##   knockouts    players you took out with the shotgun
##   games_tried  different cartridges you've finished a match of

const Looks = preload("res://scripts/core/looks.gd")

const STATS := ["matches", "match_wins", "round_wins", "shells_hit", "knockouts", "games_tried"]

## How each stat reads on a locked part: [one, many].
const WORDS := {
	"matches": ["PLAY %d MATCH", "PLAY %d MATCHES"],
	"match_wins": ["WIN %d MATCH", "WIN %d MATCHES"],
	"round_wins": ["WIN %d ROUND", "WIN %d ROUNDS"],
	"shells_hit": ["HIT %d SHELL", "HIT %d SHELLS"],
	"knockouts": ["TAKE OUT %d PLAYER", "TAKE OUT %d PLAYERS"],
	"games_tried": ["PLAY %d CARTRIDGE", "PLAY %d DIFFERENT CARTRIDGES"],
}

## part -> value -> [stat, how many]. Anything not listed is free.
const RULES := {
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
	},
}


static func rule(part: String, value) -> Array:
	return RULES.get(part, {}).get(value, [])


static func is_unlocked(part: String, value, stats: Dictionary) -> bool:
	var r := rule(part, value)
	return r.is_empty() or int(stats.get(r[0], 0)) >= int(r[1])


## "WIN 3 MATCHES (1/3)", or "" if it's free or already yours.
static func need_text(part: String, value, stats: Dictionary) -> String:
	if is_unlocked(part, value, stats):
		return ""
	var r := rule(part, value)
	var n := int(r[1])
	var words: Array = WORDS[r[0]]
	return (words[0] if n == 1 else words[1]) % n + " (%d/%d)" % [mini(int(stats.get(r[0], 0)), n), n]


## The parts of `look` that are still locked, as [part, value] pairs.
static func locked_parts(look: Dictionary, stats: Dictionary) -> Array:
	var out := []
	for part in ["base", "hat", "face", "outfit"]:
		if not is_unlocked(part, look.get(part), stats):
			out.append([part, look.get(part)])
	if bool(look.get("eyes", false)) and not is_unlocked("eyes", true, stats):
		out.append(["eyes", true])
	return out


static func look_unlocked(look: Dictionary, stats: Dictionary) -> bool:
	return locked_parts(look, stats).is_empty()


## What a part is called on screen.
static func part_name(part: String, value) -> String:
	match part:
		"base":
			return str(Looks.BASES.get(value, value))
		"hat":
			return str(Looks.HATS.get(value, value))
		"face":
			return str(Looks.FACES.get(value, value))
		"outfit":
			return "%s OUTFIT" % Looks.OUTFITS[int(value)]["name"]
		"eyes":
			return "GLOWING EYES"
		"card":
			var CardSkins = load("res://scripts/ui/card_skins.gd")
			return "%s CARDS" % CardSkins.skin_name(str(value))
	return str(value)


## Everything that unlocks going from `before` to `after`, as names.
static func newly_unlocked(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for part in RULES:
		for value in RULES[part]:
			if not is_unlocked(part, value, before) and is_unlocked(part, value, after):
				out.append(part_name(part, value))
	return out


## A stats dictionary with every stat present.
static func clean_stats(raw) -> Dictionary:
	var out := {}
	for s in STATS:
		out[s] = maxi(0, int(raw.get(s, 0))) if raw is Dictionary else 0
	return out
