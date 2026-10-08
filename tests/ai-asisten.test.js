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
assert.match(js, /panggilAi\('ai-asisten'/);
/* Asisten melayang: satu pintu masuk yang terlihat di SEMUA tab. Owner pernah
   mengeluh tidak menemukan AI-nya — panelnya terkubur di tab Ringkasan. Maka
   tombolnya harus di luar <main> dan di luar tab mana pun. */
const iMainTutup = rekap.indexOf('</main>');
const iFab = rekap.indexOf('id="btnAiFab"');
const iSheet = rekap.indexOf('id="aiSheet"');
const iLog = rekap.indexOf('id="asistenLog"');
assert.ok(iFab > iMainTutup && iSheet > iMainTutup && iLog > iSheet, 'tombol dan jendela AI harus di luar <main>, tidak ikut tersembunyi saat berpindah tab');
for (const pane of rekap.matchAll(/<section class="tab-pane[^"]*" data-pane="([a-z]+)"[\s\S]*?<\/section>/g)) {
  assert.doesNotMatch(pane[0], /id="asistenLog"|id="btnAiFab"/, `${pane[1]}: asisten tidak boleh terkubur di dalam tab`);
}
const fab = rekap.match(/<button class="ai-fab"[\s\S]*?<\/button>/)[0];
assert.match(fab, /aria-label="Buka asisten AI"/, 'tombol harus punya nama untuk pembaca layar');
assert.match(fab, /aria-expanded="false" aria-controls="aiSheet"/);
assert.match(rekap, /<div class="ai-sheet" id="aiSheet" role="dialog" aria-label="Asisten AI" hidden>/);
// Lapisan: di atas header (50) dan bilah kategori (9), di bawah editor modal (200).
const z = (sel) => Number(rekap.match(new RegExp(sel.replace('.', '\\.') + ' \\{[^}]*?z-index: (\\d+)'))[1]);
assert.ok(z('.ai-fab') > 50 && z('.ai-sheet') > z('.ai-fab') && z('.ai-sheet') < 200, 'z-index jendela AI di antara header dan modal');
assert.match(rekap, /\.ai-fab, \.ai-sheet \{ display: none !important; \}/, 'tidak ikut tercetak');
// Pintasan menunjuk elemen yang benar-benar ada, dan memicu klik di dalam
// penanganan sentuhan itu (pemilih berkas menolak dipicu dari tempat lain).
const pintas = rekap.slice(rekap.indexOf('const PINTASAN_AI = {'), rekap.indexOf('async function loadHpp()'));
for (const m of pintas.matchAll(/(?:klik|gulir): '([A-Za-z]+)'/g)) {
  assert.ok(rekap.includes(`id="${m[1]}"`), `pintasan menunjuk #${m[1]} yang tidak ada`);
}
assert.match(pintas, /document\.getElementById\(p\.klik\)\.click\(\);/);
assert.doesNotMatch(pintas, /setTimeout|await /, 'klik pintasan tidak boleh tertunda: pemilih berkas butuh gestur langsung');
assert.match(rekap, /e\.key === 'Escape' && !document\.getElementById\('aiSheet'\)\.hidden/, 'Escape menutup jendela');

/* Tampilan ponsel. Tiap butir pernah terlihat salah di ukuran nyata:
   - iOS Safari memperbesar halaman sendiri bila kolom yang diketuk berfont
     di bawah 16px;
   - papan ketik HP menutupi bawah layar tanpa mengubah tinggi halaman, jadi
     lembar yang menempel ke bawah ikut tertutup — termasuk kolom ketiknya;
   - wadah yang menggulir mendatar kehilangan tinggi minimumnya dan ikut
     mengecil sampai tombolnya terpotong. */
const coarse = rekap.slice(rekap.indexOf('@media (pointer: coarse) {'));
assert.match(coarse.slice(0, 900), /\.asisten-form input[\s\S]*?font-size: 16px;/, 'kolom ketik asisten 16px di layar sentuh');
assert.match(coarse.slice(0, 900), /\.asisten-form input, \.asisten-form \.btn-hdr \{ min-height: 44px; \}/, 'sasaran sentuh 44px');
assert.match(rekap, /\.ai-kepala \.btn-hapus \{ min-width: 44px; min-height: 44px;/, 'tombol tutup 44px');
assert.match(rekap, /\.ai-pintasan \{ display: flex; gap: 6px; flex-wrap: wrap; flex: none; \}/, 'wadah pintasan tidak boleh mengecil');
assert.match(rekap, /bottom: var\(--ai-naik, 0px\)/, 'lembar naik di atas papan ketik');
assert.match(rekap, /window\.visualViewport\.addEventListener\('resize', selarasPapanKetik\)/, 'tinggi papan ketik dibaca dari visualViewport');
assert.match(rekap, /\.ai-sheet \{ overflow-y: auto; \}/, 'isi yang melebihi lembar menggulir, tidak meluber');
assert.match(rekap, /main\.rekap-container \{ margin-bottom: 76px; \}/, 'tombol melayang tidak menutupi baris terakhir');

/* ── Rincian transaksi (migrasi 59) ──────────────────────────────────────
   Owner bertanya "6 transaksi itu detailnya bagaimana" dan asisten menjawab
   datanya tidak tersedia. Rinciannya kini ikut, tanpa data pelanggan, lewat
   fungsi terpisah yang tidak menimpa ringkasan_asisten. */
const m59 = baca('supabase_migration_59_transaksi_asisten.sql');
const transaksi = definisiTerakhir('transaksi_asisten');
assert.equal(transaksi.dari, 'supabase_migration_59_transaksi_asisten.sql');
assert.match(m59, /REVOKE EXECUTE ON FUNCTION transaksi_asisten\(DATE\) FROM PUBLIC, anon, authenticated;/);
assert.match(m59, /GRANT  EXECUTE ON FUNCTION transaksi_asisten\(DATE\) TO service_role;/);
assert.doesNotMatch(m59, /GRANT\s+EXECUTE ON FUNCTION transaksi_asisten\(DATE\) TO (authenticated|anon|PUBLIC)/);
assert.doesNotMatch(transaksi.badan, /SECURITY DEFINER|EXECUTE\s/);
assert.match(transaksi.badan, /LIMIT 500\b/, 'ukuran permintaan ke model dibatasi');
assert.match(transaksi.badan, /p_hari_ini - 59 AND p_hari_ini/, 'jendela sama dengan harian_60_hari');
for (const kolom of ['phone_wa', 'member_phone', 'member_name', 'telepon', 'm.name', 'customer']) {
  assert.ok(!transaksi.badan.includes(kolom), `rincian transaksi tidak boleh memuat ${kolom}`);
}
assert.equal(definisiTerakhir('ringkasan_asisten').dari, 'supabase_migration_58_ringkasan_asisten.sql',
  'ringkasan_asisten tidak ditulis ulang oleh migrasi 59');
// Opsional: migrasi 59 belum dijalankan tidak boleh mematikan asisten.
assert.match(fn, /rpc\('transaksi_asisten', \{ p_hari_ini: hariIni \}\)/);
assert.match(fn, /galatTransaksi \? ringkasan : \{ \.\.\.ringkasan, transaksi_60_hari/);
assert.ok(fn.indexOf("profil?.role !== 'owner'") < fn.indexOf("rpc('transaksi_asisten'"), 'owner diperiksa sebelum rincian dibaca');
assert.doesNotMatch(rekap, /rpc\('transaksi_asisten'/, 'peramban tidak boleh memanggil rincian');
const instr = fn.slice(fn.indexOf('const INSTRUKSI'), fn.indexOf('async function catatPemakaian'));
assert.match(instr, /transaksi_60_hari/);
assert.doesNotMatch(instr, /transaksi satu per satu, gaji/, 'instruksi tidak boleh lagi melarang rincian transaksi');

/* ── Jawaban rapi ─────────────────────────────────────────────────────────
   Jawaban rincian transaksi tampil sebagai satu blok teks yang sulit dibaca.
   Layar kini membentuk paragraf dan daftar, tanpa innerHTML. */
const rapi = js.slice(js.indexOf('function isiRapiAsisten'), js.indexOf('function gelembungAsisten'));
assert.ok(rapi.length > 200, 'pemformat jawaban harus ditemukan');
assert.doesNotMatch(rapi.replace(/\/\*[\s\S]*?\*\//g, ''), /innerHTML|insertAdjacentHTML/, 'pemformat tidak boleh memakai innerHTML');

function simpul(tag) {
  return {
    tag, anak: [], teks: '', className: '',
    appendChild(c) { this.anak.push(c); return c; },
    set textContent(v) { this.teks = v; this.anak = []; },
    get firstChild() { return this.anak[0] || null; },
  };
}
const doc = { createElement: simpul, createTextNode: (t) => ({ tag: '#teks', teks: t, anak: [] }) };
const rapiFn = new Function('document', rapi + '; return isiRapiAsisten;')(doc);
function ratakan(n) {
  if (n.tag === '#teks') return n.teks;
  return '<' + n.tag + '>' + (n.anak.length ? n.anak.map(ratakan).join('') : n.teks) + '</' + n.tag + '>';
}
function render(teks) { const el = simpul('div'); rapiFn(el, teks); return el.anak.map(ratakan).join(''); }
function bungkus(teks) { const el = simpul('div'); rapiFn(el, teks); return el; }

// Paragraf, daftar, tebal.
assert.equal(
  render('Omzet **12 September** **Rp 378.000**.\n\n- 07:30 · Haircut · Rp 59.500\n- 14:46 · Haircut + Hairwash · Rp 70.000\nTotal enam.'),
  '<p>Omzet <strong>12 September</strong> <strong>Rp 378.000</strong>.</p><ul><li>07:30 · Haircut · Rp 59.500</li><li>14:46 · Haircut + Hairwash · Rp 70.000</li></ul><p>Total enam.</p>',
  'satu butir per baris menjadi satu <li>, kalimat biasa menjadi paragraf');
// Judul, miring, kode inline, daftar bernomor, garis.
assert.equal(
  render('### Ringkasan\nIni *penting* dan `INV-001`.\n---\n1. Satu\n2) Dua'),
  '<h4>Ringkasan</h4><p>Ini <em>penting</em> dan <code>INV-001</code>.</p><hr></hr><ol><li>Satu</li><li>Dua</li></ol>',
  'judul, miring, kode, garis, dan daftar bernomor');
// Tabel: kepala, sekat dengan perataan, baris data; kolom kurang diisi kosong.
const tabel = bungkus('| Jam | Layanan | Total |\n|---|:---:|---:|\n| 14:46 | **Haircut** | Rp 70.000 |\n| 15:52 | Haircut |\n\nSudah.');
assert.equal(
  tabel.anak.map(ratakan).join(''),
  '<div><table><thead><tr><th>Jam</th><th>Layanan</th><th>Total</th></tr></thead>'
  + '<tbody><tr><td>14:46</td><td><strong>Haircut</strong></td><td>Rp 70.000</td></tr>'
  + '<tr><td>15:52</td><td>Haircut</td><td></td></tr></tbody></table></div><p>Sudah.</p>',
  'tabel berpipa menjadi table; baris pendek dilengkapi sel kosong; teks sesudahnya tetap paragraf');
assert.match(tabel.className, /ada-tabel/, 'gelembung bertabel dilebarkan lewat kelas ada-tabel');
const sel = tabel.anak[0].anak[0].anak[1].anak[0].anak; // table > tbody > tr > sel
assert.equal(sel[2].className, 'kanan', 'sekat ---: merataankan kolom ke kanan');
assert.equal(sel[1].className, 'tengah', 'sekat :---: memusatkan kolom');
assert.equal(sel[0].className, '');
// Judul kolom ikut rata dengan isinya; kepala yang tidak rata dengan angkanya terlihat salah.
const kepalaSel = tabel.anak[0].anak[0].anak[0].anak[0].anak; // table > thead > tr > th
assert.equal(kepalaSel[2].className, 'kanan', 'judul kolom angka ikut rata kanan');
assert.equal(kepalaSel[1].className, 'tengah');
// Baris berpipa tanpa sekat BUKAN tabel.
assert.equal(render('a | b'), '<p>a | b</p>', 'tabel hanya bila ada baris sekat');
// Tabel tidak menelan teks tak berpipa di bawahnya, dan tidak berhenti di baris kosong salah.
assert.equal(bungkus('| A |\n|---|\n| 1 |\n\n| B |\n|---|\n| 2 |').anak.length, 2, 'dua tabel terpisah baris kosong');
assert.equal(render('<img src=x onerror=alert(1)>'), '<p><img src=x onerror=alert(1)></p>',
  'tag HTML dari model hanya menjadi teks, bukan elemen');
assert.equal(render('Satu\r\nDua'), '<p>Satu</p><p>Dua</p>');
assert.equal(render(''), '', 'jawaban kosong tidak melempar galat');
assert.match(gel, /isiRapiAsisten\(el, teks\)/, 'gelembung AI memakai pemformat');
assert.match(gel, /else el\.textContent = teks;/, 'pertanyaan owner dan teks tunggu tetap lewat textContent');
const instr2 = fn.slice(fn.indexOf('const INSTRUKSI'), fn.indexOf('async function catatPemakaian'));
assert.match(instr2, /Satu butir per baris/, 'model diminta satu butir per baris');
assert.match(instr2, /pakai TABEL/, 'model diminta memakai tabel untuk data berkolom');
assert.match(instr2, /\|---\|---\|---:\|---\|/, 'model diberi contoh baris sekat tabel');
// Layar sempit: tabel lima kolom dengan kolom seragam (semua QRIS) membuat kolom
// terakhir terpotong. Model harus diminta meringkas, bukan hanya diberi contoh.
assert.match(instr2, /paling banyak 4 kolom/, 'jumlah kolom dibatasi');
assert.match(instr2, /isinya sama di SEMUA baris[\s\S]{0,40}jangan dijadikan kolom/, 'kolom seragam tidak dijadikan kolom');
assert.match(instr2, /Judul kolom satu kata pendek/, 'judul kolom pendek');

// Sel berteks panjang boleh turun baris; jam dan angka tidak pernah dipotong.
const panjang = bungkus('| Jam | Layanan | Total |\n|---|---|---:|\n| 14:46 | Haircut + Hairwash + Creambath | Rp 70.000 |');
const selBaris = panjang.anak[0].anak[0].anak[1].anak[0].anak;
assert.equal(selBaris[0].className, '', 'jam pendek tidak boleh dibungkus');
assert.equal(selBaris[1].className, 'panjang', 'nama layanan panjang boleh turun baris');
assert.equal(selBaris[2].className, 'kanan', 'angka rupiah tidak dibungkus dan rata kanan');
// CSS: bawaan sel adalah satu baris; hanya .panjang yang boleh membungkus.
const cssTabel = rekap.slice(rekap.indexOf('.asisten-gelembung.ai th, .asisten-gelembung.ai td {'));
assert.match(cssTabel.slice(0, 400), /white-space: nowrap/, 'sel tabel secara bawaan tidak dibungkus');
assert.match(rekap, /\.asisten-gelembung\.ai td\.panjang \{ white-space: normal;/, 'hanya .panjang yang membungkus');
assert.doesNotMatch(fn, /teks biasa tanpa markdown/, 'skema tidak boleh lagi melarang format');
// INSTRUKSI adalah template literal: satu backtick nyasar di dalamnya memutus
// string dan seluruh fungsi gagal dimuat. Hanya pembuka dan penutup yang boleh ada.
assert.equal((instr2.match(/`/g) || []).length, 2, 'INSTRUKSI tidak boleh memuat backtick di dalam teksnya');
assert.doesNotMatch(instr2, /\$\{(?!INSTRUKSI)/, 'INSTRUKSI tidak boleh memuat interpolasi liar');

console.log('ai-asisten: semua pemeriksaan lolos');
