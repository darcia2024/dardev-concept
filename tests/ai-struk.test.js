/* Add-on AI, fitur 1: pengeluaran dari foto struk (migrasi 53, ai-struk, lewat OpenRouter).
 *
 * Yang dijaga di sini adalah janji-janji yang, bila dilanggar, tidak akan
 * tampak sebagai galat — hanya sebagai tagihan yang membengkak, kunci API yang
 * bocor, atau pembukuan yang diam-diam salah:
 *
 *   1. Kunci API AI tidak pernah sampai ke peramban.
 *   2. AI hanya MEMBACA. Tidak ada yang tersimpan sebelum owner menekan Simpan.
 *   3. Batas harian diperiksa SEBELUM model AI dihubungi, jadi tidak ditagih.
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
assert.match(fn, /Deno\.env\.get\('OPENROUTER_API_KEY'\)/, 'kunci dibaca dari secret Supabase');
for (const f of ['rekap.html', 'pos.html', 'kartu.html', 'landing.html', 'capster.html', 'masuk.html', 'sb-app.js']) {
  const isi = baca(f);
  assert.doesNotMatch(isi, /sk-or-[A-Za-z0-9_-]{10,}/, `${f} memuat sesuatu yang berbentuk kunci OpenRouter`);
  assert.doesNotMatch(isi, /sk-ant-[A-Za-z0-9_-]{10,}/, `${f} memuat sesuatu yang berbentuk kunci API Anthropic`);
  assert.doesNotMatch(isi, /openrouter\.ai\/api|api\.anthropic\.com/,
    `${f} memanggil layanan AI langsung — itu hanya mungkin dengan kunci di peramban`);
}
assert.match(rekap, /panggilAi\('ai-struk'/, 'pembacaan struk harus lewat Edge Function');

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

/* ── 3 · Batas harian sebelum model AI dihubungi ─────────────────────────
   Bila urutannya terbalik, panggilan yang ditolak tetap sudah ditagih. */
