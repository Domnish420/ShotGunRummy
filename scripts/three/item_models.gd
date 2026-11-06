extends RefCounted
## Little low-poly 3D versions of the item cards' pictures, PS2 style, each
## with its own animation. When an item that has one is used, its card flies
## to the middle of the table, turns away, and the 3D item pops out of it
## and does its thing (see world3d.gd play_item).
##
## Models are about 0.25 tall, built facing +Z (towards the camera), centred
## on the origin.

const Props = preload("res://scripts/three/props.gd")


static func has(item_id: String) -> bool:
	return item_id in ALL


const ALL := ["cigarettes", "medicine", "blank", "saw", "beer", "magnifier", "phone", "handcuffs", "adrenaline", "shakedown", "switcheroo", "bad_trade", "chaos", "spotlight", "flashbang", "revolver", "double_down", "sticky_fingers", "dumpster_dive", "garbage_day", "tarot", "joker_paint"]


## The model for `item_id`, or null.
static func build(item_id: String) -> Node3D:
	if not has(item_id):
		return null
	var builder := Callable(load("res://scripts/three/item_models.gd"), "_" + item_id)
	var node: Node3D = builder.call()
	node.name = item_id
	return node


## Plays the model's animation. `fx` is where loose bits (smoke...) go so
## they drift on their own. Returns how long it takes, in seconds.
static func animate(model: Node3D, item_id: String, fx: Node3D) -> float:
	if not has(item_id):
		return 0.0
	var anim := Callable(load("res://scripts/three/item_models.gd"), "_animate_" + item_id)
	return float(anim.call(model, fx))


# ---------------------------------------------------------------- cigarettes

static func _cigarettes() -> Node3D:
	var root := Node3D.new()
	root.name = "Cigarettes"
	var red := Props.plain(Color(0.68, 0.1, 0.08), 0.8)
	var white := Props.plain(Color(0.93, 0.88, 0.78), 0.9)
	var foil := Props.plain(Color(0.25, 0.22, 0.3), 0.5, 0.4)
	var filter := Props.plain(Color(0.92, 0.55, 0.18), 0.8)
	var paper := Props.plain(Color(0.96, 0.94, 0.88), 0.9)
	var pack := Node3D.new()
	pack.name = "Pack"
	root.add_child(pack)
	# the pack: a red band round the top, white below with a red chevron
	Props.box(pack, Vector3(0.14, 0.13, 0.065), white, Vector3(0, -0.04, 0))
	Props.box(pack, Vector3(0.142, 0.055, 0.067), red, Vector3(0, 0.05, 0))
	var chevron := Props.box(pack, Vector3(0.07, 0.07, 0.004), red, Vector3(-0.024, 0.0, 0.034), Vector3(0, 0, 0.78))
	chevron.scale = Vector3(1, 1, 1)
	Props.box(pack, Vector3(0.07, 0.07, 0.004), red, Vector3(0.024, 0.0, 0.034), Vector3(0, 0, -0.78))
	Props.box(pack, Vector3(0.12, 0.05, 0.062), white, Vector3(0, -0.025, 0.002)) # covers the chevrons' lower halves
	# the lid, flipped open towards the back, dark foil inside
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.0775, -0.0325)
	lid.rotation.x = -1.9
	pack.add_child(lid)
	Props.box(lid, Vector3(0.142, 0.045, 0.067), red, Vector3(0, 0.0225, 0.0335))
	Props.box(pack, Vector3(0.13, 0.01, 0.06), foil, Vector3(0, 0.077, 0))
	# cigarettes standing in the pack, filters up
	for x in [-0.045, -0.015, 0.015]:
		var c := Node3D.new()
		c.position = Vector3(x, 0.07, 0.0)
		pack.add_child(c)
		Props.cyl(c, 0.011, 0.011, 0.03, 6, filter, Vector3(0, 0.015, 0))
	# the one that slides up and gets lit
	var lit := Node3D.new()
	lit.name = "Lit"
	lit.position = Vector3(0.042, 0.06, 0.008)
	pack.add_child(lit)
	Props.cyl(lit, 0.011, 0.011, 0.07, 6, paper, Vector3(0, 0.0, 0))
	var ember := Props.glow(Color(1.0, 0.35, 0.08), 0.0)
	ember.albedo_color = Color(0.85, 0.82, 0.76) # unlit: just paper
	var tip := Props.cyl(lit, 0.0115, 0.0115, 0.012, 6, ember, Vector3(0, 0.041, 0))
	tip.name = "Tip"
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(1.0, 0.5, 0.15)
	light.omni_range = 0.35
	light.light_energy = 0.0
	light.position = Vector3(0, 0.06, 0.04)
	lit.add_child(light)
	return root


