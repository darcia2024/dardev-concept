const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');

/* Sistem tidak punya jalur untuk mendengar dana QRIS masuk. Yang menutup
   celah itu mata kasir, dan gerbang inilah yang memaksanya melihat. Diuji
   dari sumber pos.html supaya tidak menyimpang diam-diam. */
const sumber = pos.slice(
  pos.indexOf('let qrisKonfirmNominal = null;'),
  pos.indexOf('function renderQrisKonfirm()')
);
assert.ok(sumber.length > 0, 'blok gerbang konfirmasi QRIS harus tersedia');

function buatGerbang(metode, total) {
  const api = new Function('metode', 'total', `
    let selectedPaymentMethod = metode;
    const totalTagihan = () => total;
    ${sumber}
    return {
      perlu: qrisPerluKonfirmasi,
      sudah: qrisSudahKonfirm,
      set: (n) => { qrisKonfirmNominal = n; },
      get: () => qrisKonfirmNominal
    };
  `);
  return api(metode, total);
}

// ── 1 · Hanya QRIS yang dijaga ─────────────────────────────────────────────
for (const metode of ['Tunai', 'EDC', 'Transfer']) {
  const g = buatGerbang(metode, 85000);
  assert.equal(g.perlu(), false, metode + ' tidak boleh ikut ditahan');
  assert.equal(g.sudah(), true, metode + ' harus lolos tanpa konfirmasi');
}

const kosong = buatGerbang('QRIS', 0);
assert.equal(kosong.perlu(), false, 'tagihan nol tidak perlu dikonfirmasi');
assert.equal(kosong.sudah(), true);

// ── 2 · QRIS ditahan sampai dikonfirmasi ───────────────────────────────────
const g = buatGerbang('QRIS', 85000);
assert.equal(g.perlu(), true);
assert.equal(g.sudah(), false, 'QRIS harus ditahan sebelum kasir mengonfirmasi');

g.set(85000);
assert.equal(g.sudah(), true, 'konfirmasi pada nominal yang sama harus lolos');

// ── 3 · Konfirmasi terikat pada NOMINAL, bukan sekadar "sudah ditekan" ─────
// Inti gerbang ini. Sebuah boolean akan tetap menyala ketika kasir menambah
// satu layanan lagi sesudah memeriksa notifikasi, dan nota tersimpan atas
// pemeriksaan yang sebenarnya menyangkut jumlah lain.
const naik = buatGerbang('QRIS', 100000);
naik.set(85000);                       // dikonfirmasi saat tagihan masih 85rb
assert.equal(naik.sudah(), false,
  'konfirmasi harus gugur begitu tagihan bergeser dari yang diperiksa');

const turun = buatGerbang('QRIS', 70000);
turun.set(85000);
assert.equal(turun.sudah(), false, 'tagihan yang turun pun harus memaksa periksa ulang');

// Nol bukan "belum dikonfirmasi": keduanya harus terbedakan.
const nol = buatGerbang('QRIS', 85000);
nol.set(0);
assert.equal(nol.sudah(), false, 'nominal 0 tidak boleh dianggap konfirmasi sah');

// ── 4 · Terpasang pada tombol simpan ───────────────────────────────────────
// Tombol yang mati di depan mata lebih jelas daripada nota yang ditolak
// sesudah ditekan — tetapi keduanya harus ada.
const cart = pos.slice(pos.indexOf('function updateCartView'),
                       pos.indexOf('/* Pilihan capster per layanan'));
assert.match(cart, /submitBtn\.disabled = !\(hasCapster && hasServices && qrisSudahKonfirm\(\)\)/,
  'tombol simpan harus ikut ditahan gerbang QRIS');

const submit = pos.slice(pos.indexOf("getElementById('btnSubmitTransaction')"),
                         pos.indexOf('const rawPhone'));
assert.match(submit, /if \(!qrisSudahKonfirm\(\)\)/, 'penjaga kedua di penangan simpan harus ada');

// ── 5 · Konfirmasi tidak boleh menetes ─────────────────────────────────────
const reset = pos.slice(pos.indexOf('function resetPOSForm'), pos.indexOf("getElementById('btnNewTransaction')"));
assert.match(reset, /qrisKonfirmNominal = null/, 'nota baru harus mulai tanpa konfirmasi');

// Penanda akhir dipilih yang khas penangan kliknya. "btnQrisKonfirm" saja
// muncul lebih dulu di dalam renderQrisKonfirm, dan potongannya jadi kosong.
const AWAL_TOMBOL = "btnQrisKonfirm').addEventListener";
assert.notEqual(pos.indexOf(AWAL_TOMBOL), -1, 'penangan klik tombol konfirmasi harus ada');

const pindahMetode = pos.slice(pos.indexOf('// Payment Method Switching'), pos.indexOf(AWAL_TOMBOL));
assert.ok(pindahMetode.length > 0, 'blok pindah metode harus dapat dipotong');
assert.match(pindahMetode, /qrisKonfirmNominal = null/, 'pindah metode bayar harus membatalkan konfirmasi');

// Tombolnya memang ada, dan dapat dibatalkan bila kasir keliru menekan.
assert.match(pos, /id="btnQrisKonfirm"/);
const tombol = pos.slice(pos.indexOf(AWAL_TOMBOL), pos.indexOf(AWAL_TOMBOL) + 400);
assert.match(tombol, /qrisSudahKonfirm\(\) \? null : totalTagihan\(\)/,
  'menekan ulang harus membatalkan, bukan mengunci selamanya');

console.log('Konfirmasi QRIS tests: OK');
