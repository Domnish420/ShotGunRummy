extends SceneTree
## Rules tests. Run from the project folder:
##   godot --headless --path . -s tests/test_runner.gd

const Cards = preload("res://scripts/core/cards.gd")
const Game = preload("res://scripts/core/game.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Items = preload("res://scripts/core/items.gd")

var _failures := 0
var _checks := 0
var _test := ""


func _init() -> void:
	for t in [
		"test_deck", "test_points", "test_trump_rotation", "test_trump_runs", "test_trump_sets",
		"test_trump_lay_off", "test_trump_in_game", "test_trump_partition", "test_go_out_check", "test_no_placing_first_turn", "test_trump_swap", "test_sets", "test_runs", "test_lay_off", "test_best_partition",
		"test_deal", "test_drawing_an_item", "test_beer_can_burn_an_item", "test_dealer_rotation", "test_turn_guards", "test_discard_pickup_rule",
		"test_many_items_per_turn", "test_handcuffs", "test_items_need_targets", "test_magnifier_and_beer",
		"test_adrenaline", "test_going_out_scores_everyone", "test_shotgun_and_elimination",
		"test_bot_matches",
	]:
		_test = t
		call(t)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL [%s] %s" % [_test, what])


## Draws from the stock until a playing card comes up (items mean drawing again).
func draw_playing_card(g: Game, seat: int) -> void:
	while g.is_turn_of(seat) and g.phase == "draw":
		g.draw_stock(seat)


## Lets everyone put cards down (they're past their first turn).
func past_first_turn(g: Game) -> void:
	for p in g.players:
		p.turns_taken = 2


func cards(ids: String) -> Array:
	return Cards.parse_many(ids)


func new_game(n: int = 2, rng_seed: int = 1) -> Game:
	var names := []
	for i in range(n):
		names.append("P%d" % (i + 1))
	var g := Game.new()
	g.setup(names, {}, rng_seed)
	g.start_round()
	return g


# ------------------------------------------------------------------ cards

func test_deck() -> void:
	var deck := Cards.create_deck()
	var ids := {}
	for c in deck:
		ids[c["id"]] = true
	check(deck.size() == 52 and ids.size() == 52, "52 unique cards")


func test_points() -> void:
	check(Cards.hand_points(cards("AS 7H KD")) == 18, "A=1, 7=7, K=10")


func test_sets() -> void:
	check(Cards.is_set(cards("7S 7H 7D")), "three sevens")
	check(Cards.is_set(cards("7S 7H 7D 7C")), "four sevens")
	check(not Cards.is_set(cards("7S 7H")), "two is not a set")
	check(not Cards.is_set(cards("7S 7H 8D")), "mixed ranks")


func test_runs() -> void:
	check(Cards.is_run(cards("AS 2S 3S")), "ace low run")
	check(Cards.is_run(cards("9H JH 10H QH")), "unsorted run")
	check(not Cards.is_run(cards("QS KS AS")), "ace is not high")
	check(not Cards.is_run(cards("4S 5H 6S")), "mixed suits")
	check(not Cards.is_run(cards("4S 6S 7S")), "gap")


func test_lay_off() -> void:
	var run := {"type": "run", "cards": cards("4D 5D 6D")}
	check(Cards.can_lay_off(run, cards("7D")), "extend run up")
	check(Cards.can_lay_off(run, cards("3D")), "extend run down")
	check(not Cards.can_lay_off(run, cards("8D")), "gap on run")
	var trio := {"type": "set", "cards": cards("9S 9H 9D")}
	check(Cards.can_lay_off(trio, cards("9C")), "fourth of a kind")
	check(not Cards.can_lay_off(trio, cards("10C")), "wrong rank")


func test_best_partition() -> void:
	var best := Cards.best_partition(cards("5S 6S 7S 7H 7D 7C KD 2C"))
	check(best["points"] == 12, "deadwood is K + 2 (got %d)" % best["points"])
	check(best["melds"].size() == 2, "two melds")


# ------------------------------------------------------------------ trump

func test_trump_rotation() -> void:
	check(Game.trump_for_round(1) == 1, "round 1: aces")
	check(Game.trump_for_round(2) == 2, "round 2: twos")
	check(Game.trump_for_round(13) == 13, "round 13: kings")
	check(Game.trump_for_round(14) == 1, "round 14: back to aces")
	var g := new_game(2)
	check(g.trump_rank == 1, "first round's trump is aces")
	g.phase = "round_over"
	g.start_round()
	check(g.trump_rank == 2, "next round's trump is twos")


func test_trump_runs() -> void:
	check(Cards.is_run(cards("2C 3C AC 5C"), 1), "2 3 A 5 of clubs: the ace is the 4")
	check(Cards.is_run(cards("2C 3C AD 5C"), 1), "the trump can be any suit")
	check(Cards.is_run(cards("2C AH 5C AS"), 1), "two trumps fill two gaps")
	check(Cards.is_run(cards("JC QC AD"), 1), "a spare trump extends the end")
	check(not Cards.is_run(cards("2C 5C AD"), 1), "one trump can't fill two gaps")
	check(not Cards.is_run(cards("2C 3H AD"), 1), "naturals still need one suit")
	check(not Cards.is_run(cards("2C 3C AD 5C"), 0), "no trump, no run")
	var shown := Cards.ids_of(Cards.sorted_meld(cards("5C AD 2C 3C"), "run", 1))
	check(shown == ["2C", "3C", "AD", "5C"], "the trump is shown in its gap (got %s)" % [shown])


func test_trump_sets() -> void:
	check(Cards.is_set(cards("7S 7H 2D"), 2), "two sevens and a trump")
	check(Cards.is_set(cards("7S 2H 2D"), 2), "one seven and two trumps")
	check(not Cards.is_set(cards("7S 7S 2D"), 2), "no duplicate suits")
	check(not Cards.is_set(cards("7S 7H 7D 7C 2D"), 2), "a set is still at most 4")
	check(Cards.meld_type(cards("7S 2H 2D"), 2) == "any", "7 + two trumps could be a set or a run")


func test_trump_lay_off() -> void:
	var run := {"type": "run", "cards": cards("4D 5D 6D")}
	check(Cards.can_lay_off(run, cards("KS"), 13), "lay a trump on a run")
	var either := {"type": "any", "cards": cards("7S 2H 2D")}
	check(Cards.lay_off_type(either, cards("8S"), 2) == "run", "an 8 of spades makes it a run")
	check(Cards.lay_off_type(either, cards("7H"), 2) == "set", "a 7 of hearts makes it a set")


func test_trump_in_game() -> void:
	var g := new_game(2)
	past_first_turn(g)
	g.players[0].hand = cards("2C 3C AD 5C 9H 9S")
	g.stock.append(Cards.parse("KH"))
	g.draw_stock(0)
	var r := g.meld(0, ["2C", "3C", "AD", "5C"])
	check(r["ok"], "meld 2 3 A 5 of clubs in round 1")
	check(r["ok"] and r["meld"]["type"] == "run", "it's a run")
	check(g.lay_off(0, ["9H"], r["meld"]["id"])["ok"] == false, "9H doesn't fit")


func test_trump_partition() -> void:
	var best := Cards.best_partition(cards("2C 3C AD 5C KH"), 1)
	check(best["points"] == 10, "only the king is deadwood (got %d)" % best["points"])


func test_go_out_check() -> void:
	var g := new_game(2)
	past_first_turn(g)
	g.players[0].hand = cards("2C 3C 4C")
	g.stock.append(Cards.parse("KH"))
	g.draw_stock(0)
	var chk := g.go_out_check(0)
	check(chk["can"], "meld 2 3 4 and discard the king")
	check(chk["rummy"], "and it's rummy: nothing melded before")
	g.players[0].hand = cards("2C 3C 4C KH QS")
	check(not g.go_out_check(0)["can"], "two loose cards: can't go out")


func test_no_placing_first_turn() -> void:
	var g := new_game(2)
	g.players[0].hand = cards("2C 3C 4C 9H")
	g.stock.append(Cards.parse("KH"))
	g.draw_stock(0)
	check(not g.can_place(0), "first turn: no placing")
	check(not g.meld(0, ["2C", "3C", "4C"])["ok"], "can't meld on your first turn")
	check(not g.go_out_check(0)["can"], "so you can't go out either")
	check(g.discard(0, "KH")["ok"], "but you can discard")
	g.players[1].hand.append(Cards.parse("QS"))
	g.stock.append(Cards.parse("JS"))
	g.draw_stock(1)
	g.discard(1, "JS")
	g.stock.append(Cards.parse("5C"))
	g.draw_stock(0)
	check(g.can_place(0), "second turn: placing allowed")
	check(g.meld(0, ["2C", "3C", "4C"])["ok"], "now you can meld")


func test_trump_swap() -> void:
	# round 1, aces are trump; the table has 2C 3C [A] 5C with the ace as the 4
	var g := new_game(2)
	past_first_turn(g)
	g.melds.append({"id": "mx", "type": "run", "cards": cards("2C 3C AD 5C"), "owner": 1})
	g.players[0].hand = cards("4C 9H 9S KD")
	g.stock.append(Cards.parse("QD"))
	g.draw_stock(0)
	var found := g.find_swap(0, "mx", ["4C", "9H", "9S"])
	check(found.get("natural", "") == "4C" and found.get("trump", "") == "AD", "4C swaps for the ace (%s)" % [found])
	check(g.find_swap(0, "mx", ["4C", "9H", "KD"]).is_empty(), "9H KD + ace isn't a meld, so no swap")
	check(g.find_swap(0, "mx", ["4C", "9H"]).is_empty(), "needs 2 cards to meld the ace with")
	check(g.find_swap(0, "mx", ["9H", "9S", "KD"]).is_empty(), "needs the card the ace stands for")
	check(not g.swap_trump(0, "mx", "9H", "AD", ["9S", "KD"])["ok"], "wrong card can't replace the ace")
	var r := g.swap_trump(0, "mx", "4C", "AD", ["9H", "9S"])
	check(r["ok"], "swap: %s" % r.get("error", ""))
	check(Cards.ids_of(g.find_meld("mx")["cards"]) == ["2C", "3C", "4C", "5C"], "the run is natural now")
	check(r["ok"] and Cards.ids_of(r["meld"]["cards"]).has("AD"), "the ace is in your new meld")
	check(Cards.ids_of(g.players[0].hand) == ["KD", "QD"], "4C 9H 9S left your hand")
	# sets work too: 7S 7H [A] and you hold 7D
	g.melds.append({"id": "my", "type": "set", "cards": cards("7S 7H AS"), "owner": 1})
	g.players[0].hand = cards("7D 5H 6H KD")
	check(g.swap_trump(0, "my", "7D", "AS", ["5H", "6H"])["ok"], "swap into a set; ace makes 5 6 A of hearts")


# ------------------------------------------------------------------ table

func test_deal() -> void:
	var g := new_game(4)
	for p in g.players:
		check(p.hand.size() == 7, "7 cards each")
		check(p.items.size() == 2, "2 items each")
	var playing := 0
	var items := 0
	for c in g.stock:
		if c.has("item"):
			items += 1
		else:
			playing += 1
	check(playing == 52 - 28 - 1, "the rest of the playing cards are the stock")
	check(items == Items.create_item_deck().size() - 8, "leftover items are shuffled into the stock")
	check(not g.top_discard().has("item"), "the discard pile starts with a playing card")


func test_drawing_an_item() -> void:
	var g := new_game(2)
	var card := Cards.parse("KD")
	var saw := {"id": "I-saw-99", "item": "saw"}
	g.stock.append(card)
	g.stock.append(saw)
	var hand_before: int = g.players[0].hand.size()
	var r := g.draw_stock(0)
	check(r["ok"] and r["item"], "drew an item")
	check(g.players[0].items.has(saw), "it goes with your items")
	check(g.phase == "draw", "and you draw again")
	r = g.draw_stock(0)
	check(r["ok"] and not r["item"] and r["card"] == card, "then a playing card")
	check(g.players[0].hand.size() == hand_before + 1, "which goes in your hand")
	check(g.phase == "play", "then you discard to end the turn")
	# after an item you may take the discard pile instead
	g = new_game(2)
	g.stock.append({"id": "I-beer-99", "item": "beer"})
	g.draw_stock(0)
	var top: Dictionary = g.top_discard()
	r = g.draw_discard(0)
	check(r["ok"] and r["card"] == top, "second draw from the discard pile")


func test_beer_can_burn_an_item() -> void:
	var g := new_game(2)
	g.stock.append({"id": "I-saw-99", "item": "saw"})
	var r := g.use_item(0, _give_item(g, 0, "beer"))
	check(r["ok"] and r["reveal"]["item"] == "saw", "burned the saw")
	check(str(r["text"]).contains("Hand Saw"), "log names the item")


func test_dealer_rotation() -> void:
	var g := new_game(3)
	check(g.dealer == 2 and g.turn == 0, "round 1: seat 3 deals, seat 1 starts")
	g.phase = "round_over"
	g.start_round()
	check(g.dealer == 1 and g.turn == 2, "round 2: deal moves right, last dealer starts")
	g.phase = "round_over"
	g.start_round()
	check(g.dealer == 0 and g.turn == 1, "round 3")
	g.phase = "round_over"
	g.start_round()
	check(g.dealer == 2 and g.turn == 0, "round 4 wraps around")


func test_turn_guards() -> void:
	var g := new_game(2)
	check(not g.draw_stock(1)["ok"], "can't draw out of turn")
	check(not g.discard(0, g.players[0].hand[0]["id"])["ok"], "must draw first")
	g.stock.append(Cards.parse("KD"))
	check(g.draw_stock(0)["ok"], "draw")
	check(not g.draw_stock(0)["ok"], "only one draw once you have a playing card")


func test_discard_pickup_rule() -> void:
	var g := new_game(2, 2)
	var top: Dictionary = g.top_discard()
	g.draw_discard(0)
	check(not g.discard(0, top["id"])["ok"], "can't discard what you picked up")
	var other: Dictionary = g.players[0].hand[0]
	check(g.discard(0, other["id"])["ok"], "discard something else")
	check(g.turn == 1, "turn passes left")


func _give_item(g: Game, seat: int, item_id: String, n: int = 9) -> String:
	var id := "I-%s-%d" % [item_id, n]
	g.players[seat].items.append({"id": id, "item": item_id})
	return id


func test_many_items_per_turn() -> void:
	var g := new_game(2)
	g.players[0].hp = 2
	var a := _give_item(g, 0, "cigarettes", 8)
	var b := _give_item(g, 0, "cigarettes", 9)
	check(g.use_item(0, a)["ok"], "use before drawing")
	check(g.use_item(0, b)["ok"], "and another")
	check(g.players[0].hp == 4, "+2 health")
	check(g.phase == "draw", "still need to draw")
	draw_playing_card(g, 0)
	check(g.use_item(0, _give_item(g, 0, "magnifier"))["ok"], "and after drawing")


func test_handcuffs() -> void:
	var g := new_game(3)
	var cuffs := _give_item(g, 0, "handcuffs")
	check(not g.use_item(0, cuffs)["ok"], "handcuffs need a target")
	check(g.use_item(0, cuffs, 1)["ok"], "cuff seat 2")
	draw_playing_card(g, 0)
	g.discard(0, g.players[0].hand[0]["id"])
	check(g.turn == 2, "seat 2 is skipped")
	check(not g.players[1].cuffed, "cuffs come off")


func test_items_need_targets() -> void:
	var g := new_game(2)
	var cigs := _give_item(g, 0, "cigarettes")
	check(g.item_blocker(0, cigs) != "", "no cigarettes at full health")
	var phone := _give_item(g, 0, "phone")
	check(g.item_blocker(0, phone, 0) != "", "can't call yourself")
	var r := g.use_item(0, phone, 1)
	check(r["ok"] and r["private"], "phone reveals privately")
	check(g.players[1].hand.has(r["reveal"]), "revealed card is theirs")


func test_magnifier_and_beer() -> void:
	var g := new_game(2)
	var top: Dictionary = g.stock.back()
	var r := g.use_item(0, _give_item(g, 0, "magnifier"))
	check(r["reveal"] == top and r["private"], "magnifier peeks privately")
	r = g.use_item(0, _give_item(g, 0, "beer"))
	check(r["reveal"] == top and not r["private"], "beer burns it publicly")
	check(g.stock.back() != top, "it's gone")


func test_adrenaline() -> void:
	var g := new_game(2)
	var before: int = g.players[1].items.size()
	var r := g.use_item(0, _give_item(g, 0, "adrenaline"), 1)
	check(r["ok"], "steal")
	check(g.players[1].items.size() == before - 1, "they lost an item")
	check(g.players[0].items.has(r["reveal"]), "you got it")


func test_going_out_scores_everyone() -> void:
	var g := new_game(3)
	past_first_turn(g)
	g.players[0].hand = cards("2S 3S 4S")
	g.players[1].hand = cards("KH 5C")
	g.players[2].hand = cards("QD")
	g.stock.append(Cards.parse("JD"))
	g.draw_stock(0)
	g.meld(0, ["2S", "3S", "4S"])
	g.discard(0, "JD")
	var r := g.last_result
	check(r["winner"] == 0, "seat 1 wins")
	check(r["rummy"], "went out in one turn")
	check(r["points"] == 50, "(15 + 10) x 2 = 50, got %d" % r["points"])
	check(r["shells"] == 3, "shells capped at 3")
	check(g.phase == "shoot" and g.gun["holder"] == 0, "winner holds the gun")


func test_shotgun_and_elimination() -> void:
	var g := new_game(3)
	g.phase = "shoot"
	g.gun = {"holder": 0, "shells": 3, "total": 3}
	g.players[0].sawed = true
	check(not g.shoot(1, 2)["ok"], "not their gun")
	check(not g.shoot(0, 0)["ok"], "no shooting yourself")
	check(g.shoot(0, 2)["damage"] == 2, "saw doubles the first shell")
	g.shoot(0, 2)
	g.shoot(0, 2)
	check(not g.players[2].alive, "seat 3 is out")
	check(g.phase == "round_over", "gun empty")
	g.start_round()
	check(g.players[2].hand.is_empty(), "eliminated players aren't dealt in")
	draw_playing_card(g, g.turn)
	var seat := g.turn
	g.discard(seat, g.players[seat].hand[0]["id"])
	check(g.players[g.turn].alive, "turns skip eliminated players")
	g.damage(1, 4)
	check(g.phase == "match_over" and g.winner == 0, "last one standing wins")


func test_bot_matches() -> void:
	for n in range(2, 7):
		for s in range(1, 11):
			var g := new_game(n, s * 31 + n)
			var turns := 0
			while g.phase != "match_over" and turns < 20000:
				turns += 1
				if g.phase == "round_over":
					g.start_round()
				elif g.phase == "shoot":
					g.shoot(g.gun["holder"], Bot.choose_target(g, g.gun["holder"]))
				else:
					Bot.play_turn(g)
					if g.phase == "draw" or g.phase == "play":
						var total: int = g.discard_pile.size()
						for c in g.stock + g.burned:
							if not c.has("item"):
								total += 1
						for m in g.melds:
							total += m["cards"].size()
						for p in g.players:
							total += p.hand.size()
						if total != 52:
							check(false, "%d players seed %d: %d cards in play" % [n, s, total])
							return
			check(g.phase == "match_over", "%d players seed %d finishes" % [n, s])
			check(g.alive_count() == 1, "one survivor")
