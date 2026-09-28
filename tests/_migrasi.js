/* Alat bersama untuk tes: menemukan definisi TERAKHIR sebuah fungsi SQL.
 *
 * Fungsi di repo ini sering ditulis ulang oleh migrasi yang lebih baru —
 * clock_in di migrasi 9, 18, lalu 50; owner_upsert_karyawan di 48 lalu 50.
 * Tes yang terpaku pada satu berkas migrasi akan tetap hijau sambil menjaga
 * kode yang sudah tidak berjalan di basis data. Itu bentuk kegagalan paling
 * menyesatkan: layarnya hijau, dan yang dijaga sudah mati.
 *
 * Maka tes menanyakan "migrasi mana yang terakhir mendefinisikan fungsi ini"
 * alih-alih menyebut nama berkasnya. Urutannya menurut nomor migrasi, sebab
 * begitulah pemilik menjalankannya.
 *
 * Nama berkas ini diawali garis bawah dan tidak berakhiran .test.js, jadi ia
 * tidak ikut dijalankan sebagai tes.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');

function berkasMigrasi() {
  return fs.readdirSync(root)
    .filter((f) => /^supabase_migration_\d+.*\.sql$/.test(f))
    .map((f) => ({ f, n: Number(f.match(/^supabase_migration_(\d+)/)[1]) }))
    .sort((a, b) => a.n - b.n || a.f.localeCompare(b.f));
}

/** { isi, dari, badan } — isi berkasnya, nama berkasnya, dan badan fungsinya
    saja (dari CREATE sampai GRANT/REVOKE pertama sesudahnya). */
function definisiTerakhir(nama) {
  const pola = new RegExp('CREATE OR REPLACE FUNCTION (public\\.)?' + nama + '\\s*\\(');
  let hasil = null;
  for (const { f } of berkasMigrasi()) {
    const isi = fs.readFileSync(path.join(root, f), 'utf8');
    const m = isi.match(pola);
    if (m) {
      const a = m.index;
      const ujung = isi.slice(a).search(/\n(REVOKE|GRANT)\s/);
      hasil = { isi, dari: f, badan: ujung < 0 ? isi.slice(a) : isi.slice(a, a + ujung) };
    }
  }
  assert.ok(hasil, nama + ' tidak didefinisikan di migrasi mana pun');
  return hasil;
}

module.exports = { definisiTerakhir, berkasMigrasi, root };
