const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');

/* Ayah dan anak mencukur lalu membayar sekali adalah kejadian sehari-hari,
   tetapi POS menolaknya: memilih layanan bersifat menyalakan-mematikan,
   sehingga klik kedua pada Haircut justru menghapus yang pertama. Satu nota
   tidak pernah bisa memuat dua potong rambut. */

const blok = pos.slice(pos.indexOf('function tambahLayanan(service)'),
                       pos.indexOf('let currentFilterCat'));
assert.ok(blok.length > 0, 'blok penambah layanan harus tersedia');

function keranjang() {
  return new Function(`
    let selectedServices = [];
    const currentFilterCat = 'ALL';
    const renderServices = () => {};
    const updateCartView = () => {};
    ${blok}
    return {
      tambah: tambahLayanan,
      hapus: hapusBarisLayanan,
      isi: () => selectedServices,
      /* Cerminan penangan di pos.html: baris dikunci INDEKS, bukan id. */
      setKapster: (idx, kapsterId) => {
        const item = selectedServices[Number(idx)];
        if (item) item.capsterId = kapsterId;
      }
    };
  `)();
}

const HAIRCUT  = { id: 'svc-hc', name: 'Haircut',  price: 85000, category: 'Haircut' };
const HAIRWASH = { id: 'svc-hw', name: 'Hairwash', price: 15000, category: 'Haircut' };

// ── 1 · Dua orang, layanan sama, satu nota ─────────────────────────────────
const k = keranjang();
k.tambah(HAIRCUT);   // ayah
k.tambah(HAIRCUT);   // anak
assert.equal(k.isi().length, 2, 'klik kedua harus MENAMBAH baris, bukan menghapus yang pertama');
assert.equal(k.isi().reduce((a, s) => a + s.price, 0), 170000, 'keduanya harus ikut ditagih');

// ── 2 · Tiap baris membawa kapsternya sendiri ──────────────────────────────
/* Inti alasan memilih baris terpisah alih-alih jumlah pada satu baris: ayah
   dicukur Cena, anaknya oleh Lukman. Satu baris berjumlah dua tidak punya
   tempat menyimpan dua nama. */
k.setKapster(0, 'cena');
k.setKapster(1, 'lukman');
assert.equal(k.isi()[0].capsterId, 'cena');
assert.equal(k.isi()[1].capsterId, 'lukman',
  'kapster baris kedua harus tersimpan sendiri');

// Versi lama mencari dengan find(x => x.id === id) dan SELALU menemukan baris
// pertama, sehingga mengubah kapster anak diam-diam mengubah kapster ayah.
assert.notEqual(k.isi()[0].capsterId, k.isi()[1].capsterId,
  'mengubah baris kedua tidak boleh ikut mengubah baris pertama');

// ── 3 · Menghapus mengenai baris ITU saja ──────────────────────────────────
const k2 = keranjang();
k2.tambah(HAIRCUT); k2.tambah(HAIRWASH); k2.tambah(HAIRCUT);
k2.setKapster(0, 'cena'); k2.setKapster(2, 'wanda');
k2.hapus(1);                               // buang Hairwash di tengah
assert.deepEqual(k2.isi().map(s => s.name), ['Haircut', 'Haircut'],
  'hanya baris yang ditunjuk yang hilang');
assert.deepEqual(k2.isi().map(s => s.capsterId), ['cena', 'wanda'],
  'kapster baris yang tersisa tidak boleh ikut bergeser');

// Indeks di luar jangkauan tidak boleh merusak apa pun.
const sebelum = k2.isi().length;
k2.hapus(99); k2.hapus(-1);
assert.equal(k2.isi().length, sebelum, 'indeks ngawur harus diabaikan diam-diam');

// ── 4 · Salinan, bukan rujukan ke katalog ──────────────────────────────────
// Menempelkan capsterId ke objek katalog membuat pilihan satu nota terbawa ke
// nota berikutnya.
const k3 = keranjang();
k3.tambah(HAIRCUT);
k3.setKapster(0, 'lukman');
assert.equal(HAIRCUT.capsterId, undefined, 'objek katalog tidak boleh ikut ternoda');

// ── 5 · Yang harus ada di sumbernya ────────────────────────────────────────
// Baris dikunci indeks. Dengan id, dua Haircut punya kunci yang sama.
assert.match(pos, /data-idx="\$\{i\}"/, 'baris keranjang harus dikunci indeks');
assert.equal(pos.indexOf('data-item='), -1, 'kunci lama berbasis id tidak boleh tersisa');
assert.match(pos, /selectedServices\[Number\(sel\.dataset\.idx\)\]/,
  'penangan kapster harus mengambil baris menurut indeks');
assert.equal(pos.indexOf('selectedServices.find(x => String(x.id)'), -1,
  'pencarian berbasis id akan selalu menemukan baris pertama');

// Klik pada katalog menambah, tidak lagi menyalakan-mematikan.
assert.equal(pos.indexOf('toggleServiceSelection'), -1, 'penyalaan-pematian lama harus hilang');
assert.match(pos, /card\.onclick = \(\) => \{\s*tambahLayanan\(s\);/);

// Membatalkan harus tetap mungkin: tombol pada barisnya.
assert.match(pos, /class="item-hapus" data-idx="\$\{i\}"/,
  'tiap baris harus punya tombol hapus sendiri');
assert.match(pos, /closest\('\.item-hapus'\)/, 'penangan hapus baris harus terpasang');

// Jumlah ditampilkan di kartu katalog, kalau tidak kasir tidak tahu ia sudah
// menekan sekali atau dua kali.
assert.match(pos, /\$\{jml > 1 \? jml : '✓'\}/, 'kartu harus menampilkan jumlah');

// ── 6 · Payload mengirim dua baris terpisah ────────────────────────────────
const kirim = pos.slice(pos.indexOf('p_items: selectedServices.map'), pos.indexOf('p_items: selectedServices.map') + 700);
assert.match(kirim, /capster_id: s\.capsterId \|\| selectedCapster\.id/,
  'tiap baris mengirim kapsternya sendiri');

console.log('Dua orang satu nota tests: OK');
