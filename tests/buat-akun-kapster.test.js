const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');

/* Yang diperiksa adalah definisi TERAKHIR owner_buat_akun_capster, bukan
   berkas migrasi tertentu. Fungsi ini pernah ditulis ulang di migrasi 49
   untuk memperbaiki bentrok dengan trigger profil; tes yang terpaku pada
   migrasi 47 akan lulus sambil menjaga kode yang sudah tidak berjalan lagi —
   bentuk kegagalan yang paling menyesatkan, sebab layarnya hijau. */
function migrasiTerakhirYangMendefinisikan(nama) {
  const berkas = fs.readdirSync(root)
    .filter(f => /^supabase_migration_\d+.*\.sql$/.test(f))
    .map(f => ({ f, n: Number(f.match(/^supabase_migration_(\d+)/)[1]) }))
    .sort((a, b) => a.n - b.n);
  let isi = null, dari = null;
  for (const { f } of berkas) {
    const teks = fs.readFileSync(path.join(root, f), 'utf8');
    if (teks.includes('FUNCTION ' + nama + '(')) { isi = teks; dari = f; }
  }
  assert.ok(isi, nama + ' tidak didefinisikan di migrasi mana pun');
  return { isi, dari };
}

const { isi: m47, dari: berkasFungsi } = migrasiTerakhirYangMendefinisikan('owner_buat_akun_capster');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

/* Fungsi ini membuat akun yang dapat masuk ke sistem. Kegagalannya tidak
   terbaca sebagai galat: akun yang perannya salah tetap bekerja, hanya saja
   pemiliknya melihat hal-hal yang bukan haknya. */

assert.equal((m47.match(/\$function\$/g) || []).length % 2, 0, 'penanda $function$ harus genap');

// ── 1 · Peran DIPAKU 'capster' ─────────────────────────────────────────────
/* Yang paling berbahaya dari fungsi ini adalah bila peran dapat ditentukan
   dari luar. Satu parameter tambahan, dan ia berubah menjadi jalan memunculkan
   owner baru. Perannya harus tertulis mati di badan fungsi. */
const tandaTangan = m47.slice(m47.indexOf('CREATE OR REPLACE FUNCTION owner_buat_akun_capster'),
                              m47.indexOf('RETURNS TABLE'));
assert.equal(tandaTangan.indexOf('role'), -1, 'peran tidak boleh menjadi parameter');
assert.match(m47, /INSERT INTO profiles \(id, full_name, role, is_active\)\s*\n\s*VALUES \(v_uid, v_cap\.name, 'capster', TRUE\)/,
  "peran harus dipaku 'capster' di badan fungsi");

/* ── 1b · Bentrok dengan trigger profil ───────────────────────────────────
   supabase_schema.sql memasang on_auth_user_created pada auth.users: tiap
   baris baru di sana OTOMATIS mendapat barisnya di profiles. Menyisipkan ke
   profiles sesudahnya tanpa ON CONFLICT bertabrakan dengan baris yang dibuat
   fungsi itu sendiri, dan tombol Buat selalu gagal dengan

       duplicate key value violates unique constraint "profiles_pkey"

   Ini pernah terjadi sungguhan, dan selalu — bukan kadang-kadang. */
const sisipProfil = m47.slice(m47.indexOf('INSERT INTO profiles'),
                              m47.indexOf('UPDATE capsters SET auth_user_id'));
assert.match(
  sisipProfil, /ON CONFLICT \(id\) DO UPDATE/,
  'sisipan ke profiles harus ON CONFLICT: trigger on_auth_user_created sudah membuat barisnya lebih dulu'
);
assert.match(
  sisipProfil, /role\s*=\s*'capster'/,
  'pada tabrakan, perannya harus tetap dipaksa capster — bukan dibiarkan apa adanya'
);

/* Dan sebaliknya: trigger membaca role dari raw_user_meta_data. Tanpa kunci
   itu ia memberi peran 'kasir', sehingga kapsternya tidak bisa absen dan
   penggantian sandinya ditolak dengan "Akun itu bukan akun capster" —
   dua kegagalan yang tidak satu pun menyebut sebabnya. */
assert.match(
  m47, /jsonb_build_object\('full_name', v_cap\.name, 'role', 'capster'\)/,
  "raw_user_meta_data harus memuat role: trigger membacanya, dan tanpanya profilnya jadi 'kasir'"
);
for (const peran of ["'owner'", "'kasir'"]) {
  assert.equal(m47.indexOf('role, is_active)\n    VALUES (v_uid, v_cap.name, ' + peran), -1,
    'fungsi ini tidak boleh dapat membuat akun ber-peran ' + peran);
}

// ── 2 · Hanya owner, dan tertutup untuk anon ───────────────────────────────
assert.match(m47, /IF NOT is_owner\(\) THEN/, 'harus dijaga is_owner()');
assert.match(m47, /REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster\(UUID, TEXT, TEXT\) FROM PUBLIC, anon;/);
assert.match(m47, /GRANT {2}EXECUTE ON FUNCTION owner_buat_akun_capster\(UUID, TEXT, TEXT\) TO authenticated;/);

// ── 3 · Sandi tidak pernah tersimpan polos ─────────────────────────────────
// Memakai panggilan yang sama dengan owner_set_capster_password sejak migrasi
// 12 — yang sudah terbukti jalan di basis data ini, bukan resep dari luar.
assert.match(m47, /extensions\.crypt\(p_password, extensions\.gen_salt\('bf'\)\)/,
  'sandi harus di-hash dengan panggilan yang sudah terbukti');
assert.equal(m47.indexOf('encrypted_password = p_password'), -1,
  'sandi polos tidak boleh masuk ke kolom apa pun');
assert.match(m47, /length\(p_password\) < 8/, 'sandi minimal 8 karakter');

