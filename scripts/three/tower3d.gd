extends Node3D
## TIMBER's tower: 18 layers of 3 wooden blocks, each a real physics body, on
## the party room table. Blocks aren't all quite the same height (like the
## real thing), so some are loose and slide out easily and some carry the
## weight and drag the tower with them.
##
## The tower keeps track of which blocks are where, which ones may be taken
## (not from the top layer, nor the one under it while the top's unfinished),
## when a block's been pulled clear (then it's carried up and laid on top),
## and whether the tower's come down: any block that isn't the one being
## moved ending up off the tower, down on the table, or tipped right over.

signal toppled
signal block_out(block: RigidBody3D) # the moving block's clear of the tower
signal dropped(block: RigidBody3D) # a lone block slid out by itself (out of the game)

const L := 0.18 # block length
const W := 0.06 # width (3 side by side make a square layer)
const H := 0.036 # height
const LAYERS := 18
const MASS := 0.12
const GAP := 0.002 # between blocks side by side
const TOP_Y := 0.03 # the table top (world3d.TABLE_TOP)

var blocks: Array = [] # every RigidBody3D
var removed := {} # block -> true: out of the game (swiped off, or carried away)
var active: RigidBody3D = null # the block being worked on: it may move
var down := false # the tower has fallen
var _base := Vector3.ZERO # the tower's middle at the table top
var _mat: PhysicsMaterial
var _rng := RandomNumberGenerator.new()
var _held: RigidBody3D = null # pinched by the hand
var _hold_at := Vector3.ZERO # where the pinch wants it (world)
var _hold_grip := Vector3.ZERO # the pinch point, in the block's own space
var _floor: StaticBody3D
var _watch := true # checking for a collapse
var fall_reason := ""
var moving := {} # block -> true: being worked on (the hand may touch them; they may move)


func build(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	clear()
	down = false
	_watch = true
	_mat = PhysicsMaterial.new()
	_mat.friction = 0.55
	_mat.bounce = 0.0
	if _floor == null:
		_floor = StaticBody3D.new()
		_floor.physics_material_override = _mat
		add_child(_floor)
		# the table top, and the floor further down for whatever falls off
		for spec in [[Vector3(1.9, 0.1, 1.15), Vector3(0, TOP_Y - 0.05, 0.15)], [Vector3(8, 0.1, 8), Vector3(0, -0.78 - 0.05, 0)]]:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = spec[0]
			cs.shape = bs
			cs.position = spec[1]
			_floor.add_child(cs)
	_base = Vector3(0, TOP_Y, 0)
	if get_node_or_null("Light") == null:
		# a warm light on the tower from each side, so its faces aren't in the dark
		for i in range(3):
			var o := OmniLight3D.new()
			o.name = "Light" if i == 0 else "Light%d" % i
			var a := i * TAU / 3.0 + 0.4
			o.position = Vector3(sin(a) * 0.9, 0.55, cos(a) * 0.9)
			o.light_color = Color(1.0, 0.88, 0.7)
			o.light_energy = 0.9
			o.omni_range = 1.6
			add_child(o)
	# pale pine, each block a shade different (like the real thing)
	var wood := []
	for i in range(6):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.98, 0.86, 0.62).lerp(Color(0.86, 0.68, 0.45), i / 5.0)
		m.roughness = 0.85
		m.emission_enabled = true # a touch of its own light: you can always read the blocks
		m.emission = m.albedo_color * 0.12
		wood.append(m)
	var y := TOP_Y
	for layer in range(LAYERS):
		# loose blocks are a hair thinner, so the layer above doesn't rest on
		# them: they slide right out. Mostly middles; now and then a side.
		var heights := []
		for k in range(3):
			var loose := k == 1 and _rng.randf() < 0.6
			heights.append(H * (1.0 - (_rng.randf_range(0.035, 0.05) if loose else 0.0)))
		var tallest: float = heights.max()
		for k in range(3):
			var b := _block(wood[_rng.randi() % wood.size()], heights[k], 0.45)
			var along_x := layer % 2 == 0
			var off := (k - 1) * (W + GAP)
			var pos := Vector3(0 if along_x else off, y + heights[k] * 0.5, off if along_x else 0)
			# a little untidy, like a hand-stacked tower: only along its length,
			# never into its neighbours
			var slide := _rng.randf_range(-0.004, 0.004)
			pos += Vector3(slide, 0, 0) if along_x else Vector3(0, 0, slide)
			b.position = pos
			b.rotation.y = 0.0 if along_x else PI / 2.0
			b.set_meta("layer", layer)
			b.set_meta("slot", k)
			blocks.append(b)
		y += tallest


## How grippy a block is: some are loose and slide right out (more often the
## middle ones), most are snug, and some are tight and drag the tower along.
func _grip(slot: int) -> float:
	var r := _rng.randf()
	var loose := 0.45 if slot == 1 else 0.25
	if r < loose:
		return _rng.randf_range(0.08, 0.16)
	if r < loose + 0.35:
		return _rng.randf_range(0.3, 0.45)
	return _rng.randf_range(0.6, 0.8)


