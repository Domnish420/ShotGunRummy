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
##   target  true if you pick another player to use it on

const DEFS := {
	"cigarettes": {"name": "Cigarettes", "icon": "🚬", "text": "Gain 1 health.", "copies": 3, "target": false},
	"beer": {"name": "Beer", "icon": "🍺", "text": "Burn the top card of the stock. Everyone sees it.", "copies": 3, "target": false},
	"magnifier": {"name": "Magnifier", "icon": "🔍", "text": "Secretly look at the top card of the stock.", "copies": 3, "target": false},
	"handcuffs": {"name": "Handcuffs", "icon": "⛓️", "text": "A player of your choice skips their next turn.", "copies": 2, "target": true},
	"saw": {"name": "Hand Saw", "icon": "🪚", "text": "Your next shotgun shell deals double damage.", "copies": 2, "target": false},
	"phone": {"name": "Burner Phone", "icon": "📱", "text": "See a random card in another player's hand.", "copies": 2, "target": true},
	"adrenaline": {"name": "Adrenaline", "icon": "💉", "text": "Steal a random item from another player.", "copies": 2, "target": true},
	"medicine": {"name": "Expired Meds", "icon": "💊", "text": "50% chance: gain 2 health. Otherwise lose 1.", "copies": 2, "target": false},
}


static func def(item_id: String) -> Dictionary:
	return DEFS[item_id]


static func item_name(card: Dictionary) -> String:
	return DEFS[card["item"]]["name"]


static func needs_target(item_id: String) -> bool:
	return DEFS[item_id]["target"]


static func create_item_deck() -> Array:
	var deck := []
	for item_id in DEFS:
		for n in range(1, int(DEFS[item_id]["copies"]) + 1):
			deck.append({"id": "I-%s-%d" % [item_id, n], "item": item_id})
	return deck
