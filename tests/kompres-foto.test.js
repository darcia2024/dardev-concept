/* Foto tidak boleh menghabiskan ruang: aset situs dan unggahan ke Storage. */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const kb = (f) => fs.statSync(path.join(root, f)).size / 1024;

/* Batas per berkas aset. Foto kapster tampil paling lebar 148 px CSS. */
const BATAS = {
  'assets/cena.webp': 25, 'assets/lukman.webp': 25, 'assets/wanda.webp': 25,
  'assets/cena.png': 120, 'assets/lukman.png': 120, 'assets/wanda.png': 120,
  'assets/login-panel.webp': 90, 'assets/login-panel.jpg': 150,
  'assets/logo.png': 20, 'assets/logo-putih.png': 20,
  'assets/og-kartu.jpg': 60, 'assets/og-landing.jpg': 60
};
for (const [f, maks] of Object.entries(BATAS)) {
  assert.ok(kb(f) <= maks, `${f} ${kb(f).toFixed(0)} KB melebihi batas ${maks} KB`);
}
const total = fs.readdirSync(path.join(root, 'assets'))
  .reduce((n, f) => n + kb('assets/' + f), 0);
assert.ok(total <= 700, `folder assets ${total.toFixed(0)} KB, batasnya 700 KB`);

/* Gambar pratinjau kartu pindah ke JPEG; tidak boleh ada rujukan ke PNG lama. */
assert.ok(!fs.existsSync(path.join(root, 'assets/og-kartu.png')));
assert.doesNotMatch(baca('kartu.html'), /og-kartu\.png/);
assert.match(baca('kartu.html'), /og:image:type" content="image\/jpeg"/);

/* Selfie absen dan lampiran izin dikecilkan sebelum diunggah ke Storage. */
const kapster = baca('capster.html');
assert.match(kapster, /async function kecilkanFoto\(file, sisi, mutu\)/);
assert.match(kapster, /async function unggahSelfie\(asli, aksi\) \{[\s\S]{0,200}await kecilkanFoto\(asli, 1080, 0\.8\)/);
assert.match(kapster, /async function unggahLampiran\(asli\) \{[\s\S]{0,250}await kecilkanFoto\(asli, 1600, 0\.85\)/);
// Absen tidak boleh gagal hanya karena fotonya tidak bisa dikecilkan.
assert.match(kapster, /catch \(e\) \{\s*return file;/);
assert.match(kapster, /hasil && hasil\.size < file\.size \? hasil : file/);

/* Foto kapster unggahan owner juga dikecilkan (migrasi 60). */
assert.match(baca('rekap.html'), /Math\.min\(1, 960 \/ gambar\.naturalWidth, 1200 \/ gambar\.naturalHeight\)/);

console.log('kompres-foto: semua pemeriksaan lolos');
