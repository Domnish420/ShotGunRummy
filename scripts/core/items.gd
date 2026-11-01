extends RefCounted
## Item / ability cards.
##
## Items are rare. Nobody is dealt any: each round only a few (options
## "items_per_round", 3) are shuffled into the stock, so a draw now and then
## gives you an item instead of a playing card. Games without a stock hand them
## out as loot (Game._loot). Draw an item and you keep it and draw again (from the stock or the
## discard pile) until you get a playing card. Unused items go back at the end of the round. Use as many items as you
## like, at any point in your turn. Items never count as deadwood and you don't
## need to get rid of them to go out.
##
## An item card is a Dictionary: { "id": "I-beer-2", "item": "beer" }.
## What each item does lives in game.gd (_apply_item). To add an item: add an
## entry here, then a matching branch in _apply_item and item_blocker.
##
##   name    shown on the card
##   icon    emoji drawn on the card
##   text    one-line rules text
##   copies  how many are in the item deck
##   needs   what you pick when you use it: "" (nothing), "player" (another
##           player), "meld_card" (a card in a meld on the table) or
##           "hand_card" (a card in your hand)

const DEFS := {
	# health and the shotgun
	"cigarettes": {"name": "Cigarettes", "icon": "🚬", "text": "Gain 1 health.", "copies": 2, "needs": ""},
	"medicine": {"name": "Expired Meds", "icon": "💊", "text": "50% chance: gain 2 health. Otherwise lose 1.", "copies": 1, "needs": ""},
	"blank": {"name": "Blank Shell", "icon": "🎯", "text": "Very rare. Slip a blank into the shotgun: the next shot fired does no damage, whoever pulls the trigger.", "copies": 1, "needs": ""},
	"saw": {"name": "Hand Saw", "icon": "🪚", "text": "Your next shotgun shell deals double damage.", "copies": 2, "needs": ""},
	# information and the stock
	"beer": {"name": "Beer", "icon": "🍺", "text": "Burn the top card of the stock. Everyone sees it.", "copies": 2, "needs": ""},
	"magnifier": {"name": "Magnifier", "icon": "🔍", "text": "Secretly look at the top card of the stock.", "copies": 2, "needs": ""},
	"phone": {"name": "Burner Phone", "icon": "📱", "text": "See a random card in another player's hand.", "copies": 1, "needs": "player"},
	# other players
	"handcuffs": {"name": "Handcuffs", "icon": "⛓️", "text": "A player of your choice skips their next turn.", "copies": 2, "needs": "player"},
	"adrenaline": {"name": "Adrenaline", "icon": "💉", "text": "Steal a random item from another player.", "copies": 1, "needs": "player"},
	"shakedown": {"name": "Shakedown", "icon": "👊", "text": "A player of your choice discards a random card.", "copies": 1, "needs": "player"},
	"switcheroo": {"name": "Switcheroo", "icon": "🔄", "text": "Swap your whole hand with another player's.", "copies": 1, "needs": "player"},
	"bad_trade": {"name": "Bad Trade", "icon": "🤝", "text": "Swap 2 random cards with another player.", "copies": 1, "needs": "player"},
	"chaos": {"name": "Chaos", "icon": "🌀", "text": "Everyone passes a random card to the player on their left.", "copies": 1, "needs": ""},
	"spotlight": {"name": "Spotlight", "icon": "🔦", "text": "A player's whole hand is shown to everyone until their next turn ends.", "copies": 1, "needs": "player"},
	"flashbang": {"name": "Flashbang", "icon": "💥", "text": "Every other player shows 2 random cards until their next turn ends.", "copies": 1, "needs": ""},
	"revolver": {"name": "Revolver", "icon": "🔫", "text": "A player must put cards down on their next turn, or play Russian roulette (1 in 6: lose 2 health).", "copies": 1, "needs": "player"},
	"double_down": {"name": "Double Down", "icon": "🎲", "text": "A player must draw 2 cards on their next turn, from either pile.", "copies": 1, "needs": "player"},
	# the table
	"sticky_fingers": {"name": "Sticky Fingers", "icon": "✋", "text": "Steal a card from a meld. A meld left with 2 cards goes to the discard pile.", "copies": 2, "needs": "meld_card"},
	"dumpster_dive": {"name": "Dumpster Dive", "icon": "🗑️", "text": "Take the top 3 cards of the discard pile.", "copies": 1, "needs": ""},
	"garbage_day": {"name": "Garbage Day", "icon": "🚮", "text": "A player of your choice takes the whole discard pile.", "copies": 1, "needs": "player"},
	# trumps
	"tarot": {"name": "Tarot Card", "icon": "🔮", "text": "The trump moves to the next rank for the rest of the round.", "copies": 1, "needs": ""},
	"joker_paint": {"name": "Joker Paint", "icon": "🎭", "text": "A card in your hand is a trump until your turn ends. Meld it to keep it wild.", "copies": 2, "needs": "hand_card"},
}


