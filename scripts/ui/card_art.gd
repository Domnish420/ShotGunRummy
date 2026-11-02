extends RefCounted
## Draws cards with plain shapes so they look the same on every device
## (the pixel font has no suit symbols, so suits are drawn as polygons).

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardSkins = preload("res://scripts/ui/card_skins.gd")

## The card skin everything is drawn in (see card_skins.gd).
static var skin: Dictionary = CardSkins.get_skin("classic")


## Draws `card` into `rect` on canvas item `ci` (call from its _draw).
## An empty card draws an empty slot. `trump` marks this round's wild cards.
static func draw_card(ci: CanvasItem, font: Font, rect: Rect2, card: Dictionary, face_down: bool = false, compact: bool = false, trump: bool = false) -> void:
	var radius := int(rect.size.x * 0.09)
	if face_down:
		_draw_back(ci, rect, radius, font)
		return
	if card.is_empty():
		var slot := Palette.box(Color(0, 0, 0, 0.15), Color(1, 1, 1, 0.15), 2, radius)
		ci.draw_style_box(slot, rect)
		return
	if card.has("item"):
		_draw_item(ci, font, rect, card, radius, compact)
		return

	if trump:
		ci.draw_style_box(Palette.box(skin["paper"], Palette.GOLD, 3, radius), rect)
	else:
		ci.draw_style_box(Palette.box(skin["paper"], skin["edge"], 2, radius), rect)
	_draw_face_wash(ci, rect, font)
	var color: Color = skin["red"] if Cards.is_red(card) else skin["ink"]
	var label := Cards.rank_label(card["rank"])
	var fs := int(rect.size.x * (0.36 if compact else 0.3))
	var pad := rect.size.x * 0.08
	var ascent := font.get_ascent(fs)
	ci.draw_string(font, rect.position + Vector2(pad, pad + ascent * 0.85), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
	var small := rect.size.x * (0.14 if compact else 0.11)
	var corner := rect.position + Vector2(pad + small, pad + ascent + small * 1.2)
	draw_suit(ci, card["suit"], corner, small, color)
	if trump:
		# a gold star: visible on the left strip of overlapped meld cards too
		var star_at := corner + Vector2(0, small * 2.8) if compact else Vector2(rect.end.x - pad - small * 1.6, rect.position.y + pad + small * 1.6)
		draw_star(ci, star_at, small * (1.4 if compact else 1.6), Palette.GOLD)
	if compact:
		return
	draw_suit(ci, card["suit"], rect.get_center() + Vector2(0, rect.size.y * 0.08), rect.size.x * 0.24, color)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, rect.end - Vector2(pad + w, pad), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


static func _draw_back(ci: CanvasItem, rect: Rect2, radius: int, font: Font = null) -> void:
	ci.draw_style_box(Palette.box(skin["back_dark"], skin["back_edge"], 3, radius), rect)
	_pattern(ci, rect.grow(-7), maxf(6.0, rect.size.x / 8.0), font)


## The face shows the back's pattern too, washed out towards the paper so the
## rank and suit stay easy to read.
static func _draw_face_wash(ci: CanvasItem, rect: Rect2, font: Font) -> void:
	var wash := float(skin.get("face_wash", 0.24))
	if wash <= 0.0:
		return
	var keep := skin
	var paper: Color = skin["paper"]
	var washed := skin.duplicate()
	washed["_wash"] = wash
	for k in ["back", "back_dark", "back_edge"]:
		washed[k] = paper.lerp(skin[k], wash)
	if skin.has("palette"):
		var pal := {}
		for ch in skin["palette"]:
			pal[ch] = paper.lerp(skin["palette"][ch], wash)
		washed["palette"] = pal
	skin = washed
	_pattern(ci, rect.grow(-maxf(4.0, rect.size.x * 0.06)), maxf(6.0, rect.size.x / 8.0), font, true)
	skin = keep


## A colour as this pattern draws it: washed out on a card's face.
static func _tint(c: Color) -> Color:
	var wash := float(skin.get("_wash", 0.0))
	return skin["paper"].lerp(c, wash) if wash > 0.0 else c


## The skin's pattern, filling `inner`. `face` is true on the front of a card
## (no background fill there: the paper shows through).
static func _pattern(ci: CanvasItem, inner: Rect2, cell: float, font: Font = null, face: bool = false) -> void:
	var fg: Color = skin["back"]
	match str(skin["pattern"]):
		"stripes":
			# thin diagonal stripes, clipped to the inside of the card
			var step := cell * 0.9
			var t := -inner.size.y
			while t < inner.size.x:
				var a := inner.position + Vector2(t, inner.size.y)
				var b := inner.position + Vector2(t + inner.size.y, 0)
				var seg := _clip_line(a, b, inner)
				if not seg.is_empty():
					ci.draw_line(seg[0], seg[1], fg, maxf(1.5, cell * 0.18))
				t += step
		"dots":
			_grid(inner, cell, func(c: Vector2, _r: int, _k: int) -> void: ci.draw_circle(c, cell * 0.22, fg))
		"checks":
			_grid(inner, cell, func(c: Vector2, r: int, k: int) -> void:
				if (r + k) % 2 == 0:
					ci.draw_rect(Rect2(c - Vector2(cell, cell) * 0.5, Vector2(cell, cell)), fg))
		"shells":
			# shotgun shells: a red tube with a brass head
			_grid(inner, cell * 1.6, func(c: Vector2, r: int, _k: int) -> void:
				var w := cell * 0.42
				var h := cell * 1.05
				var top := c - Vector2(w * 0.5, h * 0.5)
				ci.draw_rect(Rect2(top, Vector2(w, h * 0.68)), _tint(Color(0.72, 0.1, 0.08) if r % 2 == 0 else Color(0.55, 0.06, 0.05)))
				ci.draw_rect(Rect2(top + Vector2(-w * 0.1, h * 0.68), Vector2(w * 1.2, h * 0.32)), fg), true)
		"skulls":
			_grid(inner, cell * 1.7, func(c: Vector2, _r: int, _k: int) -> void:
				var r := cell * 0.42
				ci.draw_circle(c, r, fg)
				ci.draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.6), Vector2(r * 1.1, r * 0.55)), fg)
				ci.draw_circle(c + Vector2(-r * 0.38, 0), r * 0.26, skin["back_dark"])
				ci.draw_circle(c + Vector2(r * 0.38, 0), r * 0.26, skin["back_dark"]), true)
		"zigzag":
			var y := inner.position.y + cell * 0.6
			var row := 0
			while y < inner.end.y - cell * 0.3:
				var pts := PackedVector2Array()
				var x := inner.position.x
				var up := true
				while x <= inner.end.x + 0.5:
					pts.append(Vector2(x, y + (-cell * 0.35 if up else cell * 0.35)))
					up = not up
					x += cell * 0.6
				ci.draw_polyline(pts, fg if row % 2 == 0 else skin["back_edge"], maxf(1.5, cell * 0.2))
				y += cell * 1.1
				row += 1
		"diamond":
			# one big diamond with a ring of small ones
			var c := inner.get_center()
			var hw := inner.size.x * 0.42
			var hh := inner.size.y * 0.42
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)]), fg)
			var s := 0.62
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -hh * s), c + Vector2(hw * s, 0), c + Vector2(0, hh * s), c + Vector2(-hw * s, 0)]), skin["back_dark"])
			draw_star(ci, c, hw * 0.35, fg)
		"pixels":
			# chunky pixels in four shades, like an old handheld's screen
			var shades: Array = [skin["back_dark"], fg, skin["back_edge"], fg.lerp(skin["back_dark"], 0.5)]
			var px := cell * 0.5
			_grid(inner, px, func(c: Vector2, r: int, k: int) -> void:
				ci.draw_rect(Rect2(c - Vector2(px, px) * 0.45, Vector2(px, px) * 0.9), shades[(r * 7 + k * 3 + (r * k) % 5) % 4]))
		"bands":
			# fat stripes across, three colours round and round
			var cols: Array = [fg, skin["back_edge"], skin["back_dark"]]
			var y := inner.position.y
			var i := 0
			while y < inner.end.y:
				var h := minf(cell * 1.2, inner.end.y - y)
				ci.draw_rect(Rect2(Vector2(inner.position.x, y), Vector2(inner.size.x, h)), cols[i % 3])
				y += cell * 1.2
				i += 1
		"wire":
			# strands of wire, knotted with little barbs
			var y := inner.position.y + cell * 0.7
			var row := 0
			var wide := maxf(1.0, cell * 0.12)
			while y < inner.end.y - cell * 0.3:
				ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), skin["back_edge"], wide)
				var x := inner.position.x + (cell * 0.6 if row % 2 == 0 else cell * 1.3)
				while x < inner.end.x - cell * 0.3:
					var b := cell * 0.3
					ci.draw_line(Vector2(x - b, y - b), Vector2(x + b, y + b), fg, wide)
					ci.draw_line(Vector2(x - b, y + b), Vector2(x + b, y - b), fg, wide)
					x += cell * 1.4
				y += cell * 1.3
				row += 1
		"stars":
			# a night sky with a crescent moon
			_grid(inner, cell * 1.3, func(c: Vector2, r: int, k: int) -> void:
				var big := (r + k) % 3 == 0
				var jitter := Vector2(cell * 0.15 * ((r * 3 + k) % 3 - 1), cell * 0.15 * ((r + k * 2) % 3 - 1))
				draw_star(ci, c + jitter, cell * (0.42 if big else 0.22), fg if big else skin["back_edge"]), true)
			var moon := inner.position + Vector2(inner.size.x * 0.7, inner.size.y * 0.2)
			ci.draw_circle(moon, cell * 0.9, fg)
			ci.draw_circle(moon + Vector2(cell * 0.4, -cell * 0.2), cell * 0.8, skin["back_dark"])
		"target":
			# a bullseye with a crosshair, like a shooting-range card
			var c := inner.get_center()
			var rmax := minf(inner.size.x, inner.size.y) * 0.46
			for i in range(5):
				ci.draw_circle(c, rmax * (1.0 - i * 0.2), fg if i % 2 == 0 else skin["back_dark"])
			var wide := maxf(1.0, cell * 0.1)
			ci.draw_line(Vector2(inner.position.x, c.y), Vector2(inner.end.x, c.y), skin["back_dark"], wide)
			ci.draw_line(Vector2(c.x, inner.position.y), Vector2(c.x, inner.end.y), skin["back_dark"], wide)
		"hazard":
			# thick warning stripes
			var step := cell * 1.6
			var t := -inner.size.y
			while t < inner.size.x:
				var seg := _clip_line(inner.position + Vector2(t, inner.size.y), inner.position + Vector2(t + inner.size.y, 0), inner)
				if not seg.is_empty():
					ci.draw_line(seg[0], seg[1], fg, step * 0.36)
				t += step
		"grid":
			# drafting paper: fine lines, a bold frame and a compass mark
			var faint := Color(fg, 0.45)
			var x := inner.position.x
			while x <= inner.end.x:
				ci.draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), faint, 1.0)
				x += cell * 0.5
			var y := inner.position.y
			while y <= inner.end.y:
				ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), faint, 1.0)
				y += cell * 0.5
			var wide := maxf(1.5, cell * 0.13)
			ci.draw_rect(inner.grow(-cell * 0.4), fg, false, wide)
			var c := inner.get_center()
			ci.draw_arc(c, cell * 1.6, 0.0, TAU, 32, fg, wide)
			ci.draw_line(c - Vector2(cell * 2.2, 0), c + Vector2(cell * 2.2, 0), fg, wide)
			ci.draw_line(c - Vector2(0, cell * 2.2), c + Vector2(0, cell * 2.2), fg, wide)
		"web":
			# a spider web, and its spider
			var c := inner.position + Vector2(inner.size.x * 0.5, inner.size.y * 0.42)
			var ends: Array = []
			for i in range(10):
				var a := i * TAU / 10.0
				var seg := _clip_line(c, c + Vector2(cos(a), sin(a)) * 999.0, inner)
				ends.append(seg[1] if not seg.is_empty() else c)
			var thin := maxf(1.0, cell * 0.08)
			for e in ends:
				ci.draw_line(c, e, fg, thin)
			for t in [0.18, 0.36, 0.56, 0.78]:
				var ring := PackedVector2Array()
				for e in ends:
					ring.append(c + (Vector2(e) - c) * t)
				ring.append(ring[0])
				ci.draw_polyline(ring, fg, thin)
			var sp := c + Vector2(cell * 1.2, cell * 2.2)
			var leg: Color = skin["back_edge"]
			ci.draw_line(c + (sp - c) * 0.4, sp, leg, 1.0)
			for i in range(4):
				var dy := (i - 1.5) * cell * 0.16 - cell * 0.1
				ci.draw_line(sp + Vector2(-cell * 0.6, dy * 1.6), sp + Vector2(cell * 0.6, dy * 1.6), leg, maxf(1.0, cell * 0.08))
			ci.draw_circle(sp, cell * 0.32, leg)
		"sprite":
			_sprite_tiles(ci, inner, face)
		"portals":
			# white test-chamber panels with an orange and a blue portal
			if not face:
				ci.draw_rect(inner, skin["back_dark"])
			var faint := Color(skin["back_edge"].lerp(skin["back_dark"], 0.85), 1.0) if not face else _tint(Color(0.6, 0.62, 0.64))
			var x := inner.position.x
			while x <= inner.end.x:
				ci.draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), faint, 1.0)
				x += cell * 1.5
			var y := inner.position.y
			while y <= inner.end.y:
				ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), faint, 1.0)
				y += cell * 1.5
			_portal(ci, inner.position + Vector2(inner.size.x * 0.3, inner.size.y * 0.3), cell, fg)
			_portal(ci, inner.position + Vector2(inner.size.x * 0.7, inner.size.y * 0.7), cell, skin["back_edge"])
		"teams":
			# split down the middle: one team's colour each side, hats on top
			ci.draw_colored_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y)]), fg)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]), skin["back_dark"])
			_sprite_tiles(ci, inner, true)
		"cheat":
			# the most famous button combo in gaming
			var arrows := [0, 0, 2, 2, 3, 1, 3, 1] # up up down down left right left right
			var size := inner.size.x / 9.0
			var row_y := inner.position.y + inner.size.y * 0.32
			for i in range(8):
				var col := i % 4
				var line := i / 4
				var c := Vector2(inner.position.x + size * (1.2 + col * 2.2), row_y + line * size * 2.4)
				_arrow(ci, c, size * 0.8, arrows[i], fg)
			if font != null:
				var fs := int(size * 2.2)
				var text := "B  A"
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ci.draw_string(font, Vector2(inner.get_center().x - w * 0.5, inner.position.y + inner.size.y * 0.86), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, skin["back_edge"])
		"maze":
			# maze walls and a trail of dots
			var walls := [[0, 0, 6, 0], [0, 0, 0, 8], [6, 0, 6, 8], [0, 8, 6, 8], [1, 1, 2, 1], [4, 1, 5, 1], [1, 2, 1, 3], [3, 1, 3, 3], [5, 2, 5, 3], [2, 4, 4, 4], [0, 5, 1, 5], [5, 5, 6, 5], [1, 6, 2, 6], [4, 6, 5, 6], [3, 5, 3, 7]]
			var gx := inner.size.x / 6.0
			var gy := inner.size.y / 8.0
			var wide := maxf(2.0, cell * 0.22)
			for w in walls:
				ci.draw_line(inner.position + Vector2(w[0] * gx, w[1] * gy), inner.position + Vector2(w[2] * gx, w[3] * gy), fg, wide)
			for yy in range(8):
				for xx in range(6):
					var dot := inner.position + Vector2((xx + 0.5) * gx, (yy + 0.5) * gy)
					ci.draw_circle(dot, cell * (0.28 if (xx == 0 and yy == 0) or (xx == 5 and yy == 7) else 0.1), skin["back_edge"])
		"paddle":
			# two paddles, a dotted net and the ball
			var y := inner.position.y
			while y < inner.end.y:
				ci.draw_rect(Rect2(Vector2(inner.get_center().x - cell * 0.08, y), Vector2(cell * 0.16, cell * 0.35)), fg)
				y += cell * 0.7
			ci.draw_rect(Rect2(inner.position + Vector2(cell * 0.4, inner.size.y * 0.25), Vector2(cell * 0.3, cell * 2.0)), fg)
			ci.draw_rect(Rect2(Vector2(inner.end.x - cell * 0.7, inner.position.y + inner.size.y * 0.55), Vector2(cell * 0.3, cell * 2.0)), fg)
			ci.draw_rect(Rect2(inner.position + Vector2(inner.size.x * 0.66, inner.size.y * 0.36), Vector2(cell * 0.35, cell * 0.35)), fg)
		_:
			# a little diamond lattice
			_grid(inner, cell, func(c: Vector2, _r: int, _k: int) -> void:
				var h := cell * 0.42
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]), fg), true)


