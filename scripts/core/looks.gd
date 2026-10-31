extends RefCounted
## How a player looks: which base model, outfit colour, hat, face piece and
## glowing eyes. A look is a Dictionary:
##   { "base": "Rogue", "outfit": 1, "hat": "bowler", "face": "cigarette", "eyes": false,
##     "face_side": "left", "face_angle": 0, "face_height": 0 }
## The face_ keys place the face piece: which side (the character's own left
## or right: which eye the patch is on, which corner of the mouth), and its
## angle and height, from -2 to 2.
##
## PRESETS are ready-made characters built from the base models. The customiser
## starts from one and lets players change any part.

## The base models (KayKit, CC0) and their names in the customiser.
const BASES := {
	"Barbarian": "BARBARIAN", "Knight": "KNIGHT", "Mage": "MAGE", "Rogue": "ROGUE",
	"Rogue_Hooded": "HOODED ROGUE", "Skeleton_Warrior": "SKELETON WARRIOR",
	"Skeleton_Mage": "SKELETON MAGE", "Skeleton_Rogue": "SKELETON ROGUE", "Skeleton_Minion": "SKELETON",
}

## Outfit colours. Index 0 keeps the model's own colours.
const OUTFITS := [
	{"name": "ORIGINAL", "color": Color(1, 1, 1)},
	{"name": "BLOOD", "color": Color(0.85, 0.25, 0.22)},
	{"name": "MOSS", "color": Color(0.45, 0.62, 0.32)},
	{"name": "SLATE", "color": Color(0.5, 0.58, 0.7)},
	{"name": "MUSTARD", "color": Color(0.9, 0.72, 0.3)},
	{"name": "PLUM", "color": Color(0.6, 0.38, 0.65)},
	{"name": "COAL", "color": Color(0.32, 0.3, 0.3)},
	{"name": "BONE", "color": Color(0.95, 0.9, 0.78)},
]

## "own" = the model's own hat, helmet or hood (if it has one).
const HATS := {
	"own": "THEIR OWN", "none": "NONE", "bowler": "BOWLER", "top_hat": "TOP HAT",
	"cowboy": "COWBOY HAT", "flat_cap": "FLAT CAP", "beanie": "BEANIE",
}

const FACES := {"none": "NONE", "cigarette": "CIGARETTE", "cigar": "CIGAR", "eyepatch": "EYEPATCH", "shades": "SHADES"}

const PRESETS := [
	{"name": "THE BRUTE", "base": "Barbarian", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE GAMBLER", "base": "Rogue", "outfit": 1, "hat": "bowler", "face": "cigarette", "eyes": false},
	{"name": "THE UNDERTAKER", "base": "Skeleton_Minion", "outfit": 6, "hat": "top_hat", "face": "none", "eyes": true},
	{"name": "THE HOOD", "base": "Rogue_Hooded", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE COWPOKE", "base": "Barbarian", "outfit": 4, "hat": "cowboy", "face": "cigar", "eyes": false},
	{"name": "BONES", "base": "Skeleton_Warrior", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE BOOTLEGGER", "base": "Knight", "outfit": 3, "hat": "flat_cap", "face": "cigarette", "eyes": false},
	{"name": "THE CONJURER", "base": "Mage", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE PIRATE", "base": "Skeleton_Rogue", "outfit": 1, "hat": "none", "face": "eyepatch", "eyes": false},
	{"name": "THE KNIGHT", "base": "Knight", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE FORTUNE TELLER", "base": "Mage", "outfit": 5, "hat": "own", "face": "none", "eyes": true},
	{"name": "THE DRIFTER", "base": "Rogue", "outfit": 2, "hat": "cowboy", "face": "shades", "eyes": false},
	{"name": "THE LICH", "base": "Skeleton_Mage", "outfit": 0, "hat": "own", "face": "none", "eyes": true},
	{"name": "THE HUSTLER", "base": "Barbarian", "outfit": 5, "hat": "flat_cap", "face": "shades", "eyes": false},
	{"name": "THE GHOUL", "base": "Skeleton_Warrior", "outfit": 7, "hat": "beanie", "face": "cigarette", "eyes": true},
	{"name": "THE CREEP", "base": "Skeleton_Rogue", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "THE DEALER", "base": "Skeleton_Mage", "outfit": 6, "hat": "top_hat", "face": "cigar", "eyes": true},
	{"name": "THE ROGUE", "base": "Rogue", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
	{"name": "MINION", "base": "Skeleton_Minion", "outfit": 0, "hat": "own", "face": "none", "eyes": false},
]


static func preset(index: int) -> Dictionary:
	var p: Dictionary = PRESETS[posmod(index, PRESETS.size())].duplicate()
	return p


## The default look for a seat, so players who haven't picked still differ.
static func for_seat(seat: int) -> Dictionary:
	return preset(seat * 3)


## A look from anywhere (settings, the network) made safe: unknown parts are
## replaced with defaults.
static func clean(look, fallback_seat: int = 0) -> Dictionary:
	var out := for_seat(fallback_seat)
	if not (look is Dictionary):
		return out
	if BASES.has(look.get("base", "")):
		out["base"] = look["base"]
	var outfit := int(look.get("outfit", 0))
	if outfit >= 0 and outfit < OUTFITS.size():
		out["outfit"] = outfit
	if HATS.has(look.get("hat", "")):
		out["hat"] = look["hat"]
	if FACES.has(look.get("face", "")):
		out["face"] = look["face"]
	out["eyes"] = bool(look.get("eyes", false))
	# where the face piece sits: which side (the character's own), its angle
	# and its height, each a few steps either way
	out["face_side"] = "right" if str(look.get("face_side", "left")) == "right" else "left"
	out["face_angle"] = clampi(int(look.get("face_angle", 0)), -2, 2)
	out["face_height"] = clampi(int(look.get("face_height", 0)), -2, 2)
	out["name"] = str(look.get("name", "CUSTOM")).left(24)
	return out
