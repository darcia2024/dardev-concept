/* Add-on AI, fitur 5 "Internal Helper": owner bertanya soal data toko
 * (migrasi 58, ai-asisten).
 *
 * Yang dijaga di sini:
 *   1. Model tidak pernah menulis query; ia hanya membaca ringkasan tetap.
 *   2. Ringkasan hanya dapat dipanggil server, dan server memastikan owner.
 *   3. Ringkasan tidak memuat data pribadi pelanggan.
 *   4. Angka ringkasan mengikuti aturan laporan: tanggal operasional WIB,
 *      omzet sesudah diskon, kapster per baris layanan.
 *   5. Jawaban AI tidak pernah dirender sebagai HTML, dan percakapan tidak
 *      disimpan.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir, root } = require('./_migrasi');

const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const fn    = baca('supabase/functions/ai-asisten/index.ts');
const m58   = baca('supabase_migration_58_ringkasan_asisten.sql');
const rekap = baca('rekap.html');
// Dimulai dari /* pembuka komentar kepalanya, supaya komentar itu dapat
// dibuang utuh saat yang diperiksa hanya kode.
const js    = rekap.slice(rekap.lastIndexOf('/*', rekap.indexOf('TANYA DATA TOKO (Add-on AI, fitur 5')),
                          rekap.indexOf('async function loadHpp()'));
assert.ok(js.length > 500, 'kode layar Tanya Data Toko harus ditemukan');
const ringkasan = definisiTerakhir('ringkasan_asisten').badan;

/* ── 1 · Model tidak menulis query ───────────────────────────────────────── */
assert.match(fn, /sbSrv\.rpc\('ringkasan_asisten', \{ p_hari_ini: hariIni \}\)/, 'data dari satu ringkasan tetap');
assert.doesNotMatch(fn, /\.from\('(transactions|transaction_items|members|pengeluaran|attendances|bookings|capsters)'\)/,
  'ai-asisten tidak boleh membaca tabel toko langsung');
assert.doesNotMatch(fn, /tools\s*:|tool_choice|\.rpc\(\s*(hasil|data|pilihan)/, 'model tidak boleh diberi alat untuk memanggil basis data');
assert.doesNotMatch(ringkasan, /EXECUTE\s/, 'ringkasan tidak boleh menjalankan SQL dinamis');
assert.match(fn, /JANGAN mengarang, memperkirakan, atau menebak angka/, 'instruksi harus melarang angka karangan');

/* ── 2 · Hanya server, hanya owner ───────────────────────────────────────── */
assert.match(m58, /REVOKE EXECUTE ON FUNCTION ringkasan_asisten\(DATE\) FROM PUBLIC, anon, authenticated;/);
assert.match(m58, /GRANT  EXECUTE ON FUNCTION ringkasan_asisten\(DATE\) TO service_role;/);
assert.doesNotMatch(m58, /GRANT\s+EXECUTE ON FUNCTION ringkasan_asisten\(DATE\) TO (authenticated|anon|PUBLIC)/);
assert.doesNotMatch(ringkasan, /SECURITY DEFINER/, 'tidak perlu dan tidak boleh SECURITY DEFINER');
const iOwner = fn.indexOf("profil?.role !== 'owner'");
assert.ok(iOwner > 0 && iOwner < fn.indexOf("rpc('ringkasan_asisten'"), 'owner diperiksa sebelum data dibaca');
assert.ok(iOwner < fn.indexOf('await req.json()'));
assert.doesNotMatch(rekap, /rpc\('ringkasan_asisten'/, 'peramban tidak boleh memanggil ringkasan');

/* ── 3 · Tanpa data pribadi pelanggan ────────────────────────────────────── */
for (const kolom of ['phone_wa', 'member_phone', 'member_name', 'telepon', 'b.nama', 'm.name']) {
  assert.ok(!ringkasan.includes(kolom), `ringkasan tidak boleh memuat ${kolom}`);
}

/* ── 4 · Aturan angka ────────────────────────────────────────────────────── */
assert.match(ringkasan, /business_date BETWEEN v_awal AND v_akhir/, 'bulan dihitung dari tanggal operasional');
assert.match(ringkasan, /LEAST\(\(v_awal \+ INTERVAL '1 month - 1 day'\)::DATE, p_hari_ini\)/, 'bulan berjalan berhenti di hari ini');
assert.match(ringkasan, /'omzet', \(SELECT COALESCE\(sum\(t\.final_amount\), 0\)/, 'omzet bulanan = yang dibayar, sesudah diskon');
assert.match(ringkasan, /count\(\*\) AS transaksi, sum\(t\.final_amount\) AS omzet/, 'omzet harian = yang dibayar, sesudah diskon');
assert.doesNotMatch(ringkasan, /t\.subtotal/, 'subtotal adalah harga sebelum diskon, bukan omzet');
assert.match(ringkasan, /COALESCE\(i\.capster_name, t\.capster_name/, 'kapster per baris layanan');
assert.match(ringkasan, /created_at AT TIME ZONE 'Asia\/Jakarta'\)::DATE/, 'member baru per tanggal WIB');
assert.match(ringkasan, /l\.status = 'disetujui'/, 'hanya izin yang disetujui');

/* ── 5 · Pola keamanan seperti fitur AI lain ─────────────────────────────── */
const iBatas = fn.indexOf('>= BATAS_HARIAN');
const iAi    = fn.indexOf("fetch('https://openrouter.ai/api/v1/chat/completions'");
assert.ok(iBatas > 0 && iBatas < iAi, 'batas harian sebelum model AI dihubungi');
assert.match(fn, /\.eq\('fitur', 'asisten'\)/);
assert.ok((fn.slice(iAi).match(/await catatPemakaian\(/g) || []).length >= 6);
assert.doesNotMatch(fn, /keterangan:[^\n]*(content|pertanyaan|pesan\[)/, 'isi percakapan tidak boleh masuk ai_pemakaian');
assert.match(fn, /provider: \{ require_parameters: true \}/);
assert.doesNotMatch(fn.slice(iAi, fn.indexOf('  } catch (e) {', iAi)), /reasoning\s*:/);
assert.match(fn, /kodeGalat === 402\)[\s\S]{0,120}Saldo layanan AI habis/);
const iParse = fn.indexOf('JSON.parse(isiJawaban');
assert.ok(fn.indexOf('if (kodeGalat)') < iParse && fn.indexOf('message?.refusal') < iParse && fn.indexOf("finish_reason === 'length'") < iParse);
assert.match(fn, /\.slice\(-MAKS_PESAN\)/, 'riwayat dibatasi');

/* ── 6 · Layar ───────────────────────────────────────────────────────────── */
assert.match(js, /el\.textContent = teks;/, 'jawaban dirender lewat textContent');
const gel = js.slice(js.indexOf('function gelembungAsisten'), js.indexOf('async function tanyaAsisten'));
assert.doesNotMatch(gel, /innerHTML/, 'gelembung tidak boleh memakai innerHTML');
const jsTanpaKomentar = js.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
assert.doesNotMatch(jsTanpaKomentar, /localStorage|sessionStorage/, 'percakapan tidak boleh disimpan di peramban');
assert.match(js, /sb\.functions\.invoke\('ai-asisten'/);
const tabRingkasan = rekap.slice(rekap.indexOf('<section class="tab-pane is-on" data-pane="ringkasan"'),
                                 rekap.indexOf('<section class="tab-pane" data-pane="keuangan"'));
assert.match(tabRingkasan, /id="asistenLog"/, 'panel di tab Ringkasan');

console.log('ai-asisten: semua pemeriksaan lolos');
