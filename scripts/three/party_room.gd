extends RefCounted
## The party room, through the purple door at the back of the bar. Same size
## and the same card table in the middle (players sit there between throws),
## but its own walls and stuff: the dartboard on the back wall under a neon
## DARTS sign, a shelf of board game boxes on the right (still in their
## shrink-wrap), string lights, a jukebox, and the door back to the bar on
## the left. Built in the same spot as the bar and swapped in and out.

const Props = preload("res://scripts/three/props.gd")
const Dartboard3D = preload("res://scripts/three/dartboard3d.gd")

const FLOOR_Y := -0.78
const BOARD_POS := Vector3(0.0, FLOOR_Y + 1.73, -3.1) # bull height, by the rules
const BACK_DOOR := Vector3(-3.12, FLOOR_Y, 1.4) # on the left wall, back to the bar
## The board games on the shelf. A box's lid art is res://textures/boxes/<id>.png
## if there is one (square, with the game's name in the art); otherwise it's
## painted here and the name and tagline are put on it.
const BOARD_GAMES := [
	{"id": "timber", "name": "TIMBER", "tag": "THE TOWER GAME", "color": Color(0.62, 0.16, 0.1)},
]
const BOX := Vector3(0.09, 0.42, 0.42) # thickness, height, width


static func build(parent: Node3D) -> Dictionary:
	var floor_mat := Props.tex_mat("wood", Color(0.45, 0.3, 0.26), 0.7, 0.8, 0.0, true)
	Props.box(parent, Vector3(7.0, 0.05, 7.0), floor_mat, Vector3(0, FLOOR_Y - 0.025, 0))
	var wall := Props.tex_mat("plaster", Color(0.62, 0.42, 0.72), 0.4, 1.0, 0.0, true)
	for side in [Vector3(0, 0, -3.2), Vector3(0, 0, 3.2), Vector3(-3.2, 0, 0), Vector3(3.2, 0, 0)]:
		var size := Vector3(6.5, 3.7, 0.1) if side.x == 0 else Vector3(0.1, 3.7, 6.5)
		Props.box(parent, size, wall, side + Vector3(0, FLOOR_Y + 1.85, 0))
	Props.box(parent, Vector3(6.5, 0.1, 6.5), Props.tex_mat("concrete", Color(0.2, 0.16, 0.22), 0.5, 1.0, 0.0, true), Vector3(0, FLOOR_Y + 3.7, 0))
	# a dado rail and dark panelling below it
	var panel := Props.tex_mat("wood", Color(0.25, 0.14, 0.12), 1.2, 0.9, 0.0, true)
	for side in [Vector3(0, 0, -3.13), Vector3(-3.13, 0, 0), Vector3(3.13, 0, 0)]:
		var size := Vector3(6.4, 0.9, 0.04) if side.x == 0 else Vector3(0.04, 0.9, 6.4)
		Props.box(parent, size, panel, side + Vector3(0, FLOOR_Y + 0.45, 0))

	# a proper rectangular table in the middle (for the board games): a thick
	# wooden top on four square legs, and a bench along each long side
	var top_wood := Props.tex_mat("wood", Color(0.5, 0.33, 0.22), 1.6, 0.6, 0.0, true)
	var leg_wood := Props.tex_mat("wood", Color(0.32, 0.2, 0.14), 2.0)
	var table_top := 0.03
	Props.box(parent, Vector3(1.9, 0.06, 1.15), top_wood, Vector3(0, table_top - 0.03, 0.15))
	Props.box(parent, Vector3(1.8, 0.1, 1.05), leg_wood, Vector3(0, table_top - 0.11, 0.15)) # the apron under the top
	for x in [-0.85, 0.85]:
		for z in [-0.33, 0.63]:
			Props.box(parent, Vector3(0.08, table_top - FLOOR_Y - 0.06, 0.08), leg_wood, Vector3(x, (table_top - 0.06 + FLOOR_Y) * 0.5, z))
	# the darts ring: light over where everyone stands
	var ring := OmniLight3D.new()
	ring.position = Vector3(0, FLOOR_Y + 2.3, -1.9)
	ring.light_color = Color(1.0, 0.85, 0.7)
	ring.light_energy = 2.4
	ring.omni_range = 3.0
	parent.add_child(ring)

	# the dartboard, a spotlight on it and a neon DARTS sign above
	var board := Dartboard3D.new()
	board.position = BOARD_POS
	parent.add_child(board)
	var spot := SpotLight3D.new()
	spot.position = BOARD_POS + Vector3(0, 0.75, 0.75)
	spot.look_at_from_position(spot.position, BOARD_POS, Vector3.UP)
	spot.light_color = Color(1.0, 0.92, 0.78)
	spot.light_energy = 3.0
	spot.spot_range = 2.0
	spot.spot_angle = 30.0
	parent.add_child(spot)
	var neon := _neon(parent, "DARTS", BOARD_POS + Vector3(0, 1.25, 0.04), Color(1.0, 0.25, 0.3), 128)
	neon.pixel_size = 0.0026
	# the oche: a brass strip on the floor where you'd stand
	Props.box(parent, Vector3(0.6, 0.012, 0.04), Props.tex_mat("metal", Color(0.95, 0.75, 0.35), 4.0, 0.35, 0.85), Vector3(0, FLOOR_Y + 0.006, BOARD_POS.z + 2.37))

	# board games on a shelf on the right wall
	var shelf := Props.tex_mat("wood", Color(0.45, 0.32, 0.24), 1.4)
	var shelf_x := 3.0
	var dark := Props.tex_mat("wood", Color(0.3, 0.2, 0.16), 1.4)
	Props.box(parent, Vector3(0.05, 2.0, 1.8), dark, Vector3(shelf_x + 0.15, FLOOR_Y + 1.0, -1.2)) # the back
	for dz in [-0.88, 0.88]:
		Props.box(parent, Vector3(0.4, 2.0, 0.04), dark, Vector3(shelf_x - 0.02, FLOOR_Y + 1.0, -1.2 + dz)) # the sides
	for row in range(4):
		Props.box(parent, Vector3(0.4, 0.03, 1.72), shelf, Vector3(shelf_x - 0.02, FLOOR_Y + 0.12 + row * 0.48, -1.2))
	# the games themselves: one box each, standing up with its lid facing the
	# room (more go on the shelf as they're made)
	for i in range(BOARD_GAMES.size()):
		var game: Dictionary = BOARD_GAMES[i]
		_game_box(parent, game, Vector3(shelf_x - 0.04, FLOOR_Y + 0.12 + 2 * 0.48 + 0.015, -1.2 + i * 0.5))

	# the door back to the bar, on the left wall
	var frame := Props.tex_mat("wood", Color(0.3, 0.25, 0.2), 1.5)
	Props.box(parent, Vector3(0.06, 2.05, 1.0), Props.tex_mat("wood", Color(0.55, 0.42, 0.32), 1.2, 0.85), BACK_DOOR + Vector3(0.02, 1.03, 0))
	Props.box(parent, Vector3(0.1, 0.08, 1.16), frame, BACK_DOOR + Vector3(0, 2.1, 0))
	for dz in [-0.54, 0.54]:
		Props.box(parent, Vector3(0.1, 2.1, 0.08), frame, BACK_DOOR + Vector3(0, 1.05, dz))
	Props.ball(parent, 0.035, 6, Props.tex_mat("metal", Color(0.9, 0.85, 0.6), 4.0, 0.4, 0.8), BACK_DOOR + Vector3(0.07, 1.0, -0.38))
	var bar_sign := _neon(parent, "BAR", BACK_DOOR + Vector3(0.06, 2.4, 0), Color(1.0, 0.35, 0.75), 96)
	bar_sign.rotation.y = PI / 2.0

	# a jukebox in the back left corner
	var juke := Node3D.new()
	juke.position = Vector3(-2.7, FLOOR_Y, -2.75)
	juke.rotation.y = 0.6
	parent.add_child(juke)
	Props.box(juke, Vector3(0.7, 1.15, 0.45), Props.tex_mat("wood", Color(0.4, 0.15, 0.1), 1.6, 0.6), Vector3(0, 0.575, 0))
	var arch := CylinderMesh.new()
	arch.top_radius = 0.35
	arch.bottom_radius = 0.35
	arch.height = 0.45
	arch.radial_segments = 12
	Props.mesh(juke, arch, Props.tex_mat("wood", Color(0.4, 0.15, 0.1), 1.6, 0.6), Vector3(0, 1.15, 0), Vector3(PI / 2.0, 0, 0))
	Props.box(juke, Vector3(0.5, 0.35, 0.02), Props.glow(Color(1.0, 0.55, 0.15), 1.6), Vector3(0, 0.85, 0.23))
	Props.box(juke, Vector3(0.08, 0.95, 0.02), Props.glow(Color(0.3, 0.8, 1.0), 1.8), Vector3(-0.3, 0.6, 0.23))
	Props.box(juke, Vector3(0.08, 0.95, 0.02), Props.glow(Color(1.0, 0.3, 0.6), 1.8), Vector3(0.3, 0.6, 0.23))
	var juke_light := OmniLight3D.new()
	juke_light.position = Vector3(-2.4, FLOOR_Y + 1.0, -2.4)
	juke_light.light_color = Color(1.0, 0.55, 0.3)
	juke_light.light_energy = 0.8
	juke_light.omni_range = 1.8
	parent.add_child(juke_light)

	# string lights zigzagging under the ceiling
	var bulb_cols := [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.3), Color(0.3, 1.0, 0.5), Color(0.35, 0.6, 1.0), Color(0.9, 0.4, 1.0)]
	for k in range(4):
		var z0 := -2.8 + k * 1.5
		for i in range(14):
			var t := i / 13.0
			var x := lerpf(-3.0, 3.0, t)
			var sag := sin(t * PI) * 0.35
			Props.ball(parent, 0.03, 5, Props.glow(bulb_cols[(i + k) % bulb_cols.size()], 2.5), Vector3(x, FLOOR_Y + 3.1 - sag, z0 + (0.3 if k % 2 == 0 else -0.3) * t))

	# warm light round the room, so it reads as a different place
	for l in [[Vector3(-1.8, FLOOR_Y + 2.4, -1.5), Color(0.95, 0.6, 1.0), 1.8, 3.6], [Vector3(1.9, FLOOR_Y + 2.3, -1.0), Color(1.0, 0.75, 0.55), 1.8, 3.6], [Vector3(0.0, FLOOR_Y + 2.5, 2.0), Color(0.9, 0.7, 0.85), 1.2, 3.6], [Vector3(0.0, FLOOR_Y + 2.2, -2.2), Color(1.0, 0.8, 0.7), 1.0, 2.6], [Vector3(2.3, FLOOR_Y + 1.6, -1.2), Color(1.0, 0.85, 0.6), 1.3, 2.4], [Vector3(-2.3, FLOOR_Y + 1.8, 1.4), Color(0.8, 0.6, 1.0), 1.0, 2.6]]:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		o.omni_attenuation = 1.3
		parent.add_child(o)
	return {"board": board}


