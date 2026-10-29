extends Node
## Card faces for the 3D table. Every card (and its trump version, every item
## and the card back) is drawn once with the 2D card art into one big image at
## startup, then cut into textures and materials that the 3D cards share.
##
## Without a renderer (headless tests) there are no images, and cards fall back
## to plain colours.

signal built

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")

const W := 128
const H := 184
const COLS := 16

var is_built := false
var _textures := {} # key -> Texture2D
var _materials := {} # key|lit -> StandardMaterial3D


class AtlasCanvas extends Control:
	const CardArt = preload("res://scripts/ui/card_art.gd")
	var entries: Array = [] # [card, trump, face_down]

	func _draw() -> void:
		var font := get_theme_default_font()
		for i in range(entries.size()):
			var e: Array = entries[i]
			var cell := Rect2(Vector2((i % 16) * 128, (i / 16) * 184), Vector2(128, 184))
			CardArt.draw_card(self, font, cell.grow(-2), e[0], e[2], false, e[1])


## Key for a card's texture: its id, "*" on the end when it's this round's
## trump, "__back" for the back.
static func key_for(card: Dictionary, trump: bool) -> String:
	if card.has("item"):
		return "item:" + str(card["item"])
	return str(card["id"]) + ("*" if trump else "")


func build() -> void:
	var keys := []
	var entries := []
	for c in Cards.create_deck():
		for trump in [false, true]:
			keys.append(key_for(c, trump))
			entries.append([c, trump, false])
	for item_id in Items.DEFS:
		var c := {"id": "I-" + item_id, "item": item_id}
		keys.append(key_for(c, false))
		entries.append([c, false, false])
	keys.append("__back")
	entries.append([{}, false, true])

	var rows := int(ceil(entries.size() / float(COLS)))
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * W, rows * H)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := AtlasCanvas.new()
	canvas.theme = Palette.make_theme()
	canvas.size = Vector2(vp.size)
	canvas.entries = entries
	vp.add_child(canvas)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image() if vp.get_texture() != null else null
	if img != null and not img.is_empty():
		for i in range(keys.size()):
			var sub := img.get_region(Rect2i((i % COLS) * W, (i / COLS) * H, W, H))
			sub.generate_mipmaps()
			_textures[keys[i]] = ImageTexture.create_from_image(sub)
	vp.queue_free()
	_materials.clear()
	is_built = not _textures.is_empty()
	built.emit()


func texture(key: String) -> Texture2D:
	return _textures.get(key, null)


## Shared material for a card face. `lit` cards react to the lamp; unlit ones
## (your hand) always read clearly.
func material(key: String, lit: bool = true) -> StandardMaterial3D:
	var mkey := key + ("|lit" if lit else "|flat")
	if _materials.has(mkey):
		return _materials[mkey]
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not lit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.92, 0.9, 0.85)
	var tex := texture(key)
	if tex != null:
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	elif key == "__back":
		m.albedo_color = Palette.BACK
	elif key.begins_with("item:"):
		m.albedo_color = Palette.ITEM_BG
	else:
		m.albedo_color = Palette.PAPER
	_materials[mkey] = m
	return m
