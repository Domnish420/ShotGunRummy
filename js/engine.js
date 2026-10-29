/*
 * Shotgun Rummy — core rules engine.
 *
 * Pure game logic, no DOM. Works in the browser (exposes `window.RummyEngine`)
 * and in Node (module.exports) so it can be unit tested.
 *
 * Rummy (classic "Basic Rummy"):
 *  - 52-card deck with ITEM cards shuffled in (see items.js). Aces are low.
 *  - Each player is dealt 10 cards. One card is flipped to start the discard pile.
 *  - On your turn: draw one card (stock or top of discard), optionally meld,
 *    lay off and use an item, then discard one card.
 *  - Melds: a SET is 3-4 cards of the same rank; a RUN is 3+ consecutive cards
 *    of the same suit. Item cards never go in melds.
 *  - You can't discard the card you just took from the discard pile
 *    (unless it is the last card in your hand).
 *  - First to empty their hand wins the round. The winner scores the deadwood
 *    left in the opponents' hands: Ace = 1, 2-10 = face value, J/Q/K = 10,
 *    item cards = 5. Going out in one turn without having melded before
 *    ("going rummy") doubles the points.
 *
 * Shotgun:
 *  - Every player has 4 health.
 *  - The round winner picks up the shotgun with 1 shell, +1 for every 10 points
 *    scored (max 3). They choose who to shoot, one shell at a time.
 *  - Reach 0 health and you're out. Last one standing wins the match.
 *
 * The game emits events (roundStart, turnStart, turnSkipped, draw, meld, layoff,
 * discard, itemUsed, stockReshuffled, roundEnd, gunAwarded, shot, heal,
 * damage, gunEmpty, matchEnd) so the UI and future systems can react.
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
  const ITEM_DEADWOOD = 5;

  // ----------------------------------------------------------- item registry

  /** Item definitions, filled in by items.js via registerItem(). */
  const ITEMS = {};

  function registerItem(def) {
    ITEMS[def.id] = Object.assign({ copies: 1, phases: ['draw', 'play'] }, def);
  }

  function defaultItemCounts() {
    return Object.fromEntries(Object.values(ITEMS).map((d) => [d.id, d.copies]));
  }

  // ---------------------------------------------------------------- cards

  function rankLabel(rank) {
    return RANK_LABELS[rank] || String(rank);
  }

  function makeCard(rank, suit) {
    return { id: rankLabel(rank) + suit, rank, suit };
  }

  function makeItemCard(itemId, n) {
    return { id: `I-${itemId}-${n}`, kind: 'item', item: itemId };
  }

  function isItem(card) {
    return card.kind === 'item';
  }

  function createDeck() {
    const deck = [];
    for (const suit of SUITS) {
      for (let rank = 1; rank <= 13; rank++) deck.push(makeCard(rank, suit));
    }
    return deck;
  }

  function createItemCards(counts) {
    const cards = [];
    for (const [itemId, count] of Object.entries(counts)) {
      if (!ITEMS[itemId]) throw new Error(`Unknown item: ${itemId}`);
      for (let n = 1; n <= count; n++) cards.push(makeItemCard(itemId, n));
    }
    return cards;
  }

  function cardPoints(card) {
    if (isItem(card)) return ITEM_DEADWOOD;
    if (card.rank === 1) return 1;
    return Math.min(card.rank, 10);
  }

  function handPoints(cards) {
    return cards.reduce((sum, c) => sum + cardPoints(c), 0);
  }

  function cardName(card) {
    if (isItem(card)) return ITEMS[card.item] ? ITEMS[card.item].name : card.item;
    return rankLabel(card.rank) + SUIT_SYMBOLS[card.suit];
  }

  function isRed(card) {
    return !isItem(card) && RED_SUITS.has(card.suit);
  }

  // items always sort after playing cards
  function compareItems(a, b) {
    if (isItem(a) || isItem(b)) {
      if (!isItem(b)) return 1;
      if (!isItem(a)) return -1;
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    }
    return 0;
  }

  function compareBySuit(a, b) {
    return compareItems(a, b) || SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit) || a.rank - b.rank;
  }

  function compareByRank(a, b) {
    return compareItems(a, b) || a.rank - b.rank || SUITS.indexOf(a.suit) - SUITS.indexOf(b.suit);
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
    if (cards.length < 3 || cards.length > 4 || cards.some(isItem)) return false;
    const rank = cards[0].rank;
    const suits = new Set();
    for (const c of cards) {
      if (c.rank !== rank) return false;
      suits.add(c.suit);
    }
    return suits.size === cards.length;
  }

  function isRun(cards) {
    if (cards.length < 3 || cards.some(isItem)) return false;
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
    const playing = hand.filter((c) => !isItem(c));

    const byRank = new Map();
    for (const c of playing) {
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
      const cards = playing.filter((c) => c.suit === suit).sort(compareByRank);
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

  /** Shells earned for winning a round worth `points`. */
  function defaultShells(points) {
    return Math.min(3, 1 + Math.floor(points / 10));
  }

  function ok(extra) {
    return Object.assign({ ok: true }, extra);
  }
  function fail(error) {
    return { ok: false, error };
  }

  class RummyGame {
    constructor(options = {}) {
      this.options = Object.assign(
        {
          handSize: 10,
          rummyBonus: true,
          maxReshuffles: 3,
          maxHp: 4,
          itemsPerTurn: 1,
          items: null, // { itemId: copies }; null = every registered item at its default count
          shellsFor: defaultShells,
        },
        options
      );
      this.rng = options.rng || (options.seed != null ? createRng(options.seed) : Math.random);
      this.players = (options.players || DEFAULT_PLAYERS).map((p) =>
        Object.assign({}, p, { hand: [], score: 0, hasMelded: false })
      );
      this.listeners = {};
      this._resetMatch();
    }

    _resetMatch() {
      for (const p of this.players) {
        p.score = 0;
        p.hp = this.options.maxHp;
        p.maxHp = this.options.maxHp;
        p.cuffed = false;
        p.sawed = false;
      }
      this.round = 0;
      // the dealer deals; the player after the dealer goes first
      this.dealerIndex = this.players.length - 1;
      this.turnIndex = 0;
      this.phase = 'idle'; // idle | draw | play | shoot | roundOver | matchOver
      this.stock = [];
      this.discardPile = [];
      this.burned = [];
      this.melds = [];
      this.gun = null;
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
      return this.players.filter((p) => p.id !== id && p.hp > 0);
    }
    get topDiscard() {
      return this.discardPile[this.discardPile.length - 1] || null;
    }
    get topOfStock() {
      return this.stock[this.stock.length - 1] || null;
    }
    isTurnOf(id) {
      return (this.phase === 'draw' || this.phase === 'play') && this.currentPlayer.id === id;
    }

    // ---- round lifecycle
    newMatch() {
      this._resetMatch();
      return this.startRound();
    }

    startRound() {
      if (this.phase === 'matchOver') return fail('The match is over.');
      if (this.phase !== 'idle' && this.phase !== 'roundOver') return fail('A round is already in progress.');
      this.round++;
      if (this.round > 1) this.dealerIndex = (this.dealerIndex + 1) % this.players.length;

      const items = createItemCards(this.options.items || defaultItemCounts());
      const deck = shuffle(createDeck().concat(items), this.rng);
      for (const p of this.players) {
        p.hand = [];
        p.hasMelded = false;
        p.cuffed = false;
      }
      for (let i = 0; i < this.options.handSize; i++) {
        for (let k = 1; k <= this.players.length; k++) {
          this.players[(this.dealerIndex + k) % this.players.length].hand.push(deck.pop());
        }
      }
      this.discardPile = [deck.pop()];
      this.stock = deck;
      this.burned = [];
      this.melds = [];
      this.gun = null;
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
      this.itemsUsedThisTurn = 0;
      this._meldedAtTurnStart = p.hasMelded;
      this.emit('turnStart', { player: p.id });
    }

    _nextTurn() {
      // skip anyone in handcuffs (they lose one turn, then the cuffs come off)
      for (let i = 0; i < this.players.length; i++) {
        this.turnIndex = (this.turnIndex + 1) % this.players.length;
        const next = this.currentPlayer;
        if (next.hp <= 0) continue;
        if (next.cuffed) {
          next.cuffed = false;
          this.emit('turnSkipped', { player: next.id, reason: 'handcuffs' });
          continue;
        }
        break;
      }
      this._beginTurn();
    }

    _guard(playerId, phase) {
      if (this.phase === 'shoot' || this.phase === 'roundOver' || this.phase === 'matchOver') return 'The round is over.';
      if (this.currentPlayer.id !== playerId) return "It's not your turn.";
      if (phase && this.phase !== phase) {
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

    // ---- rummy actions (each returns { ok, error? })
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
      if (cards.some(isItem)) return fail("Item cards can't be melded. Use them instead.");
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

    // ---- items

    /** Why `cardId` can't be used right now, or null if it can. */
    itemBlocker(playerId, cardId) {
      const err = this._guard(playerId);
      if (err) return err;
      const player = this.currentPlayer;
      const card = player.hand.find((c) => c.id === cardId);
      if (!card) return 'That card is not in your hand.';
      if (!isItem(card)) return "That's not an item.";
      if (this.itemsUsedThisTurn >= this.options.itemsPerTurn) {
        return `You can only use ${this.options.itemsPerTurn} item per turn.`;
      }
      const def = ITEMS[card.item];
      if (!def.phases.includes(this.phase)) {
        return this.phase === 'draw' ? `Draw a card before using ${def.name}.` : `${def.name} must be used before you draw.`;
      }
      if (def.canUse) {
        const reason = def.canUse(this, player);
        if (reason) return reason;
      }
      return null;
    }

    useItem(playerId, cardId) {
      const blocker = this.itemBlocker(playerId, cardId);
      if (blocker) return fail(blocker);
      const player = this.currentPlayer;
      const card = player.hand.find((c) => c.id === cardId);
      const def = ITEMS[card.item];
      this._removeFromHand(player, [card]);
      this.burned.push(card);
      this.itemsUsedThisTurn++;
      // effect: { message, reveal?: Card, revealTo?: playerId }
      const effect = def.use(this, player) || {};
      this.emit('itemUsed', Object.assign({ player: playerId, item: def.id, card }, effect));
      if (this.phase !== 'matchOver') this._checkGoneOut(player);
      return ok(Object.assign({ item: def.id }, effect));
    }

    /** Burns the top card of the stock. Used by items. */
    burnTopOfStock() {
      if (!this.stock.length && !this._reshuffleStock()) return null;
      const card = this.stock.pop();
      this.burned.push(card);
      return card;
    }

    heal(playerId, amount) {
      const p = this.getPlayer(playerId);
      const before = p.hp;
      p.hp = Math.min(p.maxHp, p.hp + amount);
      this.emit('heal', { player: playerId, amount: p.hp - before, hp: p.hp });
      return p.hp - before;
    }

    damage(playerId, amount, source) {
      const p = this.getPlayer(playerId);
      p.hp = Math.max(0, p.hp - amount);
      this.emit('damage', { player: playerId, amount, hp: p.hp, source });
      if (p.hp <= 0) this._checkMatchOver();
      return p.hp;
    }

    _checkMatchOver() {
      const alive = this.players.filter((p) => p.hp > 0);
      if (alive.length > 1) return false;
      this.phase = 'matchOver';
      this.matchWinner = alive.length ? alive[0].id : null;
      this.gun = null;
      this.emit('matchEnd', { winner: this.matchWinner });
      return true;
    }

    _checkGoneOut(player) {
      if (player.hand.length || this.phase === 'matchOver') return false;
      this._endRound(player);
      return true;
    }

    _endRound(winner, reason) {
      const hands = this.players.map((p) => ({
        id: p.id,
        name: p.name,
        cards: p.hand.slice(),
        points: handPoints(p.hand),
      }));
      const result = { round: this.round, winner: winner ? winner.id : null, points: 0, shells: 0, rummy: false, hands, reason };
      if (winner) {
        result.points = hands.filter((h) => h.id !== winner.id).reduce((s, h) => s + h.points, 0);
        if (this.options.rummyBonus && !this._meldedAtTurnStart) {
          result.rummy = true;
          result.points *= 2;
        }
        winner.score += result.points;
        result.shells = this.options.shellsFor(result.points);
      }
      result.scores = Object.fromEntries(this.players.map((p) => [p.id, p.score]));
      this.lastResult = result;

      if (winner && result.shells > 0) {
        this.phase = 'shoot';
        this.gun = { holder: winner.id, shells: result.shells };
      } else {
        this.phase = 'roundOver';
      }
      this.emit('roundEnd', result);
      if (this.gun) this.emit('gunAwarded', { player: winner.id, shells: result.shells });
    }

    // ---- shotgun

    shoot(shooterId, targetId) {
      if (this.phase !== 'shoot' || !this.gun) return fail('Nobody has the shotgun.');
      if (this.gun.holder !== shooterId) return fail("It's not your gun.");
      const target = this.getPlayer(targetId);
      if (!target || target.hp <= 0) return fail('Pick a living target.');
      if (targetId === shooterId) return fail("Don't.");
      const shooter = this.getPlayer(shooterId);
      const dmg = shooter.sawed ? 2 : 1;
      shooter.sawed = false;
      this.gun.shells--;
      this.emit('shot', { shooter: shooterId, target: targetId, damage: dmg, shellsLeft: this.gun.shells });
      this.damage(targetId, dmg, 'shotgun');
      if (this.phase !== 'matchOver' && this.gun.shells <= 0) {
        this.gun = null;
        this.phase = 'roundOver';
        this.emit('gunEmpty', { player: shooterId });
      }
      return ok({ damage: dmg, hp: target.hp });
    }
  }

  return {
    SUITS,
    SUIT_SYMBOLS,
    ITEMS,
    ITEM_DEADWOOD,
    registerItem,
    defaultItemCounts,
    rankLabel,
    makeCard,
    makeItemCard,
    isItem,
    createDeck,
    createItemCards,
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
    defaultShells,
    RummyGame,
  };
});
