/* Karyawan non-cukur ikut absen (migrasi 48).
 *
 * Tabel `capsters` sekarang memuat seluruh karyawan outlet, bukan hanya
 * tukang cukur. Itu membuat absen, cuti, dan arsip penghapusan bekerja untuk
 * peran baru tanpa satu kolom pun dipindah — tetapi juga membuka empat cara
 * gagal yang tidak akan terlihat sampai kerusakannya sudah terjadi:
 *
 *   1. Karyawan non-cukur bocor ke daftar pencukur yang dilihat pelanggan.
 *   2. Perangkat kasir yang masih memegang salinan luring lama kehilangan
 *      seluruh daftar kapsternya, sehingga nota tidak bisa ditutup.
 *   3. Menghapus karyawan ikut menghapus riwayat absennya diam-diam, sebab
 *      attendances dan leave_requests keduanya ON DELETE CASCADE.
 *   4. Layar absen menyapa tukang bersih-bersih sebagai "Kapster".
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { definisiTerakhir } = require('./_migrasi');

const root = path.resolve(__dirname, '..');
const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');

const m48     = baca('supabase_migration_48_karyawan.sql');
const pos     = baca('pos.html');
const rekap   = baca('rekap.html');
const kapster = baca('capster.html');

/* ── 1 · Kolomnya benar-benar terpasang, dan baris lama tidak berubah ─────
   DEFAULT saja tidak cukup untuk tabel yang sudah terisi: kolom baru pada
   baris lama tetap NULL sampai ada yang mengisinya. Kalau backfill-nya
   terlewat, seluruh kapster yang sudah ada jadi ikut_pos NULL — dan setiap
   saringan `ikut_pos` di bawah akan membuang mereka semua. */
for (const kolom of ['jabatan', 'ikut_pos']) {
  assert.match(
    m48,
    new RegExp(`ADD COLUMN IF NOT EXISTS\\s+${kolom}\\b`),
    `kolom ${kolom} harus ditambahkan`
  );
  assert.match(
    m48,
    new RegExp(`UPDATE capsters SET\\s+${kolom}\\s*=[^;]*WHERE\\s+${kolom}\\s+IS NULL`),
    `${kolom} harus diisi untuk baris yang sudah ada, bukan hanya diberi DEFAULT`
  );
  assert.match(
    m48,
    new RegExp(`ALTER COLUMN\\s+${kolom}\\s+SET NOT NULL`),
    `${kolom} harus NOT NULL supaya tidak ada baris tanpa jawaban`
  );
}

/* Urutannya penting: NOT NULL sebelum backfill akan menolak migrasinya. */
assert.ok(
  m48.indexOf('UPDATE capsters SET  jabatan') < m48.indexOf('ALTER COLUMN jabatan  SET NOT NULL'),
  'backfill harus berjalan sebelum kolomnya dijadikan NOT NULL'
);

/* ── 2 · Yang bukan pencukur tidak ditawarkan sebagai pencukur ────────────
   Dua fungsi ini yang dibaca pelanggan: daftar kapster di kartu member dan
   daftar kapster di halaman booking. Tanpa saringan, tukang bersih-bersih
   muncul sebagai orang yang bisa dipilih untuk mencukur. */
for (const fn of ['member_capsters', 'public_landing']) {
  const mulai = m48.indexOf(`FUNCTION ${fn}`);
  assert.notEqual(mulai, -1, `${fn} harus ditulis ulang di migrasi 48`);
  const badan = m48.slice(mulai, m48.indexOf('$function$;', mulai));
  assert.match(
    badan, /c\.is_active AND c\.ikut_pos/,
    `${fn} harus menyaring ikut_pos, bukan hanya is_active`
  );
}

/* ── 3 · Penghapusan tidak boleh diam-diam membuang riwayat absen ─────────
   attendances.capster_id dan leave_requests.capster_id keduanya ON DELETE
   CASCADE. Tanpa penjaga ini, satu klik menghapus seluruh absen seseorang
   dan arsip deleted_attendances pun tidak ikut terisi. */
const hapus = m48.slice(
  m48.indexOf('FUNCTION owner_hapus_karyawan'),
  m48.indexOf('GRANT  EXECUTE ON FUNCTION owner_hapus_karyawan')
);
assert.ok(hapus.length > 0, 'owner_hapus_karyawan harus tersedia');
assert.match(hapus, /FROM attendances/,    'harus menghitung absen sebelum menghapus');
assert.match(hapus, /FROM leave_requests/, 'harus menghitung cuti sebelum menghapus');
assert.match(
  hapus, /v_absen > 0 OR v_cuti > 0[\s\S]*?RAISE EXCEPTION/,
  'harus menolak menghapus karyawan yang sudah punya riwayat'
);

/* Keduanya owner-only. Policy owner_all menjaga tabelnya, tetapi fungsi
   SECURITY DEFINER berjalan sebagai pemiliknya dan melewati policy itu —
   penjaganya harus ditulis di dalam fungsinya sendiri. */
for (const fn of ['owner_upsert_karyawan', 'owner_hapus_karyawan']) {
  // Definisi TERAKHIR, bukan migrasi 48: owner_upsert_karyawan ditulis ulang
  // di migrasi 50, dan menjaga salinan lamanya berarti hijau untuk kode mati.
  const { isi, badan, dari } = definisiTerakhir(fn);
  assert.match(badan, /IF NOT is_owner\(\) THEN[\s\S]*?RAISE EXCEPTION/,
    `${fn} (${dari}) harus menolak pemanggil yang bukan owner`);
  assert.match(isi, new RegExp(`REVOKE EXECUTE ON FUNCTION ${fn}\\([^)]*\\) FROM PUBLIC, anon`),
    `${fn} (${dari}) harus dicabut dari anon — Supabase memberikannya otomatis`);
}

