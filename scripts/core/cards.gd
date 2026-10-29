extends RefCounted
## Playing cards, melds and deadwood. Pure logic, no nodes.
##
## A card is a Dictionary: { "id": "7H", "rank": 7, "suit": "H" }.
## Aces are low: A-2-3 is a run, Q-K-A is not.

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

static func is_set(cards: Array) -> bool:
	if cards.size() < 3 or cards.size() > 4:
		return false
	var rank: int = cards[0]["rank"]
	var suits := {}
	for c in cards:
		if c["rank"] != rank:
			return false
		suits[c["suit"]] = true
	return suits.size() == cards.size()


static func is_run(cards: Array) -> bool:
	if cards.size() < 3:
		return false
	var suit: String = cards[0]["suit"]
	var ranks := []
	for c in cards:
		if c["suit"] != suit:
			return false
		ranks.append(c["rank"])
	ranks.sort()
	for i in range(1, ranks.size()):
		if ranks[i] != ranks[i - 1] + 1:
			return false
	return true


## "run", "set" or "" when the cards don't make a meld.
static func meld_type(cards: Array) -> String:
	if is_run(cards):
		return "run"
	if is_set(cards):
		return "set"
	return ""


static func sorted_meld(cards: Array, type: String) -> Array:
	var out := cards.duplicate()
	if type == "run":
		sort_by_rank(out)
	else:
		sort_by_suit(out)
	return out


## Can `cards` be added to a table meld ({ "type", "cards" })?
static func can_lay_off(meld: Dictionary, cards: Array) -> bool:
	if cards.is_empty():
		return false
	var combined: Array = meld["cards"] + cards
	return meld_type(combined) == meld["type"]


## Every set and run that can be formed from cards in `hand`.
static func candidate_melds(hand: Array) -> Array:
	var out := []

	var by_rank := {}
	for c in hand:
		if not by_rank.has(c["rank"]):
			by_rank[c["rank"]] = []
		by_rank[c["rank"]].append(c)
	for group in by_rank.values():
		if group.size() == 3:
			out.append(group.duplicate())
		elif group.size() == 4:
			out.append(group.duplicate())
			for skip in range(4):
				var three := []
				for i in range(4):
					if i != skip:
						three.append(group[i])
				out.append(three)

	for suit in SUITS:
		var cards := []
		for c in hand:
			if c["suit"] == suit:
				cards.append(c)
		sort_by_rank(cards)
		# split into chains of consecutive ranks
		var chains := []
		var chain := []
		for c in cards:
			if not chain.is_empty() and c["rank"] != chain[-1]["rank"] + 1:
				chains.append(chain)
				chain = []
			chain.append(c)
		if not chain.is_empty():
			chains.append(chain)
		for ch in chains:
			for i in range(ch.size()):
				for j in range(i + 2, ch.size()):
					out.append(ch.slice(i, j + 1))
	return out


## Best way to arrange a hand into melds, minimising deadwood points.
## Returns { "melds": Array[Array], "deadwood": Array, "points": int }.
static func best_partition(hand: Array) -> Dictionary:
	var candidates := candidate_melds(hand)
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
