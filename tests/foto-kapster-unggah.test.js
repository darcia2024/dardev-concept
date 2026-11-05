/* Owner mengunggah foto kapster dari Rekap (migrasi 60). */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir } = require('./_migrasi');

const root = path.resolve(__dirname, '..');
const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');

const m60 = baca('supabase_migration_60_foto_kapster.sql');
const rekap = baca('rekap.html');
const landing = baca('landing.html');
const pos = baca('pos.html');
const capster = baca('capster.html');

/* Bucket publik hanya untuk foto yang memang dipajang; selfie absensi tidak ikut. */
assert.match(m60, /'foto-kapster', 'foto-kapster', true/);
assert.doesNotMatch(m60, /'absensi'/, 'migrasi ini tidak boleh menyentuh bucket absensi');

/* Pengunjung boleh melihat, tidak boleh menulis atau mendaftar isi bucket. */
assert.match(m60, /FOR ALL TO authenticated[\s\S]*?USING \(bucket_id = 'foto-kapster' AND is_owner\(\)\)[\s\S]*?WITH CHECK \(bucket_id = 'foto-kapster' AND is_owner\(\)\)/);
assert.doesNotMatch(m60, /TO (anon|public)\s*\n?\s*(USING|WITH)/i);

const pasang = definisiTerakhir('owner_set_foto_karyawan');
assert.match(pasang.badan, /IF NOT is_owner\(\) THEN[\s\S]*?RAISE EXCEPTION/, 'fungsi definer harus menjaga owner sendiri');
assert.match(pasang.isi, /REVOKE EXECUTE ON FUNCTION owner_set_foto_karyawan\(UUID, TEXT\) FROM PUBLIC, anon/);
assert.match(pasang.badan, /\[0-9a-f\]\{32\}/, 'nama berkas harus divalidasi server');

/* Tiap pembaca di definisi terakhirnya harus membawa foto. */
for (const fn of ['owner_staff_list', 'me_capster', 'public_landing']) {
  const d = definisiTerakhir(fn);
  assert.match(d.badan, /foto_path/, fn + ' (' + d.dari + ') harus membawa foto_path');
}

/* public_landing tetap menyaring pencukur dan menjaga bentuk kunci kapster:
   ai-tanya membaca kapster sebagai daftar untai, dan nomor telepon tetap tertutup. */
const umum = definisiTerakhir('public_landing').badan;
assert.match(umum, /jsonb_agg\(c\.name ORDER BY c\.name\)/);
assert.equal((umum.match(/c\.is_active AND c\.ikut_pos/g) || []).length, 3,
  'kapster, kapster_id, dan kapster_foto semuanya harus menyaring pencukur aktif');
assert.doesNotMatch(umum, /c\.phone|auth_user_id/);

/* Panel: alurnya lewat RPC berpenjaga, dan berkas lama dibuang. */
assert.match(rekap, /data-foto-input=/);
assert.match(rekap, /rpc\('owner_set_foto_karyawan'/);
assert.match(rekap, /buangBerkasFoto\(baris && baris\.foto_lama\)/, 'foto lama harus dibuang sesudah diganti');
assert.match(rekap, /await buangBerkasFoto\(jalur\);\s*throw error;/, 'unggahan yang gagal dipasang tidak boleh tertinggal');
assert.match(rekap, /hasil\.type !== 'image\/webp'/, 'Safari diam-diam memberi PNG; harus jatuh ke JPEG, jenis yang diterima bucket');

/* Tiap layar mendahulukan unggahan, dan foto bawaan tetap jadi cadangan. */
assert.match(landing, /ISI\.kapster_foto/);
assert.match(landing, /fotoUnggahan\[nama\][\s\S]{0,120}gambarUnggahan[\s\S]{0,60}gambarKapster/);
assert.match(pos, /c\.foto_path\s*\n?\s*\? `<img/);
assert.match(capster, /if \(me\.foto_path\)[\s\S]{0,300}else if \(FOTO_KAPSTER\[capKey\]\)/);
assert.match(rekap, /if \(unggahan\) \{/);

/* Empat kapster di ponsel: 2x2, bukan 3+1. */
assert.match(landing, /\.kapster\.kapster-dua \{ grid-template-columns: repeat\(2, 1fr\); \}/);
assert.match(landing, /classList\.toggle\('kapster-dua'/);

console.log('foto-kapster-unggah: semua pemeriksaan lolos');
