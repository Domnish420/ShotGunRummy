extends RefCounted
## The gacha machine. Winning earns gacha coins (a coin for every round you
## win, a bonus coin for winning the match); each coin buys one spin, and
## the machine drops something you don't own yet: a card skin, a shotgun skin
## or a costume part. Rarer things drop less often.
##
## A prize is a key "part:value", e.g. "card:gold", "gun:neon", "hat:cowboy",
## "outfit:4", "eyes:true". Everything not in the machine is free from the
## start.

const Looks = preload("res://scripts/core/looks.gd")
const GunSkins = preload("res://scripts/core/gun_skins.gd")

const COIN_PER_ROUND := 1
const COIN_PER_MATCH := 1 # on top of the round
const STARTING_COINS := 3 # a few spins to try it out

const RARITIES := ["common", "rare", "epic", "legendary"]
const WEIGHTS := {"common": 60.0, "rare": 28.0, "epic": 10.0, "legendary": 2.0}
const RARITY_NAMES := {"common": "COMMON", "rare": "RARE", "epic": "EPIC", "legendary": "LEGENDARY"}
const RARITY_COLORS := {
	"common": Color(0.75, 0.75, 0.72),
	"rare": Color(0.35, 0.65, 1.0),
	"epic": Color(0.75, 0.4, 1.0),
	"legendary": Color(1.0, 0.75, 0.2),
}

## Everything in the machine, and how rare it is. Card skins come from
## card_skins.gd (classic is free): see CARD_RARITY.
const COSTUMES := {
	"base:Mage": "common", "base:Rogue_Hooded": "common", "base:Skeleton_Warrior": "rare",
	"base:Skeleton_Rogue": "rare", "base:Skeleton_Mage": "epic",
	"hat:flat_cap": "common", "hat:beanie": "common", "hat:cowboy": "rare", "hat:top_hat": "epic",
	"face:shades": "common", "face:cigar": "rare", "face:eyepatch": "rare",
	"outfit:4": "common", "outfit:5": "common", "outfit:6": "rare", "outfit:7": "rare",
	"eyes:true": "epic",
}

const GUNS := {
	"gun:rust": "common", "gun:blackout": "common", "gun:swamp": "common",
	"gun:chrome": "rare", "gun:bone": "rare", "gun:candy": "rare",
	"gun:blood": "epic", "gun:neon": "epic", "gun:toxic": "epic",
	"gun:gold": "legendary",
}

## Card skins not listed here are common (retro decks default to rare).
const CARD_RARITY := {
	"card:noir": "rare", "card:rave": "rare", "card:blueprint": "rare", "card:web": "rare", "card:hazard": "rare", "card:gameboy": "rare",
	"card:gold": "legendary",
	"card:test": "epic", "card:crowbar": "epic", "card:cheat": "epic", "card:goldcart": "epic", "card:invaders": "epic", "card:missing": "epic",
}


static func key(part: String, value) -> String:
	if value is bool:
		return "%s:%s" % [part, "true" if value else "false"]
	return "%s:%s" % [part, str(value)]


## Every prize in the machine -> its rarity.
static func pool() -> Dictionary:
	var CardSkins = load("res://scripts/ui/card_skins.gd")
	var out := {}
	for k in COSTUMES:
		out[k] = COSTUMES[k]
	for k in GUNS:
		out[k] = GUNS[k]
	for id in CardSkins.ORDER + CardSkins.RETRO:
		if id == "classic":
			continue
		var k := key("card", id)
		out[k] = CARD_RARITY.get(k, "rare" if CardSkins.RETRO.has(id) else "common")
	return out


static func in_machine(part: String, value) -> bool:
	return pool().has(key(part, value))


static func rarity(part: String, value) -> String:
	return str(pool().get(key(part, value), "common"))


## Do you have it? Free things (not in the machine) always.
static func owns(part: String, value, owned: Dictionary) -> bool:
	return not in_machine(part, value) or owned.has(key(part, value))


## What's left to win.
static func remaining(owned: Dictionary) -> Array:
	var out := []
	for k in pool():
		if not owned.has(k):
			out.append(k)
	return out


## One spin: picks a rarity by weight (among those with something left),
## then a prize of that rarity. "" if you own everything.
static func roll(owned: Dictionary, rng: RandomNumberGenerator) -> String:
	var all := pool()
	var left := {}
	for k in all:
		if not owned.has(k):
			left[k] = all[k]
	if left.is_empty():
		return ""
	var total := 0.0
	var by_rarity := {}
	for k in left:
		var r: String = left[k]
		if not by_rarity.has(r):
			by_rarity[r] = []
			total += float(WEIGHTS[r])
		by_rarity[r].append(k)
	var pick := rng.randf() * total
	for r in RARITIES:
		if not by_rarity.has(r):
			continue
		pick -= float(WEIGHTS[r])
		if pick <= 0.0:
			var choices: Array = by_rarity[r]
			choices.sort()
			return choices[rng.randi_range(0, choices.size() - 1)]
	var last: Array = by_rarity[by_rarity.keys()[0]]
	return last[0]


static func split(k: String) -> Array:
	var i := k.find(":")
	var part := k.left(i)
	var raw := k.substr(i + 1)
	var value: Variant = raw
	if part == "outfit":
		value = int(raw)
	elif part == "eyes":
		value = raw == "true"
	return [part, value]


## What a prize is called on screen.
static func prize_name(k: String) -> String:
	var pv := split(k)
	match pv[0]:
		"card":
			var CardSkins = load("res://scripts/ui/card_skins.gd")
			return "%s CARDS" % CardSkins.skin_name(str(pv[1]))
		"gun":
			return "%s SHOTGUN" % GunSkins.skin_name(str(pv[1]))
		"base":
			return "%s BODY" % str(Looks.BASES.get(pv[1], pv[1]))
		"hat":
			return str(Looks.HATS.get(pv[1], pv[1]))
		"face":
			return str(Looks.FACES.get(pv[1], pv[1]))
		"outfit":
			return "%s OUTFIT" % Looks.OUTFITS[int(pv[1])]["name"]
		"eyes":
			return "GLOWING EYES"
	return k


## What kind of prize, for the reveal: "CARD SKIN", "SHOTGUN SKIN", "COSTUME".
static func prize_kind(k: String) -> String:
	match split(k)[0]:
		"card":
			return "CARD SKIN"
		"gun":
			return "SHOTGUN SKIN"
	return "COSTUME"
