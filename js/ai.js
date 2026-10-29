/*
 * Shotgun Rummy — The Dealer's brain.
 *
 * The AI is split into small decisions (draw, next play, discard) so the UI
 * can run them one step at a time with pauses, like a dealer thinking.
 */
(function (root, factory) {
  const engine = typeof module === 'object' && module.exports ? require('./engine.js') : root.RummyEngine;
  const api = factory(engine);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.RummyAI = api;
})(typeof self !== 'undefined' ? self : this, function (E) {
  'use strict';

  class DealerAI {
    constructor(game, playerId, options = {}) {
      this.game = game;
      this.playerId = playerId;
      this.rng = options.rng || Math.random;
    }

    get hand() {
      return this.game.getPlayer(this.playerId).hand;
    }

    /** 'discard' if the top discard helps, otherwise 'stock'. */
    chooseDraw() {
      const top = this.game.topDiscard;
      if (!top) return 'stock';
      if (this.game.melds.some((m) => E.canLayOff(m, [top]))) return 'discard';
      const withTop = E.bestMeldPartition(this.hand.concat(top));
      return withTop.deadwood.some((c) => c.id === top.id) ? 'stock' : 'discard';
    }

    /** The next meld / lay-off to make, or null when done. */
    nextPlay() {
      const hand = this.hand;
      const best = E.bestMeldPartition(hand);
      if (best.melds.length) {
        return { type: 'meld', cardIds: best.melds[0].map((c) => c.id) };
      }
      for (const card of hand) {
        const meld = this.game.melds.find((m) => E.canLayOff(m, [card]));
        if (meld) return { type: 'layoff', cardIds: [card.id], meldId: meld.id };
      }
      return null;
    }

    /** Card id to discard: keep the hand with the least deadwood, dump high cards. */
    chooseDiscard() {
      const hand = this.hand;
      const options = hand.filter((c) => this.game.canDiscard(this.playerId, c.id));
      let best = null;
      for (const card of options) {
        const rest = hand.filter((c) => c.id !== card.id);
        let score = E.bestMeldPartition(rest).deadwoodPoints;
        // don't feed the opponent a card that fits a meld on the table
        if (this.game.melds.some((m) => E.canLayOff(m, [card]))) score += 6;
        const tiebreak = -E.cardPoints(card) + this.rng() * 0.5;
        if (!best || score < best.score || (score === best.score && tiebreak < best.tiebreak)) {
          best = { card, score, tiebreak };
        }
      }
      return best.card.id;
    }

    /** Plays a full turn synchronously (used by tests / simulations). */
    playTurn() {
      const g = this.game;
      const res = this.chooseDraw() === 'discard' ? g.drawFromDiscard(this.playerId) : g.drawFromStock(this.playerId);
      if (!res.ok || g.phase !== 'play') return;
      let play;
      while (g.phase === 'play' && (play = this.nextPlay())) {
        const r = play.type === 'meld' ? g.meld(this.playerId, play.cardIds) : g.layOff(this.playerId, play.cardIds, play.meldId);
        if (!r.ok) break;
      }
      if (g.phase === 'play') g.discard(this.playerId, this.chooseDiscard());
    }
  }

  return { DealerAI };
});
