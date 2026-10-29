/*
 * Shotgun Rummy — synthesized sound effects (no audio files needed).
 */
(function (root) {
  'use strict';

  let ctx = null;
  let enabled = true;

  function audio() {
    if (!enabled) return null;
    if (!ctx) {
      const AC = root.AudioContext || root.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
    }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }

  function noise(duration, { freq = 1200, gain = 0.8, decay = 0.15 } = {}) {
    const a = audio();
    if (!a) return;
    const len = Math.floor(a.sampleRate * duration);
    const buf = a.createBuffer(1, len, a.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (a.sampleRate * decay));
    const src = a.createBufferSource();
    src.buffer = buf;
    const filter = a.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = freq;
    const g = a.createGain();
    g.gain.value = gain;
    src.connect(filter).connect(g).connect(a.destination);
    src.start();
  }

  function tone(freq, duration, { type = 'square', gain = 0.06, slide = 0 } = {}) {
    const a = audio();
    if (!a) return;
    const osc = a.createOscillator();
    const g = a.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, a.currentTime);
    if (slide) osc.frequency.exponentialRampToValueAtTime(freq * slide, a.currentTime + duration);
    g.gain.setValueAtTime(gain, a.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + duration);
    osc.connect(g).connect(a.destination);
    osc.start();
    osc.stop(a.currentTime + duration);
  }

  root.SFX = {
    get enabled() {
      return enabled;
    },
    set enabled(v) {
      enabled = v;
    },
    unlock: () => audio(),
    card: () => noise(0.05, { freq: 3000, gain: 0.25, decay: 0.01 }),
    meld: () => {
      tone(220, 0.12, { type: 'triangle', gain: 0.12 });
      setTimeout(() => tone(330, 0.15, { type: 'triangle', gain: 0.12 }), 80);
    },
    item: () => tone(520, 0.25, { type: 'sine', gain: 0.1, slide: 0.5 }),
    heal: () => tone(440, 0.3, { type: 'sine', gain: 0.1, slide: 1.5 }),
    hurt: () => tone(160, 0.35, { type: 'sawtooth', gain: 0.08, slide: 0.5 }),
    rack: () => {
      noise(0.06, { freq: 2500, gain: 0.4, decay: 0.01 });
      setTimeout(() => noise(0.08, { freq: 1800, gain: 0.5, decay: 0.015 }), 140);
    },
    shot: () => {
      noise(0.9, { freq: 900, gain: 1, decay: 0.18 });
      tone(70, 0.4, { type: 'sine', gain: 0.5, slide: 0.4 });
    },
  };
})(typeof self !== 'undefined' ? self : this);
