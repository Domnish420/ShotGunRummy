extends SceneTree
## Rules tests. Run from the project folder:
##   godot --headless --path . -s tests/test_runner.gd

const Cards = preload("res://scripts/core/cards.gd")
const Game = preload("res://scripts/core/game.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Items = preload("res://scripts/core/items.gd")
const Looks = preload("res://scripts/core/looks.gd")
const Session = preload("res://scripts/net/session.gd")
const Blackjack = preload("res://scripts/core/blackjack.gd")
const GoFish = preload("res://scripts/core/gofish.gd")
const Cheat = preload("res://scripts/core/cheat.gd")
const Hearts = preload("res://scripts/core/hearts.gd")
const Spades = preload("res://scripts/core/spades.gd")
const Snap = preload("res://scripts/core/snap.gd")
const President = preload("res://scripts/core/president.gd")
const Poker = preload("res://scripts/core/poker.gd")
const Games = preload("res://scripts/core/games.gd")

var _failures := 0
var _checks := 0
var _test := ""


func _init() -> void:
	for t in [
		"test_deck", "test_points", "test_trump_rotation", "test_trump_runs", "test_trump_sets",
		"test_trump_lay_off", "test_trump_in_game", "test_trump_partition", "test_go_out_check", "test_no_placing_first_turn", "test_trump_swap", "test_no_discarding_trumps",
		"test_sticky_fingers", "test_tarot", "test_joker_paint", "test_shakedown", "test_switcheroo",
		"test_bad_trade", "test_chaos", "test_dumpster_dive", "test_garbage_day",
		"test_spotlight", "test_flashbang", "test_revolver", "test_double_down",
		"test_looks", "test_sets", "test_runs", "test_lay_off", "test_best_partition",
		"test_deal", "test_drawing_an_item", "test_beer_can_burn_an_item", "test_dealer_rotation", "test_turn_guards", "test_discard_pickup_rule",
		"test_many_items_per_turn", "test_handcuffs", "test_items_need_targets", "test_magnifier_and_beer",
		"test_adrenaline", "test_going_out_scores_everyone", "test_shotgun_and_elimination",
		"test_bot_matches", "test_ai_levels",
		"test_bj_totals", "test_bj_deal", "test_bj_turns", "test_bj_winner", "test_bj_blackjack_shot", "test_bj_items", "test_bj_ai_matches",
		"test_gf_ask", "test_gf_books", "test_gf_ai_matches",
		"test_ch_play", "test_ch_call", "test_ch_empty_pile", "test_hearts", "test_spades", "test_snap", "test_president", "test_poker_hands", "test_poker_betting", "test_blank_shell", "test_trumps_only_rummy", "test_normal_mode", "test_ai_all_games",
	]:
		var only := OS.get_cmdline_user_args() # -- test_name runs just that one
		if not only.is_empty() and not only.has(t):
			continue
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


func test_no_discarding_trumps() -> void:
	var g := new_game(2)
	g.players[0].hand = cards("AS 7H 9C")
	g.stock.append(Cards.parse("KD"))
	g.draw_stock(0)
	check(not g.can_discard(0, "AS"), "aces are trump in round 1: can't discard")
	check(not g.discard(0, "AS")["ok"], "discard refused")
	check(g.discard(0, "KD")["ok"], "other cards are fine")
	# holding nothing but trumps, you're allowed to
	g.players[1].hand = cards("AH AD")
	g.stock.append(Cards.parse("AC"))
	g.draw_stock(1)
	check(g.can_discard(1, "AH"), "all trumps: discarding one is allowed")


func test_sticky_fingers() -> void:
	var g := new_game(2)
	g.melds.append({"id": "mr", "type": "run", "cards": cards("4C 5C 6C 7C"), "owner": 1})
	g.melds.append({"id": "ms", "type": "set", "cards": cards("9S 9H 9D"), "owner": 1})
	var id := _give_item(g, 0, "sticky_fingers")
	var choices := g.item_choices(0, "sticky_fingers")
	check(choices.has("4C") and choices.has("7C"), "run ends can be stolen")
	check(not choices.has("5C"), "the middle of a run can't (it would break it)")
	check(choices.has("9H"), "any card from a set of 3")
	var r := g.use_item(0, id, -1, "7C")
	check(r["ok"] and g.players[0].hand.has(r["reveal"]), "stolen card is in your hand")
	check(Cards.ids_of(g.find_meld("mr")["cards"]) == ["4C", "5C", "6C"], "run is now 4 5 6")
	var pile_before: int = g.discard_pile.size()
	g.use_item(0, _give_item(g, 0, "sticky_fingers", 8), -1, "9H")
	check(g.find_meld("ms").is_empty(), "set down to 2 cards is gone")
	check(g.discard_pile.size() == pile_before + 2, "its 2 cards went to the discard pile")


func test_tarot() -> void:
	var g := new_game(2)
	g.melds.append({"id": "mx", "type": "run", "cards": cards("2C 3C AD"), "owner": 1})
	g.players[0].hand = cards("AS 2H 9C")
	check(g.trump_rank == 1, "aces to start")
	check(g.use_item(0, _give_item(g, 0, "tarot"))["ok"], "turn the tarot card")
	check(g.trump_rank == 2, "twos are trump now")
	check(Cards.is_wild(g.find_meld("mx")["cards"][2], g.trump_rank), "the ace in the meld stays wild")
	check(not g.is_trump(g.players[0].hand[0]), "the ace in your hand isn't any more")
	check(g.is_trump(g.players[0].hand[1]), "the 2 in your hand is")
	g.trump_rank = 13
	g.use_item(0, _give_item(g, 0, "tarot", 8))
	check(g.trump_rank == 1, "kings wrap round to aces")


func test_joker_paint() -> void:
	var g := new_game(2)
	past_first_turn(g)
	g.players[0].hand = cards("7H 8H KS QD")
	g.stock.append(Cards.parse("2S"))
	g.draw_stock(0)
	check(g.use_item(0, _give_item(g, 0, "joker_paint"), -1, "KS")["ok"], "paint the king")
	check(g.is_trump(g.players[0].hand[2]), "the king is wild")
	check(g.meld(0, ["7H", "8H", "KS"])["ok"], "7 8 K(wild) of hearts is a run")
	check(g.discard(0, "QD")["ok"], "end the turn")
	check(Cards.is_wild(g.melds[0]["cards"][2], g.trump_rank), "it stays wild in the meld")
	# painted but not melded: wears off
	var g2 := new_game(2)
	g2.players[0].hand = cards("KS 9D")
	g2.use_item(0, _give_item(g2, 0, "joker_paint"), -1, "KS")
	draw_playing_card(g2, 0)
	g2.discard(0, "9D")
	check(not g2.players[0].hand[0].get("wild", false), "wears off at the end of the turn")


func test_shakedown() -> void:
	var g := new_game(2)
	g.players[1].hand = cards("AS 9H")
	var before: int = g.discard_pile.size()
	var r := g.use_item(0, _give_item(g, 0, "shakedown"), 1)
	check(r["ok"] and Cards.ids_of(g.players[1].hand) == ["AS"], "they drop the non-trump (aces are trump)")
	check(g.discard_pile.size() == before + 1 and g.top_discard()["id"] == "9H", "onto the discard pile")
	check(g.item_targets(0, "shakedown").is_empty(), "can't take someone's last card")


func test_switcheroo() -> void:
	var g := new_game(2)
	g.players[0].hand = cards("2S 3S")
	g.players[1].hand = cards("KH QH JH")
	g.use_item(0, _give_item(g, 0, "switcheroo"), 1)
	check(Cards.ids_of(g.players[0].hand) == ["KH", "QH", "JH"], "you have their hand")
	check(Cards.ids_of(g.players[1].hand) == ["2S", "3S"], "they have yours")


func test_bad_trade() -> void:
	var g := new_game(2)
	g.players[0].hand = cards("2S 3S 4S")
	g.players[1].hand = cards("KH QH JH")
	g.use_item(0, _give_item(g, 0, "bad_trade"), 1)
	var hearts := 0
	for c in g.players[0].hand:
		if c["suit"] == "H":
			hearts += 1
	check(hearts == 2 and g.players[0].hand.size() == 3, "2 of their cards for 2 of yours")


func test_chaos() -> void:
	var g := new_game(3)
	g.players[0].hand = cards("2S")
	g.players[1].hand = cards("3H")
	g.players[2].hand = cards("4D")
	g.use_item(0, _give_item(g, 0, "chaos"))
	check(Cards.ids_of(g.players[1].hand) == ["2S"], "seat 1's card went left to seat 2")
	check(Cards.ids_of(g.players[0].hand) == ["4D"], "and the last seat's came round to seat 1")


func test_dumpster_dive() -> void:
	var g := new_game(2)
	g.discard_pile = cards("2S 3S 4S 5S")
	var before: int = g.players[0].hand.size()
	g.use_item(0, _give_item(g, 0, "dumpster_dive"))
	check(g.players[0].hand.size() == before + 3, "took 3")
	check(Cards.ids_of(g.discard_pile) == ["2S"], "the bottom one is left")


func test_garbage_day() -> void:
	var g := new_game(2)
	g.discard_pile = cards("2S 3S 4S 5S")
	var before: int = g.players[1].hand.size()
	g.use_item(0, _give_item(g, 0, "garbage_day"), 1)
	check(g.players[1].hand.size() == before + 4, "they took the lot")
	check(g.discard_pile.is_empty(), "pile is empty")
	check(g.item_blocker(0, _give_item(g, 0, "garbage_day", 8)) != "", "can't use it on an empty pile")


func test_spotlight() -> void:
	var g := new_game(2)
	g.use_item(0, _give_item(g, 0, "spotlight"), 1)
	check(g.players[1].exposed, "their hand is on show")
	var view := g.snapshot(0)
	check(not view["players"][1]["hand"][0].get("hidden", false), "and visible to everyone else")
	draw_playing_card(g, 0)
	g.discard(0, g.players[0].hand[0]["id"])
	check(g.players[1].exposed, "still on show during their turn")
	draw_playing_card(g, 1)
	g.discard(1, g.players[1].hand[0]["id"])
	check(not g.players[1].exposed, "hidden again once their turn ends")


func test_flashbang() -> void:
	var g := new_game(3)
	g.use_item(0, _give_item(g, 0, "flashbang"))
	for seat in [1, 2]:
		var shown := 0
		for c in g.snapshot(0)["players"][seat]["hand"]:
			if not c.get("hidden", false):
				shown += 1
		check(shown == 2, "seat %d shows exactly 2 cards (%d)" % [seat + 1, shown])
	var mine := 0
	for c in g.players[0].hand:
		if c.get("shown", false):
			mine += 1
	check(mine == 0, "yours stay hidden")


func test_revolver() -> void:
	var g := new_game(2, 7)
	past_first_turn(g)
	g.options["roulette_chambers"] = 1 # always the live round, for the test
	g.use_item(0, _give_item(g, 0, "revolver"), 1)
	check(g.players[1].ultimatum, "seat 2 has the revolver")
	draw_playing_card(g, 0)
	g.discard(0, g.players[0].hand[0]["id"])
	# seat 2 puts nothing down
	draw_playing_card(g, 1)
	g.discard(1, g.players[1].hand[0]["id"])
	check(g.players[1].hp == 2, "bang: 4 - 2 = 2 health (got %d)" % g.players[1].hp)
	check(not g.players[1].ultimatum, "only for that one turn")
	# putting cards down means no roulette
	g.use_item(0, _give_item(g, 0, "revolver", 8), 1)
	draw_playing_card(g, 0)
	g.discard(0, g.players[0].hand[0]["id"])
	g.players[1].hand = cards("5H 6H 7H KD")
	g.stock.append(Cards.parse("QS"))
	g.draw_stock(1)
	g.meld(1, ["5H", "6H", "7H"])
	g.discard(1, "QS")
	check(g.players[1].hp == 2, "melded, so no roulette")


func test_double_down() -> void:
	var g := new_game(2)
	g.use_item(0, _give_item(g, 0, "double_down"), 1)
	draw_playing_card(g, 0)
	g.discard(0, g.players[0].hand[0]["id"])
	var before: int = g.players[1].hand.size()
	g.stock.append(Cards.parse("KD"))
	var r := g.draw_stock(1)
	check(r["again"] and g.phase == "draw", "after one card they must draw again")
	var r2 := g.draw_discard(1)
	check(r2["ok"] and not r2["again"] and g.phase == "play", "second card from the discard pile, then play")
	check(g.players[1].hand.size() == before + 2, "2 cards drawn")


func test_looks() -> void:
	check(Looks.PRESETS.size() >= 15, "plenty of ready-made characters")
	for p in Looks.PRESETS:
		var clean := Looks.clean(p)
		check(clean["base"] == p["base"] and clean["hat"] == p["hat"], "%s survives cleaning" % p["name"])
	var junk := Looks.clean({"base": "Dragon", "hat": "crown", "outfit": 99, "face": "mask"}, 2)
	check(Looks.BASES.has(junk["base"]) and Looks.HATS.has(junk["hat"]) and Looks.FACES.has(junk["face"]), "junk from the network becomes a real look")
	check(int(junk["outfit"]) < Looks.OUTFITS.size(), "outfit index stays in range")
	var g := new_game(2)
	g.players[1].look = Looks.preset(2)
	var view := g.snapshot(0)
	check(view["players"][1]["look"]["name"] == "THE UNDERTAKER", "looks travel in snapshots")
	var mirror := Game.new()
	mirror.load_snapshot(view)
	check(mirror.players[1].look["hat"] == "top_hat", "and load back")


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


## Easy, normal and hard AIs play whole matches one move at a time, the way
## the table drives them, and every move they pick is legal.
func test_ai_levels() -> void:
	var wins := {"easy": 0, "normal": 0, "hard": 0}
	for s in range(1, 13):
		var n := 3 + s % 2
		var g := new_game(n, s * 17)
		for i in range(n):
			g.players[i].bot = Bot.LEVELS[(i + s) % 3]
		var memories := {}
		var steps := 0
		var refused := 0
		while g.phase != "match_over" and steps < 30000:
			steps += 1
			if g.phase == "round_over":
				g.start_round()
				continue
			var seat: int = g.gun["holder"] if g.phase == "shoot" else g.turn
			var mem: Dictionary = memories.get_or_add(seat, {})
			var act := Bot.next_action(g, seat, g.players[seat].bot, mem)
			if act.is_empty():
				check(false, "seed %d: the AI had no move in phase %s" % [s, g.phase])
				return
			var res := Session.perform(g, seat, act[0], act[1], true)
			if not res["ok"]:
				refused += 1
				Bot.note_failure(mem, act)
		check(g.phase == "match_over", "seed %d: AI match finishes (round %d, phase %s, hp %s)" % [s, g.round_num, g.phase, g.players.map(func(p): return p.hp)])
		check(refused < 20, "seed %d: AI moves are legal (%d refused)" % [s, refused])
		if g.winner >= 0:
			wins[g.players[g.winner].bot] += 1
	print("  AI wins by level: %s" % [wins])


# ================================================================ blackjack

func new_bj(n: int = 3, rng_seed: int = 1) -> Blackjack:
	var names := []
	for i in range(n):
		names.append("P%d" % (i + 1))
	var g := Blackjack.new()
	g.setup(names, {}, rng_seed)
	g.start_round()
	return g


func test_bj_totals() -> void:
	check(Blackjack.total(cards("KH 7C"), 0) == 17, "K 7 is 17")
	check(Blackjack.total(cards("AH KC"), 0) == 21, "A K is 21")
	check(Blackjack.total(cards("AH AC 9D"), 0) == 21, "A A 9 is 21")
	check(Blackjack.total(cards("AH 9C 5D"), 0) == 15, "an ace drops to 1")
	check(Blackjack.total(cards("KH QC 5D"), 0) == 25, "bust is bust")
	check(Blackjack.total(cards("7H 3C"), 7) == 14, "a trump 7 tops up to 11: 11 + 3")
	check(Blackjack.total(cards("7H KC"), 7) == 21, "a trump makes 21")
	check(Blackjack.total(cards("7H KC 9D"), 7) == 21, "a trump is worth exactly what you need (2 here)")
	check(Blackjack.total(cards("7H KC 9D 5S"), 7) == 25, "even a trump at 1 can't save that")
	check(Blackjack.total(cards("2H"), 2) == 11, "a trump alone is worth 11")


func test_bj_deal() -> void:
	var g := new_bj(4, 3)
	check(g.kind == "blackjack" and g.phase == "play", "blackjack starts on someone's turn")
	check(g.turn == g.next_alive(g.dealer), "left of the dealer goes first")
	for p in g.players:
		check(p.hand.size() == 2 and p.items.size() == 2, "2 cards and 2 items each")
		check(not p.hand[0].get("shown", false) and p.hand[1].get("shown", false), "one down, one up")
	# what others see
	var snap := g.snapshot(0)
	var other: Array = snap["players"][1]["hand"]
	check(other[0].get("hidden", false) and not other[1].get("hidden", false), "you see their face-up card, not the face-down one")
	var deck_items := 0
	for c in g.stock:
		if c.has("item"):
			deck_items += 1
	for c in g.stock:
		check(not (c.has("item") and c["item"] == "garbage_day"), "no Garbage Day in blackjack")


func test_bj_turns() -> void:
	var g := new_bj(3, 5)
	var first := g.turn
	var p = g.players[first]
	p.hand = cards("KH 5C")
	p.hand[1]["shown"] = true
	g.stock.append(cards("9D")[0])
	var res := g.hit(first)
	check(res["ok"] and res["bust"], "K 5 9 goes bust")
	check(p.bust and g.turn != first, "bust ends the turn")
	var second := g.turn
	g.players[second].hand = cards("10H 6C")
	g.stock.append(cards("5D")[0])
	g.hit(second)
	check(g.players[second].stood and g.turn != second, "21 stands by itself")
	var third := g.turn
	g.stock.append({"id": "I-beer-9", "item": "beer"})
	var before: int = g.players[third].items.size()
	var stock_before: int = g.stock.size()
	g.hit(third)
	check(g.players[third].items.size() == before + 1, "an item off the stock is kept")
	check(g.stock.size() == stock_before - 2 or g.players[third].bust or g.players[third].stood, "and you draw again")
	if g.phase == "play":
		g.stand(g.turn)
	check(g.phase == "shoot" or g.phase == "round_over", "the round ends after the dealer")


## Sets the hands for a 3-player round in turn order (the dealer last) and
## has everyone stand.
func _bj_round(rng_seed: int, hands: Array) -> Blackjack:
	var g := new_bj(hands.size(), rng_seed)
	var order := []
	var s := g.turn
	for i in range(hands.size()):
		order.append(s)
		s = g.next_alive(s)
	check(order[-1] == g.dealer, "the dealer plays last")
	for i in range(hands.size()):
		g.players[order[i]].hand = cards(hands[i])
	for i in range(hands.size()):
		if g.phase == "play":
			g.stand(g.turn)
	return g


func test_bj_winner() -> void:
	# 19 beats the dealer's 18 (safe); 17 loses and can be shot
	var g := _bj_round(7, ["10H 9C", "10S 7D", "10C 8H"])
	var first: int = g.next_alive(g.dealer)
	var second: int = g.next_alive(first)
	var duels: Array = g.last_result["duels"]
	check(duels[0]["outcome"] == "win" and duels[1]["outcome"] == "lose", "each player against the dealer: %s" % [duels])
	check(g.phase == "shoot" and g.gun["holder"] == g.dealer and g.gun["shells"] == 1, "the dealer gets a shell for the loser")
	check(not g.shoot(g.dealer, first)["ok"], "the dealer can't shoot a player who beat them")
	check(g.shoot(g.dealer, second)["ok"], "the dealer shoots the loser")
	check(g.phase == "round_over" and g.gun == null, "then the round is over")
	check(Bot.choose_target(g, g.dealer) >= 0, "choose_target still works out of a round")
	# a push or a win: nobody gets shot
	g = _bj_round(9, ["10H 8C", "9S 9D"])
	check(g.phase == "round_over" and g.last_result["shooters"].is_empty(), "a push: nobody gets shot")
	# the dealer beats everyone: 1 shell for each, aimed only at them
	g = _bj_round(13, ["10H 6C", "10S 7D", "9C 8H", "10D 10C"])
	check(g.gun != null and g.gun["holder"] == g.dealer and g.gun["shells"] == 3 and g.gun["targets"].size() == 3, "the dealer beats 3 players: 3 shells")
	check(Bot.choose_target(g, g.dealer) in g.gun["targets"], "the AI dealer aims at a loser")
	# the dealer goes bust: players still in are safe, a player who busted isn't
	g = new_bj(3, 15)
	var a := g.turn
	g.players[a].hand = cards("10H QC")
	g.stock.append(cards("5D")[0])
	g.hit(a) # bust on 25
	var b := g.turn
	g.players[b].hand = cards("10S 9D")
	g.stand(b)
	g.players[g.dealer].hand = cards("10C 6H")
	g.stock.append(cards("KD")[0])
	g.hit(g.dealer)
	check(g.last_result["dealer_bust"] and g.gun != null and g.gun["targets"] == [a], "dealer bust: only the player who busted can be shot")
	# every player bust: the dealer wins without playing
	g = new_bj(3, 17)
	var x := g.turn
	g.players[x].hand = cards("10H QC")
	g.stock.append(cards("KD")[0])
	g.hit(x)
	var y := g.turn
	g.players[y].hand = cards("10S JC")
	g.stock.append(cards("KS")[0])
	g.hit(y)
	check(g.phase == "shoot" and g.gun["holder"] == g.dealer and g.gun["shells"] == 2, "everyone bust: the dealer gets 2 shells without playing")


## A Blackjack shoots the dealer the moment it's dealt.
func test_bj_blackjack_shot() -> void:
	var shots := 0
	var found := false
	for seed in range(1, 400):
		var g := Blackjack.new()
		g.setup(["A", "B", "C", "D"], {}, seed)
		var kinds := []
		g.event.connect(func(kind, _d): kinds.append(kind))
		g.start_round()
		for k in kinds:
			if k == "blackjack_shot":
				shots += 1
		if kinds.has("blackjack_shot"):
			found = true
			check(g.players[g.dealer].hp < g.players[g.dealer].max_hp, "the dealer took the free shot")
			break
	check(found, "some deal has a Blackjack")
	# by item: Shakedown leaves a player with 2 cards making 21
	var g := new_bj(3, 21)
	var me := g.turn
	var them := g.next_alive(me)
	if them == g.dealer:
		them = g.next_alive(them)
	g.players[them].hand = cards("AH KC 5D")
	var hp: int = g.players[g.dealer].hp
	g.players[me].items = [{"id": "I-shakedown-1", "item": "shakedown"}]
	check(g.use_item(me, "I-shakedown-1", them)["ok"], "shakedown")
	check(g.players[g.dealer].hp == hp - 1, "a Blackjack made by an item shoots the dealer too")


func test_bj_items() -> void:
	var g := new_bj(3, 15)
	var me := g.turn
	var nxt := g.next_alive(me)
	var last := g.next_alive(nxt)
	# handcuffs: the next player stands on what they have
	g.players[me].items = [{"id": "I-handcuffs-1", "item": "handcuffs"}, {"id": "I-double_down-1", "item": "double_down"}, {"id": "I-spotlight-1", "item": "spotlight"}]
	check(g.use_item(me, "I-handcuffs-1", nxt)["ok"], "handcuffs on someone still to play")
	check(g.use_item(me, "I-spotlight-1", last)["ok"], "spotlight")
	check(g.players[last].hand[0].get("shown", false), "spotlight turns the face-down card up")
	g.stand(me)
	check(g.players[nxt].stood and g.turn == last, "cuffed player is skipped")
	# double down on a player who stood
	g.players[last].items = [{"id": "I-double_down-2", "item": "double_down"}]
	g.players[me].hand = cards("10H QC")
	g.stock.append(cards("KD")[0])
	var res := g.use_item(last, "I-double_down-2", me)
	check(res["ok"] and g.players[me].bust, "double down can bust a player who stood")
	# sticky fingers takes a face-up card
	g = new_bj(2, 17)
	me = g.turn
	var them := g.next_alive(me)
	g.players[me].items = [{"id": "I-sticky_fingers-1", "item": "sticky_fingers"}]
	var choices: Array = g.item_choices(me, "sticky_fingers")
	check(choices.size() == 1 and choices[0] == g.players[them].hand[1]["id"], "only the face-up card can be stolen")
	check(g.use_item(me, "I-sticky_fingers-1", -1, choices[0])["ok"] and g.players[me].hand.size() == 3, "stolen into your hand")


## Easy, normal and hard blackjack AIs finish whole matches with legal moves.
func test_bj_ai_matches() -> void:
	var wins := {"easy": 0, "normal": 0, "hard": 0}
	for s in range(1, 13):
		var n := 2 + s % 4
		var g := new_bj(n, s * 23)
		for i in range(n):
			g.players[i].bot = Bot.LEVELS[(i + s) % 3]
		var memories := {}
		var steps := 0
		var refused := 0
		while g.phase != "match_over" and steps < 20000:
			steps += 1
			if g.phase == "round_over":
				g.start_round()
				continue
			var seat: int = g.gun["holder"] if g.phase == "shoot" else g.turn
			var mem: Dictionary = memories.get_or_add(seat, {})
			var act := Bot.next_action(g, seat, g.players[seat].bot, mem)
			if act.is_empty():
				check(false, "seed %d: no move in phase %s" % [s, g.phase])
				return
			var res := Session.perform(g, seat, act[0], act[1], true)
			if not res["ok"]:
				refused += 1
				Bot.note_failure(mem, act)
			if g.phase == "play":
				var count := 0
				for p in g.players:
					for c in p.hand:
						if not c.has("item"):
							count += 1
				for c in g.stock + g.discard_pile + g.burned:
					if not c.has("item"):
						count += 1
				if count != 52:
					check(false, "seed %d: %d cards in play" % [s, count])
					return
		check(g.phase == "match_over", "seed %d: blackjack match finishes (round %d)" % [s, g.round_num])
		check(refused < 20, "seed %d: blackjack AI moves are legal (%d refused)" % [s, refused])
		if g.winner >= 0:
			wins[g.players[g.winner].bot] += 1
	print("  blackjack AI wins by level: %s" % [wins])


# ================================================================ go fish

func new_gf(n: int = 3, rng_seed: int = 1) -> GoFish:
	var names := []
	for i in range(n):
		names.append("P%d" % (i + 1))
	var g := GoFish.new()
	g.setup(names, {}, rng_seed)
	g.start_round()
	return g


func test_gf_ask() -> void:
	var g := new_gf(3, 2)
	check(g.kind == "gofish" and g.phase == "play", "go fish starts on someone's turn")
	for p in g.players:
		check(p.hand.size() + 4 * g.books_of(p.seat).size() == 7, "7 cards each with 3 players")
	var me := g.turn
	var them := g.next_alive(me)
	g.trump_rank = 13
	g.players[me].hand = cards("5H 5C 9D")
	g.players[them].hand = cards("5D 2C")
	var res := g.ask(me, them, 5)
	check(res["ok"] and res["count"] == 1 and g.turn == me, "they hand over their 5 and you go again")
	check(g.known[me].has(5), "everyone knows you have 5s")
	check(not g.ask(me, them, 7)["ok"], "you can't ask for a rank you don't hold")
	# go fish: no luck ends the turn
	g.stock.append(cards("JS")[0])
	res = g.ask(me, them, 9)
	check(res["ok"] and g.turn != me, "go fish without luck ends your turn")
	# lucky fish
	var next := g.turn
	var other := g.next_alive(next)
	g.players[next].hand = cards("8H")
	g.players[other].hand = cards("3D 4D")
	g.stock.append(cards("8C")[0])
	res = g.ask(next, other, 8)
	check(res.get("lucky", false) and g.turn == next, "fish the rank you asked for and you go again")
	# trumps can't be asked for
	g.trump_rank = 8
	check(not g.askable_ranks(next).has(8), "nobody can ask for the trump rank")


func test_gf_books() -> void:
	var g := new_gf(2, 4)
	var me := g.turn
	var them := g.next_alive(me)
	g.trump_rank = 13
	g.melds = []
	g.players[me].hand = cards("7H 7C 7D 2S")
	g.players[them].hand = cards("7S 3C")
	g.ask(me, them, 7)
	check(g.books_of(me).size() == 1 and g.players[me].hand.size() == 1, "four 7s make a book")
	# a trump fills in
	g.players[me].hand = cards("9H 9C 9D KS")
	g._make_books(g.players[me])
	check(g.books_of(me).size() == 2, "three 9s and a trump king make a book")
	# the round: most books wins and takes the shotgun
	g = new_gf(2, 6)
	me = g.turn
	them = g.next_alive(me)
	g.melds = []
	for r in ["2", "3", "4"]:
		g._lay_book(g.players[me], cards("%sH %sC %sD %sS" % [r, r, r, r]), int(r))
	g.stock = []
	g.players[me].hand = cards("10H")
	g.players[them].hand = cards("JC")
	g.ask(me, them, 10)
	check(g.phase == "shoot" and g.gun["holder"] == me and g.gun["shells"] == 3, "3 books ahead: 3 shells (%s)" % [g.phase])


## Every level of Go Fish AI finishes whole matches, cards all accounted for.
func test_gf_ai_matches() -> void:
	var wins := {"easy": 0, "normal": 0, "hard": 0}
	for s in range(1, 11):
		var n := 2 + s % 5
		var g := new_gf(n, s * 29)
		for i in range(n):
			g.players[i].bot = Bot.LEVELS[(i + s) % 3]
		var memories := {}
		var steps := 0
		var refused := 0
		while g.phase != "match_over" and steps < 30000:
			steps += 1
			if g.phase == "round_over":
				g.start_round()
				continue
			var seat: int = g.gun["holder"] if g.phase == "shoot" else g.turn
			var mem: Dictionary = memories.get_or_add(seat, {})
			var act := Bot.next_action(g, seat, g.players[seat].bot, mem)
			if act.is_empty():
				check(false, "seed %d: no go fish move in phase %s" % [s, g.phase])
				return
			var res := Session.perform(g, seat, act[0], act[1], true)
			if not res["ok"]:
				refused += 1
				Bot.note_failure(mem, act)
			if g.phase == "play":
				var count := 0
				for p in g.players:
					for c in p.hand:
						count += 1
				for m in g.melds:
					count += m["cards"].size()
				for c in g.stock + g.burned:
					if not c.has("item"):
						count += 1
				if count != 52:
					check(false, "seed %d: %d cards in play" % [s, count])
					return
		check(g.phase == "match_over", "seed %d: go fish match finishes (round %d)" % [s, g.round_num])
		check(refused < 20, "seed %d: go fish AI moves are legal (%d refused)" % [s, refused])
		if g.winner >= 0:
			wins[g.players[g.winner].bot] += 1
	print("  go fish AI wins by level: %s" % [wins])


## Normal mode: no items, no shotgun, first to 3 round wins.
func test_normal_mode() -> void:
	for kind in Games.kinds():
		var g = Games.make(kind, true)
		g.setup(["A", "B", "C"], {}, 77)
		for p in g.players:
			p.bot = "normal"
		g.start_round()
		for p in g.players:
			check(p.items.is_empty(), "%s normal mode: no items dealt" % kind)
		for c in g.stock:
			check(not c.has("item"), "%s normal mode: no items in the stock" % kind)
		var memories := {}
		var steps := 0
		while g.phase != "match_over" and steps < 40000:
			steps += 1
			check(g.phase != "shoot", "%s normal mode: nobody gets the shotgun" % kind)
			if g.phase == "shoot":
				return
			if g.phase == "round_over":
				g.start_round()
				continue
			if kind == "snap" and g.snap_ready():
				g.snap(g.alive_players()[g.rng.randi_range(0, g.alive_count() - 1)].seat)
				continue
			var mem: Dictionary = memories.get_or_add(g.turn, {})
			var act := Bot.next_action(g, g.turn, "normal", mem)
			if act.is_empty() or not Session.perform(g, g.turn, act[0], act[1], true)["ok"]:
				if not act.is_empty():
					Bot.note_failure(mem, act)
		check(g.phase == "match_over" and g.players[g.winner].rounds_won == 3, "%s normal mode: first to 3 rounds wins" % kind)
		for p in g.players:
			check(p.hp == p.max_hp, "%s normal mode: nobody loses health" % kind)


# ================================================================ cheat

func new_ch(n: int = 3, rng_seed: int = 1) -> Cheat:
	var names := []
	for i in range(n):
		names.append("P%d" % (i + 1))
	var g := Cheat.new()
	g.setup(names, {}, rng_seed)
	g.start_round()
	return g


func test_ch_play() -> void:
	var g := new_ch(3, 3)
	var total := 0
	for p in g.players:
		total += p.hand.size()
	check(total == 52 and g.required == 1, "all 52 cards dealt; aces first")
	var me := g.turn
	g.players[me].hand = cards("AH AC 7D 9S")
	check(not g.play(me, ["AH", "AC", "7D", "9S", "X"])["ok"], "need real cards")
	check(g.play(me, ["AH", "7D"])["ok"] and g.required == 2 and g.turn != me, "play 2 as aces; twos are next")
	check(g.snapshot(g.turn)["discard_pile"][0].get("hidden", false), "the pile is face down for everyone")
	check(g.can_call(g.turn), "the next player can call it")


func test_ch_call() -> void:
	var g := new_ch(3, 5)
	g.trump_rank = 13
	var a := g.turn
	g.players[a].hand = cards("AH 7D 5C")
	g.play(a, ["AH", "7D"]) # a lie
	var b := g.turn
	var before: int = g.players[b].items.size()
	var res := g.call_cheat(b)
	check(res["ok"] and res["lie"], "caught lying")
	check(g.players[a].hand.size() == 3 and g.discard_pile.is_empty(), "the liar picks up the pile")
	check(g.players[b].items.size() == before + 1, "catching a cheat earns an item")
	check(g.turn == b and not g.can_call(b), "then the caller plays")
	# telling the truth: the caller picks up
	g.players[b].hand = cards("2H 2C 9D")
	g.play(b, ["2H", "2C"])
	var c := g.turn
	var had: int = g.players[c].hand.size()
	res = g.call_cheat(c)
	check(res["ok"] and not res["lie"] and g.players[c].hand.size() == had + 2, "wrong call: the caller picks up")
	# a trump is never a lie
	g.players[c].hand = cards("KH 4D")
	g.play(c, ["KH"])
	res = g.call_cheat(g.turn)
	check(res["ok"] and not res["lie"], "a trump counts as the rank you said")
	# the last card: wins unless caught
	g = new_ch(2, 7)
	a = g.turn
	g.players[a].hand = cards("AH")
	g.play(a, ["AH"])
	b = g.turn
	check(not g.play(b, [g.players[b].hand[0]["id"]])["ok"], "after a last card you must call or let it go")
	g.let_go(b)
	check(g.phase == "shoot" and g.gun["holder"] == a, "let it go: they win")
	g = new_ch(2, 8)
	a = g.turn
	g.players[a].hand = cards("5H")
	g.play(a, ["5H"]) # aces were due: a lie
	g.call_cheat(g.turn)
	check(g.phase == "play" and g.players[a].hand.size() == 1, "caught on the last card: no win")


## Every game's AI, all three levels, finishes whole matches with legal moves
## (the newer cartridges; Rummy and Blackjack have their own tests).
func test_ai_all_games() -> void:
	for kind in ["cheat", "hearts", "spades", "snap", "president", "poker"]:
		var wins := {"easy": 0, "normal": 0, "hard": 0}
		for s in range(1, 9):
			var n := 2 + s % 5
			var names := []
			for i in range(n):
				names.append("P%d" % (i + 1))
			var g = Games.make(kind)
			g.setup(names, {}, s * 37)
			for i in range(n):
				g.players[i].bot = Bot.LEVELS[(i + s) % 3]
			g.start_round()
			var memories := {}
			var steps := 0
			var refused := 0
			while g.phase != "match_over" and steps < 30000:
				steps += 1
				if g.phase == "round_over":
					g.start_round()
					continue
				if kind == "snap" and g.phase == "play" and g.snap_ready():
					# the quickest player snaps (main.gd times the AIs' reactions)
					var alive: Array = g.alive_players()
					g.snap(alive[g.rng.randi_range(0, alive.size() - 1)].seat)
					continue
				var seat: int = g.gun["holder"] if g.phase == "shoot" else g.turn
				var mem: Dictionary = memories.get_or_add(seat, {})
				var act := Bot.next_action(g, seat, g.players[seat].bot, mem)
				if act.is_empty():
					check(false, "%s seed %d: no move in phase %s" % [kind, s, g.phase])
					return
				var res: Dictionary = Session.perform(g, seat, act[0], act[1], true)
				if not res["ok"]:
					refused += 1
					Bot.note_failure(mem, act)
					if refused == 25:
						print("    %s seed %d stuck: %s %s -> %s (phase %s, %s)" % [kind, s, g.players[seat].bot, act, res["error"], g.phase, g.snapshot(seat).get("pending_win", "")])
				if g.phase == "play":
					var count := 0
					for p in g.players:
						for c in p.hand:
							if not c.has("item"):
								count += 1
					if kind == "snap":
						for k in g.won:
							count += g.won[k].size()
					if kind == "poker":
						count += g.board.size()
					for m in g.melds:
						count += m["cards"].size()
					for c in g.stock + g.burned + g.discard_pile:
						if not c.has("item"):
							count += 1
					if kind == "hearts" or kind == "spades":
						count += g.trick.size()
						for k in g.taken:
							count += g.taken[k].size()
					if count != 52:
						check(false, "%s seed %d: %d cards in play" % [kind, s, count])
						return
			check(g.phase == "match_over", "%s seed %d: match finishes (round %d)" % [kind, s, g.round_num])
			check(refused < 20, "%s seed %d: AI moves are legal (%d refused)" % [kind, s, refused])
			if g.winner >= 0:
				wins[g.players[g.winner].bot] += 1
		print("  %s AI wins by level: %s" % [kind, wins])


## Someone plays their last card, then an item empties the pile: there's
## nothing to call, so the AI lets it go.
func test_ch_empty_pile() -> void:
	var g := new_ch(3, 9)
	var a := g.turn
	g.players[a].hand = cards("AH")
	g.play(a, ["AH"])
	var b := g.turn
	g.players[b].bot = "hard"
	g.players[b].items = [{"id": "I-garbage_day-1", "item": "garbage_day"}]
	var other := g.next_alive(b)
	check(g.use_item(b, "I-garbage_day-1", other)["ok"], "garbage day")
	check(g.pending_win == a and not g.can_call(b), "nothing left to call")
	var act := Bot.next_action(g, b, "hard", {})
	check(act[0] == "let_go", "the AI lets it go: %s" % [act])


# ================================================================ hearts and spades

## Gives seats (in turn order from the leader) these hands.
func _set_hands(g, hands: Array) -> Array:
	var order := []
	var s: int = g.turn
	for i in range(hands.size()):
		order.append(s)
		g.players[s].hand = cards(hands[i])
		s = g.next_alive(s)
	g._start_trick(order[0])
	return order


func test_hearts() -> void:
	var g := Hearts.new()
	g.setup(["A", "B", "C", "D"], {}, 3)
	g.start_round()
	for p in g.players:
		check(p.hand.size() == 13, "13 cards each with 4 players")
	g.trump_rank = 7
	var o := _set_hands(g, ["2C 5H", "9C QS", "KC 3H", "4D 6D"])
	check(not g.play_card(o[0], "5H")["ok"], "hearts can't be led before they're broken")
	check(g.play_card(o[0], "2C")["ok"], "lead a club")
	check(not g.play_card(o[1], "QS")["ok"], "must follow suit")
	g.play_card(o[1], "9C")
	g.play_card(o[2], "KC")
	var hp: int = g.players[o[2]].hp
	g.play_card(o[3], "4D")
	check(g.tricks_won[o[2]] == 1 and g.turn == o[2], "the king of clubs takes it and leads")
	# trumps beat everything, played any time
	g.players[o[2]].hand = cards("3H 7C")
	g.players[o[3]].hand = cards("6D 7D")
	g.players[o[0]].hand = cards("5H 8H")
	g.players[o[1]].hand = cards("QS 2S")
	g.broken = true
	g._start_trick(o[2])
	g.play_card(o[2], "3H")
	check(g.legal_cards(o[3]).size() == 2, "no hearts: anything goes")
	g.play_card(o[3], "7D") # a trump
	g.play_card(o[0], "8H")
	g.play_card(o[1], "QS")
	check(g.tricks_won.get(o[3], 0) == 1, "the trump wins the trick")
	check(g.players[o[3]].hp == g.players[o[3]].max_hp - 1, "taking the Queen of Spades costs 1 health")
	check(g.points(o[3]) == 15, "2 hearts + the queen = 15 points")


func test_spades() -> void:
	var g := Spades.new()
	g.setup(["A", "B", "C"], {}, 5)
	g.start_round()
	check(g.bidding and g.burned.size() == 1, "3 players: 17 each, 1 set aside, and bidding first")
	var first := g.turn
	check(not g.play_card(first, g.players[first].hand[0]["id"])["ok"], "no playing before bidding")
	g.bid(g.turn, 1)
	g.bid(g.turn, 0)
	g.bid(g.turn, 2)
	check(not g.bidding and g.turn == first, "bidding done: the leader plays")
	g.trump_rank = 13
	var o := _set_hands(g, ["AH 2S", "3H 4S", "5D 6C"])
	g.play_card(o[0], "AH")
	g.play_card(o[1], "3H")
	g.play_card(o[2], "5D")
	check(g.tricks_won[o[0]] == 1, "ace of hearts wins")
	g.players[o[0]].hand = cards("9H 2S")
	g.players[o[1]].hand = cards("4S 8C")
	g.players[o[2]].hand = cards("JH 6C")
	g._start_trick(o[0])
	check(not g.play_card(o[0], "2S")["ok"], "spades can't be led until broken")
	g.play_card(o[0], "9H")
	g.play_card(o[1], "4S") # can't follow: trumps it with a spade
	g.play_card(o[2], "JH")
	check(g.tricks_won.get(o[1], 0) == 1, "a spade beats the jack of hearts")
	check(g.round_score(o[0]) == 10, "bid 1, took 1: 10")
	check(g.round_score(o[1]) == -50, "bid nil, took 1: -50")


# ================================================================ snap

func test_snap() -> void:
	var g := Snap.new()
	g.setup(["A", "B", "C"], {}, 4)
	g.start_round()
	var total := 0
	for p in g.players:
		for c in p.hand:
			if not c.has("item"):
				total += 1
	check(total == 52, "every card is in someone's pile")
	check(g.snapshot(0)["players"][0]["hand"][0].get("hidden", false), "nobody sees their own pile")
	g.trump_rank = 13
	var a := g.turn
	g.players[a].hand = cards("5D 7C")
	g.flip(a)
	var b := g.turn
	g.players[b].hand = cards("9S 7H")
	check(not g.snap_ready(), "one card: nothing to snap")
	g.flip(b)
	check(g.snap_ready(), "7 on 7: snap!")
	var c := g.turn
	check(g.snap(c)["good"] and g.won[c].size() == 2 and g.discard_pile.is_empty(), "anyone can snap, any time, and wins the middle")
	var hp: int = g.players[a].hp
	check(not g.snap(a)["good"] and g.players[a].hp == hp - 1, "a wrong snap costs 1 health")
	# a trump matches anything
	g.discard_pile = cards("4H KD")
	check(g.snap_ready(), "a trump on top matches")
	# the end: most cards won
	g = Snap.new()
	g.setup(["A", "B"], {}, 6)
	g.start_round()
	a = g.turn
	b = g.next_alive(a)
	g.players[a].hand = cards("2C")
	g.players[b].hand = cards("2D")
	g.won[a] = cards("3C 3D 3H")
	g.flip(a)
	g.flip(b)
	check(g.last_call and g.snap_ready(), "last flip: one last chance to snap")
	g.snap(b)
	g.finish(g.turn)
	check(g.phase == "shoot" and g.gun["holder"] == a, "most cards won takes the shotgun")


# ================================================================ president

func test_president() -> void:
	var g := President.new()
	g.setup(["A", "B", "C"], {}, 8)
	g.start_round()
	g.trump_rank = 13
	var o := [g.turn, g.next_alive(g.turn), g.next_alive(g.next_alive(g.turn))]
	g.players[o[0]].hand = cards("5H 5C 9D")
	g.players[o[1]].hand = cards("4H 4C 7D 7S KS")
	g.players[o[2]].hand = cards("2H 2C 3D")
	check(not g.play(o[0], ["5H", "9D"])["ok"], "a pair must be the same rank")
	check(g.play(o[0], ["5H", "5C"])["ok"] and g.turn == o[1], "lead a pair of 5s")
	check(not g.play(o[1], ["4H", "4C"])["ok"], "4s don't beat 5s")
	check(not g.play(o[1], ["7D"])["ok"], "it has to be a pair")
	check(g.play(o[1], ["7D", "KS"])["ok"], "a 7 and a trump make a pair of 7s")
	check(g.play(o[2], ["2H", "2C"])["ok"], "2s are high")
	g.pass_turn(g.turn)
	g.pass_turn(g.turn)
	check(g.pile_top.is_empty() and g.turn == o[2], "everyone passed: the pile clears and the 2s lead")
	g.play(o[2], ["3D"])
	check(g.phase == "shoot" and g.gun["holder"] == o[2], "first out is President")
	check(g.scum == o[1], "most cards left is the Scum")
	g.gun = null
	g.phase = "round_over"
	var swaps := []
	g.event.connect(func(kind, d): if kind == "exchange": swaps.append(d))
	g.start_round()
	check(swaps.size() == 1 and swaps[0]["president"] == o[2] and swaps[0]["scum"] == o[1], "next round the Scum pays the President")


## The Blank Shell: the next shot fired does nothing, then the gun is live.
func test_blank_shell() -> void:
	var g := new_game(3, 21)
	var me := g.turn
	g.players[me].items = [{"id": "I-blank-1", "item": "blank"}]
	check(g.use_item(me, "I-blank-1")["ok"] and g.blank_loaded, "a blank goes in")
	g.phase = "shoot"
	var them := g.next_alive(me)
	g.gun = {"holder": me, "shells": 2, "total": 2}
	var hp: int = g.players[them].hp
	var res := g.shoot(me, them)
	check(res["ok"] and res["damage"] == 0 and g.players[them].hp == hp, "the blank does no damage")
	g.shoot(me, them)
	check(g.players[them].hp == hp - 1 and not g.blank_loaded, "the next shell is live")


## Trumps (and the items about them) are only in Rummy.
func test_trumps_only_rummy() -> void:
	for kind in Games.kinds():
		var g = Games.make(kind)
		g.setup(["A", "B", "C"], {}, 4)
		g.start_round()
		check((g.trump_rank > 0) == (kind == "rummy"), "%s: trumps only in Rummy (trump %d)" % [kind, g.trump_rank])
		for c in g.stock + g.item_deck:
			if c.has("item") and kind != "rummy":
				check(c["item"] != "tarot" and c["item"] != "joker_paint", "%s: no trump items" % kind)
		for p in g.players:
			for c in p.items + p.hand:
				if c.has("item") and kind != "rummy":
					check(c["item"] != "tarot" and c["item"] != "joker_paint", "%s: no trump items dealt" % kind)


# ================================================================ poker

func test_poker_hands() -> void:
	var r := func(ids: String) -> Array: return Poker.best_hand(cards(ids))
	check(r.call("AH KH QH JH 10H 2C 3D")[0] == 8, "royal flush is a straight flush")
	check(r.call("9S 9H 9D 9C 2H 3C 4D")[0] == 7, "four of a kind")
	check(r.call("9S 9H 9D 4C 4H 3C 2D")[0] == 6, "full house")
	check(r.call("2H 7H 9H JH KH 3C 4D")[0] == 5, "flush")
	check(r.call("AS 2H 3D 4C 5H 9C KD") == [4, 5], "A-2-3-4-5 is a 5-high straight")
	check(r.call("6S 7H 8D 9C 10H 2C 2D")[0] == 4, "straight")
	check(r.call("QS QH QD 4C 9H 2C 7D")[0] == 3, "three of a kind")
	check(r.call("QS QH 4D 4C 9H 2C 7D")[0] == 2, "two pair")
	check(r.call("QS QH 3D 4C 9H 2C 7D")[0] == 1, "a pair")
	check(r.call("QS 8H 3D 4C 9H 2C 7D")[0] == 0, "high card")
	check(Poker.better(r.call("AS AH 3D 4C 9H 2C 7D"), r.call("KS KH 3D 4C 9H 2C 7D")), "aces beat kings")
	check(Poker.better(r.call("AS AH KD 4C 9H 2C 7D"), r.call("AS AH QD 4C 9H 2C 7D")), "the kicker counts")


func test_poker_betting() -> void:
	var g := Poker.new()
	g.setup(["A", "B", "C"], {}, 5)
	g.start_round()
	for p in g.players:
		check(p.hand.size() == 2, "two cards each")
	check(g.snapshot(0)["players"][1]["hand"][0].get("hidden", false), "you can't see their cards")
	var a := g.turn
	g.check_call(a)
	var b := g.turn
	check(g.raise(b)["ok"] and g.shells == 2, "a raise loads a shell")
	var c := g.turn
	check(g.to_call(c), "the next player has to answer it")
	g.fold(c)
	check(g.turn == a and g.to_call(a), "back round to the first player")
	g.check_call(a)
	check(g.board.size() == 3, "everyone's answered: the flop")
	# play it out: check down to the showdown
	g.players[a].hand = cards("AS AH")
	g.players[b].hand = cards("2C 7D")
	g.board = cards("AD KC 9S")
	for i in range(20):
		if g.phase != "play":
			break
		g.check_call(g.turn)
	check(g.board.size() == 5 and (g.phase == "shoot" or g.phase == "round_over"), "turn, river, showdown")
	check(g.last_result["winner"] == a, "three aces win")
	check(g.gun != null and g.gun["shells"] == 2 and g.gun["targets"] == [b], "two shells, and only at the player who stayed in")
	check(not g.shoot(a, c)["ok"], "the folder is safe")
	# everyone else folds: they're all safe
	g = Poker.new()
	g.setup(["A", "B", "C"], {}, 6)
	g.start_round()
	g.raise(g.turn)
	g.fold(g.turn)
	g.fold(g.turn)
	check(g.phase == "round_over" and g.gun == null, "everyone folded: the raiser wins, nobody gets shot")