static func _neon(parent: Node3D, text: String, pos: Vector3, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://fonts/VT323.woff2")
	l.font_size = size
	l.pixel_size = 0.003
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.6
	glow.omni_range = 1.4
	glow.position = pos + Vector3(0, -0.05, 0.25)
	parent.add_child(glow)
	return l


## A board game box standing on the shelf, its lid turned a little towards
## the middle of the room.
static func _game_box(parent: Node3D, game: Dictionary, base: Vector3) -> void:
	var node := Node3D.new()
	node.position = base + Vector3(0, BOX.y * 0.5, 0)
	node.rotation.y = 0.3
	parent.add_child(node)
	var side := Props.plain(Color(game["color"]).darkened(0.25), 0.7)
	Props.box(node, BOX, side, Vector3.ZERO)
	# the lid: a little bigger than the box, with the art on its face
	Props.box(node, Vector3(0.012, BOX.y + 0.008, BOX.z + 0.008), Props.plain(Color(game["color"]), 0.7), Vector3(-BOX.x * 0.5 - 0.004, 0, 0))
	var art: Texture2D = null
	var path := "res://textures/boxes/%s.png" % game["id"]
	if ResourceLoader.exists(path):
		art = load(path)
	else:
		art = ImageTexture.create_from_image(_paint_lid(Color(game["color"])))
	var face := StandardMaterial3D.new()
	face.albedo_texture = art
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	face.roughness = 0.8
	var quad := QuadMesh.new()
	quad.size = Vector2(BOX.z - 0.02, BOX.y - 0.02)
	var mi := Props.mesh(node, quad, face, Vector3(-BOX.x * 0.5 - 0.0105, 0, 0), Vector3(0, -PI / 2.0, 0))
	mi.name = "Lid"
	# the name across the top of the lid, and what it is along the bottom
	# (lid art from a file has the name in it already)
	for spec in ([] if ResourceLoader.exists(path) else [[game["name"], 0.14, 128, 0.0013, Color(1.0, 0.86, 0.35)], [game["tag"], -0.175, 48, 0.0012, Color(0.98, 0.94, 0.85)]]):
		var l := Label3D.new()
		l.text = spec[0]
		l.font = load("res://fonts/VT323.woff2")
		l.font_size = spec[2]
		l.pixel_size = spec[3]
		l.modulate = spec[4]
		l.outline_size = 14
		l.outline_modulate = Color(0.15, 0.04, 0.02)
		l.position = Vector3(-BOX.x * 0.5 - 0.013, spec[1], 0)
		l.rotation.y = -PI / 2.0
		node.add_child(l)
	# a little display light on it
	var spot := OmniLight3D.new()
	spot.position = Vector3(-0.45, 0.15, 0.1)
	spot.light_color = Color(1.0, 0.9, 0.75)
	spot.light_energy = 1.2
	spot.omni_range = 0.9
	node.add_child(spot)


## Lid art painted in code: a pixel tower of pine blocks, a couple sticking
## out and one on its way down, on the box's colour.
static func _paint_lid(color: Color) -> Image:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in range(n):
		for x in range(n):
			var d := Vector2(x - n * 0.5, y - n * 0.62).length() / n
			img.set_pixel(x, y, color.lightened(0.25 - d * 0.6))
	var pine := Color(0.98, 0.84, 0.58)
	var shade := Color(0.78, 0.6, 0.38)
	var line := Color(0.35, 0.2, 0.1)
	var left := 27
	var width := 42
	var rows := 12
	var h := 5
	var bottom := 84
	for r in range(rows):
		var y0 := bottom - (r + 1) * h
		var out := 0
		if r == 4:
			out = 9 # one pushed half out
		elif r == 8:
			out = -6
		for y in range(y0, y0 + h):
			for x in range(left - 2, left + width + 12):
				var inside := x >= left and x < left + width
				if r % 2 == 0:
					# blocks end-on: three squares
					if inside:
						var k := (x - left) * 3 / width
						var edge := (x - left) % (width / 3) == 0 or y == y0
						if out != 0 and k == 1:
							continue
						img.set_pixel(x, y, line if edge else (pine if k != 1 else shade))
				else:
					# a long block, side-on
					var lx: int = left + maxi(0, out)
					var rx: int = left + width + maxi(0, out)
					if out < 0:
						lx = left + out
						rx = left + width + out
					if x >= lx and x < rx:
						img.set_pixel(x, y, line if y == y0 or x == lx or x == rx - 1 else pine)
		if r % 2 == 0 and out != 0:
			# the middle block, sticking out
			var mx0 := left + width / 3 + out
			for y in range(y0, y0 + h):
				for x in range(mx0, mx0 + width / 3):
					img.set_pixel(x, y, line if y == y0 or x == mx0 or x == mx0 + width / 3 - 1 else shade)
	# one falling off the top, tumbling
	for i in range(12):
		for j in range(5):
			var x := 72 + i - j
			var y := 22 + j + i / 2
			if x < n and y < n:
				img.set_pixel(x, y, pine if j > 0 and j < 3 else line)
	return img