## Blackjack plays the same items with their own twist. Anything not listed
## here works as in Rummy. "copies": 0 leaves an item out of the deck.
const BLACKJACK := {
	"phone": {"text": "See another player's face-down card.", "copies": 2},
	"handcuffs": {"text": "A player who hasn't played yet skips their turn and stands on what they have.", "copies": 1},
	"shakedown": {"text": "A player of your choice throws away the last card they were dealt.", "copies": 1},
	"bad_trade": {"text": "Swap 1 random card with another player.", "copies": 1},
	"spotlight": {"text": "Turn a player's face-down card face up for everyone.", "copies": 1},
	"flashbang": {"text": "Every other player turns their face-down card face up.", "copies": 1},
	"revolver": {"text": "A player who hasn't played yet must take a card on their turn, or play Russian roulette (1 in 6: lose 2 health).", "copies": 1},
	"double_down": {"text": "A player of your choice is dealt 1 more card, right now, even if they've stood.", "copies": 2},
	"sticky_fingers": {"text": "Steal a face-up card from another player's hand.", "copies": 1, "needs": "table_card"},
	"dumpster_dive": {"text": "Take the top card of the discard pile.", "copies": 1},
	"garbage_day": {"text": "A player of your choice is dealt the top card of the discard pile, face up."},
	"joker_paint": {"text": "A card in your hand is a trump (worth whatever you need) for the rest of the round.", "copies": 1},
}

const GOFISH := {
	"shakedown": {"text": "A player of your choice throws a random card back into the pond."},
	"revolver": {"text": "A player must get a card off someone on their next turn, or play Russian roulette (1 in 6: lose 2 health)."},
	"double_down": {"text": "Fish 2 cards from the pond right now.", "needs": ""},
	"sticky_fingers": {"text": "Steal a card from someone's book. The rest of the book goes back into their hand.", "copies": 1},
	"dumpster_dive": {"text": "Dig through the pond for a card that matches one in your hand."},
	"garbage_day": {"text": "A player of your choice throws their whole hand back in the pond and fishes the same number of new cards."},
	"beer": {"text": "Burn the top card of the pond. Everyone sees it."},
	"magnifier": {"text": "Secretly look at the top card of the pond."},
	"joker_paint": {"text": "A card in your hand is wild (a trump) for the rest of the round.", "copies": 1},
}

const CHEAT := {
	"beer": {"text": "Burn the top card of the pile: it's turned face up for everyone and set aside."},
	"magnifier": {"text": "Secretly look at a card from the last play. If any of them is a lie, you'll see it."},
	"shakedown": {"text": "A player of your choice takes 3 cards from the bottom of the pile."},
	"revolver": {"text": "A player who lies on their next play and gets caught also plays Russian roulette (1 in 6: lose 2 health)."},
	"double_down": {"text": "A player of your choice must put down at least 2 cards on their next turn."},
	"sticky_fingers": {"text": "Slip the top card of the pile into your hand.", "needs": "", "copies": 1},
	"dumpster_dive": {"text": "Slip a random card from your hand under the pile."},
	"garbage_day": {"text": "A player of your choice picks up the whole pile."},
	"joker_paint": {"text": "A card in your hand is wild (a trump) for the rest of the round: it always tells the truth.", "copies": 1},
}

