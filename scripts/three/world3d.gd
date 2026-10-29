extends Node3D
## The 3D table: a dark room, a hanging lamp, a felt table, the players in
## their seats, the shotgun, and every card. You sit at the near edge; your
## hand is held in front of the camera.
##
## main.gd calls sync() with what to show after every change, pick() to find
## what a tap hit, and fire() for shotgun blasts. Cards keep their identity
## between syncs, so they slide from the stock to your hand, from your hand to
## the table, and so on.

## Shuffling and dealing at the start of a round has finished.
signal deal_finished

const Cards = preload("res://scripts/core/cards.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardTextures = preload("res://scripts/three/card_textures.gd")
const Card3D = preload("res://scripts/three/card3d.gd")

const TABLE_TOP := 0.03
const TABLE_RX := 0.95 # the table is an oval
const TABLE_RZ := 1.25
const TABLE_CARD := Vector2(0.15, 0.215)
const HAND_CARD := Vector2(0.105, 0.152)
const ITEM_CARD := Vector2(0.075, 0.1)
const OPP_CARD := Vector2(0.09, 0.13)
const SEAT_RX := 1.08
const SEAT_RZ := 1.5
const MOVE_TIME := 0.28
const LAMP := 4.0
const DEAL_STEP := 0.09 # seconds between dealt cards
const TRUMP_NAMES := ["", "ACES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "SEVENS", "EIGHTS", "NINES", "TENS", "JACKS", "QUEENS", "KINGS"]
const FIGURE_COLORS := [Color(0.16, 0.13, 0.11), Color(0.22, 0.06, 0.06), Color(0.07, 0.12, 0.16), Color(0.12, 0.15, 0.07), Color(0.17, 0.1, 0.17), Color(0.2, 0.16, 0.06)]

var textures: CardTextures
var camera: Camera3D
var lamp: SpotLight3D
var shotgun: Node3D

var _font: Font
var _cards_root: Node3D
var _labels_root: Node3D
var _figures := {} # seat -> { node, head, eyes, label }
var _cards := {} # id -> Card3D
var _outline_mats := {}
var _back_mat: StandardMaterial3D
var _cam_home := Transform3D()
var _menu_mode := true
var _menu_t := 0.0
var _last := {} # the last sync, so we can redo it when textures arrive
var _viewer := 0
var _gun_pose := ""
var _landscape := false
var dealing := false # shuffle/deal animation running; taps should wait
var _round_seen := 0
var _deal := {} # while dealing: { "deck": Transform3D, "order": { id: n }, "start": seconds }
var _resync := false
var fx_busy := false # an item animation is playing
var _spots := {} # seat -> SpotLight3D over players whose hand is exposed


func _ready() -> void:
	_font = load("res://fonts/VT323.woff2") as Font
	textures = CardTextures.new()
	add_child(textures)
	textures.built.connect(_on_textures_built)
	_build_room()
	_cards_root = Node3D.new()
	add_child(_cards_root)
	_labels_root = Node3D.new()
	add_child(_labels_root)
	shotgun = _build_shotgun()
	add_child(shotgun)
	_rest_gun(true)
	textures.build()


func _on_textures_built() -> void:
	_back_mat = textures.material("__back")
	for id in _cards:
		_cards[id].queue_free()
	_cards.clear()
	if not _last.is_empty():
		sync(_last)


# ================================================================ the room

func _mat(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _mesh(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi


func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.007, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.35)
	env.ambient_light_energy = 0.07
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# floor and table
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 12)
	add_child(_mesh(floor_mesh, _mat(Color(0.05, 0.045, 0.04)), Vector3(0, -0.78, 0)))
	var rim := CylinderMesh.new()
	rim.top_radius = 1.0
	rim.bottom_radius = 0.96
	rim.height = 0.07
	rim.radial_segments = 48
	var rim_mi := _mesh(rim, _mat(Palette.WOOD, 0.7), Vector3(0, -0.01, 0))
	rim_mi.scale = Vector3(TABLE_RX + 0.06, 1, TABLE_RZ + 0.06)
	add_child(rim_mi)
	var top := CylinderMesh.new()
	top.top_radius = 1.0
	top.bottom_radius = 1.0
	top.height = 0.06
	top.radial_segments = 48
	var top_mi := _mesh(top, _mat(Palette.FELT.darkened(0.15), 1.0))
	top_mi.scale = Vector3(TABLE_RX, 1, TABLE_RZ)
	add_child(top_mi)
	var leg := CylinderMesh.new()
	leg.top_radius = 0.12
	leg.bottom_radius = 0.3
	leg.height = 0.75
	add_child(_mesh(leg, _mat(Palette.WOOD), Vector3(0, -0.4, 0)))

	# the lamp over the table
	var cord := CylinderMesh.new()
	cord.top_radius = 0.008
	cord.bottom_radius = 0.008
	cord.height = 2.0
	add_child(_mesh(cord, _mat(Color(0.05, 0.05, 0.05)), Vector3(0, 3.0, 0)))
	var shade := CylinderMesh.new()
	shade.top_radius = 0.06
	shade.bottom_radius = 0.34
	shade.height = 0.24
	shade.radial_segments = 24
	var shade_mat := _mat(Color(0.12, 0.13, 0.1), 0.5, 0.6)
	shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_mesh(shade, shade_mat, Vector3(0, 1.95, 0)))
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	add_child(_mesh(bulb, _glow(Color(1.0, 0.86, 0.6), 4.0), Vector3(0, 1.86, 0)))
	lamp = SpotLight3D.new()
	lamp.position = Vector3(0, 1.85, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.spot_range = 4.5
	lamp.spot_angle = 52.0
	lamp.spot_attenuation = 1.3
	lamp.light_energy = LAMP
	lamp.light_color = Color(1.0, 0.85, 0.62)
	lamp.shadow_enabled = true
	add_child(lamp)
	_flicker()

	# a faint fill so the near side of the table isn't pitch black
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.3, 1.6)
	fill.omni_range = 3.0
	fill.light_energy = 0.2
	fill.light_color = Color(0.9, 0.8, 0.7)
	add_child(fill)

	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.03
	camera.far = 30.0
	add_child(camera)
	camera.current = true
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)

	var outline_colors := {"gold": Palette.GOLD, "amber": Palette.AMBER, "selected": Color(1, 0.95, 0.7), "target": Palette.GOLD}
	for k in outline_colors:
		_outline_mats[k] = _glow(outline_colors[k], 1.6)
	_back_mat = textures.material("__back")


