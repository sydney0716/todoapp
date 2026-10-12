// The build script replaces these values with this release's static assets.
const CACHE = 'personaltodo-__BUILD_VERSION__';
const ASSETS = __ASSET_LIST__;
const urls = new Set(ASSETS.map(path => new URL(path, self.registration.scope).href));

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll([...urls])));
  // Let existing tabs finish their edits before activating an update.
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('personaltodo-') && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  url.search = '';
  // API responses and credentials are never stored in the offline shell cache.
  if (request.method !== 'GET' || !urls.has(url.href)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(url.href);
    return cached ?? fetch(request);
  })());
});