## Tiles the skin's pixel sprite(s) across `inner`: "sprite" (rows of
## palette letters, "." see-through) or "sprites" (several, taken in turn),
## "repeat" tiles across.
static func _sprite_tiles(ci: CanvasItem, inner: Rect2, face: bool) -> void:
	var sprites: Array = skin["sprites"] if skin.has("sprites") else [skin["sprite"]]
	var pal: Dictionary = skin["palette"]
	var cols: int = str(sprites[0][0]).length()
	var rows: int = sprites[0].size()
	var across := int(skin.get("repeat", 3))
	var px := inner.size.x / float(across * cols)
	var tile := Vector2(cols, rows) * px
	var down := int(floor(inner.size.y / tile.y))
	var top := inner.position.y + (inner.size.y - down * tile.y) * 0.5
	for ty in range(down):
		for tx in range(across):
			var spr: Array = sprites[(tx + ty) % sprites.size()]
			var origin := Vector2(inner.position.x + tx * tile.x, top + ty * tile.y)
			for r in range(rows):
				var line: String = spr[r]
				for k in range(cols):
					var ch := line[k]
					if ch == "." or not pal.has(ch):
						continue
					ci.draw_rect(Rect2(origin + Vector2(k, r) * px, Vector2(px, px) + Vector2(0.6, 0.6)), pal[ch])


