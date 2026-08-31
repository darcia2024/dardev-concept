const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const migrasi = fs.readFileSync(
  path.join(root, 'supabase_migration_33_ganti_capster.sql'),
  'utf8'
);

// Satu nota dapat dikerjakan lebih dari satu capster: potong sama Cena, cuci
// sama Lukman. POS menyediakan pemilihnya per item, dan dasbor capster sudah
// lama membaca per item. Laporan owner sempat tertinggal membaca per nota,
// sehingga yang mengerjakan sisanya mendapat nol di layar pemiliknya padahal
// pekerjaannya muncul di dasbornya sendiri.
const awal = rekap.indexOf('const daftarItem = ');
assert.notEqual(awal, -1, 'blok pengelompokan capster harus tersedia');
const akhir =
  rekap.indexOf('});', rekap.indexOf('capsterBreakdown[capName].heads += 1;')) + 3;
const blokPengelompokan = rekap.slice(awal, akhir);

function kelompokkan(txList) {
  const capsterBreakdown = {};
  txList.forEach(tx => {
    const amt = tx.final_amount || 0;
    // eslint-disable-next-line no-eval
    eval(blokPengelompokan);
  });
  return capsterBreakdown;
}

const hasil = kelompokkan([
  {
    capster_name: 'Cena', subtotal: 100000, final_amount: 100000,
    services: [
      { name: 'Haircut', price: 85000, capster_name: 'Cena' },
      { name: 'Hairwash', price: 15000, capster_name: 'Lukman' }
    ]
  },
  {
    // Dibayar Rp 64.000 sesudah potongan, tetapi dasar bagi hasilnya tetap
    // harga normal. R-05: seluruh potongan ditanggung pemilik.
    capster_name: 'Wanda', subtotal: 85000, final_amount: 64000,
    services: [{ name: 'Haircut', price: 85000, capster_name: 'Wanda' }]
  }
]);

assert.equal(hasil.Cena.omzet, 85000, 'Cena hanya dapat bagian yang dikerjakannya');
assert.equal(hasil.Lukman.omzet, 15000, 'Lukman harus dapat cuciannya, bukan nol');
assert.equal(hasil.Wanda.omzet, 85000, 'dasar bagi hasil adalah harga normal (R-05)');
assert.equal(hasil.Cena.heads, 1);
assert.equal(hasil.Lukman.heads, 1);

// Nota lama tanpa rincian item tidak boleh hilang dari laporan.
const tanpaItem = kelompokkan([
  { capster_name: 'Cena', subtotal: 50000, final_amount: 50000, services: [] }
]);
assert.equal(tanpaItem.Cena.omzet, 50000, 'nota tanpa rincian item tetap terhitung');

// capster_name wajib ikut terbawa dari kueri sampai ke pemetaan. Tanpa itu
// pengelompokan di atas jatuh diam-diam kembali ke capster level nota, dan
// hasilnya terlihat benar sampai ada nota yang benar-benar terbelah.
assert.match(rekap, /transaction_items\(service_name, price, capster_name\)/);
assert.match(rekap, /capster_name: i\.capster_name/);

// Memindahkan capster tidak boleh menyentuh poin member: poin milik member,
// bukan capster. Yang berpindah hanya atribusi omzet dan jumlah kepala.
const badanFungsi = migrasi.slice(
  migrasi.indexOf('CREATE OR REPLACE FUNCTION edit_transaction_capster'),
  migrasi.indexOf('REVOKE EXECUTE ON FUNCTION edit_transaction_capster')
);
for (const terlarang of ['points_balance', 'lifetime_points', 'point_ledger', 'compute_tier']) {
  assert.doesNotMatch(
    badanFungsi,
    new RegExp(terlarang),
    `edit_transaction_capster tidak boleh menyentuh ${terlarang}`
  );
}

// Kedua tabel harus ikut berubah. Mengubah satu saja membuat laporan owner dan
// dasbor capster menampilkan angka berbeda untuk orang yang sama.
// Batas kata dipakai dengan sengaja: tanpa itu, "UPDATE transaction_itemsX"
// yang salah ketik tetap lolos karena memuat nama tabelnya sebagai substring.
assert.match(badanFungsi, /UPDATE transaction_items\b/);
assert.match(badanFungsi, /UPDATE transactions\b/);

// Mengubah siapa yang dibayar adalah keputusan yang menyentuh uang orang.
assert.match(badanFungsi, /INSERT INTO capster_edits/);
assert.match(badanFungsi, /Alasan pemindahan wajib diisi/);
assert.match(badanFungsi, /IF NOT is_owner\(\)/);

// Jejaknya tidak boleh dicari ulang lewat penyaringan waktu: now() bernilai
// sama untuk seluruh baris dalam satu transaksi, sehingga penyaring seperti
// itu ikut menangkap baris milik transaksi lain yang berjalan bersamaan.
assert.doesNotMatch(badanFungsi, /diubah_pada >/);

console.log('Capster attribution tests: OK');
