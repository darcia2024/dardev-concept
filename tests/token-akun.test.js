const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const m55 = fs.readFileSync(path.join(root, 'supabase_migration_55_token_akun_tidak_null.sql'), 'utf8');

/* GoTrue membaca kolom token auth.users sebagai string yang tidak boleh NULL.
   Akun yang dibuat dengan kolom itu NULL tidak pernah bisa masuk: layar /masuk
   hanya berbunyi "Database error querying schema". */

assert.equal((m55.match(/\$function\$/g) || []).length % 2, 0, 'penanda $function$ harus genap');

const KOLOM = ['confirmation_token', 'recovery_token', 'email_change_token_new', 'email_change'];

// ── 1 · Akun lama diluruskan ───────────────────────────────────────────────
const perbaikan = m55.slice(m55.indexOf('DO $perbaikan$'), m55.indexOf('END $perbaikan$'));
for (const k of KOLOM) assert.ok(perbaikan.includes(`'${k}'`), `${k} harus ikut diluruskan`);
assert.match(perbaikan, /information_schema\.columns/, 'hanya kolom yang ada yang boleh di-UPDATE');
assert.match(perbaikan, /WHERE %I IS NULL/, 'hanya nilai NULL yang disentuh');

// ── 2 · Trigger menjaga akun berikutnya ────────────────────────────────────
const fungsi = m55.slice(m55.indexOf('CREATE OR REPLACE FUNCTION auth_users_token_kosong'), m55.indexOf('DROP TRIGGER'));
for (const k of KOLOM) assert.ok(fungsi.includes(`'${k}'`), `trigger harus meluruskan ${k}`);
assert.match(m55, /BEFORE INSERT OR UPDATE ON auth\.users/, 'harus BEFORE, supaya NULL tidak pernah tersimpan');
assert.match(m55, /DROP TRIGGER IF EXISTS auth_users_token_kosong ON auth\.users;/, 'harus aman dijalankan ulang');
// Merujuk NEW.kolom langsung akan menggagalkan SETIAP pembuatan akun pada
// versi GoTrue yang tidak punya kolom itu — termasuk lewat GoTrue sendiri.
assert.equal(/NEW\.[a-z_]+/.test(fungsi), false, 'kolom tidak boleh dirujuk langsung lewat NEW.<kolom>');
assert.match(fungsi, /v_baris \? v_kolom/, 'kolom yang tidak ada harus dilewati');
// Nilai yang sudah diisi (token sungguhan dari GoTrue) tidak boleh ditimpa.
assert.match(fungsi, /jsonb_typeof\(v_baris -> v_kolom\) = 'null'/, 'hanya NULL yang diganti');

// ── 3 · Tidak menulis ulang fungsi pembuat akun ────────────────────────────
/* owner_buat_akun_capster pernah tertimpa versi lama karena berkas yang lebih
   tua dijalankan belakangan. Migrasi ini tidak boleh menjadi berkas lain yang
   dapat melakukan hal yang sama. */
assert.equal(m55.includes('FUNCTION owner_buat_akun_capster'), false,
  'migrasi ini tidak boleh mendefinisikan ulang owner_buat_akun_capster');
assert.equal(fs.existsSync(path.join(root, 'supabase_migration_49_perbaiki_token_akun.sql')), false,
  'berkas lama yang menimpa fungsi dengan versi 47 tidak boleh kembali');

console.log('Token akun tests: OK');
