const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pratinjau = fs.readFileSync(path.join(root, 'koreksi_data_01a_pratinjau_poin.sql'), 'utf8');
const terap = fs.readFileSync(path.join(root, 'koreksi_data_01b_terapkan_poin.sql'), 'utf8');

/* Skrip ini mengubah saldo poin member sungguhan dan tidak punya tombol batal.
   Yang dijaga di sini bukan gaya penulisannya, melainkan tiga cara ia dapat
   merusak data secara diam-diam. */

// ── 1 · Pratinjau benar-benar hanya membaca ────────────────────────────────
// Kalau pratinjau ikut mengubah, tidak ada lagi kesempatan melihat sebelum
// memutuskan — dan seluruh gunanya hilang.
for (const kata of ['UPDATE ', 'INSERT ', 'DELETE ', 'ALTER ', 'DROP ']) {
  assert.equal(pratinjau.toUpperCase().indexOf(kata), -1,
    'skrip pratinjau tidak boleh memuat ' + kata.trim());
}
assert.match(pratinjau, /FROM transactions/, 'pratinjau harus menampilkan nota yang terdampak');
assert.match(pratinjau, /compute_tier/, 'pratinjau harus menunjukkan level sesudahnya');

// ── 2 · Penjaga idempoten dan penandanya harus PERSIS sama ─────────────────
/* Ini kegagalan yang paling mudah lolos dari mata. Bila catatan pada penjaga
   NOT EXISTS berbeda satu karakter saja dari catatan yang di-INSERT, penjaga
   tidak akan pernah menemukan barisnya — dan menjalankan skrip dua kali
   melipatgandakan poin setiap member tanpa galat apa pun. */
const catatan = [...terap.matchAll(/'Penyesuaian cashback 7% menjadi 10%'/g)];
assert.ok(catatan.length >= 2,
  'catatan penanda harus muncul di penjaga NOT EXISTS dan di INSERT');

const semuaCatatan = [...terap.matchAll(/notes\s*=\s*('[^']*')|VALUES[\s\S]{0,400}?('Penyesuaian[^']*')/g)]
  .flatMap(m => [m[1], m[2]]).filter(Boolean);
assert.equal(new Set(semuaCatatan).size, 1,
  'seluruh rujukan catatan harus identik, kalau tidak penjaga idempotennya lumpuh: '
  + JSON.stringify([...new Set(semuaCatatan)]));

assert.match(terap, /NOT EXISTS \(SELECT 1 FROM point_ledger l/,
  'nota yang sudah disesuaikan harus dilewati');

// ── 3 · Riwayat asli tidak boleh ditulis ulang ─────────────────────────────
// Baris EARN aslinya adalah jawaban atas "kenapa saldo saya berubah". Yang
// ditambahkan haruslah baris baru, bukan angka lama yang ditimpa.
assert.equal(terap.indexOf('UPDATE point_ledger'), -1,
  'buku besar tidak boleh diubah, hanya ditambah');
assert.equal(terap.indexOf('DELETE FROM point_ledger'), -1,
  'baris buku besar tidak boleh dihapus');
assert.match(terap, /INSERT INTO point_ledger/, 'penyesuaian harus dicatat sebagai baris baru');
assert.match(terap, /'ADJUSTMENT'/, 'jenisnya ADJUSTMENT, bukan EARN susulan');

// ── 4 · Satu kesatuan, dan tarifnya ikut naik ──────────────────────────────
assert.ok(terap.indexOf('BEGIN;') < terap.indexOf('COMMIT;'),
  'perubahan harus dalam satu transaksi');
assert.match(terap, /UPDATE loyalty_settings SET earn_percent = 10\.00/,
  'tarif untuk transaksi berikutnya harus ikut dinaikkan');
assert.match(terap, /UPDATE transactions\s+SET points_earned = points_earned \+ r\.tambahan/,
  'kolom yang dibaca riwayat kartu harus ikut disamakan');
assert.match(terap, /SET tier = compute_tier\(lifetime_points\)/,
  'level harus dihitung ulang dari poin seumur hidup');
assert.match(terap, /lifetime_points = lifetime_points \+ r\.tambahan/,
  'poin seumur hidup ikut naik, bukan hanya saldo');

// ── 5 · Aritmetikanya ──────────────────────────────────────────────────────
// floor(p * 10 / 7) dipakai, bukan hitung ulang dari harga. Menghitung ulang
// menuntut penggolongan layanan/produk persis seperti create_transaction; satu
// langkah meleset, selisihnya ratusan poin. Penskalaan meleset paling jauh satu.
assert.match(terap, /floor\(t\.points_earned \* 10\.0 \/ 7\.0\)::INT - t\.points_earned/);

const baru = (p) => Math.floor(p * 10 / 7);
const tambahan = (p) => baru(p) - p;

// Angka dari kartu member yang memulai semua ini.
assert.equal(baru(4900), 7000, '4.900 poin pada 7% harus menjadi 7.000 pada 10%');
assert.equal(tambahan(4900), 2100);

// Nilai yang jatuh tepat: 7% dari harga bulat selalu menghasilkan bilangan bulat.
for (const [rupiah, poin7] of [[15000, 1050], [85000, 5950], [100000, 7000], [415000, 29050]]) {
  assert.equal(poin7, Math.floor(rupiah * 0.07), 'bahan uji keliru untuk ' + rupiah);
  assert.equal(baru(poin7), Math.floor(rupiah * 0.10),
    'penskalaan harus setara hitung ulang untuk ' + rupiah);
}

/* Batas kesalahan penskalaan. Versi pertama pemeriksaan ini menuntut paling
   jauh SATU poin dan langsung gagal: pembulatan ke bawah terjadi dua kali,
   dan yang kedua diperbesar faktor 10/7. Batas sebenarnya dua poin.

   Yang lebih penting daripada besarnya: ARAHNYA. Penskalaan tidak pernah
   sekali pun memberi lebih daripada hitung ulang, jadi kesalahan terburuknya
   berpihak pada toko — bukan membagikan poin yang tidak pernah diperoleh. */
let terburuk = 0, pernahLebih = false;
for (let rupiah = 1; rupiah <= 300000; rupiah++) {
  const p7 = Math.floor(rupiah * 0.07);
  if (p7 <= 0) continue;
  const selisih = baru(p7) - Math.floor(rupiah * 0.10);
  if (selisih > 0) pernahLebih = true;
  terburuk = Math.max(terburuk, Math.abs(selisih));
}
assert.equal(terburuk, 2, 'batas melesetnya dua poin — bukan satu, dan bukan lebih');
assert.equal(pernahLebih, false,
  'penskalaan tidak boleh pernah memberi lebih daripada hitung ulang');

// Menjalankan dua kali tidak boleh menambah apa pun: nota yang sudah punya
// baris penanda dilewati penjaga NOT EXISTS.
assert.equal(tambahan(baru(4900)), 3000,
  'tanpa penjaga, pengulangan MEMANG akan menambah lagi — itulah sebabnya '
  + 'penjaga NOT EXISTS di atas wajib ada dan penandanya harus identik');

console.log('Koreksi poin tests: OK');
