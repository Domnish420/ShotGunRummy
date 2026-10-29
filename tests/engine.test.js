const test = require('node:test');
const assert = require('node:assert/strict');
const E = require('../js/engine.js');
require('../js/items.js');
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
  const g = new E.RummyGame({ seed: 3, items: {} });
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
  // 50 points = 1 + floor(50 / 10), capped at 3 shells
  assert.equal(g.phase, 'shoot');
  assert.deepEqual(g.gun, { holder: p.id, shells: 3 });
});

const item = (id, n = 1) => E.makeItemCard(id, n);

function setupTurn(seed = 4) {
  const g = new E.RummyGame({ seed, items: {} });
  g.startRound();
  const p = g.currentPlayer;
  const opp = g.opponentsOf(p.id)[0];
  return { g, p, opp };
}

test('deck includes item cards', () => {
  const g = new E.RummyGame({ seed: 5 });
  g.startRound();
  const all = g.stock.concat(g.discardPile, ...g.players.map((p) => p.hand));
  const items = all.filter(E.isItem);
  assert.equal(items.length, Object.values(E.defaultItemCounts()).reduce((a, b) => a + b, 0));
  assert.equal(all.length, 52 + items.length);
});

test('items never meld and count 5 deadwood', () => {
  assert.equal(E.meldType([item('beer', 1), item('beer', 2), item('beer', 3)]), null);
  assert.equal(E.meldType(cards('5S 6S').concat(item('saw'))), null);
  const best = E.bestMeldPartition(cards('5S 6S 7S').concat(item('saw')));
  assert.equal(best.deadwoodPoints, 5);
});

test('only one item per turn, usable before drawing', () => {
  const { g, p } = setupTurn();
  p.hp = 3;
  p.hand.push(item('cigarettes', 1), item('cigarettes', 2));
  assert.ok(g.useItem(p.id, 'I-cigarettes-1').ok);
  assert.equal(p.hp, 4);
  assert.equal(g.useItem(p.id, 'I-cigarettes-2').ok, false);
  assert.equal(g.phase, 'draw');
});

test('cigarettes need missing health', () => {
  const { g, p } = setupTurn();
  p.hand.push(item('cigarettes'));
  assert.equal(g.useItem(p.id, 'I-cigarettes-1').ok, false);
});

test('handcuffs skip the opponent turn', () => {
  const { g, p, opp } = setupTurn();
  p.hand.push(item('handcuffs'));
  assert.ok(g.useItem(p.id, 'I-handcuffs-1').ok);
  assert.equal(opp.cuffed, true);
  g.drawFromStock(p.id);
  g.discard(p.id, p.hand[0].id);
  assert.equal(g.currentPlayer.id, p.id);
  assert.equal(opp.cuffed, false);
});

test('magnifier reveals the top of the stock privately, beer burns it', () => {
  const { g, p } = setupTurn();
  p.hand.push(item('magnifier'));
  const top = g.topOfStock;
  const r = g.useItem(p.id, 'I-magnifier-1');
  assert.equal(r.reveal, top);
  assert.equal(r.revealTo, p.id);
  g.itemsUsedThisTurn = 0;
  p.hand.push(item('beer'));
  const b = g.useItem(p.id, 'I-beer-1');
  assert.equal(b.reveal, top);
  assert.notEqual(g.topOfStock, top);
});

test('adrenaline steals a card', () => {
  const { g, p, opp } = setupTurn();
  p.hand.push(item('adrenaline'));
  const before = opp.hand.length;
  const r = g.useItem(p.id, 'I-adrenaline-1');
  assert.ok(r.ok);
  assert.equal(opp.hand.length, before - 1);
  assert.ok(p.hand.includes(r.reveal));
});

test('using your last card as an item goes out', () => {
  const { g, p } = setupTurn();
  p.hp = 2;
  p.hand = [item('cigarettes')];
  g.useItem(p.id, 'I-cigarettes-1');
  assert.equal(g.lastResult.winner, p.id);
});

test('shotgun: winner shoots, saw doubles, death ends the match', () => {
  const { g, p, opp } = setupTurn();
  opp.hp = opp.maxHp = 5;
  p.sawed = true;
  p.hand = cards('2S 3S 4S');
  opp.hand = cards('KH QH KD');
  g.stock.push(c('JD'));
  g.drawFromStock(p.id);
  g.meld(p.id, ['2S', '3S', '4S']);
  g.discard(p.id, 'JD');
  // 30 points, doubled for rummy = 60 → 3 shells (the max)
  assert.equal(g.gun.shells, 3);
  assert.equal(g.shoot(opp.id, p.id).ok, false); // not their gun
  assert.equal(g.shoot(p.id, p.id).ok, false); // no self shots
  assert.equal(g.shoot(p.id, opp.id).damage, 2);
  assert.equal(opp.hp, 3);
  g.shoot(p.id, opp.id);
  g.shoot(p.id, opp.id);
  assert.equal(opp.hp, 1);
  assert.equal(g.phase, 'roundOver');
  assert.equal(g.gun, null);
  assert.ok(g.startRound().ok);
  assert.equal(opp.hp, 1); // health carries over between rounds
  g.damage(opp.id, 1);
  assert.equal(g.phase, 'matchOver');
  assert.equal(g.matchWinner, p.id);
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
    const deckSize = g.stock.length + g.discardPile.length + 20;
    let turns = 0;
    while (g.phase !== 'matchOver') {
      if (g.phase === 'roundOver') {
        g.startRound();
        continue;
      }
      if (g.phase === 'shoot') {
        g.shoot(g.gun.holder, ais[g.gun.holder].chooseTarget());
        continue;
      }
      ais[g.currentPlayer.id].playTurn();
      if (g.phase === 'matchOver') break;
      const total =
        g.stock.length +
        g.discardPile.length +
        g.burned.length +
        g.melds.reduce((s, m) => s + m.cards.length, 0) +
        g.players.reduce((s, p) => s + p.hand.length, 0);
      assert.equal(total, deckSize, `card count drifted (seed ${seed})`);
      for (const m of g.melds) assert.equal(E.meldType(m.cards), m.type);
      assert.ok(++turns < 5000, `match did not finish (seed ${seed})`);
    }
    assert.equal(g.players.filter((p) => p.hp > 0).length, 1);
  }
});
