extends RefCounted
## What the DEMO explains, and when. While the demo plays itself, each lesson
## pops up the first time its moment comes round. A lesson is
## [trigger, text]:
##   "start"           as the cards are dealt, in order
##   "end"             once the watched round is over
##   "<event>"         the first time the game sends that event (see the
##                     engines' _emit calls), e.g. "meld", "bust"
##   "<event>:key=v"   only when the event's key has that value, e.g.
##                     "draw:item=true"
## Anything that never came up is shown at the end, so every rule gets said.

## Every cartridge's own rules.
const GAMES := {
	"rummy": [
		["start", "RUMMY. The aim: get rid of every card in your hand by laying them down in MELDS."],
		["start", "Everyone gets 7 cards. Nobody starts with items: just 3 rare ones are shuffled into the face-down STOCK."],
		["start", "TRUMPS. Each round one rank is wild: aces in round 1, twos in round 2, up to kings. A trump (gold star) stands in for any card in any meld."],
		["start", "On your first turn you can't put anything down: just draw and discard."],
		["draw:source=stock", "YOUR TURN: draw 1 card, from the stock or the top of the discard pile."],
		["draw:item=true", "An item came off the stock! Keep it, and draw again."],
		["draw:source=discard", "Taking the top of the discard pile: you can't throw that same card straight back."],
		["discard", "End your turn by DISCARDING 1 card. Trumps can't be discarded."],
		["meld", "A MELD: 3 or 4 of the same rank (a set), or 3+ in a row of one suit (a run). Aces are low."],
		["layoff", "LAYING OFF: add cards to any meld on the table, yours or anyone's."],
		["swap", "SWAPPING A TRUMP: hold the real card a trump stands for? Swap it in and take the trump, if you meld it straight away."],
		["round_end", "GOING OUT: empty your hand and you win the round. Everyone else's cards count against them."],
		["round_end:rummy=true", "RUMMY! Going out in one turn, without having melded before, doubles the points."],
	],
	"blackjack": [
		["start", "BLACKJACK. Everyone plays against the DEALER, who's one of the players (the white chip)."],
		["start", "Everyone gets 2 cards, one face down and one face up. Only 3 rare items hide in the stock."],
		["start", "Count your cards: 2 to 10 their number, J Q K are 10, an ace is 1 or 11. Get closer to 21 than the dealer, without going over."],
		["hit", "HIT: take another card. As many as you like."],
		["stand", "STAND: happy with your total, and your turn's over. 21 or 5 cards stands for you."],
		["bust", "BUST: over 21 and you lose to the dealer, whatever they get."],
		["blackjack_shot", "BLACKJACK: 21 with your first 2 cards. You shoot the dealer, free, straight away!"],
		["round_end", "THE DEALER plays last. Beat them and you're safe. Lose, and the dealer gets a shell for you, and can only shoot players who lost."],
	],
	"gofish": [
		["start", "GO FISH. The aim: collect BOOKS, four of a kind."],
		["start", "7 cards each (5 with 4 or more players). The rest are the POND, with 3 rare items hidden in it."],
		["ask", "YOUR TURN: pick a card you hold and ASK another player for that rank."],
		["ask:count=0", "They didn't have any: GO FISH! Draw from the pond. Fish the rank you asked for and you go again."],
		["go_fish:lucky=true", "A lucky catch: they fished the rank they asked for, so they go again."],
		["book", "A BOOK! Four of a kind goes down in front of you by itself."],
		["round_end", "The round ends when someone has to fish and the pond is empty. Most books wins."],
		["end", "Listen to what people ask for: they must be holding that rank. Ask them for it later!"],
	],
	"cheat": [
		["start", "CHEAT. The aim: get rid of every card. All 52 are dealt out."],
		["start", "Cards go down face down in order: aces, then twos, then threes, up to kings, then round again."],
		["play", "Put down 1 to 4 cards and say they're the rank that's due. You're allowed to LIE."],
		["called", "CHEAT! Before playing, you can call the last player out. Their cards are turned over."],
		["called:lie=true", "Caught lying: the liar picks up the whole pile, and the caller gets an item."],
		["called:lie=false", "They told the truth, so the one who called it picks up the pile. Call carefully!"],
		["round_end", "Play your last card and you win, unless the next player calls CHEAT and catches you."],
		["end", "Gold cards in your hand are the truth. Hold more of a rank than could exist? Somebody's lying."],
	],
	"hearts": [
		["start", "HEARTS. The aim: DON'T take hearts. Each one is 1 point, the Queen of Spades is 13. Fewest points wins."],
		["start", "The cards are dealt out evenly. One player leads a card, everyone plays one: that's a TRICK."],
		["trick_card", "FOLLOW SUIT: play the suit that was led if you can (the cards you can play glow gold)."],
		["trick_won", "The highest card of the suit led takes the trick, and everything in it. They lead next."],
		["hearts_broken", "Hearts are BROKEN: now they can be led. Before this, nobody could lead one."],
		["queen_taken", "The QUEEN OF SPADES: 13 points, and in Shotgun Hearts she costs you 1 health on the spot!"],
		["round_end", "Fewest points wins. Take EVERY point card and you SHOOT THE MOON: you win, with 3 shells."],
		["end", "Can't follow suit? That's your chance to dump the Queen or a high heart on someone else."],
	],
	"spades": [
		["start", "SPADES. Everyone for themselves. Each round you BID how many tricks you'll take, then try to make it."],
		["bid", "BIDDING: count your aces, kings and high spades. A bid of 0 is NIL: +50 if you take no tricks at all."],
		["trick_card", "One player leads, everyone plays a card. FOLLOW SUIT if you can (the playable cards glow gold)."],
		["trick_won", "The highest card of the suit led wins the trick, unless someone played a spade: SPADES BEAT EVERYTHING."],
		["spades_broken", "Spades are BROKEN: now they can be led."],
		["round_end", "SCORING: make your bid, 10 a trick plus 1 for each extra. Miss it, -10 a trick. Best score wins the round."],
	],
	"snap": [
		["start", "SNAP. All the cards go face down into everyone's own pile. Nobody looks at theirs."],
		["flip", "On your turn, FLIP your top card onto the middle."],
		["flip:ready=true", "THEY MATCH! The top two cards are the same rank: hit SNAP! Anyone can, any time."],
		["snap:good=true", "SNAP! The first to snap wins every card in the middle."],
		["snap:good=false", "A wrong snap, when they don't match: that costs 1 health!"],
		["round_end", "When every pile's run out, whoever won the most cards wins the round."],
	],
	"president": [
		["start", "PRESIDENT. The aim: be first to get rid of every card. 3 is lowest, then up to K, A, and 2 is highest."],
		["president_play", "The leader plays a single, a pair, three or four of a kind. Everyone after must beat it with the SAME NUMBER of a higher rank."],
		["pass", "Can't beat it, or don't want to? PASS. You sit out until the pile clears."],
		["pile_cleared", "Everyone else passed: the pile clears and the last player to play leads again."],
		["round_end", "First out is PRESIDENT. Whoever's left holding the most is the SCUM."],
		["exchange", "THE SCUM PAYS UP: their best card goes to the President, who hands back their worst."],
	],
	"poker": [
		["start", "POKER: Texas Hold'em, betting SHELLS instead of chips. Everyone gets 2 cards face down."],
		["bet:action=check", "CHECK: stay in without raising."],
		["bet:action=raise", "RAISE: load another shell into the shotgun (up to 3). Everyone still in must CALL it, or fold."],
		["bet:action=call", "CALL: match the raise and stay in."],
		["bet:action=fold", "FOLD: you can't win this round, but you're SAFE. The winner can't shoot you."],
		["board", "Cards in the middle: 3 (the flop), then 1 (the turn), then 1 (the river). Everyone uses them."],
		["round_end", "THE SHOWDOWN: best five-card hand wins, and fires every shell loaded, only at players who stayed in."],
		["end", "From best: straight flush, four of a kind, full house, flush, straight, three of a kind, two pair, a pair, high card."],
	],
}

