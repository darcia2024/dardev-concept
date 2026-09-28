/* Jam kerja per karyawan (migrasi 50).
 *
 * Karyawan non-kapster bekerja 09.00 - 17.00, bukan mengikuti jam buka toko.
 * Kegagalannya tidak pernah berupa galat — hanya laporan absensi yang
 * menyatakan disiplin yang tidak pernah terjadi, atau menuduh keterlambatan
 * yang tidak pernah terjadi. Tiga janji yang dijaga:
 *
 *   1. clock_in menilai keterlambatan dari jam orangnya sendiri.
 *   2. Kapster yang tidak diberi jam tetap mengikuti jadwal toko, persis
 *      seperti sebelumnya — termasuk Jumat yang buka 13.00.
 *   3. Jam masuk dan jam pulang selalu diisi berpasangan.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir, root } = require('./_migrasi');

const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

/* ── 1 · clock_in memakai satu sumber jam masuk ──────────────────────────
   Yang diperiksa definisi TERAKHIR clock_in, di migrasi mana pun ia berada.
   Membaca jam_hari_ini() langsung berarti karyawan 09.00 diukur dari jam
   buka toko: datang 10.10 tercatat tepat waktu, dan setiap Jumat ia boleh
   datang tengah hari tanpa pernah terlambat. */
