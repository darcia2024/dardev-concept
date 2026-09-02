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

// ── 6 · Payload QRIS bersumber dari server ─────────────────────────────────
const migrasi = fs.readFileSync(path.join(root, 'supabase_migration_44_qris_dinamis.sql'), 'utf8');

// Delimiter $function$ harus berpasangan; yang ganjil membuat seluruh berkas
// gagal dijalankan di Supabase dan itu baru ketahuan saat ditempel.
assert.equal((migrasi.match(/\$function\$/g) || []).length % 2, 0,
  'penanda $function$ harus genap');

// Tak satu pun fungsi baru boleh terbuka untuk anon: halaman depan publik
// memakai kunci anon yang sama.
for (const fn of ['pos_qris_config()', 'owner_set_qris(TEXT)',
                  'tandai_qris_konfirmasi(UUID)', 'owner_qris_belum_konfirmasi(DATE)']) {
  assert.ok(migrasi.includes('REVOKE EXECUTE ON FUNCTION ' + fn + ' FROM PUBLIC, anon;'),
    fn + ' harus dicabut dari anon');
}
// Yang mengubah dan yang membaca daftar pantau hanya owner.
for (const fn of ['owner_set_qris', 'owner_qris_belum_konfirmasi']) {
  const badan = migrasi.slice(migrasi.indexOf('FUNCTION ' + fn), migrasi.indexOf('REVOKE EXECUTE ON FUNCTION ' + fn));
  assert.match(badan, /IF NOT is_owner\(\) THEN/, fn + ' harus dijaga is_owner()');
}
assert.match(migrasi.slice(migrasi.indexOf('FUNCTION pos_qris_config')), /auth\.uid\(\) IS NULL/,
  'pos_qris_config harus menolak perangkat tak terdaftar');

// Penandaan ulang tidak boleh menggeser waktu pemeriksaan yang sebenarnya.
const tandai = migrasi.slice(migrasi.indexOf('FUNCTION tandai_qris_konfirmasi'),
                             migrasi.indexOf('REVOKE EXECUTE ON FUNCTION tandai_qris_konfirmasi'));
assert.match(tandai, /COALESCE\(t\.qris_konfirmasi_at, now\(\)\)/,
  'penandaan ulang harus mempertahankan waktu pertama');
assert.match(tandai, /payment_method = 'QRIS'/, 'hanya nota QRIS yang ditandai');

// create_transaction sengaja tidak disentuh. Menyalin ulang 306 baris demi
// satu penanda menaruh seluruh jalur penjualan pada risiko yang tidak sepadan.
assert.doesNotMatch(migrasi, /FUNCTION (public\.)?create_transaction/,
  'migrasi ini tidak boleh menulis ulang create_transaction');

// POS membaca dari server, dan salinan lokal hanya cadangan luring.
assert.match(pos, /sb\.rpc\('pos_qris_config'\)/, 'POS harus memuat payload dari server');
const simpanQris = pos.slice(pos.indexOf("btnSaveQris').addEventListener"),
                             pos.indexOf("btnHapusQris').addEventListener"));
assert.match(simpanQris, /sb\.rpc\('owner_set_qris'/, 'menyimpan harus lewat server');
assert.ok(simpanQris.indexOf("sb.rpc('owner_set_qris'") < simpanQris.indexOf('localStorage.setItem'),
  'salinan lokal baru ditulis SESUDAH server menerima, supaya perangkat ini '
  + 'tidak memakai payload yang gagal tersimpan');

// Penandaan dikirim sesudah nota tersimpan, dan kegagalannya tidak menjatuhkan
// apa pun — notanya sudah sah dan uangnya sudah masuk.
const kirim = pos.slice(pos.indexOf("sb.rpc('tandai_qris_konfirmasi'") - 700,
                        pos.indexOf("sb.rpc('tandai_qris_konfirmasi'") + 300);
assert.match(kirim, /if \(res\.tx && selectedPaymentMethod === 'QRIS'\)/,
  'penandaan hanya untuk nota QRIS yang benar-benar tersimpan di server');
assert.match(kirim, /try \{[\s\S]*catch/, 'gagalnya penandaan harus ditelan');

// ── 7 · Daftar pantau pemilik ──────────────────────────────────────────────
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
assert.match(rekap, /sb\.rpc\('owner_qris_belum_konfirmasi'/);
const pantau = rekap.slice(rekap.indexOf('async function muatQrisPantau'),
                           rekap.indexOf('function renderDashboard()'));
assert.match(pantau, /if \(!baris\.length\) \{ panel\.hidden = true; return; \}/,
  'panel harus sembunyi saat tidak ada yang perlu dikerjakan');
assert.match(pantau, /escapeHtml\(r\.invoice_no/, 'isi dari basis data harus disaring');
// Kalimatnya tidak boleh menuduh: penanda yang hilang bukan bukti dana tidak masuk.
assert.match(pantau, /belum tentu berarti dananya tidak masuk/);

console.log('Konfirmasi QRIS tests: OK');
