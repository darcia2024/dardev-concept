/* Add-on AI, fitur 3 bagian stok (migrasi 57, ai-stok).
 *
 * Yang dijaga di sini adalah janji yang, bila dilanggar, tidak tampak sebagai
 * galat — hanya sebagai angka stok yang diam-diam salah:
 *
 *   1. Stok dihitung dari mutasi; tidak ada angka stok yang ditimpa langsung.
 *   2. Penjualan dan belanja menggeser stok lewat TRIGGER, bukan dengan
 *      menulis ulang create_transaction atau owner_simpan_pengeluaran.
 *   3. Pembatalan hanya mengembalikan yang dulu benar-benar tercatat.
 *   4. Selisih hitung fisik dihitung di server, bukan di peramban.
 *   5. Id produk tidak pernah dikarang model; nama dipetakan di server.
 *   6. AI hanya mengusulkan; tidak ada yang tercatat sebelum owner menyimpan.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir, root } = require('./_migrasi');

const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const m57   = baca('supabase_migration_57_stok.sql');
const fn    = baca('supabase/functions/ai-stok/index.ts');
const rekap = baca('rekap.html');
const js    = rekap.slice(rekap.indexOf('STOK PRODUK (Add-on AI, fitur 3)'), rekap.indexOf('async function loadHpp()'));
assert.ok(js.length > 1000, 'kode layar Stok Produk harus ditemukan');
const sqlTanpaKomentar = m57.replace(/--.*$/gm, '');

/* ── 1 · Stok = jumlah mutasi ────────────────────────────────────────────── */
assert.doesNotMatch(sqlTanpaKomentar, /ADD COLUMN[^;]*\bstok\b\s+(NUMERIC|INT)/i, 'tidak boleh ada kolom stok yang ditimpa');
assert.match(definisiTerakhir('owner_stok_list').badan, /sum\(m\.qty_delta\)/, 'stok dihitung dari jumlah mutasi');
assert.match(m57, /CREATE POLICY owner_baca ON stok_mutasi FOR SELECT TO authenticated USING \(is_owner\(\)\);/);
assert.doesNotMatch(sqlTanpaKomentar, /ON stok_mutasi\s+FOR (ALL|INSERT|UPDATE|DELETE)/, 'mutasi tidak boleh dapat disunting dari peramban');

/* ── 2 · Lewat trigger, tidak menulis ulang fungsi yang sudah ada ────────── */
for (const f of ['create_transaction', 'owner_simpan_pengeluaran', 'delete_transaction', 'owner_hapus_pengeluaran']) {
  assert.doesNotMatch(m57, new RegExp('CREATE OR REPLACE FUNCTION ' + f + '\\s*\\('), `migrasi 57 tidak boleh menulis ulang ${f}`);
}
assert.match(m57, /AFTER INSERT OR DELETE ON transaction_items/);
assert.match(m57, /AFTER INSERT OR DELETE ON pengeluaran_item/);
const jual = m57.slice(m57.indexOf('FUNCTION stok_dari_penjualan'), m57.indexOf('DROP TRIGGER IF EXISTS stok_dari_penjualan'));
assert.match(jual, /NEW\.item_type = 'produk' AND NEW\.product_id IS NOT NULL/, 'hanya produk yang mengurangi stok, bukan layanan');
assert.match(jual, /'jual', -NEW\.qty/);

/* ── 3 · Pembatalan hanya untuk yang dulu tercatat ───────────────────────
   Tanpa syarat ini, menghapus transaksi dari sebelum migrasi 57 menambah
   stok dari udara. */
assert.match(jual, /EXISTS \(SELECT 1 FROM stok_mutasi m WHERE m\.ref_id = OLD\.id AND m\.jenis = 'jual'\)/);
const belanja = m57.slice(m57.indexOf('FUNCTION stok_dari_belanja'), m57.indexOf('DROP TRIGGER IF EXISTS stok_dari_belanja'));
assert.match(belanja, /EXISTS \(SELECT 1 FROM stok_mutasi m WHERE m\.ref_id = OLD\.id AND m\.jenis = 'belanja'\)/);
// ref_id bukan foreign key: baris asalnya memang dihapus saat dibatalkan.
assert.doesNotMatch(m57, /ref_id\s+UUID\s+REFERENCES/, 'ref_id tidak boleh foreign key');

/* ── 4 · Hitung fisik dihitung di server, dengan kunci ──────────────────── */
const catat = definisiTerakhir('owner_stok_catat').badan;
assert.match(catat, /IF NOT is_owner\(\) THEN/);
assert.match(catat, /FOR UPDATE;\s*\n\s*SELECT COALESCE\(sum\(qty_delta\), 0\) INTO v_stok/, 'stok dibaca sesudah produknya dikunci');
assert.match(catat, /v_qty - v_stok, v_qty/, 'selisih = hasil hitung - stok saat itu');
assert.match(catat, /v_jenis NOT IN \('hitung', 'masuk', 'keluar'\)/, 'owner tidak boleh mencatat jual/belanja sendiri');
for (const f of ['owner_stok_list', 'owner_stok_catat', 'owner_stok_riwayat', 'owner_set_stok_minimum']) {
  assert.match(m57, new RegExp(`REVOKE EXECUTE ON FUNCTION ${f}\\([^)]*\\) FROM PUBLIC, anon;`), `${f} harus dicabut dari anon`);
  assert.match(definisiTerakhir(f).badan, /is_owner\(\)/, `${f} hanya untuk owner`);
}
// Peramban tidak mengirim selisih; ia mengirim hasil hitung. (qty_delta
// boleh DIBACA untuk riwayat, tetapi tidak boleh ada di yang disimpan.)
const simpanStok = js.slice(js.indexOf("getElementById('btnSimpanStok').addEventListener"),
                            js.indexOf('/* ── Masukan untuk AI'));
