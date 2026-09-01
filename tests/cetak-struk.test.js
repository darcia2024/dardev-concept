const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');

// Struk thermal 58mm hanya muat 32 karakter per baris pada font A. Baris yang
// lebih panjang dibungkus mesinnya sendiri dan keluar sebagai potongan yatim
// di bawahnya — terlihat seperti struk rusak, padahal isinya benar.
const sumber = pos.slice(
  pos.indexOf('const LEBAR_STRUK'),
  pos.indexOf('async function sambungPrinter')
);
assert.ok(sumber.length > 0, 'penyusun ESC/POS harus tersedia');

const escposStruk = new Function('formatWa', 'formatRupiah', sumber + '; return escposStruk;')(
  p => p,
  n => 'Rp ' + Number(n || 0).toLocaleString('id-ID')
);

function barisStruk(tx) {
  const b = escposStruk(tx);
  return Buffer.from(b).toString('latin1')
    .replace(/\x1B@/g, '').replace(/\x1Ba[\x00-\x02]/g, '').replace(/\x1DV\x00/g, '')
    .split('\n');
}

const panjangSekali = {
  invoice_no: 'INV-260901-010', created_at: '2026-09-01T01:19:00Z',
  member_name: 'Nama Pelanggan Yang Panjang Sekali Melebihi Kertas',
  member_phone: '6282125381501', member_tier: 'Platinum',
  capster_name: 'Wanda',
  services: [{ name: 'Design Perm Dengan Nama Layanan Panjang', price: 415000 }],
  final_amount: 415000, payment_method: 'Tunai',
  cash_paid: 500000, cash_change: 85000,
  discount_points: 0, discount_manual: 0,
  points_earned: 29050, points_balance: 31500
};

for (const tx of [panjangSekali, { ...panjangSekali, member_phone: '-', services: [] }]) {
  for (const l of barisStruk(tx)) {
    assert.ok(l.length <= 32,
      'baris melebihi 32 kolom dan akan terbungkus: ' + JSON.stringify(l));
  }
}

// Mesin thermal memakai tabel 8-bit, bukan UTF-8. Karakter di luar ASCII cetak
// keluar sebagai sampah, jadi harus sudah dibersihkan sebelum dikirim.
const kotor = {
  ...panjangSekali,
  member_name: 'Ibu Ayu \u2014 "Spesial" \u00b7 \u2b50',
  capster_name: 'Wanda\u2019s'
};
for (const l of barisStruk(kotor)) {
  for (const c of l) {
    assert.ok(c.charCodeAt(0) >= 0x20 && c.charCodeAt(0) <= 0x7E,
      'karakter di luar tabel cetak: ' + JSON.stringify(c) + ' pada ' + JSON.stringify(l));
  }
}

// Perintah wajib: inisialisasi di depan, dan kertas maju di belakang supaya
// struknya dapat disobek tanpa memotong barisnya sendiri.
const byte = Array.from(escposStruk(panjangSekali));
assert.deepEqual(byte.slice(0, 2), [0x1B, 0x40], 'harus dimulai dengan ESC @');
assert.ok(byte.slice(-6).filter(x => x === 10).length >= 3, 'harus ada kertas maju di akhir');

// BLE mengirim dalam potongan kecil. Mengirim sekaligus akan terpotong
// diam-diam di tengah dan struknya keluar separuh.
assert.match(pos, /const POTONG = \d+;/);
assert.match(pos, /writeValueWithoutResponse/);

// Tombolnya hanya muncul bila peramban mendukung; tombol yang pasti gagal
// lebih buruk daripada tidak ada tombol sama sekali.
assert.match(pos, /if \(!navigator\.bluetooth\) \{\s*\n\s*btnBt\.remove\(\);/);

// Karakteristiknya dicari, bukan ditebak: tiap merek memakai UUID sendiri.
assert.match(pos, /c\.properties\.write \|\| c\.properties\.writeWithoutResponse/);

console.log('Cetak struk tests: OK');