## Portrait phones keep the table's width on screen; wide screens its height.
func _fit_camera() -> void:
	var s := get_viewport().get_visible_rect().size
	_landscape = s.x > s.y
	camera.keep_aspect = Camera3D.KEEP_HEIGHT if _landscape else Camera3D.KEEP_WIDTH
	camera.fov = 50.0 if _landscape else 62.0
	# wide screens look a little further across the table, to see faces
	if _landscape:
		camera.look_at_from_position(Vector3(0, 1.3, 1.8), Vector3(0, 0.18, -0.45), Vector3.UP)
	else:
		camera.look_at_from_position(Vector3(0, 1.12, 1.55), Vector3(0, 0, -0.12), Vector3.UP)
	_cam_home = camera.transform
	if _menu_mode:
		return
	if not _last.is_empty():
		sync(_last)


func _flicker() -> void:
	var t := create_tween().set_loops()
	t.tween_interval(5.5)
	t.tween_property(lamp, "light_energy", LAMP * 0.3, 0.05)
	t.tween_property(lamp, "light_energy", LAMP, 0.07)
	t.tween_property(lamp, "light_energy", LAMP * 0.5, 0.05)
	t.tween_property(lamp, "light_energy", LAMP, 0.12)
	t.tween_interval(3.0)


func _process(delta: float) -> void:
	if _menu_mode:
		# drift slowly round the table behind the menus
		_menu_t += delta * 0.12
		var pos := Vector3(sin(_menu_t) * 1.7, 1.25, cos(_menu_t) * 2.0)
		camera.look_at_from_position(pos, Vector3(0, 0.1, 0), Vector3.UP)


## A new match is starting: its first round gets dealt even if the last
## match ended on round 1 too.
func reset_rounds() -> void:
	_round_seen = 0


## Menu mode: an empty table and a slowly moving camera.
func set_menu_mode(on: bool) -> void:
	_menu_mode = on
	if on:
		_last = {}
		_round_seen = 0
		_deal = {}
		dealing = false
		for k in _spots:
			_spots[k].queue_free()
		_spots.clear()
		for id in _cards:
			_cards[id].queue_free()
		_cards.clear()
		_clear_labels()
		for s in _figures:
			_figures[s]["node"].queue_free()
		_figures.clear()
		_rest_gun(true)
	else:
		camera.transform = _cam_home


# ================================================================ seats

## Where a seat sits around the table, with the viewer always at the near side.
func seat_position(seat: int, viewer: int, count: int) -> Vector3:
	var rel := posmod(seat - viewer, count)
	var angle := PI * 0.5 + TAU * rel / float(count)
	return Vector3(cos(angle) * SEAT_RX, 0.0, sin(angle) * SEAT_RZ)


## A point on the table in front of a seat: t = 0 at the seat, 1 at the centre.
func _toward_center(seat_pos: Vector3, t: float) -> Vector3:
	return seat_pos.lerp(Vector3.ZERO, t)


func _figure(seat: int, color: Color) -> Dictionary:
	var node := Node3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.2
	body.height = 0.9
	node.add_child(_mesh(body, _mat(color, 0.95), Vector3(0, 0.12, 0)))
	var shoulders := CapsuleMesh.new()
	shoulders.radius = 0.12
	shoulders.height = 0.56
	var sh := _mesh(shoulders, _mat(color, 0.95), Vector3(0, 0.48, 0))
	sh.rotation.z = PI / 2.0
	node.add_child(sh)
	var head := Node3D.new()
	head.position = Vector3(0, 0.72, 0)
	var skull := SphereMesh.new()
	skull.radius = 0.15
	skull.height = 0.34
	head.add_child(_mesh(skull, _mat(Color(0.09, 0.085, 0.08), 0.7)))
	var eyes := []
	for x in [-0.055, 0.055]:
		var eye := SphereMesh.new()
		eye.radius = 0.02
		eye.height = 0.04
		var e := _mesh(eye, _glow(Color(1, 0.98, 0.9), 3.0), Vector3(x, 0.02, -0.135))
		head.add_child(e)
		eyes.append(e)
	node.add_child(head)
	var label := Label3D.new()
	label.font = _font
	label.font_size = 34
	label.pixel_size = 0.0022
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.0, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.add_child(label)
	add_child(node)
	return {"node": node, "head": head, "eyes": eyes, "label": label, "slumped": false, "seat": seat}


