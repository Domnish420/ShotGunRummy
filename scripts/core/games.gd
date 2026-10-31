extends RefCounted
## The cartridges: every card game in Shotgun Cards, in shelf order.
##
## Each game is a rules engine built on game.gd (players, items, health and
## the shotgun). To add one: write its engine (and an AI in its own file),
## list it here, then give it a table screen in scripts/ui/modes/.
##
##   name    on the cartridge label and the menus
##   color   the cartridge's plastic
##   min/max players

const Game = preload("res://scripts/core/game.gd")
const Blackjack = preload("res://scripts/core/blackjack.gd")
const GoFish = preload("res://scripts/core/gofish.gd")
const Cheat = preload("res://scripts/core/cheat.gd")
const Hearts = preload("res://scripts/core/hearts.gd")
const Spades = preload("res://scripts/core/spades.gd")
const Snap = preload("res://scripts/core/snap.gd")
const President = preload("res://scripts/core/president.gd")

const LIST := {
	"rummy": {"name": "RUMMY", "color": Color(0.55, 0.12, 0.1), "min": 2, "max": 6},
	"blackjack": {"name": "BLACKJACK", "color": Color(0.1, 0.32, 0.18), "min": 2, "max": 6},
	"gofish": {"name": "GO FISH", "color": Color(0.12, 0.3, 0.55), "min": 2, "max": 6},
	"cheat": {"name": "CHEAT", "color": Color(0.5, 0.36, 0.08), "min": 2, "max": 6},
	"hearts": {"name": "HEARTS", "color": Color(0.62, 0.15, 0.32), "min": 2, "max": 6},
	"spades": {"name": "SPADES", "color": Color(0.16, 0.16, 0.2), "min": 2, "max": 6},
	"snap": {"name": "SNAP", "color": Color(0.85, 0.55, 0.1), "min": 2, "max": 6},
	"president": {"name": "PRESIDENT", "color": Color(0.35, 0.18, 0.5), "min": 2, "max": 6},
}

## Shotgun matches of a game to finish before its normal mode unlocks.
const UNLOCK_NORMAL_AFTER := 3


static func has(kind: String) -> bool:
	return LIST.has(kind)


static func title(kind: String) -> String:
	return "SHOTGUN " + str(LIST.get(kind, {"name": "?"})["name"])


static func label(kind: String) -> String:
	return str(LIST.get(kind, {"name": "?"})["name"])


static func color(kind: String) -> Color:
	return LIST.get(kind, {"color": Color.GRAY})["color"]


static func kinds() -> Array:
	return LIST.keys()


## A new, empty game. `normal` leaves out the items and the shotgun.
static func make(kind: String, normal: bool = false) -> Game:
	var g: Game
	match kind:
		"blackjack":
			g = Blackjack.new()
		"gofish":
			g = GoFish.new()
		"cheat":
			g = Cheat.new()
		"hearts":
			g = Hearts.new()
		"spades":
			g = Spades.new()
		"snap":
			g = Snap.new()
		"president":
			g = President.new()
		_:
			g = Game.new()
	if normal:
		g.options.merge(Game.NORMAL_MODE, true)
	return g
