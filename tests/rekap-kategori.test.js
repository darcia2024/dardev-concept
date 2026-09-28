/* Dashboard owner dikelompokkan jadi tujuh kategori.
 *
 * Dua puluh lima panel dalam satu aliran menuntut gulir yang sangat panjang.
 * Yang dipindah hanyalah apa yang TAMPAK — seluruh data tetap dimuat sekali
 * saat halaman dibuka. Empat cara perombakan ini dapat rusak tanpa ada yang
 * menyadarinya:
 *
 *   1. Sebuah panel tidak masuk tab mana pun, sehingga tidak pernah terlihat
 *      lagi oleh siapa pun.
 *   2. Tab menimpa atribut hidden milik panel, sehingga panel yang seharusnya
 *      sembunyi justru dipaksa tampil.
 *   3. Peringatan yang dulunya terlihat begitu saja di alur kini terkubur di
 *      balik tab tanpa ada yang memberi tahu.
 *   4. Penyaring periode ikut masuk salah satu tab, sehingga di tab lain
 *      owner mengira filternya tidak berlaku.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const L = rekap.split(/\r?\n/);

const TAB = ['ringkasan', 'keuangan', 'karyawan', 'member', 'booking', 'pengaturan', 'arsip'];

/* ── 1 · Bilah dan pane-nya sepadan ──────────────────────────────────────── */
const tombol = [...rekap.matchAll(/<button class="tab-btn[^"]*" data-pane="([a-z]+)"/g)].map(m => m[1]);
const pane   = [...rekap.matchAll(/<section class="tab-pane[^"]*" data-pane="([a-z]+)"/g)].map(m => m[1]);

assert.deepEqual(tombol, TAB, 'tombol kategori harus lengkap dan berurutan');
assert.deepEqual(pane, TAB, 'tiap kategori harus punya <section> sendiri');
assert.equal(
  (rekap.match(/class="tab-pane is-on"/g) || []).length, 1,
  'tepat satu kategori yang terbuka saat halaman dimuat'
);

/* ── 2 · Tidak ada panel yang tertinggal di luar tab ─────────────────────
   Dihitung dengan menelusuri kedalaman elemen, bukan ditebak dari indentasi.
   Panel yang jatuh di luar semua <section> tidak akan pernah tampil lagi, dan
   tidak ada galat yang akan memberitahukannya. */
const aMain = L.findIndex(l => l.includes('<main class="rekap-container">'));
const bMain = L.findIndex((l, i) => i > aMain && l.trim() === '</main>');
assert.ok(aMain > 0 && bMain > aMain, '<main> harus ditemukan');

let dalamSection = 0;
const yatim = [];
let adaControlStrip = false;
for (let i = aMain + 1; i < bMain; i++) {
  const b = L[i];
  if (/<section class="tab-pane/.test(b)) dalamSection++;
  if (/^\s*<\/section>/.test(b)) dalamSection--;

  if (/<div class="table-panel/.test(b) && dalamSection === 0) {
    let judul = '(tanpa judul)';
    for (let j = i; j < Math.min(i + 12, bMain); j++) {
      const h = L[j].match(/<h2[^>]*>(.*?)<\/h2>/);
      if (h) { judul = h[1].replace(/<[^>]*>/g, '').trim(); break; }
    }
    yatim.push(judul);
  }
  /* ── 4 · Penyaring periode WAJIB di luar tab ───────────────────────────
     Ia mempengaruhi hampir semua panel. Menaruhnya di dalam satu kategori
     membuat owner di kategori lain mengira filternya tidak berlaku. */
  if (/<div class="control-strip"/.test(b)) {
    adaControlStrip = true;
    assert.equal(dalamSection, 0, 'penyaring periode tidak boleh berada di dalam tab');
  }
}
assert.ok(adaControlStrip, 'penyaring periode harus tetap ada');
assert.deepEqual(yatim, [], 'ada panel di luar kategori mana pun: ' + yatim.join(', '));
assert.equal(dalamSection, 0, 'jumlah <section> dan penutupnya tidak seimbang');

/* Seluruh panel yang dulu ada harus masih ada. Dihitung, bukan didaftar:
   daftar tangan tidak ikut bertambah saat panel baru dibuat. */
const jml = (rekap.match(/<div class="table-panel/g) || []).length;
assert.ok(jml >= 23, `panel menyusut jadi ${jml} — ada yang hilang saat disusun ulang`);

/* ── 3 · Tab tidak boleh menyentuh hidden milik panel ────────────────────
   panelQrisPantau mengatur hidden-nya sendiri menurut ada atau tidaknya nota
   yang belum diperiksa. Bila perpindahan tab ikut menulis hidden, panel itu
   akan dipaksa tampil justru ketika tidak ada yang perlu dikerjakan. */
const gantiTab = rekap.slice(rekap.indexOf('function gantiTab'), rekap.indexOf('function tandaiTab'));
assert.ok(gantiTab.length > 0, 'gantiTab harus tersedia');
assert.match(gantiTab, /classList\.toggle\('is-on'/, 'perpindahan tab lewat kelas, bukan atribut');
assert.doesNotMatch(gantiTab, /\.hidden\s*=/, 'gantiTab tidak boleh menulis atribut hidden');

/* [hidden] hanya berasal dari stylesheet bawaan peramban, dan aturan author
   mana pun mengalahkannya — .table-panel yang display:flex, misalnya. Tanpa
   baris ini, tiap panel yang menyetel hidden tetap tampil sebagai kotak
   kosong, dan tidak ada galat yang muncul. */
assert.match(
  rekap, /\[hidden\]\s*\{\s*display:\s*none\s*!important;?\s*\}/,
  'atribut hidden harus ditegakkan di atas aturan display milik kelas'
);

/* ── 5 · Peringatan tidak boleh terkubur diam-diam ───────────────────────
   Panel QRIS memunculkan dirinya sendiri saat ada yang perlu diperiksa.
   Sebelum ada tab ia terlihat begitu saja; sekarang tabnya yang memberi
   tahu, di KEDUA arah — menyala saat ada, padam saat tidak. */
const pantau = rekap.slice(rekap.indexOf('async function muatQrisPantau'),
                           rekap.indexOf('function renderDashboard()'));
assert.ok(pantau.length > 0, 'muatQrisPantau harus tersedia');
assert.match(pantau, /tandaiTab\('keuangan', true\)/, 'tab ditandai saat ada nota yang belum diperiksa');
assert.match(pantau, /tandaiTab\('keuangan', false\)/, 'tandanya padam saat tidak ada');
assert.ok(
  (pantau.match(/tandaiTab\('keuangan', false\)/g) || []).length >= 2,
  'tanda harus padam pada kedua jalan keluar: daftar kosong dan gagal memuat'
);
assert.match(rekap, /data-dot="keuangan"/, 'tab Keuangan harus punya wadah penandanya');

/* ── 6 · Ingatan tab tidak boleh menjatuhkan halaman ─────────────────────
   localStorage melempar di mode privat sebagian peramban. Dashboard yang
   gagal dimuat karena mengingat tab adalah tukar-tambah yang buruk. */
const ingat = rekap.slice(rekap.indexOf('const TAB_INGATAN'),
                          rekap.indexOf('})();', rekap.indexOf('function pulihkanTab')) + 5);
for (const panggil of ['setItem', 'getItem']) {
  const i = ingat.indexOf('localStorage.' + panggil);
  assert.notEqual(i, -1, `localStorage.${panggil} harus dipakai`);
  assert.match(
    ingat.slice(Math.max(0, i - 120), i + 160), /try\s*\{[\s\S]*catch/,
    `localStorage.${panggil} harus dibungkus try/catch`
  );
}

/* Tautan langsung menang atas tab yang diingat: /rekap#karyawan harus selalu
   membuka Karyawan, bukan tab terakhir yang kebetulan tersimpan. */
const pulih = rekap.slice(rekap.indexOf('function pulihkanTab'));
assert.ok(
  pulih.indexOf('location.hash') < pulih.indexOf('localStorage.getItem'),
  'tanda pagar harus diperiksa sebelum ingatan'
);

console.log('rekap-kategori: semua pemeriksaan lolos');
