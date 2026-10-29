/*
 * Shotgun Rummy — offline support.
 * Network first (so updates show up straight away), falling back to the cache
 * when the phone is offline. Bump VERSION when files are added or renamed.
 */
const VERSION = 'sgr-v2';
const FILES = [
  './',
  './index.html',
  './manifest.webmanifest',
  './css/style.css',
  './fonts/vt323-latin.woff2',
  './js/engine.js',
  './js/items.js',
  './js/ai.js',
  './js/sound.js',
  './js/ui.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(VERSION).then((c) => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
