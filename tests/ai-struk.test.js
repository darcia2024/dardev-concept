/* Add-on AI, fitur 1: pengeluaran dari foto struk (migrasi 53, ai-struk).
 *
 * Yang dijaga di sini adalah janji-janji yang, bila dilanggar, tidak akan
 * tampak sebagai galat — hanya sebagai tagihan yang membengkak, kunci API yang
 * bocor, atau pembukuan yang diam-diam salah:
 *
 *   1. Kunci API AI tidak pernah sampai ke peramban.
 *   2. AI hanya MEMBACA. Tidak ada yang tersimpan sebelum owner menekan Simpan.
 *   3. Batas harian diperiksa SEBELUM Claude dihubungi, jadi tidak ditagih.
 *   4. Harga modal (HPP) hanya berubah untuk baris yang owner tautkan sendiri.
 *   5. Penolakan dan jawaban terpotong ditangani sebelum JSON-nya dibaca.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir, root } = require('./_migrasi');

const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const fn    = baca('supabase/functions/ai-struk/index.ts');
const rekap = baca('rekap.html');

/* ── 1 · Kunci API hanya di server ───────────────────────────────────────── */
assert.match(fn, /apiKey: Deno\.env\.get\('ANTHROPIC_API_KEY'\)/, 'kunci dibaca dari secret Supabase');
for (const f of ['rekap.html', 'pos.html', 'kartu.html', 'landing.html', 'capster.html', 'masuk.html', 'sb-app.js']) {
  const isi = baca(f);
  assert.doesNotMatch(isi, /sk-ant-[A-Za-z0-9_-]{10,}/, `${f} memuat sesuatu yang berbentuk kunci API Anthropic`);
  assert.doesNotMatch(isi, /api\.anthropic\.com/, `${f} memanggil API Anthropic langsung — itu hanya mungkin dengan kunci di peramban`);
}
assert.match(rekap, /sb\.functions\.invoke\('ai-struk'/, 'pembacaan struk harus lewat Edge Function');

/* ── 2 · AI hanya membaca ────────────────────────────────────────────────
   Edge Function tidak boleh menulis ke pembukuan. Satu-satunya tulisannya
   adalah catatan pemakaian. */
assert.doesNotMatch(fn, /from\('pengeluaran(_item)?'\)/, 'ai-struk tidak boleh menyentuh tabel pengeluaran');
// Dicari pemanggilannya, bukan penyebutannya: komentar di kepala fungsi itu
// justru menyebut owner_simpan_pengeluaran untuk menerangkan bahwa ia TIDAK
// menyimpan apa pun.
assert.doesNotMatch(fn, /rpc\(\s*'owner_simpan_pengeluaran'|from\(\s*'products_hpp'\)/,
  'ai-struk tidak boleh menyimpan atau mengubah HPP');
assert.match(rekap, /rpc\('owner_simpan_pengeluaran'/, 'penyimpanan lewat RPC owner');
// Hasil AI hanya mengisi formulir; penyimpanan hanya di tombol Simpan.
const penanganFoto = rekap.slice(rekap.indexOf("getElementById('inpFotoStruk').addEventListener"),
                                 rekap.indexOf("getElementById('btnSimpanPengeluaran').addEventListener"));
assert.ok(penanganFoto.length > 0);
assert.match(penanganFoto, /bukaFormPengeluaran\(hasil, 'struk_ai'\)/, 'hasil bacaan mengisi formulir untuk diperiksa');
assert.doesNotMatch(penanganFoto, /owner_simpan_pengeluaran/, 'membaca struk tidak boleh langsung menyimpan');

/* ── 3 · Batas harian sebelum Claude dihubungi ───────────────────────────
   Bila urutannya terbalik, panggilan yang ditolak tetap sudah ditagih. */
const iBatas  = fn.indexOf('>= BATAS_HARIAN');
const iClaude = fn.indexOf('claude.beta.messages.create(');
assert.ok(iBatas > 0 && iClaude > 0, 'batas harian dan panggilan Claude harus ada');
assert.ok(iBatas < iClaude, 'batas harian harus diperiksa sebelum Claude dihubungi');
// Penjaga owner juga sebelum Claude, dan sebelum badan permintaan dibaca.
assert.ok(fn.indexOf("profil?.role !== 'owner'") < fn.indexOf('await req.json()'), 'owner diperiksa sebelum masukan dibaca');
assert.ok(fn.indexOf("profil?.role !== 'owner'") < iClaude);
// Setiap jalan keluar setelah Claude dipanggil tercatat — kalau tidak, batasnya bocor.
const sesudah = fn.slice(iClaude);
assert.ok((sesudah.match(/await catatPemakaian\(/g) || []).length >= 4,
  'berhasil, refusal, max_tokens, dan galat harus semuanya tercatat');

/* ── 4 · Permintaan ke Claude ────────────────────────────────────────────── */
assert.match(fn, /const MODEL = 'claude-opus-5-5';/);
assert.match(fn, /effort: 'medium'/, 'effort ditulis eksplisit — bawaan model ini medium, dan pilihan itu harus terlihat');
assert.match(fn, /format: \{ type: 'json_schema', schema: SKEMA_STRUK \}/, 'jawaban dibatasi skema lewat structured outputs');
assert.match(fn, /betas: \['server-side-fallback-2026-07-01'\]/);
assert.match(fn, /fallbacks: 'default'/);
assert.doesNotMatch(fn, /budget_tokens|type: 'disabled'|temperature/,
  'parameter yang ditolak model ini tidak boleh dikirim');

// Structured outputs menolak batasan angka dan panjang string, dan menuntut
// additionalProperties: false pada setiap objek.
const skema = fn.slice(fn.indexOf('const SKEMA_STRUK'), fn.indexOf('as const;'));
assert.doesNotMatch(skema, /minimum|maximum|minLength|maxLength|multipleOf/, 'batasan yang tidak didukung structured outputs');
assert.equal((skema.match(/type: 'object'/g) || []).length, (skema.match(/additionalProperties: false/g) || []).length,
  'setiap objek dalam skema harus additionalProperties: false');

/* ── 5 · Penolakan dan jawaban terpotong ditangani sebelum JSON dibaca ──── */
// Pembacaan JAWABAN Claude, bukan JSON.parse pertama di berkas — pemilah
// SUPABASE_SECRET_KEYS di bagian atas juga memakai JSON.parse.
const iParse = fn.indexOf('JSON.parse(teks');
assert.ok(iParse > 0, 'pembacaan jawaban Claude harus ditemukan');
assert.ok(fn.indexOf("stop_reason === 'refusal'") < iParse, 'refusal diperiksa sebelum JSON dibaca');
assert.ok(fn.indexOf("stop_reason === 'max_tokens'") < iParse, 'jawaban terpotong diperiksa sebelum JSON dibaca');
// Galat API ditangkap dari yang paling khusus, tanpa mencocokkan teks pesan.
assert.match(fn, /e instanceof Anthropic\.AuthenticationError/);
assert.match(fn, /e instanceof Anthropic\.RateLimitError/);

/* ── 6 · Basis data ──────────────────────────────────────────────────────── */
const simpan = definisiTerakhir('owner_simpan_pengeluaran').badan;
assert.match(simpan, /IF NOT is_owner\(\) THEN/, 'hanya owner yang mencatat pengeluaran');
assert.match(simpan, /p_tanggal > jakarta_today\(\)/, 'tanggal masa depan ditolak');
// HPP hanya untuk baris yang ditautkan, dan harga nol tidak menimpa.
assert.match(simpan, /IF v_produk IS NOT NULL AND v_harga > 0 THEN\s*\n\s*UPDATE products_hpp SET buy_price = v_harga/,
  'harga modal hanya berubah untuk baris yang ditautkan owner, dan tidak oleh harga nol');
assert.equal((simpan.match(/UPDATE products_hpp/g) || []).length, 1, 'tidak ada jalur lain yang mengubah harga modal');

const m53 = baca('supabase_migration_53_pengeluaran_struk.sql');
// ai_pemakaian: owner hanya membaca. Bila authenticated boleh menulis,
// siapa pun yang login dapat menghapus catatannya dan membuka lagi batas harian.
assert.match(m53, /CREATE POLICY owner_baca ON ai_pemakaian FOR SELECT TO authenticated USING \(is_owner\(\)\);/);
assert.doesNotMatch(m53, /ON ai_pemakaian\s+FOR (ALL|INSERT|UPDATE|DELETE)/, 'ai_pemakaian tidak boleh dapat ditulis dari peramban');
for (const f of ['owner_simpan_pengeluaran', 'owner_pengeluaran_list', 'owner_hapus_pengeluaran']) {
  assert.match(m53, new RegExp(`REVOKE EXECUTE ON FUNCTION ${f}\\([^)]*\\) FROM PUBLIC, anon;`), `${f} harus dicabut dari anon`);
}

/* ── 7 · Layar ───────────────────────────────────────────────────────────── */
assert.match(rekap, /const SISI = 1568;/, 'foto diperkecil sebelum dikirim — tagihan AI dihitung dari ukuran gambar');
assert.match(rekap, /await loadHpp\(\);\s*\n\s*await muatPengeluaran\(\);/, 'daftar pengeluaran ikut dimuat dan ikut berganti periode');
assert.match(rekap, /gambarBerhalaman\('pengeluaran'/, 'daftar pengeluaran memakai pager yang sama');

/* ── 8 · Kunci layanan jenis baru diutamakan ─────────────────────────────
   Dashboard proyek ini menandai SUPABASE_SERVICE_ROLE_KEY DEPRECATED. Masih
   disuntikkan hari ini, tetapi fungsi yang bergantung padanya akan berhenti
   begitu kunci lama dimatikan, tanpa ada yang mengubah kodenya. */
assert.ok(fn.includes("Deno.env.get('KUNCI_LAYANAN')"), 'kunci layanan dapat dipasang owner sendiri');
const iLama = fn.indexOf("Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')");
assert.ok(fn.indexOf("Deno.env.get('SUPABASE_SECRET_KEYS')") > 0, 'SUPABASE_SECRET_KEYS harus dibaca');
assert.ok(fn.indexOf('kunciRahasiaBaru()', fn.indexOf('const KUNCI_SRV')) < iLama,
  'kunci jenis baru harus dicoba sebelum SUPABASE_SERVICE_ROLE_KEY yang deprecated');
assert.ok(fn.includes("Deno.env.get('SUPABASE_URL') ?? 'https://grzjfnqljjzjkvmgtohe.supabase.co'"), 'URL proyek punya cadangan');
assert.doesNotMatch(fn, /Deno\.env\.get\('SUPABASE_[A-Z_]+'\)!/, 'secret bawaan tidak boleh dianggap pasti ada');
assert.ok(fn.indexOf('if (!KUNCI_SRV)') > 0 && fn.indexOf('if (!KUNCI_SRV)') < fn.indexOf('sbSrv.auth.getUser'),
  'tanpa kunci layanan, berhenti dengan pesan yang jelas sebelum apa pun');

console.log('ai-struk: semua pemeriksaan lolos');
