const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const landing = fs.readFileSync(path.join(root, 'landing.html'), 'utf8');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase_migration_25_booking_hardening.sql'),
  'utf8'
);
const migrationJamTutup = fs.readFileSync(
  path.join(root, 'supabase_migration_26_jam_tutup.sql'),
  'utf8'
);

const berkasMigrasi = fs
  .readdirSync(root)
  .filter(nama => /^supabase_migration_\d+.*\.sql$/.test(nama))
  .sort((a, b) => parseInt(a.match(/\d+/)[0], 10) - parseInt(b.match(/\d+/)[0], 10));
const berkasCreateBooking = berkasMigrasi
  .filter(nama =>
    /CREATE OR REPLACE FUNCTION create_booking/.test(
      fs.readFileSync(path.join(root, nama), 'utf8')
    )
  )
  .at(-1);
assert.ok(berkasCreateBooking, 'harus ada migrasi yang mendefinisikan create_booking');
const migrationBooking = fs.readFileSync(path.join(root, berkasCreateBooking), 'utf8');

function extractFunctionSource(source, functionName) {
  const start = source.indexOf(`function ${functionName}`);
  assert.notEqual(start, -1, `${functionName} harus tersedia`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Penutup ${functionName} tidak ditemukan`);
}

// rekap.html dan capster.html ikut diperiksa sejak keduanya menyusun markup
// foto kapster sendiri. Sebelumnya keduanya tidak pernah diurai sama sekali,
// jadi satu kutip yang hilang di sana lolos sampai ke layar orang.
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const capster = fs.readFileSync(path.join(root, 'capster.html'), 'utf8');

for (const [name, html] of [['landing.html', landing], ['pos.html', pos],
                            ['rekap.html', rekap], ['capster.html', capster]]) {
  for (const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    if (match[1].trim()) new Function(match[1]);
  }
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length, `${name} tidak boleh punya ID ganda`);
}

const slotSource = extractFunctionSource(landing, 'buatSlotBooking');
const buatSlotBooking = new Function(`${slotSource}; return buatSlotBooking;`)();

assert.deepEqual(
  buatSlotBooking(600, 1260, 45, 600).slice(-2),
  ['19:30', '20:00'],
  'layanan 45 menit harus selesai sebelum pukul 21.00'
);
assert.equal(
  buatSlotBooking(600, 1260, 150, 600).at(-1),
  '18:30',
  'layanan 150 menit terakhir dimulai pukul 18.30'
);
assert.equal(buatSlotBooking(600, 1260, 30, 950)[0], '16:00');
assert.deepEqual(buatSlotBooking(600, 1260, 30, 1240), []);

// Slot yang sudah lewat tetap digambar, hanya dimatikan. Membuangnya membuat
// grid sore hari terlihat pendek dan pengunjung mengira toko hampir tutup.
const seluruhSumber =
  extractFunctionSource(landing, 'buatSlotBooking') +
  ';' +
  extractFunctionSource(landing, 'seluruhSlotHari');
const seluruhSlotHari = new Function(
  `${seluruhSumber}; return seluruhSlotHari;`
)();

const sore = seluruhSlotHari(600, 1260, 45, 1080);
assert.equal(sore.length, 21, 'seluruh jam hari itu harus tetap tampil');
assert.equal(sore[0].jam, '10:00');
assert.equal(sore[0].lewat, true);
assert.equal(sore.at(-1).jam, '20:00');
assert.equal(sore.at(-1).lewat, false);
assert.equal(
  sore.filter(x => !x.lewat).length,
  buatSlotBooking(600, 1260, 45, 1080).length,
  'jam yang dapat dipilih harus sama persis dengan hitungan server'
);

// Picker: batas di layar harus sama dengan batas di server, kalau tidak orang
// memilih layanan kelima lalu ditolak setelah seluruh formulir terisi.
assert.match(landing, /const MAKS_LAYANAN = 4;/);
assert.match(migrationBooking, /array_length\(v_ids, 1\) > 4/);
assert.match(landing, /p_service_ids: layananPilih,/);
assert.doesNotMatch(landing, /p_service_id:/);
assert.match(landing, /if \(!b \|\| b\.disabled\) return;/);

// Pilihan ganda dirapikan di server, bukan dipercayakan pada layar.
assert.match(migrationBooking, /array_agg\(DISTINCT x\)/);
assert.match(migrationBooking, /Pilih minimal satu layanan/);
// Ringkasan gabungan tetap ditulis supaya panel kasir di POS tidak perlu tahu
// soal banyak layanan untuk dapat menampilkannya.
assert.match(migrationBooking, /service_ids, service_name,/);
assert.match(migrationBooking, /string_agg\(s\.name, ' \+ '/);
// Jam tutup pada definisi yang benar-benar berjalan, bukan pada migrasi lama.
assert.match(
  migrationBooking,
  /EXTRACT\(EPOCH FROM p_jam\) \/ 60 \+ v_durasi/
);
assert.doesNotMatch(migrationBooking, /p_jam \+ make_interval\(/);
assert.match(migrationBooking, /REVOKE EXECUTE ON FUNCTION create_booking/);

// Hero digambar CSS. Kalau suatu saat ada yang menautkan berkas gambar lagi,
// berkasnya sudah tidak ada di repositori dan hero akan kosong tanpa suara.
assert.doesNotMatch(landing, /hero-merek|hero-landing|hero-gambar/);
assert.match(landing, /\.hero-kabut \{/);
assert.match(landing, /src="assets\/logo\.png"/);

// Animasi gulir tidak boleh menunggu data. Kalau amati() hanya dipanggil
// setelah render, satu kegagalan jaringan meninggalkan seluruh halaman tak
// terlihat, bukan sekadar tanpa daftar layanan.
assert.match(landing.replace(/\s+/g, ' '), /amati\(\); muat\(\);/);
assert.match(landing, /<noscript><style>\.muncul/);

// Peta hanya diambil saat bagiannya mendekati layar, dan tidak boleh merampas
// gulir halaman sebelum orangnya memang menyentuhnya.
assert.match(landing, /f\.loading = 'lazy';/);
assert.match(landing, /peta-tirai/);
assert.match(landing, /www\.google\.com\/maps\?q=/);

// Foto kapster: WebP dulu, PNG sebagai cadangan. Tanpa <source> WebP, tiap
// pengunjung mengunduh 3 MB PNG untuk avatar yang tampil 148x185 piksel;
// tanpa <img> PNG, Safari di bawah iOS 14 tidak melihat wajah sama sekali.
const berkasFoto = ['landing.html', 'pos.html', 'rekap.html', 'capster.html'];
for (const nama of berkasFoto) {
  const isi = fs.readFileSync(path.join(root, nama), 'utf8');
  for (const orang of ['cena', 'lukman', 'wanda']) {
    assert.match(isi, new RegExp('assets/' + orang), nama + ' harus merujuk foto ' + orang);
  }
  assert.match(isi, /\.webp/, nama + ' harus menawarkan WebP');
  assert.match(isi, /\.png\?v=/, nama + ' harus menyimpan cadangan PNG');
  assert.match(isi, /type="image\/webp"/, nama + ' harus memakai <source type="image/webp">');

  // Aturannya satu kalimat: foto kapster selalu lewat <picture>. Memeriksa
  // keberadaan ".webp" di berkas saja tidak cukup, sebab satu <source> yang
  // hilang tetap lolos selama saudaranya masih ada, dan justru yang satu itu
  // yang diam-diam mengirim 1 MB ke tiap pengunjung.
  //
  // Diperiksa dengan mengeluarkan seluruh blok <picture> lebih dulu, lalu
  // menuntut tidak ada lagi <img> foto kapster yang tersisa di luar. Cara ini
  // tidak peduli bagaimana URL-nya disusun, dan tiga layar staf memang
  // menyusunnya dari batang nama lewat penggabungan teks.
  const rapat = isi.replace(/\s+/g, ' ');
  const blokPicture = rapat.match(/<picture>.*?<\/picture>/g) || [];
  assert.ok(blokPicture.length > 0, nama + ' harus menyajikan foto lewat <picture>');
  for (const blok of blokPicture) {
    assert.match(blok, /<source [^>]*type="image\/webp"/,
      nama + ' punya <picture> tanpa <source> WebP');
    assert.match(blok, /<img [^>]*\.png/,
      nama + ' punya <picture> tanpa cadangan PNG');
  }

  const diLuar = rapat.replace(/<picture>.*?<\/picture>/g, '');
  const tercecer = diLuar.match(/<img [^>]*(?:assets\/(?:cena|lukman|wanda)|\$\{foto\}|FOTO_KAPSTER)/g) || [];
  assert.deepEqual(tercecer, [],
    nama + ' punya <img> foto kapster di luar <picture>, jadi PNG penuh terkirim tanpa cadangan WebP');
  // Kotak avatar adalah grid; tanpa display contents, <picture> jadi butir
  // grid dan gambarnya meluber ke ukuran asli 761x950.
  assert.match(isi, /picture { display: contents; }/, nama + ' harus menetralkan kotak <picture>');
}

// Markup kapster yang statis hanya bertahan sampai data tiba: isiKapster()
// menimpa seluruh isi #kapsterDaftar. Jadi pembangun JS inilah yang benar-benar
// dilihat pengunjung, dan ia harus diperiksa terpisah dari markupnya.
const sumberGambarKapster = extractFunctionSource(landing, 'gambarKapster');
assert.match(sumberGambarKapster, /<picture>/, 'gambarKapster harus membungkus dengan <picture>');
assert.match(sumberGambarKapster, /<source /, 'gambarKapster harus memakai <source>');
assert.match(sumberGambarKapster, /type="image\/webp"/, 'gambarKapster harus menawarkan WebP');
assert.match(sumberGambarKapster, /\.png\?v=/, 'gambarKapster harus menyimpan cadangan PNG');
assert.match(
  extractFunctionSource(landing, 'isiKapster'),
  /gambarKapster\(/,
  'isiKapster harus menggambar avatar lewat gambarKapster'
);

// kartu.html tidak pernah menampilkan foto kapster, jadi service worker tidak
// boleh menyimpannya di cangkang luring kartu member.
const sw = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
const KERANGKA = sw.slice(sw.indexOf('const KERANGKA'), sw.indexOf(']', sw.indexOf('const KERANGKA')));
assert.doesNotMatch(KERANGKA, /cena|lukman|wanda/);

assert.match(landing, /id="bkKirim" disabled>Menyiapkan/);
assert.match(landing, /function tampilkanGagalMuat/);
assert.doesNotMatch(landing, /pesan\(res\.error\.message/);
assert.match(landing, /assets\/og-landing\.jpg/);
assert.doesNotMatch(landing, /og:image" content="[^"]*og-kartu/);

assert.match(pos, /id="btnOpenBookings"/);
assert.match(pos, /id="bookingModal"/);
assert.match(pos, /sb\.rpc\('bookings_list'/);
assert.match(pos, /sb\.rpc\('decide_booking'/);
assert.match(pos, /Hubungi WhatsApp/);

assert.match(migration, /INTERVAL '30 minutes'/);
// Jam tutup harus dihitung dalam menit sejak tengah malam. Penjumlahan pada
// tipe time berputar: '23:30' + 45 menit menghasilkan '00:15', dan
// '00:15' > '21:00' bernilai salah, sehingga booking tengah malam lolos.
assert.match(
  migrationJamTutup,
  /EXTRACT\(EPOCH FROM p_jam\) \/ 60 \+ v_srv\.duration_minutes/
);
assert.doesNotMatch(
  migrationJamTutup,
  /p_jam \+ make_interval\(mins => v_srv\.duration_minutes\)/
);
assert.match(migration, /length\(COALESCE\(v_catatan, ''\)\) > 300/);
assert.match(migration, /pg_advisory_xact_lock/);
assert.match(migration, /REVOKE EXECUTE ON FUNCTION create_booking/);

console.log('Landing and booking tests: OK');
