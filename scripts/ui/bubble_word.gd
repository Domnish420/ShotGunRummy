extends Button
## A floating word you tap, in place of a boxed button: big outlined letters
## that bob and sway like an old handheld game's menu.

var _t := 0.0
var _speed := 1.0


func setup(word: String, on_press: Callable, color: Color, font_size: int = 52) -> void:
	text = word
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_hover_color", color.lightened(0.25))
	add_theme_color_override("font_pressed_color", color.lightened(0.4))
	add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
	add_theme_constant_override("outline_size", 14)
	pressed.connect(on_press)
	_t = randf() * TAU
	_speed = randf_range(0.8, 1.2)
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _process(delta: float) -> void:
	_t += delta * _speed
	if disabled:
		rotation = 0.0
		scale = Vector2.ONE
		return
	rotation = sin(_t * 1.7) * 0.05
	var s := 1.0 + sin(_t * 2.6) * 0.04 + (0.08 if is_hovered() else 0.0)
	scale = Vector2(s, s)
