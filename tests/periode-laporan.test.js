const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

/* Periode laporan pernah tersebar di empat tempat dengan bentuk berbeda, dan
   kuerinya terkunci 30 hari — sehingga "Semua Riwayat" pun tidak pernah
   menampilkan lebih dari sebulan. Kegagalan seperti itu tidak terbaca sebagai
   galat: layarnya menunjukkan angka yang tampak wajar, hanya saja kurang. */
const sumber = rekap.slice(rekap.indexOf('const PERIODE = {'),
                           rekap.indexOf('/** Ambil transaksi langsung dari Supabase'));
assert.notEqual(rekap.indexOf('const PERIODE = {'), -1, 'tabel PERIODE harus tersedia');
assert.ok(sumber.length > 0);

// Waktu dibekukan supaya hasilnya tidak bergantung pada jam berapa tes berjalan.
const BEKU = Date.parse('2026-09-10T05:00:00Z');   // 10 Sep 2026, 12:00 WIB
function api() {
  // Date asli dioper sebagai argumen: menulis `const Date_ = Date` di dalam
  // scope yang juga mendeklarasikan `const Date` kena temporal dead zone.
  return new Function('BEKU', 'DateAsli', `
    const Date = class extends DateAsli {
      constructor(...a) { super(...(a.length ? a : [BEKU])); }
      static now() { return BEKU; }
    };
    ${sumber}
    let selectedDateFilter = 'TODAY';
    return {
      PERIODE,
      rentang: rentangPeriode,
      label: (k) => { selectedDateFilter = k; return labelPeriode(); }
    };
  `)(BEKU, Date);
}
const A = api();

// ── 1 · Pilihan yang diminta pemilik ada semuanya ──────────────────────────
assert.deepEqual(Object.keys(A.PERIODE),
  ['TODAY', 'YESTERDAY', 'D7', 'D30', 'D90', 'D180', 'D365', 'ALL'],
  'urutan pilihan harus dari yang terpendek ke terpanjang');

// ── 2 · Periode satu hari benar-benar satu hari ────────────────────────────
assert.deepEqual(A.rentang('TODAY'),     { dari: '2026-09-10', sampai: '2026-09-10' });
assert.deepEqual(A.rentang('YESTERDAY'), { dari: '2026-09-09', sampai: '2026-09-09' });

// ── 3 · Rentang panjang INKLUSIF hari ini ──────────────────────────────────
// "7 hari" berarti hari ini beserta enam hari sebelumnya, bukan tujuh hari
// sebelum hari ini. Salah satu hari di sini menggeser seluruh laporan.
assert.deepEqual(A.rentang('D7'),   { dari: '2026-09-04', sampai: '2026-09-10' });
assert.deepEqual(A.rentang('D30'),  { dari: '2026-08-12', sampai: '2026-09-10' });
assert.deepEqual(A.rentang('D90'),  { dari: '2026-06-13', sampai: '2026-09-10' });
assert.deepEqual(A.rentang('D180'), { dari: '2026-03-15', sampai: '2026-09-10' });
assert.deepEqual(A.rentang('D365'), { dari: '2025-09-11', sampai: '2026-09-10' });

// Jumlah harinya harus persis seperti namanya.
const hari = (r) => Math.round((Date.parse(r.sampai) - Date.parse(r.dari)) / 864e5) + 1;
assert.equal(hari(A.rentang('D7')),   7);
assert.equal(hari(A.rentang('D30')),  30);
assert.equal(hari(A.rentang('D365')), 365);

// ── 4 · Semua Riwayat tanpa batas di kedua sisi ────────────────────────────
assert.deepEqual(A.rentang('ALL'), { dari: null, sampai: null });

// Kunci yang tidak dikenal jatuh ke hari ini, bukan ke tanpa batas — menarik
// setahun penuh karena salah ketik adalah kegagalan yang mahal di ponsel.
assert.deepEqual(A.rentang('ENTAH'), A.rentang('TODAY'));

// ── 5 · Label dipakai bersama layar dan teks bagikan ───────────────────────
assert.equal(A.label('D90'), '3 Bulan Terakhir');
assert.equal(A.label('ENTAH'), 'Hari Ini');

// ── 6 · Kueri benar-benar mengikuti rentangnya ─────────────────────────────
// Inti perbaikannya. Dengan batas 30 hari yang lama, memilih "3 Bulan"
// menampilkan layar kosong untuk bulan yang datanya memang tidak diambil.
const muat = rekap.slice(rekap.indexOf('async function loadData()'),
                         rekap.indexOf('capstersData = capRes.data'));
assert.ok(muat.length > 0, 'loadData harus dapat dipotong');
assert.equal(muat.indexOf('30 * 864e5'), -1, 'batas 30 hari tetap tidak boleh ada lagi');
assert.match(muat, /qTx\.gte\('business_date', r\.dari\)/);
assert.match(muat, /qTx\.lte\('business_date', r\.sampai\)/);

// Berganti periode harus MEMUAT ULANG, bukan sekadar menyaring yang sudah ada:
// data periode yang lebih panjang belum pernah diambil.
const ganti = rekap.slice(rekap.indexOf("getElementById('selPeriode').addEventListener"));
assert.notEqual(rekap.indexOf("getElementById('selPeriode').addEventListener"), -1,
  'dropdown periode harus punya penangan');
assert.match(ganti.slice(0, 900), /await loadData\(\)/, 'ganti periode harus memuat ulang');
assert.match(ganti.slice(0, 900), /sel\.disabled = true/,
  'pemilihnya dikunci selama memuat supaya permintaan tidak menumpuk');

// Setoran kas ikut rentang yang sama, tidak lagi terpaku satu hari.
const kas = rekap.slice(rekap.indexOf('async function loadClosings()'),
                        rekap.indexOf('function renderClosings()'));
assert.match(kas, /gte\('business_date', r\.dari\)/, 'setoran kas harus ikut rentang');
assert.match(kas, /lte\('business_date', r\.sampai\)/);

console.log('Periode laporan tests: OK');
