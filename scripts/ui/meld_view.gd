extends Control
## A meld on the table: overlapping cards with the owner's name. Tap it to lay
## off the selected cards onto it.

signal tapped(meld_id: String)

const CardArt = preload("res://scripts/ui/card_art.gd")
const Palette = preload("res://scripts/ui/palette.gd")

const CARD := Vector2(46, 66)
const STEP := 24.0
const LABEL_H := 22.0

var meld: Dictionary = {}
var owner_label := ""
var target := false


func setup(p_meld: Dictionary, p_owner_label: String, p_target: bool) -> void:
	meld = p_meld
	owner_label = p_owner_label
	target = p_target
	var n: int = meld["cards"].size()
	custom_minimum_size = Vector2(STEP * (n - 1) + CARD.x + 8, CARD.y + LABEL_H + 8)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(str(meld["id"]))
		accept_event()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 17), owner_label, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 18, Palette.DIM)
	var x := 4.0
	for c in meld["cards"]:
		CardArt.draw_card(self, font, Rect2(Vector2(x, LABEL_H + 4), CARD), c, false, true)
		x += STEP
	if target:
		draw_rect(Rect2(Vector2(1, LABEL_H), size - Vector2(2, LABEL_H + 1)), Palette.AMBER, false, 3.0)