assert.ok(simpanStok.length > 0);
assert.doesNotMatch(simpanStok, /qty_delta|selisih/, 'peramban tidak boleh menghitung atau mengirim selisih');
assert.match(simpanStok, /rpc\('owner_stok_catat', \{ p_items: baris, p_sumber: stokSumber \}\)/);

/* ── 5 · Id produk dari server ──────────────────────────────────────────── */
assert.match(fn, /from\('products_hpp'\)\s*\n?\s*\.select\('id, name'\)/, 'katalog dibaca di server');
assert.match(fn, /const cocok = peta\.get\(normal\(String\(b\?\.produk/, 'nama dari model dipetakan ke id oleh kode');
assert.match(fn, /product_id: cocok \? cocok\.id : ''/, 'nama yang tidak cocok tidak mendapat id');
const skema = fn.slice(fn.indexOf('const SKEMA_STOK'), fn.indexOf('as const;', fn.indexOf('const SKEMA_STOK')));
assert.doesNotMatch(skema, /product_id|\bid\b:/, 'model tidak boleh diminta menulis id produk');
assert.doesNotMatch(skema, /minimum|maximum|minLength|maxLength|multipleOf|anyOf|'null'/);
assert.equal((skema.match(/type: 'object'/g) || []).length, (skema.match(/additionalProperties: false/g) || []).length);

/* ── 6 · AI hanya mengusulkan ───────────────────────────────────────────── */
assert.doesNotMatch(fn, /from\('stok_mutasi'\)|rpc\(\s*'owner_stok_catat'/, 'ai-stok tidak boleh mencatat stok');
assert.match(fn, /Deno\.env\.get\('OPENROUTER_API_KEY'\)/);
assert.match(js, /sb\.functions\.invoke\('ai-stok'/);
const baca2 = js.slice(js.indexOf("getElementById('btnStokBaca').addEventListener"));
assert.match(baca2, /bukaEditorStok\(hasil\.baris, 'ai'/, 'hasil AI membuka penyunting');
assert.doesNotMatch(baca2, /owner_stok_catat/, 'membaca tidak boleh langsung menyimpan');
// Baris tanpa produk ditolak sebelum dikirim.
assert.match(js, /belum dipilih produknya/);

/* ── 7 · Batas harian dan penanganan galat seperti ai-struk ─────────────── */
const iBatas = fn.indexOf('>= BATAS_HARIAN');
const iAi    = fn.indexOf("fetch('https://openrouter.ai/api/v1/chat/completions'");
assert.ok(iBatas > 0 && iAi > 0 && iBatas < iAi, 'batas harian sebelum model AI dihubungi');
assert.match(fn, /\.eq\('fitur', 'stok'\)/);
assert.ok(fn.indexOf("profil?.role !== 'owner'") < fn.indexOf('await req.json()'));
assert.ok((fn.slice(iAi).match(/await catatPemakaian\(/g) || []).length >= 6);
assert.match(fn, /provider: \{ require_parameters: true \}/);
assert.doesNotMatch(fn.slice(iAi, fn.indexOf('  } catch (e) {', iAi)), /reasoning\s*:/);
assert.match(fn, /input_audio: \{ data: audio, format: 'wav' \}/, 'OpenRouter tidak menerima webm');
assert.match(fn, /kodeGalat === 402\)[\s\S]{0,120}Saldo layanan AI habis/);
const iParse = fn.indexOf('JSON.parse(isiJawaban');
assert.ok(fn.indexOf('if (kodeGalat)') < iParse && fn.indexOf('message?.refusal') < iParse && fn.indexOf("finish_reason === 'length'") < iParse);

/* ── 8 · Layar ───────────────────────────────────────────────────────────── */
// Escape di setiap teks yang masuk innerHTML.
for (const n of ['gambarStok', 'muatRiwayatStok', 'barisStok', 'opsiProdukStok']) {
  const a = js.indexOf('function ' + n + '(');
  assert.ok(a > 0, n + ' harus ada');
  const isi = js.slice(a, js.indexOf('\n    }\n', a));
  assert.doesNotMatch(isi, /\+ (p|m|b)\.(name|catatan|disebut) \+/, `${n}: teks disambung ke HTML tanpa escapeHtml`);
}
// Perekam dipakai bersama, bukan disalin.
assert.equal((rekap.match(/function buatPerekam\(/g) || []).length, 1);
assert.match(js, /buatPerekam\(\{ tombol: 'btnRekamStok'/);
assert.doesNotMatch(rekap.match(/<input type="file" id="inpFotoStok"[^>]*>/)[0], /\bcapture\b/, 'foto catatan boleh dari galeri');
// Stok ikut segar saat sumber mutasinya berubah.
assert.match(rekap, /await muatPengeluaran\(\);\s*\n\s*await muatStok\(\);/, 'belanja struk mengubah stok');
const tabKeuangan = rekap.slice(rekap.indexOf('<section class="tab-pane" data-pane="keuangan"'), rekap.indexOf('<section class="tab-pane" data-pane="karyawan"'));
assert.match(tabKeuangan, /id="stokBody"/, 'panel Stok Produk di tab Keuangan');

console.log('ai-stok: semua pemeriksaan lolos');
