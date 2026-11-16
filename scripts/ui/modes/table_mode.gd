extends RefCounted
## A game's table screen: its three buttons, what tapping the table does, the
## status line, its log lines, its end-of-round screen, rules and tutorial
## tips. main.gd builds everything the games share (menus, the shotgun, the
## pass screen, items) and hands the rest to one of these.

const Cards = preload("res://scripts/core/cards.gd")
const Items = preload("res://scripts/core/items.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const CardView = preload("res://scripts/ui/card_view.gd")

var main # main.gd


func _init(m) -> void:
	main = m


## The three big buttons: [text, callable, accent color or null]. A text of
## "" hides that button.
func buttons() -> Array:
	return []


## Redraws the table and the buttons.
func refresh() -> void:
	pass


func status() -> String:
	return ""


## A tap on the table found `hit` (see world3d.pick).
func on_pick(_hit: Dictionary) -> void:
	pass


## Game events this game adds (logging and effects).
func on_event(_kind: String, _d: Dictionary) -> void:
	pass


## Fills in the end-of-round screen above the shotgun / next round buttons.
func show_result(_box: VBoxContainer) -> void:
	pass


func rules() -> Array:
	return []


## A tip for the tutorial, about what to do right now.
func coach() -> String:
	return ""


# ---------------------------------------------------------------- helpers

func game():
	return main.game


## A row of small face-up cards.
func card_row(cards: Array, card_size: Vector2 = Vector2(52, 76)) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	for c in cards:
		var cv := CardView.new()
		cv.setup(c, card_size)
		cv.trump = main.game.is_trump(c)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.add_child(cv)
	return flow


## Status text while it's not your turn.
func waiting_text() -> String:
	var g = main.game
	if main._is_bot(g.turn):
		return "%s IS THINKING..." % main._name(g.turn)
	return "WAITING FOR %s..." % main._name(g.turn)


## The status line for a selected item, or "".
func item_text() -> String:
	var g = main.game
	if main.selected_item == "":
		return ""
	var item: Dictionary = g.find_item(main._me(), main.selected_item)
	if item.is_empty():
		return ""
	var def := Items.def(item["item"])
	var blocker: String = g.item_blocker(main._me(), main.selected_item)
	return "%s: %s%s" % [str(def["name"]).to_upper(), def["text"], " (%s)" % blocker if blocker != "" else ""]