const clockIn = definisiTerakhir('clock_in');
assert.match(
  clockIn.badan, /v_masuk := jam_masuk_karyawan\(v_cap\.id, v_date\);/,
  `clock_in (${clockIn.dari}) harus mengambil jam masuk milik karyawannya sendiri`
);
assert.doesNotMatch(
  clockIn.badan, /FROM jam_hari_ini\(/,
  'clock_in tidak boleh membaca jadwal toko langsung — itu mengabaikan jam karyawan'
);
// Penilaiannya sendiri tidak berubah: toleransi yang sama untuk semua.
assert.match(clockIn.badan, /v_wib > \(v_masuk \+ make_interval\(mins => v_rule\.toleransi_menit\)\)/);

/* ── 2 · Urutan cadangannya: orang, lalu toko, lalu aturan umum ───────────
   Bila urutan ini terbalik — jadwal toko lebih dulu — jam milik karyawan
   tidak akan pernah dipakai, sebab jadwal toko selalu terisi. Tidak ada
   yang gagal; hanya jam yang diisi owner diam-diam diabaikan. */
const jmk = definisiTerakhir('jam_masuk_karyawan').badan;
const iOrang = jmk.indexOf('c.jam_masuk FROM capsters');
const iToko  = jmk.indexOf('FROM jam_hari_ini(');
const iUmum  = jmk.indexOf('FROM work_rules');
assert.ok(iOrang > 0 && iToko > 0 && iUmum > 0, 'ketiga sumber jam masuk harus ada');
assert.ok(iOrang < iToko && iToko < iUmum,
  'jam milik karyawan harus diutamakan, lalu jadwal toko, lalu work_rules');
assert.match(jmk, /COALESCE\(/, 'sumber berikutnya hanya dipakai bila yang sebelumnya kosong');

/* ── 3 · Berpasangan ─────────────────────────────────────────────────────
   Jam masuk tanpa jam pulang menghasilkan karyawan yang separuh ikut toko
   dan separuh tidak. Dijaga di tiga lapis: tabel, fungsi, dan layar. */
const m50 = fs.readFileSync(path.join(root, 'supabase_migration_50_jam_kerja_karyawan.sql'), 'utf8');
assert.match(
  m50,
  /\(jam_masuk IS NULL AND jam_pulang IS NULL\)\s*OR \(jam_masuk IS NOT NULL AND jam_pulang IS NOT NULL AND jam_pulang > jam_masuk\)/,
  'constraint tabel harus menuntut keduanya diisi atau keduanya kosong'
);

const upsert = definisiTerakhir('owner_upsert_karyawan');
assert.match(upsert.badan, /\(p_jam_masuk IS NULL\) <> \(p_jam_pulang IS NULL\)/,
  'fungsi harus menolak jam yang diisi sebelah');
assert.match(upsert.badan, /p_jam_pulang <= p_jam_masuk/, 'jam pulang harus setelah jam masuk');
assert.match(upsert.badan, /p_jam_masuk\s+TIME DEFAULT NULL/, 'parameter jam harus berbawaan NULL');

/* Versi enam parameter harus dibuang. Dua versi berdampingan membuat
   PostgREST tidak dapat memilih, dan SETIAP simpan karyawan gagal. */
assert.match(
  upsert.isi,
  /DROP FUNCTION IF EXISTS owner_upsert_karyawan\(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN\);/,
  'tanda tangan lama owner_upsert_karyawan harus dibuang sebelum yang baru dibuat'
);

/* Daftar staf membawa jamnya, supaya formulir Ubah dapat mengisinya.
   Tanpa itu, membuka Ubah lalu menekan Simpan akan menghapus jam kerja
   orang itu diam-diam — kolomnya kosong, dan kosong berarti "ikut toko". */
assert.match(definisiTerakhir('owner_staff_list').badan, /jam_masuk TIME, jam_pulang TIME/,
  'owner_staff_list harus mengembalikan jam kerja');

/* ── 4 · Layar ───────────────────────────────────────────────────────────── */
assert.match(rekap, /id="inpKarJamMasuk"/);
assert.match(rekap, /id="inpKarJamPulang"/);
assert.match(rekap, /p_jam_masuk:\s+jamMasuk\s+\|\| null/, 'jam masuk harus dikirim saat simpan');
assert.match(rekap, /p_jam_pulang: jamPulang \|\| null/, 'jam pulang harus dikirim saat simpan');

/* TIME dari Postgres datang sebagai HH:MM:SS; <input type=time> menerima
   HH:MM. Tanpa dipotong, sebagian peramban menampilkan kolomnya kosong —
   dan simpan berikutnya menghapus jam kerja orang itu. */
assert.match(rekap, /String\(kar\.jam_masuk\)\.slice\(0, 5\)/, 'jam masuk harus dipotong ke HH:MM saat mengisi formulir');
assert.match(rekap, /String\(kar\.jam_pulang\)\.slice\(0, 5\)/, 'jam pulang harus dipotong ke HH:MM saat mengisi formulir');

assert.match(rekap, /if \(!!jamMasuk !== !!jamPulang\)/, 'layar harus menolak jam yang diisi sebelah sebelum mengirim');

/* ── 5 · Yang ditulis di layar absen = yang dipakai menilai (migrasi 52) ──
   Migrasi 50 mengubah PENILAIAN, tetapi layar absen tetap menulis jam dari
   work_rules — satu angka umum. Habibah (09.00-17.00) membaca 10:00-21:00,
   dan setiap Jumat kapster membaca 10:00 padahal dinilai dari 13.00. Tidak
   ada yang gagal; layarnya hanya berbohong kepada orang yang membacanya. */
const jks = definisiTerakhir('jam_kerja_saya').badan;
assert.match(jks, /jam_masuk_karyawan\(c\.id, jakarta_today\(\)\)/,
  'jam masuk di layar harus datang dari fungsi yang sama dengan penilaian clock_in');
assert.match(jks, /jam_pulang_karyawan\(c\.id, jakarta_today\(\)\)/);
assert.match(jks, /WHERE c\.auth_user_id = auth\.uid\(\)/, 'hanya jam milik pemanggil sendiri');
assert.match(jks, /FUNCTION jam_kerja_saya\(\)\s*\n/,
  'jam_kerja_saya tidak boleh menerima id — karyawan tidak perlu menanyakan jam rekannya');

const jpk = definisiTerakhir('jam_pulang_karyawan').badan;
const pOrang = jpk.indexOf('c.jam_pulang FROM capsters');
const pToko  = jpk.indexOf('jh.tutup FROM jam_hari_ini(');
const pUmum  = jpk.indexOf('wr.jam_pulang FROM work_rules');
assert.ok(pOrang > 0 && pOrang < pToko && pToko < pUmum,
  'jam pulang: milik karyawan, lalu jadwal toko, lalu work_rules — urutan yang sama dengan jam masuk');

const kapster = fs.readFileSync(path.join(root, 'capster.html'), 'utf8');
assert.match(kapster, /sb\.rpc\('jam_kerja_saya'\)/, 'layar absen harus menanyakan jam milik orangnya');
assert.match(kapster, /const jamTampil = jamKerjaSaya \|\| aturanKerja;/,
  'jam milik orangnya diutamakan; work_rules hanya cadangan bila migrasi 52 belum jalan');
assert.doesNotMatch(kapster, /\$\('jamKerja'\)\.textContent = String\(aturanKerja\./,
  'label jam tidak boleh lagi ditulis langsung dari work_rules');

console.log('jam-kerja-karyawan: semua pemeriksaan lolos');
