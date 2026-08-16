// Daily Immersive Read — service worker.
// Shell (html/css/js/icons): stale-while-revalidate, so the app opens instantly
// and picks up a new build on the next launch.
// reads.json: network-first, so a fresh day always wins when online.
// Bump this on every shell change (index.html / app.js / app.css / styles.css).
// The activate handler deletes any cache whose name differs, so a new version
// is what forces phones to drop the old JS instead of serving it for another
// launch or two.
const CACHE = 'dir-v3';
const SHELL = [
  './', './index.html', './app.js', './app.css', './styles.css',
  './manifest.webmanifest', './icon-192.png', './icon-512.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// Only a real, same-origin success is worth storing. Without this check a 404
// body gets cached like any other: a failed deploy would overwrite the last
// good reads.json (leaving the app with no data at all once offline), and a
// momentary 404 on app.js would be served as the script on the next launch.
const cacheable = (res) => res && res.ok && res.type === 'basic';

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;

  const store = (res) => {
    const copy = res.clone();
    return caches.open(CACHE).then((c) => c.put(req, copy));
  };

  // Data — always try the network first.
  if (url.pathname.endsWith('reads.json')) {
    e.respondWith(
      fetch(req).then((res) => {
        // waitUntil, not a floating promise: the browser is free to kill the
        // worker once the response is delivered, which can land mid-write.
        if (cacheable(res)) e.waitUntil(store(res));
        return res;
      }).catch(() => caches.match(req))
    );
    return;
  }

  // Shell — serve cache immediately, refresh in the background.
  const net = fetch(req)
    .then((res) => (cacheable(res) ? store(res).then(() => res) : res))
    .catch(() => null);

  // Registered synchronously, while the event is still active: a cache hit
  // settles respondWith straight away, so the revalidation is exactly the
  // work that would otherwise be cut short before it wrote anything.
  e.waitUntil(net);

  e.respondWith(
    caches.match(req).then((hit) => hit || net.then((res) => res || Response.error()))
  );
});
