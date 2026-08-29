# Serah Terima Sistem — Barber Membership & Loyalty

Dokumen operasional untuk owner dan pengembang penerus.
Disusun oleh **Dardev**. Menyertai *Addendum Ruang Lingkup Revisi 02*.

---

## 1. Alamat Sistem

| Halaman | Alamat | Untuk siapa |
| :--- | :--- | :--- |
| Pintu masuk | `/masuk` | semua peran |
| POS Kasir | `/pos` | kasir (PIN) |
| Dashboard Owner | `/rekap` | owner |
| Kinerja Capster | `/capster` | capster |
| Kartu Member | `/kartu?c=KODE` | pelanggan, tanpa login |

Basis: `https://dardev-concept.vercel.app`

---

## 2. Siapa Masuk Lewat Mana

Sistem memakai tiga cara masuk yang berbeda, dan perbedaannya disengaja.

| Peran | Cara masuk | Alasan |
| :--- | :--- | :--- |
| **Owner** | Email + kata sandi | Akses penuh; perlu kredensial sungguhan. |
| **Perangkat POS** | Email + kata sandi, **sekali saat setup** | Yang menjaga basis data adalah autentikasi perangkat, bukan PIN. |
| **Kasir** | **PIN pribadi** | Kasir tidak mengetik email/sandi tiap mulai kerja. PIN menentukan *siapa yang bertugas*, bukan membuka basis data. |
| **Capster** | Email + kata sandi | Dibuka dari ponsel pribadi, yang tidak boleh punya izin membuat transaksi. |
| **Pelanggan** | Tautan kartu berisi kode | Pelanggan tidak akan membuat akun. |

> **Mengapa PIN tidak dipakai sebagai kredensial basis data.**
> PIN 4 digit hanya 10.000 kemungkinan dan akan habis ditebak dalam hitungan
> detik bila menjadi satu-satunya penjaga. Karena itu **perangkat** yang
> diautentikasi sekali oleh owner, sementara **PIN** hanya menentukan kasir
> mana yang bertanggung jawab atas sebuah transaksi. PIN disimpan sebagai
> hash bcrypt, diverifikasi di server, dan dibatasi 5 percobaan per menit.

### Menyiapkan perangkat kasir baru

1. Buka `/pos` di perangkat itu.
2. Masuk dengan akun **perangkat POS** (bukan akun owner).
3. Selesai. Setelahnya kasir cukup memasukkan PIN masing-masing.
4. Ganti kasir bertugas: tekan nama kasir di kanan atas.

---

## 3. Yang Dilihat Tiap Peran

Pembatasan ini ditegakkan di basis data (Row Level Security), bukan hanya
disembunyikan di tampilan. Menyembunyikan tombol tidak menghalangi siapa pun
memanggil API secara langsung.

| Data | Kasir | Capster | Owner |
| :--- | :---: | :---: | :---: |
| Katalog layanan & produk | ✅ | — | ✅ |
| Membuat transaksi | ✅ | — | ✅ |
| Daftar pelanggan | — | — | ✅ |
| Laporan omzet | — | — | ✅ |
| Harga modal & margin produk | — | — | ✅ |
| Setoran kas & selisih | — | — | ✅ |
| Kinerja capster lain | — | — | ✅ |
| Kinerja dirinya sendiri | — | ✅ | ✅ |
| Absensi & cuti dirinya | — | ✅ | ✅ |
| Absensi & cuti semua orang | — | — | ✅ |

---

## 4. Operasi Harian

### Kasir

1. Buka `/pos`, masukkan PIN.
2. Pilih capster → pilih layanan (tab **Produk** untuk barang retail).
3. Isi nomor WhatsApp pelanggan. Bila sudah member, poinnya muncul otomatis.
4. Bila menukar poin: isi jumlah poin, atau tekan **Maks**.
5. Bila pelanggan menunjukkan kode klaim reward: masukkan di kolom
   **Kode Klaim Reward** dan tekan **Periksa** sebelum menghitung tagihan.
6. Pilih metode bayar → **Proses Transaksi**.
7. Kirim struk lewat WhatsApp. Struk memuat tautan kartu member.

### Akhir shift kasir — Tutup Kas

