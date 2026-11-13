extends Node3D
## The dartboard on the party room wall: a low-res face painted in code
## (128 px across, so it looks like a PS2 texture up close), the numbers round
## the edge, and the darts stuck in it. Facing +z; the board's own units are
## board radii (darts.gd): (0, 0) the bull, 1.0 the edge of the doubles.

const Darts = preload("res://scripts/core/darts.gd")

const R := 0.24 # metres to the outside of the double ring
const SURROUND := 1.34 # the black rim, in board radii
const TEX_SIZE := 128

var _darts: Array = [] # the darts stuck in the board (or the wall)
var _font: Font
var _flights := Color(0.9, 0.15, 0.12)


func _ready() -> void:
	_font = load("res://fonts/VT323.woff2") as Font
	# the backboard: a square of dark wood the board hangs on
	var back := BoxMesh.new()
	back.size = Vector3(R * 3.2, R * 3.2, 0.03)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.08, 0.05)
	wood.roughness = 0.9
	_add(back, wood, Vector3(0, 0, -0.03))
	# the face
	var disc := CylinderMesh.new()
	disc.top_radius = R * SURROUND
	disc.bottom_radius = R * SURROUND
	disc.height = 0.04
	disc.radial_segments = 40
	var face := StandardMaterial3D.new()
	face.albedo_texture = ImageTexture.create_from_image(_paint())
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	face.roughness = 0.95
	var side := StandardMaterial3D.new()
	side.albedo_color = Color(0.05, 0.05, 0.05)
	# a cylinder's cap UVs are awkward; a flat quad carries the face instead
	var rim := _add(disc, side, Vector3(0, 0, 0))
	rim.rotation.x = PI / 2.0
	var quad := QuadMesh.new()
	quad.size = Vector2(R * SURROUND * 2.0, R * SURROUND * 2.0)
	var front := _add(quad, face, Vector3(0, 0, 0.0205))
	front.name = "Face"
	# the numbers on the wire ring
	for i in range(20):
		var a := deg_to_rad(i * 18.0)
		var l := Label3D.new()
		l.font = _font
		l.text = str(Darts.NUMBERS[i])
		l.font_size = 64
		l.pixel_size = 0.0012
		l.modulate = Color(0.95, 0.92, 0.8)
		l.outline_size = 0
		l.position = Vector3(sin(a), cos(a), 0) * R * 1.17 + Vector3(0, 0, 0.024)
		add_child(l)


func _add(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## The board face, pixel by pixel.
func _paint() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var black := Color(0.07, 0.06, 0.06)
	var cream := Color(0.86, 0.8, 0.62)
	var red := Color(0.75, 0.1, 0.1)
	var green := Color(0.08, 0.45, 0.2)
	var wire := Color(0.62, 0.62, 0.58)
	for py in range(TEX_SIZE):
		for px in range(TEX_SIZE):
			var x := ((px + 0.5) / TEX_SIZE * 2.0 - 1.0) * SURROUND
			var y := -((py + 0.5) / TEX_SIZE * 2.0 - 1.0) * SURROUND
			var r := sqrt(x * x + y * y)
			var c := black
			if r <= Darts.BULL:
				c = red
			elif r <= Darts.OUTER_BULL:
				c = green
			elif r <= 1.0:
				var a := fposmod(rad_to_deg(atan2(x, y)) + 9.0, 360.0)
				var seg := int(a / 18.0)
				var dark := seg % 2 == 0 # the 20 is a black bed
				var ring := (r >= Darts.TREBLE_IN and r <= Darts.TREBLE_OUT) or r >= Darts.DOUBLE_IN
				if ring:
					c = red if dark else green
				else:
					c = black if dark else cream
				# a thin wire between the beds
				if fposmod(a, 18.0) < 0.9 or absf(r - Darts.TREBLE_IN) < 0.012 or absf(r - Darts.TREBLE_OUT) < 0.012 or absf(r - Darts.DOUBLE_IN) < 0.012:
					c = wire
			elif r > SURROUND * 0.985:
				c = Color(0.03, 0.03, 0.03)
			img.set_pixel(px, py, c)
	return img


## Board radii to a point in the world, just off the face.
func board_to_world(p: Vector2, out: float = 0.025) -> Vector3:
	return to_global(Vector3(p.x * R, p.y * R, out))


## A dart: steel point, a barrel, and flights.
func _make_dart(color: Color) -> Node3D:
	var d := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.75, 0.78)
	steel.metallic = 0.8
	steel.roughness = 0.3
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.006
	barrel.bottom_radius = 0.006
	barrel.height = 0.06
	barrel.radial_segments = 6
	var b := MeshInstance3D.new()
	b.mesh = barrel
	b.material_override = steel
	b.rotation.x = PI / 2.0
	b.position = Vector3(0, 0, 0.04)
	d.add_child(b)
	var flight := StandardMaterial3D.new()
	flight.albedo_color = color
	flight.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in range(2):
		var f := QuadMesh.new()
		f.size = Vector2(0.04, 0.035)
		var fm := MeshInstance3D.new()
		fm.mesh = f
		fm.material_override = flight
		fm.position = Vector3(0, 0, 0.085)
		fm.rotation = Vector3(0, PI / 2.0, k * PI / 2.0)
		d.add_child(fm)
	return d


## Throws a dart at board point `p`: it flies in from `from` and sticks.
## Returns the flight time.
func throw_dart(p: Vector2, from: Vector3, color: Color) -> float:
	var d := _make_dart(color)
	add_child(d)
	_darts.append(d)
	var tilt := Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), 0)
	var off := maxf(0.0, p.length() - SURROUND) # off the board: it sticks in the wall behind
	var land := Vector3(p.x * R, p.y * R, 0.02 if off <= 0.0 else -0.02)
	d.global_position = from
	d.rotation = tilt
	var t := create_tween()
	t.tween_property(d, "position", land, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(d, "rotation", tilt + Vector3(0.06, 0, 0), 0.05)
	t.tween_property(d, "rotation", tilt, 0.08)
	return 0.25


## Pull the darts out (a new visit).
func clear_darts() -> void:
	for d in _darts:
		if is_instance_valid(d):
			d.queue_free()
	_darts.clear()


func dart_count() -> int:
	return _darts.size()
