extends Node3D
## The gacha machine standing in the corner of the room: a red cabinet, a
## glass globe full of capsules, a coin slot, a crank and a chute. spin()
## plays the whole thing: the coin goes in, the crank turns, the capsules
## tumble, one drops out, wobbles (more for rarer prizes) and pops open.
##
## The front faces +Z. Sounds go out through `sfx` (the world passes them
## on), the burst of light and sparks through `burst`.

signal sfx(name: String)
signal burst(at: Vector3, color: Color, count: int)
signal dropped # the capsule has landed in the tray

const Props = preload("res://scripts/three/props.gd")

const CAPSULE_COLORS := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.8, 0.2), Color(0.4, 0.85, 0.4), Color(0.8, 0.45, 1.0), Color(1.0, 0.55, 0.2)]
const GLOBE_Y := 1.08
const GLOBE_R := 0.3
const SLOT := Vector3(-0.08, 0.54, 0.24)
const CHUTE_IN := Vector3(0.0, 0.3, 0.12)
const CHUTE_OUT := Vector3(0.0, 0.25, 0.27)
const TRAY := Vector3(0.0, 0.205, 0.36)

var busy := false
var _capsules: Array = [] # [node, home position]
var _crank: Node3D
var _globe: Node3D
var _bulbs: Array = [] # [material, base colour]
var _glow_light: OmniLight3D
var _prize: Node3D # the capsule that drops out
var _coin: MeshInstance3D


func _ready() -> void:
	_build()


## A capsule: a coloured bottom half, a white top half.
static func capsule(color: Color, r: float) -> Node3D:
	var n := Node3D.new()
	var top := SphereMesh.new()
	top.radius = r
	top.height = r
	top.is_hemisphere = true
	top.radial_segments = 12
	top.rings = 4
	var top_mi := Props.mesh(n, top, Props.plain(Color(0.95, 0.95, 0.97), 0.25), Vector3.ZERO)
	top_mi.name = "Top"
	var bottom := SphereMesh.new()
	bottom.radius = r
	bottom.height = r
	bottom.is_hemisphere = true
	bottom.radial_segments = 12
	bottom.rings = 4
	var bottom_mi := Props.mesh(n, bottom, Props.plain(color, 0.3), Vector3.ZERO, Vector3(PI, 0, 0))
	bottom_mi.name = "Bottom"
	# the seam round the middle
	var seam := TorusMesh.new()
	seam.inner_radius = r * 0.97
	seam.outer_radius = r * 1.04
	seam.rings = 12
	seam.ring_segments = 3
	Props.mesh(n, seam, Props.plain(color.darkened(0.35), 0.4), Vector3.ZERO)
	return n


