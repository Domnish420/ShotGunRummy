extends SceneTree
## Rules tests. Run from the project folder:
##   godot --headless --path . -s tests/test_runner.gd

const Cards = preload("res://scripts/core/cards.gd")
const Game = preload("res://scripts/core/game.gd")
const Bot = preload("res://scripts/core/bot.gd")

var _failures := 0
var _checks := 0
var _test := ""


func _init() -> void:
	for t in [
		"test_deck", "test_points", "test_sets", "test_runs", "test_lay_off", "test_best_partition",
		"test_deal", "test_dealer_rotation", "test_turn_guards", "test_discard_pickup_rule",
		"test_one_item_per_turn", "test_handcuffs", "test_items_need_targets", "test_magnifier_and_beer",
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


# ------------------------------------------------------------------ table

func test_deal() -> void:
	var g := new_game(4)
	for p in g.players:
		check(p.hand.size() == 7, "7 cards each")
		check(p.items.size() == 2, "2 items each")
	check(g.stock.size() == 52 - 28 - 1, "rest is the stock")


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
	check(g.draw_stock(0)["ok"], "draw")
	check(not g.draw_stock(0)["ok"], "only one draw")


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


func test_one_item_per_turn() -> void:
	var g := new_game(2)
	g.players[0].hp = 2
	var a := _give_item(g, 0, "cigarettes", 8)
	var b := _give_item(g, 0, "cigarettes", 9)
	check(g.use_item(0, a)["ok"], "use before drawing")
	check(g.players[0].hp == 3, "+1 health")
	check(not g.use_item(0, b)["ok"], "second item is blocked")
	check(g.phase == "draw", "still need to draw")


func test_handcuffs() -> void:
	var g := new_game(3)
	var cuffs := _give_item(g, 0, "handcuffs")
	check(not g.use_item(0, cuffs)["ok"], "handcuffs need a target")
	check(g.use_item(0, cuffs, 1)["ok"], "cuff seat 2")
	g.draw_stock(0)
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
	g.items_used_this_turn = 0
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
	g.draw_stock(g.turn)
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
						var total: int = g.stock.size() + g.discard_pile.size() + g.burned.size()
						for m in g.melds:
							total += m["cards"].size()
						for p in g.players:
							total += p.hand.size()
						if total != 52:
							check(false, "%d players seed %d: %d cards in play" % [n, s, total])
							return
			check(g.phase == "match_over", "%d players seed %d finishes" % [n, s])
			check(g.alive_count() == 1, "one survivor")
