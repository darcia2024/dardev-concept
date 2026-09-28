/* Pembuatan akun karyawan lewat Edge Function (migrasi 48).
 *
 * Membuat pengguna di auth.users butuh service-role key. Kunci itu memintas
 * seluruh Row Level Security, jadi seluruh rancangan ini hanya punya satu
 * alasan: menjauhkannya dari peramban. Yang dijaga di sini adalah empat cara
 * rancangan itu dapat runtuh tanpa ada layar yang memberitahu:
 *
 *   1. Kuncinya bocor ke berkas yang dikirim ke peramban.
 *   2. Penjaga owner dilewati, atau dibaca dari badan permintaan.
 *   3. Peran akun dapat ditentukan pemanggil, sehingga endpoint ini bisa
 *      dipakai mencetak owner baru.
 *   4. Fungsi penaut di basis data terbuka untuk `authenticated`.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');

const fn    = baca('supabase/functions/buat-akun-karyawan/index.ts');
const m48   = baca('supabase_migration_48_tautkan_akun.sql');
const rekap = baca('rekap.html');

/* ── 1 · Service-role key tidak boleh ada di apa pun yang dikirim ke peramban
   Ini pemeriksaan terpenting di berkas ini. Satu baris ceroboh di sini
   menyerahkan seluruh basis data — termasuk nama dan nomor WhatsApp tiap
   pelanggan — kepada siapa pun yang membuka sumber halaman. */
const KE_PERAMBAN = [
  'rekap.html', 'pos.html', 'kartu.html', 'landing.html',
  'capster.html', 'masuk.html', 'app.html', 'sb-app.js', 'sw.js',
];
/* Diperiksa dengan membongkar tiap JWT yang ditemukan, bukan dengan mencari
   kata "service_role". Kata itu justru pantas ada — sb-app.js memuat
   peringatan agar kuncinya tidak pernah ditaruh di sana, dan tes yang
   melarang katanya akan ikut melarang peringatannya. Yang berbahaya adalah
   tokennya, dan token hanya dapat dikenali dari isinya. */
function peranToken(tok) {
  try {
    const muatan = tok.split('.')[1];
    if (!muatan) return null;
    const json = Buffer.from(muatan.replace(/-/g, '+').replace(/_/g, '/'), 'base64')
      .toString('utf8');
    return JSON.parse(json).role || null;
  } catch { return null; }
}

for (const f of KE_PERAMBAN) {
  const isi = baca(f);
  for (const tok of isi.match(/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+/g) || []) {
    const peran = peranToken(tok);
    assert.notEqual(
      peran, 'service_role',
      `${f} memuat token service_role — kunci itu memintas seluruh RLS`
    );
    assert.ok(
      peran === null || peran === 'anon',
      `${f} memuat token berperan "${peran}"; hanya anon/publishable yang boleh`
    );
  }
}

/* Halaman tidak boleh memanggil Admin API sendiri. Itu hanya mungkin dengan
   service-role key, jadi kemunculannya berarti kuncinya sudah di sana. */
