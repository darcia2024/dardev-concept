/* Berkas mana yang benar-benar terunggah ke Vercel.
 *
 * Proyek ini statis: setiap berkas yang ikut terunggah dilayani apa adanya di
 * alamatnya sendiri. Tidak ada rute yang perlu dibuat, dan tidak ada layar yang
 * memberitahu bahwa sesuatu terbuka — .vercelignore satu-satunya yang memutuskan.
 *
 * Dua arah kesalahan, dan keduanya senyap:
 *
 *   1. Sesuatu yang mestinya tertutup ikut terunggah. Migrasi SQL membuka
 *      seluruh skema dan tiap kebijakan RLS; halaman penawaran lama
 *      menjanjikan manfaat yang tidak pernah dibangun.
 *   2. Sesuatu yang dibutuhkan situs ikut tertutup. Satu pola yang terlalu
 *      lebar — `*.js` misalnya — mematikan seluruh aplikasi, dan tidak ada
 *      tes lain di repo ini yang akan menangkapnya.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pola = fs.readFileSync(path.join(root, '.vercelignore'), 'utf8')
  .split('\n')
  .map((b) => b.trim())
  .filter((b) => b && !b.startsWith('#'));

/* Penyamaan ala .gitignore, dibatasi pada bentuk yang benar-benar dipakai
   berkas ini: nama persis, awalan direktori `dir/`, dan glob `*.ext`.
   Bentuk lain sengaja dianggap tidak cocok daripada ditebak-tebak — tes yang
   menebak akan menjawab "aman" untuk pola yang tidak ia pahami. */
function tertutup(berkas) {
  return pola.some((p) => {
    if (p.endsWith('/')) return berkas.startsWith(p);
    if (p.startsWith('*.')) return berkas.endsWith(p.slice(1));
    return berkas === p || berkas.startsWith(p + '/');
  });
}

/* ── 1 · Yang wajib tertutup ─────────────────────────────────────────────── */
const WAJIB_TERTUTUP = [
  'supabase_schema.sql',
  'supabase_migration_02_akses.sql',
  'supabase_migration_48_karyawan.sql',
  'koreksi_data_01b_terapkan_poin.sql',
  'tests/berkas-publik.test.js',
  'tests/akun-karyawan.test.js',
  'supabase/functions/ai-struk/index.ts',
  'perencanaan.html',
  'SERAH-TERIMA.md',
  'README.md',
  'TUTORIAL-DISKON-KASIR.md',
  '.pos_hooks.txt',
];
for (const f of WAJIB_TERTUTUP) {
  assert.ok(tertutup(f), `${f} harus dikecualikan dari unggahan Vercel`);
}

/* ── 2 · Yang wajib TETAP terunggah ──────────────────────────────────────
   Ini separuh yang lebih mudah dilanggar. Menutup sesuatu terasa aman, dan
   kesalahannya baru terlihat setelah situsnya mati di produksi. */
const WAJIB_TERBUKA = [
  'landing.html', 'kartu.html', 'pos.html', 'rekap.html',
  'capster.html', 'masuk.html', 'finalpenawaran.html',
  'sb-app.js', 'sw.js', 'theme.css', 'manifest.json', 'vercel.json',
  'assets/logo.png',
  'vendor/supabase.js',
];
for (const f of WAJIB_TERBUKA) {
  assert.ok(!tertutup(f), `${f} dibutuhkan situs tetapi ikut dikecualikan`);
}

/* ── 3 · Yang dikecualikan memang ada ────────────────────────────────────
   Pola yang menunjuk berkas yang sudah tidak ada bukan kesalahan, tetapi ia
   menumpuk dan membuat berkas ini lambat laun tidak lagi menggambarkan apa
   pun. Hanya diperiksa untuk pola bernama berkas, bukan glob. */
for (const p of pola) {
  if (p.startsWith('*') || p.endsWith('/')) continue;
  assert.ok(
    fs.existsSync(path.join(root, p)),
    `.vercelignore menunjuk ${p} yang sudah tidak ada`
  );
}

/* ── 4 · Tidak ada .sql atau .md yang lolos ──────────────────────────────
   Diperiksa terhadap isi direktori yang sebenarnya, bukan terhadap daftar
   yang ditulis tangan di atas: migrasi dan dokumen berikutnya akan bernama
   apa pun, dan daftar tangan tidak akan ikut bertambah sendiri. Justru
   berkas yang ditambahkan setelah ini yang paling mungkin terlewat. */
for (const f of fs.readdirSync(root)) {
  if (f.endsWith('.sql') || f.endsWith('.md')) {
    assert.ok(tertutup(f), `${f} ikut terunggah — seluruh .sql dan .md harus tertutup`);
  }
}

console.log('berkas-publik: semua pemeriksaan lolos');
