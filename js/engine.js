/*
 * Shotgun Rummy — core Rummy rules engine.
 *
 * Pure game logic, no DOM. Works in the browser (exposes `window.RummyEngine`)
 * and in Node (module.exports) so it can be unit tested.
 *
 * Rules implemented (classic "Basic Rummy", 2 players):
 *  - 52-card deck, no jokers. Aces are low (A-2-3 is a run, Q-K-A is not).
 *  - Each player is dealt 10 cards. One card is flipped to start the discard pile.
 *  - On your turn: draw one card (stock or top of discard), optionally meld
 *    and/or lay off, then discard one card.
 *  - Melds: a SET is 3-4 cards of the same rank; a RUN is 3+ consecutive cards
 *    of the same suit.
 *  - You may lay off cards onto any meld on the table (yours or your opponent's).
 *  - You can't discard the card you just took from the discard pile
 *    (unless it is the last card in your hand).
 *  - First to empty their hand wins the round (with or without a final discard).
 *  - The winner scores the deadwood left in the opponent's hand:
 *    Ace = 1, 2-10 = face value, J/Q/K = 10. Going out in one turn without
 *    having melded before ("going rummy") doubles the points.
 *  - First to the target score (default 100) wins the match.
 *
 * The game emits events (roundStart, turnStart, draw, meld, layoff, discard,
 * stockReshuffled, roundEnd, matchEnd) — these are the hooks the shotgun /
 * ability layer will attach to later.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.RummyEngine = api;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SUITS = ['S', 'H', 'D', 'C'];
  const SUIT_SYMBOLS = { S: '♠', H: '♥', D: '♦', C: '♣' };
  const RED_SUITS = new Set(['H', 'D']);
  const RANK_LABELS = { 1: 'A', 11: 'J', 12: 'Q', 13: 'K' };

  // ---------------------------------------------------------------- cards

  function rankLabel(rank) {
    return RANK_LABELS[rank] || String(rank);
  }

  function makeCard(rank, suit) {
    return { id: rankLabel(rank) + suit, rank, suit };
  }

  function createDeck() {
    const deck = [];
    for (const suit of SUITS) {
      for (let rank = 1; rank <= 13; rank++) deck.push(makeCard(rank, suit));
    }
    return deck;
  }

  function cardPoints(card) {
    if (card.rank === 1) return 1;
    return Math.min(card.rank, 10);
  }

  function handPoints(cards) {
    return cards.reduce((sum, c) => sum + cardPoints(c), 0);
  }

  function cardName(card) {
    return rankLabel(card.rank) + SUIT_SYMBOLS[card.suit];
  }

  function isRed(card) {
    return RED_SUITS.has(card.suit);
  }

  function compareBySuit(a, b) {
    return SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit) || a.rank - b.rank;
  }

  function compareByRank(a, b) {
    return a.rank - b.rank || SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit);
  }

  // ------------------------------------------------------------------ rng

  /** Small seedable PRNG so games/tests can be reproduced. */
  function createRng(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function shuffle(arr, rng = Math.random) {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  // ---------------------------------------------------------------- melds

  function isSet(cards) {
    if (cards.length < 3 || cards.length > 4) return false;
    const rank = cards[0].rank;
    const suits = new Set();
    for (const c of cards) {
      if (c.rank !== rank) return false;
      suits.add(c.suit);
    }
    return suits.size === cards.length;
  }

  function isRun(cards) {
    if (cards.length < 3) return false;
    const suit = cards[0].suit;
    if (cards.some((c) => c.suit !== suit)) return false;
    const ranks = cards.map((c) => c.rank).sort((a, b) => a - b);
    for (let i = 1; i < ranks.length; i++) {
      if (ranks[i] !== ranks[i - 1] + 1) return false;
    }
    return true;
  }

  /** Returns 'run', 'set' or null. */
  function meldType(cards) {
    if (isRun(cards)) return 'run';
    if (isSet(cards)) return 'set';
    return null;
  }

  function sortMeldCards(cards, type) {
    return cards.slice().sort(type === 'run' ? compareByRank : compareBySuit);
  }

  /** Can `cards` be added to an existing table meld? */
  function canLayOff(meld, cards) {
    if (!cards.length) return false;
    return meldType(meld.cards.concat(cards)) === meld.type;
  }

  /** Every set/run that can be formed from cards in `hand`. */
  function findCandidateMelds(hand) {
    const out = [];

    const byRank = new Map();
    for (const c of hand) {
      if (!byRank.has(c.rank)) byRank.set(c.rank, []);
      byRank.get(c.rank).push(c);
    }
    for (const group of byRank.values()) {
      // dedupe suits in case extra decks ever get added
      const uniq = [...new Map(group.map((c) => [c.suit, c])).values()];
      if (uniq.length >= 3) {
        if (uniq.length === 4) {
          out.push(uniq.slice());
          for (let skip = 0; skip < 4; skip++) out.push(uniq.filter((_, i) => i !== skip));
        } else {
          out.push(uniq.slice());
        }
      }
    }

    for (const suit of SUITS) {
      const cards = hand.filter((c) => c.suit === suit).sort(compareByRank);
      // split into chains of consecutive ranks
      let chain = [];
      const chains = [];
      for (const c of cards) {
        if (chain.length && c.rank === chain[chain.length - 1].rank) continue;
        if (chain.length && c.rank !== chain[chain.length - 1].rank + 1) {
          chains.push(chain);
          chain = [];
        }
        chain.push(c);
      }
      if (chain.length) chains.push(chain);
      for (const ch of chains) {
        for (let i = 0; i < ch.length; i++) {
          for (let j = i + 2; j < ch.length; j++) out.push(ch.slice(i, j + 1));
        }
      }
    }
    return out;
  }

  /**
   * Best way to arrange a hand into melds, minimising deadwood points.
   * Returns { melds: Card[][], deadwood: Card[], deadwoodPoints }.
   */
  function bestMeldPartition(hand) {
    const candidates = findCandidateMelds(hand);
    const index = new Map(hand.map((c, i) => [c.id, i]));
    const masks = candidates.map((m) => m.reduce((mask, c) => mask | (1 << index.get(c.id)), 0));
    const values = candidates.map(handPoints);

    let best = { saved: 0, cards: 0, chosen: [] };
    const chosen = [];
    (function search(start, used, saved, cards) {
      if (saved > best.saved || (saved === best.saved && cards > best.cards)) {
        best = { saved, cards, chosen: chosen.slice() };
      }
      for (let i = start; i < candidates.length; i++) {
        if (masks[i] & used) continue;
        chosen.push(i);
        search(i + 1, used | masks[i], saved + values[i], cards + candidates[i].length);
        chosen.pop();
      }
    })(0, 0, 0, 0);

    const melds = best.chosen.map((i) => candidates[i]);
    const inMeld = new Set(melds.flat().map((c) => c.id));
    const deadwood = hand.filter((c) => !inMeld.has(c.id));
    return { melds, deadwood, deadwoodPoints: handPoints(deadwood) };
  }

  // ----------------------------------------------------------------- game

  const DEFAULT_PLAYERS = [
    { id: 'player', name: 'You' },
    { id: 'dealer', name: 'The Dealer', isAI: true },
  ];

  function ok(extra) {
    return Object.assign({ ok: true }, extra);
  }
  function fail(error) {
    return { ok: false, error };
  }

  class RummyGame {
    constructor(options = {}) {
      this.options = Object.assign(
        { handSize: 10, targetScore: 100, rummyBonus: true, maxReshuffles: 3 },
        options
      );
      this.rng = options.rng || (options.seed != null ? createRng(options.seed) : Math.random);
      this.players = (options.players || DEFAULT_PLAYERS).map((p) =>
        Object.assign({}, p, { hand: [], score: 0, hasMelded: false })
      );
      this.listeners = {};
      this.round = 0;
      // the dealer deals; the player after the dealer goes first
      this.dealerIndex = this.players.length - 1;
      this.turnIndex = 0;
      this.phase = 'idle'; // idle | draw | play | roundOver | matchOver
      this.stock = [];
      this.discardPile = [];
      this.melds = [];
      this.lastResult = null;
      this.matchWinner = null;
      this._meldCounter = 0;
    }

    // ---- events
    on(event, fn) {
      (this.listeners[event] = this.listeners[event] || []).push(fn);
      return () => {
        this.listeners[event] = this.listeners[event].filter((f) => f !== fn);
      };
    }
    emit(event, payload = {}) {
      for (const fn of this.listeners[event] || []) fn(payload, this);
      for (const fn of this.listeners['*'] || []) fn(Object.assign({ event }, payload), this);
    }

    // ---- queries
    get currentPlayer() {
      return this.players[this.turnIndex];
    }
    getPlayer(id) {
      return this.players.find((p) => p.id === id);
    }
    opponentsOf(id) {
      return this.players.filter((p) => p.id !== id);
    }
    get topDiscard() {
      return this.discardPile[this.discardPile.length - 1] || null;
    }
    isTurnOf(id) {
      return (this.phase === 'draw' || this.phase === 'play') && this.currentPlayer.id === id;
    }

    // ---- round lifecycle
    newMatch() {
      for (const p of this.players) p.score = 0;
      this.round = 0;
      this.matchWinner = null;
      this.dealerIndex = this.players.length - 1;
      this.phase = 'idle';
      return this.startRound();
    }

    startRound() {
      if (this.phase === 'matchOver') return fail('The match is over.');
      if (this.phase === 'draw' || this.phase === 'play') return fail('A round is already in progress.');
      this.round++;
      if (this.round > 1) this.dealerIndex = (this.dealerIndex + 1) % this.players.length;

      const deck = shuffle(createDeck(), this.rng);
      for (const p of this.players) {
        p.hand = [];
        p.hasMelded = false;
      }
      for (let i = 0; i < this.options.handSize; i++) {
        for (let k = 1; k <= this.players.length; k++) {
          this.players[(this.dealerIndex + k) % this.players.length].hand.push(deck.pop());
        }
      }
      this.discardPile = [deck.pop()];
      this.stock = deck;
      this.melds = [];
      this.lastResult = null;
      this._reshuffles = 0;
      this.turnIndex = (this.dealerIndex + 1) % this.players.length;
      this.emit('roundStart', { round: this.round, dealer: this.players[this.dealerIndex].id });
      this._beginTurn();
      return ok();
    }

    _beginTurn() {
      const p = this.currentPlayer;
      this.phase = 'draw';
      this.drawnFromDiscard = null;
      this._meldedAtTurnStart = p.hasMelded;
      this.emit('turnStart', { player: p.id });
    }

    _nextTurn() {
      this.turnIndex = (this.turnIndex + 1) % this.players.length;
      this._beginTurn();
    }

    _guard(playerId, phase) {
      if (this.phase === 'roundOver' || this.phase === 'matchOver') return 'The round is over.';
      if (this.currentPlayer.id !== playerId) return "It's not your turn.";
      if (this.phase !== phase) {
        return phase === 'draw' ? 'You already drew this turn.' : 'Draw a card first.';
      }
      return null;
    }

    _cardsFromHand(player, cardIds) {
      if (!cardIds || !cardIds.length) return null;
      if (new Set(cardIds).size !== cardIds.length) return null;
      const cards = cardIds.map((id) => player.hand.find((c) => c.id === id));
      return cards.every(Boolean) ? cards : null;
    }

    _removeFromHand(player, cards) {
      const ids = new Set(cards.map((c) => c.id));
      player.hand = player.hand.filter((c) => !ids.has(c.id));
    }

    // ---- actions (each returns { ok, error? })
    drawFromStock(playerId) {
      const err = this._guard(playerId, 'draw');
      if (err) return fail(err);
      if (!this.stock.length && !this._reshuffleStock()) {
        this._endRound(null, 'The deck ran dry.');
        return ok({ roundOver: true });
      }
      const card = this.stock.pop();
      this.currentPlayer.hand.push(card);
      this.phase = 'play';
      this.emit('draw', { player: playerId, source: 'stock', card });
      return ok({ card });
    }

    drawFromDiscard(playerId) {
      const err = this._guard(playerId, 'draw');
      if (err) return fail(err);
      if (!this.discardPile.length) return fail('The discard pile is empty.');
      const card = this.discardPile.pop();
      this.currentPlayer.hand.push(card);
      this.drawnFromDiscard = card.id;
      this.phase = 'play';
      this.emit('draw', { player: playerId, source: 'discard', card });
      return ok({ card });
    }

    _reshuffleStock() {
      if (this.discardPile.length <= 1 || this._reshuffles >= this.options.maxReshuffles) return false;
      const top = this.discardPile.pop();
      this.stock = shuffle(this.discardPile, this.rng);
      this.discardPile = [top];
      this._reshuffles++;
      this.emit('stockReshuffled', { size: this.stock.length });
      return true;
    }

    meld(playerId, cardIds) {
      const err = this._guard(playerId, 'play');
      if (err) return fail(err);
      const player = this.currentPlayer;
      const cards = this._cardsFromHand(player, cardIds);
      if (!cards) return fail('Those cards are not in your hand.');
      const type = meldType(cards);
      if (!type) return fail('That is not a valid set (3-4 of a rank) or run (3+ in a row, same suit).');
      this._removeFromHand(player, cards);
      const meld = { id: 'm' + ++this._meldCounter, type, cards: sortMeldCards(cards, type), owner: playerId };
      this.melds.push(meld);
      player.hasMelded = true;
      this.emit('meld', { player: playerId, meld, cards });
      this._checkGoneOut(player);
      return ok({ meld });
    }

    layOff(playerId, cardIds, meldId) {
      const err = this._guard(playerId, 'play');
      if (err) return fail(err);
      const player = this.currentPlayer;
      const cards = this._cardsFromHand(player, cardIds);
      if (!cards) return fail('Those cards are not in your hand.');
      const meld = this.melds.find((m) => m.id === meldId);
      if (!meld) return fail('That meld does not exist.');
      if (!canLayOff(meld, cards)) return fail("Those cards don't fit on that meld.");
      this._removeFromHand(player, cards);
      meld.cards = sortMeldCards(meld.cards.concat(cards), meld.type);
      player.hasMelded = true;
      this.emit('layoff', { player: playerId, meld, cards });
      this._checkGoneOut(player);
      return ok({ meld });
    }

    canDiscard(playerId, cardId) {
      const player = this.getPlayer(playerId);
      return !(cardId === this.drawnFromDiscard && player.hand.length > 1);
    }

    discard(playerId, cardId) {
      const err = this._guard(playerId, 'play');
      if (err) return fail(err);
      const player = this.currentPlayer;
      const card = player.hand.find((c) => c.id === cardId);
      if (!card) return fail('That card is not in your hand.');
      if (!this.canDiscard(playerId, cardId)) {
        return fail("You can't discard the card you just picked up from the discard pile.");
      }
      this._removeFromHand(player, [card]);
      this.discardPile.push(card);
      this.emit('discard', { player: playerId, card });
      if (!this._checkGoneOut(player)) this._nextTurn();
      return ok({ card });
    }

    _checkGoneOut(player) {
      if (player.hand.length) return false;
      this._endRound(player);
      return true;
    }

    _endRound(winner, reason) {
      this.phase = 'roundOver';
      const hands = this.players.map((p) => ({
        id: p.id,
        name: p.name,
        cards: p.hand.slice(),
        points: handPoints(p.hand),
      }));
      const result = { round: this.round, winner: winner ? winner.id : null, points: 0, rummy: false, hands, reason };
      if (winner) {
        result.points = hands.filter((h) => h.id !== winner.id).reduce((s, h) => s + h.points, 0);
        if (this.options.rummyBonus && !this._meldedAtTurnStart) {
          result.rummy = true;
          result.points *= 2;
        }
        winner.score += result.points;
      }
      result.scores = Object.fromEntries(this.players.map((p) => [p.id, p.score]));
      this.lastResult = result;
      this.emit('roundEnd', result);

      const champion = this.players.find((p) => p.score >= this.options.targetScore);
      if (champion) {
        this.phase = 'matchOver';
        this.matchWinner = champion.id;
        this.emit('matchEnd', { winner: champion.id, scores: result.scores });
      }
    }
  }

  return {
    SUITS,
    SUIT_SYMBOLS,
    rankLabel,
    makeCard,
    createDeck,
    cardPoints,
    handPoints,
    cardName,
    isRed,
    compareBySuit,
    compareByRank,
    createRng,
    shuffle,
    isSet,
    isRun,
    meldType,
    sortMeldCards,
    canLayOff,
    findCandidateMelds,
    bestMeldPartition,
    RummyGame,
  };
});
