extends Node3D
## The hand for TIMBER: a low-poly skeleton hand (everyone at this table's a
## skeleton) that does what you tell it to the tower.
##
##   poke   one finger out: pushes a block along
##   two    two fingers: a wider, firmer push
##   pinch  thumb and finger: grips the end that sticks out and pulls
##   flat   flat hand on its edge: sweeps a whole layer out sideways
##
## What touches the blocks is `tip`, a small physics body pulled toward
## `target` by a spring with a limited strength: a loose block slides, a
## tight one pushes back and the finger stalls, and shove too hard and you
## drag the tower with it. The bones just follow the tip around.

const TOOLS := ["poke", "two", "pinch", "flat"]
## How hard each tool can push (newtons), and how quick it gets there.
const STRENGTH := {"poke": 5.0, "two": 9.0, "pinch": 0.0, "flat": 40.0}
const BONE := Color(0.92, 0.88, 0.76)

var tool := "poke"
var tip: RigidBody3D
var target := Vector3.ZERO
var facing := Vector3(0, 0, -1) # which way the fingers point (flat on the table)
var grip := 0.0 # pinch: 0 open, 1 closed
var _shapes := {} # tool -> CollisionShape3D
var _fingers := [] # [ [base joint, middle joint, end joint], ... ] index, middle, ring, little
var _thumb := [] # [base, end]
var _wrist: Node3D
var _palm: Node3D
var _speed := 0.0
var boost := 1.0 # pushing harder than a finger likes to (an AI out of options)


func _ready() -> void:
	_build_bones()
	tip = RigidBody3D.new()
	tip.gravity_scale = 0.0
	tip.mass = 0.12
	tip.lock_rotation = true
	tip.can_sleep = false
	tip.continuous_cd = true
	# the fingers only ever touch the block (or layer) being worked on, never
	# snag the ones round it (the tower sets that block on layer 2)
	tip.collision_layer = 4
	tip.collision_mask = 2
	var pm := PhysicsMaterial.new()
	pm.friction = 0.4
	tip.physics_material_override = pm
	var poke := SphereShape3D.new()
	poke.radius = 0.011
	var two := BoxShape3D.new()
	two.size = Vector3(0.05, 0.02, 0.022) # across both fingers
	var flat := BoxShape3D.new()
	flat.size = Vector3(0.016, 0.026, 0.22) # the hand's edge, along the blocks
	for pair in [["poke", poke], ["two", two], ["flat", flat]]:
		var cs := CollisionShape3D.new()
		cs.shape = pair[1]
		tip.add_child(cs)
		_shapes[pair[0]] = cs
	tip.top_level = true
	tip.position = Vector3(0, -3, 0) # out of the way (never inside the tower)
	add_child(tip)
	tool = "poke"
	park()


## Pick a tool: the hand changes shape and the right part touches the blocks.
func set_tool(t: String) -> void:
	tool = t
	for k in _shapes:
		_shapes[k].disabled = k != t
	_pose()


## Put the hand somewhere straight away (no pushing through the tower).
func jump_to(at: Vector3, face: Vector3) -> void:
	facing = Vector3(face.x, 0, face.z).normalized()
	target = at
	tip.global_position = at
	tip.linear_velocity = Vector3.ZERO
	_shapes["flat"].rotation.y = 0.0
	_place_bones()


## Take the tip out of the way (it's not your turn).
func park() -> void:
	visible = false
	for k in _shapes:
		_shapes[k].disabled = true
	tip.global_position = Vector3(0, -3, 0)
	target = tip.global_position
	tip.linear_velocity = Vector3.ZERO


func show_hand() -> void:
	visible = true
	set_tool(tool)


func _physics_process(_delta: float) -> void:
	if tip == null or not visible:
		return
	var most: float = STRENGTH.get(tool, 5.0) * boost
	var k := 500.0 if tool != "flat" else 2500.0
	var c := 2.0 * sqrt(k * tip.mass)
	var f := (target - tip.global_position) * k - tip.linear_velocity * c
	if tool == "pinch":
		# the pinch doesn't push: the tower holds the block; the hand just goes
		tip.linear_velocity = (target - tip.global_position) * 20.0
		return
	tip.apply_central_force(f.limit_length(most + tip.mass * 9.8 * 0.0))
	_speed = tip.linear_velocity.length()


func _process(delta: float) -> void:
	if visible:
		_place_bones()
		_pose(delta)


## How fast the tip is going (for the sounds).
func speed() -> float:
	return _speed


# ---------------------------------------------------------------- the bones

