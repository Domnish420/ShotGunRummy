/*
 * Shotgun Rummy — table UI (phone first).
 * Renders the RummyGame state, wires up taps, paces the Dealer's turns and
 * runs the shotgun scene between rounds.
 */
(function () {
  'use strict';

  const E = window.RummyEngine;
  const { DealerAI } = window.RummyAI;
  const SFX = window.SFX;
  const $ = (id) => document.getElementById(id);

  const PLAYER = 'player';
  const DEALER = 'dealer';
  const DEALER_DELAY = 750;

  const LINES = {
    roundStart: ['Ten cards. Make them count.', 'Another round.', 'Cut. Deal. Begin.', 'Your move.'],
    dealerTakesDiscard: ["I'll take that.", 'Generous of you.', 'Thank you.'],
    dealerMeld: ['Down it goes.', 'Look at that.', 'Mine.'],
    dealerLayoff: ['That fits.', "Don't mind if I do."],
    dealerItem: ['Let me try something.', 'Watch this.', 'Hm.'],
    playerMeld: ['Hm.', 'Lucky.', 'Interesting.', '...'],
    playerItem: ['Cute.', 'Is that so.', '...'],
    dealerWins: ['The house wins.', 'Pay up.', 'Stand still.'],
    playerWins: ['...', 'Fine.', 'Go on then.'],
    dealerTurn: ['...', 'Hmm.', 'Let me see.'],
    skipped: ['Sit tight.', 'Comfortable?', 'Hands where I can see them.'],
    dealerShoots: ['Nothing personal.', 'Hold still.', 'This will sting.'],
    dealerHit: ['...!', 'Hah.', 'You will regret that.'],
  };
  const BANNED_NAMES = new Set(['DEALER', 'GOD']);

  const store = {
    get(k) {
      try {
        return localStorage.getItem('sgr.' + k);
      } catch (e) {
        return null;
      }
    },
    set(k, v) {
      try {
        localStorage.setItem('sgr.' + k, v);
      } catch (e) {
        /* storage unavailable */
      }
    },
  };

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
  let shownResultRound = 0;
  let inGunScene = false;
  let logEntries = [];
  let pendingReveals = [];

  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const nameOf = (id) => (id === PLAYER ? playerName : 'THE DEALER');
  const cardsText = (cards) => cards.map(E.cardName).join(' ');
  const player = () => game.getPlayer(PLAYER);
  const dealer = () => game.getPlayer(DEALER);
  const playerTurn = (phase) => !busy && !inGunScene && game.isTurnOf(PLAYER) && (!phase || game.phase === phase);

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
    logEntries.unshift({ text, cls });
    if (logEntries.length > 120) logEntries.pop();
  }

  function effects(kind) {
    const f = $('flash');
    f.className = 'flash' + (kind === 'red' ? ' red' : '');
    void f.offsetWidth; // restart the animation
    f.classList.add('on');
    document.body.classList.remove('shake');
    void document.body.offsetWidth;
    document.body.classList.add('shake');
    if (navigator.vibrate) navigator.vibrate(kind === 'red' ? [120, 40, 200] : 150);
  }

  function attachEvents() {
    game.on('roundStart', ({ round }) => log(`— ROUND ${round} —`, 'big'));
    game.on('draw', ({ player: p, source, card }) => {
      SFX.card();
      if (source === 'discard') log(`${nameOf(p)} takes ${E.cardName(card)} from the discard pile`, p);
      else log(`${nameOf(p)} draws from the stock`, p);
    });
    game.on('meld', ({ player: p, meld }) => {
      SFX.meld();
      log(`${nameOf(p)} melds ${cardsText(meld.cards)}`, p);
    });
    game.on('layoff', ({ player: p, cards }) => {
      SFX.meld();
      log(`${nameOf(p)} lays off ${cardsText(cards)}`, p);
    });
    game.on('discard', ({ player: p, card }) => {
      SFX.card();
      log(`${nameOf(p)} discards ${E.cardName(card)}`, p);
    });
    game.on('turnSkipped', ({ player: p }) => {
      log(`${nameOf(p)} is in handcuffs and skips a turn`, 'big');
      if (p === PLAYER) say('skipped');
    });
    game.on('stockReshuffled', () => log('The discard pile is shuffled back into the stock'));
    game.on('itemUsed', (e) => {
      SFX.item();
      const def = E.ITEMS[e.item];
      log(def.log(e, nameOf), e.player);
      pendingReveals.push(itemReveal(e, def));
    });
    game.on('heal', ({ amount }) => amount && SFX.heal());
    game.on('damage', ({ player: p }) => {
      SFX.hurt();
      const bar = $('hp-' + p);
      bar.classList.remove('hit');
      void bar.offsetWidth;
      bar.classList.add('hit');
      if (p === PLAYER) effects('red');
    });
    game.on('roundEnd', (r) => {
      if (!r.winner) log('The deck ran dry. Nobody scores.', 'big');
      else log(`${nameOf(r.winner)} goes out${r.rummy ? ' — RUMMY!' : ''} +${r.points}. ${r.shells} shell${r.shells === 1 ? '' : 's'}`, 'big');
    });
    game.on('shot', ({ shooter, target, damage }) => log(`${nameOf(shooter)} shoots ${nameOf(target)}. -${damage}`, 'big'));
    game.on('matchEnd', ({ winner }) => log(`${nameOf(winner)} WALKS OUT`, 'big'));
  }

  /** What the player gets to see when an item is used. */
  function itemReveal(e, def) {
    const visible = e.reveal && (e.revealTo === 'all' || e.revealTo === PLAYER);
    const who = e.player === PLAYER ? 'YOU USE' : 'THE DEALER USES';
    let text = def.log(e, nameOf);
    if (visible && e.item === 'magnifier') text = 'Top of the stock:';
    if (visible && e.item === 'phone') text = 'The Dealer is holding:';
    return {
      title: `${who} ${def.name.toUpperCase()}`,
      card: visible ? e.reveal : e.card,
      text,
      auto: e.player === PLAYER ? 0 : 2200,
    };
  }

  // ------------------------------------------------------------------ render

  function cardEl(card, { back = false } = {}) {
    const el = document.createElement('div');
    if (back) {
      el.className = 'card back';
      return el;
    }
    el.dataset.id = card.id;
    if (E.isItem(card)) {
      const def = E.ITEMS[card.item];
      el.className = 'card itemcard';
      el.innerHTML =
        `<span class="corner">${def.icon}</span>` +
        `<span class="icon">${def.icon}</span><span class="iname">${def.name.toUpperCase()}</span>`;
      el.setAttribute('aria-label', `${def.name}: ${def.text}`);
      return el;
    }
    el.className = 'card' + (E.isRed(card) ? ' red' : '');
    const label = E.rankLabel(card.rank);
    const suit = E.SUIT_SYMBOLS[card.suit];
    el.innerHTML =
      `<span class="corner">${label}<br>${suit}</span>` +
      `<span class="pip">${suit}</span>` +
      `<span class="corner bottom">${label}<br>${suit}</span>`;
    el.setAttribute('aria-label', E.cardName(card));
    return el;
  }

  function hpHtml(p) {
    let html = '';
    for (let i = 0; i < p.maxHp; i++) html += `<span class="seg${i < p.hp ? ' full' : ''}"></span>`;
    return html;
  }

  function flagsText(p) {
    return (p.cuffed ? '⛓️' : '') + (p.sawed ? '🪚' : '');
  }

  function selectedCards() {
    return player().hand.filter((c) => selected.has(c.id));
  }

  function layoutHand(el, count) {
    const cards = el.children;
    if (!cards.length) return;
    const cw = cards[0].offsetWidth;
    const avail = el.clientWidth;
    const step = count > 1 ? Math.min(cw + 6, (avail - cw) / (count - 1)) : 0;
    for (let i = 1; i < cards.length; i++) cards[i].style.marginLeft = `${step - cw}px`;
  }

  function render() {
    $('round-label').textContent = `ROUND ${game.round}`;
    $('player-name').textContent = playerName;
    $('player-zone-label').textContent = playerName;
    $('hp-player').innerHTML = hpHtml(player());
    $('hp-dealer').innerHTML = hpHtml(dealer());
    $('player-flags').textContent = flagsText(player());
    $('dealer-flags').textContent = flagsText(dealer());

    $('dealer-hand').replaceChildren(...dealer().hand.map(() => cardEl(null, { back: true })));

    // piles
    const canDraw = playerTurn('draw');
    const stock = $('stock');
    stock.classList.toggle('clickable', canDraw);
    stock.classList.toggle('empty', !game.stock.length);
    $('stock-count').textContent = game.stock.length ? `STOCK ${game.stock.length}` : 'SHUFFLE';

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
      $('melds-' + owner).replaceChildren(
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
      if (!E.isItem(c) && game.melds.some((m) => E.canLayOff(m, [c]))) hintIds.add(c.id);
    }
    const ph = $('player-hand');
    const active = playerTurn();
    ph.classList.toggle('active', active);
    ph.replaceChildren(
      ...hand.map((c) => {
        const el = cardEl(c);
        if (selected.has(c.id)) el.classList.add('selected');
        if (hints && hintIds.has(c.id)) el.classList.add('hint');
        if (c.id === lastDrawnId) el.classList.add('new');
        if (canPlay && !game.canDiscard(PLAYER, c.id)) el.classList.add('locked');
        return el;
      })
    );
    layoutHand(ph, hand.length);

    // controls
    const validMeld = canPlay && sel.length >= 3 && E.meldType(sel) !== null;
    const meldBtn = $('meld-btn');
    meldBtn.disabled = !validMeld;
    meldBtn.classList.toggle('ready', validMeld);
    const oneItem = sel.length === 1 && E.isItem(sel[0]) ? sel[0] : null;
    const itemBlocked = oneItem ? game.itemBlocker(PLAYER, oneItem.id) : 'no item';
    $('use-btn').disabled = !(active && oneItem && !itemBlocked);
    $('discard-btn').disabled = !(canPlay && sel.length === 1 && game.canDiscard(PLAYER, sel[0].id));
    $('sort-btn').textContent = `SORT: ${sortMode.toUpperCase()}`;
    $('deadwood').textContent = `DEADWOOD ${best.deadwoodPoints}`;

    // status
    const status = $('status');
    status.classList.toggle('bad', !!flash);
    let text;
    if (flash) text = flash;
    else if (game.phase === 'shoot' || game.phase === 'roundOver') text = 'ROUND OVER';
    else if (game.phase === 'matchOver') text = 'IT IS OVER';
    else if (!game.isTurnOf(PLAYER)) text = 'THE DEALER IS PLAYING...';
    else if (oneItem) {
      const def = E.ITEMS[oneItem.item];
      text = `${def.name.toUpperCase()}: ${def.text}` + (itemBlocked ? ` (${itemBlocked})` : '');
    } else if (game.phase === 'draw') text = 'YOUR TURN — TAP THE STOCK OR THE DISCARD PILE';
    else if (!sel.length) text = 'SELECT CARDS TO MELD, LAY OFF, OR DISCARD';
    else if (validMeld) text = 'VALID MELD — PRESS MELD';
    else if (canPlay && game.melds.some((m) => E.canLayOff(m, sel))) text = 'TAP A GLOWING MELD TO LAY OFF';
    else if (sel.length === 1) text = 'PRESS DISCARD TO END YOUR TURN';
    else text = 'NOT A VALID MELD';
    status.textContent = text;
  }

  // ----------------------------------------------------------------- reveals

  function showReveal({ title, card, text, auto }) {
    return new Promise((resolve) => {
      const box = $('reveal');
      $('reveal-title').textContent = title;
      $('reveal-card').replaceChildren(cardEl(card));
      $('reveal-text').textContent = text;
      box.classList.remove('hidden');
      let timer = null;
      const done = () => {
        clearTimeout(timer);
        box.classList.add('hidden');
        box.onclick = null;
        resolve();
      };
      box.onclick = done;
      if (auto) timer = setTimeout(done, auto);
    });
  }

  async function flushReveals() {
    while (pendingReveals.length) await showReveal(pendingReveals.shift());
  }

  // ----------------------------------------------------------------- actions

  async function handle(result) {
    flash = result.ok ? null : result.error;
    if (result.ok) selected.clear();
    render();
    if (pendingReveals.length) {
      busy = true;
      await flushReveals();
      busy = false;
    }
    afterAction();
    return result.ok;
  }

  function afterAction() {
    render();
    if (inGunScene) return;
    if (game.phase === 'matchOver' && !game.gun) {
      setTimeout(showMatchEnd, 500);
    } else if ((game.phase === 'shoot' || game.phase === 'roundOver') && shownResultRound !== game.round) {
      shownResultRound = game.round;
      setTimeout(showRoundEnd, 600);
    } else if (!busy && game.isTurnOf(DEALER)) {
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
    if (!playerTurn()) return;
    const card = player().hand.find((c) => c.id === id);
    if (game.phase === 'draw' && !E.isItem(card)) {
      flash = 'DRAW A CARD FIRST (YOU CAN USE AN ITEM BEFORE DRAWING)';
      render();
      return;
    }
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

  function useSelected() {
    if (!playerTurn() || selected.size !== 1) return;
    const res = game.useItem(PLAYER, [...selected][0]);
    if (res.ok && Math.random() < 0.5) say('playerItem');
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

    const item = ai.chooseItem();
    if (item) {
      say('dealerItem');
      game.useItem(DEALER, item);
      render();
      await flushReveals();
    }

    if (game.isTurnOf(DEALER)) {
      if (ai.chooseDraw() === 'discard') {
        game.drawFromDiscard(DEALER);
        say('dealerTakesDiscard');
      } else {
        game.drawFromStock(DEALER);
      }
      render();
      await sleep(DEALER_DELAY);
    }

    let play;
    while (game.isTurnOf(DEALER) && game.phase === 'play' && (play = ai.nextPlay())) {
      const res = play.type === 'meld' ? game.meld(DEALER, play.cardIds) : game.layOff(DEALER, play.cardIds, play.meldId);
      if (!res.ok) break;
      freshMeldId = res.meld.id;
      say(play.type === 'meld' ? 'dealerMeld' : 'dealerLayoff');
      render();
      await sleep(DEALER_DELAY);
    }

    if (game.isTurnOf(DEALER) && game.phase === 'play') game.discard(DEALER, ai.chooseDiscard());
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
    $('modal').querySelector('.modal-box').scrollTop = 0;
  }

  function handRowHtml(cards) {
    const holder = document.createElement('div');
    holder.className = 'hand-row';
    holder.append(...cards.map((c) => cardEl(c)));
    return holder.outerHTML;
  }

  function showRoundEnd() {
    const r = game.lastResult;
    let title;
    let cls = '';
    if (!r.winner) {
      title = 'DEAD DECK';
    } else if (r.winner === PLAYER) {
      title = 'YOU GO OUT';
      cls = 'win';
      say('playerWins');
    } else {
      title = 'THE DEALER GOES OUT';
      cls = 'lose';
      say('dealerWins');
    }

    let html = `<h2 class="${cls}">${title}</h2>`;
    if (r.winner) {
      html += `<p>${r.rummy ? '<b>RUMMY!</b> Out in a single turn — points doubled. ' : ''}${nameOf(r.winner)} scores <b>${r.points}</b> points.</p>`;
      html += `<p>That's <b>${r.shells} shell${r.shells === 1 ? '' : 's'}</b> in the shotgun. (1, +1 per 10 points, max 3)</p>`;
    } else {
      html += '<p>The stock ran out. Nobody gets the shotgun.</p>';
    }
    for (const h of r.hands) {
      if (h.id === r.winner) continue;
      html += `<p>${nameOf(h.id)} was left holding ${h.points} point${h.points === 1 ? '' : 's'}:</p>`;
      html += h.cards.length ? handRowHtml(h.cards) : '';
    }

    const button = !game.gun ? 'NEXT ROUND' : game.gun.holder === PLAYER ? 'PICK UP THE SHOTGUN' : 'FACE THE DEALER';
    openModal(html, button, () => (game.gun ? gunScene() : nextRound()));
  }

  function nextRound() {
    selected.clear();
    lastDrawnId = null;
    freshMeldId = null;
    flash = null;
    game.startRound();
    say('roundStart');
    afterAction();
  }

  function showMatchEnd() {
    const won = game.matchWinner === PLAYER;
    say(won ? '...' : 'Next.');
    const html = won
      ? `<h2 class="win">YOU WALK OUT</h2><p>The Dealer slumps over the table. The cards are yours, ${playerName}.</p>`
      : `<h2 class="lose">YOU DIED</h2><p>The Dealer gathers the cards and shuffles. Someone else will sign the waiver.</p>`;
    openModal(html + `<p>Rounds played: ${game.round}</p>`, 'PLAY AGAIN', () => {
      logEntries = [];
      shownResultRound = 0;
      selected.clear();
      flash = null;
      game.newMatch();
      say('roundStart');
      afterAction();
    });
  }

  function showRules() {
    const items = Object.values(E.ITEMS)
      .map((d) => `<li><span class="ico">${d.icon}</span><span><b>${d.name}</b> ×${d.copies} — ${d.text}</span></li>`)
      .join('');
    openModal(
      `<h2>RULES</h2>
      <ul>
        <li>You and the Dealer get <b>10 cards</b>. On your turn, <b>draw</b> one card from the stock or the top of the discard pile.</li>
        <li><b>Meld</b>: a set is 3–4 of a rank (7♠ 7♥ 7♦), a run is 3+ in a row of one suit (4♥ 5♥ 6♥). Aces are low.</li>
        <li><b>Lay off</b> cards onto any meld on the table: select them, then tap the glowing meld.</li>
        <li><b>Discard</b> one card to end your turn. Not the one you just took from the discard pile.</li>
        <li>Empty your hand to win the round. You score what's left in the Dealer's hand: A = 1, 2–10 = face, J/Q/K = 10, items = 5. Out in a single turn is <b>RUMMY</b>: double points.</li>
      </ul>
      <p><b>ITEMS</b> are shuffled into the deck. Use <b>one per turn</b>, before or after drawing: select it and press USE. They can't be melded, and if you discard one the Dealer can pick it up.</p>
      <ul class="item-list">${items}</ul>
      <p><b>THE SHOTGUN.</b> Whoever goes out gets the shotgun with 1 shell, +1 for every 10 points scored (max 3), and chooses who to shoot. Each shell costs 1 health. Everyone has ${game.options.maxHp}. Health carries over between rounds. Last one standing walks out.</p>
      <p>Underlined cards are part of your best melds (HINTS). DEADWOOD is what you'd give away if the Dealer went out now.</p>`,
      'BACK'
    );
  }

  function showLog() {
    const items = logEntries.map((e) => `<li class="${e.cls}">${e.text}</li>`).join('');
    openModal(`<h2>LOG</h2><ol class="log">${items}</ol>`, 'BACK');
  }

  // ---------------------------------------------------------------- shotgun

  function renderGun(text) {
    const r = game.lastResult;
    const left = game.gun ? game.gun.shells : 0;
    let shells = '';
    for (let i = 0; i < r.shells; i++) shells += `<span class="shell${i >= left ? ' spent' : ''}"></span>`;
    $('gun-shells').innerHTML = shells;
    const bars = game.players
      .map((p) => `<div class="seat-name">${nameOf(p.id)} ${p.id === r.winner && p.sawed ? '🪚' : ''}</div><div class="hp" style="justify-content:center">${hpHtml(p)}</div>`)
      .join('');
    $('gun-text').innerHTML = `<p>${text}</p>${bars}`;
  }

  async function fire(shooter, target) {
    SFX.rack();
    await sleep(550);
    game.shoot(shooter, target);
    SFX.shot();
    effects(target === PLAYER ? 'red' : 'white');
    const gun = document.querySelector('.shotgun');
    gun.classList.remove('recoil');
    void gun.offsetWidth;
    gun.classList.add('recoil');
    if (target === DEALER && game.phase !== 'matchOver') say('dealerHit');
    render();
  }

  async function gunScene() {
    inGunScene = true;
    const holder = game.gun.holder;
    const actions = $('gun-actions');
    $('gun-scene').classList.remove('hidden');
    $('gun-title').textContent = holder === PLAYER ? 'THE SHOTGUN IS YOURS' : 'THE DEALER PICKS UP THE SHOTGUN';
    actions.replaceChildren();

    if (holder === PLAYER) {
      await new Promise((resolve) => {
        const offer = () => {
          renderGun(player().sawed ? 'Sawn-off barrel: the next shell hits for 2. Choose your target.' : 'Choose your target.');
          actions.replaceChildren(
            ...game.opponentsOf(PLAYER).map((o) => {
              const b = document.createElement('button');
              b.className = 'btn danger';
              b.textContent = `SHOOT ${nameOf(o.id)}`;
              b.onclick = async () => {
                actions.replaceChildren();
                await fire(PLAYER, o.id);
                renderGun('BANG.');
                await sleep(900);
                if (game.phase === 'shoot') offer();
                else resolve();
              };
              return b;
            })
          );
        };
        offer();
      });
    } else {
      renderGun('The Dealer racks the shotgun and looks at you.');
      await sleep(1200);
      while (game.phase === 'shoot') {
        say('dealerShoots');
        await sleep(900);
        await fire(DEALER, ai.chooseTarget());
        renderGun('BANG.');
        await sleep(1200);
      }
    }

    renderGun(game.phase === 'matchOver' ? 'Silence.' : 'The shotgun goes back on the wall.');
    await new Promise((resolve) => {
      const b = document.createElement('button');
      b.className = 'btn';
      b.textContent = game.phase === 'matchOver' ? 'CONTINUE' : 'NEXT ROUND';
      b.onclick = resolve;
      actions.replaceChildren(b);
    });
    $('gun-scene').classList.add('hidden');
    inGunScene = false;
    if (game.phase === 'matchOver') showMatchEnd();
    else nextRound();
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
    attachEvents();
    $('waiver').classList.add('hidden');
    $('table').classList.remove('hidden');
    game.startRound();
    say('roundStart');
    afterAction();
  }

  function sign() {
    SFX.unlock();
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
    store.set('name', name);
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

  function updateSoundBtn() {
    $('sound-btn').textContent = SFX.enabled ? 'SFX ON' : 'SFX OFF';
  }

  $('name-input').value = store.get('name') || '';
  SFX.enabled = store.get('sound') !== 'off';
  updateSoundBtn();

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
  $('use-btn').addEventListener('click', useSelected);
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
  $('log-btn').addEventListener('click', showLog);
  $('sound-btn').addEventListener('click', () => {
    SFX.enabled = !SFX.enabled;
    store.set('sound', SFX.enabled ? 'on' : 'off');
    updateSoundBtn();
  });
  window.addEventListener('resize', () => game && render());

  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
})();