## Hearts and Spades: no stock or discard pile, and every trick needs a card
## from everyone, so here the items never change how many cards anyone holds.
const TRICKS := {
	"beer": {"text": "A random card of a player of your choice is shown to everyone until the trick ends.", "needs": "player"},
	"magnifier": {"text": "Secretly see the highest card of the next player to play."},
	"handcuffs": {"text": "A player of your choice must play their lowest card next."},
	"shakedown": {"text": "Take a random card from a player of your choice. They get your lowest card back."},
	"switcheroo": {"text": "Swap your whole hand with a player holding as many cards as you."},
	"sticky_fingers": {"text": "Swap a random card of yours for the card a player of your choice played to this trick.", "needs": "player"},
	"dumpster_dive": {"text": "Take the best card from the last trick. A random card of yours goes in its place."},
	"bad_trade": {"copies": 1},
	"spotlight": {"text": "A player's whole hand is shown to everyone until the trick ends.", "copies": 2},
	"flashbang": {"text": "Every other player shows 2 random cards until the trick ends."},
	"revolver": {"text": "If a player of your choice wins the next trick they play Russian roulette (1 in 6: lose 2 health).", "copies": 2},
	"double_down": {"text": "A player of your choice must play their highest card next.", "copies": 2},
	"joker_paint": {"text": "A card in your hand is wild (a trump) for the rest of the round: play it any time, it wins the trick.", "copies": 1},
}

const HEARTS := {
	"garbage_day": {"text": "Dump your worst point card onto the tricks of a player of your choice."},
}

const SPADES := {
	"garbage_day": {"text": "Give one of the tricks you've won to a player of your choice."},
}

const SNAP := {
	"beer": {"text": "Burn the next card of a player of your choice's pile. Everyone sees it.", "needs": "player"},
	"magnifier": {"text": "Secretly look at your next card."},
	"phone": {"text": "See another player's next card."},
	"handcuffs": {"text": "A player of your choice skips their next flip."},
	"shakedown": {"text": "A player of your choice flips their next card onto the middle right now. Get ready to SNAP!"},
	"spotlight": {"text": "Everyone sees the next card in a player of your choice's pile."},
	"flashbang": {"text": "Everyone sees the next card in every other pile."},
	"revolver": {"text": "If a player of your choice snaps wrong, they also play Russian roulette (1 in 6: lose 2 health)."},
	"double_down": {"text": "A player of your choice flips 2 cards on their next turn."},
	"sticky_fingers": {"text": "Steal 3 of another player's won cards.", "needs": "player", "copies": 1},
	"dumpster_dive": {"text": "Take the bottom 3 cards of the middle as cards you've won."},
	"garbage_day": {"text": "A player of your choice dumps 5 of their won cards under the middle: the next good SNAP wins them."},
	"joker_paint": {"text": "The top card in the middle turns wild: it matches anything. Get ready to SNAP!", "needs": "", "copies": 2},
}

const PRESIDENT := {
	"beer": {"text": "Knock the pile over: it clears and you lead."},
	"magnifier": {"text": "Secretly see the best card of a player of your choice.", "needs": "player"},
	"handcuffs": {"text": "A player of your choice passes their next turn."},
	"shakedown": {"text": "Shove your worst card onto a player of your choice."},
	"revolver": {"text": "If a player of your choice passes on their next turn, they play Russian roulette (1 in 6: lose 2 health)."},
	"double_down": {"text": "A player of your choice sits out this pile and the next one."},
	"sticky_fingers": {"text": "Steal a random card from a player of your choice. They get your worst card back.", "needs": "player"},
	"dumpster_dive": {"text": "Dig the best card that's been played this round out of the pile and into your hand."},
	"garbage_day": {"text": "A player of your choice picks up the play on the table. The pile clears and you lead."},
	"joker_paint": {"text": "A card in your hand is wild (a trump) for the rest of the round: it fills in any set.", "copies": 1},
}

