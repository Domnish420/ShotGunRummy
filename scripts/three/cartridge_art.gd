extends Node
## The cartridge labels: each game's title drawn like an early-2000s
## handheld game logo (a chunky bevelled name with a fat outline and drop
## shadow, a sunburst behind it, sparkles), drawn small and blown up with
## crisp pixels. Built once at startup in a SubViewport, like the card faces.

signal built

const Games = preload("res://scripts/core/games.gd")

const W := 160
const H := 100

var _textures := {}
var is_built := false


func texture(kind: String) -> Texture2D:
	return _textures.get(kind, null)


class Label_ extends Control:
	var kind := ""
	var font: Font

	func _draw() -> void:
		var col: Color = Games.color(kind)
		var w := size.x
		var h := size.y
		# sky: light at the top, deep at the bottom
		for y in range(int(h)):
			var t := y / h
			draw_rect(Rect2(0, y, w, 1), col.lightened(0.45).lerp(col.darkened(0.45), t))
		# sunburst from behind the title
		var c := Vector2(w * 0.5, h * 0.56)
		for i in range(16):
			if i % 2 == 1:
				continue
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * w, c + Vector2(cos(a1), sin(a1)) * w]), Color(1, 1, 1, 0.12))
		# a band behind the name
		draw_rect(Rect2(0, h * 0.4, w, h * 0.34), Color(0, 0, 0, 0.25))
		# "SHOTGUN" in red, bouncing along an arc
		var top := "SHOTGUN"
		var x := w * 0.5 - top.length() * 6.0
		for i in range(top.length()):
			var y := h * 0.3 - sin(PI * (i + 0.5) / top.length()) * 6.0
			var ch := top.substr(i, 1)
			draw_string_outline(font, Vector2(x + 1, y + 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.2, 0.12))
			draw_string(font, Vector2(x, y - 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.55, 0.4, 0.6))
			x += 12.0
		# the name: shadow, fat outline, orange body, gold bevel on top
		var name_text: String = Games.label(kind)
		var fs := 44 if name_text.length() <= 6 else (36 if name_text.length() <= 8 else 30)
		var tw := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2((w - tw) * 0.5, h * 0.7)
		draw_string_outline(font, p + Vector2(3, 3), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.7))
		draw_string_outline(font, p, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.08, 0.03, 0.02))
		draw_string(font, p, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.5, 0.08))
		draw_string(font, p - Vector2(0, 2), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.2, 0.75))
		draw_string(font, p - Vector2(0, 4), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 0.8, 0.35))
		# sparkles
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(kind) + 3
		for i in range(4):
			var s := Vector2(rng.randf_range(8, w - 8), rng.randf_range(6, h * 0.45))
			var r := rng.randf_range(2.5, 4.5)
			draw_colored_polygon(PackedVector2Array([s + Vector2(0, -r * 2), s + Vector2(r * 0.4, 0), s + Vector2(0, r * 2), s + Vector2(-r * 0.4, 0)]), Color(1, 1, 0.85))
			draw_colored_polygon(PackedVector2Array([s + Vector2(-r * 2, 0), s + Vector2(0, r * 0.4), s + Vector2(r * 2, 0), s + Vector2(0, -r * 0.4)]), Color(1, 1, 0.85))
		# the strip along the bottom
		draw_rect(Rect2(0, h - 13, w, 13), Color(0.06, 0.06, 0.08))
		draw_string(font, Vector2(6, h - 3), "SHOTGUN CARDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.85))
		draw_string(font, Vector2(w - 34, h - 3), "2-6P", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.5))


func build() -> void:
	var font: Font = load("res://fonts/VT323.woff2") as Font
	var kinds := Games.kinds()
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H * kinds.size())
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in range(kinds.size()):
		var l := Label_.new()
		l.kind = kinds[i]
		l.font = font
		l.position = Vector2(0, H * i)
		l.size = Vector2(W, H)
		vp.add_child(l)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image() if vp.get_texture() != null else null
	if img != null and not img.is_empty():
		for i in range(kinds.size()):
			_textures[kinds[i]] = ImageTexture.create_from_image(img.get_region(Rect2i(0, H * i, W, H)))
	vp.queue_free()
	is_built = not _textures.is_empty()
	built.emit()
