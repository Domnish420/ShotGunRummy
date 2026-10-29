extends RefCounted
## Builds the low-poly, PS2-era models for the 3D table: the room and its
## clutter, the players, and the shotgun. Faceted on purpose: few sides on
## round things, small gritty textures.

const Palette = preload("res://scripts/ui/palette.gd")

const TEX := {
	"felt": "res://textures/felt.png", "wood": "res://textures/wood.png", "gun_wood": "res://textures/gun_wood.png",
	"concrete": "res://textures/concrete.png", "plaster": "res://textures/plaster.png", "metal": "res://textures/metal.png",
}


## A textured material, mapped by position (no UVs needed) so it can go on
## any shape. `scale` repeats the texture more for bigger numbers.
static func tex_mat(tex: String, tint: Color = Color.WHITE, scale: float = 1.0, roughness: float = 0.9, metallic: float = 0.0, world: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t = load(TEX[tex])
	if t is Texture2D:
		m.albedo_texture = t
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = roughness
	m.metallic = metallic
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


static func plain(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func mesh(parent: Node3D, m: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(parent, b, mat, pos, rot)


static func cyl(parent: Node3D, top: float, bottom: float, height: float, sides: int, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return mesh(parent, c, mat, pos, rot)


static func ball(parent: Node3D, radius: float, sides: int, mat: Material, pos: Vector3) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = sides
	s.rings = maxi(3, sides / 2)
	return mesh(parent, s, mat, pos)


## A box stretched from `a` to `b`, like an arm or a pipe.
static func limb(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


# ================================================================ the room

static func build_room(parent: Node3D, table_top: float, table_rx: float, table_rz: float) -> void:
	var floor_y := -0.78
	# floor, walls, ceiling
	box(parent, Vector3(7.0, 0.05, 7.0), tex_mat("concrete", Color(0.8, 0.78, 0.74), 0.55, 0.95, 0.0, true), Vector3(0, floor_y - 0.025, 0))
	var wall := tex_mat("plaster", Color(0.75, 0.75, 0.7), 0.4, 1.0, 0.0, true)
	for side in [Vector3(0, 0, -3.2), Vector3(0, 0, 3.2), Vector3(-3.2, 0, 0), Vector3(3.2, 0, 0)]:
		var size := Vector3(6.5, 3.7, 0.1) if side.x == 0 else Vector3(0.1, 3.7, 6.5)
		box(parent, size, wall, side + Vector3(0, floor_y + 1.85, 0))
	box(parent, Vector3(6.5, 0.1, 6.5), tex_mat("concrete", Color(0.35, 0.34, 0.32), 0.5, 1.0, 0.0, true), Vector3(0, floor_y + 3.7, 0))
	# skirting along the bottom of the walls
	var skirt := tex_mat("wood", Color(0.5, 0.45, 0.4), 1.0, 0.9, 0.0, true)
	for side in [Vector3(0, 0, -3.13), Vector3(-3.13, 0, 0), Vector3(3.13, 0, 0)]:
		var size := Vector3(6.4, 0.16, 0.04) if side.x == 0 else Vector3(0.04, 0.16, 6.4)
		box(parent, size, skirt, side + Vector3(0, floor_y + 0.08, 0))

	# a door in the back wall, with an EXIT sign over it
	var door_wood := tex_mat("wood", Color(0.55, 0.42, 0.32), 1.2, 0.85, 0.0, false)
	box(parent, Vector3(1.0, 2.05, 0.06), door_wood, Vector3(0.9, floor_y + 1.03, -3.13))
	var frame := tex_mat("wood", Color(0.3, 0.25, 0.2), 1.5)
	box(parent, Vector3(1.16, 0.08, 0.1), frame, Vector3(0.9, floor_y + 2.1, -3.12))
	for x in [0.36, 1.44]:
		box(parent, Vector3(0.08, 2.1, 0.1), frame, Vector3(x, floor_y + 1.05, -3.12))
	ball(parent, 0.035, 6, tex_mat("metal", Color(0.9, 0.85, 0.6), 4.0, 0.4, 0.8), Vector3(0.52, floor_y + 1.0, -3.08))
	var sign_y := floor_y + 2.32
	box(parent, Vector3(0.42, 0.16, 0.05), glow(Color(0.85, 0.12, 0.08), 1.6), Vector3(0.9, sign_y, -3.11))
	var exit := Label3D.new()
	exit.text = "EXIT"
	exit.font = load("res://fonts/VT323.woff2")
	exit.font_size = 64
	exit.pixel_size = 0.0022
	exit.modulate = Color(1.0, 0.85, 0.8)
	exit.position = Vector3(0.9, sign_y, -3.08)
	parent.add_child(exit)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.15, 0.1)
	red.light_energy = 0.6
	red.omni_range = 1.6
	red.position = Vector3(0.9, sign_y - 0.1, -2.95)
	parent.add_child(red)

	# a shelf of old bottles on the left wall
	var shelf := tex_mat("wood", Color(0.45, 0.38, 0.3), 1.5)
	for h in [0.75, 1.25]:
		box(parent, Vector3(0.28, 0.04, 1.6), shelf, Vector3(-3.0, floor_y + h, -0.9))
	var glass_cols := [Color(0.2, 0.3, 0.12, 0.8), Color(0.35, 0.18, 0.06, 0.8), Color(0.12, 0.2, 0.25, 0.8)]
	for i in range(7):
		var gm := plain(glass_cols[i % 3], 0.15, 0.3)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var h: float = [0.75, 1.25][i % 2]
		var z := -1.55 + i * 0.21
		var tall := 0.22 + (i % 3) * 0.05
		cyl(parent, 0.035, 0.04, tall, 7, gm, Vector3(-2.98, floor_y + h + 0.02 + tall * 0.5, z))
		cyl(parent, 0.012, 0.03, 0.08, 6, gm, Vector3(-2.98, floor_y + h + 0.06 + tall, z))

	# crates in the back corner, pipes along the right wall
	var crate := tex_mat("wood", Color(0.6, 0.5, 0.36), 2.0)
	box(parent, Vector3(0.6, 0.6, 0.6), crate, Vector3(-2.5, floor_y + 0.3, -2.6), Vector3(0, 0.3, 0))
	box(parent, Vector3(0.5, 0.5, 0.5), crate, Vector3(-2.45, floor_y + 0.85, -2.55), Vector3(0, -0.2, 0))
	box(parent, Vector3(0.55, 0.55, 0.55), crate, Vector3(2.55, floor_y + 0.27, -2.6), Vector3(0, 0.6, 0))
	var pipe := tex_mat("metal", Color(0.8, 0.8, 0.75), 3.0, 0.5, 0.7)
	for y in [2.45, 2.6]:
		cyl(parent, 0.05, 0.05, 6.2, 8, pipe, Vector3(3.05, floor_y + y, 0), Vector3(PI / 2.0, 0, 0))

	# the table: felt top, wooden rim, a heavy pedestal
	var top_mi := cyl(parent, 1.0, 1.0, 0.06, 28, tex_mat("felt", Color(0.85, 0.9, 0.85), 1.4, 1.0, 0.0, true), Vector3(0, table_top - 0.03, 0))
	top_mi.scale = Vector3(table_rx, 1, table_rz)
	var rim_mi := cyl(parent, 1.0, 0.95, 0.09, 28, tex_mat("wood", Color(0.55, 0.45, 0.35), 2.5, 0.7, 0.0, true), Vector3(0, table_top - 0.05, 0))
	rim_mi.scale = Vector3(table_rx + 0.07, 1, table_rz + 0.07)
	var dark_wood := tex_mat("wood", Color(0.35, 0.3, 0.25), 2.0)
	cyl(parent, 0.14, 0.14, 0.62, 8, dark_wood, Vector3(0, table_top - 0.4, 0))
	cyl(parent, 0.45, 0.5, 0.1, 8, dark_wood, Vector3(0, floor_y + 0.05, 0))

	# clutter on the table
	var tray := tex_mat("metal", Color(0.7, 0.68, 0.62), 6.0, 0.5, 0.7)
	cyl(parent, 0.075, 0.065, 0.025, 10, tray, Vector3(0.58, table_top + 0.012, 0.95))
	var butt := plain(Color(0.85, 0.8, 0.7))
	for i in range(3):
		var a := i * 2.1
		cyl(parent, 0.006, 0.006, 0.05, 5, butt, Vector3(0.58 + cos(a) * 0.03, table_top + 0.03, 0.95 + sin(a) * 0.03), Vector3(0, a, PI / 2.0 - 0.2))
	var bottle := plain(Color(0.32, 0.17, 0.05, 0.85), 0.1, 0.2)
	bottle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl(parent, 0.045, 0.05, 0.22, 8, bottle, Vector3(-0.72, table_top + 0.11, -0.72))
	cyl(parent, 0.015, 0.04, 0.1, 7, bottle, Vector3(-0.72, table_top + 0.27, -0.72))
	var glass := plain(Color(0.75, 0.8, 0.8, 0.35), 0.05, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl(parent, 0.035, 0.03, 0.08, 8, glass, Vector3(-0.6, table_top + 0.04, -0.85))


## The cone of light under the lamp, with dust drifting in it.
static func build_light_cone(parent: Node3D, lamp_y: float, table_top: float) -> ShaderMaterial:
	var cone_mat := ShaderMaterial.new()
	cone_mat.shader = load("res://shaders/light_cone.gdshader")
	var height := lamp_y - table_top
	var c := CylinderMesh.new()
	c.top_radius = 0.09
	c.bottom_radius = 1.0
	c.height = height
	c.radial_segments = 24
	c.cap_top = false
	c.cap_bottom = false
	var mi := mesh(parent, c, cone_mat, Vector3(0, table_top + height * 0.5, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dust := CPUParticles3D.new()
	dust.amount = 36
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.4, height * 0.4, 0.4)
	dust.position = Vector3(0, table_top + height * 0.5, 0)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.005
	dust.initial_velocity_max = 0.03
	dust.gravity = Vector3(0, -0.004, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.007, 0.007)
	var dm := glow(Color(0.9, 0.82, 0.65), 0.5)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.9, 0.82, 0.65, 0.35)
	q.material = dm
	dust.mesh = q
	parent.add_child(dust)
	return cone_mat


# ================================================================ players

## A player in their chair, looking down the -Z axis at the table.
## style: 0 bare-headed, 1 hat, 2 beanie.
static func build_figure(parent: Node3D, color: Color, style: int) -> Dictionary:
	var node := Node3D.new()
	parent.add_child(node)
	var coat := tex_mat("concrete", color.lightened(0.55), 2.5, 1.0)
	var skin := tex_mat("concrete", Color(0.62, 0.54, 0.47), 4.0, 0.8)
	var chair := tex_mat("wood", Color(0.45, 0.36, 0.28), 2.0)
	# the chair behind them
	box(node, Vector3(0.48, 0.05, 0.44), chair, Vector3(0, -0.32, 0.06))
	box(node, Vector3(0.46, 0.62, 0.05), chair, Vector3(0, 0.02, 0.3), Vector3(-0.08, 0, 0))
	# body
	cyl(node, 0.23, 0.2, 0.64, 6, coat, Vector3(0, 0.14, 0.05))
	box(node, Vector3(0.56, 0.12, 0.26), coat, Vector3(0, 0.45, 0.05))
	cyl(node, 0.06, 0.07, 0.08, 6, skin, Vector3(0, 0.54, 0.04))
	# arms resting on the table, hands by their cards
	for x in [-1.0, 1.0]:
		var shoulder := Vector3(0.27 * x, 0.42, 0.05)
		var elbow := Vector3(0.3 * x, 0.1, -0.18)
		var hand := Vector3(0.15 * x, 0.06, -0.42)
		limb(node, shoulder, elbow, 0.11, coat)
		limb(node, elbow, hand, 0.095, coat)
		box(node, Vector3(0.08, 0.04, 0.11), skin, hand + Vector3(0, -0.01, -0.06))
	# head: faceted on purpose
	var head := Node3D.new()
	head.position = Vector3(0, 0.71, 0.02)
	node.add_child(head)
	ball(head, 0.145, 7, skin, Vector3.ZERO)
	box(head, Vector3(0.05, 0.05, 0.05), skin, Vector3(0, -0.01, -0.14)) # nose
	var eyes := []
	for x in [-0.05, 0.05]:
		eyes.append(ball(head, 0.019, 5, glow(Color(1, 0.97, 0.88), 3.0), Vector3(x, 0.025, -0.128)))
	match style:
		1:
			var hat := plain(color.darkened(0.3), 0.8)
			cyl(head, 0.22, 0.22, 0.02, 10, hat, Vector3(0, 0.09, 0))
			cyl(head, 0.12, 0.14, 0.13, 8, hat, Vector3(0, 0.16, 0))
		2:
			var wool := tex_mat("felt", color.lightened(0.2), 3.0)
			var cap := ball(head, 0.155, 7, wool, Vector3(0, 0.04, 0.005))
			cap.scale = Vector3(1, 0.75, 1)
	return {"node": node, "head": head, "eyes": eyes}


## The character models (KayKit, CC0), by name. Seats get them in this order
## for now; character customisation will let players pick.
const CHARACTERS := ["Barbarian", "Skeleton_Warrior", "Rogue_Hooded", "Skeleton_Mage", "Knight", "Mage", "Skeleton_Rogue", "Rogue", "Skeleton_Minion"]
const CHAR_SCALE := 0.62
const SEAT_HEIGHT := 0.6 # hips above the floor
const WEAPON_WORDS := ["sword", "shield", "axe", "mug", "staff", "wand", "book", "dagger", "knife", "crossbow", "blade", "quiver", "arrow", "bow", "smoke"]


## A seated character in a chair, looking down -Z at the table. Returns
## { node, head (follows the head bone), anim (AnimationPlayer), eyes: [] }.
static func build_character(parent: Node3D, character: String, floor_y: float) -> Dictionary:
	var node := Node3D.new()
	parent.add_child(node)
	var scene = load("res://models/characters/%s.glb" % character)
	if not (scene is PackedScene):
		var fallback := build_figure(parent, Color(0.2, 0.18, 0.16), 0)
		node.queue_free()
		return fallback
	var model: Node3D = scene.instantiate()
	model.rotation.y = PI # the models face +Z; the table is at -Z
	model.scale = Vector3.ONE * CHAR_SCALE
	# seated: hips just behind the seat point, a chair's height off the floor
	# (in the sitting pose the hips are 0.48 up and 0.4 back, in model units)
	var hips_y := floor_y + SEAT_HEIGHT
	var hips_z := 0.14
	model.position = Vector3(0, hips_y - 0.48 * CHAR_SCALE, hips_z - 0.4 * CHAR_SCALE)
	node.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var lower := str(mi.name).to_lower()
		for w in WEAPON_WORDS:
			if lower.contains(w):
				mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# a chair under them
	var chair := tex_mat("wood", Color(0.45, 0.36, 0.28), 2.0)
	box(node, Vector3(0.5, 0.05, 0.46), chair, Vector3(0, hips_y - 0.07, hips_z))
	box(node, Vector3(0.48, 0.7, 0.05), chair, Vector3(0, hips_y + 0.28, hips_z + 0.24), Vector3(-0.08, 0, 0))
	for corner in [Vector3(-0.22, 0, -0.2), Vector3(0.22, 0, -0.2), Vector3(-0.22, 0, 0.2), Vector3(0.22, 0, 0.2)]:
		box(node, Vector3(0.04, hips_y - 0.07 - floor_y, 0.04), chair, Vector3(corner.x, (hips_y - 0.07 + floor_y) * 0.5, hips_z + corner.z))
	# follow the head bone, for aiming the shotgun and placing labels
	var head := Node3D.new()
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if skeleton != null and skeleton.find_bone("head") >= 0:
		var att := BoneAttachment3D.new()
		att.bone_name = "head"
		skeleton.add_child(att)
		att.add_child(head)
	else:
		head.position = Vector3(0, 0.55, 0.15)
		node.add_child(head)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim != null:
		for loop_name in ["Sit_Chair_Idle", "Idle"]:
			if anim.has_animation(loop_name):
				anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("Sit_Chair_Idle"):
			anim.play("Sit_Chair_Idle")
			anim.seek(randf() * anim.current_animation_length, true)
	return {"node": node, "head": head, "anim": anim, "eyes": []}


# ================================================================ the shotgun

## Barrels point down -Z; the muzzle is at about z = -0.66.
static func build_shotgun() -> Node3D:
	var g := Node3D.new()
	var steel := tex_mat("metal", Color(0.75, 0.75, 0.78), 5.0, 0.35, 0.8)
	var wood := tex_mat("gun_wood", Color(0.9, 0.85, 0.8), 6.0, 0.6)
	for x in [-0.022, 0.022]:
		cyl(g, 0.021, 0.021, 0.62, 8, steel, Vector3(x, 0.0, -0.33), Vector3(PI / 2.0, 0, 0))
	box(g, Vector3(0.012, 0.012, 0.6), steel, Vector3(0, 0.022, -0.33)) # sight rib
	ball(g, 0.006, 4, plain(Color(0.9, 0.9, 0.8), 0.3, 0.8), Vector3(0, 0.032, -0.62))
	box(g, Vector3(0.085, 0.08, 0.17), steel, Vector3(0, -0.012, 0.04)) # receiver
	box(g, Vector3(0.075, 0.05, 0.2), wood, Vector3(0, -0.035, -0.2)) # fore-end
	box(g, Vector3(0.055, 0.065, 0.14), wood, Vector3(0, -0.04, 0.18), Vector3(0.18, 0, 0)) # wrist
	box(g, Vector3(0.07, 0.13, 0.26), wood, Vector3(0, -0.08, 0.36), Vector3(0.12, 0, 0)) # butt
	box(g, Vector3(0.072, 0.135, 0.02), plain(Color(0.08, 0.07, 0.06)), Vector3(0, -0.095, 0.49), Vector3(0.12, 0, 0)) # butt pad
	var guard := TorusMesh.new()
	guard.inner_radius = 0.018
	guard.outer_radius = 0.026
	guard.rings = 8
	guard.ring_segments = 4
	mesh(g, guard, steel, Vector3(0, -0.065, 0.08), Vector3(0, 0, PI / 2.0))
	box(g, Vector3(0.008, 0.03, 0.008), steel, Vector3(0, -0.06, 0.075)) # trigger
	return g
