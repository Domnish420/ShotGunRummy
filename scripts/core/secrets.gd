extends RefCounted
## The computer in the corner of the room boots once you've finished a match
## of every game. Its arcade stick takes codes (up, down, left, right, A, B),
## old-school cheat style. Each code unlocks secret skins that never come out
## of the gacha machine, an easter egg (a fun effect you can switch on and
## off), or both.
##
## A found code is kept in `owned` (as "code:<id>"), with its prizes, so it
## saves with everything else you've won. Easter eggs are "egg:<id>" keys.
##
## Codes are written with U D L R A B. No code ends with another code (see
## suffix_free), so typing one can never fire a different one by accident.

const CODES := [
	{"id": "konami", "code": "UUDDLRLRBA", "name": "THE CODE",
		"prizes": ["gun:spreadshot"],
		"message": "30 LIVES! Well, no. But here's a shotgun with a spread.",
		"hint": "The most famous code in gaming, from Gradius (1986). Up first, and it ends B, A."},
	{"id": "disco", "code": "UDUDLRLRAA", "name": "DISCO INFERNO",
		"prizes": ["egg:disco", "outfit:12"],
		"message": "The lamp has a new job. Everybody dance!",
		"hint": "Get up, get down, get up, get down, side to side, side to side, then double A to drop the beat."},
	{"id": "pocket", "code": "LLRRBBAA", "name": "POCKET MODE",
		"prizes": ["egg:pocket"],
		"message": "Four shades of green, like it's 1989.",
		"hint": "Left foot twice, right foot twice, then B twice and A twice. Batteries not included."},
	{"id": "confetti", "code": "AAAAUUUU", "name": "PARTY POPPERS",
		"prizes": ["egg:confetti"],
		"message": "Shots now come with confetti. Still hurts, though.",
		"hint": "Mash A four times, then point up four times, like pulling a party popper."},
	{"id": "noir", "code": "DDDDBBBB", "name": "FILM NOIR",
		"prizes": ["egg:noir"],
		"message": "It was a dark and stormy night. In black and white.",
		"hint": "Everything goes down: down four times, then B four times, for black and white."},
	{"id": "turbo", "code": "RRRRAAAA", "name": "TURBO",
		"prizes": ["egg:turbo"],
		"message": "The AIs have had too much coffee.",
		"hint": "Hold right on the stick (four times) and hammer A (four times). Turbo button!"},
	{"id": "cake", "code": "UBABDABA", "name": "THE CAKE",
		"prizes": ["card:cake"],
		"message": "The cake is a lie. The cards are real, though.",
		"hint": "At the end of the test there's cake: up, B, A, B, then down, A, B, A."},
	{"id": "devroom", "code": "LDRULDRU", "name": "DEV ROOM",
		"prizes": ["card:devroom"],
		"message": "You found the developers' room. Mind the orange walls.",
		"hint": "Spin the stick round twice, starting left and going down: left, down, right, up, and again."},
	{"id": "glitch", "code": "BBBBBBBB", "name": "GLITCH CITY",
		"prizes": ["card:glitch", "outfit:13"],
		"message": "Something's wrong with the cards. Keep them.",
		"hint": "Press B eight times. It shouldn't do anything. It does."},
	{"id": "propeller", "code": "UUUUUUUU", "name": "UP AND AWAY",
		"prizes": ["hat:propeller"],
		"message": "A hat that wants to fly.",
		"hint": "Up, up, up and away: eight ups in a row."},
	{"id": "rainbow", "code": "RLRLRLRL", "name": "RAINBOW ROAD",
		"prizes": ["gun:rainbow"],
		"message": "No guard rails on this one.",
		"hint": "Wiggle all the way round the rainbow: right, left, right, left, four times, right first."},
	{"id": "party", "code": "ABABUDUD", "name": "PARTY HAT",
		"prizes": ["hat:party"],
		"message": "The rarest hat in old-school online gaming. Now yours.",
		"hint": "Pop the cracker (A, B, A, B), then hat on, hat off (up, down, up, down)."},
	{"id": "halo", "code": "UAUAUAUA", "name": "RING WORLD",
		"prizes": ["hat:halo"],
		"message": "A ring of light. Very holy. Very loaded.",
		"hint": "Reach for the ring: up, A, four times over."},
	{"id": "ghost", "code": "DLDLDLDL", "name": "GHOST GUN",
		"prizes": ["gun:ghost"],
		"message": "It's here. Then it isn't.",
		"hint": "Sneak through the wall like a ghost: down, left, four times over."},
]

