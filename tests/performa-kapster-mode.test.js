const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

/* Mode "tanpa omzet" ada supaya daftar performa dapat dikirim ke grup
   kapster. Kegagalan yang dijaga di sini cuma satu, tetapi tidak dapat
   ditarik kembali: satu angka rupiah yang lolos ke teks yang ditempel ke
   grup memberitahu setiap kapster pendapatan rekannya. */
const sumber = rekap.slice(
  rekap.indexOf('let performaKapster = [];'),
  rekap.indexOf('function renderDashboard()')
);
assert.ok(sumber.length > 0, 'blok performa kapster harus tersedia');

function buat(mode, periode) {
  return new Function('mode', 'periode', `
    const formatRupiah = n => 'Rp ' + Number(n || 0).toLocaleString('id-ID');
    const escapeHtml = s => String(s).replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
    const document = {
      getElementById: () => null,
      querySelectorAll: () => [],
      querySelector: () => (periode ? { textContent: periode } : null)
    };
    ${sumber}
    modePerforma = mode;
    performaKapster = [
      ['Cena',   { omzet: 850000, heads: 6,  layanan: { Haircut: 4, Hairwash: 2 } }],
      ['Lukman', { omzet: 415000, heads: 11, layanan: { Haircut: 5, Hairwash: 6 } }],
      ['Wanda',  { omzet: 620000, heads: 4,  layanan: { Haircut: 4 } }]
    ];
    return { urut: performaTerurut, teks: performaSebagaiTeks };
  `)(mode, periode);
}

// ── 1 · Urutan harus cocok dengan angka yang terlihat ──────────────────────
// Mengurutkan menurut omzet sementara yang tampil jumlah layanan membuat
// daftarnya terbaca seperti salah urut oleh orang yang tidak melihat omzetnya.
const dgn = buat('omzet');
assert.deepEqual(dgn.urut().map(x => x[0]), ['Cena', 'Wanda', 'Lukman'],
  'mode omzet diurutkan menurut omzet');

const tanpa = buat('tanpa');
assert.deepEqual(tanpa.urut().map(x => x[0]), ['Lukman', 'Cena', 'Wanda'],
  'mode tanpa omzet diurutkan menurut jumlah layanan');

// ── 2 · Teks bagikan: tidak boleh ada rupiah sama sekali ───────────────────
const teksTanpa = buat('tanpa').teks();
assert.doesNotMatch(teksTanpa, /Rp/, 'teks bagikan tidak boleh memuat lambang rupiah');
for (const angka of ['850.000', '415.000', '620.000', '850000', '415000', '620000']) {
  assert.ok(!teksTanpa.includes(angka), 'omzet ' + angka + ' bocor ke teks bagikan');
}
// Yang justru harus ada: nama, peringkat, dan jumlah kerjanya.
for (const nama of ['Cena', 'Lukman', 'Wanda']) assert.ok(teksTanpa.includes(nama));
/* Rincian, bukan angka gabungan. "4 pangkas & layanan" terbaca sama antara
   empat potong dan dua potong dua cuci — dan kapster yang menerimanya di grup
   membantah daftar yang sebenarnya benar. Diurutkan menurut jumlah, jadi
   Hairwash 6 berdiri sebelum Haircut 5. */
assert.match(teksTanpa, /1\. Lukman — 6 Hairwash · 5 Haircut/,
  'peringkat dan rincian layanan harus tertulis');
assert.equal(teksTanpa.indexOf('pangkas & layanan'), -1,
  'kalimat gabungan yang membingungkan tidak boleh tersisa');
assert.match(teksTanpa, /Total: 13 Haircut · 8 Hairwash\./,
  'totalnya pun harus dirinci, bukan dijumlahkan menjadi satu angka');

// Mode pemilik tetap memuat omzetnya — yang lama tidak boleh ikut hilang.
const teksDgn = buat('omzet').teks();
assert.match(teksDgn, /Rp/, 'mode dengan omzet harus tetap memuat rupiah');
assert.match(teksDgn, /Cena — 4 Haircut · 2 Hairwash · Rp 850\.000/);

// Periode ikut terbawa supaya penerima tahu daftar ini tentang rentang mana.
assert.match(buat('tanpa', 'Hari Ini').teks(), /^\*Performa Kapster\* — Hari Ini/);
assert.doesNotMatch(buat('tanpa').teks(), /—\s*$/m);

// Daftar kosong tidak menghasilkan teks setengah jadi.
const sepi = new Function(`
  const formatRupiah = n => 'Rp ' + n;
  const escapeHtml = s => String(s);
  const document = { getElementById: () => null, querySelectorAll: () => [], querySelector: () => null };
  ${sumber}
  performaKapster = [];
  return performaSebagaiTeks();
`)();
assert.equal(sepi, '', 'tanpa data, teks bagikan harus kosong dan ditolak pemanggilnya');