func _bone(parent: Node3D, length: float, thick: float, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.position = at
	parent.add_child(joint)
	var m := BoxMesh.new()
	m.size = Vector3(thick, thick * 0.85, length)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BONE
	mat.roughness = 0.8
	mi.material_override = mat
	mi.position = Vector3(0, 0, -length * 0.5)
	joint.add_child(mi)
	# a knuckle
	var k := SphereMesh.new()
	k.radius = thick * 0.62
	k.height = thick * 1.24
	k.radial_segments = 6
	k.rings = 3
	var ki := MeshInstance3D.new()
	ki.mesh = k
	ki.material_override = mat
	joint.add_child(ki)
	joint.set_meta("length", length)
	return joint


## Fingers point down -z, the palm faces -y. The wrist is the origin.
func _build_bones() -> void:
	_wrist = Node3D.new()
	add_child(_wrist)
	_palm = Node3D.new()
	_wrist.add_child(_palm)
	var palm_len := 0.17
	# the palm: five long bones fanning from the wrist
	for i in range(4):
		var x := (i - 1.5) * 0.034
		var b := _bone(_palm, palm_len, 0.016, Vector3(x * 0.55, 0, 0))
		b.rotation.y = -x * 0.35
	var lengths := [[0.085, 0.055, 0.04], [0.095, 0.06, 0.042], [0.088, 0.056, 0.04], [0.068, 0.042, 0.034]]
	for i in range(4):
		var x := (i - 1.5) * 0.034
		var base := _bone(_palm, lengths[i][0], 0.022, Vector3(x, 0, -palm_len))
		var mid := _bone(base, lengths[i][1], 0.019, Vector3(0, 0, -lengths[i][0]))
		var end := _bone(mid, lengths[i][2], 0.017, Vector3(0, 0, -lengths[i][1]))
		_fingers.append([base, mid, end])
	var tb := _bone(_palm, 0.07, 0.024, Vector3(-0.06, -0.01, -0.035))
	var te := _bone(tb, 0.055, 0.021, Vector3(0, 0, -0.07))
	_thumb = [tb, te]
	# the wrist and a bit of forearm, so it doesn't end in mid-air
	var arm := _bone(_wrist, 0.3, 0.04, Vector3(0, 0, 0.3))


## Curl each finger for the tool.
func _pose(delta: float = 1.0) -> void:
	if _fingers.is_empty():
		return
	var curl := [1.4, 1.4, 1.4, 1.4] # how far each finger bends (0 straight)
	var thumb := [0.9, 0.8]
	match tool:
		"poke":
			curl = [0.0, 1.5, 1.5, 1.5]
		"two":
			curl = [0.0, 0.0, 1.5, 1.5]
		"pinch":
			var g := 0.25 + grip * 0.35
			curl = [g, 1.3, 1.4, 1.4]
			thumb = [0.2 + grip * 0.2, -0.3 - grip * 0.25]
		"flat":
			curl = [0.0, 0.0, 0.0, 0.0]
			thumb = [0.0, 0.0]
	var t := minf(1.0, delta * 12.0)
	for i in range(4):
		for j in range(3):
			var j_node: Node3D = _fingers[i][j]
			j_node.rotation.x = lerpf(j_node.rotation.x, -curl[i] * (0.9 if j == 0 else 1.0), t)
	_thumb[0].rotation = _thumb[0].rotation.lerp(Vector3(-thumb[0] * 0.4, -0.6 + thumb[0] * 0.3, 0.5), t)
	_thumb[1].rotation.x = lerpf(_thumb[1].rotation.x, -thumb[1], t)


## Line the hand up so the working fingertip sits on the tip.
func _place_bones() -> void:
	if tip == null:
		return
	var f := facing if facing.length() > 0.1 else Vector3(0, 0, -1)
	var b := Basis.looking_at(f, Vector3.UP) # -z along `facing`, palm down
	match tool:
		"flat":
			b = b * Basis(Vector3(0, 0, 1), -PI / 2.0) # on its edge
		"pinch":
			b = b * Basis(Vector3(0, 0, 1), -PI / 2.0) * Basis(Vector3(1, 0, 0), 0.15)
	# where the working tip is, in the hand's own space, with the fingers straight
	var reach := Vector3(-0.017, 0, -0.17 - 0.2)
	match tool:
		"two":
			reach = Vector3(0.0, 0, -0.17 - 0.2)
		"flat":
			reach = Vector3(0.0, 0.0, -0.17 - 0.1)
		"pinch":
			reach = Vector3(-0.03, 0.0, -0.17 - 0.1)
	global_transform = Transform3D(b, tip.global_position - b * reach)
	if tool == "flat":
		_shapes["flat"].global_basis = Basis.looking_at(f, Vector3.UP)
