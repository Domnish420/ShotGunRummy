extends RefCounted
## Playing cards, melds and deadwood. Pure logic, no nodes.
##
## A card is a Dictionary: { "id": "7H", "rank": 7, "suit": "H" }.
## Aces are low: A-2-3 is a run, Q-K-A is not. Each round one rank is trump
## (wild); see the melds section.

const SUITS := ["S", "H", "D", "C"]
const SUIT_SYMBOLS := {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
const RANK_LABELS := {1: "A", 11: "J", 12: "Q", 13: "K"}


static func rank_label(rank: int) -> String:
	return RANK_LABELS.get(rank, str(rank))


static func make_card(rank: int, suit: String) -> Dictionary:
	return {"id": rank_label(rank) + suit, "rank": rank, "suit": suit}


## Parses "7H", "10S", "AD" into a card. Handy for tests.
static func parse(id: String) -> Dictionary:
	var suit := id.right(1)
	var label := id.left(id.length() - 1)
	var rank := 0
	match label:
		"A": rank = 1
		"J": rank = 11
		"Q": rank = 12
		"K": rank = 13
		_: rank = int(label)
	return make_card(rank, suit)


static func parse_many(ids: String) -> Array:
	var out := []
	for id in ids.split(" ", false):
		out.append(parse(id))
	return out


static func create_deck() -> Array:
	var deck := []
	for suit in SUITS:
		for rank in range(1, 14):
			deck.append(make_card(rank, suit))
	return deck


static func is_red(card: Dictionary) -> bool:
	return card["suit"] == "H" or card["suit"] == "D"


static func card_points(card: Dictionary) -> int:
	var rank: int = card["rank"]
	if rank == 1:
		return 1
	return mini(rank, 10)


static func hand_points(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += card_points(c)
	return total


static func card_name(card: Dictionary) -> String:
	return rank_label(card["rank"]) + SUIT_SYMBOLS[card["suit"]]


static func cards_text(cards: Array) -> String:
	var parts := []
	for c in cards:
		parts.append(card_name(c))
	return " ".join(parts)


static func ids_of(cards: Array) -> Array:
	var out := []
	for c in cards:
		out.append(c["id"])
	return out


## Sorts in place by suit, then rank.
static func sort_by_suit(cards: Array) -> void:
	_insertion_sort(cards, false)


## Sorts in place by rank, then suit.
static func sort_by_rank(cards: Array) -> void:
	_insertion_sort(cards, true)


# hands are tiny, so a plain insertion sort is plenty
static func _insertion_sort(cards: Array, by_rank: bool) -> void:
	for i in range(1, cards.size()):
		var item = cards[i]
		var j := i - 1
		while j >= 0:
			var before: bool = _less_by_rank(item, cards[j]) if by_rank else _less_by_suit(item, cards[j])
			if not before:
				break
			cards[j + 1] = cards[j]
			j -= 1
		cards[j + 1] = item


static func _less_by_suit(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = SUITS.find(a["suit"])
	var sb: int = SUITS.find(b["suit"])
	if sa != sb:
		return sa < sb
	return a["rank"] < b["rank"]


static func _less_by_rank(a: Dictionary, b: Dictionary) -> bool:
	if a["rank"] != b["rank"]:
		return a["rank"] < b["rank"]
	return SUITS.find(a["suit"]) < SUITS.find(b["suit"])


# ------------------------------------------------------------------ melds
#
# `trump` is this round's wild rank (1 = aces ... 13 = kings, 0 = none).
# A trump card can stand in for any card, of any suit, in any set or run.

static func is_wild(card: Dictionary, trump: int) -> bool:
	return trump > 0 and int(card["rank"]) == trump


static func is_set(cards: Array, trump: int = 0) -> bool:
	if cards.size() < 3 or cards.size() > 4:
		return false
	var rank := -1
	var suits := {}
	for c in cards:
		if is_wild(c, trump):
			continue
		if rank == -1:
			rank = c["rank"]
		elif c["rank"] != rank:
			return false
		if suits.has(c["suit"]):
			return false
		suits[c["suit"]] = true
	return true


static func is_run(cards: Array, trump: int = 0) -> bool:
	if cards.size() < 3 or cards.size() > 13:
		return false
	var suit := ""
	var ranks := {}
	var wilds := 0
	for c in cards:
		if is_wild(c, trump):
			wilds += 1
			continue
		if suit == "":
			suit = c["suit"]
		elif c["suit"] != suit:
			return false
		if ranks.has(c["rank"]):
			return false
		ranks[c["rank"]] = true
	if ranks.is_empty():
		return true
	var lo: int = ranks.keys().min()
	var hi: int = ranks.keys().max()
	# trump cards fill the gaps; any spare ones extend the ends
	return (hi - lo + 1) - ranks.size() <= wilds


## "run", "set", "any" (trump cards make it work either way, e.g. 7 + two
## trumps) or "" when the cards don't make a meld.
static func meld_type(cards: Array, trump: int = 0) -> String:
	var run := is_run(cards, trump)
	var set3 := is_set(cards, trump)
	if run and set3:
		return "any"
	if run:
		return "run"
	if set3:
		return "set"
	return ""


## Cards in display order. In runs, trump cards sit in the gaps they fill.
static func sorted_meld(cards: Array, type: String, trump: int = 0) -> Array:
	var out := cards.duplicate()
	if type == "run" and is_run(cards, 0):
		# a natural run, even if some of it happens to be trump
		sort_by_rank(out)
		return out
	var naturals := []
	var wilds := []
	for c in cards:
		if is_wild(c, trump):
			wilds.append(c)
		else:
			naturals.append(c)
	if type != "run":
		# sets: naturals by suit, then the trumps standing in
		sort_by_suit(naturals)
		return naturals + wilds
	sort_by_rank(naturals)
	var arranged := []
	for i in range(naturals.size()):
		if i > 0:
			for gap in range(int(naturals[i]["rank"]) - int(naturals[i - 1]["rank"]) - 1):
				arranged.append(wilds.pop_back())
		arranged.append(naturals[i])
	# spare trumps go on the high end while there's room, then the low end
	var top: int = naturals[-1]["rank"]
	while not wilds.is_empty():
		if top < 13:
			arranged.append(wilds.pop_back())
			top += 1
		else:
			arranged.push_front(wilds.pop_back())
	return arranged


## Can `cards` be added to a table meld ({ "type", "cards" })?
static func can_lay_off(meld: Dictionary, cards: Array, trump: int = 0) -> bool:
	return lay_off_type(meld, cards, trump) != ""


## The meld's type after laying `cards` on it, or "" if they don't fit.
static func lay_off_type(meld: Dictionary, cards: Array, trump: int = 0) -> String:
	if cards.is_empty():
		return ""
	var combined: Array = meld["cards"] + cards
	var now := meld_type(combined, trump)
	var was: String = meld["type"]
	if now == "":
		return ""
	if was == "any":
		return now
	if now == "any" or now == was:
		return was
	return ""


## Every set and run that can be formed from cards in `hand`.
## Hands are small (about 8 cards), so every subset of 3+ cards is checked.
static func candidate_melds(hand: Array, trump: int = 0) -> Array:
	var out := []
	var n := hand.size()
	if n > 16:
		n = 16
	for mask in range(1, 1 << n):
		var subset := []
		for i in range(n):
			if mask & (1 << i):
				subset.append(hand[i])
		if subset.size() >= 3 and meld_type(subset, trump) != "":
			out.append(subset)
	return out


## Best way to arrange a hand into melds, minimising deadwood points.
## Returns { "melds": Array[Array], "deadwood": Array, "points": int }.
static func best_partition(hand: Array, trump: int = 0) -> Dictionary:
	var candidates := candidate_melds(hand, trump)
	var index := {}
	for i in range(hand.size()):
		index[hand[i]["id"]] = i
	var masks := []
	var values := []
	for m in candidates:
		var mask := 0
		for c in m:
			mask |= 1 << int(index[c["id"]])
		masks.append(mask)
		values.append(hand_points(m))

	var ctx := {"masks": masks, "values": values, "sizes": [], "best_saved": 0, "best_cards": 0, "best": []}
	for m in candidates:
		ctx["sizes"].append(m.size())
	_search(ctx, 0, 0, 0, 0, [])

	var melds := []
	var in_meld := {}
	for i in ctx["best"]:
		melds.append(candidates[i])
		for c in candidates[i]:
			in_meld[c["id"]] = true
	var deadwood := []
	for c in hand:
		if not in_meld.has(c["id"]):
			deadwood.append(c)
	return {"melds": melds, "deadwood": deadwood, "points": hand_points(deadwood)}


static func _search(ctx: Dictionary, start: int, used: int, saved: int, count: int, chosen: Array) -> void:
	if saved > ctx["best_saved"] or (saved == ctx["best_saved"] and count > ctx["best_cards"]):
		ctx["best_saved"] = saved
		ctx["best_cards"] = count
		ctx["best"] = chosen.duplicate()
	var masks: Array = ctx["masks"]
	for i in range(start, masks.size()):
		var mask: int = masks[i]
		if mask & used:
			continue
		chosen.append(i)
		_search(ctx, i + 1, used | mask, saved + int(ctx["values"][i]), count + int(ctx["sizes"][i]), chosen)
		chosen.pop_back()