/* Nomor telepon tetap lewat satu penormal yang sama. Menyimpan '0812...'
   apa adanya membuat notifikasi WhatsApp gagal tanpa pesan galat. */
assert.match(
  definisiTerakhir('owner_upsert_karyawan').badan,
  /normalkan_nomor_wa\(p_telepon\)/,
  'nomor harus dinormalkan server, bukan disimpan apa adanya'
);

/* ── 4 · Saringan kasir memakai satu sumber, dan ramah data luring ────────
   Perangkat kasir menyimpan salinan master data di localStorage. Salinan
   yang dibuat sebelum migrasi 48 belum punya kolom ikut_pos sama sekali.
   Menuntut `=== true` akan mengosongkan daftar kapster di perangkat itu dan
   kasir tidak bisa menutup nota — kegagalan yang muncul di jam sibuk, di
   perangkat yang justru paling jarang disegarkan. */
assert.match(
  pos, /function bolehMencukur\(c\)\s*\{[^}]*c\.ikut_pos !== false/,
  'bolehMencukur harus membaca ikut_pos dengan !== false, bukan === true'
);

const pemakaian = pos.match(/bolehMencukur/g) || [];
assert.ok(
  pemakaian.length >= 4,
  `bolehMencukur harus dipakai di semua penyaring kapster (ditemukan ${pemakaian.length})`
);

/* Tidak boleh ada penyaring kapster yang tertinggal menyaring sendiri. */
assert.doesNotMatch(
  pos, /capsters\.filter\(c => c\.is_active !== false\)/,
  'masih ada penyaring kapster yang belum memakai bolehMencukur'
);

/* Kedua layar menghapus lewat RPC yang sama. DELETE langsung ke tabel tetap
   diizinkan policy owner_all, jadi kalau salah satu layar memakainya lagi,
   penjaga riwayat di atas terlewati tanpa ada yang gagal. */
assert.doesNotMatch(
  pos, /from\('capsters'\)\.delete\(\)/,
  'penghapusan di kasir harus lewat owner_hapus_karyawan, bukan DELETE langsung'
);
assert.match(pos, /rpc\('owner_hapus_karyawan'/, 'kasir harus memanggil RPC penghapusan');

/* Peringatannya menyebut absen. Kalimat lama hanya menjanjikan transaksi
   tetap aman dan diam soal absen, yang justru bagian yang hilang. */
assert.match(
  pos, /Hapus karyawan[\s\S]{0,160}riwayat absen/,
  'peringatan hapus di kasir harus menyebut riwayat absen yang ikut terhapus'
);

/* ── 5 · Memindahkan nota tidak boleh menawarkan yang tidak mencukur ──────
   Nota yang pindah ke tukang bersih-bersih merusak laporan produktivitas,
   dan tidak ada layar yang akan memberitahu bahwa itu terjadi. */
assert.match(
  rekap, /sb\.from\('capsters'\)\.select\('id, name, is_active, ikut_pos'\)/,
  'daftar kapster dashboard harus ikut mengambil ikut_pos'
);
assert.match(
  rekap, /capstersData \|\| \[\]\)\.filter\(c => c\.is_active && c\.ikut_pos !== false\)/,
  'pemindahan nota harus menyaring ikut_pos'
);

/* ── 6 · Panelnya benar-benar ada, dan lewat RPC berpenjaga ───────────────
   Owner memang bisa menulis langsung ke capsters lewat policy owner_all.
   Kalau panel ini memakai jalan itu, normalisasi nomor dan penolakan nama
   kembar ikut hilang — dan keduanya baru ketahuan setelah datanya rusak. */
assert.match(rekap, /id="btnTambahKaryawan"/, 'tombol tambah karyawan harus ada');
assert.match(rekap, /rpc\('owner_upsert_karyawan'/, 'panel harus lewat RPC, bukan tulis langsung');
assert.match(rekap, /rpc\('owner_hapus_karyawan'/, 'penghapusan harus lewat RPC berpenjaga');
assert.match(
  rekap, /p_ikut_pos:\s*document\.getElementById\('chkKarIkutPos'\)\.checked/,
  'penanda ikut_pos harus benar-benar dikirim, bukan dibiarkan bawaan'
);

/* Peringatan hapus harus menyebut angka absennya. Kalimat umum seperti
   "yakin hapus?" tidak memberi tahu apa yang sebenarnya hilang. */
assert.match(
  rekap, /jml_absen/,
  'peringatan hapus harus memakai jumlah absen yang sebenarnya'
);
assert.match(
  definisiTerakhir('owner_staff_list').badan, /jml_absen BIGINT/,
  'owner_staff_list harus ikut membawa jumlah absen'
);

/* ── 7 · Layar absen menyebut jabatan dari data ───────────────────────────
   Menuliskannya tetap berarti menyapa tukang bersih-bersih sebagai Kapster
   setiap kali ia absen. */
assert.match(kapster, /id="jabatanLabel"/, 'label jabatan harus punya wadahnya sendiri');
assert.match(
  kapster, /me\.jabatan[\s\S]{0,80}jabatanLabel'\)\.textContent = me\.jabatan/,
  'label jabatan harus diisi dari me_capster(), bukan ditulis tetap'
);
assert.match(
  m48.slice(m48.indexOf('FUNCTION me_capster')), /c\.jabatan/,
  'me_capster harus mengembalikan jabatan'
);

console.log('karyawan-panel: semua pemeriksaan lolos');