// ── 4 · Baris identitas WAJIB ada ──────────────────────────────────────────
/* Tanpa baris di auth.identities, akunnya tercipta dan terlihat wajar di
   dasbor Supabase — tetapi setiap upaya masuk ditolak tanpa sebab yang
   terbaca. Kegagalan paling mahal dari fungsi ini justru yang paling senyap. */
assert.match(m47, /INSERT INTO auth\.identities/, 'akun tanpa identitas tidak akan pernah bisa masuk');
assert.match(m47, /'email', v_uid::TEXT/, "provider 'email' dan provider_id harus terisi");
assert.match(m47, /jsonb_build_object\('sub', v_uid::TEXT, 'email', v_mail\)/,
  'identity_data harus memuat sub dan email');

// Tanpa email_confirmed_at, akun menunggu konfirmasi yang tidak akan pernah
// datang: alamat seperti amirul@underrated.com bukan kotak surat sungguhan.
assert.match(m47, /email_confirmed_at/, 'akun harus langsung terkonfirmasi');

// ── 5 · Menolak, bukan menimpa ─────────────────────────────────────────────
assert.match(m47, /IF v_cap\.auth_user_id IS NOT NULL THEN[\s\S]{0,120}RAISE EXCEPTION/,
  'kapster yang sudah punya akun harus ditolak, bukan dibuatkan akun kedua');
assert.match(m47, /EXISTS \(SELECT 1 FROM auth\.users u WHERE lower\(u\.email\) = v_mail\)[\s\S]{0,120}RAISE EXCEPTION/,
  'email yang sudah dipakai harus ditolak');
assert.match(m47, /RAISE EXCEPTION 'Kapster tidak ditemukan\.'/);

// ── 6 · Layar owner ────────────────────────────────────────────────────────
// Dicari di dalam teks yang benar-benar dirender — string berkutip tunggal
// yang disambung menjadi HTML — bukan di seluruh berkas. Komentar penjelas di
// rekap.html mengutip pesan lama itu untuk menerangkan apa yang berubah, dan
// larangan yang membaca seluruh berkas akan ikut menghapus penjelasannya.
const tanpaKomentar = rekap
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^[ \t]*\/\/.*$/gm, '');
assert.equal(tanpaKomentar.indexOf('buatkan dulu lewat Dardev'), -1,
  'pesan yang menyuruh menunggu pengembang tidak boleh tersisa di layar');
assert.match(rekap, /sb\.rpc\('owner_buat_akun_capster'/, 'tombolnya harus memanggil RPC-nya');
assert.match(rekap, /data-akun-email=|data-akun-sandi=|data-akun-buat=/);

// Form pembuatan hanya muncul bila belum punya akun; yang sudah punya tetap
// mendapat penggantian sandi, bukan kehilangan keduanya.
const kartu = rekap.slice(rekap.indexOf('const bisa = c.punya_akun'), rekap.indexOf("}).join('') ||"));
assert.ok(kartu.length > 0, 'blok kartu kapster harus dapat dipotong');
assert.match(kartu, /bisa\s*\?[\s\S]*data-sandi-simpan[\s\S]*:[\s\S]*data-akun-buat/,
  'punya akun -> ganti sandi; belum -> buat akun');

// Dikonfirmasi sekali sebelum dibuat: akun tidak dapat dibatalkan dari layar ini.
const penangan = rekap.slice(rekap.indexOf('if (bAkun) {'), rekap.indexOf('if (bAkun) {') + 2600);
assert.match(penangan, /confirm\(/, 'pembuatan akun harus dikonfirmasi');
assert.match(penangan, /sandi\.length < 8/, 'sandi pendek ditolak sebelum menunggu jaringan');

// Tiap fungsi yang dipanggil penangan ini harus benar-benar ada. Versi
// pertamanya memanggil muatKelola(), yang tidak pernah ada di berkas ini:
// akunnya berhasil dibuat di server, lalu layarnya melempar ReferenceError
// dan kartunya tidak pernah menyegar. Owner melihat galat sesudah pekerjaan
// yang sebenarnya berhasil, dan tidak punya cara tahu mana yang terjadi.
//
// Diperiksa untuk seluruh berkas, bukan hanya penangan ini: kekeliruan yang
// sama pada penangan lain gagal dengan cara yang sama persis.
const dideklarasikan = new Set(
  [...rekap.matchAll(/(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map((m) => m[1])
);
for (const [, dipanggil] of rekap.matchAll(/await\s+(muat[A-Za-z]*)\s*\(/g)) {
  assert.ok(
    dideklarasikan.has(dipanggil),
    `${dipanggil}() dipanggil tetapi tidak pernah dideklarasikan di rekap.html`
  );
}

// ── 7 · Saran email ────────────────────────────────────────────────────────
const a = rekap.indexOf('function saranEmail(nama)');
const b = rekap.indexOf('}', rekap.indexOf('return (bersih', a)) + 1;
const saranEmail = new Function(rekap.slice(a, b) + '; return saranEmail;')();

assert.equal(saranEmail('Amirul'), 'amirul@underrated.com');
assert.equal(saranEmail('A Bayu'), 'abayu@underrated.com', 'spasi dibuang');
assert.equal(saranEmail('Réza Ñoël'), 'rezanoel@underrated.com', 'huruf beraksen diluruskan');
assert.equal(saranEmail('Mas Opik-2'), 'masopik2@underrated.com', 'tanda baca dibuang, angka tetap');
// Nama kosong tidak boleh menghasilkan "@underrated.com" yang ditolak server.
assert.equal(saranEmail('   '), 'kapster@underrated.com');
assert.equal(saranEmail(null), 'kapster@underrated.com');

console.log('Buat akun kapster tests: OK');
