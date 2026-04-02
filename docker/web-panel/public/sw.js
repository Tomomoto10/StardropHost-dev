// StardropHost Service Worker
// Caches the app shell for offline/install support.
// All API requests always go to network — never cached.

const CACHE   = 'stardrophost-v1';
const SHELL   = [
  '/',
  '/css/style.css',
  '/js/api.js',
  '/js/app.js',
  '/favicon.png',
  '/manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  // Never cache API, WebSocket, or auth calls
  const url = new URL(e.request.url);
  if (url.pathname.startsWith('/api/') || url.pathname === '/ws') return;

  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
});
