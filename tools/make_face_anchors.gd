extends SceneTree
## Measures every character model's head and writes the face anchors (the
## points cosmetics sit on) to models/characters/face_anchors.json.
##   godot --headless --path . -s tools/make_face_anchors.gd
##
## It casts rays at the head's real surface, so anchors sit exactly on it:
##   eye_left, eye_right, nose, brow, mouth, mouth_left, mouth_right   (rays
##       from the front, at the heights in TARGETS)
##   cover_left, cover_right: in front of each eye, resting on the rim round
##       it (where a patch or a lens goes)
##   crown (from above), ear_left, ear_right (from the sides), back
## and a "ring" of the head's outline: its distance from the middle at every
## 15 degrees round, at several heights, for straps and glasses' arms.
## Everything is in the head bone's space; +z is the way the face points.
## "left" and "right" are the character's own.
##
## Run it again after adding a model to looks.gd's BASES. The JSON can be
## edited by hand to nudge a point.

const Props = preload("res://scripts/three/props.gd")
const Looks = preload("res://scripts/core/looks.gd")

const OUT := "res://models/characters/face_anchors.json"

## Where to aim on each face (x, y in head space), by model family.
const TARGETS := {
	"person": {"eye_y": 0.36, "eye_x": 0.2, "mouth_y": 0.14, "mouth_x": 0.14},
	"skeleton": {"eye_y": 0.37, "eye_x": 0.2, "mouth_y": 0.16, "mouth_x": 0.13},
}
const RING_STEP := 15 # degrees
const RING_HEIGHTS := [-0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]


func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var out := {}
	for base in Looks.BASES:
		var look := Looks.preset(0)
		look["base"] = base
		look["hat"] = "none"
		look["face"] = "none"
		look["eyes"] = false
		var built: Dictionary = Props.build_character(holder, look, 0.0, false)
		var node: Node3D = built["node"]
		# rest pose: no animation, so the head bone matches the meshes
		for ap in node.find_children("*", "AnimationPlayer", true, false):
			ap.stop()
		for sk in node.find_children("*", "Skeleton3D", true, false):
			sk.reset_bone_poses()
		await process_frame
		await process_frame
		var head: Node3D = built["head"]
		var tris := _head_triangles(node, head)
		var family := "skeleton" if str(base).begins_with("Skeleton") else "person"
		out[base] = _measure(tris, TARGETS[family])
		print("%s: %d triangles, front at %.3f, eyes at %s" % [base, tris.size() / 3, out[base]["eye_left"]["pos"][2], out[base]["eye_left"]["pos"]])
		node.queue_free()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("wrote %s (%d models)" % [OUT, out.size()])
	quit()


## Every visible triangle of the head, in the head bone's space.
func _head_triangles(node: Node3D, head: Node3D) -> PackedVector3Array:
	var inv := head.global_transform.affine_inverse()
	var tris := PackedVector3Array()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or head.is_ancestor_of(mi):
			continue # hidden kit, or something we added
		var to_head: Transform3D = inv * mi.global_transform
		var faces: PackedVector3Array = mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a: Vector3 = to_head * faces[i]
			var b: Vector3 = to_head * faces[i + 1]
			var c: Vector3 = to_head * faces[i + 2]
			# only the head: above the neck
			if (a.y + b.y + c.y) / 3.0 < -0.15:
				continue
			tris.append(a)
			tris.append(b)
			tris.append(c)
	return tris


## The nearest hit of a ray on the triangles: { pos, normal } or {}.
func _cast(tris: PackedVector3Array, from: Vector3, dir: Vector3) -> Dictionary:
	var best := INF
	var hit := {}
	for i in range(0, tris.size(), 3):
		var p = Geometry3D.ray_intersects_triangle(from, dir, tris[i], tris[i + 1], tris[i + 2])
		if p == null:
			continue
		var d: float = from.distance_to(p)
		if d < best:
			best = d
			var n: Vector3 = (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]).normalized()
			if n.dot(dir) > 0.0:
				n = -n # face the ray
			hit = {"pos": p, "normal": n}
	return hit


func _measure(tris: PackedVector3Array, t: Dictionary) -> Dictionary:
	var a := {}
	var front := func(x: float, y: float) -> Dictionary: return _cast(tris, Vector3(x, y, 3.0), Vector3(0, 0, -1))
	# "left" is the character's own left: +x, as they face +z
	a["eye_left"] = front.call(t["eye_x"], t["eye_y"])
	a["eye_right"] = front.call(-t["eye_x"], t["eye_y"])
	a["nose"] = front.call(0.0, t["eye_y"] + 0.01)
	a["brow"] = front.call(0.0, t["eye_y"] + 0.2)
	a["mouth"] = front.call(0.0, t["mouth_y"])
	a["mouth_left"] = front.call(t["mouth_x"], t["mouth_y"])
	a["mouth_right"] = front.call(-t["mouth_x"], t["mouth_y"])
	a["crown"] = _cast(tris, Vector3(0, 3.0, 0), Vector3(0, -1, 0))
	a["ear_left"] = _cast(tris, Vector3(3.0, t["eye_y"], 0), Vector3(-1, 0, 0))
	a["ear_right"] = _cast(tris, Vector3(-3.0, t["eye_y"], 0), Vector3(1, 0, 0))
	a["back"] = _cast(tris, Vector3(0, t["eye_y"], -3.0), Vector3(0, 0, 1))
	# what covers an eye (a patch, a lens) rests on the rim round it, not in it
	for side in ["left", "right"]:
		var cx: float = t["eye_x"] * (1.0 if side == "left" else -1.0)
		var top := {}
		var normal_sum := Vector3.ZERO
		for gx in [-0.11, 0.0, 0.11]:
			for gy in [-0.08, 0.0, 0.08]:
				var hit: Dictionary = front.call(cx + gx, t["eye_y"] + gy)
				if hit.is_empty():
					continue
				normal_sum += hit["normal"]
				if top.is_empty() or hit["pos"].z > top["pos"].z:
					top = hit
		if not top.is_empty():
			a["cover_" + side] = {"pos": Vector3(cx, t["eye_y"], top["pos"].z), "normal": normal_sum.normalized()}
	var out := {}
	for k in a:
		var hit: Dictionary = a[k]
		if hit.is_empty():
			continue
		out[k] = {"pos": _v(hit["pos"]), "normal": _v(hit["normal"])}
	# the outline: rays in towards the middle of the head, all the way round
	var mid_z: float = (float(out["eye_left"]["pos"][2]) + float(out.get("back", {"pos": [0, 0, -0.5]})["pos"][2])) * 0.5
	var ring := []
	for h in RING_HEIGHTS:
		var row := []
		for deg in range(0, 360, RING_STEP):
			var ang := deg_to_rad(deg)
			var dir := Vector3(sin(ang), 0, cos(ang)) # 0 degrees: straight ahead
			var axis := Vector3(0, h, mid_z)
			var hit := _cast(tris, axis + dir * 3.0, -dir)
			row.append(snappedf(Vector2(hit["pos"].x, hit["pos"].z - mid_z).length(), 0.001) if not hit.is_empty() else -1.0)
		ring.append(row)
	out["ring"] = {"center_z": snappedf(mid_z, 0.001), "heights": RING_HEIGHTS, "step": RING_STEP, "radius": ring}
	out["eye_y"] = t["eye_y"]
	out["mouth_y"] = t["mouth_y"]
	return out


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
