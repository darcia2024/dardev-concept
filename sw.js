/* =============================================================================
   SERVICE WORKER — Kartu Member Underrated Barbershop

   Satu aturan yang mengatur seluruh berkas ini:

     KERANGKA APLIKASI boleh disimpan. DATA POIN TIDAK PERNAH.

   Menyimpan halaman, gaya, dan pustaka membuat aplikasi terbuka seketika dan
   tetap terbuka saat sinyal hilang. Tetapi menyimpan jawaban dari basis data
   berarti pelanggan bisa melihat saldo poin kemarin dan mengira itu saldo hari
   ini — lalu datang ke kasir menuntut penukaran yang poinnya sudah habis.
   Angka yang salah lebih merugikan daripada layar yang jujur mengatakan
   "tidak ada sambungan".

   Karena itu permintaan ke /rest/v1/ dan /auth/v1/ SELALU lewat jaringan, dan
   tidak pernah disimpan — bahkan tidak dijadikan cadangan saat luring.
   ============================================================================= */

const VERSI = 'underrated-v3';
const KERANGKA = [
  '/kartu',
  '/kartu.html',
  '/theme.css',
  '/vendor/supabase.js',
  '/vendor/qrcode.js',
  '/assets/logo.png',
  '/assets/icon-192.png',
  '/assets/icon-512.png',
  '/assets/cena.png',
  '/assets/lukman.png',
  '/assets/wanda.png',
  '/manifest.json'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(VERSI)
      // addAll gagal seluruhnya bila satu berkas meleset. Disimpan satu per
      // satu supaya satu berkas yang hilang tidak membatalkan pemasangan.
      .then((c) => Promise.all(KERANGKA.map((u) => c.add(u).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((k) => Promise.all(k.filter((n) => n !== VERSI).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Data selalu dari jaringan. Tidak disimpan, tidak dicadangkan.
  if (url.pathname.startsWith('/rest/v1/') ||
      url.pathname.startsWith('/auth/v1/') ||
      url.pathname.startsWith('/storage/v1/')) {
    return;
  }

  // Halaman: coba jaringan dulu supaya pembaruan langsung terpakai; bila
  // gagal barulah salinan tersimpan dipakai, sehingga aplikasi tetap terbuka.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const salinan = res.clone();
          caches.open(VERSI).then((c) => c.put('/kartu', salinan)).catch(() => {});
          return res;
        })
        .catch(() => caches.match('/kartu').then((r) => r || caches.match('/kartu.html')))
    );
    return;
  }

  // Aset: salinan tersimpan lebih dulu — isinya jarang berubah dan kecepatan
  // membuka lebih berharga daripada kesegaran beberapa kilobyte CSS.
  e.respondWith(
    caches.match(req).then((tersimpan) => {
      if (tersimpan) return tersimpan;
      return fetch(req).then((res) => {
        if (res && res.status === 200 && res.type === 'basic') {
          const salinan = res.clone();
          caches.open(VERSI).then((c) => c.put(req, salinan)).catch(() => {});
        }
        return res;
      }).catch(() => tersimpan);
    })
  );
});
