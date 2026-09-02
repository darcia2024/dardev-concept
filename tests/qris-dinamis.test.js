const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');

/* Konverter QRIS diambil langsung dari pos.html, bukan disalin ke sini.
   Salinan akan menyimpang diam-diam, dan penyimpangan pada CRC menghasilkan
   QR yang tampak wajar tetapi ditolak aplikasi bank — kegagalan yang baru
   ketahuan di depan pelanggan. */
const sumber = pos.slice(
  pos.indexOf('const QRIS_KUNCI'),
  pos.indexOf('/* ── akhir QRIS statis → dinamis')
);
assert.ok(sumber.length > 0, 'blok konverter QRIS harus tersedia di pos.html');

const { qrisCrc16, qrisUrai, qrisDinamis } = new Function(
  sumber + '; return { qrisCrc16, qrisUrai, qrisDinamis };'
)();

// ── 1 · CRC harus benar ────────────────────────────────────────────────────
// Dua rujukan luar, bukan hasil hitungan sendiri. Menguji CRC dengan angka
// yang dihasilkan rumus yang sama persis tidak membuktikan apa pun.

// Nilai periksa baku CRC-16/CCITT-FALSE.
assert.equal(qrisCrc16('123456789'), '29B1', 'CRC-16/CCITT-FALSE("123456789") harus 29B1');

// Contoh resmi spesifikasi EMVCo. Memuat aksara Han, sehingga sekaligus
// membuktikan CRC dihitung atas byte UTF-8 dan bukan unit UTF-16.
const EMVCO = '00020101021229300012D156000000000510A93FO3230Q31280012D1560000000103081234'
  + '5678520441115802CN5914BEST TRANSPORT6007BEIJING64200002ZH0104最佳运输0202北京540523.72'
  + '53031565502016233030412340603***0708A60086670902ME91320016A011223344998877070812345678'
  + '6304A13A';
assert.equal(qrisCrc16(EMVCO.slice(0, -4)), 'A13A', 'contoh resmi EMVCo harus menghasilkan A13A');

// ── 2 · Bahan uji: QRIS statis Indonesia yang sah ──────────────────────────
function tlv(t, v) { return t + String(v.length).padStart(2, '0') + v; }
const merchant = tlv('00', 'ID.CO.QRIS.WWW') + tlv('02', 'ID1234567890123') + tlv('03', 'UMI');
const badan = tlv('00', '01') + tlv('01', '11') + tlv('26', merchant)
  + tlv('52', '5812') + tlv('53', '360') + tlv('58', 'ID')
  // Nama merchant sengaja berspasi: pernah ada versi yang membuang seluruh
  // spasi saat membersihkan salin-tempel, dan itu merusak payload sekaligus
  // panjang tag yang sudah tertulis di dalamnya.
  + tlv('59', 'UNDERRATED BARBERSHOP') + tlv('60', 'BSD CITY') + tlv('61', '15310');
const STATIS = badan + '6304' + qrisCrc16(badan + '6304');

const peta = function (s) {
  return Object.fromEntries(qrisUrai(s.slice(0, -8)).map(function (x) { return [x.tag, x.val]; }));
};

// ── 3 · Perubahan yang dimaksud, dan hanya itu ─────────────────────────────
const DIN = qrisDinamis(STATIS, 85000);
const a = peta(STATIS), b = peta(DIN);

assert.equal(a['01'], '11', 'bahan uji harus statis');
assert.equal(b['01'], '12', 'tag 01 harus menjadi 12 (dinamis)');
assert.equal(a['54'], undefined, 'QRIS statis tidak boleh punya nominal');
assert.equal(b['54'], '85000', 'nominal harus tersuntik di tag 54');

for (const tag of ['00', '26', '52', '53', '58', '59', '60', '61']) {
  assert.equal(b[tag], a[tag], 'tag ' + tag + ' milik acquirer tidak boleh berubah');
}
assert.equal(b['59'], 'UNDERRATED BARBERSHOP', 'spasi pada nama merchant harus utuh');

// Checksum hasil harus sah, kalau tidak seluruh QR ditolak.
assert.equal(qrisCrc16(DIN.slice(0, -4)), DIN.slice(-4), 'CRC hasil harus dihitung ulang');
assert.notEqual(DIN.slice(-4), STATIS.slice(-4), 'CRC tidak boleh diwarisi begitu saja');

// Tag menaik: 54 harus mendarat antara 53 dan 58, bukan diempaskan ke ekor.
const urutan = qrisUrai(DIN.slice(0, -8)).map(function (x) { return x.tag; });
assert.deepEqual(urutan, ['00', '01', '26', '52', '53', '54', '58', '59', '60', '61'],
  'tag 54 harus disisipkan menurut urutan menaik');

// ── 4 · Mengubah nominal mengganti, bukan menumpuk ─────────────────────────
const DIN2 = qrisDinamis(DIN, 120000);
assert.equal(peta(DIN2)['54'], '120000');
assert.equal(qrisUrai(DIN2.slice(0, -8)).filter(function (x) { return x.tag === '54'; }).length, 1,
  'nominal lama harus diganti, bukan ditambahkan sebagai tag kedua');
