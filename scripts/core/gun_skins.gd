extends RefCounted
## Shotgun skins: how the gun looks when you're the one holding it. Each sets
## the metal (barrels, receiver, guard) and the stock's colours, how shiny the
## metal is, and an optional glow. Whoever holds the gun shows their skin, so
## everyone at the table sees it (it travels with your look, as "gun").

const ORDER := ["standard", "rust", "blackout", "swamp", "chrome", "bone", "candy", "blood", "neon", "toxic", "gold"]

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
}


static func get_skin(id: String) -> Dictionary:
	return SKINS.get(id, SKINS["standard"])


static func skin_name(id: String) -> String:
	return str(get_skin(id)["name"])


static func clean(id) -> String:
	return str(id) if SKINS.has(str(id)) else "standard"
