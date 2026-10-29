extends Control
## A chunky shotgun drawn with polygons. Call kick() for recoil.


func _ready() -> void:
	custom_minimum_size = Vector2(440, 100)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func kick() -> void:
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "rotation", -0.12, 0.05)
	t.parallel().tween_property(self, "position:x", position.x - 30.0, 0.05)
	t.tween_property(self, "rotation", 0.0, 0.3)
	t.parallel().tween_property(self, "position:x", position.x, 0.3)


func _draw() -> void:
	var k := size.x / 440.0
	var o := Vector2(0, (size.y - 100.0 * k) * 0.5)
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	# barrels
	draw_rect(Rect2(p.call(110, 26), Vector2(320, 12) * k), Color(0.29, 0.29, 0.29))
	draw_rect(Rect2(p.call(110, 39), Vector2(280, 9) * k), Color(0.2, 0.2, 0.2))
	# pump
	draw_rect(Rect2(p.call(220, 46), Vector2(80, 13) * k), Color(0.36, 0.23, 0.13))
	# stock
	draw_colored_polygon(PackedVector2Array([p.call(10, 42), p.call(110, 22), p.call(124, 22), p.call(124, 60), p.call(92, 62), p.call(66, 94), p.call(18, 94), p.call(6, 68)]), Color(0.42, 0.27, 0.16))
	# trigger guard
	draw_arc(p.call(112, 62), 14.0 * k, 0.2, PI - 0.2, 12, Color(0.16, 0.16, 0.16), 4.0 * k)
