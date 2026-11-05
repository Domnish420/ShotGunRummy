extends RefCounted
## Shotgun skins: how the gun looks when you're the one holding it. Each sets
## the metal (barrels, receiver, guard) and the stock's colours, how shiny the
## metal is, and an optional glow. Whoever holds the gun shows their skin, so
## everyone at the table sees it (it travels with your look, as "gun").

const ORDER := ["standard", "rust", "blackout", "swamp", "chrome", "bone", "candy", "blood", "neon", "toxic", "gold"]

## Retro skins: each nods to a famous game (own colours, no logos) and comes
## with a bit of gaming history ("fact").
const RETRO := ["subject", "gravity", "physbeam", "blockblaster", "boomstick", "plumber", "speedblue", "lightgun", "vault", "plasma", "bfg", "umbrella", "splat", "keyblade", "buster", "celshade", "lancer", "hylian"]

## Secret skins: only a code typed into the computer gives these (secrets.gd).
const SECRET := ["spreadshot", "rainbow", "ghost"]

const SKINS := {
	"standard": {"name": "STANDARD ISSUE", "metal": Color(0.75, 0.75, 0.78), "wood": Color(0.9, 0.85, 0.8), "shine": 0.8},
	"rust": {"name": "RUST BUCKET", "metal": Color(0.62, 0.36, 0.2), "wood": Color(0.55, 0.42, 0.32), "shine": 0.2},
	"blackout": {"name": "BLACKOUT", "metal": Color(0.16, 0.16, 0.17), "wood": Color(0.2, 0.19, 0.19), "shine": 0.6},
	"swamp": {"name": "SWAMP CAMO", "metal": Color(0.36, 0.4, 0.26), "wood": Color(0.5, 0.52, 0.32), "shine": 0.3},
	"chrome": {"name": "CHROME", "metal": Color(1.0, 1.0, 1.0), "wood": Color(1.0, 0.95, 0.88), "shine": 1.0},
	"bone": {"name": "BONE SAW", "metal": Color(0.92, 0.88, 0.78), "wood": Color(1.0, 0.96, 0.85), "shine": 0.2},
	"candy": {"name": "CANDY STRIPE", "metal": Color(1.0, 0.55, 0.75), "wood": Color(1.0, 1.0, 1.0), "shine": 0.5},
	"blood": {"name": "BLOOD ORANGE", "metal": Color(0.2, 0.15, 0.15), "wood": Color(0.85, 0.2, 0.12), "shine": 0.6},
	"neon": {"name": "NEON NIGHTS", "metal": Color(1.0, 0.3, 0.85), "wood": Color(0.2, 0.9, 1.0), "shine": 0.6, "glow": Color(1.0, 0.3, 0.85)},
	"toxic": {"name": "TOXIC", "metal": Color(0.15, 0.17, 0.14), "wood": Color(0.45, 1.0, 0.3), "shine": 0.5, "glow": Color(0.45, 1.0, 0.3)},
	"gold": {"name": "SOLID GOLD", "metal": Color(1.0, 0.8, 0.3), "wood": Color(1.0, 0.82, 0.35), "shine": 1.0},
	"subject": {"name": "TEST SUBJECT", "metal": Color(0.95, 0.95, 0.95), "wood": Color(1.0, 0.55, 0.1), "shine": 0.6, "glow": Color(0.2, 0.6, 1.0),
		"fact": "Portal's gun is officially the Aperture Science Handheld Portal Device. Players just call it the portal gun."},
	"gravity": {"name": "GRAVITY BEAM", "metal": Color(1.0, 0.5, 0.08), "wood": Color(0.15, 0.15, 0.16), "shine": 0.7, "glow": Color(1.0, 0.5, 0.08),
		"fact": "Half-Life 2 (2004) let you pick up and fling almost anything with the Gravity Gun, thanks to its physics engine."},
	"physbeam": {"name": "PHYS BEAM", "metal": Color(0.3, 0.75, 1.0), "wood": Color(0.92, 0.92, 0.95), "shine": 0.6, "glow": Color(0.3, 0.75, 1.0),
		"fact": "Garry's Mod began in 2004 as a free mod for Half-Life 2, made by Garry Newman."},
	"blockblaster": {"name": "BLOCK BLASTER", "metal": Color(0.4, 0.9, 0.88), "wood": Color(0.55, 0.4, 0.22), "shine": 0.8,
		"fact": "Minecraft's diamond tools were the best you could get until netherite arrived in 2020."},
	"boomstick": {"name": "BOOMSTICK", "metal": Color(0.3, 0.3, 0.32), "wood": Color(0.45, 0.25, 0.12), "shine": 0.5, "glow": Color(0.9, 0.15, 0.05),
		"fact": "Doom II (1994) added the double-barrelled Super Shotgun, still one of the best-loved guns in gaming."},
	"plumber": {"name": "PLUMBER RED", "metal": Color(0.9, 0.12, 0.12), "wood": Color(0.15, 0.3, 0.85), "shine": 0.4,
		"fact": "Mario's first name was Jumpman, in Donkey Kong (1981)."},
	"speedblue": {"name": "SPEED BLUE", "metal": Color(0.12, 0.35, 0.95), "wood": Color(0.95, 0.95, 0.95), "shine": 0.6,
		"fact": "Sonic was made blue to match the colour of Sega's logo."},
	"lightgun": {"name": "LIGHT GUN", "metal": Color(1.0, 0.45, 0.1), "wood": Color(0.35, 0.35, 0.37), "shine": 0.3,
		"fact": "The NES Zapper light gun used in Duck Hunt (1984) was grey at first; the bright orange one came later."},
	"vault": {"name": "VAULT DWELLER", "metal": Color(0.2, 0.4, 0.85), "wood": Color(1.0, 0.82, 0.2), "shine": 0.5,
		"fact": "Fallout (1997) starts in an underground vault, decades after a nuclear war."},
	"plasma": {"name": "PLASMA", "metal": Color(0.45, 0.25, 0.75), "wood": Color(0.3, 0.2, 0.45), "shine": 0.9, "glow": Color(0.4, 0.75, 1.0),
		"fact": "Halo: Combat Evolved (2001) launched alongside the very first Xbox."},
	"bfg": {"name": "BIG GREEN", "metal": Color(0.25, 0.27, 0.25), "wood": Color(0.3, 0.32, 0.3), "shine": 0.6, "glow": Color(0.3, 1.0, 0.3),
		"fact": "Doom's biggest gun, the BFG 9000, fires a huge ball of green plasma."},
	"umbrella": {"name": "BIOHAZARD", "metal": Color(0.92, 0.92, 0.92), "wood": Color(0.8, 0.08, 0.1), "shine": 0.5,
		"fact": "Resident Evil (1996) is called Biohazard in Japan."},
	"splat": {"name": "INK SPLAT", "metal": Color(1.0, 0.45, 0.05), "wood": Color(0.55, 0.15, 0.85), "shine": 0.7, "glow": Color(1.0, 0.45, 0.05),
		"fact": "In Splatoon (2015) you win by covering the most ground in your team's ink, not by knocking people out."},
	"keyblade": {"name": "KEY TO THE HEART", "metal": Color(0.85, 0.85, 0.9), "wood": Color(1.0, 0.8, 0.2), "shine": 1.0,
		"fact": "Kingdom Hearts (2002) mixed Final Fantasy with Disney worlds, and its hero fights with a giant key."},
	"buster": {"name": "ARM BUSTER", "metal": Color(0.2, 0.5, 1.0), "wood": Color(0.35, 0.8, 1.0), "shine": 0.7, "glow": Color(1.0, 0.9, 0.3),
		"fact": "Mega Man is called Rockman in Japan; his sister is Roll. Rock and roll!"},
	"celshade": {"name": "CEL SHADED", "metal": Color(1.0, 0.85, 0.15), "wood": Color(0.12, 0.12, 0.12), "shine": 0.1,
		"fact": "Borderlands (2009) switched to its comic-book cel-shaded look late in making it."},
	"lancer": {"name": "CHAINSAW BAYONET", "metal": Color(0.35, 0.37, 0.4), "wood": Color(0.2, 0.2, 0.22), "shine": 0.7, "glow": Color(1.0, 0.15, 0.1),
		"fact": "Gears of War (2006) helped make the cover system, ducking behind walls between shots, standard in shooters."},
	"hylian": {"name": "HERO'S SHIELD", "metal": Color(0.25, 0.35, 0.75), "wood": Color(0.85, 0.15, 0.15), "shine": 0.6,
		"fact": "Link, the hero of The Legend of Zelda, is left-handed in most of the older games."},
	"spreadshot": {"name": "SPREAD SHOT", "metal": Color(0.85, 0.15, 0.1), "wood": Color(1.0, 0.85, 0.2), "shine": 0.6, "glow": Color(1.0, 0.3, 0.1),
		"fact": "In Contra (1988), the famous code gave you 30 lives instead of 3. The Spread Gun is the one everyone wanted."},
	"rainbow": {"name": "RAINBOW ROAD", "metal": Color(1.0, 0.3, 0.6), "wood": Color(0.3, 0.8, 1.0), "shine": 0.9, "glow": Color(1.0, 0.95, 0.3),
		"fact": "Rainbow Road, first seen in Super Mario Kart (1992), has no guard rails. Many karts have fallen off it."},
	"ghost": {"name": "GHOST GUN", "metal": Color(0.85, 0.9, 1.0), "wood": Color(0.7, 0.8, 1.0), "shine": 0.2, "glow": Color(0.75, 0.85, 1.0),
		"fact": "Pac-Man's four ghosts are Blinky, Pinky, Inky and Clyde."},
}


static func get_skin(id: String) -> Dictionary:
	return SKINS.get(id, SKINS["standard"])


static func skin_name(id: String) -> String:
	return str(get_skin(id)["name"])


static func fact(id: String) -> String:
	return str(get_skin(id).get("fact", ""))


static func clean(id) -> String:
	return str(id) if SKINS.has(str(id)) else "standard"
