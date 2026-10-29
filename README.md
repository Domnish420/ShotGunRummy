# Shotgun Rummy

Pass-and-play Rummy for 2–6 players on one phone. Item cards bend the rules, and
whoever goes out picks up the shotgun.

Built with [Godot 4](https://godotengine.org/) (4.4 or newer; the latest 4.x is best).

## Run it on your computer

1. Download Godot 4 (the standard version, not .NET) from https://godotengine.org/download.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ Play button, top right).

The window opens at phone shape (portrait). Untick **HIDE HANDS BETWEEN TURNS**
on the setup screen if you're testing alone and don't want the "pass the phone"
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

## How to play

- **The table.** One player deals each round and the player to their left goes
  first. Next round the deal moves one seat to the right, so whoever dealt last
  round goes first.
- **The deal.** Everyone gets 7 playing cards and 2 item cards.
- **Your turn.** Draw 1 card (from the stock or the top of the discard pile),
  meld and lay off as much as you like, use up to **1 item**, then **discard 1
  card**. You can't discard the card you just took from the discard pile.
- **Melds.** A set is 3–4 cards of the same rank. A run is 3+ cards in a row of
  one suit. Aces are low (A-2-3 counts, Q-K-A doesn't). You can lay off onto
  anyone's meld.
- **Going out.** Empty your hand to win the round. You score the cards everyone
  else is still holding (A = 1, 2–10 = face value, J/Q/K = 10). Going out in one
  turn without having melded before is **Rummy** and doubles it.
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
| `scripts/ui/` | Everything on screen: `main.gd` builds the screens, `card_art.gd` draws the cards. |
| `tests/test_runner.gd` | Rules tests. |

Tunable numbers (hand size, health, items per turn, shells) are in `options` at
the top of `game.gd`.

### Running the tests

```
godot --headless --path . --import
godot --headless --path . -s tests/test_runner.gd
```

## Roadmap

- [x] Rummy for 2–6 local players with a rotating dealer
- [x] Item cards, health and the shotgun
- [ ] Sound effects
- [ ] AI players
- [ ] Extra cards (jokers, special cards)
- [ ] 3D PC version