## Easter eggs: switch them on and off at the computer once found.
const EGGS := {
	"disco": {"name": "DISCO LAMP", "text": "The lamp over the table cycles through the colours."},
	"pocket": {"name": "POCKET MODE", "text": "The whole screen in four shades of handheld green."},
	"confetti": {"name": "PARTY POPPERS", "text": "Every shotgun blast bursts into confetti."},
	"noir": {"name": "FILM NOIR", "text": "Black and white, like an old detective film."},
	"turbo": {"name": "TURBO", "text": "The AIs take their turns twice as fast."},
}

const BUTTONS := ["U", "D", "L", "R", "A", "B"]
const MAX_INPUT := 12 # the longest code is 10; the screen shows the last 12 presses


static func code_by_id(id: String) -> Dictionary:
	for c in CODES:
		if c["id"] == id:
			return c
	return {}


## Every prize that only a code gives.
static func secret_prizes() -> Dictionary:
	var out := {}
	for c in CODES:
		for p in c["prizes"]:
			if not str(p).begins_with("egg:"):
				out[p] = c["id"]
	return out


static func is_secret(k: String) -> bool:
	return secret_prizes().has(k)


## The code `presses` ends with, or {} if none. Already-found codes still
## match (so you can show off), but give nothing new.
static func match_input(presses: String) -> Dictionary:
	for c in CODES:
		if presses.ends_with(c["code"]):
			return c
	return {}


## Is it one of our codes, or could it still turn into one?
static func is_prefix_of_code(presses: String) -> bool:
	for c in CODES:
		for n in range(1, mini(presses.length(), str(c["code"]).length()) + 1):
			if str(c["code"]).begins_with(presses.right(n)):
				return true
	return false


## No code ends with another: typing one never fires another early.
static func suffix_free() -> bool:
	for a in CODES:
		for b in CODES:
			if a != b and str(a["code"]).ends_with(b["code"]):
				return false
	return true


## The codes you've found.
static func found(owned: Dictionary) -> Array:
	var out := []
	for c in CODES:
		if owned.has("code:" + c["id"]):
			out.append(c["id"])
	return out


## Enter a code: what it gives you that you don't have yet. Marks it found.
static func redeem(code: Dictionary, owned: Dictionary) -> Array:
	var fresh := []
	owned["code:" + code["id"]] = true
	for p in code["prizes"]:
		if not owned.has(p):
			owned[p] = true
			fresh.append(p)
	return fresh


static func egg_found(id: String, owned: Dictionary) -> bool:
	return owned.has("egg:" + id)


## The computer boots once you've finished a match of every game.
static func computer_unlocked(tried: Dictionary, kinds: Array) -> bool:
	return missing_games(tried, kinds).is_empty()


static func missing_games(tried: Dictionary, kinds: Array) -> Array:
	var out := []
	for k in kinds:
		if not tried.has(k):
			out.append(k)
	return out


## U D L R A B as arrows and letters for the screen.
static func pretty(presses: String) -> String:
	var map := {"U": "▲", "D": "▼", "L": "◀", "R": "▶", "A": "A", "B": "B"}
	var parts := []
	for ch in presses:
		parts.append(map.get(ch, ch))
	return " ".join(parts)
