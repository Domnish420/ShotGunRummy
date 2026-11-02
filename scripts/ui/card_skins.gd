extends RefCounted
## Card skins: how the playing cards look, front and back. Each one sets the
## face colours (paper, edge, black and red ink) and the back (colours and a
## pattern). Item cards keep their own purple look so they always stand out.
##
## Patterns are drawn in card_art.gd: lattice, stripes, dots, checks, shells,
## skulls, zigzag, diamond, pixels, bands, wire, stars, target, hazard, grid,
## web.

const ORDER := ["classic", "felt", "candy", "blood", "wire", "pumpkin", "midnight", "bone", "noir", "rave", "blueprint", "wanted", "web", "hazard", "gameboy", "gold"]

## The retro decks: each one nods to a famous game with its own original art
## (no names, logos or characters), and unlocking it teaches you a bit of
## gaming history ("fact").
const RETRO := ["overworld", "paddle", "missing", "diamond", "lava", "dust", "teams", "bricks", "test", "cheat", "crowbar", "rings", "maze", "lineclear", "goldcart", "shareware", "dungeon", "invaders"]

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
	"overworld": {
		"name": "OVERWORLD", "set": "retro",
		"paper": Color(0.93, 0.95, 0.88), "edge": Color(0.3, 0.55, 0.2), "ink": Color(0.12, 0.1, 0.06), "red": Color(0.7, 0.15, 0.1),
		"back": Color(0.42, 0.72, 0.26), "back_dark": Color(0.36, 0.25, 0.15), "back_edge": Color(0.3, 0.55, 0.2), "pattern": "sprite",
		"sprite": ["GGgGGgGG", "gGGgGGgG", "GdGGdgGd", "dDdddDdd", "ddDddddD", "dDddDdDd", "ddddddDd", "DddDdddd"],
		"palette": {"G": Color(0.42, 0.72, 0.26), "g": Color(0.32, 0.58, 0.2), "d": Color(0.52, 0.36, 0.22), "D": Color(0.4, 0.27, 0.16)}, "repeat": 3,
		"fact": "The very first public version of Minecraft came out in May 2009.",
	},
	"diamond": {
		"name": "DIAMOND ORE", "set": "retro",
		"paper": Color(0.9, 0.92, 0.93), "edge": Color(0.4, 0.42, 0.44), "ink": Color(0.1, 0.1, 0.12), "red": Color(0.7, 0.12, 0.15),
		"back": Color(0.45, 0.92, 0.9), "back_dark": Color(0.45, 0.45, 0.47), "back_edge": Color(0.45, 0.92, 0.9), "pattern": "sprite",
		"sprite": ["sSssssSs", "ssCcssss", "sscCSsss", "ssssssCc", "Sssssscc", "ssSsssss", "scCsssSs", "ssccssss"],
		"palette": {"s": Color(0.5, 0.5, 0.52), "S": Color(0.38, 0.38, 0.4), "c": Color(0.45, 0.92, 0.9), "C": Color(0.85, 1.0, 1.0)}, "repeat": 3,
		"fact": "In Minecraft, diamonds hide deep underground, close to the bottom of the world: dig down (but never straight down).",
	},
	"lava": {
		"name": "LAVA DEPTHS", "set": "retro",
		"paper": Color(0.98, 0.9, 0.85), "edge": Color(0.5, 0.12, 0.1), "ink": Color(0.15, 0.05, 0.05), "red": Color(0.85, 0.25, 0.05),
		"back": Color(1.0, 0.5, 0.05), "back_dark": Color(0.35, 0.08, 0.08), "back_edge": Color(1.0, 0.6, 0.1), "pattern": "sprite",
		"sprite": ["rRrrrRrr", "rrROrrRr", "RrOYOrrr", "rrrOrrRr", "rRrrrrrr", "rrrRrOrR", "RrrrrrOY", "rrRrrrOr"],
		"palette": {"r": Color(0.48, 0.14, 0.13), "R": Color(0.35, 0.09, 0.09), "O": Color(1.0, 0.5, 0.05), "Y": Color(1.0, 0.85, 0.2)}, "repeat": 3,
		"fact": "Minecraft's fiery Nether arrived in 2010, in an update released just before Halloween.",
	},
	"test": {
		"name": "TEST CHAMBER", "set": "retro",
		"paper": Color(0.97, 0.97, 0.96), "edge": Color(0.6, 0.62, 0.64), "ink": Color(0.15, 0.16, 0.18), "red": Color(0.95, 0.45, 0.05),
		"back": Color(0.98, 0.5, 0.06), "back_dark": Color(0.88, 0.89, 0.9), "back_edge": Color(0.2, 0.55, 1.0), "pattern": "portals",
		"fact": "Portal (2007) grew out of Narbacular Drop, a student game made at DigiPen. Valve hired its team to make Portal.",
	},
	"crowbar": {
		"name": "CROWBAR", "set": "retro",
		"paper": Color(0.98, 0.93, 0.85), "edge": Color(0.95, 0.5, 0.1), "ink": Color(0.12, 0.1, 0.08), "red": Color(0.8, 0.15, 0.1),
		"back": Color(0.8, 0.15, 0.1), "back_dark": Color(0.95, 0.52, 0.1), "back_edge": Color(0.3, 0.3, 0.32), "pattern": "sprite",
		"sprite": ["......RR", ".....R.r", "....R...", "...R....", "..R.....", ".R......", "R.......", "........"],
		"palette": {"R": Color(0.75, 0.12, 0.1), "r": Color(0.5, 0.07, 0.06)}, "repeat": 3,
		"fact": "Half-Life (1998) hands you a crowbar as your very first weapon. It became one of the most famous weapons in gaming.",
	},
	"missing": {
		"name": "MISSING TEXTURE", "set": "retro",
		"paper": Color(1.0, 0.93, 1.0), "edge": Color(0.9, 0.0, 0.9), "ink": Color(0.05, 0.05, 0.05), "red": Color(0.85, 0.0, 0.8),
		"back": Color(1.0, 0.0, 1.0), "back_dark": Color(0.0, 0.0, 0.0), "back_edge": Color(1.0, 0.0, 1.0), "pattern": "sprite",
		"sprite": ["MK", "KM"],
		"palette": {"M": Color(1.0, 0.0, 1.0), "K": Color(0.0, 0.0, 0.0)}, "repeat": 3,
		"fact": "Games on Valve's Source engine show a pink-and-black checkerboard when a texture is missing. Every Garry's Mod player knows it.",
	},
	"dust": {
		"name": "DUST CRATES", "set": "retro",
		"paper": Color(0.96, 0.9, 0.78), "edge": Color(0.6, 0.45, 0.25), "ink": Color(0.18, 0.13, 0.08), "red": Color(0.7, 0.2, 0.1),
		"back": Color(0.72, 0.55, 0.32), "back_dark": Color(0.82, 0.72, 0.52), "back_edge": Color(0.45, 0.32, 0.16), "pattern": "sprite",
		"sprite": ["FFFFFFFF", "FpppppqF", "FpFppFpF", "FppFFppF", "FppFFppF", "FpFppFpF", "FqpppppF", "FFFFFFFF"],
		"palette": {"F": Color(0.45, 0.3, 0.15), "p": Color(0.72, 0.55, 0.32), "q": Color(0.6, 0.44, 0.24)}, "repeat": 3,
		"fact": "Counter-Strike began in 1999 as a fan-made mod for Half-Life, by Minh Le and Jess Cliffe.",
	},
	"teams": {
		"name": "TEAM COLOURS", "set": "retro",
		"paper": Color(0.95, 0.92, 0.88), "edge": Color(0.35, 0.35, 0.4), "ink": Color(0.12, 0.12, 0.15), "red": Color(0.72, 0.2, 0.18),
		"back": Color(0.72, 0.22, 0.2), "back_dark": Color(0.3, 0.45, 0.6), "back_edge": Color(0.92, 0.85, 0.7), "pattern": "teams",
		"sprite": ["........", "..KKKK..", "..KKKK..", "..KKKK..", "..YYYY..", ".KKKKKK.", "........", "........"],
		"palette": {"K": Color(0.12, 0.1, 0.1), "Y": Color(0.92, 0.8, 0.4)}, "repeat": 3,
		"fact": "Team Fortress 2 went free-to-play in 2011, and its hats grew into a whole economy of their own.",
	},
	"shareware": {
		"name": "SHAREWARE", "set": "retro",
		"paper": Color(0.92, 0.92, 0.95), "edge": Color(0.2, 0.25, 0.45), "ink": Color(0.08, 0.08, 0.15), "red": Color(0.7, 0.1, 0.15),
		"back": Color(0.12, 0.14, 0.25), "back_dark": Color(0.6, 0.12, 0.1), "back_edge": Color(0.85, 0.85, 0.9), "pattern": "sprite",
		"sprite": ["KKKKKKK.", "KKsssKKK", "KKsKsKKK", "KKsssKKK", "KKKKKKKK", "KLLLLLLK", "KLllllLK", "KLLLLLLK"],
		"palette": {"K": Color(0.12, 0.14, 0.25), "s": Color(0.75, 0.76, 0.8), "L": Color(0.95, 0.95, 0.92), "l": Color(0.6, 0.15, 0.15)}, "repeat": 3,
		"fact": "Doom (1993) spread as shareware: its first episode was free to copy and pass on, so it ended up everywhere.",
	},
	"cheat": {
		"name": "CHEAT CODE", "set": "retro",
		"paper": Color(0.86, 0.86, 0.84), "edge": Color(0.3, 0.3, 0.32), "ink": Color(0.1, 0.1, 0.1), "red": Color(0.75, 0.1, 0.15),
		"back": Color(0.85, 0.12, 0.15), "back_dark": Color(0.18, 0.18, 0.2), "back_edge": Color(0.78, 0.78, 0.75), "pattern": "cheat",
		"fact": "Up, Up, Down, Down, Left, Right, Left, Right, B, A: the Konami Code first appeared in Gradius on the NES in 1986.",
	},
	"rings": {
		"name": "GOLD RINGS", "set": "retro",
		"paper": Color(0.92, 0.95, 1.0), "edge": Color(0.15, 0.3, 0.8), "ink": Color(0.05, 0.1, 0.3), "red": Color(0.8, 0.12, 0.12),
		"back": Color(1.0, 0.85, 0.2), "back_dark": Color(0.12, 0.3, 0.85), "back_edge": Color(1.0, 0.85, 0.2), "pattern": "sprite",
		"sprite": ["........", "..YYYY..", ".Y....Y.", ".Y....y.", ".Y....y.", ".y....y.", "..yyyy..", "........"],
		"palette": {"Y": Color(1.0, 0.85, 0.2), "y": Color(0.8, 0.6, 0.1)}, "repeat": 3,
		"fact": "In Sonic the Hedgehog (1991), holding even one ring means a hit scatters your rings instead of costing a life.",
	},
	"bricks": {
		"name": "BRICK AND COIN", "set": "retro",
		"paper": Color(1.0, 0.95, 0.88), "edge": Color(0.6, 0.3, 0.15), "ink": Color(0.1, 0.08, 0.06), "red": Color(0.8, 0.15, 0.1),
		"back": Color(0.72, 0.36, 0.18), "back_dark": Color(0.35, 0.55, 1.0), "back_edge": Color(0.6, 0.3, 0.15), "pattern": "sprite",
		"sprites": [["rrrrkrrr", "rrrrkrrr", "kkkkkkkk", "rkrrrrrr", "rkrrrrrr", "kkkkkkkk", "rrrrkrrr", "rrrrkrrr"], ["........", "..YYYY..", ".YYooYY.", ".YYoYYY.", ".YYoYYY.", ".YYooYY.", "..YYYY..", "........"]],
		"palette": {"r": Color(0.72, 0.36, 0.18), "k": Color(0.2, 0.1, 0.05), "Y": Color(1.0, 0.8, 0.15), "o": Color(0.75, 0.5, 0.05)}, "repeat": 3,
		"fact": "In Super Mario Bros. (1985), every 100 coins you collect gives you an extra life.",
	},
	"maze": {
		"name": "MAZE DOTS", "set": "retro",
		"paper": Color(0.95, 0.95, 0.9), "edge": Color(0.15, 0.2, 0.9), "ink": Color(0.05, 0.05, 0.1), "red": Color(0.85, 0.15, 0.2),
		"back": Color(0.15, 0.25, 1.0), "back_dark": Color(0.02, 0.02, 0.05), "back_edge": Color(1.0, 0.85, 0.6), "pattern": "maze",
		"fact": "In Pac-Man (1980) each ghost hunts its own way: Blinky heads straight for you, while Pinky aims for where you're going.",
	},
	"invaders": {
		"name": "ALIEN WAVE", "set": "retro",
		"paper": Color(0.9, 1.0, 0.9), "edge": Color(0.1, 0.7, 0.2), "ink": Color(0.04, 0.1, 0.04), "red": Color(0.8, 0.1, 0.2),
		"back": Color(0.3, 1.0, 0.35), "back_dark": Color(0.03, 0.03, 0.06), "back_edge": Color(0.2, 1.0, 0.3), "pattern": "sprite",
		"sprite": ["..........", "...G..G...", "....GG....", "...GGGG...", "..GKGGKG..", ".GGGGGGGG.", ".G.GGGG.G.", ".G.G..G.G.", "....GG....", ".........."],
		"palette": {"G": Color(0.3, 1.0, 0.35), "K": Color(0.03, 0.03, 0.06)}, "repeat": 3,
		"fact": "Space Invaders (1978) speeds up as you shoot because the hardware has fewer aliens to draw. That accident became the game.",
	},
	"lineclear": {
		"name": "LINE CLEAR", "set": "retro",
		"paper": Color(0.95, 0.95, 0.98), "edge": Color(0.4, 0.3, 0.7), "ink": Color(0.08, 0.06, 0.15), "red": Color(0.8, 0.1, 0.2),
		"back": Color(0.6, 0.5, 0.9), "back_dark": Color(0.08, 0.06, 0.18), "back_edge": Color(0.6, 0.5, 0.9), "pattern": "sprite",
		"sprite": ["CCCC..YY", "OO....YY", "O..MMM..", "O...M.GG", ".RR..GG.", "..RRBBB.", "......B.", "........"],
		"palette": {"C": Color(0.2, 0.85, 0.95), "Y": Color(0.98, 0.85, 0.2), "O": Color(0.98, 0.55, 0.15), "M": Color(0.65, 0.3, 0.85), "G": Color(0.3, 0.85, 0.3), "R": Color(0.9, 0.2, 0.2), "B": Color(0.2, 0.35, 0.9)}, "repeat": 2,
		"fact": "Tetris was made by Alexey Pajitnov in Moscow in 1984.",
	},
	"goldcart": {
		"name": "GOLD CARTRIDGE", "set": "retro",
		"paper": Color(1.0, 0.96, 0.82), "edge": Color(0.8, 0.62, 0.15), "ink": Color(0.15, 0.1, 0.02), "red": Color(0.65, 0.15, 0.08),
		"back": Color(0.95, 0.78, 0.25), "back_dark": Color(0.12, 0.3, 0.15), "back_edge": Color(0.9, 0.72, 0.2), "pattern": "sprite",
		"sprite": ["YYYYYYY.", "YyyyyyY.", "YlllllY.", "YlLLLlY.", "YlllllY.", "YYYYYYY.", "YkYkYkY.", "........"],
		"palette": {"Y": Color(0.95, 0.78, 0.25), "y": Color(0.75, 0.55, 0.12), "l": Color(0.9, 0.88, 0.8), "L": Color(0.2, 0.45, 0.25), "k": Color(0.3, 0.22, 0.05)}, "repeat": 3,
		"fact": "The Legend of Zelda came to the NES in a gold cartridge, with a battery inside so you could save your adventure.",
	},
	"dungeon": {
		"name": "DUNGEON CRAWL", "set": "retro",
		"paper": Color(0.88, 0.86, 0.82), "edge": Color(0.35, 0.33, 0.32), "ink": Color(0.1, 0.1, 0.1), "red": Color(0.6, 0.12, 0.1),
		"back": Color(0.45, 0.44, 0.44), "back_dark": Color(0.15, 0.14, 0.14), "back_edge": Color(0.95, 0.6, 0.15), "pattern": "sprite",
		"sprites": [["SSSSkSSS", "sSSSkSSs", "kkkkkkkk", "SSkSSSSS", "SskSSSsS", "kkkkkkkk", "SSSSSkSS", "sSSSSkSs"], ["...O....", "..OYO...", "..OYO...", "...O....", "...b....", "...b....", "..bbb...", "........"]],
		"palette": {"S": Color(0.45, 0.44, 0.44), "s": Color(0.38, 0.37, 0.37), "k": Color(0.2, 0.2, 0.2), "O": Color(1.0, 0.5, 0.1), "Y": Color(1.0, 0.9, 0.3), "b": Color(0.45, 0.3, 0.15)}, "repeat": 3,
		"fact": "Rogue (1980) gave its name to a whole genre: roguelikes, where the dungeon is new every time and death is for keeps.",
	},
	"paddle": {
		"name": "PADDLE BALL", "set": "retro",
		"paper": Color(0.92, 0.92, 0.92), "edge": Color(0.2, 0.2, 0.2), "ink": Color(0.05, 0.05, 0.05), "red": Color(0.55, 0.1, 0.1),
		"back": Color(0.95, 0.95, 0.95), "back_dark": Color(0.04, 0.04, 0.04), "back_edge": Color(0.95, 0.95, 0.95), "pattern": "paddle",
		"fact": "Pong (1972) was Atari's first hit. The first machine was tested in a bar called Andy Capp's Tavern.",
	},
}


static func get_skin(id: String) -> Dictionary:
	return SKINS.get(id, SKINS["classic"])


static func skin_name(id: String) -> String:
	return str(get_skin(id)["name"])


## The bit of gaming history a retro deck teaches you ("" for the others).
static func fact(id: String) -> String:
	return str(get_skin(id).get("fact", ""))


static func clean(id) -> String:
	return str(id) if SKINS.has(str(id)) else "classic"
