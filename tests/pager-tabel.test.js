/* Tabel berhalaman di dashboard owner.
 *
 * Catatan Absensi Harian bisa mencapai hampir seratus baris sebulan. Kini
 * ditampilkan sepuluh per halaman.
 *
 * Yang diuji di sini adalah PERILAKU, bukan susunan huruf: gambarBerhalaman()
 * dipotong dari rekap.html dan dijalankan dengan DOM tiruan. Logika halaman
 * paling sering salah justru di tepinya — halaman terakhir yang tidak penuh,
 * baris yang habis setelah dihapus, nomor halaman yang sudah tidak ada — dan
 * tidak satu pun dari itu terlihat dengan mencocokkan teks.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

const a = rekap.indexOf('const BARIS_PER_HALAMAN');
const b = rekap.indexOf('const gambarUlangTabel');
assert.ok(a > 0 && b > a, 'gambarBerhalaman harus dapat dipotong dari rekap.html');

/* DOM tiruan secukupnya: dua elemen yang dibaca fungsi itu. */
function buatKonteks() {
  const el = { tb: { innerHTML: '' }, nav: { innerHTML: '' } };
  const ctx = {
    document: { getElementById: (id) => (id === 'tb' ? el.tb : id === 'nav' ? el.nav : null) },
    Math,
  };
  vm.createContext(ctx);
  vm.runInContext(rekap.slice(a, b) + '\nthis.gambar = gambarBerhalaman; this.hal = halamanTabel; this.N = BARIS_PER_HALAMAN;', ctx);
  return { ...ctx, el };
}

const baris = (n) => Array.from({ length: n }, (_, i) => ({ i: i + 1 }));
const opsi = { tbody: 'tb', nav: 'nav', kolom: 9, kosong: 'kosong', baris: (r) => '<tr>' + r.i + '</tr>' };
const jmlBaris = (html) => (html.match(/<tr>/g) || []).length;
const isiBaris = (html) => [...html.matchAll(/<tr>(\d+)<\/tr>/g)].map((m) => Number(m[1]));

/* ── 1 · Sepuluh per halaman ─────────────────────────────────────────────── */
{
  const k = buatKonteks();
  assert.equal(k.N, 10, 'ukuran halaman harus 10 baris');
  k.gambar('t', baris(93), opsi);
  assert.equal(jmlBaris(k.el.tb.innerHTML), 10, 'halaman pertama memuat 10 baris');
  assert.deepEqual(isiBaris(k.el.tb.innerHTML), [1,2,3,4,5,6,7,8,9,10]);
  assert.match(k.el.nav.innerHTML, /1&ndash;10 dari 93/);
  assert.match(k.el.nav.innerHTML, /Hal\. 1\/10/, '93 baris = 10 halaman');
}

/* ── 2 · Halaman terakhir yang tidak penuh ───────────────────────────────── */
{
  const k = buatKonteks();
  k.hal.t = 10;
  k.gambar('t', baris(93), opsi);
  assert.deepEqual(isiBaris(k.el.tb.innerHTML), [91, 92, 93], 'halaman terakhir hanya sisa tiga');
  assert.match(k.el.nav.innerHTML, /91&ndash;93 dari 93/);
  // Tombol maju mati di halaman terakhir, tombol mundur hidup.
  assert.match(k.el.nav.innerHTML, /data-ke="11" disabled/, 'tidak boleh maju melewati halaman terakhir');
  assert.doesNotMatch(k.el.nav.innerHTML, /data-ke="9" disabled/);
}

/* ── 3 · Nomor halaman yang sudah tidak ada dijepit, bukan dikosongkan ──────
   Menghapus baris terakhir di halaman 10 dari 10 menyisakan 90 baris — 9
   halaman. Halaman 10 sudah tidak ada. Tanpa penjepitan, owner melihat
   tabel kosong dan mengira datanya hilang. */
{
  const k = buatKonteks();
  k.hal.t = 10;
  k.gambar('t', baris(90), opsi);
  assert.equal(k.hal.t, 9, 'nomor halaman harus dijepit ke halaman terakhir yang sah');
  assert.deepEqual(isiBaris(k.el.tb.innerHTML), [81,82,83,84,85,86,87,88,89,90]);
}

/* ── 4 · Satu halaman saja: tidak ada navigasi ───────────────────────────
   Tombol yang tidak dapat melakukan apa-apa hanya membuat bingung. */
{
  const k = buatKonteks();
  k.gambar('t', baris(10), opsi);
  assert.equal(jmlBaris(k.el.tb.innerHTML), 10);
  assert.equal(k.el.nav.innerHTML, '', 'tepat 10 baris tidak butuh navigasi');

  k.gambar('t', baris(3), opsi);
  assert.equal(k.el.nav.innerHTML, '');
}

/* ── 5 · Kosong ──────────────────────────────────────────────────────────── */
{
  const k = buatKonteks();
  k.hal.t = 4;
  k.gambar('t', [], opsi);
  assert.match(k.el.tb.innerHTML, /colspan="9"[^>]*>kosong</, 'pesan kosong harus merentang seluruh kolom');
  assert.equal(k.el.nav.innerHTML, '', 'navigasi dibersihkan saat tidak ada baris');
}

/* ── 6 · Tiap tabel mengingat halamannya sendiri ─────────────────────────── */
{
  const k = buatKonteks();
  k.hal.satu = 3;
  k.gambar('dua', baris(50), opsi);
  assert.equal(k.hal.satu, 3, 'menggambar tabel lain tidak boleh menggeser halaman tabel ini');
  assert.equal(k.hal.dua, 1);
}

/* ── 7 · Tersambung di tempat yang benar ─────────────────────────────────── */
assert.match(rekap, /<div class="pager" id="absenRowPager"><\/div>/, 'wadah navigasi harus ada di panel absensi');
assert.match(rekap, /gambarBerhalaman\('absen', rows,/, 'Catatan Absensi Harian harus memakai pager');
assert.match(rekap, /gambarUlangTabel\.absen = gambar/, 'tombol halaman harus tahu cara menggambar ulang');

/* Ganti bulan kembali ke halaman 1. Penjepitan menjaga nomornya tetap sah,
   tetapi halaman 9 September tidak bermakna apa-apa untuk Agustus. */
const gantiBulan = rekap.slice(rekap.indexOf("el.addEventListener('change'"),
                               rekap.indexOf('muatSemuaAbsensi();', rekap.indexOf("el.addEventListener('change'")));
assert.match(gantiBulan, /halamanTabel\.absen = 1/, 'ganti bulan harus kembali ke halaman 1');

/* Pemenggalan terjadi di layar, jadi baris yang dimuat tidak boleh berkurang:
   kueri harus tetap mengambil seluruh bulan. */
assert.doesNotMatch(
  rekap.slice(rekap.indexOf('async function muatAbsenBaris'), rekap.indexOf('const satuBaris')),
  /\.range\(|\.limit\(/,
  'kueri tidak boleh dibatasi — pemenggalan terjadi di layar'
);

console.log('pager-tabel: semua pemeriksaan lolos');
