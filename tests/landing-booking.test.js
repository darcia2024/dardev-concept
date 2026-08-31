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

for (const [name, html] of [['landing.html', landing], ['pos.html', pos]]) {
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