func _build() -> void:
	var red := Props.plain(Color(0.72, 0.1, 0.08), 0.45, 0.1)
	var dark_red := Props.plain(Color(0.42, 0.05, 0.04), 0.5)
	var chrome := Props.tex_mat("metal", Color(0.95, 0.95, 0.95), 5.0, 0.25, 0.9)
	var gold := Props.plain(Color(0.95, 0.75, 0.25), 0.3, 0.8)
	var black := Props.plain(Color(0.05, 0.05, 0.05), 0.8)
	# feet, cabinet, trim
	for x in [-0.23, 0.23]:
		for z in [-0.18, 0.18]:
			Props.box(self, Vector3(0.07, 0.06, 0.07), black, Vector3(x, 0.03, z))
	Props.box(self, Vector3(0.56, 0.64, 0.46), red, Vector3(0, 0.38, 0))
	Props.box(self, Vector3(0.6, 0.05, 0.5), dark_red, Vector3(0, 0.725, 0))
	Props.box(self, Vector3(0.6, 0.04, 0.5), dark_red, Vector3(0, 0.08, 0))
	# the sign on the front
	var sign := Label3D.new()
	sign.text = "GACHA"
	sign.font = load("res://fonts/VT323.woff2")
	sign.font_size = 72
	sign.pixel_size = 0.0018
	sign.modulate = Color(1.0, 0.88, 0.4)
	sign.outline_size = 10
	sign.outline_modulate = Color(0.3, 0.02, 0.02)
	sign.position = Vector3(0, 0.655, 0.236)
	add_child(sign)
	# coin plate and slot
	Props.box(self, Vector3(0.34, 0.15, 0.012), gold, Vector3(0, 0.51, 0.232))
	Props.box(self, Vector3(0.06, 0.014, 0.01), black, SLOT + Vector3(0, 0, 0.004))
	var price := Label3D.new()
	price.text = "1 COIN"
	price.font = sign.font
	price.font_size = 40
	price.pixel_size = 0.0014
	price.modulate = Color(0.25, 0.08, 0.02)
	price.position = SLOT + Vector3(0, -0.045, 0.01)
	add_child(price)
	# the crank: a disc with a handle, on a pivot that turns
	_crank = Node3D.new()
	_crank.position = Vector3(0.08, 0.51, 0.245)
	add_child(_crank)
	Props.cyl(_crank, 0.055, 0.055, 0.025, 14, chrome, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	Props.box(_crank, Vector3(0.016, 0.1, 0.016), black, Vector3(0, 0, 0.02))
	Props.ball(_crank, 0.016, 8, gold, Vector3(0, 0.045, 0.03))
	# the chute and its tray
	Props.box(self, Vector3(0.18, 0.12, 0.012), black, Vector3(0, 0.27, 0.232))
	Props.box(self, Vector3(0.22, 0.02, 0.14), chrome, Vector3(0, 0.185, 0.3))
	Props.box(self, Vector3(0.22, 0.05, 0.015), chrome, Vector3(0, 0.205, 0.37))
	# the globe on a chrome collar, with a cap on top
	Props.cyl(self, 0.22, 0.25, 0.07, 18, chrome, Vector3(0, 0.78, 0))
	_globe = Node3D.new()
	_globe.position = Vector3(0, GLOBE_Y, 0)
	add_child(_globe)
	var glass := Props.plain(Color(0.85, 0.92, 1.0, 0.16), 0.02, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.render_priority = 1
	var sphere := SphereMesh.new()
	sphere.radius = GLOBE_R
	sphere.height = GLOBE_R * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var globe_mi := Props.mesh(_globe, sphere, glass, Vector3.ZERO)
	globe_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Props.cyl(self, 0.09, 0.12, 0.06, 14, red, Vector3(0, GLOBE_Y + GLOBE_R + 0.01, 0))
	Props.ball(self, 0.035, 8, gold, Vector3(0, GLOBE_Y + GLOBE_R + 0.06, 0))
	# capsules piled in the globe
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in range(30):
		var c := capsule(CAPSULE_COLORS[i % CAPSULE_COLORS.size()], 0.05)
		var a := rng.randf() * TAU
		var layer := float(i / 9)
		var d := rng.randf_range(0.0, 0.2 - layer * 0.03)
		var home := Vector3(cos(a) * d, -0.2 + layer * 0.085 + rng.randf() * 0.03, sin(a) * d)
		c.position = home
		c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_globe.add_child(c)
		_capsules.append([c, home])
	# a ring of bulbs round the collar
	for i in range(10):
		var a := i * TAU / 10.0
		var base: Color = CAPSULE_COLORS[i % CAPSULE_COLORS.size()]
		var m := Props.glow(base.darkened(0.3), 1.0)
		Props.ball(self, 0.014, 6, m, Vector3(cos(a) * 0.255, 0.8, sin(a) * 0.255))
		_bulbs.append([m, base])
	# a little light inside the globe
	_glow_light = OmniLight3D.new()
	_glow_light.position = Vector3(0, GLOBE_Y, 0.05)
	_glow_light.light_color = Color(1.0, 0.85, 0.6)
	_glow_light.light_energy = 0.2
	_glow_light.omni_range = 0.9
	add_child(_glow_light)
	# the prize capsule, out of sight until it drops
	_prize = capsule(Color.WHITE, 0.055)
	_prize.visible = false
	add_child(_prize)
	# the coin
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.034
	coin_mesh.bottom_radius = 0.034
	coin_mesh.height = 0.008
	coin_mesh.radial_segments = 14
	_coin = Props.mesh(self, coin_mesh, gold, Vector3.ZERO)
	_coin.visible = false


## Where the prize capsule sits once it's out, in world space (for the camera).
func tray_point() -> Vector3:
	return to_global(TRAY)


## Idle: the bulbs chase round slowly.
func _process(_delta: float) -> void:
	if not is_visible_in_tree() or busy:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in range(_bulbs.size()):
		var lit := int(t * 3.0) % _bulbs.size() == i
		_bulbs[i][0].albedo_color = _bulbs[i][1] if lit else _bulbs[i][1].darkened(0.45)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## The whole spin. `color` is the prize capsule's colour (its rarity) and
## `wobbles` how many times it shakes before opening (rarer: more).
## Returns when the capsule has popped open.
func spin(color: Color, wobbles: int) -> void:
	busy = true
	_reset_prize()
	# 1. the coin flips up and drops into the slot
	_coin.visible = true
	_coin.position = Vector3(-0.12, 0.72, 0.62)
	_coin.rotation = Vector3(PI / 2.0, 0, 0)
	sfx.emit("coin_flip")
	var t := create_tween()
	t.tween_property(_coin, "position", SLOT + Vector3(0, 0.1, 0.06), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_coin, "rotation:y", TAU * 3.0, 0.35)
	t.tween_property(_coin, "rotation", Vector3(PI / 2.0, 0, PI / 2.0), 0.08)
	t.tween_property(_coin, "position", SLOT + Vector3(0, 0, 0.02), 0.12)
	t.tween_property(_coin, "position", SLOT + Vector3(0, 0, -0.04), 0.1)
	if t.is_running():
		await t.finished
	_coin.visible = false
	sfx.emit("coin_in")
	_flash_bulbs(Color(1.0, 0.85, 0.3), 2)
	await _wait(0.25)
	# 2. the crank turns twice, clicking; the capsules tumble
	var turns := 2.0
	var tc := create_tween()
	tc.tween_property(_crank, "rotation:z", _crank.rotation.z - TAU * turns, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tumble(1.5)
	sfx.emit("rattle")
	for i in range(int(turns * 4)):
		sfx.emit("crank")
		if i == 4:
			sfx.emit("rattle")
		await _wait(1.5 / (turns * 4))
	if tc.is_running():
		await tc.finished
	# 3. a capsule drops down the chute and bounces into the tray
	for c in _prize.get_children():
		if c.name == "Bottom":
			(c as MeshInstance3D).material_override = Props.plain(color, 0.3)
	_prize.position = CHUTE_IN
	_prize.visible = true
	var td := create_tween()
	td.tween_property(_prize, "position", CHUTE_OUT, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	td.tween_property(_prize, "position", TRAY + Vector3(0, 0.06, -0.02), 0.12)
	td.tween_property(_prize, "position", TRAY, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	td.tween_property(_prize, "position", TRAY + Vector3(0, 0.025, 0.01), 0.08).set_ease(Tween.EASE_OUT)
	td.tween_property(_prize, "position", TRAY + Vector3(0, 0, 0.02), 0.08).set_ease(Tween.EASE_IN)
	td.parallel().tween_property(_prize, "rotation:x", TAU * 0.75, 0.5)
	sfx.emit("capsule_drop")
	if td.is_running():
		await td.finished
	_prize.rotation = Vector3.ZERO
	dropped.emit()
	await _wait(0.7)
	# 4. it wobbles: once for a common prize, up to four times for a legendary
	for i in range(wobbles):
		sfx.emit("capsule_wobble")
		var tw := create_tween()
		var lean := 0.25 + i * 0.08
		tw.tween_property(_prize, "rotation:z", lean, 0.07)
		tw.tween_property(_prize, "rotation:z", -lean, 0.12)
		tw.tween_property(_prize, "rotation:z", 0.0, 0.07)
		if i >= 2:
			_flash_bulbs(color, 1)
		if tw.is_running():
			await tw.finished
		await _wait(0.28 - i * 0.04)
	# 5. pop! the halves fly apart, light and sparks in the prize's colour
	sfx.emit("capsule_pop")
	var top: Node3D = _prize.get_node("Top")
	var bottom: Node3D = _prize.get_node("Bottom")
	var tp := create_tween()
	tp.tween_property(top, "position", Vector3(0.02, 0.14, -0.03), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tp.parallel().tween_property(top, "rotation", Vector3(-1.2, 0.4, 0.3), 0.3)
	tp.parallel().tween_property(bottom, "position", Vector3(0, -0.01, 0.02), 0.2)
	burst.emit(to_global(TRAY + Vector3(0, 0.04, 0)), color, 6 + wobbles * 4)
	_flash_bulbs(color, 3 + wobbles)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 1.4
	light.position = TRAY + Vector3(0, 0.08, 0.05)
	add_child(light)
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 4.0 + wobbles, 0.08)
	tl.tween_property(light, "light_energy", 0.0, 0.9)
	tl.tween_callback(light.queue_free)
	if tp.is_running():
		await tp.finished
	await _wait(0.25)
	busy = false


## Put the last prize capsule away.
func _reset_prize() -> void:
	_prize.visible = false
	_prize.rotation = Vector3.ZERO
	var top: Node3D = _prize.get_node("Top")
	var bottom: Node3D = _prize.get_node("Bottom")
	top.position = Vector3.ZERO
	top.rotation = Vector3.ZERO
	bottom.position = Vector3.ZERO
	bottom.rotation = Vector3(PI, 0, 0)


## The capsules jostle about inside the globe for `seconds`.
func _tumble(seconds: float) -> void:
	var gt := create_tween()
	for i in range(6):
		gt.tween_property(_globe, "position", Vector3(randf_range(-0.012, 0.012), GLOBE_Y + randf_range(0, 0.008), 0), seconds / 6.0)
	gt.tween_property(_globe, "position", Vector3(0, GLOBE_Y, 0), 0.1)
	for entry in _capsules:
		var c: Node3D = entry[0]
		var home: Vector3 = entry[1]
		var ct := c.create_tween()
		var hops := 3
		for k in range(hops):
			var lift := Vector3(randf_range(-0.05, 0.05), randf_range(0.03, 0.12), randf_range(-0.05, 0.05))
			ct.tween_property(c, "position", (home + lift).limit_length(0.22), seconds / (hops * 2.0)).set_trans(Tween.TRANS_SINE)
			ct.parallel().tween_property(c, "rotation", c.rotation + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), seconds / (hops * 2.0))
			ct.tween_property(c, "position", home, seconds / (hops * 2.0)).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## The bulbs blink in `color`, `times` times.
func _flash_bulbs(color: Color, times: int) -> void:
	var t := create_tween()
	for k in range(times):
		t.tween_callback(func() -> void:
			for b in _bulbs:
				b[0].albedo_color = color)
		t.tween_interval(0.08)
		t.tween_callback(func() -> void:
			for b in _bulbs:
				b[0].albedo_color = b[1].darkened(0.45))
		t.tween_interval(0.08)