static func _animate_cigarettes(model: Node3D, fx: Node3D) -> float:
	var pack: Node3D = model.get_node("Pack")
	var lit: Node3D = pack.get_node("Lit")
	var tip: MeshInstance3D = lit.get_node("Tip")
	var ember: StandardMaterial3D = tip.material_override
	var light: OmniLight3D = lit.get_node("Glow")
	# it spins in, then sways gently the whole time
	pack.rotation.y = -1.4
	var sway := pack.create_tween()
	sway.tween_property(pack, "rotation:y", 0.35, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sway.tween_property(pack, "rotation:y", -0.25, 0.9).set_trans(Tween.TRANS_SINE)
	sway.tween_property(pack, "rotation:y", 0.15, 0.8).set_trans(Tween.TRANS_SINE)
	# a cigarette slides up out of the pack...
	var t := lit.create_tween()
	t.tween_interval(0.35)
	t.tween_property(lit, "position:y", 0.115, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# ...its tip catches and glows...
	t.tween_property(ember, "emission_energy_multiplier", 4.0, 0.15)
	t.parallel().tween_property(ember, "albedo_color", Color(1.0, 0.35, 0.08), 0.15)
	t.parallel().tween_property(light, "light_energy", 2.5, 0.15)
	t.tween_property(ember, "emission_energy_multiplier", 1.6, 0.25)
	t.parallel().tween_property(light, "light_energy", 1.0, 0.25)
	# ...it takes a drag (glows up again) and smoke curls off it
	t.tween_property(ember, "emission_energy_multiplier", 3.5, 0.3)
	t.parallel().tween_property(light, "light_energy", 2.0, 0.3)
	t.tween_property(ember, "emission_energy_multiplier", 1.2, 0.5)
	t.parallel().tween_property(light, "light_energy", 0.8, 0.5)
	var smoke := model.create_tween()
	smoke.tween_interval(0.85)
	for i in range(12):
		smoke.tween_callback(_smoke_puff.bind(tip, fx, i))
		smoke.tween_interval(0.1)
	return 2.1


## One blocky grey puff off the tip, curling up and fading.
static func _smoke_puff(tip: Node3D, fx: Node3D, i: int) -> void:
	if not is_instance_valid(tip) or not tip.is_inside_tree() or not is_instance_valid(fx):
		return
	var m := Props.plain(Color(0.75, 0.74, 0.72, 0.8), 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var s := 0.012 + randf() * 0.008
	var puff := Props.box(fx, Vector3(s, s, s), m, fx.to_local(tip.global_position + Vector3(0, 0.01, 0)))
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	var side := sin(i * 1.3) * 0.04
	var t := puff.create_tween()
	t.tween_property(puff, "position", puff.position + Vector3(side, 0.18 + randf() * 0.06, 0.01), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(puff, "scale", Vector3.ONE * 2.6, 1.1)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, 1.1)
	t.tween_callback(puff.queue_free)


# ================================================================ helpers

static func _m(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	return Props.plain(c, rough, metal)


static func _see(c: Color, alpha: float) -> StandardMaterial3D:
	var m := Props.plain(Color(c, alpha), 0.3)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _g(c: Color, e: float = 2.0) -> StandardMaterial3D:
	return Props.glow(c, e)


static func _ring(parent: Node3D, outer: float, inner: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.outer_radius = outer
	t.inner_radius = inner
	t.rings = 12
	t.ring_segments = 6
	return Props.mesh(parent, t, mat, pos, rot)


static func _node(parent: Node3D, n: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var x := Node3D.new()
	x.name = n
	x.position = pos
	parent.add_child(x)
	return x


## A loose bit (a pill, a spark, a drip...) in the world, at `at`.
static func _bit(fx: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var b := Props.box(fx, size, mat, fx.to_local(at))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return b


## A bit flies from `at` by `move` and fades/shrinks away over `time`.
static func _fling(fx: Node3D, at: Vector3, move: Vector3, size: float, color: Color, time: float, glowing: bool = false) -> void:
	if not is_instance_valid(fx):
		return
	var m := _g(color, 2.5) if glowing else _m(color)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var b := _bit(fx, at, Vector3.ONE * size, m)
	b.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	var t := b.create_tween()
	t.tween_property(b, "position", b.position + move, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "rotation", b.rotation + Vector3(4, 3, 0), time)
	t.parallel().tween_property(m, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	t.tween_callback(b.queue_free)


static func _shake(node: Node3D, amount: float, times: int, step: float = 0.04) -> Tween:
	var home := node.position
	var t := node.create_tween()
	for i in range(times):
		t.tween_property(node, "position", home + Vector3(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5, 0), step)
	t.tween_property(node, "position", home, step)
	return t


static func _spin_in(node: Node3D, from_yaw: float = -1.6, to_yaw: float = 0.3) -> Tween:
	node.rotation.y = from_yaw
	var t := node.create_tween()
	t.tween_property(node, "rotation:y", to_yaw, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## A hand: palm, fingers (straight or curled) and thumb, in `mat`.
static func _hand(parent: Node3D, mat: Material, curled: bool) -> Node3D:
	var h := _node(parent, "Hand")
	Props.box(h, Vector3(0.085, 0.09, 0.03), mat, Vector3.ZERO)
	for i in range(4):
		var x := -0.03 + i * 0.02
		var f := _node(h, "F%d" % i, Vector3(x, 0.045, 0))
		var long := 0.065 - absf(i - 1.5) * 0.008
		if curled:
			Props.box(f, Vector3(0.019, 0.03, 0.04), mat, Vector3(0, 0.0, 0.02))
		else:
			Props.box(f, Vector3(0.018, long, 0.022), mat, Vector3(0, long * 0.5, 0))
	var th := _node(h, "Thumb", Vector3(-0.048, 0.0, 0.005))
	th.rotation.z = 0.7 if not curled else 1.3
	Props.box(th, Vector3(0.02, 0.05, 0.022), mat, Vector3(0, 0.025, 0))
	return h


# ================================================================ medicine

static func _medicine() -> Node3D:
	var root := Node3D.new()
	var olive := _see(Color(0.55, 0.62, 0.12), 0.92)
	var label := _m(Color(0.35, 0.28, 0.08))
	var pivot := _node(root, "Pivot", Vector3(0.05, -0.1, 0))
	Props.cyl(pivot, 0.05, 0.05, 0.13, 8, olive, Vector3(0, 0.065, 0))
	Props.cyl(pivot, 0.051, 0.051, 0.05, 8, label, Vector3(0, 0.07, 0))
	Props.cyl(pivot, 0.038, 0.038, 0.025, 8, olive, Vector3(0, 0.142, 0))
	var pills := _node(root, "Pills")
	for i in range(6):
		var p := _node(pills, "P%d" % i, Vector3(-0.08, -0.07, 0))
		p.visible = false
		Props.cyl(p, 0.012, 0.012, 0.024, 6, _m(Color(0.8, 0.22, 0.12)), Vector3(0.012, 0, 0), Vector3(0, 0, PI / 2.0))
		Props.cyl(p, 0.012, 0.012, 0.024, 6, _m(Color(0.75, 1.0, 0.8)), Vector3(-0.012, 0, 0), Vector3(0, 0, PI / 2.0))
	return root


static func _animate_medicine(model: Node3D, _fx: Node3D) -> float:
	var pivot: Node3D = model.get_node("Pivot")
	_spin_in(model, -1.0, 0.25)
	var t := pivot.create_tween()
	t.tween_interval(0.45)
	# it wobbles... and tips over
	t.tween_property(pivot, "rotation:z", 0.25, 0.12)
	t.tween_property(pivot, "rotation:z", -0.1, 0.12)
	t.tween_property(pivot, "rotation:z", 1.45, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var pills: Node3D = model.get_node("Pills")
	var spots := [Vector3(-0.15, -0.095, 0.05), Vector3(-0.2, -0.095, -0.01), Vector3(-0.12, -0.095, 0.09), Vector3(-0.24, -0.095, 0.06), Vector3(-0.17, -0.095, 0.11), Vector3(-0.1, -0.095, 0.02)]
	for i in range(6):
		var p: Node3D = pills.get_child(i)
		var pt := p.create_tween()
		pt.tween_interval(0.85 + i * 0.09)
		pt.tween_callback(func() -> void: p.visible = true)
		pt.tween_property(p, "position", spots[i], 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(p, "rotation:y", randf_range(-2.0, 2.0), 0.3)
	return 2.0


# ================================================================ blank shell

static func _blank() -> Node3D:
	var root := Node3D.new()
	var shell := _node(root, "Shell")
	Props.cyl(shell, 0.032, 0.032, 0.16, 8, _m(Color(0.9, 0.88, 0.8)), Vector3(0, 0.0, 0))
	Props.cyl(shell, 0.034, 0.034, 0.035, 8, _m(Color(0.78, 0.66, 0.35), 0.4, 0.7), Vector3(0, -0.07, 0))
	Props.cyl(shell, 0.038, 0.038, 0.008, 8, _m(Color(0.7, 0.58, 0.3), 0.4, 0.7), Vector3(0, -0.09, 0))
	Props.cyl(shell, 0.026, 0.026, 0.004, 8, _m(Color(0.6, 0.58, 0.52)), Vector3(0, 0.081, 0)) # crimped, empty top
	return root


static func _animate_blank(model: Node3D, fx: Node3D) -> float:
	var shell: Node3D = model.get_node("Shell")
	var t := shell.create_tween()
	t.tween_property(shell, "rotation:y", TAU, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(shell, "position:y", 0.03, 0.15).set_ease(Tween.EASE_OUT)
	t.tween_property(shell, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN)
	# ...and a sad little puff of dust where the bang should be
	t.tween_callback(func() -> void:
		var top := shell.to_global(Vector3(0, 0.09, 0))
		for i in range(7):
			_fling(fx, top, Vector3(randf_range(-0.04, 0.04), 0.05 + randf() * 0.04, randf_range(-0.02, 0.02)), 0.014, Color(0.6, 0.56, 0.5), 0.8))
	t.tween_interval(0.25)
	t.tween_property(shell, "rotation:z", 0.25, 0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(shell, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	return 1.9


# ================================================================ hand saw

static func _saw() -> Node3D:
	var root := Node3D.new()
	var saw := _node(root, "Saw")
	var rust := _m(Color(0.62, 0.38, 0.2), 0.9, 0.3)
	var wood := _m(Color(0.5, 0.32, 0.17))
	Props.box(saw, Vector3(0.2, 0.075, 0.006), rust, Vector3(-0.04, 0.0, 0))
	for i in range(11):
		Props.box(saw, Vector3(0.012, 0.012, 0.005), rust, Vector3(-0.135 + i * 0.018, -0.04, 0), Vector3(0, 0, PI / 4.0))
	for bar in [[Vector3(0.025, 0.11, 0.022), Vector3(0.07, 0.0, 0)], [Vector3(0.025, 0.11, 0.022), Vector3(0.12, 0.0, 0)], [Vector3(0.075, 0.022, 0.022), Vector3(0.095, 0.045, 0)], [Vector3(0.075, 0.022, 0.022), Vector3(0.095, -0.045, 0)]]:
		Props.box(saw, bar[0], wood, bar[1])
	for y in [-0.025, 0.0, 0.025]:
		Props.ball(saw, 0.005, 6, _m(Color(0.7, 0.65, 0.5), 0.4, 0.7), Vector3(0.07, y, 0.012))
	saw.rotation.z = -0.25
	return root


static func _animate_saw(model: Node3D, fx: Node3D) -> float:
	var saw: Node3D = model.get_node("Saw")
	_spin_in(model, -1.2, 0.2)
	var t := saw.create_tween()
	t.tween_interval(0.45)
	# back and forth, throwing sparks off the teeth
	for i in range(6):
		t.tween_property(saw, "position:x", 0.05, 0.09).set_trans(Tween.TRANS_SINE)
		t.tween_callback(func() -> void:
			var at := saw.to_global(Vector3(-0.05 + randf() * 0.08, -0.045, 0))
			for k in range(3):
				_fling(fx, at, Vector3(randf_range(-0.06, 0.06), -0.05 - randf() * 0.05, randf_range(0.0, 0.05)), 0.008, Color(1.0, 0.75, 0.3), 0.4, true))
		t.tween_property(saw, "position:x", -0.05, 0.09).set_trans(Tween.TRANS_SINE)
	t.tween_property(saw, "position:x", 0.0, 0.1)
	return 1.75


# ================================================================ beer

static func _beer() -> Node3D:
	var root := Node3D.new()
	var b := _node(root, "Bottle", Vector3(0, -0.11, 0))
	var glass := _see(Color(0.45, 0.24, 0.1), 0.93)
	Props.cyl(b, 0.045, 0.045, 0.13, 8, glass, Vector3(0, 0.065, 0))
	Props.cyl(b, 0.018, 0.045, 0.045, 8, glass, Vector3(0, 0.152, 0))
	Props.cyl(b, 0.017, 0.018, 0.05, 8, glass, Vector3(0, 0.2, 0))
	return root


static func _animate_beer(model: Node3D, fx: Node3D) -> float:
	var b: Node3D = model.get_node("Bottle")
	_spin_in(model, -1.0, 0.15)
	var t := b.create_tween()
	t.tween_interval(0.4)
	# a shake...
	for i in range(4):
		t.tween_property(b, "rotation:z", 0.18, 0.06)
		t.tween_property(b, "rotation:z", -0.18, 0.06)
	t.tween_property(b, "rotation:z", 0.0, 0.06)
	# ...and the foam boils up out of the neck and down the side
	var foam := _m(Color(0.92, 0.88, 0.72))
	for i in range(14):
		t.tween_callback(func() -> void:
			if not is_instance_valid(b):
				return
			var top := b.to_global(Vector3(0, 0.23, 0))
			var side := 1.0 if i % 2 == 0 else -1.0
			var bit := _bit(fx, top, Vector3.ONE * (0.016 + randf() * 0.01), foam)
			var bt := bit.create_tween()
			bt.tween_property(bit, "position", bit.position + Vector3(side * randf_range(0.0, 0.03), 0.03, 0.01), 0.18).set_ease(Tween.EASE_OUT)
			bt.tween_property(bit, "position", bit.position + Vector3(side * 0.04, -0.08 - randf() * 0.06, 0.02), 0.5).set_ease(Tween.EASE_IN)
			bt.parallel().tween_property(bit, "scale", Vector3.ONE * 0.3, 0.5)
			bt.tween_callback(bit.queue_free))
		t.tween_interval(0.06)
	return 1.9


# ================================================================ magnifier

static func _magnifier() -> Node3D:
	var root := Node3D.new()
	var g := _node(root, "Glass")
	var brass := _m(Color(0.72, 0.6, 0.3), 0.4, 0.7)
	_ring(g, 0.075, 0.06, brass, Vector3(0.02, 0.03, 0), Vector3(PI / 2.0, 0, 0))
	Props.cyl(g, 0.062, 0.062, 0.006, 12, _see(Color(0.35, 0.33, 0.42), 0.75), Vector3(0.02, 0.03, 0), Vector3(PI / 2.0, 0, 0))
	Props._rod(g, Vector3(-0.03, -0.025, 0), Vector3(-0.1, -0.1, 0), 0.014, brass)
	var glint := Props.box(g, Vector3(0.016, 0.016, 0.004), _g(Color(1.0, 0.95, 0.8), 3.0), Vector3(0.05, 0.06, 0.006), Vector3(0, 0, PI / 4.0))
	glint.name = "Glint"
	glint.scale = Vector3.ONE * 0.01
	return root


static func _animate_magnifier(model: Node3D, _fx: Node3D) -> float:
	var g: Node3D = model.get_node("Glass")
	var glint: Node3D = g.get_node("Glint")
	_spin_in(model, -1.2, 0.0)
	var t := g.create_tween()
	t.tween_interval(0.4)
	# sweeping round, peering...
	t.tween_property(g, "position", Vector3(-0.05, 0.02, 0.02), 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(g, "position", Vector3(0.05, -0.01, 0.02), 0.45).set_trans(Tween.TRANS_SINE)
	t.tween_property(g, "position", Vector3(0, 0, 0.04), 0.3).set_trans(Tween.TRANS_SINE)
	# ...found it: a glint
	t.tween_property(glint, "scale", Vector3.ONE * 2.2, 0.12)
	t.parallel().tween_property(glint, "rotation:z", PI, 0.3)
	t.tween_property(glint, "scale", Vector3.ONE * 0.01, 0.2)
	return 1.9


# ================================================================ burner phone

static func _phone() -> Node3D:
	var root := Node3D.new()
	var grey := _m(Color(0.55, 0.53, 0.5), 0.6, 0.3)
	var body := _node(root, "Body", Vector3(0, -0.02, 0))
	body.rotation.x = -0.35
	Props.box(body, Vector3(0.075, 0.11, 0.014), grey, Vector3(0, -0.055, 0))
	for r in range(4):
		for c in range(3):
			Props.box(body, Vector3(0.016, 0.01, 0.004), _m(Color(0.35, 0.34, 0.33)), Vector3(-0.022 + c * 0.022, -0.04 - r * 0.016, 0.008))
	var lid := _node(body, "Lid")
	lid.rotation.x = PI # closed: folded over the keys
	Props.box(lid, Vector3(0.075, 0.105, 0.012), grey, Vector3(0, 0.052, 0.0))
	var screen := Props.box(lid, Vector3(0.055, 0.065, 0.003), _g(Color(0.05, 0.08, 0.05), 1.0), Vector3(0, 0.055, 0.007))
	screen.name = "Screen"
	return root


static func _animate_phone(model: Node3D, _fx: Node3D) -> float:
	var body: Node3D = model.get_node("Body")
	var lid: Node3D = body.get_node("Lid")
	var screen: MeshInstance3D = lid.get_node("Screen")
	var sm: StandardMaterial3D = screen.material_override
	_spin_in(model, -1.0, 0.3)
	var t := lid.create_tween()
	t.tween_interval(0.45)
	t.tween_property(lid, "rotation:x", -0.2, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# the screen flickers on, green
	for e in [Color(0.3, 0.9, 0.4), Color(0.05, 0.1, 0.05), Color(0.4, 1.0, 0.5)]:
		t.tween_property(sm, "albedo_color", e, 0.06)
		t.parallel().tween_property(sm, "emission", e, 0.06)
	t.parallel().tween_property(sm, "emission_energy_multiplier", 2.2, 0.06)
	t.tween_interval(0.2)
	t.tween_callback(func() -> void: _shake(body, 0.006, 8, 0.035)) # bzzt bzzt
	t.tween_interval(0.5)
	return 1.8


# ================================================================ handcuffs

static func _handcuffs() -> Node3D:
	var root := Node3D.new()
	var steel := _m(Color(0.7, 0.7, 0.72), 0.4, 0.8)
	root.scale = Vector3.ONE * 1.3
	var a := _node(root, "A", Vector3(-0.06, 0.025, 0))
	_ring(a, 0.052, 0.04, steel, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	Props.box(a, Vector3(0.04, 0.03, 0.018), steel, Vector3(0.035, -0.035, 0))
	var b := _node(root, "B", Vector3(0.065, -0.02, 0.01))
	b.rotation.z = 0.5
	_ring(b, 0.052, 0.04, steel, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	Props.box(b, Vector3(0.04, 0.03, 0.018), steel, Vector3(-0.035, -0.035, 0))
	var chain := _node(root, "Chain")
	for i in range(3):
		_ring(chain, 0.013, 0.008, steel, Vector3(-0.01 + i * 0.018, -0.06 + absf(i - 1) * 0.01, 0), Vector3(PI / 2.0 if i % 2 == 0 else 0.0, 0, 0))
	return root


static func _animate_handcuffs(model: Node3D, _fx: Node3D) -> float:
	var b: Node3D = model.get_node("B")
	var chain: Node3D = model.get_node("Chain")
	_spin_in(model, -1.5, 0.2)
	var t := b.create_tween()
	t.tween_interval(0.5)
	# swing the open cuff round... and SNAP it shut
	t.tween_property(b, "rotation:z", 1.6, 0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(b, "rotation:z", -0.1, 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(b, "scale", Vector3.ONE * 1.15, 0.05)
	t.tween_property(b, "scale", Vector3.ONE, 0.1)
	t.tween_callback(func() -> void: _shake(model, 0.01, 5))
	var c := chain.create_tween()
	c.tween_interval(0.9)
	for i in range(3):
		c.tween_property(chain, "rotation:x", 0.4, 0.08)
		c.tween_property(chain, "rotation:x", -0.4, 0.08)
	c.tween_property(chain, "rotation:x", 0.0, 0.08)
	return 1.8


# ================================================================ adrenaline

static func _adrenaline() -> Node3D:
	var root := Node3D.new()
	var s := _node(root, "Syringe")
	s.rotation.z = 0.8
	Props.cyl(s, 0.026, 0.026, 0.15, 8, _see(Color(0.8, 0.8, 0.85), 0.35), Vector3(0, 0.0, 0))
	var juice := Props.cyl(s, 0.021, 0.021, 0.13, 8, _g(Color(0.85, 1.0, 0.3), 1.6), Vector3(0, -0.005, 0))
	juice.name = "Juice"
	Props.box(s, Vector3(0.07, 0.008, 0.02), _m(Color(0.75, 0.75, 0.78)), Vector3(0, 0.075, 0))
	var plunger := _node(s, "Plunger", Vector3(0, 0.075, 0))
	Props.cyl(plunger, 0.006, 0.006, 0.07, 6, _m(Color(0.7, 0.7, 0.72)), Vector3(0, 0.035, 0))
	Props.cyl(plunger, 0.022, 0.022, 0.006, 8, _m(Color(0.7, 0.7, 0.72)), Vector3(0, 0.07, 0))
	Props.cyl(s, 0.009, 0.009, 0.015, 6, _m(Color(0.7, 0.7, 0.72)), Vector3(0, -0.082, 0))
	Props.cyl(s, 0.0, 0.0025, 0.06, 4, _m(Color(0.8, 0.8, 0.85), 0.3, 0.9), Vector3(0, -0.12, 0))
	return root


static func _animate_adrenaline(model: Node3D, fx: Node3D) -> float:
	var s: Node3D = model.get_node("Syringe")
	var plunger: Node3D = s.get_node("Plunger")
	var juice: Node3D = s.get_node("Juice")
	_spin_in(model, -1.2, 0.1)
	var t := plunger.create_tween()
	t.tween_interval(0.5)
	t.tween_property(plunger, "position:y", 0.02, 0.6).set_trans(Tween.TRANS_SINE)
	var j := juice.create_tween()
	j.tween_interval(0.5)
	j.tween_property(juice, "scale:y", 0.55, 0.6)
	j.parallel().tween_property(juice, "position:y", -0.035, 0.6)
	# drops of the glowing stuff fall off the needle
	var d := model.create_tween()
	d.tween_interval(0.6)
	for i in range(5):
		d.tween_callback(func() -> void:
			if is_instance_valid(s):
				_fling(fx, s.to_global(Vector3(0, -0.15, 0)), Vector3(randf_range(-0.01, 0.01), -0.12, 0.0), 0.012, Color(0.85, 1.0, 0.3), 0.5, true))
		d.tween_interval(0.13)
	return 1.8


# ================================================================ shakedown

static func _shakedown() -> Node3D:
	var root := Node3D.new()
	var f := _node(root, "Fist")
	var h := _hand(f, _m(Color(0.32, 0.22, 0.16), 0.7), true)
	h.rotation = Vector3(-0.35, 0.5, 0) # the curled fingers and knuckles to you
	f.scale = Vector3.ONE * 1.9
	return root


static func _animate_shakedown(model: Node3D, fx: Node3D) -> float:
	var f: Node3D = model.get_node("Fist")
	var t := f.create_tween()
	t.tween_property(f, "position", Vector3(0.03, 0.0, -0.12), 0.4).set_trans(Tween.TRANS_SINE) # wind up
	t.parallel().tween_property(f, "rotation:z", 0.3, 0.4)
	t.tween_property(f, "position", Vector3(0, 0, 0.1), 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN) # POW
	t.parallel().tween_property(f, "rotation:z", -0.1, 0.09)
	t.tween_callback(func() -> void:
		var at := f.to_global(Vector3(0, 0, 0.06))
		for i in range(10):
			var a := i * TAU / 10.0
			_fling(fx, at, Vector3(cos(a), sin(a), 0.2) * 0.1, 0.012, Color(1.0, 0.9, 0.5), 0.35, true))
	t.tween_callback(func() -> void: _shake(model, 0.015, 6))
	t.tween_interval(0.35)
	t.tween_property(f, "position", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(f, "rotation:z", 0.0, 0.35)
	# a second jab
	t.tween_property(f, "position", Vector3(0, 0, 0.07), 0.08)
	t.tween_property(f, "position", Vector3.ZERO, 0.2)
	return 1.9


# ================================================================ switcheroo

static func _arrow_arc(parent: Node3D, mat: Material, start: float) -> void:
	var r := 0.085
	for i in range(8):
		var a := start + i * PI / 9.0
		var seg := Props.box(parent, Vector3(0.035, 0.03, 0.03), mat, Vector3(cos(a) * r, sin(a) * r, 0))
		seg.rotation.z = a
	var tip := start + 8 * PI / 9.0 + 0.15
	var head := Props.cyl(parent, 0.0, 0.035, 0.05, 4, mat, Vector3(cos(tip) * r, sin(tip) * r, 0))
	head.rotation.z = tip # points round the circle


static func _switcheroo() -> Node3D:
	var root := Node3D.new()
	var ring := _node(root, "Ring")
	_arrow_arc(ring, _m(Color(0.8, 0.25, 0.25), 0.6, 0.3), PI * 0.55)
	_arrow_arc(ring, _m(Color(0.3, 0.45, 0.8), 0.6, 0.3), PI * 1.55)
	return root


static func _animate_switcheroo(model: Node3D, _fx: Node3D) -> float:
	var ring: Node3D = model.get_node("Ring")
	_spin_in(model, -1.2, 0.0)
	var t := ring.create_tween()
	t.tween_interval(0.35)
	t.tween_property(ring, "rotation:z", TAU * 2.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(ring, "scale", Vector3.ONE * 1.15, 0.55).set_trans(Tween.TRANS_SINE)
	t.tween_property(ring, "scale", Vector3.ONE, 0.25)
	return 1.75


# ================================================================ bad trade

static func _bad_trade() -> Node3D:
	var root := Node3D.new()
	var glove := _m(Color(0.33, 0.28, 0.25), 0.8)
	root.scale = Vector3.ONE * 1.5
	var l := _node(root, "L", Vector3(-0.2, 0, 0))
	var hl := _hand(l, glove, false)
	hl.rotation = Vector3(0, 0, -PI / 2.0)
	_sleeve(hl, Color(0.15, 0.15, 0.2))
	var r := _node(root, "R", Vector3(0.2, 0, 0.02))
	var hr := _hand(r, _m(Color(0.42, 0.34, 0.28), 0.8), false)
	hr.rotation = Vector3(0, PI, -PI / 2.0)
	_sleeve(hr, Color(0.35, 0.12, 0.1))
	# the card one of them is slipping across underneath
	var card := Props.box(root, Vector3(0.04, 0.056, 0.003), _m(Color(0.95, 0.93, 0.88)), Vector3(0.0, -0.09, 0.03))
	card.name = "Card"
	card.scale = Vector3.ONE * 0.01
	return root


static func _animate_bad_trade(model: Node3D, _fx: Node3D) -> float:
	var l: Node3D = model.get_node("L")
	var r: Node3D = model.get_node("R")
	var card: Node3D = model.get_node("Card")
	var t := model.create_tween()
	t.tween_property(l, "position:x", -0.035, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(r, "position:x", 0.035, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in range(3):
		t.tween_property(model, "position:y", 0.02, 0.1)
		t.tween_property(model, "position:y", -0.02, 0.1)
	t.tween_property(model, "position:y", 0.0, 0.1)
	# ...while a card slides across underneath
	t.tween_property(card, "scale", Vector3.ONE, 0.15)
	t.tween_property(card, "position:x", 0.12, 0.35).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(card, "rotation:z", -0.6, 0.35)
	return 1.75


## A shirt cuff and a jacket sleeve below a hand's wrist.
static func _sleeve(hand: Node3D, jacket: Color) -> void:
	Props.box(hand, Vector3(0.09, 0.02, 0.04), _m(Color(0.92, 0.9, 0.85)), Vector3(0, -0.055, 0))
	Props.box(hand, Vector3(0.1, 0.12, 0.05), _m(jacket), Vector3(0, -0.125, 0))


# ================================================================ chaos

static func _chaos() -> Node3D:
	var root := Node3D.new()
	var purple := _m(Color(0.55, 0.42, 0.75), 0.7)
	for i in range(6):
		var y := -0.1 + i * 0.04
		var r := 0.03 + i * 0.016
		var ring := _node(root, "R%d" % i, Vector3(sin(i * 1.3) * 0.01, y, 0))
		_ring(ring, r, r - 0.018, purple, Vector3.ZERO)
		Props.box(ring, Vector3(0.022, 0.03, 0.002), _m(Color(0.95, 0.93, 0.88)), Vector3(r, 0.01, 0), Vector3(0, 0.6, 0.3)) # a card caught in it
	return root


static func _animate_chaos(model: Node3D, _fx: Node3D) -> float:
	for i in range(6):
		var ring: Node3D = model.get_node("R%d" % i)
		var t := ring.create_tween()
		t.tween_property(ring, "rotation:y", TAU * (2.0 + i * 0.4), 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var w := model.create_tween()
	for i in range(5):
		w.tween_property(model, "rotation:z", 0.12, 0.17).set_trans(Tween.TRANS_SINE)
		w.tween_property(model, "rotation:z", -0.12, 0.17).set_trans(Tween.TRANS_SINE)
	w.tween_property(model, "rotation:z", 0.0, 0.1)
	return 1.8


# ================================================================ spotlight

static func _spotlight() -> Node3D:
	var root := Node3D.new()
	var metal := _m(Color(0.45, 0.45, 0.43), 0.5, 0.6)
	for a in [0.0, 2.1, 4.2]:
		Props._rod(root, Vector3(0, -0.04, 0), Vector3(cos(a) * 0.06, -0.12, sin(a) * 0.06), 0.006, metal)
	Props._rod(root, Vector3(0, -0.04, 0), Vector3(0, 0.03, 0), 0.008, metal)
	var head := _node(root, "Head", Vector3(0, 0.05, 0))
	head.rotation.z = -0.5
	Props.cyl(head, 0.045, 0.04, 0.1, 8, metal, Vector3(0, 0, 0), Vector3(0, 0, -PI / 2.0))
	var lens := Props.cyl(head, 0.038, 0.038, 0.006, 8, _g(Color(0.3, 0.3, 0.28), 1.0), Vector3(0.052, 0, 0), Vector3(0, 0, -PI / 2.0))
	lens.name = "Lens"
	# an additive beam: black is off, brighter is on
	var beam_m := StandardMaterial3D.new()
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_m.albedo_color = Color(0, 0, 0)
	beam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_m.no_depth_test = false
	var beam := Props.cyl(head, 0.038, 0.11, 0.28, 10, beam_m, Vector3(0.195, 0, 0), Vector3(0, 0, -PI / 2.0))
	beam.name = "Beam"
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _animate_spotlight(model: Node3D, _fx: Node3D) -> float:
	var head: Node3D = model.get_node("Head")
	var beam: MeshInstance3D = head.get_node("Beam")
	var lens: MeshInstance3D = head.get_node("Lens")
	var bm: StandardMaterial3D = beam.material_override
	var lm: StandardMaterial3D = lens.material_override
	_spin_in(model, -1.0, 0.4)
	var t := head.create_tween()
	t.tween_interval(0.45)
	t.tween_property(head, "rotation:z", -0.15, 0.3).set_trans(Tween.TRANS_SINE)
	# it clunks on: flicker, flicker, full beam
	for a in [0.35, 0.0, 0.25, 0.0, 0.4]:
		t.tween_property(bm, "albedo_color", Color(1.0, 0.96, 0.85) * a, 0.05)
		t.parallel().tween_property(lm, "albedo_color", Color(1, 0.97, 0.85) if a > 0.0 else Color(0.3, 0.3, 0.28), 0.05)
	t.tween_property(head, "rotation:z", -0.6, 0.6).set_trans(Tween.TRANS_SINE)
	return 1.85


# ================================================================ flashbang

static func _flashbang() -> Node3D:
	var root := Node3D.new()
	var g := _node(root, "Grenade")
	Props.cyl(g, 0.032, 0.032, 0.13, 8, _m(Color(0.75, 0.66, 0.55)), Vector3(0, -0.02, 0))
	Props.cyl(g, 0.033, 0.033, 0.03, 8, _m(Color(0.3, 0.45, 0.4)), Vector3(0, -0.02, 0))
	Props.cyl(g, 0.034, 0.034, 0.02, 8, _m(Color(0.35, 0.36, 0.33)), Vector3(0, -0.08, 0))
	Props.box(g, Vector3(0.03, 0.03, 0.03), _m(Color(0.4, 0.4, 0.38), 0.5, 0.6), Vector3(0, 0.06, 0))
	var spoon := _node(g, "Spoon", Vector3(0.018, 0.07, 0))
	Props.box(spoon, Vector3(0.008, 0.11, 0.016), _m(Color(0.42, 0.42, 0.4), 0.5, 0.6), Vector3(0.012, -0.05, 0))
	var pin := _node(g, "Pin", Vector3(0.035, 0.06, 0))
	_ring(pin, 0.02, 0.016, _m(Color(0.6, 0.6, 0.6), 0.4, 0.8), Vector3(0.015, 0, 0), Vector3(PI / 2.0, 0, 0))
	return root


static func _animate_flashbang(model: Node3D, fx: Node3D) -> float:
	var g: Node3D = model.get_node("Grenade")
	var spoon: Node3D = g.get_node("Spoon")
	var pin: Node3D = g.get_node("Pin")
	_spin_in(model, -1.2, 0.2)
	var t := g.create_tween()
	t.tween_interval(0.45)
	t.tween_property(pin, "position", Vector3(0.14, 0.12, 0.05), 0.2).set_ease(Tween.EASE_OUT) # pin out
	t.parallel().tween_property(pin, "rotation:z", 3.0, 0.2)
	t.tween_property(spoon, "rotation:z", -2.2, 0.15) # spoon flies
	t.parallel().tween_property(spoon, "position", Vector3(0.1, 0.13, 0), 0.15)
	t.tween_callback(func() -> void: _shake(g, 0.006, 6, 0.04)) # fizzing...
	t.tween_interval(0.3)
	t.tween_callback(func() -> void:
		var at := g.global_position
		g.visible = false
		var m := _g(Color(1, 1, 1), 6.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var flash := Props.ball(fx, 0.05, 10, m, fx.to_local(at))
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l := OmniLight3D.new()
		l.light_energy = 12.0
		l.omni_range = 2.5
		flash.add_child(l)
		var ft := flash.create_tween()
		m.albedo_color.a = 0.85
		ft.tween_property(flash, "scale", Vector3.ONE * 3.5, 0.15).set_ease(Tween.EASE_OUT)
		ft.parallel().tween_property(l, "light_energy", 0.0, 0.5)
		ft.tween_property(m, "albedo_color:a", 0.0, 0.3)
		ft.tween_callback(flash.queue_free))
	t.tween_interval(0.45)
	return 1.85


# ================================================================ revolver

static func _revolver() -> Node3D:
	var root := Node3D.new()
	var steel := _m(Color(0.32, 0.32, 0.33), 0.5, 0.7)
	var gun := _node(root, "Gun")
	Props.box(gun, Vector3(0.09, 0.04, 0.025), steel, Vector3(0.0, 0.03, 0))
	Props.cyl(gun, 0.012, 0.012, 0.1, 8, steel, Vector3(-0.08, 0.042, 0), Vector3(0, 0, PI / 2.0))
	Props.box(gun, Vector3(0.04, 0.1, 0.03), _m(Color(0.35, 0.2, 0.12)), Vector3(0.055, -0.04, 0), Vector3(0, 0, -0.3))
	Props.box(gun, Vector3(0.012, 0.03, 0.01), steel, Vector3(0.04, 0.06, 0), Vector3(0, 0, -0.5)) # hammer
	var cyl := _node(gun, "Cylinder", Vector3(-0.01, 0.0, 0.05)) # swung out
	Props.cyl(cyl, 0.035, 0.035, 0.04, 8, steel, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	for i in range(6):
		var a := i * TAU / 6.0
		var p := Vector3(cos(a) * 0.022, sin(a) * 0.022, 0.021)
		if i == 0:
			Props.cyl(cyl, 0.007, 0.007, 0.006, 6, _m(Color(0.85, 0.65, 0.25), 0.3, 0.8), p, Vector3(PI / 2.0, 0, 0))
		else:
			Props.cyl(cyl, 0.007, 0.007, 0.004, 6, _m(Color(0.04, 0.04, 0.04)), p, Vector3(PI / 2.0, 0, 0))
	return root


static func _animate_revolver(model: Node3D, _fx: Node3D) -> float:
	var gun: Node3D = model.get_node("Gun")
	var cyl: Node3D = gun.get_node("Cylinder")
	_spin_in(model, -1.0, 0.35)
	var t := cyl.create_tween()
	t.tween_interval(0.35)
	t.tween_property(cyl, "rotation:z", TAU * 4.0 + randf() * TAU, 1.0).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT) # spin...
	t.tween_property(cyl, "position", Vector3(-0.01, 0.0, 0.0), 0.08) # ...snap it in
	t.tween_callback(func() -> void: _shake(gun, 0.006, 3, 0.03))
	t.tween_interval(0.3)
	return 1.8


# ================================================================ double down

static func _die(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var d := _node(parent, n, pos)
	Props.box(d, Vector3(0.065, 0.065, 0.065), _m(Color(0.78, 0.3, 0.26), 0.6), Vector3.ZERO)
	var pip := _m(Color(0.45, 0.08, 0.08))
	var six := [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]
	for p in six: # six facing you
		Props.box(d, Vector3(0.011, 0.011, 0.004), pip, Vector3(p.x * 0.017, p.y * 0.018, 0.033))
	for p in six: # and six on top
		Props.box(d, Vector3(0.011, 0.004, 0.011), pip, Vector3(p.x * 0.017, 0.033, p.y * 0.018))
	return d


static func _double_down() -> Node3D:
	var root := Node3D.new()
	_die(root, "A", Vector3(-0.045, -0.04, 0))
	_die(root, "B", Vector3(0.045, -0.04, 0.01))
	return root


static func _animate_double_down(model: Node3D, _fx: Node3D) -> float:
	for n in ["A", "B"]:
		var d: Node3D = model.get_node(n)
		var land := d.position
		d.position = land + Vector3(0, 0.18, -0.05)
		d.rotation = Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0)
		var t := d.create_tween()
		t.tween_interval(0.15 if n == "A" else 0.28)
		t.tween_property(d, "position", land, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(d, "rotation", Vector3(0.25, -0.35 if n == "A" else 0.3, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(d, "scale", Vector3.ONE * 1.15, 0.1)
		t.tween_property(d, "scale", Vector3.ONE, 0.12)
	return 1.6


# ================================================================ sticky fingers

static func _sticky_fingers() -> Node3D:
	var root := Node3D.new()
	var skin := _m(Color(0.62, 0.48, 0.45), 0.8)
	var h := _hand(root, skin, false)
	root.scale = Vector3.ONE * 2.0
	h.position = Vector3(0, -0.04, 0)
	h.rotation.z = -0.35
	var honey := _see(Color(0.95, 0.65, 0.15), 0.85)
	Props.ball(h, 0.04, 8, honey, Vector3(0.0, -0.005, 0.018)).scale = Vector3(1, 0.9, 0.4)
	for i in range(4):
		var f: Node3D = h.get_node("F%d" % i)
		Props.ball(f, 0.012, 6, honey, Vector3(0, 0.06, 0.012))
		Props._rod(h, Vector3(0, 0, 0.02), f.position + Vector3(0, 0.05, 0.012), 0.003, honey)
	return root


static func _animate_sticky_fingers(model: Node3D, fx: Node3D) -> float:
	var h: Node3D = model.get_node("Hand")
	_spin_in(model, -1.0, 0.2)
	var t := h.create_tween()
	t.tween_interval(0.4)
	# the fingers flex, stretching the honey...
	for k in range(2):
		for i in range(4):
			var f: Node3D = h.get_node("F%d" % i)
			t.parallel().tween_property(f, "rotation:z", (i - 1.5) * 0.18, 0.25).set_trans(Tween.TRANS_SINE)
		t.tween_interval(0.25)
		for i in range(4):
			var f: Node3D = h.get_node("F%d" % i)
			t.parallel().tween_property(f, "rotation:x", 0.5, 0.25).set_trans(Tween.TRANS_SINE)
		t.tween_interval(0.25)
		for i in range(4):
			var f: Node3D = h.get_node("F%d" % i)
			t.parallel().tween_property(f, "rotation:x", 0.0, 0.2)
	# ...and it drips
	var d := model.create_tween()
	d.tween_interval(0.6)
	for i in range(6):
		d.tween_callback(func() -> void:
			if is_instance_valid(h):
				_fling(fx, h.to_global(Vector3(randf_range(-0.03, 0.03), -0.045, 0.02)), Vector3(0, -0.13, 0.01), 0.012, Color(0.95, 0.65, 0.15), 0.6))
		d.tween_interval(0.16)
	return 1.9


# ================================================================ dumpster dive

static func _dumpster_dive() -> Node3D:
	var root := Node3D.new()
	var green := _m(Color(0.25, 0.48, 0.3), 0.7, 0.3)
	Props.box(root, Vector3(0.2, 0.11, 0.12), green, Vector3(0, -0.06, 0))
	Props.box(root, Vector3(0.21, 0.012, 0.13), green, Vector3(0, -0.003, 0))
	for x in [-0.11, 0.11]:
		Props.box(root, Vector3(0.012, 0.03, 0.08), green, Vector3(x, -0.03, 0))
	for c in [[Color(0.6, 0.5, 0.35), Vector3(-0.05, 0.005, 0)], [Color(0.1, 0.1, 0.12), Vector3(0.05, 0.01, -0.01)], [Color(0.35, 0.3, 0.2), Vector3(0.0, 0.0, 0.03)]]:
		Props.box(root, Vector3(0.05, 0.035, 0.05), _m(c[0]), c[1], Vector3(0.2, 0.5, 0.1))
	var lid := _node(root, "Lid", Vector3(0, 0.0, -0.06))
	Props.box(lid, Vector3(0.21, 0.01, 0.125), _m(Color(0.2, 0.38, 0.25), 0.6, 0.3), Vector3(0, 0.0, 0.062))
	var cards := _node(root, "Cards")
	for i in range(3):
		var c := Props.box(cards, Vector3(0.042, 0.06, 0.003), _m(Color(0.95, 0.93, 0.88)), Vector3(-0.03 + i * 0.03, -0.01, 0.0))
		c.name = "C%d" % i
		c.visible = false
	return root


static func _animate_dumpster_dive(model: Node3D, _fx: Node3D) -> float:
	var lid: Node3D = model.get_node("Lid")
	var cards: Node3D = model.get_node("Cards")
	_spin_in(model, -0.9, 0.3)
	var t := lid.create_tween()
	t.tween_interval(0.4)
	t.tween_property(lid, "rotation:x", -1.9, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) # lid flies up
	# three cards pop out of the rubbish
	for i in range(3):
		var c: Node3D = cards.get_node("C%d" % i)
		var ct := c.create_tween()
		ct.tween_interval(0.75 + i * 0.15)
		ct.tween_callback(func() -> void: c.visible = true)
		ct.tween_property(c, "position", Vector3(-0.07 + i * 0.07, 0.12, 0.06), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(c, "rotation", Vector3(0, TAU, (1 - i) * 0.3), 0.3)
	return 1.75


# ================================================================ garbage day

static func _garbage_day() -> Node3D:
	var root := Node3D.new()
	var tin := _m(Color(0.58, 0.57, 0.52), 0.6, 0.5)
	var can := _node(root, "Can", Vector3(0.0, -0.1, 0))
	Props.cyl(can, 0.06, 0.055, 0.15, 10, tin, Vector3(0, 0.075, 0))
	_ring(can, 0.064, 0.056, tin, Vector3(0, 0.15, 0))
	var junk := _node(root, "Junk")
	var bits := [[Vector3(0.04, 0.03, 0.04), Color(0.55, 0.45, 0.3)], [Vector3(0.05, 0.05, 0.05), Color(0.1, 0.1, 0.12)], [Vector3(0.03, 0.02, 0.04), Color(0.8, 0.78, 0.7)], [Vector3(0.02, 0.04, 0.02), Color(0.7, 0.2, 0.2)], [Vector3(0.035, 0.035, 0.035), Color(0.5, 0.42, 0.3)], [Vector3(0.025, 0.02, 0.025), Color(0.4, 0.5, 0.35)]]
	for i in range(bits.size()):
		var b := Props.box(junk, bits[i][0], _m(bits[i][1]), Vector3(0, -0.02, 0))
		b.name = "J%d" % i
		b.visible = false
	return root


static func _animate_garbage_day(model: Node3D, _fx: Node3D) -> float:
	var can: Node3D = model.get_node("Can")
	var junk: Node3D = model.get_node("Junk")
	_spin_in(model, -0.8, 0.35)
	var t := can.create_tween()
	t.tween_interval(0.4)
	t.tween_property(can, "rotation:z", -0.2, 0.12)
	t.tween_property(can, "rotation:z", 0.15, 0.12)
	t.tween_property(can, "rotation:z", -PI / 2.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT) # over it goes
	# and everything spills out across the floor
	for i in range(junk.get_child_count()):
		var b: Node3D = junk.get_child(i)
		var bt := b.create_tween()
		bt.tween_interval(0.85 + i * 0.07)
		bt.tween_callback(func() -> void:
			b.visible = true
			b.position = Vector3(0.14, -0.06, 0))
		bt.tween_property(b, "position", Vector3(0.17 + i * 0.025, -0.09, -0.04 + (i % 3) * 0.05), 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		bt.parallel().tween_property(b, "rotation", Vector3(randf() * 3.0, randf() * 3.0, randf() * 3.0), 0.3)
	return 1.75


# ================================================================ tarot (crystal ball)

static func _tarot() -> Node3D:
	var root := Node3D.new()
	var brass := _m(Color(0.6, 0.5, 0.28), 0.5, 0.6)
	Props.cyl(root, 0.05, 0.065, 0.04, 8, brass, Vector3(0, -0.1, 0))
	_ring(root, 0.052, 0.042, brass, Vector3(0, -0.075, 0))
	var orb := _see(Color(0.6, 0.5, 0.8), 0.55)
	Props.ball(root, 0.075, 12, orb, Vector3(0, 0.0, 0))
	var swirl := _node(root, "Swirl")
	for i in range(3):
		var a := i * TAU / 3.0
		var w := Props.ball(swirl, 0.018, 6, _g(Color(0.85, 0.6, 1.0), 2.0), Vector3(cos(a) * 0.035, sin(a * 2.0) * 0.015, sin(a) * 0.035))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = Color(0.75, 0.5, 1.0)
	l.light_energy = 0.5
	l.omni_range = 0.4
	root.add_child(l)
	return root


static func _animate_tarot(model: Node3D, fx: Node3D) -> float:
	var swirl: Node3D = model.get_node("Swirl")
	var l: OmniLight3D = model.get_node("Glow")
	var t := swirl.create_tween()
	t.tween_property(swirl, "rotation", Vector3(0.6, TAU * 3.0, 0.3), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var g := l.create_tween()
	for i in range(3):
		g.tween_property(l, "light_energy", 2.5, 0.25)
		g.tween_property(l, "light_energy", 0.6, 0.25)
	# a vision: sparkles rise off the glass
	g.tween_callback(func() -> void:
		for i in range(8):
			var a := i * TAU / 8.0
			_fling(fx, model.to_global(Vector3(cos(a) * 0.06, 0.02, sin(a) * 0.06)), Vector3(cos(a) * 0.05, 0.12, sin(a) * 0.05), 0.01, Color(0.9, 0.75, 1.0), 0.6, true))
	return 1.8


# ================================================================ joker paint

static func _joker_paint() -> Node3D:
	var root := Node3D.new()
	var mask := _node(root, "Mask")
	var face := Props.ball(mask, 0.09, 10, _m(Color(0.9, 0.87, 0.8), 0.7), Vector3.ZERO)
	face.scale = Vector3(0.85, 1.05, 0.45)
	var dark := _m(Color(0.05, 0.04, 0.05))
	for x in [-0.03, 0.03]:
		Props.box(mask, Vector3(0.028, 0.014, 0.01), dark, Vector3(x, 0.025, 0.038), Vector3(0, 0, -0.25 if x < 0 else 0.25))
	var grin := _node(mask, "Grin", Vector3(0, -0.035, 0.036))
	for i in range(7):
		var a := (i - 3) * 0.28
		Props.box(grin, Vector3(0.014, 0.012, 0.01), dark, Vector3(sin(a) * 0.045, (1.0 - cos(a)) * 0.03, 0.0), Vector3(0, 0, a))
	grin.scale = Vector3(0.4, 0.4, 1)
	var splats := _node(mask, "Splats")
	var cols := [Color(0.9, 0.15, 0.15), Color(0.95, 0.85, 0.15), Color(0.2, 0.45, 0.95), Color(0.9, 0.15, 0.15), Color(0.95, 0.85, 0.15), Color(0.2, 0.45, 0.95)]
	var spots := [Vector3(-0.05, 0.06, 0.03), Vector3(0.05, 0.05, 0.032), Vector3(-0.055, -0.01, 0.034), Vector3(0.06, -0.02, 0.03), Vector3(-0.02, 0.08, 0.025), Vector3(0.03, -0.07, 0.028)]
	for i in range(6):
		var sp := Props.box(splats, Vector3(0.03, 0.025, 0.006), _m(cols[i], 0.5), spots[i], Vector3(0, 0, randf() * 3.0))
		sp.scale = Vector3.ONE * 0.01
	return root


static func _animate_joker_paint(model: Node3D, _fx: Node3D) -> float:
	var mask: Node3D = model.get_node("Mask")
	var grin: Node3D = mask.get_node("Grin")
	var splats: Node3D = mask.get_node("Splats")
	_spin_in(model, -1.4, 0.25)
	var t := splats.create_tween()
	t.tween_interval(0.45)
	# splat, splat, splat: paint flies on
	for i in range(splats.get_child_count()):
		var sp: Node3D = splats.get_child(i)
		t.tween_property(sp, "scale", Vector3.ONE * 1.3, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(sp, "scale", Vector3.ONE, 0.05)
	# ...and it grins
	var g := grin.create_tween()
	g.tween_interval(1.2)
	g.tween_property(grin, "scale", Vector3(1.15, 1.1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var w := mask.create_tween()
	w.tween_interval(1.2)
	w.tween_property(mask, "rotation:z", 0.15, 0.15)
	w.tween_property(mask, "rotation:z", -0.12, 0.15)
	w.tween_property(mask, "rotation:z", 0.0, 0.12)
	return 1.9
