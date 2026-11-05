# Shotgun Party

Party games, starting with a shelf of card games, for 2–6 players at a 3D table under a hanging lamp, on one phone or
over the same Wi-Fi, with AI players to fill the seats. Every game plays by the
same house rules: a dealer that moves round the table, item cards shuffled into
the deck that bend the rules, health, and a shotgun for whoever wins the hand.
Items never carry over: every round deals fresh ones. The shotgun isn't on the
table: the winner is handed it at the end of the round, and it's taken away
once they've fired. Rummy also has its rotating wild **trump** rank (the
other games don't).

- **Rummy**: classic Rummy. Go out first.
- **Blackjack**: everyone against the dealer, who's one of the players.
- **Go Fish**: ask for cards, collect books of four.
- **Cheat**: play cards face down and lie about them. Get caught and
  pick up the pile.
- **Hearts**: don't take hearts, and stay away from the Queen of
  Spades.
- **Spades**: everyone for themselves. Bid your tricks, then make it.
- **Snap**: flip, watch, and snap first. Snap wrong and it hurts.
- **President**: beat the pile or pass. First out is President; the
  Scum pays up next round.
- **Poker**: Texas Hold'em, betting shells instead of chips. Fold and
  you're safe; stay in and you might get shot.

### The room

There's no menu screen: the menu is the room. You stand at the front and
**drag (or swipe) to look around** (arrow keys or A and D on a computer
turn you too). Each station has a sign floating over it; **tap it** (or the
thing itself) and you walk over:

- **PLAY**, the table: the cartridges, then VS AI, pass the phone, host or
  join a lobby.
- **WARDROBE**, on the right wall: its doors swing open and your character
  steps out in front of it to be dressed. Card skins and shotgun skins are in
  here too.
- **BAR**, by the bottle shelf under the pink neon: settings (your name,
  graphics, sound).
- **GACHA**, the machine in the back corner.
- **EXIT**, the door: leave the game, and it swings open as you go.
- **COMPUTER**, the old beige one in the front-left corner, with an arcade
  stick plugged in. It won't boot until you've finished a match of every
  game. Then it takes cheat codes (see below).

### The computer: cheat codes and easter eggs

Type codes on the arcade stick: the d-pad (up, down, left, right) and the
**A** and **B** buttons (on a computer, the arrow keys and A and B work too).
There are 14 codes. Each one unlocks a **secret skin** that never comes out
of the gacha machine (decks, shotguns, hats and outfits), an **easter egg**,
or both. You know the first one already: it's the most famous code in gaming.

**HINTS** has a riddle for every code you haven't found, and the full code
for the ones you have. **EGGS** switches the easter eggs you've found on and
off:

- **DISCO LAMP**: the lamp over the table cycles through the colours.
- **POCKET MODE**: the whole screen in four shades of handheld green.
- **FILM NOIR**: black and white.
- **PARTY POPPERS**: every shotgun blast bursts into confetti.
- **TURBO**: the AIs take their turns twice as fast.

The codes and what they give are in `scripts/core/secrets.gd`.

The room code is in `scripts/three/world3d.gd` (look for "the room"), the
furniture in `scripts/three/props.gd`.

### Shells

Winning a round loads the shotgun with **1 shell**. An instant or perfect win
loads **2**, the most there ever is: a **rummy** (going out in one turn), a
natural **Blackjack** (two shots at the dealer, there and then), **shooting
the moon** in Hearts, making **nil** in Spades, going out in Cheat without
ever being caught lying, more than half the books in Go Fish, more than half
the deck in Snap, going out first in President without passing once, or a
straight flush in Poker. AI players with the gun take turns: each shoots
whoever's been shot the least so far.

### At the table

**Items that need a card** (Joker Paint, Sticky Fingers, ...) don't open a
menu: the cards you can pick glow, and you tap one. Tap the item again, or
CANCEL, to put it away.

**Zoom** in on any part of the table to read it: pinch with two fingers on a
phone, or roll the mouse wheel over the spot on PC. Your hand stays in front of
you while you're zoomed, and the view goes back to your seat when the round
ends or the gun comes out.

