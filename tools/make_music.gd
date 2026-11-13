extends SceneTree
## Renders the saloon music (scripts/audio/saloon.gd) into res://music/, one
## track for the room and one per game. Run it again after changing the tune
## or adding a game:
##   godot --headless --path . -s tools/make_music.gd [-- room poker ...]

const Saloon = preload("res://scripts/audio/saloon.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://music"))
	var only := OS.get_cmdline_user_args()
	for id in Saloon.VARIANTS:
		if not only.is_empty() and not only.has(id):
			continue
		var t0 := Time.get_ticks_msec()
		var stream := Saloon.render(id)
		var path := "res://music/%s.res" % id
		var err := ResourceSaver.save(stream, path)
		print("%s: %.1fs of music, %d KB, made in %.1fs%s" % [id, stream.data.size() / 2.0 / Saloon.RATE, stream.data.size() / 1024, (Time.get_ticks_msec() - t0) / 1000.0, "" if err == OK else " (SAVE FAILED %d)" % err])
	quit()
