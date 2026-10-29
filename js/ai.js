/*
 * Shotgun Rummy — The Dealer's brain.
 *
 * The AI is split into small decisions (item, draw, next play, discard, target)
 * so the UI can run them one step at a time with pauses, like a dealer thinking.
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
      this.peeked = null; // card seen on top of the stock with the magnifier
      game.on('itemUsed', (e) => {
        if (e.player === this.playerId && e.item === 'magnifier') this.peeked = e.reveal;
      });
      game.on('turnStart', () => {
        this.peeked = null;
      });
    }

    get me() {
      return this.game.getPlayer(this.playerId);
    }

    get hand() {
      return this.me.hand;
    }

    _helps(card) {
      if (E.isItem(card)) return false;
      if (this.game.melds.some((m) => E.canLayOff(m, [card]))) return true;
      const withCard = E.bestMeldPartition(this.hand.concat(card));
      return !withCard.deadwood.some((c) => c.id === card.id);
    }

    /** Item card id to use now, or null. Called in the draw phase. */
    chooseItem() {
      const g = this.game;
      const me = this.me;
      const items = this.hand.filter((c) => E.isItem(c) && !g.itemBlocker(this.playerId, c.id));
      if (!items.length) return null;
      const opp = g.opponentsOf(this.playerId)[0];
      const has = (id) => items.find((c) => c.item === id);
      const pick = (id) => has(id) && has(id).id;

      if (me.hp <= me.maxHp - 2 && me.hp >= 2 && has('medicine')) return pick('medicine');
      if (me.hp < me.maxHp && has('cigarettes')) return pick('cigarettes');
      if (has('saw')) return pick('saw');
      if (opp && opp.hand.length <= 6 && has('handcuffs')) return pick('handcuffs');
      if (opp && opp.hand.length <= 6 && has('adrenaline')) return pick('adrenaline');
      if (has('magnifier')) return pick('magnifier');
      if (has('phone')) return pick('phone');
      if (has('beer') && this.rng() < 0.5) return pick('beer');
      return null;
    }

    /** 'discard' if the top discard helps, otherwise 'stock'. */
    chooseDraw() {
      const top = this.game.topDiscard;
      const peek = this.peeked && this.peeked === this.game.topOfStock ? this.peeked : null;
      if (peek && this._helps(peek)) return 'stock';
      if (!top) return 'stock';
      if (E.isItem(top)) {
        // only grab items it would use right away next turn
        return top.item === 'cigarettes' && this.me.hp < this.me.maxHp ? 'discard' : 'stock';
      }
      return this._helps(top) ? 'discard' : 'stock';
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
        // don't hand over good items
        if (E.isItem(card) && card.item !== 'beer') score += 4;
        const tiebreak = -E.cardPoints(card) + this.rng() * 0.5;
        if (!best || score < best.score || (score === best.score && tiebreak < best.tiebreak)) {
          best = { card, score, tiebreak };
        }
      }
      return best.card.id;
    }

    /** Who to shoot: the weakest living opponent. */
    chooseTarget() {
      const opps = this.game.opponentsOf(this.playerId);
      return opps.sort((a, b) => a.hp - b.hp)[0].id;
    }

    /** Plays a full turn synchronously (used by tests / simulations). */
    playTurn() {
      const g = this.game;
      const item = this.chooseItem();
      if (item) g.useItem(this.playerId, item);
      if (!g.isTurnOf(this.playerId)) return;
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