func _block(mat: Material, height: float, grip: float = 0.5) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = MASS
	var pm := PhysicsMaterial.new()
	pm.friction = grip
	pm.bounce = 0.0
	b.physics_material_override = pm
	b.set_meta("grip", grip)
	b.can_sleep = false # waking a sleeping stack jolts it (the contacts are solved afresh): it stays awake
	# a good bit of damping: wooden blocks settle dead still instead of
	# jittering (and a collapse comes down a touch slow, which reads well)
	b.linear_damp = 1.0
	b.angular_damp = 2.0
	b.continuous_cd = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(L, height, W)
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(L, height, W)
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	b.set_meta("mesh", mi)
	b.set_meta("height", height)
	add_child(b)
	return b


func clear() -> void:
	for b in blocks:
		if is_instance_valid(b):
			b.queue_free()
	blocks.clear()
	removed.clear()
	active = null
	_held = null


## Start or stop the physics (frozen, the tower can't fall: between games).
func set_frozen(on: bool) -> void:
	for b in blocks:
		if not removed.has(b):
			b.freeze = on


# ---------------------------------------------------------------- layers

## Each layer from the bottom: the blocks still in the tower there.
func layer_blocks() -> Array:
	var out := []
	for b in blocks:
		if removed.has(b):
			continue
		var l := int(b.get_meta("layer"))
		while out.size() <= l:
			out.append([])
		out[l].append(b)
	return out


func top_layer() -> int:
	var ls := layer_blocks()
	for i in range(ls.size() - 1, -1, -1):
		if not ls[i].is_empty():
			return i
	return -1


## May this block be taken? Not from the bottom layer, not from the top
## layer, and not from the one under it while the top's not finished.
func takeable(b: RigidBody3D) -> bool:
	if b == null or removed.has(b) or down:
		return false
	var top := top_layer()
	var l := int(b.get_meta("layer"))
	if l == 0 or l >= top:
		return false # the bottom layer stays put (house rule), and not the top
	if l == top - 1 and layer_blocks()[top].size() < 3:
		return false
	return true


func block_axis(b: RigidBody3D) -> Vector3:
	var a: Vector3 = b.global_transform.basis.x
	a.y = 0.0
	return a.normalized()


## How far the block sticks out of the tower at each end (metres; 0 when
## it's flush), as [toward -axis, toward +axis].
func protrusion(b: RigidBody3D) -> Array:
	var axis := block_axis(b)
	var c: float = (b.global_position - tower_center()).dot(axis)
	return [maxf(0.0, -c), maxf(0.0, c)]


## The middle of the tower (the average of its blocks, at the table).
func tower_center() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for b in blocks:
		if removed.has(b) or b == active or moving.has(b):
			continue
		c += b.global_position
		n += 1
	if n == 0:
		return _base
	c /= n
	return Vector3(c.x, TOP_Y, c.z)


# ---------------------------------------------------------------- moving one

## What the hand may touch: only the block being worked on (physics layer 2).
## Every block is on layer 1 for the rest of the tower.
func set_active(b: RigidBody3D) -> void:
	set_touchable(([] if b == null else [b]))
	active = b
	if b != null:
		b.sleeping = false


func set_touchable(list: Array) -> void:
	moving = {}
	for o in list:
		moving[o] = true
	for o in blocks:
		var on := list.has(o)
		o.collision_layer = 1 | (2 if on else 0)
		o.collision_mask = 1 | (4 if on else 0) # and it feels the fingers back


## Pinch: hold the block at its grip point and pull it toward `to`.
func hold(b: RigidBody3D, grip_world: Vector3) -> void:
	_held = b
	_hold_grip = b.to_local(grip_world)
	_hold_at = grip_world
	b.sleeping = false
	b.angular_damp = 6.0


func hold_to(to: Vector3) -> void:
	_hold_at = to


func release() -> void:
	if _held != null and is_instance_valid(_held):
		_held.angular_damp = 2.0
	_held = null


## Is the moving block out? Once it's more than about 60% out (just before it
## would tip over the edge) the other hand catches it; or it's down on the table.
func is_out(b: RigidBody3D) -> bool:
	var d := b.global_position - tower_center()
	d.y = 0.0
	return d.length() > L * 0.62 or b.global_position.y < TOP_Y + H * 0.6 and int(b.get_meta("layer")) > 0


