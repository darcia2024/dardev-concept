const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baca = (n) => fs.readFileSync(path.join(root, n), 'utf8');

/* Meta Pixel mengirim URL halaman apa adanya ke Meta, dan fitur Automatic
   Advanced Matching-nya menyapu isi formulir. Halaman depan tidak memuat data
   siapa pun selain milik pengunjung itu sendiri; halaman lain memuat nomor
   telepon pelanggan, kode kartu member, omzet, dan absensi karyawan.

   Berkas ini menjaga satu hal yang mudah dilanggar tanpa sadar: menempelkan
   cuplikan pixel "ke seluruh sistem" karena begitu bunyi permintaannya. */

// ── 1 · Terpasang di halaman depan ─────────────────────────────────────────
const landing = baca('landing.html');
assert.match(landing, /connect\.facebook\.net\/en_US\/fbevents\.js/, 'pixel harus ada di halaman depan');
assert.match(landing, /fbq\('init', '2154833071732943'\)/, 'ID pixel pemilik harus terpasang');
assert.match(landing, /fbq\('track', 'PageView'\)/);

// ── 2 · TIDAK terpasang di mana pun selain halaman depan ───────────────────
const terlarang = ['pos.html', 'rekap.html', 'capster.html', 'kartu.html', 'masuk.html', 'app.html'];
for (const berkas of terlarang) {
  const isi = baca(berkas);
  assert.doesNotMatch(isi, /fbq\(/,
    berkas + ' tidak boleh memuat Meta Pixel');
  assert.doesNotMatch(isi, /connect\.facebook\.net|facebook\.com\/tr\?/,
    berkas + ' tidak boleh memanggil server Meta');
}

// POS punya alasan tambahan: seluruh pustakanya di-host sendiri supaya kasir
// tidak ikut mati ketika jaringan luar terganggu.
const pos = baca('pos.html');
assert.match(pos, /Library di-host sendiri, bukan CDN/,
  'prinsip self-host di POS harus tetap tertulis');
const skripLuar = (pos.match(/<script[^>]+src="https?:\/\//g) || []);
assert.deepEqual(skripLuar, [], 'POS tidak boleh memuat script dari domain luar');

// ── 3 · Booking yang jadi ikut dilaporkan ──────────────────────────────────
// PageView saja tidak menjawab "iklan mana yang menghasilkan booking": setiap
// orang yang sekadar lewat ikut terhitung.
assert.match(landing, /fbq\('track', 'Schedule'\)/,
  'booking yang berhasil harus dilaporkan sebagai peristiwa Schedule');

const sukses = landing.slice(landing.indexOf("const b = Array.isArray(res.data)"),
                             landing.indexOf("} catch (err) {"));
assert.ok(sukses.length > 0, 'blok sukses booking harus dapat dipotong');
assert.match(sukses, /fbq\('track', 'Schedule'\)/,
  'Schedule harus dikirim di jalur sukses, bukan di mana pun sebelum notanya jadi');

// Kode booking harus sudah tampil lebih dulu. Pengukuran iklan tidak boleh
// mendahului apa yang ditunggu pengunjung.
assert.ok(sukses.indexOf('scrollIntoView') < sukses.indexOf("fbq('track', 'Schedule')"),
  'Schedule dikirim SESUDAH kode booking ditampilkan');

// Pixel yang diblokir pemblokir iklan tidak boleh menjatuhkan konfirmasi.
assert.match(sukses, /typeof fbq === 'function'/, 'pemanggilan fbq harus dijaga');
assert.match(sukses, /try \{[\s\S]*fbq\('track', 'Schedule'\)[\s\S]*\} catch/,
  'kegagalan pixel harus ditelan');

// ── 4 · Tidak ada data pribadi yang ikut terkirim ──────────────────────────
// Nama dan nomor WhatsApp pengunjung tinggal di sini. Yang dilaporkan hanya
// bahwa sebuah booking terjadi.
const semuaFbq = landing.match(/fbq\([^)]*\)/g) || [];
for (const panggilan of semuaFbq) {
  for (const bocor of ['nama', 'telp', 'phone', 'bkNama', 'bkTelepon', 'email', 'em:', 'ph:']) {
    assert.ok(!panggilan.includes(bocor),
      'panggilan fbq membawa data pribadi: ' + panggilan);
  }
}
assert.equal(semuaFbq.length, 3, 'hanya init, PageView, dan Schedule yang boleh dipanggil');

console.log('Meta Pixel tests: OK');