## An oval portal: a bright ring round a darker middle.
static func _portal(ci: CanvasItem, c: Vector2, cell: float, color: Color) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(24):
		var a := i * TAU / 24.0
		outer.append(c + Vector2(cos(a) * cell * 1.1, sin(a) * cell * 1.9))
		inner.append(c + Vector2(cos(a) * cell * 0.75, sin(a) * cell * 1.45))
	ci.draw_colored_polygon(outer, color)
	ci.draw_colored_polygon(inner, color.darkened(0.08 if skin.has("_wash") else 0.45))


## An arrow pointing up (0), right (1), down (2) or left (3).
static func _arrow(ci: CanvasItem, c: Vector2, s: float, dir: int, color: Color) -> void:
	var pts := [Vector2(0, -1), Vector2(0.9, 0.2), Vector2(0.35, 0.2), Vector2(0.35, 1), Vector2(-0.35, 1), Vector2(-0.35, 0.2), Vector2(-0.9, 0.2)]
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(c + Vector2(p).rotated(dir * PI / 2.0) * s)
	ci.draw_colored_polygon(poly, color)


## Calls draw(centre, row, column) for every cell of a grid filling `inner`.
## `offset` shifts every other row by half a cell.
static func _grid(inner: Rect2, cell: float, draw: Callable, offset: bool = false) -> void:
	var y := inner.position.y
	var row := 0
	while y + cell <= inner.end.y + 0.5:
		var x := inner.position.x + (cell * 0.5 if offset and row % 2 == 1 else 0.0)
		var k := 0
		while x + cell <= inner.end.x + 0.5:
			draw.call(Vector2(x + cell * 0.5, y + cell * 0.5), row, k)
			x += cell
			k += 1
		y += cell
		row += 1


## The part of the line a-b inside `r`, or [] if none (for stripes).
static func _clip_line(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for i in range(4):
		var p: float = [-d.x, d.x, -d.y, d.y][i]
		var q: float = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y][i]
		if absf(p) < 0.00001:
			if q < 0.0:
				return []
			continue
		var t := q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]


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


## A four-pointed star with a dark outline, marking trump cards.
static func draw_star(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	var outline := PackedVector2Array()
	var fill := PackedVector2Array()
	for i in range(8):
		var a := i * PI / 4.0 - PI / 2.0
		var r := s if i % 2 == 0 else s * 0.38
		outline.append(c + Vector2(cos(a), sin(a)) * (r + 2.0))
		fill.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(outline, Palette.CARD_INK)
	ci.draw_colored_polygon(fill, color)


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
