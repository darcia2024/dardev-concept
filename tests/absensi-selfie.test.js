const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const capster = fs.readFileSync(path.join(root, 'capster.html'), 'utf8');

// Nama berkas selfie absensi harus berbeda tiap percobaan.
//
// Sebelumnya ia sepenuhnya ditentukan oleh tanggal dan aksi. Satu percobaan
// yang gagal SESUDAH fotonya terunggah — GPS meleset sesaat, sinyal putus di
// tengah jalan — meninggalkan berkas yang menghalangi seluruh percobaan
// berikutnya hari itu dengan galat "The resource already exists", dan
// capsternya terkunci seharian tanpa cara memperbaikinya sendiri.
const sumber = capster.slice(
  capster.indexOf('async function unggahSelfie'),
  capster.indexOf('$(\'btnAbsen\').addEventListener')
);
assert.ok(sumber.length > 0, 'unggahSelfie harus tersedia');
assert.match(sumber, /Math\.random\(\)/, 'nama berkas harus mengandung bagian acak');

// upsert tetap false: foto absensi yang sudah tercatat tidak boleh ditimpa.
// Yang diperbaiki adalah tabrakan namanya, bukan penjagaannya.
assert.match(sumber, /upsert: false/);

// Dua panggilan berturut-turut untuk aksi dan tanggal yang sama wajib
// menghasilkan nama berbeda.
const buatJalur = new Function('meCapster', 'sbJakartaToday', 'file', 'aksi',
  sumber.slice(sumber.indexOf('{') + 1, sumber.lastIndexOf('const res')) +
  '; return path;');
const arg = [{ id: 'abc' }, () => '2026-09-01', { type: 'image/jpeg' }, 'masuk'];
const jalur = new Set();
for (let i = 0; i < 200; i += 1) jalur.add(buatJalur(...arg));
assert.ok(jalur.size > 190,
  'nama berkas harus praktis selalu berbeda, dapat ' + jalur.size + ' dari 200');

// Bentuknya tetap: folder per capster, lalu tanggal dan aksinya terbaca.
const contoh = [...jalur][0];
assert.match(contoh, /^abc\/2026-09-01-/, 'jalur: ' + contoh);
assert.match(contoh, /\.jpg$/);

console.log('Absensi selfie tests: OK');
