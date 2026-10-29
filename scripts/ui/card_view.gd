extends Control
## One tappable card. Selected cards lift up; hinted cards get an amber bar.

signal tapped(card_id: String)

const CardArt = preload("res://scripts/ui/card_art.gd")
const Palette = preload("res://scripts/ui/palette.gd")

var card: Dictionary = {}
var face_down := false
var selected := false
var hint := false
var glow := false
var locked := false
var lift := 0.0


func setup(p_card: Dictionary, card_size: Vector2, p_lift: float = 0.0, p_face_down: bool = false) -> void:
	card = p_card
	face_down = p_face_down
	lift = p_lift
	custom_minimum_size = card_size + Vector2(0, lift)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(str(card.get("id", "")))
		accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	var top := 0.0 if selected else lift
	var rect := Rect2(Vector2(0, top), Vector2(size.x, size.y - lift))
	CardArt.draw_card(self, font, rect, card, face_down)
	if locked:
		draw_rect(rect, Color(0, 0, 0, 0.35))
	if hint:
		draw_rect(Rect2(rect.position.x + 8, rect.end.y - 6, rect.size.x - 16, 4), Palette.AMBER)
	if selected:
		draw_rect(rect.grow(2), Palette.AMBER, false, 4.0)
	elif glow:
		draw_rect(rect.grow(3), Color(Palette.AMBER, 0.85), false, 3.0)