func _sync_figures(game, viewer: int) -> void:
	var n: int = game.players.size()
	for s in _figures.keys():
		if s >= n or s == viewer:
			_figures[s]["node"].queue_free()
			_figures.erase(s)
	for p in game.players:
		if p.seat == viewer:
			continue
		if not _figures.has(p.seat):
			_figures[p.seat] = _figure(p.seat, FIGURE_COLORS[p.seat % FIGURE_COLORS.size()])
			_figures[p.seat]["node"].position = seat_position(p.seat, viewer, n) * 1.3
		var f: Dictionary = _figures[p.seat]
		var node: Node3D = f["node"]
		var pos := seat_position(p.seat, viewer, n)
		var target := Transform3D(Basis.looking_at(-pos.normalized(), Vector3.UP), pos)
		if not p.alive:
			# slumped over in the chair
			target.basis = target.basis * Basis(Vector3.RIGHT, -0.9)
			target.origin.y -= 0.18
		_tween(node, "transform", target)
		for e in f["eyes"]:
			e.visible = p.alive
		var lines := [p.name + (" (D)" if p.seat == game.dealer else "")]
		if p.alive:
			lines.append("HP %d/%d  %d CARDS" % [p.hp, p.max_hp, p.hand.size()])
			var flags := []
			if p.cuffed:
				flags.append("CUFFED")
			if p.sawed:
				flags.append("SAWN-OFF")
			if p.exposed:
				flags.append("EXPOSED")
			if p.ultimatum:
				flags.append("REVOLVER")
			if p.extra_draws > 0:
				flags.append("DRAWS 2")
			if not flags.is_empty():
				lines.append(" ".join(flags))
		else:
			lines.append("OUT")
		var label: Label3D = f["label"]
		label.text = "\n".join(lines)
		var turn_now: bool = game.is_turn_of(p.seat)
		label.modulate = Palette.AMBER if turn_now else (Palette.INK if p.alive else Palette.DIM)


# ================================================================ cards

func _card(id: String, card_size: Vector2, spawn: Transform3D) -> Card3D:
	if _cards.has(id):
		return _cards[id]
	var c := Card3D.new()
	_cards_root.add_child(c)
	c.setup(card_size, _back_mat)
	c.transform = spawn
	_cards[id] = c
	return c


func _flat(pos: Vector3, yaw: float, face_up: bool) -> Transform3D:
	var tilt := Basis(Vector3.RIGHT, -PI / 2.0 if face_up else PI / 2.0)
	return Transform3D(Basis(Vector3.UP, yaw) * tilt, pos)


