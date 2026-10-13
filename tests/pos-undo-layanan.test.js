/* Kartu layanan di POS: urungkan, tambah-kurang, dan ketukan ganda.
 *
 * Keluhan kasir: kapster sering kepencet dua kali, dan satu-satunya cara
 * membatalkannya adalah memuat ulang halaman — tombol hapus hanya ada di baris
 * keranjang, bukan di kartu yang baru saja ditekan. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const pos = fs.readFileSync(path.join(__dirname, '..', 'pos.html'), 'utf8');
const blok = pos.slice(pos.indexOf('function tambahLayanan(service)'), pos.indexOf('let currentFilterCat'));
assert.ok(blok.includes('function urungkanLayanan(') && blok.includes('function ketukTerlaluCepat('), 'fungsi urungkan dan penjaga harus ada di blok yang diuji');

function buat() {
  let renders = 0;
  const api = new Function('hitung', `
    let selectedServices = [];
    const currentFilterCat = 'ALL';
    const renderServices = () => { hitung.render++; };
    const updateCartView = () => {};
    ${blok}
    return {
      tambah: tambahLayanan, urungkan: urungkanLayanan, hapus: hapusBarisLayanan,
      cepat: ketukTerlaluCepat, isi: () => selectedServices, JEDA: JEDA_KETUK_GANDA_MS,
      setKapster: (i, k) => { selectedServices[i].capsterId = k; }
    };
  `)({ get render() { return renders; }, set render(v) { renders = v; } });
  api.renders = () => renders;
  return api;
}
const HC = { id: 'hc', name: 'Haircut', price: 85000 };
const HW = { id: 'hw', name: 'Hairwash', price: 15000 };

// ── 1 · Urungkan membatalkan yang TERAKHIR, bukan yang pertama ─────────────
{
  const k = buat();
  k.tambah(HC); k.tambah(HW); k.tambah(HC);
  k.setKapster(0, 'cena'); k.setKapster(2, 'lukman');
  assert.equal(k.urungkan('hc'), true);
  assert.deepEqual(k.isi().map((s) => s.name), ['Haircut', 'Hairwash'], 'satu Haircut hilang, yang lain utuh');
  assert.equal(k.isi()[0].capsterId, 'cena', 'yang terakhir yang dibatalkan: Haircut pertama (milik Cena) tetap ada');
  assert.equal(k.urungkan('hc'), true);
  assert.deepEqual(k.isi().map((s) => s.name), ['Hairwash']);
  assert.equal(k.urungkan('hc'), false, 'layanan yang tidak ada di keranjang: tidak melakukan apa-apa');
  assert.equal(k.isi().length, 1);
}

// ── 2 · Tombol − habis sampai nol, dan + menambah lagi ─────────────────────
{
  const k = buat();
  k.tambah(HC); k.tambah(HC);          // kepencet dua kali
  k.urungkan('hc');                    // ketuk −
  assert.equal(k.isi().filter((s) => s.id === 'hc').length, 1, 'kembali ke satu');
  k.tambah(HC);                        // ketuk +
  assert.equal(k.isi().filter((s) => s.id === 'hc').length, 2);
  k.urungkan('hc'); k.urungkan('hc');
  assert.equal(k.isi().length, 0, 'bisa dikembalikan sampai kosong tanpa memuat ulang halaman');
}

// ── 3 · Layar disegarkan sesudah urungkan ──────────────────────────────────
{
  const k = buat();
  k.tambah(HC);
  const sebelum = k.renders();
  k.urungkan('hc');
  assert.ok(k.renders() > sebelum, 'daftar layanan harus digambar ulang supaya jumlahnya berubah');
}

// ── 4 · Penjaga ketukan ganda ──────────────────────────────────────────────
{
  const k = buat();
  const asli = Date.now;
  try {
    let t = 1_000_000; Date.now = () => t;
    assert.equal(k.cepat('hc'), false, 'ketukan pertama diterima');
    t += 200;
    assert.equal(k.cepat('hc'), true, 'ketukan kedua 200 md kemudian = kepencet, diabaikan');
    t += 200;                                  // 400 md sejak yang diterima
    assert.equal(k.cepat('hc'), true, 'masih di dalam jeda');
    t += 100;                                  // 500 md sejak yang diterima
    assert.equal(k.cepat('hc'), false, 'sesudah jeda diterima lagi');
    // Jeda dihitung dari ketukan yang DITERIMA: rentetan ketukan yang ditolak
    // tidak boleh terus mengunci kartunya.
    t += 100; assert.equal(k.cepat('hc'), true);     // 100 md sejak yang diterima
    t += 100; assert.equal(k.cepat('hc'), true);     // 200
    t += 100; assert.equal(k.cepat('hc'), true);     // 300
    t += 100; assert.equal(k.cepat('hc'), true);     // 400: masih di dalam jeda 450
    t += 50;  assert.equal(k.cepat('hc'), false, '450 md sejak yang terakhir DITERIMA, bukan sejak ketukan terakhir');
    // Kartu lain tidak ikut terkunci: Haircut lalu Hairwash itu normal.
    assert.equal(k.cepat('hw'), false);
    assert.ok(k.JEDA >= 300 && k.JEDA <= 600, 'jeda cukup untuk jari yang kepencet, cukup pendek untuk ketukan disengaja');
  } finally { Date.now = asli; }
}

// ── 5 · Yang harus ada di sumbernya ────────────────────────────────────────
assert.match(pos, /class="step-kurang" aria-label="Kurangi/, 'tombol − ada, berlabel untuk pembaca layar');
assert.match(pos, /class="step-tambah" aria-label="Tambah/);
assert.match(pos, /\$\{jml > 0 \? `\s*<div class="service-stepper"/, 'pengatur jumlah hanya muncul pada kartu yang sudah terpilih');
assert.match(pos, /kurang\.onclick = \(e\) => \{ e\.stopPropagation\(\); urungkanLayanan\(s\.id\); \};/,
  'tombol − tidak boleh ikut memicu penangan kartunya');
assert.match(pos, /\.onclick = \(e\) => \{ e\.stopPropagation\(\); tambahLayanan\(s\); \};/, 'tombol + juga');
assert.match(pos, /\.service-stepper button \{\s*width: 44px; height: 40px;/, 'sasaran sentuh sebesar jempol');
// Tombol + sengaja TIDAK dijaga: dua potong yang disengaja harus tetap mudah.
const mulaiKartu = pos.indexOf("const kurang = card.querySelector('.step-kurang')");
assert.ok(mulaiKartu > 0, 'penangan tombol kartu harus ditemukan');
const kartu = pos.slice(mulaiKartu, pos.indexOf('container.appendChild(card);', mulaiKartu));
assert.doesNotMatch(kartu.slice(0, kartu.indexOf('card.onclick')), /ketukTerlaluCepat/, 'tombol + tidak dijaga');
assert.match(kartu, /card\.onclick = \(\) => \{\s*if \(ketukTerlaluCepat\(s\.id\)\) return;/, 'ketukan pada badan kartu dijaga');

console.log('pos-undo-layanan: semua pemeriksaan lolos');