Tekan **Tutup Kas**, hitung fisik uang tunai, masukkan jumlahnya.

> **Layar kasir sengaja tidak menampilkan berapa yang seharusnya ada.**
> Bila kasir dapat melihat angka sistem, hitungan fisiknya berhenti menjadi
> kontrol — siapa pun tinggal mengetik ulang angka yang sudah tertera.
> Selisih hanya terlihat oleh owner.

Setoran hanya bisa dikirim **sekali per hari**. Bila keliru, owner yang
menyesuaikan; angka asli kasir tidak pernah ditimpa.

### Capster

Buka `/capster` dari ponsel. Berisi kinerja hari ini, absensi, dan cuti.
Absen masuk memerlukan **foto selfie** dan **berada dalam radius outlet**.

### Owner

Buka `/rekap`. Berisi omzet, metode bayar, performa capster, log transaksi,
setoran kas, HPP & laba produk, rekap absensi, dan persetujuan cuti.

---

## 5. Yang Harus Diisi Sebelum Dipakai Sungguhan

Seluruh data berikut masih **contoh** dan wajib diganti:

- [x] ~~Daftar layanan dan harga final~~ — sudah terpasang dari klien
- [x] ~~Daftar capster~~ — Cena, Lukman, Wanda sudah terpasang beserta akunnya
- [ ] Nama kasir dan **PIN masing-masing** — PIN contoh `1234/5678/9012`
      berurutan dan mudah ditebak
- [ ] Alamat dan **koordinat outlet** — dipakai validasi radius absensi
- [ ] Katalog produk beserta **harga modal** — `/rekap` → HPP & Laba Produk
- [ ] Daftar reward dan biaya poinnya
- [ ] Rasio poin dan nilai tukarnya
- [ ] Syarat naik tier Silver → Black
- [ ] Jam kerja, toleransi terlambat, kuota cuti tahunan
- [ ] Ganti kata sandi owner dan perangkat POS
- [ ] **Rotate Personal Access Token Supabase** yang dipakai saat pengembangan

Aturan poin dan tier disimpan sebagai **data**, bukan kode. Mengubahnya tidak
memerlukan rilis ulang.

---

## 6. Keputusan Teknis yang Perlu Diketahui Penerus

Beberapa hal di bawah tampak berlebihan sampai keadaannya benar-benar terjadi.

**Nomor nota dibuat server.** Bila dihitung di perangkat kasir, dua perangkat
menghasilkan nomor kembar. Diuji dengan 12 transaksi serentak: 12 nomor unik.

**Batas hari memakai zona Asia/Jakarta.** `toISOString()` berbasis UTC
menggeser batas hari ke pukul 07.00 WIB, sehingga transaksi dini hari masuk ke
tanggal sebelumnya.

**Saldo poin tidak pernah dijumlah dari riwayat.** Penukaran mengunci baris
member (`FOR UPDATE`). Diuji dengan 4 penukaran serentak atas saldo yang hanya
cukup untuk satu: satu berhasil, tiga ditolak.

**HPP dibekukan saat penjualan.** Bila laba dihitung ulang memakai HPP terkini,
laba bulan lalu berubah setiap kali harga supplier direvisi, dan laporan yang
sudah dicetak tidak lagi cocok.

**Antrean offline tidak pernah membuang transaksi.** Kegagalan berulang
ditandai agar terlihat orang, bukan diulang diam-diam selamanya.

**Foto absensi tidak dapat ditimpa atau dihapus** oleh siapa pun, termasuk
owner. Bukti yang dapat diganti belakangan bukan lagi bukti.

**Hash PIN tidak pernah keluar dari basis data.** Hak baca kolom `pin_hash`
dicabut dari seluruh peran API; `select=*` pada tabel `cashiers` sengaja
ditolak. Sebelumnya hash ikut terkirim ke sesi owner, dan dengan bcrypt biaya 6
seluruh PIN 4 digit dapat dipulihkan luring dalam 92 detik — melewati pembatas
5 percobaan per menit sepenuhnya. Yang rusak bukan kerahasiaan owner melainkan
kemampuan sistem membuktikan siapa melakukan apa: bila PIN Ahmad dapat
dipulihkan, transaksi dapat dibuat atas namanya. Biaya bcrypt kini 11.

