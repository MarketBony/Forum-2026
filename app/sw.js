// =====================================================================
//  sw.js — coquille hors ligne
//
//  Le service worker met en cache l'application elle-même, pour qu'un
//  animateur puisse OUVRIR l'app sans réseau. Les appels à la base ne
//  sont jamais mis en cache : c'est la file d'attente d'api.js qui gère
//  les écritures, et un solde périmé serait pire qu'une absence de solde.
//
//  Changer VERSION à chaque déploiement force le renouvellement.
// =====================================================================
const VERSION = 'gbp-v26';
const COQUILLE = [
  './',
  './index.html',
  './app.css',
  './config.js',
  './js/app.js',
  './js/api.js',
  './js/verre.js',
  './icone.svg',
  './manifest.webmanifest',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(VERSION)
      .then((c) => c.addAll(COQUILLE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((noms) => Promise.all(noms.filter((n) => n !== VERSION).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);

  // Jamais de cache pour la base de données.
  if (u.pathname.startsWith('/rest/v1/') || u.hostname.endsWith('.supabase.co')) return;

  if (e.request.method !== 'GET') return;

  // Réseau d'abord pour la coquille (on reste à jour), cache en secours.
  if (u.origin === location.origin) {
    e.respondWith(
      fetch(e.request)
        .then((r) => {
          const copie = r.clone();
          caches.open(VERSION).then((c) => c.put(e.request, copie)).catch(() => {});
          return r;
        })
        .catch(() => caches.match(e.request).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  // Polices Google : cache d'abord, elles ne changent pas.
  if (u.hostname === 'fonts.googleapis.com' || u.hostname === 'fonts.gstatic.com') {
    e.respondWith(
      caches.match(e.request).then((r) => r || fetch(e.request).then((rep) => {
        const copie = rep.clone();
        caches.open(VERSION).then((c) => c.put(e.request, copie)).catch(() => {});
        return rep;
      }).catch(() => new Response('', { status: 504 })))
    );
  }
});