assert.doesNotMatch(
  rekap, /auth\.admin\./,
  'rekap.html memanggil Admin API — itu hanya mungkin dengan service-role key'
);
assert.match(
  rekap, /sb\.functions\.invoke\('buat-akun-karyawan'/,
  'pembuatan akun harus lewat Edge Function'
);

/* ── 2 · Penjaga owner dibaca dari JWT, bukan dari badan permintaan ──────── */
assert.match(fn, /auth\.getUser\(jwt\)/, 'JWT pemanggil harus diverifikasi');
assert.match(
  fn, /from\('profiles'\)\.select\('role'\)\.eq\('id', pengguna\.user\.id\)/,
  'peran harus dibaca dari tabel memakai id yang sudah diverifikasi'
);
assert.match(
  fn, /profil\?\.role !== 'owner'[\s\S]{0,200}403/,
  'pemanggil yang bukan owner harus ditolak dengan 403'
);

/* Urutannya penting: penjaga owner harus lewat sebelum badan permintaan
   dibaca sama sekali. Membaca masukan lebih dulu bukan lubang keamanan, tapi
   membuat mudah menyisipkan pekerjaan sebelum penjaganya tanpa disadari. */
assert.ok(
  fn.indexOf("!== 'owner'") < fn.indexOf('await req.json()'),
  'penjaga owner harus diperiksa sebelum badan permintaan diproses'
);

/* ── 3 · Peran akun ditulis tetap, tidak pernah dari pemanggil ───────────── */
assert.match(
  fn, /user_metadata: \{ full_name: karyawan\.name, role: 'capster' \}/,
  "peran harus ditulis tetap 'capster'"
);
assert.doesNotMatch(
  fn, /badan\.role|badan\.peran|body\.role/,
  'peran tidak boleh dibaca dari badan permintaan'
);

/* ── 4 · Fungsi penaut tertutup untuk peramban ───────────────────────────── */
assert.match(
  m48,
  /REVOKE EXECUTE ON FUNCTION tautkan_akun_karyawan\(UUID, UUID\) FROM PUBLIC, anon, authenticated/,
  'tautkan_akun_karyawan harus dicabut dari authenticated, bukan hanya anon'
);
assert.match(
  m48, /GRANT  EXECUTE ON FUNCTION tautkan_akun_karyawan\(UUID, UUID\) TO service_role/,
  'hanya service_role yang boleh memanggil tautkan_akun_karyawan'
);
assert.doesNotMatch(
  rekap, /rpc\('tautkan_akun_karyawan'/,
  'halaman tidak boleh memanggil tautkan_akun_karyawan langsung'
);

/* Penautan menolak menimpa akun yang sudah ada, dan menulis perannya sendiri
   alih-alih menggantungkan diri pada trigger handle_new_user(). Akun tanpa
   metadata berperan 'kasir', dan akibatnya baru terasa saat absen menolak. */
const taut = m48.slice(
  m48.indexOf('FUNCTION tautkan_akun_karyawan'),
  m48.indexOf('REVOKE EXECUTE ON FUNCTION tautkan_akun_karyawan')
);
assert.match(taut, /auth_user_id IS NOT NULL[\s\S]{0,200}RAISE EXCEPTION/,
  'harus menolak menimpa tautan akun yang sudah ada');
assert.match(taut, /INSERT INTO profiles[\s\S]{0,200}'capster'/,
  'perannya harus ditulis, tidak hanya diserahkan ke trigger');

/* ── 5 · Akun yatim dibereskan ────────────────────────────────────────────
   Bila penautan gagal setelah akunnya terlanjur dibuat, akun itu jadi
   kredensial hidup yang tidak muncul di layar mana pun. */
assert.match(
  fn, /galatTaut[\s\S]{0,400}auth\.admin\.deleteUser\(dibuat\.user\.id\)/,
  'akun yang gagal ditautkan harus dihapus kembali'
);
assert.match(
  fn, /gagal dihapus/,
  'kegagalan membereskan akun yatim harus dilaporkan, bukan ditelan'
);

/* ── 6 · Sandi yang diketik owner tidak dipantulkan balik ────────────────── */
assert.match(
  fn, /sandi_dibuat: sandiDiminta \? null : sandi/,
  'sandi hanya boleh dikembalikan bila fungsi ini yang membuatnya'
);
/* Sandi acak memakai sumber acak kriptografis. Math.random dapat ditebak
   dari keluaran sebelumnya, dan ini sandi sungguhan untuk orang sungguhan. */
assert.match(fn, /crypto\.getRandomValues/, 'sandi acak harus kriptografis');
/* Dicari pemanggilannya — `Math.random(` — bukan penyebutannya: komentar di
   fungsi itu justru menjelaskan kenapa ia tidak dipakai, dan tes yang
   melarang namanya akan ikut menghapus alasannya. */
assert.doesNotMatch(fn, /Math\.random\(/, 'Math.random tidak boleh dipakai untuk sandi');

/* ── 7 · Melepas akun tetap owner-only dan tidak menyasar peran lain ─────── */
const lepas = m48.slice(
  m48.indexOf('FUNCTION owner_lepas_akun_karyawan'),
  m48.indexOf('REVOKE EXECUTE ON FUNCTION owner_lepas_akun_karyawan')
);
assert.match(lepas, /IF NOT is_owner\(\) THEN[\s\S]{0,120}RAISE EXCEPTION/,
  'melepas akun harus owner-only');
assert.match(lepas, /p\.role <> 'capster'[\s\S]{0,140}RAISE EXCEPTION/,
  'tidak boleh dipakai melepas akun owner atau perangkat POS');

console.log('akun-karyawan: semua pemeriksaan lolos');
