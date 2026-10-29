extends SceneTree
## Taps through a trump swap on the real table screen (pass-and-play).
##   godot --headless --path . -s tests/ui_swap_check.gd

const Cards = preload("res://scripts/core/cards.gd")


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.player_names = ["SAM", "ALEX"]
	main.hide_hands = false
	main._start_from_setup()
	await process_frame
	var g = main.game
	for p in g.players:
		p.turns_taken = 2
	g.melds.append({"id": "mx", "type": "run", "cards": Cards.parse_many("2C 3C AD 5C"), "owner": 1})
	g.players[0].hand = Cards.parse_many("4C 9H 9S KD")
	g.stock.append(Cards.parse("QD"))
	g.draw_stock(0)
	main._refresh()
	main.selected = ["4C", "9H", "9S"]
	main._refresh()
	var status: String = main.status_label.text
	main._lay_off_on("mx")
	await process_frame
	var ok: bool = Cards.ids_of(g.find_meld("mx")["cards"]) == ["2C", "3C", "4C", "5C"] and g.melds.size() == 2
	print("status before tap: " + status)
	print("UI SWAP %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
