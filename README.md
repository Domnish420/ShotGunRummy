# Shotgun Rummy

Rummy against The Dealer, in the style of Buckshot Roulette.

## Play

Open `index.html` in a browser. There's nothing to install or build.

(Or run `npm start` and go to http://localhost:8000.)

Sign the waiver, then on your turn:

1. **Draw**: click the stock or the top card of the discard pile.
2. **Meld**: select 3+ cards that make a set (7♠ 7♥ 7♦) or a run (4♥ 5♥ 6♥) and press **MELD**.
3. **Lay off**: select cards that fit a meld already on the table, then click the glowing meld.
4. **Discard**: select one card and press **DISCARD** to end your turn.

Empty your hand to win the round. You score the points left in the Dealer's hand
(A = 1, 2–10 = face value, J/Q/K = 10). Going out in a single turn is **RUMMY** and
scores double. First to 100 wins. The **RULES** button in the game has the full rules.

## Code layout

| File | What it does |
| --- | --- |
| `js/engine.js` | Rummy rules: deck, meld checks, turns, scoring. No DOM, so it can be unit tested. |
| `js/ai.js` | The Dealer's decisions: what to draw, what to meld, and what to discard. |
| `js/ui.js` | Draws the table and connects clicks to the engine. |
| `css/style.css` | The look of the table. |
| `tests/` | Engine tests. Run them with `npm test`. |

The engine emits events (`roundStart`, `turnStart`, `draw`, `meld`, `layoff`,
`discard`, `roundEnd`, `matchEnd`, …) via `game.on(event, fn)`. The shotgun and
abilities will attach to these.

## Roadmap

- [x] Playable Rummy vs. The Dealer
- [ ] The shotgun: lives, a loaded shell sequence, and who pulls the trigger after a round
- [ ] Items and abilities (Buckshot-style consumables)
- [ ] Extra cards (jokers, special cards)