// ── 3 · HTML yang benar-benar tergambar ────────────────────────────────────
// Regex atas sumber tidak membuktikan hasilnya: templat yang salah tetap
// cocok polanya namun menggambar sampah.
function gambar(mode) {
  return new Function('mode', `
    const formatRupiah = n => 'Rp ' + Number(n || 0).toLocaleString('id-ID');
    const escapeHtml = s => String(s).replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
    const wadah = { innerHTML: '' };
    const document = {
      getElementById: (id) => (id === 'capsterPerfContainer' ? wadah : null),
      querySelectorAll: () => [],
      querySelector: () => null
    };
    ${sumber}
    modePerforma = mode;
    performaKapster = [
      ['Cena',   { omzet: 850000, heads: 6,  layanan: { Haircut: 4, Hairwash: 2 } }],
      ['Lukman', { omzet: 415000, heads: 11, layanan: { Haircut: 5, Hairwash: 6 } }]
    ];
    renderPerformaKapster();
    return wadah.innerHTML;
  `)(mode);
}

const htmlTanpa = gambar('tanpa');
assert.doesNotMatch(htmlTanpa, /Rp/, 'HTML mode bagikan tidak boleh memuat rupiah');
assert.doesNotMatch(htmlTanpa, /850\.000|415\.000/, 'angka omzet tidak boleh tergambar');
assert.match(htmlTanpa, /class="capster-rank">1</, 'peringkat harus tergambar');
assert.match(htmlTanpa, /Lukman/);
assert.match(htmlTanpa, /6 Hairwash · 5 Haircut/, 'rincian harus tergambar di kartu');
assert.equal(htmlTanpa.indexOf('pangkas &amp; layanan'), -1,
  'kalimat gabungan tidak boleh tersisa di layar');

const htmlDgn = gambar('omzet');
assert.match(htmlDgn, /capster-omzet">Rp 850\.000/, 'mode pemilik harus tetap menampilkan omzet');
assert.doesNotMatch(htmlDgn, /capster-rank/, 'peringkat hanya untuk mode bagikan');

// Nama dari basis data ikut disaring. Sebelumnya nama disisipkan mentah.
const jahat = new Function(`
  const formatRupiah = n => 'Rp ' + n;
  const escapeHtml = s => String(s).replace(/[&<>"]/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const wadah = { innerHTML: '' };
  const document = {
    getElementById: (id) => (id === 'capsterPerfContainer' ? wadah : null),
    querySelectorAll: () => [], querySelector: () => null
  };
  ${sumber}
  modePerforma = 'omzet';
  performaKapster = [['<img src=x onerror=alert(1)>',
    { omzet: 1000, heads: 1, layanan: { '<svg onload=alert(2)>': 1 } }]];
  renderPerformaKapster();
  return wadah.innerHTML;
`)();
assert.doesNotMatch(jahat, /<img src=x/, 'nama kapster harus disaring sebelum disisipkan');
assert.match(jahat, /&lt;img src=x/);
// Nama LAYANAN kini ikut digambar; itu titik masuk yang sebelumnya tidak ada.
assert.doesNotMatch(jahat, /<svg onload/, 'nama layanan harus ikut disaring');
assert.match(jahat, /&lt;svg onload/);

// ── 4 · Mode pemilik tidak dihapus ─────────────────────────────────────────
assert.match(rekap, /data-perf="omzet"/, 'mode dengan omzet harus tetap dapat dipilih');
assert.match(rekap, /data-perf="tanpa"/);
assert.match(rekap, /class="capster-omzet"/, 'baris omzet tidak boleh dibuang');

// Yang tergambar mengikuti mode yang sedang tampil, sehingga tidak ada cara
// tak sengaja menyalin angka dari layar yang menyembunyikannya.
const render = rekap.slice(rekap.indexOf('function renderPerformaKapster()'),
                           rekap.indexOf('function performaSebagaiTeks()'));
assert.match(render, /modePerforma === 'tanpa'[\s\S]*capster-omzet/,
  'omzet hanya digambar pada mode omzet');

// ── 5 · Pemilih periode tidak boleh menabrak tombol mode ───────────────────
/* Dulu periode dipilih lewat tombol ber-kelas .btn-filter-date, kelas yang
   sama dengan tombol mode di sini — menekan "Tanpa Omzet" ikut mengosongkan
   periode. Sejak periode menjadi dropdown, benturan itu hilang seluruhnya.

   Versi awal pemeriksaan ini memakai rekap.slice(rekap.indexOf(...)).length > 0
   dan TIDAK PERNAH BISA GAGAL: indexOf mengembalikan -1 saat tidak ketemu, dan
   slice(-1) mengembalikan satu karakter terakhir. */
assert.match(rekap, /<select id="selPeriode"/, 'periode harus dipilih lewat dropdown');
assert.equal(rekap.indexOf('data-range='), -1, 'tombol periode lama tidak boleh tersisa');

// Tombol mode tetap disaring lewat [data-perf], bukan lewat kelasnya — kelas
// .btn-filter-date masih dipakai belasan tombol lain di halaman ini.
assert.notEqual(rekap.indexOf("querySelectorAll('[data-perf]')"), -1,
  'tombol mode harus disaring lewat [data-perf]');
assert.equal(rekap.indexOf("querySelectorAll('.btn-filter-date')"), -1,
  'tidak boleh ada penangan yang menyapu seluruh .btn-filter-date');

console.log('Mode performa kapster tests: OK');
