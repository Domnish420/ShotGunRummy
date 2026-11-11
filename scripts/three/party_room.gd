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
	Props.box(parent, Vector3(0.4, 2.0, 1.8), Props.tex_mat("wood", Color(0.3, 0.2, 0.16), 1.4), Vector3(shelf_x + 0.05, FLOOR_Y + 1.0, -1.2))
	var box_cols := [Color(0.8, 0.15, 0.12), Color(0.15, 0.4, 0.75), Color(0.95, 0.75, 0.15), Color(0.2, 0.6, 0.3), Color(0.55, 0.25, 0.65), Color(0.9, 0.45, 0.1), Color(0.85, 0.85, 0.8)]
	for row in range(4):
		var y := FLOOR_Y + 0.12 + row * 0.48
		Props.box(parent, Vector3(0.4, 0.03, 1.72), shelf, Vector3(shelf_x - 0.02, y, -1.2))
		var z := -1.95
		var i := row * 3
		while z < -0.5:
			var w := 0.2 + float((i * 37) % 5) * 0.04
			var h := 0.28 + float((i * 11) % 4) * 0.035
			if (i + row) % 3 == 0:
				# a pile of boxes lying flat
				for k in range(2):
					Props.box(parent, Vector3(0.32, 0.07, w + 0.1), Props.plain(box_cols[(i + k) % box_cols.size()], 0.6), Vector3(shelf_x - 0.06, y + 0.05 + k * 0.075, z + w * 0.5))
			else:
				Props.box(parent, Vector3(0.3, h, w * 0.4), Props.plain(box_cols[i % box_cols.size()], 0.6), Vector3(shelf_x - 0.06, y + 0.02 + h * 0.5, z + w * 0.2), Vector3(0, 0, -0.05 if i % 4 == 0 else 0.0))
			z += w * 0.42 + 0.03 if (i + row) % 3 != 0 else w + 0.16
			i += 1

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
