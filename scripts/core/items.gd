extends RefCounted
## Item / ability cards.
##
## Every player is dealt 2 items at the start of each round, and the rest are
## shuffled into the stock, so a draw can give you an item instead of a playing
## card. Draw an item and you keep it and draw again (from the stock or the
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
	# the table
	"sticky_fingers": {"name": "Sticky Fingers", "icon": "✋", "text": "Steal a card from a meld. A meld left with 2 cards goes to the discard pile.", "copies": 2, "needs": "meld_card"},
	"dumpster_dive": {"name": "Dumpster Dive", "icon": "🗑️", "text": "Take the top 3 cards of the discard pile.", "copies": 1, "needs": ""},
	"garbage_day": {"name": "Garbage Day", "icon": "🚮", "text": "A player of your choice takes the whole discard pile.", "copies": 1, "needs": "player"},
	# trumps
	"tarot": {"name": "Tarot Card", "icon": "🔮", "text": "The trump moves to the next rank for the rest of the round.", "copies": 1, "needs": ""},
	"joker_paint": {"name": "Joker Paint", "icon": "🎭", "text": "A card in your hand is a trump until your turn ends. Meld it to keep it wild.", "copies": 2, "needs": "hand_card"},
}


static func def(item_id: String) -> Dictionary:
	return DEFS[item_id]


static func item_name(card: Dictionary) -> String:
	return DEFS[card["item"]]["name"]


## Does this item need another player picked?
static func needs_target(item_id: String) -> bool:
	return DEFS[item_id]["needs"] == "player"


## What has to be picked: "", "player", "meld_card" or "hand_card".
static func needs(item_id: String) -> String:
	return DEFS[item_id]["needs"]


static func create_item_deck() -> Array:
	var deck := []
	for item_id in DEFS:
		for n in range(1, int(DEFS[item_id]["copies"]) + 1):
			deck.append({"id": "I-%s-%d" % [item_id, n], "item": item_id})
	return deck
