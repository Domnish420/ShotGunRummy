/*
 * Shotgun Rummy — table UI.
 * Renders the RummyGame state and wires up the player's clicks and the
 * Dealer's paced turns.
 */
(function () {
  'use strict';

  const E = window.RummyEngine;
  const { DealerAI } = window.RummyAI;
  const $ = (id) => document.getElementById(id);

  const PLAYER = 'player';
  const DEALER = 'dealer';
  const DEALER_DELAY = 800;

  const LINES = {
    roundStart: ['Ten cards. Make them count.', 'Another round.', 'Cut. Deal. Begin.', 'Your move.'],
    dealerTakesDiscard: ["I'll take that.", 'Generous of you.', 'Thank you.'],
    dealerMeld: ['Down it goes.', 'Look at that.', 'Mine.'],
    dealerLayoff: ['That fits.', "Don't mind if I do."],
    playerMeld: ['Hm.', 'Lucky.', 'Interesting.', '...'],
    dealerWins: ['The house wins.', 'Pay up.', 'Again?'],
    playerWins: ['...', 'Fine.', 'Enjoy it while it lasts.'],
    dealerTurn: ['...', 'Hmm.', 'Let me see.'],
  };
  const BANNED_NAMES = new Set(['DEALER', 'GOD']);

  let game;
  let ai;
  let playerName = 'YOU';
  let selected = new Set();
  let sortMode = 'suit';
  let hints = true;
  let busy = false;
  let lastDrawnId = null;
  let freshMeldId = null;
  let flash = null;
  let speechTimer = null;

  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ------------------------------------------------------------- dealer voice

  function say(keyOrText) {
    const text = LINES[keyOrText] ? pick(LINES[keyOrText]) : keyOrText;
    const el = $('dealer-speech');
    clearInterval(speechTimer);
    el.textContent = '';
    let i = 0;
    speechTimer = setInterval(() => {
      el.textContent = text.slice(0, ++i);
      if (i >= text.length) clearInterval(speechTimer);
    }, 35);
  }

  // --------------------------------------------------------------------- log

  function log(text, cls = '') {
    const li = document.createElement('li');
    li.textContent = text;
    if (cls) li.className = cls;
    const list = $('log');
    list.prepend(li);
    while (list.children.length > 80) list.lastChild.remove();
  }

  const nameOf = (id) => (id === PLAYER ? playerName : 'DEALER');
  const cardsText = (cards) => cards.map(E.cardName).join(' ');

  function attachLogging() {
    game.on('roundStart', ({ round }) => log(`— ROUND ${round} —`, 'big'));
    game.on('draw', ({ player, source, card }) => {
      if (source === 'discard') log(`${nameOf(player)} takes ${E.cardName(card)} from the discard pile`, player);
      else log(`${nameOf(player)} draws from the stock`, player);
    });
    game.on('meld', ({ player, meld }) => log(`${nameOf(player)} melds ${cardsText(meld.cards)}`, player));
    game.on('layoff', ({ player, cards }) => log(`${nameOf(player)} lays off ${cardsText(cards)}`, player));
    game.on('discard', ({ player, card }) => log(`${nameOf(player)} discards ${E.cardName(card)}`, player));
    game.on('stockReshuffled', () => log('The discard pile is shuffled back into the stock'));
    game.on('roundEnd', (r) => {
      if (!r.winner) log('The deck ran dry. Nobody scores.', 'big');
      else log(`${nameOf(r.winner)} goes out${r.rummy ? ' — RUMMY!' : ''} +${r.points}`, 'big');
    });
    game.on('matchEnd', ({ winner }) => log(`${nameOf(winner)} WINS THE MATCH`, 'big'));
  }

  // ------------------------------------------------------------------ render

  function cardEl(card, { back = false } = {}) {
    const el = document.createElement('div');
    if (back) {
      el.className = 'card back';
      return el;
    }
    el.className = 'card' + (E.isRed(card) ? ' red' : '');
    el.dataset.id = card.id;
    const label = E.rankLabel(card.rank);
    const suit = E.SUIT_SYMBOLS[card.suit];
    el.innerHTML =
      `<span class="corner">${label}<br>${suit}</span>` +
      `<span class="pip">${suit}</span>` +
      `<span class="corner bottom">${label}<br>${suit}</span>`;
    el.setAttribute('aria-label', E.cardName(card));
    return el;
  }

  const playerTurn = (phase) => !busy && game.isTurnOf(PLAYER) && (!phase || game.phase === phase);
  const player = () => game.getPlayer(PLAYER);
  const dealer = () => game.getPlayer(DEALER);

  function selectedCards() {
    return player().hand.filter((c) => selected.has(c.id));
  }

  function render() {
    $('score-player').textContent = `${playerName} ${player().score}`;
    $('score-dealer').textContent = `DEALER ${dealer().score}`;
    $('target-score').textContent = game.options.targetScore;
    $('round-label').textContent = `ROUND ${game.round}`;
    $('player-zone-label').textContent = `${playerName}'S MELDS`;

    // dealer hand (face down)
    const dh = $('dealer-hand');
    dh.replaceChildren(...dealer().hand.map(() => cardEl(null, { back: true })));

    // piles
    const canDraw = playerTurn('draw');
    const stock = $('stock');
    stock.classList.toggle('clickable', canDraw);
    stock.style.visibility = game.stock.length ? 'visible' : 'hidden';
    $('stock-count').textContent = `STOCK ${game.stock.length}`;

    const discardSlot = $('discard');
    discardSlot.replaceChildren();
    const top = game.topDiscard;
    if (top) {
      const el = cardEl(top);
      discardSlot.className = '';
      discardSlot.append(el);
      el.classList.toggle('clickable', canDraw);
    } else {
      discardSlot.className = 'slot';
    }

    // melds
    const sel = selectedCards();
    const canPlay = playerTurn('play');
    for (const owner of [DEALER, PLAYER]) {
      const zone = $('melds-' + owner);
      zone.replaceChildren(
        ...game.melds
          .filter((m) => m.owner === owner)
          .map((m) => {
            const el = document.createElement('div');
            el.className = 'meld';
            el.dataset.meld = m.id;
            if (m.id === freshMeldId) el.classList.add('fresh');
            if (canPlay && sel.length && E.canLayOff(m, sel)) el.classList.add('target');
            el.append(...m.cards.map((c) => cardEl(c)));
            return el;
          })
      );
    }

    // player hand
    const hand = player().hand.slice().sort(sortMode === 'suit' ? E.compareBySuit : E.compareByRank);
    const best = E.bestMeldPartition(player().hand);
    const hintIds = new Set(best.melds.flat().map((c) => c.id));
    for (const c of best.deadwood) {
      if (game.melds.some((m) => E.canLayOff(m, [c]))) hintIds.add(c.id);
    }
    const ph = $('player-hand');
    ph.classList.toggle('active', canPlay);
    ph.replaceChildren(
      ...hand.map((c) => {
        const el = cardEl(c);
        if (selected.has(c.id)) el.classList.add('selected');
        if (hints && hintIds.has(c.id)) el.classList.add('hint');
        if (c.id === lastDrawnId) el.classList.add('new');
        if (canPlay && !game.canDiscard(PLAYER, c.id)) {
          el.classList.add('locked');
          el.title = "You can't discard this card this turn";
        }
        return el;
      })
    );

    // controls
    const meldBtn = $('meld-btn');
    const validMeld = canPlay && sel.length >= 3 && E.meldType(sel) !== null;
    meldBtn.disabled = !validMeld;
    meldBtn.classList.toggle('ready', validMeld);
    $('discard-btn').disabled = !(canPlay && sel.length === 1 && game.canDiscard(PLAYER, sel[0].id));
    $('sort-btn').textContent = `SORT: ${sortMode.toUpperCase()}`;
    $('deadwood').textContent = `DEADWOOD ${best.deadwoodPoints}`;

    // status
    const status = $('status');
    status.classList.toggle('bad', !!flash);
    if (flash) status.textContent = flash;
    else if (game.phase === 'roundOver' || game.phase === 'matchOver') status.textContent = 'ROUND OVER';
    else if (!game.isTurnOf(PLAYER)) status.textContent = 'THE DEALER IS PLAYING...';
    else if (game.phase === 'draw') status.textContent = 'YOUR TURN — DRAW FROM THE STOCK OR THE DISCARD PILE';
    else if (!sel.length) status.textContent = 'SELECT CARDS TO MELD, LAY OFF, OR DISCARD';
    else if (validMeld) status.textContent = 'VALID MELD — PRESS MELD';
    else if (game.melds.some((m) => E.canLayOff(m, sel))) status.textContent = 'CLICK A GLOWING MELD TO LAY OFF';
    else if (sel.length === 1) status.textContent = 'PRESS DISCARD TO END YOUR TURN';
    else status.textContent = 'NOT A VALID MELD';
  }

  // ----------------------------------------------------------------- actions

  function handle(result) {
    flash = result.ok ? null : result.error;
    if (result.ok) selected.clear();
    afterAction();
    return result.ok;
  }

  function afterAction() {
    render();
    if (game.phase === 'roundOver' || game.phase === 'matchOver') {
      setTimeout(showRoundEnd, 600);
    } else if (!busy && game.currentPlayer.id === DEALER) {
      dealerTurn();
    }
  }

  function drawStock() {
    if (!playerTurn('draw')) return;
    const res = game.drawFromStock(PLAYER);
    lastDrawnId = res.card ? res.card.id : null;
    handle(res);
  }

  function drawDiscard() {
    if (!playerTurn('draw') || !game.topDiscard) return;
    const res = game.drawFromDiscard(PLAYER);
    lastDrawnId = res.card ? res.card.id : null;
    handle(res);
  }

  function toggleCard(id) {
    if (!playerTurn('play')) return;
    if (selected.has(id)) selected.delete(id);
    else selected.add(id);
    flash = null;
    lastDrawnId = null;
    render();
  }

  function meldSelected() {
    if (!playerTurn('play')) return;
    const res = game.meld(PLAYER, [...selected]);
    if (res.ok) {
      freshMeldId = res.meld.id;
      if (game.phase === 'play') say('playerMeld');
    }
    handle(res);
  }

  function layOffOn(meldId) {
    if (!playerTurn('play') || !selected.size) return;
    const res = game.layOff(PLAYER, [...selected], meldId);
    freshMeldId = null;
    handle(res);
  }

  function discardSelected() {
    if (!playerTurn('play') || selected.size !== 1) return;
    lastDrawnId = null;
    handle(game.discard(PLAYER, [...selected][0]));
  }

  async function dealerTurn() {
    busy = true;
    freshMeldId = null;
    render();
    if (Math.random() < 0.3) say('dealerTurn');
    await sleep(DEALER_DELAY);

    if (ai.chooseDraw() === 'discard') {
      game.drawFromDiscard(DEALER);
      say('dealerTakesDiscard');
    } else {
      game.drawFromStock(DEALER);
    }
    render();
    await sleep(DEALER_DELAY);

    let play;
    while (game.phase === 'play' && (play = ai.nextPlay())) {
      const res = play.type === 'meld' ? game.meld(DEALER, play.cardIds) : game.layOff(DEALER, play.cardIds, play.meldId);
      if (!res.ok) break;
      freshMeldId = res.meld.id;
      say(play.type === 'meld' ? 'dealerMeld' : 'dealerLayoff');
      render();
      await sleep(DEALER_DELAY);
    }

    if (game.phase === 'play') game.discard(DEALER, ai.chooseDiscard());
    busy = false;
    afterAction();
  }

  // ------------------------------------------------------------------ modals

  function openModal(html, buttonText, onClose) {
    $('modal-body').innerHTML = html;
    const btn = $('modal-btn');
    btn.textContent = buttonText;
    btn.onclick = () => {
      $('modal').classList.add('hidden');
      onClose && onClose();
    };
    $('modal').classList.remove('hidden');
    btn.focus();
  }

  function handRowHtml(cards) {
    const holder = document.createElement('div');
    holder.className = 'hand-row';
    holder.append(...cards.map((c) => cardEl(c)));
    return holder.outerHTML;
  }

  function showRoundEnd() {
    const r = game.lastResult;
    const matchOver = game.phase === 'matchOver';
    let title;
    let cls;
    if (!r.winner) {
      title = 'DEAD DECK';
      cls = '';
    } else if (r.winner === PLAYER) {
      title = matchOver ? 'YOU WALK OUT' : 'YOU GO OUT';
      cls = 'win';
      say('playerWins');
    } else {
      title = matchOver ? 'THE HOUSE WINS' : 'THE DEALER GOES OUT';
      cls = 'lose';
      say('dealerWins');
    }

    let html = `<h2 class="${cls}">${title}</h2>`;
    if (r.winner) {
      html += `<p>${r.rummy ? '<b>RUMMY!</b> Went out in a single turn — points doubled. ' : ''}` + `${nameOf(r.winner)} scores <b>+${r.points}</b>.</p>`;
    } else {
      html += '<p>The stock ran out. Nobody scores this round.</p>';
    }
    for (const h of r.hands) {
      if (h.id === r.winner) continue;
      html += `<p>${nameOf(h.id)} was left holding ${h.points} point${h.points === 1 ? '' : 's'}:</p>`;
      html += handRowHtml(h.cards);
    }
    html += `<p>SCORE — ${playerName} ${r.scores[PLAYER]} · DEALER ${r.scores[DEALER]} (first to ${game.options.targetScore})</p>`;
    if (matchOver) {
      html += game.matchWinner === PLAYER
        ? '<p>The Dealer slides the money across the table.</p>'
        : '<p>The shotgun stays on the wall. For now.</p>';
    }

    openModal(html, matchOver ? 'PLAY AGAIN' : 'NEXT ROUND', () => {
      selected.clear();
      lastDrawnId = null;
      freshMeldId = null;
      flash = null;
      if (matchOver) {
        $('log').replaceChildren();
        game.newMatch();
      } else {
        game.startRound();
      }
      say('roundStart');
      afterAction();
    });
  }

  function showRules() {
    openModal(
      `<h2>RULES</h2>
      <ul>
        <li>You and the Dealer get <b>10 cards</b> each.</li>
        <li>On your turn, <b>draw</b> one card: from the stock (face down) or the top of the discard pile.</li>
        <li><b>Meld</b> if you can: a <b>set</b> is 3–4 cards of the same rank (7♠ 7♥ 7♦), a <b>run</b> is 3+ cards in a row of the same suit (4♥ 5♥ 6♥). Aces are low: A-2-3 counts, Q-K-A doesn't.</li>
        <li><b>Lay off</b> single cards onto any meld already on the table — yours or the Dealer's. Select the cards, then click the glowing meld.</li>
        <li>End your turn by <b>discarding</b> one card. You can't discard the card you just took from the discard pile.</li>
        <li>Empty your hand to <b>go out</b> and win the round. You score the points left in the Dealer's hand: A = 1, 2–10 = face value, J/Q/K = 10.</li>
        <li>Go out in a single turn without having melded before and it's <b>RUMMY</b>: double points.</li>
        <li>First to <b>${game.options.targetScore}</b> wins.</li>
      </ul>
      <p>Underlined cards are part of your best melds (turn off HINTS to hide). DEADWOOD is what you'd lose if the Dealer went out right now.</p>`,
      'BACK'
    );
  }

  // ------------------------------------------------------------------ wiring

  function startGame() {
    game = new E.RummyGame({
      players: [
        { id: PLAYER, name: playerName },
        { id: DEALER, name: 'The Dealer', isAI: true },
      ],
    });
    ai = new DealerAI(game, DEALER);
    attachLogging();
    $('waiver').classList.add('hidden');
    $('table').classList.remove('hidden');
    game.startRound();
    say('roundStart');
    afterAction();
  }

  function sign() {
    const name = $('name-input').value.trim().toUpperCase().replace(/[^A-Z0-9 ]/g, '');
    const err = $('waiver-error');
    if (!name) {
      err.textContent = 'Sign the waiver.';
      return;
    }
    if (BANNED_NAMES.has(name)) {
      err.textContent = 'Nice try.';
      return;
    }
    playerName = name;
    startGame();
  }

  function onActivate(el, fn) {
    el.addEventListener('click', fn);
    el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        fn();
      }
    });
  }

  $('sign-btn').addEventListener('click', sign);
  $('name-input').addEventListener('keydown', (e) => e.key === 'Enter' && sign());
  onActivate($('stock'), drawStock);
  onActivate($('discard'), drawDiscard);
  $('player-hand').addEventListener('click', (e) => {
    const card = e.target.closest('.card');
    if (card) toggleCard(card.dataset.id);
  });
  for (const owner of [DEALER, PLAYER]) {
    $('melds-' + owner).addEventListener('click', (e) => {
      const meld = e.target.closest('.meld');
      if (meld) layOffOn(meld.dataset.meld);
    });
  }
  $('meld-btn').addEventListener('click', meldSelected);
  $('discard-btn').addEventListener('click', discardSelected);
  $('sort-btn').addEventListener('click', () => {
    sortMode = sortMode === 'suit' ? 'rank' : 'suit';
    render();
  });
  $('hint-toggle').addEventListener('change', (e) => {
    hints = e.target.checked;
    render();
  });
  $('rules-btn').addEventListener('click', showRules);
  $('name-input').focus();
})();
