/* Panel Pengeluaran & Struk Belanja dipakai owner dari HP. Dua keluhan nyata
 * yang dijaga di sini:
 *
 *   1. "Foto Struk" langsung membuka kamera, padahal struknya sering sudah
 *      difoto lebih dulu atau dikirim pemasok lewat WhatsApp.
 *   2. Di HP, tabel barang selebar 700px menyembunyikan harga dan subtotal —
 *      justru angka yang harus diperiksa sebelum menyimpan — dan label
 *      menempel ke kolomnya.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const rekap = fs.readFileSync(path.join(__dirname, '..', 'rekap.html'), 'utf8');

/* ── 1 · Pilihan kamera, galeri, atau berkas ─────────────────────────────── */
const inp = rekap.match(/<input type="file" id="inpFotoStruk"[^>]*>/);
assert.ok(inp, 'masukan foto struk harus ada');
assert.doesNotMatch(inp[0], /\bcapture\b/,
  'capture memaksa HP langsung membuka kamera; owner harus bisa memilih galeri atau berkas');
assert.match(inp[0], /accept="image\/\*,application\/pdf,\.pdf"/, 'foto dan PDF (invoice belanja online) diterima');

/* ── 2 · Baris barang menjadi kartu di layar sempit ──────────────────────── */
assert.match(rekap, /<table class="tx-table peng-items">/, 'tabel barang harus bisa ditata khusus untuk ponsel');
const ponsel = rekap.slice(rekap.indexOf('table.peng-items { min-width: 0; }') - 40,
                           rekap.indexOf('table.peng-items tr:hover td'));
assert.ok(ponsel.length > 40, 'aturan ponsel untuk baris barang harus ada');
assert.match(ponsel, /table\.peng-items thead \{ display: none; \}/);
assert.match(ponsel, /content: attr\(data-label\)/, 'tiap kolom membawa labelnya sendiri saat judul tabel disembunyikan');

const baris = rekap.slice(rekap.indexOf('function barisPengeluaran'), rekap.indexOf('function bacaBarisPengeluaran'));
for (const f of ['nama', 'qty', 'harga', 'sub', 'produk']) {
  assert.match(baris, new RegExp(`<td[^>]*data-label="[^"]+"[^>]*><(input|select)[^>]*data-f="${f}"`),
    `kolom ${f} harus berlabel di tampilan kartu`);
}

/* ── 3 · Label tidak menempel, header tidak menutupi ─────────────────────── */
assert.match(rekap, /\.kelola-form-dua > div \{ display: flex; flex-direction: column; gap: 6px;/,
  'label dan kolom di formulir dua-kolom butuh jarak sendiri');
assert.match(rekap, /\.kelola-form input\[type="date"\] \{\s*-webkit-appearance: none;/,
  'kolom tanggal di Safari iOS melewati tepi kotak tanpa ini');
assert.match(rekap, /@media \(max-width: 720px\) \{[\s\S]{0,700}header\.rekap-header \{ position: static; \}/,
  'di ponsel header tidak lengket, supaya tidak menutupi bilah kategori yang lengket di top:0');

console.log('pengeluaran-ponsel: semua pemeriksaan lolos');
