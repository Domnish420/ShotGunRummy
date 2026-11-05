extends SceneTree
## Writes every item card's face to item_faces/ as a 512x736 PNG, plus a
## blank template and a list of what each item does in each game: a kit
## for drawing new faces. Put finished art in textures/items/<id>.png.
##   godot --path . -s tools/export_item_faces.gd -- <out dir>

const Items = preload("res://scripts/core/items.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const Palette = preload("res://scripts/ui/palette.gd")
const SIZE := Vector2i(512, 736)


class Blank extends Control:
	func _draw() -> void:
		draw_style_box(Palette.box(Palette.ITEM_BG, Palette.PURPLE, 8, 24), Rect2(Vector2.ZERO, size))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "item_faces"
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var theme_holder := Control.new()
	theme_holder.theme = Palette.make_theme()
	theme_holder.size = Vector2(SIZE)
	vp.add_child(theme_holder)
	var lines := ["SHOTGUN PARTY ITEM CARDS", "Draw each face at 512 x 736 px (PNG) and name it <id>.png.", "The whole face is yours: picture, name, border. Rounded corners are fine (transparent outside).", ""]
	for id in Items.DEFS:
		for c in theme_holder.get_children():
			c.queue_free()
		var cv := CardView.new()
		theme_holder.add_child(cv)
		cv.setup({"id": "I-%s-1" % id, "item": id}, Vector2(SIZE))
		cv.size = Vector2(SIZE)
		for i in range(4):
			await process_frame
		vp.get_texture().get_image().save_png("%s/%s.png" % [out, id])
		var d: Dictionary = Items.DEFS[id]
		lines.append("%s.png  -  %s %s  (%d in the deck)" % [id, d["icon"], d["name"], int(d["copies"])])
		lines.append("    Rummy: %s" % d["text"])
		for game in Items.OVERRIDES:
			var change: Dictionary = Items.OVERRIDES[game].get(id, {})
			if change.has("text"):
				lines.append("    %s: %s" % [game.capitalize(), change["text"]])
		lines.append("")
	for c in theme_holder.get_children():
		c.queue_free()
	var blank := Blank.new()
	blank.size = Vector2(SIZE)
	theme_holder.add_child(blank)
	for i in range(4):
		await process_frame
	vp.get_texture().get_image().save_png("%s/_blank_template.png" % out)
	var f := FileAccess.open("%s/ITEMS.txt" % out, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("wrote %d item faces to %s" % [Items.DEFS.size(), out])
	quit()