const POKER := {
	"beer": {"text": "Burn the next card for the middle. Everyone sees it."},
	"magnifier": {"text": "Secretly look at the next card for the middle."},
	"phone": {"text": "See one of another player's cards."},
	"handcuffs": {"text": "A player of your choice skips their next go (they stay in the hand)."},
	"shakedown": {"text": "A player of your choice throws away a random card and gets a new one."},
	"switcheroo": {"text": "Swap your two cards with another player's."},
	"bad_trade": {"text": "Swap 1 random card with another player."},
	"chaos": {"text": "Everyone passes a random card to the player on their left."},
	"spotlight": {"text": "A player's cards are turned face up for everyone."},
	"flashbang": {"text": "Every other player still in shows 1 card."},
	"revolver": {"text": "If a player of your choice folds this hand, they play Russian roulette (1 in 6: lose 2 health)."},
	"double_down": {"text": "A player of your choice can't fold this hand."},
	"sticky_fingers": {"text": "Swap your lower card for a random card of a player of your choice.", "needs": "player"},
	"dumpster_dive": {"text": "Throw away your lower card and get a new one."},
	"garbage_day": {"text": "A player of your choice throws away both their cards and gets two new ones."},
}

## Each game's changes to the items, by game.
const OVERRIDES := {"poker": POKER, "blackjack": BLACKJACK, "gofish": GOFISH, "cheat": CHEAT, "hearts": TRICKS, "spades": TRICKS, "snap": SNAP, "president": PRESIDENT}

## Changes on top of OVERRIDES, for games that share one set.
const EXTRA := {"hearts": HEARTS, "spades": SPADES}

## Which game's rules the items follow (a key of games.gd's LIST). Set when a
## game starts.
static var mode := "rummy"


## Items about the trump rank, which only Rummy has.
const RUMMY_ONLY := ["tarot", "joker_paint"]


static func def(item_id: String) -> Dictionary:
	if mode != "rummy" and RUMMY_ONLY.has(item_id):
		var only: Dictionary = DEFS[item_id].duplicate()
		only["copies"] = 0
		return only
	var changes: Dictionary = OVERRIDES.get(mode, {})
	var extra: Dictionary = EXTRA.get(mode, {})
	if changes.has(item_id) or extra.has(item_id):
		var d: Dictionary = DEFS[item_id].duplicate()
		d.merge(changes.get(item_id, {}), true)
		d.merge(extra.get(item_id, {}), true)
		return d
	return DEFS[item_id]


static func item_name(card: Dictionary) -> String:
	return def(card["item"])["name"]


## Does this item need another player picked?
static func needs_target(item_id: String) -> bool:
	return def(item_id)["needs"] == "player"


## What has to be picked: "", "player", "meld_card", "hand_card" or
## "table_card" (a face-up card in someone else's hand, in Blackjack).
static func needs(item_id: String) -> String:
	return def(item_id)["needs"]


## The item deck for the current game.
static func create_item_deck() -> Array:
	var deck := []
	for item_id in DEFS:
		for n in range(1, int(def(item_id)["copies"]) + 1):
			deck.append({"id": "I-%s-%d" % [item_id, n], "item": item_id})
	return deck


## A plain way for an AI to use `card`: a random target or card if it needs
## one. [] if there's nothing to use it on.
static func any_use(game, seat: int, card: Dictionary) -> Array:
	var item_id: String = card["item"]
	var target := -1
	var choice := ""
	match needs(item_id):
		"player":
			var targets: Array = game.item_targets(seat, item_id)
			if targets.is_empty():
				return []
			target = targets[game.rng.randi_range(0, targets.size() - 1)]
		"meld_card", "hand_card", "table_card":
			var choices: Array = game.item_choices(seat, item_id)
			if choices.is_empty():
				return []
			choice = choices[game.rng.randi_range(0, choices.size() - 1)]
	return [card["id"], target, choice]
