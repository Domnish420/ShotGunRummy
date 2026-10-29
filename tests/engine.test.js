const test = require('node:test');
const assert = require('node:assert/strict');
const E = require('../js/engine.js');
const { DealerAI } = require('../js/ai.js');

const c = (id) => {
  const suit = id.slice(-1);
  const label = id.slice(0, -1);
  const rank = { A: 1, J: 11, Q: 12, K: 13 }[label] || Number(label);
  return E.makeCard(rank, suit);
};
const cards = (ids) => ids.split(' ').map(c);

test('deck has 52 unique cards', () => {
  const deck = E.createDeck();
  assert.equal(deck.length, 52);
  assert.equal(new Set(deck.map((x) => x.id)).size, 52);
});

test('card points', () => {
  assert.equal(E.cardPoints(c('AS')), 1);
  assert.equal(E.cardPoints(c('7H')), 7);
  assert.equal(E.cardPoints(c('KD')), 10);
  assert.equal(E.handPoints(cards('AS 7H KD')), 18);
});

test('sets', () => {
  assert.ok(E.isSet(cards('7S 7H 7D')));
  assert.ok(E.isSet(cards('7S 7H 7D 7C')));
  assert.ok(!E.isSet(cards('7S 7H')));
  assert.ok(!E.isSet(cards('7S 7H 8D')));
});

test('runs (ace low)', () => {
  assert.ok(E.isRun(cards('AS 2S 3S')));
  assert.ok(E.isRun(cards('9H JH 10H QH')));
  assert.ok(!E.isRun(cards('QS KS AS')));
  assert.ok(!E.isRun(cards('4S 5H 6S')));
  assert.ok(!E.isRun(cards('4S 6S 7S')));
  assert.equal(E.meldType(cards('4D 5D 6D')), 'run');
  assert.equal(E.meldType(cards('4D 4S 4C')), 'set');
  assert.equal(E.meldType(cards('4D 5S 6C')), null);
});

test('lay off onto melds', () => {
  const run = { type: 'run', cards: cards('4D 5D 6D') };
  assert.ok(E.canLayOff(run, cards('7D')));
  assert.ok(E.canLayOff(run, cards('3D')));
  assert.ok(E.canLayOff(run, cards('7D 8D')));
  assert.ok(!E.canLayOff(run, cards('8D')));
  const set = { type: 'set', cards: cards('9S 9H 9D') };
  assert.ok(E.canLayOff(set, cards('9C')));
  assert.ok(!E.canLayOff(set, cards('10C')));
});

test('best partition minimises deadwood', () => {
  // 7s can go in the set or the run; best uses 7S in the run 5S-6S-7S and keeps 7H 7D 7C as a set
  const hand = cards('5S 6S 7S 7H 7D 7C KD 2C');
  const best = E.bestMeldPartition(hand);
  assert.equal(best.deadwoodPoints, 12);
  assert.equal(best.melds.length, 2);
  assert.deepEqual(best.deadwood.map((x) => x.id).sort(), ['2C', 'KD']);
});

test('cannot act out of turn or out of phase', () => {
  const g = new E.RummyGame({ seed: 1 });
  g.startRound();
  const first = g.currentPlayer.id;
  const other = g.opponentsOf(first)[0].id;
  assert.equal(g.drawFromStock(other).ok, false);
  assert.equal(g.discard(first, g.currentPlayer.hand[0].id).ok, false); // must draw first
  assert.equal(g.drawFromStock(first).ok, true);
  assert.equal(g.drawFromStock(first).ok, false); // only one draw
});

test('cannot discard the card just taken from the discard pile', () => {
  const g = new E.RummyGame({ seed: 2 });
  g.startRound();
  const p = g.currentPlayer.id;
  const top = g.topDiscard;
  g.drawFromDiscard(p);
  assert.equal(g.discard(p, top.id).ok, false);
  const other = g.currentPlayer.hand.find((x) => x.id !== top.id);
  assert.equal(g.discard(p, other.id).ok, true);
  assert.notEqual(g.currentPlayer.id, p);
});

test('going out scores opponent deadwood, rummy doubles', () => {
  const g = new E.RummyGame({ seed: 3 });
  g.startRound();
  const p = g.currentPlayer;
  const opp = g.opponentsOf(p.id)[0];
  p.hand = cards('2S 3S 4S 9H 9D 9C');
  opp.hand = cards('KH QH 5C');
  g.stock.push(c('JD'));
  g.drawFromStock(p.id);
  assert.ok(g.meld(p.id, ['2S', '3S', '4S']).ok);
  assert.ok(g.meld(p.id, ['9H', '9D', '9C']).ok);
  assert.ok(g.discard(p.id, 'JD').ok);
  assert.equal(g.lastResult.winner, p.id);
  assert.equal(g.lastResult.rummy, true);
  assert.equal(g.lastResult.points, 50); // (10+10+5) * 2
  assert.equal(p.score, 50);
});

test('AI vs AI matches always finish and conserve cards', () => {
  for (let seed = 1; seed <= 40; seed++) {
    const g = new E.RummyGame({
      seed,
      players: [
        { id: 'a', name: 'A' },
        { id: 'b', name: 'B' },
      ],
    });
    const ais = { a: new DealerAI(g, 'a', { rng: E.createRng(seed) }), b: new DealerAI(g, 'b', { rng: E.createRng(seed + 99) }) };
    g.startRound();
    let turns = 0;
    while (g.phase !== 'matchOver') {
      if (g.phase === 'roundOver') {
        g.startRound();
        continue;
      }
      ais[g.currentPlayer.id].playTurn();
      const total =
        g.stock.length + g.discardPile.length + g.melds.reduce((s, m) => s + m.cards.length, 0) + g.players.reduce((s, p) => s + p.hand.length, 0);
      assert.equal(total, 52, `card count drifted (seed ${seed})`);
      for (const m of g.melds) assert.equal(E.meldType(m.cards), m.type);
      assert.ok(++turns < 5000, `match did not finish (seed ${seed})`);
    }
    assert.ok(g.players.some((p) => p.score >= 100));
  }
});
