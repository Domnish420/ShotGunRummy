extends Control
## TIMBER's view from above: a round little map of the layer you're working
## on, drawn flat. The tower's square, the blocks in that layer where they
## really are (yours in gold, a line showing how far it has to go to be
## clear), and the fingertip (white) with where your thumb wants it (ghost).

var tower # tower3d.gd
var hand # hand3d.gd
var layer := -1
var block: RigidBody3D = null
var forward := Vector3(0, 0, -1) # the way you're pushing: up on the map, like your thumb

const SCALE := 520.0 # pixels per metre
const PINE := Color(0.92, 0.78, 0.55)
const GOLD := Color(1.0, 0.82, 0.25)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(220, 220)
	size = Vector2(220, 220)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _to_px(p: Vector3, c: Vector3) -> Vector2:
	var d := Vector2(p.x - c.x, p.z - c.z)
	var f := Vector2(forward.x, forward.z).normalized()
	var r := Vector2(-f.y, f.x)
	return size * 0.5 + Vector2(d.dot(r), -d.dot(f)) * SCALE


func _draw() -> void:
	var r := size.x * 0.5
	var mid := size * 0.5
	draw_circle(mid, r, Color(0.06, 0.04, 0.03, 0.88))
	if tower == null or block == null or not is_instance_valid(block):
		return
	var c: Vector3 = tower.tower_center()
	# the tower's footprint
	var foot := PackedVector2Array()
	for corner in [[-1, -1], [1, -1], [1, 1], [-1, 1], [-1, -1]]:
		foot.append(_to_px(c + Vector3(corner[0], 0, corner[1]) * tower.L * 0.5, c))
	draw_polyline(foot, Color(1, 1, 1, 0.18), 2.0)
	# the blocks in this layer
	for b in tower.blocks:
		if tower.removed.has(b) or int(b.get_meta("layer")) != layer:
			continue
		var axis: Vector3 = tower.block_axis(b)
		var across := Vector3(-axis.z, 0, axis.x)
		var p: Vector3 = b.global_position
		var pts := PackedVector2Array()
		for corner in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			pts.append(_to_px(p + axis * (tower.L * 0.5 * corner[0]) + across * (tower.W * 0.5 * corner[1]), c))
		var col: Color = GOLD if b == block else PINE.darkened(0.25)
		draw_colored_polygon(pts, col)
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.7), 2.0)
	# the fingertip, and where your thumb wants it
	if hand != null and hand.visible:
		draw_circle(_to_px(hand.target, c), 7.0, Color(1, 1, 1, 0.35))
		draw_circle(_to_px(hand.tip.global_position, c), 6.0, Color(1, 1, 1))
	# the rim
	draw_arc(mid, r - 3.0, 0.0, TAU, 48, Color(0.95, 0.85, 0.4), 6.0)
