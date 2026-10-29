/*
 * Shotgun Rummy — item cards.
 *
 * Items are shuffled into the deck with the playing cards. Draw one and it goes
 * in your hand. On your turn you can use one item (before or after drawing),
 * or discard it like any other card (and maybe hand it to your opponent).
 * Items can't be melded and count 5 points of deadwood if you get caught
 * holding them.
 *
 * To add an item, call registerItem with:
 *   id       unique key
 *   name     shown on the card
 *   icon     emoji/glyph shown on the card
 *   text     one-line rules text
 *   copies   how many are shuffled into the deck
 *   phases   when it can be used: 'draw' (before drawing) and/or 'play'
 *   canUse   (game, player) => reason it can't be used, or null
 *   use      (game, player) => effect data passed along with the itemUsed event.
 *            Put a card in `reveal` and set `revealTo` ('all' or a player id)
 *            to show it to someone.
 *   log      (effect, nameOf) => text for the game log
 */
(function (root, factory) {
  const engine = typeof module === 'object' && module.exports ? require('./engine.js') : root.RummyEngine;
  factory(engine);
  if (typeof module === 'object' && module.exports) module.exports = engine.ITEMS;
})(typeof self !== 'undefined' ? self : this, function (E) {
  'use strict';

  /** The next living opponent in turn order. */
  function nextOpponent(game, player) {
    const n = game.players.length;
    const start = game.players.indexOf(player);
    for (let k = 1; k < n; k++) {
      const p = game.players[(start + k) % n];
      if (p.hp > 0) return p;
    }
    return null;
  }

  E.registerItem({
    id: 'cigarettes',
    name: 'Cigarettes',
    icon: '🚬',
    text: 'Gain 1 health.',
    copies: 2,
    canUse: (g, p) => (p.hp >= p.maxHp ? "You're already at full health." : null),
    use: (g, p) => ({ healed: g.heal(p.id, 1) }),
    log: (e, n) => `${n(e.player)} lights a cigarette. +1 health`,
  });

  E.registerItem({
    id: 'beer',
    name: 'Beer',
    icon: '🍺',
    text: 'Burn the top card of the stock. Everyone sees it.',
    copies: 2,
    canUse: (g) => (g.stock.length || g.discardPile.length > 1 ? null : 'The stock is empty.'),
    use: (g) => {
      const card = g.burnTopOfStock();
      return { reveal: card, revealTo: 'all' };
    },
    log: (e, n) => `${n(e.player)} cracks a beer and burns ${e.reveal ? E.cardName(e.reveal) : 'nothing'} off the stock`,
  });

  E.registerItem({
    id: 'magnifier',
    name: 'Magnifier',
    icon: '🔍',
    text: 'Secretly look at the top card of the stock.',
    copies: 2,
    canUse: (g) => (g.stock.length ? null : 'The stock is empty.'),
    use: (g, p) => ({ reveal: g.topOfStock, revealTo: p.id }),
    log: (e, n) => `${n(e.player)} peeks at the top of the stock`,
  });

  E.registerItem({
    id: 'handcuffs',
    name: 'Handcuffs',
    icon: '⛓️',
    text: 'Your opponent skips their next turn.',
    copies: 1,
    canUse: (g, p) => {
      const o = nextOpponent(g, p);
      return !o ? 'No one to cuff.' : o.cuffed ? 'They are already cuffed.' : null;
    },
    use: (g, p) => {
      const o = nextOpponent(g, p);
      o.cuffed = true;
      return { target: o.id };
    },
    log: (e, n) => `${n(e.player)} handcuffs ${n(e.target)}. They skip a turn`,
  });

  E.registerItem({
    id: 'saw',
    name: 'Hand Saw',
    icon: '🪚',
    text: 'Your next shotgun shell deals double damage.',
    copies: 1,
    canUse: (g, p) => (p.sawed ? 'Your barrel is already sawn off.' : null),
    use: (g, p) => {
      p.sawed = true;
      return {};
    },
    log: (e, n) => `${n(e.player)} saws off the barrel. Next shell hits for 2`,
  });

  E.registerItem({
    id: 'phone',
    name: 'Burner Phone',
    icon: '📱',
    text: "See a random card in your opponent's hand.",
    copies: 1,
    canUse: (g, p) => {
      const o = nextOpponent(g, p);
      return o && o.hand.length ? null : 'Their hand is empty.';
    },
    use: (g, p) => {
      const o = nextOpponent(g, p);
      const card = o.hand[Math.floor(g.rng() * o.hand.length)];
      return { target: o.id, reveal: card, revealTo: p.id };
    },
    log: (e, n) => `${n(e.player)} makes a call about ${n(e.target)}'s hand`,
  });

  E.registerItem({
    id: 'adrenaline',
    name: 'Adrenaline',
    icon: '💉',
    text: "Steal a random card from your opponent's hand.",
    copies: 1,
    canUse: (g, p) => {
      const o = nextOpponent(g, p);
      return o && o.hand.length >= 2 ? null : 'They have too few cards to steal from.';
    },
    use: (g, p) => {
      const o = nextOpponent(g, p);
      const card = o.hand[Math.floor(g.rng() * o.hand.length)];
      o.hand = o.hand.filter((c) => c !== card);
      p.hand.push(card);
      return { target: o.id, reveal: card, revealTo: 'all' };
    },
    log: (e, n) => `${n(e.player)} snatches ${E.cardName(e.reveal)} from ${n(e.target)}`,
  });

  E.registerItem({
    id: 'medicine',
    name: 'Expired Meds',
    icon: '💊',
    text: '50% chance: gain 2 health. Otherwise lose 1.',
    copies: 1,
    use: (g, p) => {
      if (g.rng() < 0.5) return { lucky: true, healed: g.heal(p.id, 2) };
      g.damage(p.id, 1, 'medicine');
      return { lucky: false };
    },
    log: (e, n) => (e.lucky ? `${n(e.player)} swallows the pills. +2 health` : `${n(e.player)} swallows the pills. They were bad. -1 health`),
  });

  E.nextOpponent = nextOpponent;
});
