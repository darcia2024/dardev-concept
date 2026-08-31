const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const kartu = fs.readFileSync(path.join(root, 'kartu.html'), 'utf8');

const TIER = ['Silver', 'Gold', 'Platinum', 'Infinite', 'Black'];

// Kelima tingkat harus punya wajahnya sendiri. Tingkat tanpa definisi warna
// akan jatuh ke nilai cadangan dan terlihat persis sama dengan Silver, dan
// janji "beginilah kartu Anda nanti" berhenti benar untuk tingkat itu.
for (const t of TIER) {
  assert.match(
    kartu,
    new RegExp(`\\[data-tier="${t}"\\]\\s*\\{`),
    `level ${t} harus punya definisi warnanya sendiri`
  );
}

// Contoh kecil di tangga memakai peubah yang sama dengan kartu besarnya.
// Kalau salah satunya menulis warna sendiri, keduanya akan perlahan berbeda.
assert.match(kartu, /\.card-hero \{[\s\S]*?background:var\(--t-bg/);
assert.match(kartu, /\.tangga-swatch \{[\s\S]*?background:var\(--t-bg\)/);

// Kartu harus benar-benar dipasangi levelnya saat digambar.
assert.match(kartu, /\.card-hero'\)\.dataset\.tier = m\.tier/);

// Tangga diambil dari server, bukan ditulis tetap di halaman.
assert.match(kartu, /sb\.rpc\('tier_ladder'\)/);

// Manfaat diturunkan dari data. Menuliskannya tetap di halaman berarti
// menjanjikan sesuatu yang sistemnya belum tentu dapat tepati — spesifikasi
// klien menyebut catatan model potongan dan gratis cuci rambut, dan keduanya
// belum dibangun sama sekali.
const sumberTangga = kartu.slice(
  kartu.indexOf('function renderTangga'),
  kartu.indexOf('async function muat()')
);
assert.ok(sumberTangga.length > 0, 'renderTangga harus tersedia');
assert.match(sumberTangga, /reward\.filter\(r => r\.min_tier === t\.tier\)/);
assert.match(sumberTangga, /Number\(t\.multiplier\)/);
for (const janji of ['cuci rambut', 'catatan potongan', 'gratis seumur', 'prioritas']) {
  assert.doesNotMatch(
    sumberTangga,
    new RegExp(janji, 'i'),
    `manfaat "${janji}" tidak boleh ditulis tetap: belum ada di sistem`
  );
}

// ── Kontras kelima wajah kartu ─────────────────────────────────────────────
// Diuji pada KEDUA ujung gradasinya, bukan hanya tengahnya: ujung yang paling
// terang adalah tempat teks paling mungkin gagal terbaca.
function luminansi([r, g, b]) {
  const f = v => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
function rasio(a, b) {
  const A = luminansi(hex(a));
  const B = luminansi(hex(b));
  return (Math.max(A, B) + 0.05) / (Math.min(A, B) + 0.05);
}

// Nilai dibaca dari berkasnya, bukan disalin ke sini. Kalau disalin, mengubah
// warna di kartu tidak akan pernah membuat pengujian ini merah.
function tokenLevel(tier) {
  const blok = kartu.slice(kartu.indexOf(`[data-tier="${tier}"]`));
  const potong = blok.slice(0, blok.indexOf('}'));
  const ambil = nama => {
    const m = potong.match(new RegExp(`--${nama}:\\s*(#[0-9A-Fa-f]{6})`));
    return m && m[1];
  };
  const gradasi = [...potong.matchAll(/#[0-9A-Fa-f]{6}(?=\s+\d+%)/g)].map(m => m[0]);
  return { gradasi, aksen: ambil('t-aksen'), ink: ambil('t-ink'), dim: ambil('t-ink-dim') };
}

for (const t of TIER) {
  const w = tokenLevel(t);
  assert.ok(w.gradasi.length >= 2, `${t}: gradasi latar harus terbaca`);
  assert.ok(w.aksen && w.ink && w.dim, `${t}: warna teks harus lengkap`);

  for (const [nama, warna] of [['ink', w.ink], ['ink-dim', w.dim], ['aksen', w.aksen]]) {
    const terburuk = Math.min(...w.gradasi.map(bg => rasio(warna, bg)));
    assert.ok(
      terburuk >= 4.5,
      `${t}/${nama}: kontras ${terburuk.toFixed(2)} di bawah ambang 4,5 pada gradasinya`
    );
  }
}

console.log('Tier ladder tests: OK');
