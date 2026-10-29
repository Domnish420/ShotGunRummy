extends Node3D
## One card on the 3D table: a face, a back, an outline for hints and a pick
## area so taps can find it. Local +Z is the face side.

var key := "" # texture key (see card_textures.gd)
var pick_kind := "" # hand | item | stock | discard | meld | "" (not tappable)
var pick_id := ""

var _front: MeshInstance3D
var _back: MeshInstance3D
var _outline: MeshInstance3D
var _area: Area3D
var _size := Vector2.ZERO


func setup(card_size: Vector2, back_material: Material) -> void:
	_size = card_size
	var quad := QuadMesh.new()
	quad.size = card_size
	_front = MeshInstance3D.new()
	_front.mesh = quad
	add_child(_front)
	_back = MeshInstance3D.new()
	_back.mesh = quad
	_back.rotation.y = PI
	_back.material_override = back_material
	add_child(_back)
	var ring := QuadMesh.new()
	ring.size = card_size + Vector2(0.014, 0.014)
	_outline = MeshInstance3D.new()
	_outline.mesh = ring
	_outline.position.z = -0.0006
	_outline.visible = false
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	_area = Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(card_size.x, card_size.y, 0.004)
	shape.shape = box
	_area.add_child(shape)
	_area.set_meta("card", self)
	add_child(_area)


func set_face(face_key: String, face_material: Material) -> void:
	key = face_key
	_front.material_override = face_material


func set_outline(outline_material: Material) -> void:
	_outline.visible = outline_material != null
	if outline_material != null:
		_outline.material_override = outline_material


func set_pickable(kind: String, id: String) -> void:
	pick_kind = kind
	pick_id = id
	_area.collision_layer = 1 if kind != "" else 0


func set_shadows(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_front.cast_shadow = mode
	_back.cast_shadow = mode