## The house rules every cartridge shares.
const COMMON := [
	["start", "THE DEALER: the white chip shows who deals. The player to their left goes first, and the deal moves one seat to the right each round."],
	["loot", "ITEMS ARE RARE: nobody starts with any, and only 3 turn up each round. Finding one can change the game."],
	["item_used", "ITEMS: tap one of your items, then USE ITEM. Use as many as you like on your turn, but they don't carry over to the next round."],
	["round_end", "THE SHOTGUN: whoever wins the round is handed it, loaded with shells."],
	["shot", "They pick who to shoot. Each shell takes 1 health, and everyone has 4."],
	["shot:blank=true", "CLICK. A Blank Shell was loaded: that shot does nothing."],
	["eliminated", "Lose all 4 health and you're out. The last one standing walks out the winner."],
	["roulette", "The Revolver: spin it, and 1 time in 6 you lose 2 health."],
	["end", "NORMAL MODE: after 3 shotgun games of a cartridge, NORMAL unlocks: the plain game, no items, no shotgun."],
]

## The last word before the practice.
const PRACTICE := "NOW YOU TRY. Play %d practice rounds against two easy players, with tips on screen."


## The lessons for a cartridge, its own first.
static func for_game(kind: String) -> Array:
	return GAMES.get(kind, []) + COMMON


## Does `trigger` match this event?
static func matches(trigger: String, kind: String, d: Dictionary) -> bool:
	var parts := trigger.split(":", false, 1)
	if parts[0] != kind:
		return false
	if parts.size() < 2:
		return true
	var kv := parts[1].split("=", false, 1)
	if kv.size() < 2:
		return false
	return str(d.get(kv[0], "")).to_lower() == kv[1].to_lower()