const iBatas = fn.indexOf('>= BATAS_HARIAN');
const iAi    = fn.indexOf("fetch('https://openrouter.ai/api/v1/chat/completions'");
assert.ok(iBatas > 0 && iAi > 0, 'batas harian dan panggilan AI harus ada');
assert.ok(iBatas < iAi, 'batas harian harus diperiksa sebelum model AI dihubungi');
// Penjaga owner juga sebelum AI, dan sebelum badan permintaan dibaca.
assert.ok(fn.indexOf("profil?.role !== 'owner'") < fn.indexOf('await req.json()'), 'owner diperiksa sebelum masukan dibaca');
assert.ok(fn.indexOf("profil?.role !== 'owner'") < iAi);
// Setiap jalan keluar setelah AI dipanggil tercatat — kalau tidak, batasnya bocor.
const sesudah = fn.slice(iAi);
assert.ok((sesudah.match(/await catatPemakaian\(/g) || []).length >= 6,
  'jaringan, galat HTTP, refusal, length, JSON rusak, dan berhasil harus semuanya tercatat');

/* ── 4 · Permintaan ke OpenRouter ────────────────────────────────────────── */
assert.match(fn, /const MODEL = Deno\.env\.get\('MODEL_AI'\) \|\| 'google\/gemini-3\.5-flash-lite';/,
  'model dapat diganti lewat secret MODEL_AI, dengan bawaan yang murah');
assert.match(fn, /response_format: \{\s*type: 'json_schema',\s*json_schema: \{ name: 'struk', strict: true, schema: SKEMA_STRUK \},?\s*\}/,
  'jawaban dibatasi skema lewat structured outputs');
// Tanpa ini OpenRouter boleh merutekan ke penyedia yang mengabaikan skema.
assert.match(fn, /provider: \{ require_parameters: true \}/);
// Parameter reasoning TIDAK dikirim: require_parameters akan menuntutnya
// juga, sehingga mengganti MODEL_AI ke model tanpa reasoning gagal dirutekan.
const badanPermintaan = fn.slice(iAi, fn.indexOf('  } catch (e) {', iAi));
assert.doesNotMatch(badanPermintaan, /reasoning\s*:/, 'parameter reasoning tidak boleh dikirim bersama require_parameters');
// Teks lebih dulu, lalu gambar — rekomendasi OpenRouter.
assert.ok(badanPermintaan.indexOf("type: 'text'") < badanPermintaan.indexOf("type: 'image_url'"),
  'bagian teks harus mendahului gambar');

// Structured outputs menolak batasan angka dan panjang string, dan menuntut
// additionalProperties: false pada setiap objek. anyOf dihindari karena
// dukungan penyedia di belakang OpenRouter tidak merata.
const skema = fn.slice(fn.indexOf('const SKEMA_STRUK'), fn.indexOf('as const;'));
assert.doesNotMatch(skema, /minimum|maximum|minLength|maxLength|multipleOf/, 'batasan yang tidak didukung structured outputs');
assert.doesNotMatch(skema, /anyOf|'null'/, 'skema tidak boleh bergantung pada anyOf/null');
assert.equal((skema.match(/type: 'object'/g) || []).length, (skema.match(/additionalProperties: false/g) || []).length,
  'setiap objek dalam skema harus additionalProperties: false');

/* ── 5 · Galat, penolakan, dan jawaban terpotong ditangani sebelum JSON dibaca */
const iParse = fn.indexOf('JSON.parse(teks');
assert.ok(iParse > 0, 'pembacaan jawaban AI harus ditemukan');
assert.ok(fn.indexOf('if (kodeGalat)') < iParse, 'galat HTTP dan galat di badan diperiksa sebelum JSON dibaca');
assert.match(fn, /!res\.ok \? res\.status : \(data\?\.error/, 'galat di tengah jalan datang sebagai 200 dengan error di badan');
assert.ok(fn.indexOf('message?.refusal') < iParse, 'penolakan diperiksa sebelum JSON dibaca');
assert.ok(fn.indexOf("finish_reason === 'length'") < iParse, 'jawaban terpotong diperiksa sebelum JSON dibaca');
// Saldo habis (402) disebut terang-terangan, bukan sebagai "gagal" umum.
assert.match(fn, /kodeGalat === 402\)[\s\S]{0,200}Saldo layanan AI habis/, 'saldo habis harus disebut dengan jelas');

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

/* ── 9 · Struk dari PDF ──────────────────────────────────────────────────
   PDF dikirim sebagai berkas, bukan gambar (dokumentasi OpenRouter
   multimodal/pdfs), dan tidak boleh "diperkecil" lewat kanvas — itu hanya
   bekerja untuk gambar dan akan gagal diam-diam untuk PDF. */
assert.match(fn, /'image\/webp', 'application\/pdf'\] as const/, 'PDF termasuk jenis yang diterima');
assert.match(fn, /\{ type: 'file', file: \{ filename: 'struk\.pdf', file_data: `data:application\/pdf;base64,\$\{gambar\}` \} \}/,
  'PDF dikirim dengan bentuk content part file');
assert.ok(badanPermintaan.indexOf("type: 'text'") < badanPermintaan.indexOf("type: 'file'"), 'teks mendahului PDF');
// Batas ukuran tetap diperiksa untuk PDF, sebelum AI dihubungi.
assert.ok(fn.indexOf('gambar.length > UKURAN_MAKS_BASE64') < iAi);
const foto = rekap.slice(rekap.indexOf("getElementById('inpFotoStruk').addEventListener"),
                         rekap.indexOf("getElementById('btnSimpanPengeluaran').addEventListener"));
assert.match(foto, /adalahPdf\(berkas\) \? await bacaPdf\(berkas\) : await perkecilGambar\(berkas\)/,
  'PDF dibaca utuh, foto diperkecil');
const pdf = rekap.slice(rekap.indexOf('function bacaPdf'), rekap.indexOf('function adalahPdf'));
assert.match(pdf, /berkas\.size > PDF_MAKS/, 'PDF besar ditolak sebelum diunggah');
assert.doesNotMatch(pdf, /perkecilGambar|canvas/i, 'PDF tidak boleh lewat kanvas');

console.log('ai-struk: semua pemeriksaan lolos');