func _tween(node: Node3D, prop: String, value, delay: float = 0.0, time: float = MOVE_TIME) -> void:
	if not node.is_inside_tree():
		node.set(prop, value)
		return
	var old = node.get_meta("tween") if node.has_meta("tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := node.create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(node, prop, value, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	node.set_meta("tween", t)


## Everything about one card's place this sync.
func _place(seen: Dictionary, id: String, card: Dictionary, card_size: Vector2, xf: Transform3D, face_up: bool, lit: bool, kind: String, pick_id: String, outline: String, trump: bool, spawn: Transform3D) -> void:
	seen[id] = true
	var fresh := not _cards.has(id)
	var delay := 0.0
	if fresh and not _deal.is_empty() and _deal["order"].has(id):
		var n: int = _deal["order"][id]
		spawn = _deal["deck"].translated(Vector3(0, 0.0012 * (200 - n), 0))
		delay = _deal["start"] + n * DEAL_STEP
	var c := _card(id, card_size, spawn)
	if face_up and not card.get("hidden", false) and not card.is_empty():
		var k := CardTextures.key_for(card, trump)
		c.set_face(k, textures.material(k, lit))
	else:
		c.set_face("__back", _back_mat)
	c.set_outline(_outline_mats.get(outline, null))
	c.set_pickable(kind, pick_id)
	c.set_shadows(lit)
	if fresh and spawn == xf:
		c.transform = xf
	elif delay > 0.0:
		_tween(c, "transform", xf, delay, 0.32)
	else:
		_tween(c, "transform", xf)


## Shows the game as `viewer` sees it. `s` holds:
##   game, viewer, hand (sorted cards), selected, selected_item, meld_hints,
##   lay_hints, lit, can_draw, targets (meld ids that would take the selection)
func sync(s: Dictionary) -> void:
	_last = s
	var game = s["game"]
	var viewer: int = s["viewer"]
	var new_round: bool = game.round_num != _round_seen and (game.phase == "draw" or game.phase == "play")
	if dealing and not new_round:
		_resync = true # catch up when the deal is done
		return
	_viewer = viewer
	var n: int = game.players.size()
	var trump_rank: int = game.trump_rank
	var seen := {}
	_clear_labels()
	_sync_figures(game, viewer)
	if new_round:
		_begin_deal(game, viewer, s["hand"])

	var stock_xf := _flat(Vector3(-0.2, TABLE_TOP + 0.002, -0.02), 0.08, false)
	var discard_base := Vector3(0.2, TABLE_TOP + 0.002, -0.02)
	var cam: Transform3D = _cam_home

	# the stock: a little stack; only the top one is tappable
	var stock_n: int = mini(game.stock.size(), 14)
	for i in range(stock_n):
		var xf := stock_xf.translated(Vector3(0, 0.003 * i, 0))
		var top_one := i == stock_n - 1
		_place(seen, "stock-%d" % i, {}, TABLE_CARD, xf, false, true, "stock" if top_one else "", "", "amber" if top_one and s["can_draw"] else "", false, xf)
	if stock_n == 0:
		_label_at("SHUFFLE", stock_xf.origin + Vector3(0, 0.01, 0), 22, Palette.DIM)
	_label_at("STOCK %d" % game.stock.size(), stock_xf.origin + Vector3(0, 0.01, 0.15), 26, Palette.DIM)

	# the discard pile: the top few, a bit messy
	var pile: Array = game.discard_pile
	var from := maxi(0, pile.size() - 3)
	for i in range(from, pile.size()):
		var c: Dictionary = pile[i]
		var yaw := (hash(c["id"]) % 100) / 100.0 * 0.5 - 0.25
		var xf := _flat(discard_base + Vector3(0, 0.003 * (i - from), 0), yaw, true)
		var top_one := i == pile.size() - 1
		_place(seen, c["id"], c, TABLE_CARD, xf, true, true, "discard" if top_one else "", c["id"], "amber" if top_one and s["can_draw"] else "", game.is_trump(c), stock_xf)
	_label_at("DISCARD", discard_base + Vector3(0, 0.01, 0.15), 26, Palette.DIM)
	if trump_rank > 0:
		_label_at("TRUMP: %s" % TRUMP_NAMES[trump_rank], Vector3(0, TABLE_TOP + 0.01, 0.23), 34, Palette.GOLD)

	# melds, in a grid on the table
	var slots := [Vector3(-0.4, 0, 0.32), Vector3(0.4, 0, 0.32), Vector3(-0.4, 0, -0.38), Vector3(0.4, 0, -0.38), Vector3(-0.4, 0, 0.58), Vector3(0.4, 0, 0.58), Vector3(-0.4, 0, -0.64), Vector3(0.4, 0, -0.64)]
	for mi in range(game.melds.size()):
		var m: Dictionary = game.melds[mi]
		var base: Vector3 = slots[mi] if mi < slots.size() else Vector3(-0.42 + 0.84 * (mi % 2), 0, -0.9 - 0.22 * ((mi - slots.size()) / 2))
		var cards: Array = m["cards"]
		var step := minf(0.05, 0.6 / maxf(1.0, cards.size()))
		var start := base.x - step * (cards.size() - 1) * 0.5
		var is_target: bool = s["targets"].has(m["id"])
		for ci in range(cards.size()):
			var c: Dictionary = cards[ci]
			var pos := Vector3(start + step * ci, TABLE_TOP + 0.002 + 0.0015 * ci, base.z)
			_place(seen, c["id"], c, TABLE_CARD, _flat(pos, 0.0, true), true, true, "meld", m["id"], "target" if is_target else "", Cards.is_wild(c, trump_rank), stock_xf)
		_label_at(game.players[m["owner"]].name, Vector3(base.x, TABLE_TOP + 0.01, base.z + 0.14), 22, Palette.DIM)

	# other players' hands and items, face down in front of them
	for p in game.players:
		if p.seat == viewer:
			continue
		var seat_pos := seat_position(p.seat, viewer, n)
		var center := _toward_center(seat_pos, 0.34)
		var side := Vector3.UP.cross(seat_pos.normalized()).normalized()
		var yaw := atan2(-seat_pos.x, -seat_pos.z)
		var hand: Array = p.hand
		for i in range(hand.size()):
			var pos := center + side * ((i - (hand.size() - 1) * 0.5) * 0.035)
			pos.y = TABLE_TOP + 0.002 + 0.001 * i
			# Spotlight / Flashbang: revealed cards lie face up
			var shown: bool = p.exposed or hand[i].get("shown", false)
			var xf := _flat(pos, yaw + (i - hand.size() * 0.5) * 0.06, shown)
			_place(seen, hand[i]["id"], hand[i], OPP_CARD, xf, shown, true, "", "", "", game.is_trump(hand[i]) if shown else false, stock_xf)
		var items: Array = p.items
		for i in range(items.size()):
			var pos := _toward_center(seat_pos, 0.2) + side * (0.22 + i * 0.06)
			pos.y = TABLE_TOP + 0.002
			_place(seen, items[i]["id"], items[i], ITEM_CARD, _flat(pos, yaw, false), false, true, "", "", "", false, stock_xf)

	# your hand, held in front of the camera
	var hand_cards: Array = s["hand"]
	var hn := hand_cards.size()
	var hstep := minf(0.086, 0.6 / maxf(1.0, hn))
	for i in range(hn):
		var c: Dictionary = hand_cards[i]
		var mid := (hn - 1) * 0.5
		var lift := 0.035 if s["selected"].has(c["id"]) else 0.0
		var hand_z := -1.0 if _landscape else -0.62
		var hand_y := -0.225 if _landscape else -0.27
		var local := Transform3D(Basis(Vector3.FORWARD, (i - mid) * 0.05), Vector3((i - mid) * hstep, hand_y - absf(i - mid) * 0.006 + lift, hand_z + i * 0.0025))
		if s.get("hide_hand", false):
			local.basis = local.basis * Basis(Vector3.UP, PI) # backs toward you
		var outline := ""
		if s["selected"].has(c["id"]):
			outline = "selected"
		elif s["meld_hints"].has(c["id"]):
			outline = "gold"
		elif c["id"] == s["lit"]:
			outline = "amber"
		_place(seen, c["id"], c, HAND_CARD, cam * local, true, false, "hand", c["id"], outline, game.is_trump(c), stock_xf)
		if s["lay_hints"].has(c["id"]) and not s["selected"].has(c["id"]):
			_label_at("+", (cam * local).origin + cam.basis.y * -0.092, 34, Palette.GOLD, true)

	# your items, a row above your hand
	var my_items: Array = game.players[viewer].items
	for i in range(my_items.size()):
		var c: Dictionary = my_items[i]
		var x := (i - (my_items.size() - 1) * 0.5) * 0.085
		var local := Transform3D(Basis(), Vector3(x + (0.62 if _landscape else 0.0), -0.16 if _landscape else -0.13, -0.98 if _landscape else -0.64))
		if s.get("hide_hand", false):
			local.basis = local.basis * Basis(Vector3.UP, PI)
		var outline := "selected" if c["id"] == s["selected_item"] else ""
		_place(seen, c["id"], c, ITEM_CARD, cam * local, true, false, "item", c["id"], outline, false, stock_xf)

	for id in _cards.keys():
		if not seen.has(id):
			_cards[id].queue_free()
			_cards.erase(id)

	_sync_gun(game, viewer)
	_sync_spots(game, viewer)


## A beam of light over anyone whose hand is in the Spotlight.
func _sync_spots(game, viewer: int) -> void:
	var n: int = game.players.size()
	for p in game.players:
		var want: bool = p.exposed and p.seat != viewer and p.alive
		if want and not _spots.has(p.seat):
			var beam := SpotLight3D.new()
			beam.light_color = Color(1.0, 0.95, 0.8)
			beam.light_energy = 0.0
			beam.spot_range = 3.5
			beam.spot_angle = 16.0
			add_child(beam)
			var pos := seat_position(p.seat, viewer, n)
			beam.look_at_from_position(pos * 0.8 + Vector3(0, 2.4, 0), pos * 0.75, Vector3.FORWARD)
			beam.create_tween().tween_property(beam, "light_energy", 9.0, 0.4)
			_spots[p.seat] = beam
		elif not want and _spots.has(p.seat):
			_spots[p.seat].queue_free()
			_spots.erase(p.seat)


# ================================================================ items

const ITEM_COLORS := {
	"cigarettes": Color(0.6, 1.0, 0.6), "medicine": Color(0.5, 1.0, 0.7), "saw": Color(1.0, 0.75, 0.3),
	"beer": Color(1.0, 0.7, 0.2), "magnifier": Color(0.6, 0.85, 1.0), "phone": Color(0.5, 0.8, 1.0),
	"handcuffs": Color(0.8, 0.85, 1.0), "adrenaline": Color(1.0, 0.4, 0.4), "shakedown": Color(1.0, 0.35, 0.25),
	"switcheroo": Color(0.7, 0.6, 1.0), "bad_trade": Color(0.7, 0.6, 1.0), "chaos": Color(0.85, 0.4, 1.0),
	"sticky_fingers": Color(1.0, 0.6, 0.9), "dumpster_dive": Color(0.6, 0.9, 0.4), "garbage_day": Color(0.6, 0.9, 0.4),
	"tarot": Color(1.0, 0.8, 0.25), "joker_paint": Color(1.0, 0.8, 0.25), "spotlight": Color(1.0, 0.97, 0.85),
	"flashbang": Color(1, 1, 1), "revolver": Color(1.0, 0.25, 0.2), "double_down": Color(1.0, 0.85, 0.5),
}
const SPINNERS := ["tarot", "joker_paint", "chaos"]


## Where a player's things are: your item row, or in front of their seat.
func _seat_spot(seat: int, height: float = 0.1) -> Vector3:
	if seat == _viewer:
		return _cam_home * Vector3(0, -0.13, -0.64)
	var n: int = _last["game"].players.size() if not _last.is_empty() else 2
	var pos := _toward_center(seat_position(seat, _viewer, n), 0.25)
	pos.y = TABLE_TOP + height
	return pos


## A point over the table in front of a seat, for effects.
func _table_spot(seat: int, height: float) -> Vector3:
	if seat == _viewer:
		return Vector3(0, TABLE_TOP + height, 0.8)
	return _seat_spot(seat, height)


## Plays an item: its card rises to the middle of the table, glows, then
## shoots off at the target (or bursts in place), with a little extra for
## some items.
func play_item(item_id: String, user: int, target: int = -1) -> void:
	fx_busy = true
	var color: Color = ITEM_COLORS.get(item_id, Palette.PURPLE)
	var card := Card3D.new()
	add_child(card)
	card.setup(Vector2(0.15, 0.2), _back_mat)
	var key := "item:" + item_id
	card.set_face(key, textures.material(key, false))
	card.set_pickable("", "")
	card.set_shadows(false)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 0.7
	light.light_energy = 0.0
	light.position = Vector3(0, 0, 0.08)
	card.add_child(light)

	var start := _seat_spot(user)
	var center := Vector3(0, 0.72, 0.45)
	# face the camera (a card's face is its +Z side)
	var facing := Basis.looking_at(_cam_home.origin - center, Vector3.UP) * Basis(Vector3.UP, PI)
	card.transform = Transform3D(facing.scaled(Vector3(0.4, 0.4, 0.4)), start)
	var big := Transform3D(facing.scaled(Vector3(1.9, 1.9, 1.9)), center)

	var t := card.create_tween()
	t.tween_property(card, "transform", big, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(light, "light_energy", 1.5, 0.4)
	if SPINNERS.has(item_id):
		t.tween_method(func(a: float) -> void: card.transform = Transform3D(big.basis * Basis(Vector3.UP, a), center), 0.0, TAU * 2.0, 0.7)
	else:
		t.tween_interval(0.55)
	t.tween_callback(_item_extra.bind(item_id, user, target, color))
	if target >= 0:
		var to := _head_of(target) if target != _viewer else _cam_home * Vector3(0, -0.05, -0.5)
		t.tween_property(card, "transform", Transform3D(facing.scaled(Vector3(0.2, 0.2, 0.2)), to), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(_pulse.bind(to, color, 2.5))
	else:
		t.tween_property(card, "transform", Transform3D(facing.scaled(Vector3(2.4, 2.4, 2.4)), center), 0.15)
		t.parallel().tween_property(light, "light_energy", 3.0, 0.15)
		t.tween_property(card, "transform", Transform3D(facing.scaled(Vector3(0.01, 0.01, 0.01)), center), 0.2)
	t.tween_callback(card.queue_free)
	t.tween_callback(func() -> void: fx_busy = false)


## A quick flash of coloured light at a spot.
func _pulse(at: Vector3, color: Color, energy: float = 3.0, time: float = 0.45) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = 0.9
	l.light_energy = energy
	l.position = at
	add_child(l)
	var t := l.create_tween()
	t.tween_property(l, "light_energy", 0.0, time)
	t.tween_callback(l.queue_free)


## Little glowing blobs that drift up and fade, e.g. smoke or sparks.
func _puffs(at: Vector3, color: Color, count: int = 6, size: float = 0.05, rise: float = 0.35, glowing: bool = true) -> void:
	for i in range(count):
		var sphere := SphereMesh.new()
		sphere.radius = size
		sphere.height = size * 2.0
		var m := _glow(color, 1.5) if glowing else _mat(Color(color, 0.55), 1.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if not glowing:
			m.albedo_color = Color(color, 0.5)
		var mi := _mesh(sphere, m, at + Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var drift := Vector3(randf_range(-0.12, 0.12), rise + randf_range(0, 0.15), randf_range(-0.12, 0.12))
		var t := mi.create_tween()
		t.tween_interval(i * 0.06)
		t.tween_property(mi, "position", mi.position + drift, 0.8)
		t.parallel().tween_property(mi, "scale", Vector3.ONE * 2.2, 0.8)
		t.parallel().tween_property(m, "albedo_color:a", 0.0, 0.8)
		t.tween_callback(mi.queue_free)


## The extra bit of each item's animation.
func _item_extra(item_id: String, user: int, target: int, color: Color) -> void:
	var stock_top := Vector3(-0.2, TABLE_TOP + 0.06, -0.02)
	var discard_top := Vector3(0.2, TABLE_TOP + 0.06, -0.02)
	match item_id:
		"cigarettes":
			_puffs(_table_spot(user, 0.25), Color(0.7, 0.7, 0.68), 8, 0.035, 0.5, false)
		"medicine":
			_puffs(_table_spot(user, 0.2), color, 6, 0.02, 0.4)
		"saw":
			_puffs(shotgun.global_position, Color(1.0, 0.8, 0.4), 10, 0.015, 0.25)
			_pulse(shotgun.global_position, color, 2.0)
		"beer":
			_puffs(stock_top, Color(1.0, 0.5, 0.15), 10, 0.03, 0.45)
			_pulse(stock_top, color, 2.5)
		"magnifier":
			_pulse(stock_top, color, 2.0, 0.9)
		"dumpster_dive", "garbage_day":
			_puffs(discard_top, color, 6, 0.03, 0.3)
		"sticky_fingers":
			_pulse(Vector3(0, TABLE_TOP + 0.1, 0.2), color, 2.0)
		"tarot":
			_pulse(Vector3(0, TABLE_TOP + 0.1, 0.23), Palette.GOLD, 3.0, 0.9)
		"flashbang":
			_pulse(Vector3(0, 0.6, 0), Color.WHITE, 30.0, 0.6)
		"chaos":
			_puffs(Vector3(0, TABLE_TOP + 0.1, 0), color, 12, 0.03, 0.3)
		"shakedown", "revolver":
			if target >= 0 and _figures.has(target):
				var node: Node3D = _figures[target]["node"]
				var home := node.transform
				var tj := node.create_tween()
				for i in range(4):
					tj.tween_property(node, "transform", home.translated(Vector3(randf_range(-0.04, 0.04), 0, randf_range(-0.04, 0.04))), 0.05)
				tj.tween_property(node, "transform", home, 0.08)
			elif target == _viewer:
				shake(0.02)


## Russian roulette: a red or dull flash at the player.
func roulette(seat: int, hit: bool) -> void:
	var at := _head_of(seat) if seat != _viewer else _cam_home * Vector3(0, 0, -0.6)
	if hit:
		_pulse(at, Color(1, 0.3, 0.15), 14.0, 0.5)
		if seat == _viewer:
			shake(0.07)
	else:
		_pulse(at, Color(0.6, 0.6, 0.6), 1.5, 0.3)


# ================================================================ dealing

## Start of a round: sweep the old cards to the dealer, shuffle, then deal one
## card at a time to each player in turn, starting on the dealer's left, then
## the items, then turn up the discard and set down the stock.
func _begin_deal(game, viewer: int, my_hand: Array) -> void:
	_round_seen = game.round_num
	var n: int = game.players.size()
	var deck_pos := _toward_center(seat_position(game.dealer, viewer, n), 0.5)
	deck_pos.y = TABLE_TOP + 0.002
	var yaw := atan2(-deck_pos.x, -deck_pos.z)
	var deck := _flat(deck_pos, yaw, false)

	# old cards go back to the dealer
	for id in _cards:
		var c: Card3D = _cards[id]
		c.set_pickable("", "")
		_tween(c, "transform", deck, randf() * 0.15, 0.3)
		get_tree().create_timer(0.5).timeout.connect(c.queue_free)
	_cards.clear()

	# deal order: round and round from the dealer's left
	var seats := []
	var s: int = game.next_alive(game.dealer)
	for i in range(n):
		if game.players[s].alive:
			seats.append(s)
		s = (s + 1) % n
	var order := {}
	var count := 0
	var hand_size := 0
	for seat in seats:
		hand_size = maxi(hand_size, (my_hand if seat == viewer else game.players[seat].hand).size())
	for k in range(hand_size):
		for seat in seats:
			var hand: Array = my_hand if seat == viewer else game.players[seat].hand
			if k < hand.size():
				order[hand[k]["id"]] = count
				count += 1
	var item_rounds := 0
	for seat in seats:
		item_rounds = maxi(item_rounds, game.players[seat].items.size())
	for k in range(item_rounds):
		for seat in seats:
			var items: Array = game.players[seat].items
			if k < items.size():
				order[items[k]["id"]] = count
				count += 1
	for c in game.discard_pile:
		order[c["id"]] = count
		count += 1
	for i in range(mini(game.stock.size(), 14)):
		order["stock-%d" % i] = count + i / 4 # the stock slides over in a few clumps
	count += 4

	var shuffle_start := 0.45
	var deal_start := shuffle_start + 1.3
	_deal = {"deck": deck, "order": order, "start": deal_start}
	dealing = true
	_shuffle_show(deck, shuffle_start)
	if game.trump_rank > 0:
		_banner("ROUND %d\nTRUMP: %s" % [game.round_num, TRUMP_NAMES[game.trump_rank]], Vector3(0, 0.55, -0.15), deal_start + count * DEAL_STEP)
	var done := get_tree().create_timer(deal_start + count * DEAL_STEP + 0.4)
	done.timeout.connect(_end_deal)


func _end_deal() -> void:
	dealing = false
	_deal = {}
	if _resync and not _last.is_empty():
		_resync = false
		sync(_last)
	deal_finished.emit()


## A quick riffle: the deck splits, the halves come back together, twice.
func _shuffle_show(deck: Transform3D, start: float) -> void:
	var side := deck.basis.x.normalized()
	var halves := [[], []]
	for i in range(16):
		var c := Card3D.new()
		_cards_root.add_child(c)
		c.setup(TABLE_CARD, _back_mat)
		c.set_face("__back", _back_mat)
		c.set_pickable("", "")
		c.transform = deck.translated(Vector3(0, 0.0015 * i, 0))
		c.visible = false
		halves[i % 2].append(c)
	for h in range(2):
		for i in range(halves[h].size()):
			var c: Card3D = halves[h][i]
			var home := c.transform
			var apart := home.translated(side * (0.13 if h == 0 else -0.13) + Vector3(0, 0.02, 0))
			var t := c.create_tween()
			t.tween_interval(start)
			t.tween_callback(c.show)
			for rep_i in range(2):
				t.tween_property(c, "transform", apart, 0.22).set_trans(Tween.TRANS_SINE)
				t.tween_interval(0.02 * i)
				t.tween_property(c, "transform", home, 0.18).set_trans(Tween.TRANS_SINE)
			t.tween_interval(0.25)
			t.tween_callback(c.queue_free)


## Shows a big message over the middle of the table for a few seconds.
func announce(text: String) -> void:
	_banner(text, Vector3(0, 0.55, -0.15), 2.5)


## Big floating text over the table, e.g. the round's trump.
func _banner(text: String, pos: Vector3, seconds: float) -> void:
	var l := Label3D.new()
	l.font = _font
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0025
	l.modulate = Palette.GOLD
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos
	add_child(l)
	var t := l.create_tween()
	t.tween_interval(seconds)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


# ================================================================ labels

func _clear_labels() -> void:
	for c in _labels_root.get_children():
		c.queue_free()


func _label_at(text: String, pos: Vector3, size: int, color: Color, billboard: bool = false) -> void:
	var l := Label3D.new()
	l.font = _font
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0022
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
	else:
		# lying on the table, readable from your seat
		l.rotation = Vector3(-PI / 2.0, 0, 0)
	l.position = pos
	_labels_root.add_child(l)


# ================================================================ picking

## What did a tap at this screen position hit? { kind, id } or {}.
func pick(screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 20.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var area: Object = hit["collider"]
	if not area.has_meta("card"):
		return {}
	var c: Card3D = area.get_meta("card")
	if c.pick_kind == "":
		return {}
	return {"kind": c.pick_kind, "id": c.pick_id}


# ================================================================ the shotgun

func _build_shotgun() -> Node3D:
	var g := Node3D.new()
	var steel := _mat(Color(0.18, 0.18, 0.19), 0.35, 0.8)
	var wood := _mat(Color(0.36, 0.2, 0.1), 0.6)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.022
	barrel.bottom_radius = 0.022
	barrel.height = 0.62
	for x in [-0.024, 0.024]:
		var b := _mesh(barrel, steel, Vector3(x, 0.0, -0.31))
		b.rotation.x = PI / 2.0
		g.add_child(b)
	var receiver := BoxMesh.new()
	receiver.size = Vector3(0.09, 0.08, 0.16)
	g.add_child(_mesh(receiver, steel, Vector3(0, -0.01, 0.06)))
	var pump := BoxMesh.new()
	pump.size = Vector3(0.08, 0.05, 0.14)
	g.add_child(_mesh(pump, wood, Vector3(0, -0.035, -0.22)))
	var stock := BoxMesh.new()
	stock.size = Vector3(0.07, 0.1, 0.34)
	var stock_mi := _mesh(stock, wood, Vector3(0, -0.05, 0.3))
	stock_mi.rotation.x = 0.18
	g.add_child(stock_mi)
	var flash := OmniLight3D.new()
	flash.name = "Flash"
	flash.position = Vector3(0, 0, -0.66)
	flash.light_color = Color(1, 0.8, 0.45)
	flash.omni_range = 3.0
	flash.light_energy = 0.0
	g.add_child(flash)
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	var puff_mi := _mesh(puff, _glow(Color(1, 0.75, 0.35), 6.0), Vector3(0, 0, -0.7))
	puff_mi.name = "Puff"
	puff_mi.visible = false
	g.add_child(puff_mi)
	return g


func _rest_gun(instant: bool = false) -> void:
	_gun_pose = "rest"
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, TABLE_TOP + 0.035, -0.86))
	if instant:
		shotgun.transform = xf
	else:
		_tween(shotgun, "transform", xf)


func _holder_pose(holder: int, aim: Vector3) -> Transform3D:
	var n: int = 0
	if not _last.is_empty():
		n = _last["game"].players.size()
	var origin: Vector3
	if holder == _viewer:
		origin = _cam_home * Vector3(0.15, -0.25, -0.5)
	else:
		origin = seat_position(holder, _viewer, n) * 0.82 + Vector3(0, 0.5, 0)
	return Transform3D(Basis.looking_at(aim - origin, Vector3.UP), origin)


func _head_of(seat: int) -> Vector3:
	if seat == _viewer:
		return _cam_home.origin + Vector3(0, -0.1, 0)
	if _figures.has(seat):
		return _figures[seat]["head"].global_position
	return Vector3(0, 0.6, 0)


func _sync_gun(game, viewer: int) -> void:
	if game.phase == "shoot" and game.gun != null:
		var holder: int = game.gun["holder"]
		# aim at the middle of the table until a target is picked
		var aim := Vector3(0, 0.45, 0) if holder == viewer else _head_of(viewer)
		var pose := "held%d" % holder
		if _gun_pose != pose:
			_gun_pose = pose
			_tween(shotgun, "transform", _holder_pose(holder, aim))
	elif _gun_pose != "rest" and game.phase != "match_over":
		_rest_gun()


## Bang. Swings to the target, kicks back, flashes, and the target jolts.
func fire(shooter: int, target: int) -> void:
	var aim := _head_of(target)
	var pose := _holder_pose(shooter, aim)
	_gun_pose = "fired"
	var t := create_tween()
	t.tween_property(shotgun, "transform", pose, 0.18)
	t.tween_callback(_bang.bind(target))
	var kicked := pose
	kicked.origin += pose.basis.z * 0.12
	kicked.basis = kicked.basis * Basis(Vector3.RIGHT, 0.35)
	t.tween_property(shotgun, "transform", kicked, 0.05)
	t.tween_property(shotgun, "transform", pose, 0.35)


func _bang(target: int) -> void:
	var flash: OmniLight3D = shotgun.get_node("Flash")
	var puff: MeshInstance3D = shotgun.get_node("Puff")
	flash.light_energy = 14.0
	puff.visible = true
	var t := create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.25)
	t.parallel().tween_callback(func() -> void: puff.visible = false).set_delay(0.06)
	if target == _viewer:
		shake(0.06)
	elif _figures.has(target):
		var node: Node3D = _figures[target]["node"]
		var back := node.transform
		var jolt := back.translated(back.origin.normalized() * 0.18)
		var tj := node.create_tween()
		tj.tween_property(node, "transform", jolt, 0.06)
		tj.tween_property(node, "transform", back, 0.4)


func shake(amount: float = 0.03) -> void:
	var t := create_tween()
	for i in range(6):
		var off := Vector3(randf_range(-amount, amount), randf_range(-amount, amount), 0)
		t.tween_property(camera, "transform", _cam_home.translated_local(off), 0.035)
	t.tween_property(camera, "transform", _cam_home, 0.06)
