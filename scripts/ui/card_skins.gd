extends RefCounted
## Card skins: how the playing cards look, front and back. Each one sets the
## face colours (paper, edge, black and red ink) and the back (colours and a
## pattern). Item cards keep their own purple look so they always stand out.
##
## Patterns are drawn in card_art.gd: lattice, stripes, dots, checks, shells,
## skulls, zigzag, diamond, pixels, bands, wire, stars, target, hazard, grid,
## web.

const ORDER := ["classic", "felt", "candy", "blood", "wire", "pumpkin", "midnight", "bone", "noir", "rave", "blueprint", "wanted", "web", "hazard", "gameboy", "gold"]

const SKINS := {
	"classic": {
		"name": "CLASSIC",
		"paper": Color(0.914, 0.886, 0.812), "edge": Color(0.6, 0.55, 0.45), "ink": Color(0.086, 0.078, 0.071), "red": Color(0.639, 0.125, 0.106),
		"back": Color(0.353, 0.075, 0.063), "back_dark": Color(0.231, 0.043, 0.035), "back_edge": Color(0.851, 0.820, 0.733), "pattern": "lattice",
	},
	"felt": {
		"name": "CASINO FELT",
		"paper": Color(0.97, 0.96, 0.92), "edge": Color(0.35, 0.5, 0.38), "ink": Color(0.08, 0.1, 0.08), "red": Color(0.78, 0.1, 0.12),
		"back": Color(0.14, 0.45, 0.24), "back_dark": Color(0.05, 0.24, 0.12), "back_edge": Color(0.85, 0.75, 0.4), "pattern": "dots",
	},
	"blood": {
		"name": "BLOOD MONEY",
		"paper": Color(0.94, 0.88, 0.8), "edge": Color(0.5, 0.1, 0.08), "ink": Color(0.12, 0.05, 0.04), "red": Color(0.65, 0.04, 0.04),
		"back": Color(0.82, 0.62, 0.22), "back_dark": Color(0.36, 0.02, 0.02), "back_edge": Color(0.82, 0.62, 0.22), "pattern": "shells",
	},
	"pumpkin": {
		"name": "PUMPKIN",
		"paper": Color(1.0, 0.93, 0.8), "edge": Color(0.85, 0.42, 0.08), "ink": Color(0.12, 0.08, 0.05), "red": Color(0.86, 0.36, 0.04),
		"back": Color(0.96, 0.5, 0.08), "back_dark": Color(0.1, 0.07, 0.06), "back_edge": Color(0.96, 0.5, 0.08), "pattern": "checks",
	},
	"bone": {
		"name": "BONE YARD",
		"paper": Color(0.9, 0.87, 0.78), "edge": Color(0.45, 0.42, 0.36), "ink": Color(0.16, 0.15, 0.13), "red": Color(0.55, 0.14, 0.12),
		"back": Color(0.88, 0.85, 0.76), "back_dark": Color(0.2, 0.19, 0.17), "back_edge": Color(0.88, 0.85, 0.76), "pattern": "skulls",
	},
	"noir": {
		"name": "NOIR",
		"paper": Color(0.13, 0.13, 0.14), "edge": Color(0.75, 0.75, 0.72), "ink": Color(0.93, 0.92, 0.88), "red": Color(1.0, 0.36, 0.33),
		"back": Color(0.6, 0.6, 0.58), "back_dark": Color(0.06, 0.06, 0.07), "back_edge": Color(0.85, 0.85, 0.82), "pattern": "stripes",
	},
	"rave": {
		"name": "RAVE",
		"paper": Color(0.07, 0.05, 0.1), "edge": Color(0.2, 1.0, 0.55), "ink": Color(0.35, 0.95, 1.0), "red": Color(1.0, 0.3, 0.8),
		"back": Color(0.25, 1.0, 0.45), "back_dark": Color(0.08, 0.03, 0.14), "back_edge": Color(1.0, 0.3, 0.8), "pattern": "zigzag",
	},
	"gold": {
		"name": "HIGH ROLLER",
		"paper": Color(1.0, 0.97, 0.88), "edge": Color(0.85, 0.66, 0.2), "ink": Color(0.1, 0.08, 0.04), "red": Color(0.7, 0.08, 0.1),
		"back": Color(0.98, 0.82, 0.35), "back_dark": Color(0.45, 0.3, 0.06), "back_edge": Color(0.98, 0.82, 0.35), "pattern": "diamond",
	},
	"candy": {
		"name": "CANDY CORN",
		"paper": Color(1.0, 0.98, 0.9), "edge": Color(0.98, 0.62, 0.12), "ink": Color(0.2, 0.12, 0.05), "red": Color(0.9, 0.35, 0.05),
		"back": Color(0.98, 0.55, 0.1), "back_dark": Color(1.0, 0.97, 0.88), "back_edge": Color(1.0, 0.82, 0.15), "pattern": "bands",
	},
	"wire": {
		"name": "BARBED WIRE",
		"paper": Color(0.86, 0.82, 0.74), "edge": Color(0.42, 0.3, 0.2), "ink": Color(0.14, 0.12, 0.1), "red": Color(0.58, 0.2, 0.1),
		"back": Color(0.62, 0.6, 0.56), "back_dark": Color(0.3, 0.17, 0.1), "back_edge": Color(0.55, 0.32, 0.18), "pattern": "wire",
	},
	"midnight": {
		"name": "MIDNIGHT",
		"paper": Color(0.9, 0.92, 0.98), "edge": Color(0.25, 0.3, 0.55), "ink": Color(0.08, 0.1, 0.2), "red": Color(0.75, 0.15, 0.3),
		"back": Color(1.0, 0.92, 0.6), "back_dark": Color(0.06, 0.08, 0.2), "back_edge": Color(0.75, 0.8, 0.95), "pattern": "stars",
	},
	"blueprint": {
		"name": "BLUEPRINT",
		"paper": Color(0.92, 0.95, 1.0), "edge": Color(0.2, 0.4, 0.75), "ink": Color(0.08, 0.2, 0.45), "red": Color(0.8, 0.2, 0.25),
		"back": Color(0.75, 0.88, 1.0), "back_dark": Color(0.1, 0.3, 0.62), "back_edge": Color(0.92, 0.96, 1.0), "pattern": "grid",
	},
	"wanted": {
		"name": "WANTED",
		"paper": Color(0.9, 0.8, 0.6), "edge": Color(0.45, 0.3, 0.15), "ink": Color(0.22, 0.13, 0.06), "red": Color(0.6, 0.18, 0.08),
		"back": Color(0.86, 0.72, 0.48), "back_dark": Color(0.4, 0.24, 0.1), "back_edge": Color(0.86, 0.72, 0.48), "pattern": "target",
	},
	"web": {
		"name": "SPIDER WEB",
		"paper": Color(0.85, 0.85, 0.88), "edge": Color(0.3, 0.3, 0.34), "ink": Color(0.08, 0.08, 0.1), "red": Color(0.55, 0.05, 0.25),
		"back": Color(0.82, 0.82, 0.86), "back_dark": Color(0.14, 0.1, 0.18), "back_edge": Color(0.55, 0.2, 0.6), "pattern": "web",
	},
	"hazard": {
		"name": "HAZARD",
		"paper": Color(0.95, 0.94, 0.85), "edge": Color(0.95, 0.78, 0.1), "ink": Color(0.08, 0.08, 0.06), "red": Color(0.85, 0.2, 0.05),
		"back": Color(0.98, 0.8, 0.1), "back_dark": Color(0.08, 0.08, 0.07), "back_edge": Color(0.98, 0.8, 0.1), "pattern": "hazard",
	},
	"gameboy": {
		"name": "POCKET",
		"paper": Color(0.61, 0.74, 0.06), "edge": Color(0.19, 0.38, 0.19), "ink": Color(0.06, 0.22, 0.06), "red": Color(0.19, 0.38, 0.19),
		"back": Color(0.55, 0.67, 0.06), "back_dark": Color(0.06, 0.22, 0.06), "back_edge": Color(0.61, 0.74, 0.06), "pattern": "pixels",
	},
}


static func get_skin(id: String) -> Dictionary:
	return SKINS.get(id, SKINS["classic"])


static func skin_name(id: String) -> String:
	return str(get_skin(id)["name"])


static func clean(id) -> String:
	return str(id) if SKINS.has(str(id)) else "classic"
