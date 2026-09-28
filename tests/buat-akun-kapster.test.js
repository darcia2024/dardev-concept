const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const m47 = fs.readFileSync(path.join(root, 'supabase_migration_47_owner_buat_akun_capster.sql'), 'utf8');
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
assert.equal(rekap.indexOf('buatkan dulu lewat Dardev'), -1,
  'pesan yang menyuruh menunggu pengembang tidak boleh tersisa');
assert.match(rekap, /sb\.rpc\('owner_buat_akun_capster'/, 'tombolnya harus memanggil RPC-nya');
assert.match(rekap, /data-akun-email=|data-akun-sandi=|data-akun-buat=/);

// Form pembuatan hanya muncul bila belum punya akun; yang sudah punya tetap
// mendapat penggantian sandi, bukan kehilangan keduanya.
const kartu = rekap.slice(rekap.indexOf('const bisa = c.punya_akun'), rekap.indexOf("}).join('') ||"));
assert.ok(kartu.length > 0, 'blok kartu kapster harus dapat dipotong');
assert.match(kartu, /bisa\s*\?[\s\S]*data-sandi-simpan[\s\S]*:[\s\S]*data-akun-buat/,
  'punya akun -> ganti sandi; belum -> buat akun');

// Dikonfirmasi sekali sebelum dibuat: akun tidak dapat dibatalkan dari layar ini.
const penangan = rekap.slice(rekap.indexOf('if (bAkun) {'), rekap.indexOf('if (bAkun) {') + 1600);
assert.match(penangan, /confirm\(/, 'pembuatan akun harus dikonfirmasi');
assert.match(penangan, /sandi\.length < 8/, 'sandi pendek ditolak sebelum menunggu jaringan');

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