## Carry the moving block up and lay it on top. Returns the time it takes.
func place_on_top(b: RigidBody3D) -> float:
	release()
	active = b # it's carried: not part of the tower till it's down
	var ls := layer_blocks()
	var top := -1
	for i in range(ls.size() - 1, -1, -1):
		if not ls[i].filter(func(o): return o != b).is_empty():
			top = i
			break
	var top_blocks: Array = ls[top].filter(func(o): return o != b) if top >= 0 else []
	var layer := top
	if top_blocks.size() >= 3:
		layer = top + 1
		top_blocks = []
	var used := top_blocks.map(func(o): return int(o.get_meta("slot")))
	var slot := 1
	for s in [1, 0, 2]:
		if not used.has(s):
			slot = s
			break
	# line up with the layer it lies on: across it, centred on it, just above
	var under: Array = (ls[layer - 1] if layer >= 1 and layer - 1 < ls.size() else []).filter(func(o): return o != b)
	var center := Vector3.ZERO
	var high := TOP_Y
	var under_axis := Vector3(0, 0, 1) if layer % 2 == 0 else Vector3(1, 0, 0)
	if not under.is_empty():
		for o in under:
			center += o.global_position
			high = maxf(high, o.global_position.y + float(o.get_meta("height")) * 0.5)
		center /= under.size()
		under_axis = block_axis(under[0])
		# along their length, one sticking out would drag the average: use the
		# middle one (or the tower's middle)
		var alongs := []
		for o in under:
			alongs.append(o.global_position.dot(under_axis))
		alongs.sort()
		var mid_along: float = alongs[alongs.size() / 2] if alongs.size() == 3 else tower_center().dot(under_axis)
		center += under_axis * (mid_along - center.dot(under_axis))
	var axis := Vector3(-under_axis.z, 0, under_axis.x) # this layer runs across the one below
	if top_blocks.size() > 0:
		axis = block_axis(top_blocks[0])
	var across := Vector3(-axis.z, 0, axis.x)
	var target := Vector3(center.x, high + float(b.get_meta("height")) * 0.5 + 0.002, center.z) + across * ((slot - 1) * (W + GAP))
	b.set_meta("layer", layer)
	b.set_meta("slot", slot)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	# carried through the air, it touches nothing till it's set down on top
	b.collision_layer = 0
	b.collision_mask = 0
	# first it slides on out, clear of the tower, then up and over
	var out_dir := b.global_position - tower_center()
	out_dir.y = 0.0
	var own := block_axis(b)
	if own.dot(out_dir) < 0.0:
		own = -own
	var clear := Vector3(tower_center().x, b.global_position.y, tower_center().z) + own * (L + 0.03)
	var lift := Vector3(clear.x, target.y + 0.12, clear.z)
	var basis := Basis(Vector3.UP, atan2(-axis.z, axis.x))
	var t := create_tween()
	t.tween_property(b, "global_position", clear, 0.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "global_position", lift, 0.35).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(b, "global_basis", basis, 0.35)
	t.tween_property(b, "global_position", target + Vector3(0, 0.025, 0), 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "global_position", target, 0.15)
	t.tween_callback(func() -> void:
		b.collision_layer = 1
		b.collision_mask = 1
		b.freeze = false
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		if active == b:
			active = null)
	return 1.1


## Take a block out of the game (swiped off the tower).
func discard(b: RigidBody3D) -> void:
	removed[b] = true
	if b == active:
		active = null


func _physics_process(delta: float) -> void:
	if _held != null and is_instance_valid(_held):
		var grip: Vector3 = _held.to_global(_hold_grip)
		var k := 260.0
		var c := 14.0
		var v: Vector3 = _held.linear_velocity
		var f := (_hold_at - grip) * k - v * c
		# a pinch can only pull so hard: yank too hard and it slips
		var most := 7.0
		if f.length() > most * 1.8:
			release()
			return
		f = f.limit_length(most)
		_held.apply_force(f, grip - _held.global_position)
	if _watch and not down and _fallen():
		down = true
		toppled.emit()


## Has the tower come down? Blocks off the tower or down on the table (that
## weren't on the bottom), or any block tipped right over. One block that
## slides out on its own, low in the tower (one left sticking out, say), just
## drops out of the game: that's not a collapse.
func _fallen() -> bool:
	var center := tower_center()
	var off := []
	for b in blocks:
		if removed.has(b) or b == active or moving.has(b) or b.freeze:
			continue
		var d: Vector3 = b.global_position - center
		d.y = 0.0
		if b.global_transform.basis.y.dot(Vector3.UP) < 0.75 or d.length() > L * 1.1 or (int(b.get_meta("layer")) >= 2 and b.global_position.y < TOP_Y + H * 1.2):
			off.append(b)
	if off.is_empty():
		return false
	if off.size() == 1 and int(off[0].get_meta("layer")) < top_layer() - 1:
		removed[off[0]] = true
		dropped.emit(off[0])
		return false
	fall_reason = "%d off the tower (L%d)" % [off.size(), int(off[0].get_meta("layer"))]
	return true


## How much the tower is moving right now (the fastest block but the active one).
func shake() -> float:
	var most := 0.0
	for b in blocks:
		if removed.has(b) or b == active or b.freeze:
			continue
		most = maxf(most, b.linear_velocity.length())
	return most


## The top of the tower (for the camera).
func height() -> float:
	var h := TOP_Y
	for b in blocks:
		if not removed.has(b):
			h = maxf(h, b.global_position.y)
	return h


func set_watch(on: bool) -> void:
	_watch = on
