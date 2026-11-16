extends RefCounted
## The points on each character's head that cosmetics sit on, measured off the
## models by tools/make_face_anchors.gd (see there for the list). Everything
## is in the head bone's space, +z the way the face points, "left" and "right"
## the character's own.
##
## A cosmetic asks for an anchor ("cover_left", "mouth_right"...) and gets its
## exact spot on the surface and which way the surface faces, or for a point
## on the head's outline at any angle and height (for straps and arms). A new
## model only needs the tool run again.

const PATH := "res://models/characters/face_anchors.json"
const FALLBACK := "Barbarian"

static var _data := {}


static func _all() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func _model(base: String) -> Dictionary:
	var all := _all()
	return all.get(base, all.get(FALLBACK, {}))


static func has_model(base: String) -> bool:
	return _all().has(base)


static func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO


## { "pos": Vector3, "normal": Vector3 } for an anchor (a sensible guess if the
## model doesn't have it).
static func anchor(base: String, name_: String) -> Dictionary:
	var a: Dictionary = _model(base).get(name_, {})
	if a.is_empty():
		return {"pos": Vector3(0, 0.4, 0.5), "normal": Vector3(0, 0, 1)}
	return {"pos": _vec(a["pos"]), "normal": _vec(a["normal"]).normalized()}


static func value(base: String, key: String, default: float) -> float:
	return float(_model(base).get(key, default))


## Front to back, the middle of the head (the outline is measured from here).
static func ring_center(base: String) -> float:
	return float(_model(base).get("ring", {}).get("center_z", 0.0))


## A point on the head's outline: `degrees` round from straight ahead (+90 is
## the character's left), at height `y`. Comes with the outward direction.
static func around(base: String, degrees: float, y: float) -> Dictionary:
	var ring: Dictionary = _model(base).get("ring", {})
	if ring.is_empty():
		var d := Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees)))
		return {"pos": d * 0.5 + Vector3(0, y, 0), "normal": d}
	var heights: Array = ring["heights"]
	var step := float(ring["step"])
	var radius: Array = ring["radius"]
	var cz := float(ring["center_z"])
	# which two heights, which two angles, then blend
	var hi := 0
	while hi < heights.size() - 2 and float(heights[hi + 1]) < y:
		hi += 1
	var hf := clampf((y - float(heights[hi])) / (float(heights[hi + 1]) - float(heights[hi])), 0.0, 1.0)
	var count: int = radius[0].size()
	var af := fposmod(degrees, 360.0) / step
	var ai: int = int(floor(af)) % count
	var aj: int = (ai + 1) % count
	af -= floor(af)
	var r := lerpf(lerpf(_r(radius, hi, ai), _r(radius, hi, aj), af), lerpf(_r(radius, hi + 1, ai), _r(radius, hi + 1, aj), af), hf)
	var d := Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees)))
	return {"pos": Vector3(d.x * r, y, cz + d.z * r), "normal": d}


## A radius from the table, falling back on a neighbour where a ray missed.
static func _r(radius: Array, h: int, a: int) -> float:
	var v := float(radius[h][a])
	if v > 0.0:
		return v
	for dh in [1, -1, 2, -2]:
		var hh: int = clampi(h + dh, 0, radius.size() - 1)
		if float(radius[hh][a]) > 0.0:
			return float(radius[hh][a])
	return 0.5


## A basis that faces along `normal`, upright.
static func facing(normal: Vector3) -> Basis:
	var z := normal.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)
