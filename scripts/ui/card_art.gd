extends RefCounted
## Draws cards with plain shapes so they look the same on every device
## (the pixel font has no suit symbols, so suits are drawn as polygons).

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")


## Draws `card` into `rect` on canvas item `ci` (call from its _draw).
## An empty card draws an empty slot.
static func draw_card(ci: CanvasItem, font: Font, rect: Rect2, card: Dictionary, face_down: bool = false, compact: bool = false) -> void:
	var radius := int(rect.size.x * 0.09)
	if face_down:
		_draw_back(ci, rect, radius)
		return
	if card.is_empty():
		var slot := Palette.box(Color(0, 0, 0, 0.15), Color(1, 1, 1, 0.15), 2, radius)
		ci.draw_style_box(slot, rect)
		return
	if card.has("item"):
		_draw_item(ci, font, rect, card, radius, compact)
		return

	ci.draw_style_box(Palette.box(Palette.PAPER, Color(0.6, 0.55, 0.45), 1, radius), rect)
	var color := Palette.CARD_RED if Cards.is_red(card) else Palette.CARD_INK
	var label := Cards.rank_label(card["rank"])
	var fs := int(rect.size.x * (0.36 if compact else 0.3))
	var pad := rect.size.x * 0.08
	var ascent := font.get_ascent(fs)
	ci.draw_string(font, rect.position + Vector2(pad, pad + ascent * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	var small := rect.size.x * (0.14 if compact else 0.11)
	var corner := rect.position + Vector2(pad + small, pad + ascent + small * 1.2)
	draw_suit(ci, card["suit"], corner, small, color)
	if compact:
		return
	draw_suit(ci, card["suit"], rect.get_center() + Vector2(0, rect.size.y * 0.08), rect.size.x * 0.24, color)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, rect.end - Vector2(pad + w, pad), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


static func _draw_back(ci: CanvasItem, rect: Rect2, radius: int) -> void:
	ci.draw_style_box(Palette.box(Palette.BACK_DARK, Palette.WAIVER, 3, radius), rect)
	# a little diamond lattice
	var inner := rect.grow(-7)
	var cell := maxf(6.0, rect.size.x / 8.0)
	var y := inner.position.y
	var row := 0
	while y + cell <= inner.end.y + 0.5:
		var x := inner.position.x + (cell * 0.5 if row % 2 == 1 else 0.0)
		while x + cell <= inner.end.x + 0.5:
			var c := Vector2(x + cell * 0.5, y + cell * 0.5)
			var h := cell * 0.42
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]), Palette.BACK)
			x += cell
		y += cell
		row += 1


static func _draw_item(ci: CanvasItem, font: Font, rect: Rect2, card: Dictionary, radius: int, compact: bool) -> void:
	var def: Dictionary = Items.def(card["item"])
	ci.draw_style_box(Palette.box(Palette.ITEM_BG, Palette.PURPLE, 2, radius), rect)
	var icon_fs := int(rect.size.x * (0.4 if compact else 0.46))
	var icon_w := font.get_string_size(def["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, icon_fs).x
	var icon_y := rect.position.y + rect.size.y * (0.55 if compact else 0.5)
	ci.draw_string(font, Vector2(rect.get_center().x - icon_w * 0.5, icon_y), def["icon"], HORIZONTAL_ALIGNMENT_LEFT, -1, icon_fs, Color.WHITE)
	if compact:
		return
	# name along the bottom, shrunk to fit
	var title: String = str(def["name"]).to_upper()
	var fs := int(rect.size.x * 0.2)
	while fs > 10 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x - 8:
		fs -= 1
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(rect.get_center().x - w * 0.5, rect.end.y - rect.size.y * 0.08), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.INK)


## Suit shape centred on `c`, roughly 2*s tall.
static func draw_suit(ci: CanvasItem, suit: String, c: Vector2, s: float, color: Color) -> void:
	match suit:
		"D":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.72, 0), c + Vector2(0, s), c + Vector2(-s * 0.72, 0)]), color)
		"H":
			ci.draw_circle(c + Vector2(-s * 0.46, -s * 0.28), s * 0.5, color)
			ci.draw_circle(c + Vector2(s * 0.46, -s * 0.28), s * 0.5, color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.94, -s * 0.12), c + Vector2(s * 0.94, -s * 0.12), c + Vector2(0, s)]), color)
		"S":
			ci.draw_circle(c + Vector2(-s * 0.46, s * 0.12), s * 0.48, color)
			ci.draw_circle(c + Vector2(s * 0.46, s * 0.12), s * 0.48, color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.92, s * 0.02), c + Vector2(s * 0.92, s * 0.02), c + Vector2(0, -s)]), color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.2), c + Vector2(s * 0.34, s), c + Vector2(-s * 0.34, s)]), color)
		"C":
			ci.draw_circle(c + Vector2(0, -s * 0.5), s * 0.42, color)
			ci.draw_circle(c + Vector2(-s * 0.5, s * 0.08), s * 0.42, color)
			ci.draw_circle(c + Vector2(s * 0.5, s * 0.08), s * 0.42, color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.1), c + Vector2(s * 0.34, s), c + Vector2(-s * 0.34, s)]), color)
