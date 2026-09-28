const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const m49 = fs.readFileSync(path.join(root, 'supabase_migration_49_perbaiki_token_akun.sql'), 'utf8');

/* GoTrue membaca kolom token auth.users sebagai string yang tidak boleh NULL.
   Akun yang dibuat dengan kolom itu NULL tidak pernah bisa masuk: layar /masuk
   hanya berbunyi "Database error querying schema". */

assert.equal((m49.match(/\$function\$/g) || []).length % 2, 0, 'penanda $function$ harus genap');

// ── 1 · Akun lama diluruskan ───────────────────────────────────────────────
for (const kolom of ['confirmation_token', 'recovery_token', 'email_change_token_new', 'email_change']) {
  assert.ok(m49.includes(`'${kolom}'`), `${kolom} harus ikut diluruskan dari NULL ke ''`);
}
assert.match(m49, /information_schema\.columns/, 'hanya kolom yang ada yang boleh di-UPDATE');
assert.match(m49, /WHERE %I IS NULL/, 'hanya nilai NULL yang disentuh');

// ── 2 · Fungsi baru mengisi token dengan '' ────────────────────────────────
const ins = m49.slice(m49.indexOf('INSERT INTO auth.users ('), m49.indexOf('INSERT INTO auth.identities'));
assert.ok(ins.length > 0, 'INSERT auth.users harus ada');
const [kolomBag, nilaiBag] = ins.split(') VALUES (');
const kolom = kolomBag.replace('INSERT INTO auth.users (', '').split(',').map((s) => s.trim());
// Dipecah pada koma di luar tanda kutip dan kurung: nilai raw_app_meta_data
// adalah literal JSON yang memuat koma sendiri.
function pecah(teks) {
  const hasil = [];
  let kini = '', dalam = 0, kutip = false;
  for (const ch of teks) {
    if (ch === "'") kutip = !kutip;
    else if (!kutip && ch === '(') dalam++;
    else if (!kutip && ch === ')') dalam--;
    if (!kutip && dalam === 0 && ch === ',') { hasil.push(kini.trim()); kini = ''; continue; }
    kini += ch;
  }
  hasil.push(kini.trim());
  return hasil;
}
const nilai = pecah(nilaiBag.replace(/\s*--.*$/gm, '').replace(/\);[\s\S]*$/, ''));
assert.equal(kolom.length, nilai.length, 'jumlah kolom dan nilai INSERT harus sama');
for (const k of ['confirmation_token', 'recovery_token', 'email_change_token_new', 'email_change']) {
  const i = kolom.indexOf(k);
  assert.ok(i >= 0, `${k} harus disebut di INSERT auth.users`);
  assert.equal(nilai[i], "''", `${k} harus diisi string kosong, bukan NULL`);
}

// Penjagaan dari migrasi 47 tidak boleh hilang saat fungsi ditulis ulang.
assert.match(m49, /IF NOT is_owner\(\) THEN/);
assert.match(m49, /VALUES \(v_uid, v_cap\.name, 'capster', TRUE\)/);
assert.match(m49, /extensions\.crypt\(p_password, extensions\.gen_salt\('bf'\)\)/);
assert.match(m49, /INSERT INTO auth\.identities/);
assert.match(m49, /REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster\(UUID, TEXT, TEXT\) FROM PUBLIC, anon;/);
assert.match(m49, /GRANT {2}EXECUTE ON FUNCTION owner_buat_akun_capster\(UUID, TEXT, TEXT\) TO authenticated;/);

console.log('Token akun tests: OK');
