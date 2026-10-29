extends RefCounted
## Colours and style helpers for the dark, grimy table look.

const BG := Color(0.043, 0.039, 0.035)
const INK := Color(0.847, 0.824, 0.753)
const DIM := Color(0.490, 0.467, 0.416)
const RED := Color(0.769, 0.188, 0.169)
const PINK := Color(0.941, 0.698, 0.682)
const AMBER := Color(0.890, 0.702, 0.255)
const GOLD := Color(1.0, 0.808, 0.247)
const PAPER := Color(0.914, 0.886, 0.812)
const WAIVER := Color(0.851, 0.820, 0.733)
const CARD_INK := Color(0.086, 0.078, 0.071)
const CARD_RED := Color(0.639, 0.125, 0.106)
const FELT := Color(0.059, 0.165, 0.114)
const FELT_DARK := Color(0.027, 0.082, 0.055)
const WOOD := Color(0.102, 0.071, 0.047)
const ITEM_BG := Color(0.110, 0.082, 0.075)
const PURPLE := Color(0.561, 0.420, 0.847)
const BACK := Color(0.353, 0.075, 0.063)
const BACK_DARK := Color(0.231, 0.043, 0.035)
const BUTTON := Color(0.078, 0.071, 0.063)
const BUTTON_EDGE := Color(0.227, 0.212, 0.184)
const HP_EMPTY := Color(0.165, 0.047, 0.043)
const SHELL_BRASS := Color(0.788, 0.635, 0.290)


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0, radius: int = 4, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	var font = load("res://fonts/VT323.woff2")
	if font is Font:
		t.default_font = font
	t.default_font_size = 30

	t.set_color("font_color", "Label", INK)

	t.set_stylebox("normal", "Button", box(BUTTON, BUTTON_EDGE, 2, 2, 10))
	t.set_stylebox("hover", "Button", box(BUTTON, INK, 2, 2, 10))
	t.set_stylebox("pressed", "Button", box(Color(0.15, 0.14, 0.12), AMBER, 2, 2, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.05, 0.05, 0.045), Color(0.13, 0.12, 0.11), 2, 2, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color(0.3, 0.29, 0.26))

	t.set_stylebox("normal", "LineEdit", _underline(Color(0, 0, 0, 0)))
	t.set_stylebox("focus", "LineEdit", _underline(Color(0, 0, 0, 0.06)))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "LineEdit", CARD_INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.35, 0.32, 0.27))
	t.set_color("caret_color", "LineEdit", CARD_INK)
	t.set_font_size("font_size", "LineEdit", 34)

	t.set_stylebox("panel", "PanelContainer", box(Color(0, 0, 0, 0)))
	return t


static func _underline(bg: Color) -> StyleBoxFlat:
	var sb := box(bg, CARD_INK, 0, 0, 6)
	sb.border_width_bottom = 3
	return sb


## A coloured button style, e.g. red for DISCARD.
static func accent(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", box(BUTTON, color, 2, 2, 10))
	button.add_theme_stylebox_override("hover", box(BUTTON, color.lightened(0.3), 2, 2, 10))
	button.add_theme_color_override("font_color", color.lightened(0.45))
	button.add_theme_color_override("font_hover_color", color.lightened(0.6))
