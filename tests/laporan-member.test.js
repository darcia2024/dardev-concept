const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const mLaporan = fs.readFileSync(
  path.join(root, 'supabase_migration_37_laporan_member.sql'),
  'utf8'
);
const mOutlet = fs.readFileSync(
  path.join(root, 'supabase_migration_36_outlet_transaksi.sql'),
  'utf8'
);

// ── Asal cabang pada tiap transaksi ────────────────────────────────────────
// Selama tokonya satu, kolom ini tidak terasa. Begitu cabang kedua buka,
// seluruh riwayat lama menjadi tidak dapat dipisahkan lagi — dan tidak ada
// cara memperbaikinya secara surut.
assert.match(mOutlet, /ALTER TABLE transactions\s+ADD COLUMN IF NOT EXISTS outlet_id/);
assert.match(mOutlet, /outlet_aktif\(\)/);

// Outlet diputuskan, bukan ditebak. Memilih diam-diam yang pertama berarti
// pada hari cabang kedua dibuka, seluruh transaksinya tercatat atas nama
// cabang pertama tanpa ada yang menyadarinya sampai berbulan-bulan kemudian.
const sumberOutlet = mOutlet.slice(
  mOutlet.indexOf('CREATE OR REPLACE FUNCTION outlet_aktif'),
  mOutlet.indexOf('REVOKE EXECUTE ON FUNCTION outlet_aktif')
);
assert.match(sumberOutlet, /v_jumlah > 1/, 'harus menolak saat outlet lebih dari satu');
assert.match(sumberOutlet, /RAISE EXCEPTION/);
assert.doesNotMatch(
  sumberOutlet,
  /ORDER BY[\s\S]*LIMIT 1/,
  'tidak boleh memilih satu outlet secara diam-diam'
);
// create_transaction wajib mengisinya, kalau tidak kolomnya selamanya kosong
// untuk baris baru dan masalahnya cuma berpindah ke masa depan.
assert.match(mOutlet, /outlet_aktif\(\),\s*\n\s*auth\.uid\(\)/);

// ── A-05: batas maksimal ditampilkan di depan ──────────────────────────────
// Spesifikasi minta kasir melihat nilai maksimal yang boleh dipakai. Sebelum
// ini batas itu baru muncul sesudah kasir terlanjur mengetik terlalu banyak.
assert.match(pos, /function poinMaksimal\(\)/);
assert.match(pos, /id="lblPointMax"/);
assert.match(pos, /function perbaruiBatasPoin\(\)/);
// Batas bergantung pada subtotal, jadi ia harus ikut disegarkan tiap
// keranjang berubah; kalau tidak, kasir membaca batas yang sudah basi.
const sumberKeranjang = pos.slice(
  pos.indexOf('function updateCartView'),
  pos.indexOf('function updateCartView') + 400
);
assert.match(sumberKeranjang, /perbaruiBatasPoin/);

// Satu tempat menghitung batasnya, dipakai tombol maupun keterangan; kalau
// dihitung dua kali, angka yang ditampilkan dan angka yang diisi tombol
// "Maks" bisa berbeda tanpa ada yang menyadarinya.
const sumberMaks = pos.slice(
  pos.indexOf('function poinMaksimal'),
  pos.indexOf('function perbaruiBatasPoin')
);
const poinMaksimal = new Function(
  'memberAktif', 'loyalty', 'selectedServices',
  sumberMaks + '; return poinMaksimal();'
);
const L = { max_redeem_percent: 25, rupiah_per_point_redeem: 1 };
assert.equal(poinMaksimal({ points_balance: 5000 }, L, [{ price: 85000 }]), 5000,
  'dibatasi saldo bila saldo lebih kecil dari batas persen');
assert.equal(poinMaksimal({ points_balance: 99999 }, L, [{ price: 85000 }]), 21250,
  'dibatasi 25 persen dari subtotal bila saldo besar');
assert.equal(poinMaksimal({ points_balance: 99999 }, L, [{ price: 15000 }]), 3750);
assert.equal(poinMaksimal({ points_balance: 99999 }, L, []), 0,
  'keranjang kosong harus menghasilkan nol, bukan NaN');
assert.equal(Number.isInteger(poinMaksimal({ points_balance: 99999 }, L, [{ price: 85001 }])), true,
  'batas harus bilangan bulat: angkanya diisikan langsung ke kolom jumlah poin');

// ── L-04 / L-06 / L-07 ─────────────────────────────────────────────────────
for (const fn of ['owner_members_per_tier', 'owner_members_hampir_naik', 'owner_members_lama_hilang']) {
  assert.match(mLaporan, new RegExp('CREATE OR REPLACE FUNCTION ' + fn));
  assert.match(mLaporan, new RegExp('REVOKE EXECUTE ON FUNCTION ' + fn));
  assert.match(rekap, new RegExp("sb\\.rpc\\('" + fn + "'"), fn + ' harus dipakai layar owner');
}

// L-04 memakai tier_rules sebagai sisi kiri supaya level yang belum
// berpenghuni tetap muncul dengan angka nol. Level kosong justru keterangan
// penting: ia memberi tahu sampai mana tangganya benar-benar terpakai.
assert.match(mLaporan, /FROM tier_rules tr\s+LEFT JOIN members m/);

// L-07 menghitung dari transaksi terakhir, bukan dari tanggal bergabung:
// member yang mendaftar tahun lalu dan masih rutin datang bukan member yang
// hilang. Yang belum pernah bertransaksi jatuh ke tanggal bergabungnya, kalau
// tidak ia tidak akan pernah muncul justru karena tidak pernah datang.
assert.match(mLaporan, /MAX\(t\.business_date\)/);
assert.match(mLaporan, /COALESCE\(a\.terakhir,/);

// Ketiganya wajib berpagar peran di dalam fungsinya, bukan hanya lewat GRANT.
for (const potongan of mLaporan.split('CREATE OR REPLACE FUNCTION owner_members_').slice(1)) {
  assert.match(potongan, /is_owner\(\)/, 'tiap laporan member harus berpagar is_owner()');
}

console.log('Laporan member tests: OK');
