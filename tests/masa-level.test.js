/* K-04 dan K-06 dari spesifikasi MBR-UB-01-DEV.
 *
 * K-04 — pembelian produk tidak menghasilkan poin.
 * K-06 — level berlaku satu tahun, lalu poin seumur hidup dipotong sebesar
 *        ambang levelnya; naik level memulai periode baru.
 *
 * Yang dijaga di sini adalah hal-hal yang rusaknya tidak kelihatan sampai
 * berbulan-bulan kemudian: poin yang diam-diam dihitung dari produk, saldo
 * yang ikut terpotong saat perpanjangan, dan kolom tabel yang bergeser.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baca = f => fs.readFileSync(path.join(root, f), 'utf8');

const m42 = baca('supabase_migration_42_poin_hanya_layanan.sql');
const m43 = baca('supabase_migration_43_masa_berlaku_level.sql');
const m44 = baca('supabase_migration_44_tampilan_masa_level.sql');
const kartu = baca('kartu.html');
const rekap = baca('rekap.html');

/* ── K-04 · Poin hanya dari layanan ───────────────────────────────────────*/

// Bagian layanan dijumlah terpisah, dan dasarnya dibagi menurut porsi itu.
assert.match(m42,
  /FILTER \(\s*WHERE COALESCE\(NULLIF\(elem->>'item_type',''\), 'layanan'\) = 'layanan'\)/,
  'porsi layanan harus dijumlah dari item_type');
