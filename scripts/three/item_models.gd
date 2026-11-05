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
	return item_id in ["cigarettes"]


## The model for `item_id`, or null.
static func build(item_id: String) -> Node3D:
	match item_id:
		"cigarettes":
			return _cigarettes()
	return null


## Plays the model's animation. `fx` is where loose bits (smoke...) go so
## they drift on their own. Returns how long it takes, in seconds.
static func animate(model: Node3D, item_id: String, fx: Node3D) -> float:
	match item_id:
		"cigarettes":
			return _animate_cigarettes(model, fx)
	return 0.0


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
