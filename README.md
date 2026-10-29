# Shotgun Rummy

Rummy for 2–6 players at a 3D table under a hanging lamp, on one phone or over
the same Wi-Fi. Item cards bend the rules, and whoever goes out picks up the
shotgun.

You sit at the near side of the table with your hand in front of you. Tap
cards to select them, tap the stock or discard pile to draw, and tap a meld on
the table to lay off onto it. The other players sit around the table with
their health and card counts above their heads.

Built with [Godot 4](https://godotengine.org/) (4.4 or newer; the latest 4.x is best).

## Run it on your computer

1. Download Godot 4 (the standard version, not .NET) from https://godotengine.org/download.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ Play button, top right).

The window opens at phone shape (portrait). Under **PASS & PLAY**, untick **HIDE HANDS BETWEEN TURNS**
if you're testing alone and don't want the "pass the phone"
screen between every turn.

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

From the main menu:

- **HOST A LOBBY**: your phone runs the game. Others join, then you press START.
- **JOIN A LOBBY**: lobbies on the same Wi-Fi show up automatically. If none
  appear (some routers and hotspots block this), type the IP address shown on
  the host's screen and press JOIN.
- **PASS & PLAY**: everyone shares one phone.

Every phone needs this project. The host's phone is the referee: other phones
only ever receive their own hand, so nobody can peek. If anyone leaves mid-game,
the game ends for everyone. When exporting an app for Android, tick the
**INTERNET** permission in the export settings.

## How to play

- **The table.** One player deals each round and the player to their left goes
  first. Next round the deal moves one seat to the right, so whoever dealt last
  round goes first.
- **The deal.** Everyone gets 7 playing cards and 2 item cards. The other item
  cards are shuffled into the stock, so a draw can give you an item instead.
- **Your turn.** Draw 1 card (from the stock or the top of the discard pile),
  meld, lay off and use items as much as you like, then **discard 1 card**.
  If the stock gives you an item, keep it and draw again until you get a
  playing card. You can't discard the card you just took from the discard pile.
- **Melds.** A set is 3–4 cards of the same rank. A run is 3+ cards in a row of
  one suit. Aces are low (A-2-3 counts, Q-K-A doesn't). You can lay off onto
  anyone's meld.
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
  you can go out (and when it would be Rummy). Turn them off with HINTS.
- **The shotgun.** The winner gets 1 shell, +1 for every 10 points (max 3), and
  picks who to shoot with each one. Everyone has 4 health. Health carries over
  between rounds. 0 health and you're out. Last one standing wins.

### Items

| Item | What it does |
| --- | --- |
| 🚬 Cigarettes | Gain 1 health. |
| 🍺 Beer | Burn the top card of the stock. Everyone sees it. |
| 🔍 Magnifier | Secretly look at the top card of the stock. |
| ⛓️ Handcuffs | A player of your choice skips their next turn. |
| 🪚 Hand Saw | Your next shotgun shell deals double damage. |
| 📱 Burner Phone | See a random card in another player's hand. |
| 💉 Adrenaline | Steal a random item from another player. |
| 💊 Expired Meds | 50%: gain 2 health. Otherwise lose 1. |

## Code layout

| Path | What it does |
| --- | --- |
| `scripts/core/cards.gd` | Cards, sets, runs, lay-offs, deadwood. |
| `scripts/core/items.gd` | Item list (names, icons, copies). Edit this to tune items. |
| `scripts/core/game.gd` | The full rules: dealing, turns, items, scoring, shotgun, health. No UI, so it can be tested and reused for AI or online play later. |
| `scripts/core/bot.gd` | A simple player the tests use. Starting point for AI players. |
| `scripts/net/session.gd` | Lobbies, Wi-Fi discovery and online play (the host checks every move). |
| `scripts/three/world3d.gd` | The 3D room: table, lamp, players, shotgun, card placement and tap picking. |
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

`tests/net_test.gd` runs a host and two players in one process and plays a
whole 3-player match over the network, checking nobody can see anyone else's
cards:

```
godot --headless --path . -s tests/net_test.gd
```

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
- [ ] Character customisation
- [ ] Online lobbies over the internet
- [ ] Sound effects
- [ ] AI players
- [ ] Extra cards (jokers, special cards)
- [x] 3D table (phone portrait; also works on a PC screen)
- [ ] Polished PC version