assert.match(m42, /v_dasar := CASE WHEN p_subtotal > 0\s+THEN v_final \* v_layanan \/ p_subtotal/);
assert.match(m42, /v_earn := floor\(v_dasar \* v_set\.earn_percent \/ 100 \* v_mult\);/);
assert.doesNotMatch(m42, /v_earn := floor\(v_final \* v_set\.earn_percent/,
  'dasar poin tidak boleh kembali ke seluruh tagihan');

// Nilai bawaan item_type harus sama persis di dua tempat. Kalau penjumlahan
// menganggap item tanpa tipe sebagai produk sementara penyisipan menganggapnya
// layanan, item itu masuk laporan sebagai layanan tetapi tidak menghasilkan
// poin — dan tidak ada satu pun galat yang muncul.
const bawaanJumlah = m42.match(/COALESCE\(NULLIF\(elem->>'item_type',''\), '(\w+)'\)/);
const bawaanLoop = m42.match(/COALESCE\(NULLIF\(v_item->>'item_type',''\)::item_kind, '(\w+)'\)/);
assert.ok(bawaanJumlah && bawaanLoop, 'kedua nilai bawaan item_type harus ada');
assert.equal(bawaanJumlah[1], bawaanLoop[1],
  'nilai bawaan item_type harus sama di penjumlahan dan penyisipan');

// Pembagiannya sebanding, bukan dibebankan ke salah satu sisi.
assert.doesNotMatch(m42, /v_layanan - v_disc|v_layanan - v_manual/,
  'potongan tidak boleh dibebankan seluruhnya ke porsi layanan');

/* ── K-06 · Masa berlaku satu tahun ───────────────────────────────────────*/

assert.match(m43, /ALTER TABLE members ADD COLUMN IF NOT EXISTS tier_period_end DATE;/);
assert.match(m43, /SET DEFAULT \(\(jakarta_today\(\) \+ INTERVAL '1 year'\)::date\);/,
  'DEFAULT di kolom, bukan di tiap fungsi pendaftaran');
assert.match(m43, /ALTER TABLE members ALTER COLUMN tier_period_end SET NOT NULL;/);

const mesin = m43.slice(m43.indexOf('FUNCTION perpanjang_masa_level'),
                        m43.indexOf('CREATE OR REPLACE FUNCTION owner_jalankan_perpanjangan'));

// Potongannya sebesar ambang level yang sedang dipegang.
assert.match(mesin, /SELECT tr\.min_lifetime_points INTO v_min\s+FROM tier_rules tr WHERE tr\.tier = m\.tier;/);
assert.match(mesin, /v_sesudah\s+:= GREATEST\(v_sebelum - v_min, 0\);/,
  'poin seumur hidup tidak boleh menjadi negatif');
assert.match(mesin, /v_tier_baru := compute_tier\(v_sesudah\);/);

// Saldo yang dapat dibelanjakan tidak boleh ikut terpotong. Ini janji yang
// berbeda dari level, dan pemilik tidak pernah meminta menariknya kembali.
assert.doesNotMatch(mesin, /points_balance/,
  'perpanjangan tidak boleh menyentuh saldo poin');

// Tier sebelum diambil dari yang tersimpan, bukan dihitung ulang dari poin:
// keduanya bisa berbeda pada data lama, dan jejak audit harus mencatat apa
// yang benar-benar dipegang member, bukan apa yang seharusnya.
assert.match(mesin, /v_tier_lama := m\.tier;/);
assert.match(mesin, /VALUES \(m\.id, jakarta_today\(\), v_tier_lama, v_tier_baru,/);

// Periode yang tertinggal diselesaikan sekaligus, dengan batas putaran.
assert.match(mesin, /WHILE m\.tier_period_end <= jakarta_today\(\) AND v_putar < 20 LOOP/);
assert.match(mesin, /tier_period_end = \(members\.tier_period_end \+ INTERVAL '1 year'\)::date,/,
  'periode berikutnya dihitung dari periode lama, bukan dari hari ini');

// Kenaikan level memulai periode baru, dibandingkan lewat ambang.
assert.match(m43, /SELECT \(SELECT tr\.min_lifetime_points FROM tier_rules tr WHERE tr\.tier = v_tier_baru\)\s+> \(SELECT tr\.min_lifetime_points FROM tier_rules tr WHERE tr\.tier = v_tier_lama\)\s+INTO v_naik;/);
assert.match(m43, /tier_period_end = CASE WHEN v_naik\s+THEN \(jakarta_today\(\) \+ INTERVAL '1 year'\)::date\s+ELSE members\.tier_period_end END,/);

// Jejaknya bukan di point_ledger: buku besar itu mencatat pergerakan saldo,
// dan perpanjangan tidak menggerakkan saldo.
assert.doesNotMatch(mesin, /point_ledger/,
  'perpanjangan tidak boleh menulis ke buku besar poin');
assert.match(m43, /CREATE TABLE IF NOT EXISTS perpanjangan_level/);
assert.match(m43, /ALTER TABLE perpanjangan_level ENABLE ROW LEVEL SECURITY;/);
assert.doesNotMatch(m43, /CREATE POLICY[\s\S]*perpanjangan_level/);

// Mesinnya tidak boleh dapat dipanggil dari peramban sama sekali; yang
// terbuka hanyalah pembungkus yang memeriksa owner.
assert.match(m43, /REVOKE EXECUTE ON FUNCTION perpanjang_masa_level\(\) FROM PUBLIC, anon, authenticated;/);
assert.doesNotMatch(m43, /GRANT\s+EXECUTE ON FUNCTION perpanjang_masa_level/);
assert.match(m43, /IF NOT is_owner\(\) THEN\s+RAISE EXCEPTION 'Hanya owner yang boleh menjalankan perpanjangan level\.';/);
for (const f of ['owner_jalankan_perpanjangan\\(\\)', 'owner_perpanjangan_level\\(INT\\)']) {
  assert.match(m43, new RegExp(`REVOKE EXECUTE ON FUNCTION ${f} FROM PUBLIC, anon;`),
    `${f} harus dicabut dari anon`);
}

// Berjalan sendiri, bukan menunggu owner ingat.
assert.match(m43, /CREATE EXTENSION IF NOT EXISTS pg_cron;/);
assert.match(m43, /cron\.schedule\('perpanjang-masa-level', '0 18 \* \* \*'/,
  '18:00 UTC = 01:00 WIB, di luar jam buka');

/* ── Migrasi 44 · angka yang dibaca orang ─────────────────────────────────*/

// Yang perlu dikumpulkan adalah DUA KALI ambang: pada akhir periode poin
// dipotong sebesar ambang, jadi sisanya baru cukup bila ia dua kali lipat.
const duaKali = /GREATEST\(\(SELECT tr\.min_lifetime_points \* 2 FROM tier_rules tr\s+WHERE tr\.tier = m\.tier\) - m\.lifetime_points, 0\)/g;
assert.equal((m44.match(duaKali) || []).length, 2,
  'member_card dan owner_members_list harus memakai rumus yang sama');

// DROP memulihkan hak bawaan Supabase, yang mencakup anon. Kartu member
// memang terbuka untuk anon; daftar member owner tidak.
assert.match(m44, /GRANT\s+EXECUTE ON FUNCTION member_card\(TEXT\) TO anon, authenticated;/);
assert.match(m44, /REVOKE EXECUTE ON FUNCTION owner_members_list\(INT\) FROM PUBLIC, anon;/);
assert.doesNotMatch(m44, /GRANT\s+EXECUTE ON FUNCTION owner_members_list\(INT\) TO anon/);

/* ── Layar ────────────────────────────────────────────────────────────────*/

// Silver berambang nol dan tidak pernah turun. Menampilkan tanggal di sana
// menakut-nakuti tanpa ada yang dapat dilakukan orangnya.
assert.match(kartu, /if \(!m\.masa_berlaku \|\| tier === 'Silver'\) \{ el\.hidden = true; return; \}/);
assert.match(rekap, /if \(!m\.masa_berlaku \|\| m\.tier === 'Silver'\)/);

// Tabel member: jumlah kolom kepala, jumlah sel per baris, dan colspan baris
// kosong harus tetap bertiga sama. Kolom yang bergeser tidak pernah melempar
// galat — ia hanya menaruh angka di bawah judul yang salah.
const kepala = rekap.slice(rekap.indexOf('<table class="tx-table" id="memberTable">'));
const barisKepala = kepala.slice(kepala.indexOf('<tr>'), kepala.indexOf('</tr>'));
const jumlahKepala = (barisKepala.match(/<th/g) || []).length;

const perender = rekap.slice(rekap.indexOf('tb.innerHTML = rows.map(function (m) {'));
const badanBaris = perender.slice(0, perender.indexOf(".join('');"));
const jumlahSel = (badanBaris.match(/\+ '<td/g) || []).length;

const daftarMember = rekap.slice(rekap.indexOf('async function muatMember()'),
                                 rekap.indexOf("document.getElementById('memberTableBody').addEventListener('click', async (e)"));
const colspan = [...daftarMember.matchAll(/colspan="(\d+)"/g)].map(x => Number(x[1]));

assert.equal(jumlahKepala, 11, 'tabel member harus punya 11 kolom');
assert.equal(jumlahSel, jumlahKepala, 'jumlah sel harus sama dengan jumlah kolom kepala');
assert.ok(colspan.length >= 2, 'baris kosong dan baris galat sama-sama perlu colspan');
for (const c of colspan) {
  assert.equal(c, jumlahKepala, 'colspan harus mengikuti jumlah kolom');
}

// Tombol manual ada, dan menjalankan pembungkus yang memeriksa owner —
// bukan mesinnya langsung.
assert.match(rekap, /sb\.rpc\('owner_jalankan_perpanjangan'\)/);
assert.doesNotMatch(rekap, /sb\.rpc\('perpanjang_masa_level'/);
assert.match(rekap, /sb\.rpc\('owner_perpanjangan_level'/);

console.log('Masa berlaku level & poin layanan tests: OK');