**Merah dipakai hemat.** Merah #BE0000 diambil dari bintang pada logo dan
hanya muncul di aksi utama, penanda posisi, dan angka yang menjadi kesimpulan
sebuah layar. Harga layanan sengaja bertinta, bukan merah — harga muncul
puluhan kali dalam satu layar, dan mewarnainya merah membuat kasir berhenti
melihat merah sebagai peringatan. Daftar tempat merah boleh muncul ada di
bagian akhir `theme.css`; menambah baris di sana berarti mengurangi artinya
di tempat lain.

**Tidak ada huruf tebal.** Bobot berhenti di 600. Hierarki dibangun dari
ukuran, warna, jarak huruf, dan ruang kosong.

**Library di-host sendiri di `vendor/`, bukan CDN.** Kasir tidak boleh ikut
mati bila jaringan luar terganggu.

---

## 7. Batasan yang Diakui

Disebutkan apa adanya, bukan dianggap tidak ada.

- **Koordinat GPS dapat dipalsukan** pada perangkat yang di-root atau memakai
  aplikasi *mock location*. Radius absensi menyaring kelalaian, bukan
  kecurangan yang disengaja.
- **Tautan kartu member adalah kredensialnya.** Siapa pun yang memegang tautan
  dapat melihat poin dan riwayat pelanggan tersebut. Karena itu nomor WhatsApp
  disamarkan, dan penukaran reward tetap harus divalidasi kasir di meja.
- **Sistem memerlukan internet.** Kasir tetap dapat melayani saat sinyal putus
  (transaksi masuk antrean dan terkirim otomatis), tetapi perubahan master
  data, tutup kas, dan absensi memerlukan koneksi.
- **Di luar scope** sesuai proposal: komisi capster otomatis, booking online,
  manajemen stok gudang, aplikasi Play Store, dan integrasi QRIS dinamis
  (Level 2) maupun mesin EDC (Level 3).

---

## 8. Struktur Berkas

| Berkas | Isi |
| :--- | :--- |
| `masuk.html` | Pintu masuk, perutean per peran |
| `pos.html` | POS kasir |
| `rekap.html` | Dashboard owner |
| `capster.html` | Kinerja, absensi, cuti capster |
| `kartu.html` | Kartu member 5 tab |
| `sb-app.js` | Konfigurasi, gerbang login, gerbang PIN, antrean offline |
| `theme.css` | **Sistem desain** — palet, tipografi, komponen dasar. Mengubah warna cukup di sini. |
| `assets/logo.png` · `logo-putih.png` | Logo Underrated Barbershop (gelap & putih) |
| `vendor/` | Library Supabase & QR, di-host sendiri |
| `supabase_schema.sql` | Skema dasar |
| `supabase_migration_02..10_*.sql` | Migrasi berurutan; jalankan sesuai nomor |

Kunci di `sb-app.js` adalah *publishable key* yang memang dirancang untuk
publik. Yang menjaga data adalah RLS. **Jangan pernah** menaruh `service_role`
atau `sb_secret_...` di berkas frontend.

---

## 9. Bila Terjadi Masalah

| Gejala | Kemungkinan sebab |
| :--- | :--- |
| Kasir melihat "OFFLINE" | Jaringan outlet putus. Transaksi tetap tercatat dan terkirim otomatis. |
| "N TRANSAKSI GAGAL KIRIM" | Kegagalan berulang. Arahkan kursor ke label untuk melihat sebabnya. |
| Menu kasir kosong | Master layanan belum diisi. Buka ⚙️ Pengaturan dengan akun owner. |
| Absen ditolak karena jarak | Koordinat outlet belum diisi atau salah. Perbaiki di tabel `outlets`. |
| Poin tidak bertambah | Transaksi tanpa nomor WhatsApp tidak menghasilkan poin. |
| Owner tidak melihat transaksi kasir | Perangkat kasir belum tersambung, atau masih ada antrean offline. |

---

*Dokumen ini menjelaskan sistem sebagaimana diserahkan. Perubahan setelah
serah terima sebaiknya dicatat menyusul di bawah bagian ini.*