assert.equal(qrisCrc16(DIN2.slice(0, -4)), DIN2.slice(-4));

// Nominal berkoma dibulatkan ke rupiah utuh; QRIS tidak mengenal sen.
assert.equal(peta(qrisDinamis(STATIS, 85000.4))['54'], '85000');

// ── 5 · Yang harus ditolak ─────────────────────────────────────────────────
// Menerima payload cacat lebih buruk daripada menolaknya: QR-nya tetap
// tergambar, pelanggan tetap memindai, dan gagalnya baru terlihat di kasir.
const tolak = [
  ['payload kosong', '', 10000],
  ['bukan QRIS', 'halo dunia', 10000],
  ['checksum dirusak', STATIS.slice(0, -4) + '0000', 10000],
  ['payload terpotong', STATIS.slice(0, 40), 10000],
  ['nominal nol', STATIS, 0],
  ['nominal minus', STATIS, -5000],
  ['nominal bukan angka', STATIS, 'delapan puluh ribu']
];
for (const [nama, payload, nominal] of tolak) {
  assert.throws(function () { qrisDinamis(payload, nominal); }, Error, nama + ' harus ditolak');
}

// Spasi di tengah payload tidak boleh "diperbaiki" diam-diam: itu tanda
// salinan rusak, dan menambalnya menghasilkan QR yang salah tanpa peringatan.
assert.throws(function () {
  qrisDinamis(STATIS.slice(0, 30) + ' ' + STATIS.slice(30), 10000);
}, Error, 'spasi sisipan harus tertangkap checksum');

// Baris baru dan tab dari salin-tempel justru harus dimaafkan.
const terlipat = STATIS.slice(0, 60) + '\n' + STATIS.slice(60, 100) + '\t' + STATIS.slice(100);
assert.equal(qrisDinamis(terlipat, 85000), DIN, 'baris baru dan tab harus dibersihkan');
assert.equal(qrisDinamis('  ' + STATIS + '\n', 85000), DIN, 'spasi di ujung harus dipangkas');

// Tetapi spasi di TENGAH tidak ditambal, sekalipun berdampingan dengan baris
// baru. Spasi sah muncul di nama merchant, jadi tidak ada cara membedakan
// indentasi dari isi — dan menebak berarti menghasilkan QR salah tanpa
// peringatan. Checksum harus menolaknya dengan berisik.
assert.throws(function () {
  qrisDinamis(STATIS.slice(0, 60) + '\n  ' + STATIS.slice(60), 85000);
}, /Checksum/, 'indentasi setelah baris baru harus tertangkap, bukan ditambal');

// QRIS negara lain dan mata uang selain Rupiah bukan wilayah kerja alat ini.
const asing = badan.replace(tlv('58', 'ID'), tlv('58', 'SG'));
assert.throws(function () { qrisDinamis(asing + '6304' + qrisCrc16(asing + '6304'), 10000); },
  /bukan terbitan Indonesia/);

const rupiahLain = badan.replace(tlv('53', '360'), tlv('53', '702'));
assert.throws(function () { qrisDinamis(rupiahLain + '6304' + qrisCrc16(rupiahLain + '6304'), 10000); },
  /bukan Rupiah/);

// ── 6 · Terpasang di alur kasir ────────────────────────────────────────────
// Nominal yang basi lebih berbahaya daripada tidak ada QR: pelanggan membayar
// angka nota sebelumnya. QR harus digambar ulang tiap tagihan berubah.
assert.match(pos, /function renderQrisDinamis\(\)/);
const cart = pos.slice(pos.indexOf('function updateCartView'),
                       pos.indexOf('/* Pilihan capster per layanan'));
assert.ok(cart.length > 0, 'updateCartView harus dapat dipotong');
assert.match(cart, /renderQrisDinamis\(\)/, 'keranjang berubah harus menggambar ulang QR');
const bayar = pos.slice(pos.indexOf('// Payment Method Switching'), pos.indexOf('// Process Transaction'));
assert.match(bayar, /renderQrisDinamis\(\)/, 'pindah metode bayar harus menggambar ulang QR');

// Payload disimpan hanya setelah lulus konversi percobaan.
const simpan = pos.slice(pos.indexOf("getElementById('btnSaveQris')"), pos.indexOf("getElementById('btnHapusQris')"));
assert.match(simpan, /qrisDinamis\(nilai, 10000\)/, 'payload harus diuji sebelum disimpan');
assert.ok(simpan.indexOf('qrisDinamis(nilai, 10000)') < simpan.indexOf('localStorage.setItem'),
  'pengujian harus mendahului penyimpanan');

// Gagal menggambar harus jatuh ke stiker meja, bukan layar kosong tanpa jalan
// keluar bagi kasir.
const render = pos.slice(pos.indexOf('function renderQrisDinamis'), pos.indexOf('// Payment Method Switching'));
assert.match(render, /catch/, 'kegagalan harus ditangkap');
assert.match(render, /Gunakan stiker di meja/, 'kasir harus diberi jalan keluar');

// Halaman harus benar-benar memuat penggambar QR-nya.
assert.match(pos, /<script src="vendor\/qrcode\.js"><\/script>/);

console.log('QRIS dinamis tests: OK');
