extends SceneTree
## Plays a whole match through the real UI (the same handlers taps trigger) and
## saves screenshots. Needs a display, so not headless:
##   godot --path . -s tests/ui_smoke.gd -- --shots=/some/folder

const Cards = preload("res://scripts/core/cards.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Items = preload("res://scripts/core/items.gd")

var main
var shots_dir := ""
var taken := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _frames(n: int = 4) -> void:
	for i in range(n):
		await process_frame


func _shot(name: String) -> void:
	if shots_dir == "" or taken.has(name):
		return
	taken[name] = true
	await _frames(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])


func _overlay_buttons() -> Array:
	var out := []
	var stack: Array = [main.overlay_layer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and not n.disabled:
			out.append(n)
		stack.append_array(n.get_children())
	out.reverse()
	return out


func _overlay_text() -> String:
	var parts := []
	var stack: Array = [main.overlay_layer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			parts.append(n.text)
		stack.append_array(n.get_children())
	return " ".join(parts)


func _run() -> void:
	await _frames(6)
	await _shot("00_menu")
	main._name_edit.text = "sam"
	main._on_host_pressed()
	await _frames()
	await _shot("00b_host_lobby")
	main.show_menu()
	await _frames()
	main._on_join_pressed()
	await _frames(90)
	await _shot("00c_join")
	main.show_menu()
	await _frames()
	main._on_pass_and_play_pressed()
	await _frames()
	await _shot("01_setup")
	main.player_names = ["SAM", "ALEX", "JO"]
	main.setup_bots = [] # everyone a person (settings may remember AIs)
	main.game_kind = "rummy" # settings may remember another game
	main.normal_mode = false
	main.hide_hands = true
	main.show_setup()
	await _frames()
	main._start_from_setup()
	await _frames()
	await _shot("02_pass_screen")

	var steps := 0
	var used_item := false
	while steps < 20000:
		steps += 1
		await _frames(1)
		var game = main.game
		if OS.get_cmdline_user_args().has("--progress") and steps % 400 == 0:
			print("step %d: round %d phase %s turn %d overlay %d [%s] status '%s' dealing %s fx %s" % [steps, game.round_num, game.phase, game.turn, main.overlay_layer.get_child_count(), _overlay_text().left(60), main.status_label.text, main.world.dealing, main.world.fx_busy])
		if main.overlay_layer.get_child_count() > 0:
			var text := _overlay_text()
			if text.contains("HAS THE SHOTGUN"):
				await _shot("06_shotgun")
			elif text.contains("GOES OUT") or text.contains("DEAD DECK"):
				await _shot("05_round_result")
			elif text.contains("WALKS OUT") or text.contains("NOBODY WALKS OUT"):
				await _shot("07_match_end")
				print("SMOKE OK: match finished after %d rounds" % game.round_num)
				quit(0)
				return
			elif text.contains("USES") or text.contains("DREW AN ITEM"):
				if text.contains("DREW AN ITEM"):
					await _shot("04b_drew_item")
				await _shot("04_item")
			var buttons := _overlay_buttons()
			var pick = buttons[0] if not buttons.is_empty() else null
			for b in buttons:
				if b.text.begins_with("SHOOT"):
					pick = b
					break
			if pick == null:
				push_error("overlay without buttons: " + text)
				quit(1)
				return
			pick.pressed.emit()
			continue

		var seat: int = game.turn
		var me = game.players[seat]
		if game.phase == "draw":
			# try an item now and then, through the UI
			if not used_item and not me.items.is_empty():
				for item in me.items:
					if game.item_blocker(seat, item["id"]) == "":
						main._toggle_item(item["id"])
						await _frames()
						await _shot("03_item_selected")
						main._use_selected_item()
						used_item = true
						break
				if main.overlay_layer.get_child_count() > 0:
					continue
			used_item = false
			var top: Dictionary = game.top_discard()
			if not top.is_empty() and Bot.helps(game, me.hand, top):
				main._draw_discard()
			else:
				main._draw_stock()
			continue
		if game.phase == "play":
			if game.go_out_check(seat)["can"]:
				await _shot("03d_can_go_out")
			var best: Dictionary = Cards.best_partition(me.hand, game.trump_rank) if game.can_place(seat) else {"melds": []}
			if not best["melds"].is_empty():
				main.selected = Cards.ids_of(best["melds"][0])
				main._refresh()
				await _frames()
				await _shot("03b_meld_ready")
				main._meld_selected()
				continue
			var laid := false
			for c in (me.hand if game.can_place(seat) else []):
				for m in game.melds:
					if Cards.can_lay_off(m, [c], game.trump_rank):
						main.selected = [c["id"]]
						main._lay_off_on(m["id"])
						laid = true
						break
				if laid:
					break
			if laid:
				continue
			if game.melds.size() >= 2:
				await _shot("03c_table_with_melds")
			main.selected = [Bot.choose_discard(game, seat)]
			main._discard_selected()
	var g = main.game
	push_error("smoke test did not finish: round %d, phase %s, turn %d, overlay %d [%s], status '%s'" % [g.round_num, g.phase, g.turn, main.overlay_layer.get_child_count(), _overlay_text(), main.status_label.text])
	quit(1)