**SETTINGS** on the top bar changes graphics, sound, music and hints without
leaving the game; **MENU** pauses (restart, new players, back to the room).
Playing against AIs on one phone, once every person at the table is out the
match ends for you there and then (**YOU'RE OUT**), so there's no watching the
AIs finish it.

### Music

Slow swing jazz plays in the background: the room has its own song, and each
game its own (in its own key and scale), fading over as you sit down at the
table. They're whole songs, so each plays through to its natural ending, takes
a breath and starts again. Turn the music off with **MUSIC** at the bar or in
the in-game MENU (**SOUND** turns everything off).

The songs are in `music/`, named for where they play: `room`, and the game's
name for its table (`rummy`, `blackjack`, `gofish`, `cheat`, `hearts`,
`spades`, `snap`, `president`, `poker`; a game without its own plays the
room's). Drop in `.ogg`, `.mp3` or `.wav` files with those names
and open the project in Godot once to import them.

If there are no recordings at all, a made-in-code stand-in plays instead:
the tune is written out note by note in `scripts/audio/saloon.gd`, and
`godot --headless --path . -s tools/make_music.gd` renders it into `music/`.

### Cartridges

Each game is a cartridge in the style of the early-2000s handhelds: a big
wide plastic cart with its title drawn like a handheld game logo. Tapping the
**table** in the room brings them up in front of you: swipe (or tap the arrows) to
scroll through them. Each one ticks past and plays its own little tune (made
in code for now, in `scripts/audio/chiptune.gd`, until the real music). The
words float instead of sitting in boxes: **PLAY** slots the cartridge into
the console in the middle of the table and asks how you want to play (VS AI,
pass the phone, host or join); **DEMO** teaches it. **SHOTGUN / NORMAL** picks
the mode. In a lobby the host taps the cartridge to change it. A white
**DEALER** chip on the table shows who deals.

### Normal mode and demos

- **Normal mode** is the plain card game: no items, no health, no shotgun. Win
  rounds instead; the first to 3 takes the match. It unlocks for a cartridge
  after you've finished 3 shotgun games of it.
- **The DEMO** teaches each game. First it plays itself (every seat, yours
  too, slowed down, and the same game every time) and explains each rule the
  moment it comes up: a card pops up at the top, the game waits, and it moves
  on by itself or when you tap NEXT. It's played in shotgun mode, so items and
  the shotgun get explained too. After the watched round, any rule that didn't
  come up gets its card, then you play 3 practice rounds against two easy
  players with tips on screen. The game offers one the first time you open it.
  Every game's lessons, and when they pop up, are in `scripts/ui/demo_lessons.gd`.

## Graphics

The look is late PS2 / early PS3: the 3D table is drawn at low resolution and
scaled up with crisp pixels, then a post-processing shader adds ordered
dithering, film grain, a warm colour grade and a vignette. The lamp throws a
visible cone of light with dust in it, and there's fog. Textures are small and
gritty on purpose; they're generated by `tools/make_textures.py`.

The players are animated characters from the free **KayKit Character Packs**
by Kay Lousberg (CC0, www.kaylousberg.com): adventurers and skeletons who sit
and fidget at the table, stand up and cheer when they win a round, and keel
over when they're knocked out. They live in `models/characters/`.

### Characters

The **wardrobe** in the room opens character select: a grid of the 19
ready-made characters (The Gambler, The Undertaker, The Cowpoke, The Dealer…),
then any you've made, then a **+** box. The **+** opens the creator: name your
character and pick from 9 bodies, 8 outfit colours, 7 hats (their own, bowler,
top hat, cowboy hat, flat cap, beanie, none), 5 face pieces (cigarette, cigar,
eyepatch, shades, none) and glowing eyes. Your own characters can be edited or
deleted. For the face piece you also pick **which side** (the eye the patch
covers, the corner of the mouth the cigarette sits in), its **angle** (how
the cigarette droops, how steep the strap runs, the glasses' tilt) and its
**height**.

**Face anchors.** Face pieces don't sit at fixed spots: each model has
anchors measured off its real head by `tools/make_face_anchors.gd` (eyes,
the rims round them, nose, brow, mouth corners, crown, ears, and the head's
outline all the way round at several heights), saved in
`models/characters/face_anchors.json`. Every cosmetic sits on those, so it
rests on the surface instead of floating or sinking in, straps and glasses'
arms follow the shape of the head, and a new model only needs the tool run
once (`godot --headless --path . -s tools/make_face_anchors.gd`). Points can
be nudged by hand in the JSON. Whoever you play as is saved, and other players see them at the
table, online too. In pass & play each player picks a
character on the setup screen. Presets and parts are in `scripts/core/looks.gd`.

### The gacha machine

Every round you win gives you a **gacha coin**, and winning the match gives
one more (you start with 3). The **gacha machine** in the room's corner walks you over
to the machine in the corner of the room (`scripts/three/gacha3d.gd`). You
do it by hand: **drag the coin** into the slot, **turn the crank** by
dragging round in circles (twice round; every quarter turn clicks and the
capsules tumble in the globe), and a capsule drops down the chute into the
tray as the camera closes in. **Tap it** to crack it open: rarer prizes take
more taps, and it wobbles harder each time before it pops in a flash of its
rarity's colour. **AUTO** does the lot for you. Inside is a card skin, a shotgun skin or a costume part you
don't have yet (never a repeat). Every step has its own sound. Prizes
are Common, Rare, Epic or Legendary; rarer ones drop less often. Odds,
coins and what's inside are in `scripts/core/gacha.gd`.

**Shotgun skins** (Standard Issue, Rust Bucket, Blackout, Swamp Camo, Chrome,
Bone Saw, Candy Stripe, Blood Orange, Neon Nights, Toxic, Solid Gold) are
picked from **SHOTGUN** in the wardrobe. Retro shotguns nod to famous games
too (Test Subject, Gravity Beam, Phys Beam, Block Blaster, Boomstick, Plumber
Red, Speed Blue, Light Gun), and so do retro costume pieces: the Pumpkin Head,
Miner's Helmet, Gnome Cap, Royale Crown and Party Chat headset, the Plumber's
Tash and HUD Visor, and the Hazard Orange, Overall Blue, Creep Green and Ghost
Pink outfits. Every retro prize comes with its bit of gaming history. Whoever holds the gun shows their skin,
so everyone at the table sees it, online too (`scripts/core/gun_skins.gd`).

### Your name, unlocks and card skins

The first time the game opens it asks **WHO'S PLAYING?**: sign your name
once and it's kept (change it from the character screen's **NAME** button).

**Unlocks.** Some bodies, hats, face pieces, outfit colours, the glowing eyes,
most card skins and the shotgun skins start locked (🔒): they come out of the
gacha machine, and each lock says how rare it is. Ready-made characters that
use a locked part are locked too. Anything you'd already unlocked from your
stats before the machine arrived is yours to keep.

**Card skins.** **CARDS** in the wardrobe picks how your cards look, front
and back. 16 skins: Classic, Casino Felt, Candy Corn, Blood Money (shotgun
shells), Barbed Wire, Pumpkin, Midnight (stars and a moon), Bone Yard
(skulls), Noir, Rave (neon), Blueprint, Wanted (a bullseye), Spider Web,
Hazard, Pocket (an old handheld's green screen) and High Roller (gold).

**Retro decks.** 24 more skins nod to famous games without using their
names, logos or characters: Overworld (grass blocks), Diamond Ore, Lava
Depths, Test Chamber (orange and blue portals), Crowbar, Missing Texture,
Dust Crates, Team Colours, Shareware (floppy disks), Cheat Code (↑↑↓↓←→←→BA),
Gold Rings, Brick and Coin, Maze Dots, Alien Wave, Line Clear, Gold
Cartridge, Dungeon Crawl, Paddle Ball, Checkered Flag, Three Hearts,
Harvest, First Aid, Fireball and Bunny Hop. Unlocking one shows a bit of real
gaming history about the game it nods to. Every card's face carries a faint
copy of its back's pattern, so both sides match. It's just for you:
everyone at the table sees their own skin. Skins are in
`scripts/ui/card_skins.gd`, drawn by `scripts/ui/card_art.gd`.

Change the sharpness under **GRAPHICS** at the bar or the in-game MENU:
**PS2** (chunkiest), **PS3** (default) or **SHARP** (full resolution, no
dithering).

## Run it on your computer

1. Download Godot 4 (the standard version, not .NET) from https://godotengine.org/download.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ Play button, top right).

The window opens at phone shape (portrait). To try it alone, use
**PLAY ON THIS PHONE → VS AI (SOLO)**.

## Build a Windows .exe or a web version

`export_presets.cfg` has two ready-made exports (Godot's export templates
need installing once: **Editor → Manage Export Templates → Download**):

- **Windows Desktop**: one `ShotgunParty.exe` with everything packed inside.
  **Project → Export → Windows Desktop → Export Project**, or
  `godot --headless --export-release "Windows Desktop" build/windows/ShotgunParty.exe`
- **Web**: for itch.io and other sites that run games in the browser.
  `godot --headless --export-release "Web" build/web/index.html`, then zip
  what's in `build/web/` and upload it. Browsers can't open the connections
  Wi-Fi lobbies use, so the web version is solo and pass & play only (the
  lobby buttons are hidden there).

## Run it on your phone

**Android, quickest:** turn on Developer options and USB debugging on the phone,
plug it in, then in Godot: **Editor → Manage Export Templates → Download**,
**Project → Export → Add… → Android**, and use the Android button (one-click
deploy) at the top right of the editor. Godot will tell you if it needs the
Android SDK or a Java JDK. The guide is at
https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html

**iPhone:** exporting needs a Mac with Xcode. See
https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html

## Playing together

From the room (tap the table):

- **HOST A LOBBY**: your phone runs the game. Others join, then you press START.
- **JOIN A LOBBY**: lobbies on the same Wi-Fi show up automatically. If none
  appear (some routers and hotspots block this), type the IP address shown on
  the host's screen and press JOIN.
- **PLAY ON THIS PHONE**:
  - **VS AI (SOLO)**: just you against 1–5 AI players. Pick how many and how
    good they are (easy, normal, hard, or mixed for one of each), then
    **DEAL ME IN**. You play as your own name and character.
  - **PASS THE PHONE**: friends share one phone and take turns. Any seat can
    be an AI too.

### AI players

Play them on your own with **VS AI (SOLO)**, or mix them in with people. In
**PASS THE PHONE**, tap the **PERSON** button next to a
player to change it to **AI: EASY**, **AI: NORMAL** or **AI: HARD** (player 1
is always you). In a lobby the host taps **+ ADD AN AI PLAYER**, then the level
button to change it or **X** to remove it. Online, the host's phone plays the
AIs, so it has to stay in the game.

- **Easy** draws without much thought, often throws away the wrong card and
  uses items at random.
- **Normal** plays its cards well and uses items when they help: cigarettes when
  it's hurt, handcuffs on whoever is closest to going out, Joker Paint when it
  makes a meld.
- **Hard** also holds its melds back to go out in one turn for Rummy, won't
  throw the next player a card that fits the table, and shoots whoever is
  winning (or whoever one shot would knock out).

An AI only knows what its seat would know: its own hand, the table, cards shown
by Spotlight or Flashbang, and the top of the stock if it used a magnifier. The
AIs play one move at a time so you can watch them. If you're playing alone
against AIs, your hand is never hidden. With two or more people, the phone asks
to be passed only when it's the next person's turn.

Every phone needs this project. The host's phone is the referee: other phones
only ever receive their own hand, so nobody can peek. If anyone leaves mid-game,
the game ends for everyone. When exporting an app for Android, tick the
**INTERNET** permission in the export settings.

## How to play Rummy

- **The table.** One player deals each round and the player to their left goes
  first. Next round the deal moves one seat to the right, so whoever dealt last
  round goes first.
- **The deal.** Everyone gets 7 playing cards. Nobody starts with items: a random
  handful (sometimes none, sometimes lots) are shuffled into the stock each
  round, so a draw can now and then give you an item instead.
- **Your turn.** Draw 1 card (from the stock or the top of the discard pile),
  meld, lay off and use items as much as you like, then **discard 1 card**.
  If the stock gives you an item, keep it and draw again until you get a
  playing card. You can't discard the card you just took from the discard pile.
- **Melds.** A set is 3–4 cards of the same rank. A run is 3+ cards in a row of
  one suit. Aces are low (A-2-3 counts, Q-K-A doesn't). Once you've put down a
  meld of your own this round, you can lay off onto anyone's meld.
- **Going out.** Empty your hand of playing cards to win the round (items don't count). You score the cards everyone
  else is still holding (A = 1, 2–10 = face value, J/Q/K = 10). Going out in one
  turn without having melded before is **Rummy** and doubles it.
- **Trump cards.** Each round one rank is wild: aces in round 1, 2s in round 2,
  and so on up to kings in round 13, then back to aces. A trump card (gold star)
  can stand in for any card of any suit in any set or run, so in round 1
  2♣ 3♣ A♦ 5♣ is a run.
- **Swapping a trump.** If a meld on the table has a trump in it and you hold
  the real card it stands for, swap it in and take the trump, but only if you
  meld the trump straight away with 2+ of your own cards.
- **First turn.** Nobody can put cards down on their first turn of a round.
- **No discarding trumps.** Trump cards can't be discarded (unless you hold
  nothing but trumps). The round's trump is shown on the table.
- **Hints.** A gold outline means a card makes a meld in your hand, a gold
  underline means it fits a meld on the table, and a gold banner tells you when
  you can go out (and when it would be Rummy). Turn them off in SETTINGS.
- **The shotgun.** The winner gets 1 shell (2 for a **rummy**, going out in one turn), and
  shoots someone with each one: no buttons, just **tap (or click) the person**
  you want to shoot (a red marker floats over everyone you can). Everyone has 4 health. Health carries over
  between rounds. 0 health and you're out. Last one standing wins.

## How to play Blackjack

- **The table.** One player is the dealer, and everyone else plays against
  them. The player to the dealer's left goes first, play goes round to the
  left, and the dealer plays last. Each round the deal moves one seat to the
  right, just like Rummy.
- **The deal.** Everyone gets 2 cards, one face down and one face up.
  A random few rare items are shuffled into the stock, and one card is burned face up onto
  the discard pile. The deck is
  shuffled fresh every round.
- **Your turn.** **HIT** (or tap the stock) to take a card, as often as you
  like, then **STAND**. Use items any time in your turn. Draw an item and you
  keep it and draw again.
- **Counting.** 2–10 count their number, J/Q/K 10, an ace 1 or 11. Over 21 and
  you're **bust**. Reaching 21 or 5 cards stands for you.
- **Trump cards.** The same rotating trump as Rummy (aces in round 1, then
  twos…). A trump counts as whatever you need, from 1 to 11.
- **Against the dealer.** Bust and you lose. If the dealer busts, everyone
  still in wins. Otherwise the better hand wins: a **Blackjack** (21 with your
  first 2 cards) beats a **five-card Charlie** (5 cards without going bust),
  which beats the higher total. The same hand is a push. If every player
  busts, the dealer wins without playing.
- **Blackjack shoots.** The moment you have a Blackjack, you shoot the
  dealer twice, free (no shells used), unless the dealer has a Blackjack too.
- **A Blackjack protects you.** Holding one, nobody can shoot you that round,
  not even a dealer with a Blackjack of their own.
- **The shotgun.** The dealer gets 1 shell for every player who lost (2 at most)
  and taps who to shoot, but only players who lost. Beat the dealer or push
  and you're safe.
- **Items.** The same items, adapted where they need to be: the Burner Phone
  sees someone's face-down card, Spotlight and Flashbang turn face-down cards
  up, Double Down deals a player one more card right now (even if they've
  stood), Shakedown makes someone throw away their last card, Handcuffs make
  someone who hasn't played yet stand on what they have, the Revolver makes
  someone take a card or spin, Sticky Fingers steals a face-up card, Dumpster
  Dive takes the top of the discard pile, and Joker Paint makes a card wild
  for the round. Garbage Day isn't in the Blackjack deck. The in-game RULES
  list shows each one.

## How to play Go Fish

- **The deal.** 7 cards each (5 with 4 or more players). The rest
  of the cards and the items are the **pond**.
- **Your turn.** Tap a card to pick its rank, then **ASK** a player for it. If
  they have any, they hand them all over and you go again. If not, **go fish**:
  draw from the pond. Draw the rank you asked for and you go again. Draw an
  item and you keep it and draw again.
- **Books.** Four of a kind goes down in front of you by itself. Trumps are
  wild for books (three of a rank and a trump, or two and two trumps). Nobody
  can ask for the trump rank, and trumps are never handed over.
- **The end.** The round ends when someone has to fish and the pond is empty.
  Most books wins: 1 shell, or 2 for more than half the books.
- **Items.** Shakedown throws a card back in the pond, Sticky Fingers steals a
  card from someone's book (the rest goes back in their hand), the Revolver
  makes someone get a card off another player or spin. Double Down fishes 2
  cards, Dumpster Dive digs the pond for a card that matches your hand, and
  Garbage Day makes someone throw their hand back and fish a new one.

## How to play Cheat

- **The deal.** All 52 cards are dealt out. Catch a liar to get an item.
- **Your turn.** Cards go down in order: aces, then twos, up to kings, then
  round again. Tap 1 to 4 cards and **PLAY** them face down as the rank that's
  due. You can lie.
- **CHEAT!** Before you play you can call **CHEAT!** on the player before you.
  If any of their cards isn't what they said, they pick up the whole pile and
  you get an item. If they told the truth, you pick it up.
- **Trumps** always count as the rank you said: they're never a lie.
- **Winning.** Play your last card and you win, unless the next player calls
  CHEAT! and catches you. The winner gets 1 shell, or 2 for going out without
  ever being caught lying.
- **Items.** The magnifier peeks at the last play (it shows you a lie if there
  is one), Shakedown makes someone take 3 cards off the bottom of the pile,
  Garbage Day makes someone pick up the whole pile, Sticky Fingers slips the
  top card into your hand, Double Down makes someone put down 2+ cards, and the
  Revolver makes a caught liar spin as well.

## How to play Hearts and Spades

Both are trick-taking games. The cards are dealt out evenly (any left over are
set aside). Winning a trick can find an item. The player left of the dealer leads; everyone
plays one card, following the suit that was led if they can (playable cards
glow gold), and the highest card of that suit takes the trick (aces high). The
round's **trump rank is wild**: a trump can be played any time and wins the
trick (the first one played, if there's more than one).

- **Hearts.** Each heart taken is 1 point, the Queen of Spades 13; fewest
  points wins. Hearts can't be led until one has been played. Taking the Queen
  of Spades costs **1 health** on the spot. Take every point card and you
  **shoot the moon**: an instant win with 2 shells. Otherwise the winner
  gets 1 shell.
- **Spades.** Everyone plays for themselves (2–6 players). Before the first
  trick everyone **bids** how many tricks they'll take (0 is nil). Spades beat
  the other suits and can't be led until one has been played. Make your bid:
  10 a trick, +1 for each extra; miss it: −10 a trick; nil: ±50. Best round
  score wins, with 1 shell, or 2 for making a nil bid.
- **Items.** Every trick needs a card from everyone, so here the items swap
  cards rather than add or take them. The Revolver makes someone spin if they
  win the next trick, Double Down makes someone play their highest card next
  and Handcuffs their lowest. Sticky Fingers swaps a card out of the trick,
  Dumpster Dive digs the best card out of the last one, and Garbage Day dumps
  your worst point card on someone (Hearts) or gives away a trick (Spades).

## How to play Snap

- **The deal.** All the cards go face down into everyone's own pile, with the
  a random few rare items shuffled in. Nobody looks at their pile.
- **Your turn.** **FLIP** your top card onto the middle (or tap your pile).
  Flip an item and you keep it and flip again.
- **The middle** isn't on the table, where it'd be too small to see: every
  card flipped shows big over the table, turning over next to the one it lands
  on (a 2 next to a 2), then the old one fades.
- **SNAP!** When the top two cards in the middle match (same rank, or either
  is a trump), anyone can press **SNAP!** at any time. First to snap wins the
  middle. The AIs snap too: easy ones take about 4 seconds, normal about 2½,
  hard about 1½. While a match is showing, the AIs wait before flipping again
  so everyone gets their chance.
- **Wrong snaps** cost 1 health (in normal mode, 2 cards from your pile go in
  the middle).
- **The end.** When every pile has run out there's one last chance to snap,
  then **COUNT UP**: most cards won takes the shotgun: 1 shell, or 2 for winning
  more than half the deck.
- **On one phone**, whoever grabs it first presses SNAP! and says who they are.
- **Items.** The magnifier and the phone peek at the next card in a pile,
  Sticky Fingers steals 3 won cards, Double Down makes someone flip 2, and
  Joker Paint turns the top card wild: a snap for whoever's quickest.

## How to play President

- **The deal.** All the cards are dealt out. Clearing the pile can find an item. 3 is low, then
  up to K, A, and 2 is high.
- **Playing.** The leader plays a single, a pair, three or four of a kind.
  Going round, each player beats it with the same number of a higher rank, or
  **PASS**es (and sits out until the pile clears). When everyone else has
  passed, the last player to play leads again.
- **President.** First out wins, with 1 shell, or 2 for going out without
  passing once. Whoever's left holding the most is the **Scum**: next round they hand the
  President their best card and get the worst one back.

## How to play Poker

- **The deal.** Texas Hold'em: 2 cards face down each. Items turn up as loot. Five
  cards go face up in the middle: the flop (3), the turn (1) and the river (1),
  with a round of betting before each and after the last.
- **Betting shells.** There are no chips. **CHECK**, or **RAISE** to load
  another shell into the shotgun (2 at most). Once someone raises, everyone else
  still in **CALL**s it or **FOLD**s.
- **Fold and you're safe**: you can't win, but the winner can't shoot you.
- **The hand book.** Tap **HAND BOOK** under your buttons for every hand from
  best to worst, with an example of each and a marker on the one you're
  holding right now. It floats over the table, and the game carries on.
- **Winning.** Best five-card hand from your two and the five in the middle.
  The winner fires every shell that was loaded, only at players who stayed in;
  a straight flush loads both, whatever was bet.
- **Items.** The magnifier peeks at the next card for the middle, Beer burns
  it, Spotlight turns someone's cards up, Double Down stops someone folding,
  the Revolver makes a folder spin, Shakedown swaps one of someone's cards
  for a new one.

Every item can turn up in every game (Tarot and Joker Paint are about trumps,
so they're Rummy only). Each game has its own version where it needs one: the
card on an item always says what it does in the game you're playing.

### Items (Rummy)

Items are rare and it's all luck: nobody is dealt any, and every item card
has its own small chance of turning up each round (about 3 on average; some
rounds have none, some have loads). Finding one can change the game.
Use as many as you like on your turn. Copies are in brackets; tune them in
`scripts/core/items.gd`.

| Item | What it does |
| --- | --- |
| 🚬 Cigarettes (2) | Gain 1 health. |
| 💊 Expired Meds (1) | 50%: gain 2 health. Otherwise lose 1. |
| 🪚 Hand Saw (2) | Your next shotgun shell deals double damage. |
| 🍺 Beer (2) | Burn the top card of the stock. Everyone sees it. |
| 🔍 Magnifier (2) | Secretly look at the top card of the stock. |
| 📱 Burner Phone (1) | See a random card in another player's hand. |
| ⛓️ Handcuffs (2) | A player of your choice skips their next turn. |
| 💉 Adrenaline (1) | Steal a random item from another player. |
| 👊 Shakedown (1) | A player of your choice discards a random card (never their last). |
| 🔄 Switcheroo (1) | Swap your whole hand with another player's. |
| 🤝 Bad Trade (1) | Swap 2 random cards with another player. |
| 🌀 Chaos (1) | Everyone passes their whole hand to the player on their left. |
| ✋ Sticky Fingers (2) | Steal a card from a meld (it must stay a meld). A meld left with 2 cards goes to the discard pile. |
| 🗑️ Dumpster Dive (1) | Take the top 3 cards of the discard pile. |
| 🚮 Garbage Day (1) | A player of your choice takes the whole discard pile. |
| 🔦 Spotlight (1) | A player's whole hand is shown to everyone until their next turn ends. |
| 💥 Flashbang (1) | Every other player shows 2 random cards until their next turn ends. |
| 🎯 Blank Shell (1) | Very rare. Slips a blank into the shotgun: the next shot fired does no damage. In every game. |
| 🔫 Revolver (1) | A player must put cards down on their next turn, or play Russian roulette (1 in 6: lose 2 health). |
| 🎲 Double Down (1) | A player must draw 2 cards on their next turn, from either pile. |
| 🔮 Tarot Card (1) | The trump moves to the next rank for the rest of the round. Melds on the table keep their trumps. |
| 🎭 Joker Paint (2) | A card in your hand is a trump until your turn ends. Meld it to keep it wild. |

## Code layout

| Path | What it does |
| --- | --- |
| `scripts/core/cards.gd` | Cards, sets, runs, lay-offs, deadwood. |
| `scripts/core/items.gd` | Item list (names, icons, copies). Edit this to tune items. |
| `scripts/core/game.gd` | Rummy's rules: dealing, turns, items, scoring, shotgun, health. No UI, so it's tested on its own. |
| `scripts/core/blackjack.gd` | Blackjack's rules. Builds on `game.gd` for the players, items, health and shotgun. |
| `scripts/core/blackjack_bot.gd` | The Blackjack AI. |
| `scripts/core/gofish.gd`, `gofish_bot.gd` | Go Fish's rules and AI. |
| `scripts/core/cheat.gd`, `cheat_bot.gd` | Cheat's rules and AI. |
| `scripts/core/tricks.gd`, `hearts.gd`, `spades.gd`, `tricks_bot.gd` | Trick-taking, Hearts and Spades, and their AI. |
| `scripts/core/snap.gd`, `snap_bot.gd` | Snap's rules and AI (main.gd times the AIs' snaps). |
| `scripts/core/president.gd`, `president_bot.gd` | President's rules and AI. |
| `scripts/core/poker.gd`, `poker_bot.gd` | Poker's rules (with the hand rankings) and AI. |
| `scripts/audio/chiptune.gd` | Every sound and jingle, made in code (stand-ins for the real audio). |
| `scripts/core/games.gd` | The cartridges: every game, its colour, and normal mode. |
| `scripts/ui/modes/` | Each newer game's table screen (buttons, taps, results, rules, tutorial tips). |
| `scripts/core/bot.gd` | The AI players (easy, normal, hard): one move at a time, using the same actions as a person. |
| `scripts/net/session.gd` | Lobbies, Wi-Fi discovery and online play (the host checks every move). |
| `scripts/three/world3d.gd` | The 3D room: table, lamp, players, shotgun, card placement and tap picking. |
| `scripts/three/props.gd` | The low-poly models: room, furniture, the seated characters, shotgun. |
| `models/characters/` | Character models (KayKit, CC0), slimmed with `tools/slim_models.mjs`. |
| `shaders/` | The post-processing look and the lamp's light cone. |
| `scripts/three/card3d.gd`, `card_textures.gd` | A 3D card, and the card faces (drawn once at startup from the 2D card art). |
| `scripts/ui/` | Menus, buttons and pop-ups over the 3D view: `main.gd` builds the screens, `card_art.gd` draws card faces. |
| `tests/test_runner.gd` | Rules tests. |

Tunable numbers (hand size, health, items per turn, shells) are in `options` at
the top of `game.gd`.

### Running the tests

```
godot --headless --path . --import
godot --headless --path . -s tests/test_runner.gd
```

`tests/net_test.gd` runs a host, two players and an AI in one process and
plays a whole 4-player match of each game over the network, checking nobody
can see anyone else's cards:

```
godot --headless --path . -s tests/net_test.gd
```

`tests/ui_games_check.gd` plays each newer cartridge solo through the real
screens, a shotgun match and then its tutorial:

```
godot --headless --path . -s tests/ui_games_check.gd
```

`tests/ui_demo_check.gd` watches every cartridge's demo and checks every
rule gets explained:

```
godot --headless --path . -s tests/ui_demo_check.gd
```

`tests/ui_blackjack_check.gd` plays Blackjack solo against two AIs
through the real screens:

```
godot --headless --path . -s tests/ui_blackjack_check.gd
```

`tests/ui_ai_check.gd` plays a pass & play match of one person against three
AIs through the real screens:

```
godot --headless --path . -s tests/ui_ai_check.gd
```

`tests/ui_room_check.gd` walks the room (looking round, tapping every station
and coming back) and `tests/ui_gacha_check.gd` spins the gacha machine by hand
and with AUTO.

`tests/ui_smoke.gd` plays a whole 3-player match through the real screens and
can save screenshots (needs a window, so leave off `--headless`):

```
godot --path . -s tests/ui_smoke.gd -- --shots=/tmp/shots
```

## Roadmap

- [x] Rummy for 2–6 local players with a rotating dealer
- [x] Item cards, health and the shotgun
- [x] Trump cards and gold hints
- [x] Main menu, lobbies on the same Wi-Fi
- [x] Character customisation
- [ ] Online lobbies over the internet
- [x] Sound effects for everything: every item, every game's big moments,
  turns, taps and menus (made in code in `scripts/audio/chiptune.gd` for
  now; swap in real recordings before release)
- [x] AI players (easy, normal, hard)
- [ ] Voice chat (once there's internet play)
- [x] Blackjack
- [ ] More card games
- [ ] Extra cards (jokers, special cards)
- [x] 3D table (phone portrait; also works on a PC screen)
- [ ] Polished PC version
