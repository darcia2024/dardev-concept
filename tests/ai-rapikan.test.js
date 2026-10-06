/* Add-on AI, fitur 2: catatan acak dan voice note dirapikan AI (migrasi 56, ai-rapikan).
 *
 * Yang dijaga di sini adalah janji yang, bila dilanggar, tidak tampak sebagai
 * galat — hanya sebagai tagihan yang membengkak, kunci yang bocor, rekaman
 * suara yang diam-diam tersimpan, atau instruksi salah dengar yang tersebar
 * ke tim seolah fakta:
 *
 *   1. Kunci API AI tidak pernah sampai ke peramban.
 *   2. AI hanya MERAPIKAN. Tidak ada yang tersimpan sebelum owner menekan Simpan.
 *   3. Rekaman suara tidak disimpan di mana pun.
 *   4. Batas harian diperiksa SEBELUM model AI dihubungi.
 *   5. Audio dikirim dalam format yang memang diterima OpenRouter.
 *   6. Hasil AI tidak pernah dirender sebagai HTML.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir, root } = require('./_migrasi');

const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const fn    = baca('supabase/functions/ai-rapikan/index.ts');
const rekap = baca('rekap.html');
const m56   = baca('supabase_migration_56_catatan_rapi.sql');
const js    = rekap.slice(rekap.indexOf('RAPIKAN CATATAN (Add-on AI, fitur 2)'), rekap.indexOf('async function loadHpp()'));
assert.ok(js.length > 1000, 'kode layar Rapikan Catatan harus ditemukan');

/* ── 1 · Kunci hanya di server ───────────────────────────────────────────── */
assert.match(fn, /Deno\.env\.get\('OPENROUTER_API_KEY'\)/);
assert.match(js, /sb\.functions\.invoke\('ai-rapikan'/, 'merapikan harus lewat Edge Function');
assert.doesNotMatch(rekap, /openrouter\.ai\/api/, 'peramban tidak boleh memanggil OpenRouter langsung');

/* ── 2 · AI hanya merapikan ──────────────────────────────────────────────── */
assert.doesNotMatch(fn, /from\('catatan_rapi'\)|rpc\(\s*'owner_simpan_catatan_rapi'/, 'ai-rapikan tidak boleh menyimpan catatan');
const penangan = js.slice(js.indexOf("getElementById('btnRapikan').addEventListener"),
                          js.indexOf('/* ── Penyunting hasil'));
assert.ok(penangan.length > 0);
assert.match(penangan, /bukaEditorRapi\(null, hasil\.judul, hasil, sumber\)/, 'hasil AI membuka penyunting untuk diperiksa');
assert.doesNotMatch(penangan, /owner_simpan_catatan_rapi/, 'merapikan tidak boleh langsung menyimpan');

/* ── 3 · Rekaman suara tidak disimpan ────────────────────────────────────── */
assert.doesNotMatch(m56.replace(/--.*$/gm, ''), /audio|storage\.|bucket/i, 'tidak boleh ada kolom atau bucket audio');
assert.doesNotMatch(fn, /storage\.from|\.upload\(/, 'Edge Function tidak boleh mengunggah rekaman');
// Yang dicatat hanya panjangnya.
assert.match(fn, /keterangan: audio \? `suara \$\{detik\} detik` : 'teks'/);
assert.doesNotMatch(fn, /keterangan:[^\n]*(audio\.slice|teks\.slice|\$\{teks\}|\$\{audio\})/, 'isi catatan tidak boleh masuk ai_pemakaian');
assert.doesNotMatch(js, /\.upload\(|storage\.from/, 'layar tidak boleh mengunggah rekaman');

/* ── 4 · Batas harian sebelum AI, owner sebelum masukan ─────────────────── */
const iBatas = fn.indexOf('>= BATAS_HARIAN');
const iAi    = fn.indexOf("fetch('https://openrouter.ai/api/v1/chat/completions'");
assert.ok(iBatas > 0 && iAi > 0 && iBatas < iAi, 'batas harian harus diperiksa sebelum model AI dihubungi');
assert.match(fn, /\.eq\('fitur', 'rapikan'\)/, 'batasnya dihitung terpisah dari struk dan chat');
assert.ok(fn.indexOf("profil?.role !== 'owner'") < fn.indexOf('await req.json()'), 'owner diperiksa sebelum masukan dibaca');
assert.ok((fn.slice(iAi).match(/await catatPemakaian\(/g) || []).length >= 6,
  'jaringan, galat HTTP, refusal, length, JSON rusak, dan berhasil harus semuanya tercatat');
// Masukan dibatasi sebelum AI dihubungi.
for (const jaga of ['teks.length > TEKS_MAKS', 'audio.length > AUDIO_MAKS_BASE64']) {
  assert.ok(fn.indexOf(jaga) > 0 && fn.indexOf(jaga) < iAi, `${jaga} harus diperiksa sebelum AI`);
}

/* ── 5 · Audio dan permintaan ke OpenRouter ──────────────────────────────── */
// OpenRouter tidak menerima webm — padahal itu yang dihasilkan perekam Chrome.
assert.match(fn, /type: 'input_audio', input_audio: \{ data: audio, format: 'wav' \}/);
assert.match(js, /function keWav\(sampel, laju\)/, 'rekaman harus diubah ke WAV di peramban');
assert.match(js, /tulis\(0, 'RIFF'\)[\s\S]*tulis\(8, 'WAVE'\)/, 'header WAV harus benar');
assert.match(js, /const LAJU = 16000;/);
assert.match(js, /REKAM_MAKS_DETIK = 180/, 'rekaman berhenti sendiri di 3 menit');
assert.match(fn, /provider: \{ require_parameters: true \}/);
const badanPermintaan = fn.slice(iAi, fn.indexOf('  } catch (e) {', iAi));
assert.doesNotMatch(badanPermintaan, /reasoning\s*:/, 'parameter reasoning tidak boleh dikirim bersama require_parameters');
assert.match(fn, /json_schema: \{ name: 'catatan_rapi', strict: true, schema: SKEMA_RAPI \}/);
const skema = fn.slice(fn.indexOf('const SKEMA_RAPI'), fn.indexOf('as const;', fn.indexOf('const SKEMA_RAPI')));
assert.doesNotMatch(skema, /minimum|maximum|minLength|maxLength|multipleOf|anyOf|'null'/);
assert.equal((skema.match(/type: 'object'/g) || []).length, (skema.match(/additionalProperties: false/g) || []).length,
  'setiap objek dalam skema harus additionalProperties: false');
const iParse = fn.indexOf('JSON.parse(isiJawaban');
assert.ok(fn.indexOf('if (kodeGalat)') < iParse && fn.indexOf('message?.refusal') < iParse
  && fn.indexOf("finish_reason === 'length'") < iParse, 'galat, penolakan, dan jawaban terpotong ditangani sebelum JSON dibaca');
assert.match(fn, /kodeGalat === 402\)[\s\S]{0,120}Saldo layanan AI habis/);

/* ── 6 · Hasil AI tidak pernah dirender sebagai HTML ─────────────────────
   Setiap teks dari hasil AI atau dari basis data yang masuk ke innerHTML
   harus lewat escapeHtml. Diperiksa hanya di fungsi yang menyusun HTML;
   teksRapi menyusun teks polos untuk WhatsApp dan memang tidak di-escape. */
const fungsiHtml = ['isiRapiHtml', 'gambarDaftarRapi', 'barisTodoRapi', 'barisLangkahRapi', 'gambarTabelRapi']
  .map(function (n) {
    const a = js.indexOf('function ' + n + '(');
    assert.ok(a > 0, n + ' harus ada');
    return js.slice(a, js.indexOf('\n    }\n', a));
  }).join('\n');
for (const kunci of ['tugas', 'untuk', 'kapan', 'judul', 'ringkasan']) {
  assert.doesNotMatch(fungsiHtml, new RegExp(`\\+ (t|c|isi)\\.${kunci} \\+`), `${kunci} disambung ke HTML tanpa escapeHtml`);
}
assert.doesNotMatch(fungsiHtml, /'<t[hd]>' \+ [a-z]+ \+ '<\/t[hd]>'/, 'sel tabel harus lewat escapeHtml');
assert.doesNotMatch(fungsiHtml, /'<li>' \+ l \+/, 'langkah harus lewat escapeHtml');
assert.doesNotMatch(fungsiHtml, /\+ ket \+/, 'keterangan to-do harus lewat escapeHtml');
assert.doesNotMatch(teksDiperiksa(), /innerHTML\s*=\s*teks/, 'teks salinan tidak boleh masuk innerHTML');
function teksDiperiksa() { return js; }

/* ── 7 · Basis data ──────────────────────────────────────────────────────── */
const simpan = definisiTerakhir('owner_simpan_catatan_rapi').badan;
assert.match(simpan, /IF NOT is_owner\(\) THEN/);
assert.match(simpan, /v_isi := catatan_rapi_bersihkan\(p_isi\);/, 'isi dari peramban harus dibersihkan, bukan dipercaya');
for (const f of ['owner_simpan_catatan_rapi', 'owner_catatan_rapi_list', 'owner_hapus_catatan_rapi']) {
  assert.match(m56, new RegExp(`REVOKE EXECUTE ON FUNCTION ${f}\\([^)]*\\) FROM PUBLIC, anon;`), `${f} harus dicabut dari anon`);
  assert.match(definisiTerakhir(f).badan, /is_owner\(\)/, `${f} hanya untuk owner`);
}
assert.match(m56, /ALTER TABLE catatan_rapi ENABLE ROW LEVEL SECURITY;/);

/* ── 8 · Panel berada di tab Karyawan dan ikut dimuat ────────────────────── */
const tabKaryawan = rekap.slice(rekap.indexOf('<section class="tab-pane" data-pane="karyawan"'),
                                rekap.indexOf('<section class="tab-pane" data-pane="member"'));
assert.match(tabKaryawan, /id="daftarRapi"/, 'panel Rapikan Catatan harus di tab Karyawan');
assert.match(rekap, /await loadCuti\(\);\s*\n\s*await muatCatatanRapi\(\);/, 'daftar catatan harus ikut dimuat');
// Tanpa ini tabel catatan selebar 700px dan di ponsel hanya kolom pertama terlihat.
assert.match(rekap, /table\.tx-table\.rapi-tabel \{ min-width: 0; \}/);

console.log('ai-rapikan: semua pemeriksaan lolos');
