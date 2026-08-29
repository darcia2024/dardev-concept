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
| | | *Kasir dan capster adalah orang yang sama.* Nama sengaja diseragamkan agar laporan tidak menampilkan dua daftar nama untuk tiga orang. |
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
| Foto selfie absensi | — | miliknya | ✅ |
| Hapus transaksi, absensi, member | — | — | ✅ |
| Hapus foto absensi | — | — | ✅ |
| Ganti sandi capster & PIN kasir | — | — | ✅ |

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

Buka `/capster` dari ponsel. Berisi kinerja hari ini, absensi, cuti, dan
**ganti sandi**. Absen masuk memerlukan **foto selfie** dan **berada dalam
radius outlet**.

Sandi awal dibuat owner dan bersifat acak. Kartu **Ganti Sandi** di bawah
halaman itu satu-satunya cara capster memperbaruinya sendiri; tanpa itu setiap
lupa sandi harus diselesaikan owner lewat dashboard Supabase. Sandi diminta
dua kali karena tidak ada pemulihan mandiri — salah ketik sekali mengunci
orangnya sampai owner turun tangan.

> **Capster tidak memakai PIN.** PIN hanya hidup di POS, pada perangkat yang
> sudah diautentikasi owner, dan tugasnya menandai siapa yang bertugas — bukan
> membuka basis data. Halaman capster dibuka dari ponsel pribadi, yang tidak
> pernah boleh memegang kredensial perangkat POS: ponsel itu ikut pulang, dan
> kredensialnya bertahan setelah orangnya berhenti. Karena itu ponsel pribadi
> memakai akun sungguhan yang dapat dicabut satu per satu. Tiga orang yang
> merangkap kasir dan capster memegang dua kredensial: PIN di POS, sandi di
> ponsel sendiri.

### Owner

Buka `/rekap`. Berisi omzet, metode bayar, performa capster, log transaksi,
setoran kas, HPP & laba produk, rekap absensi, dan persetujuan cuti.

---

## 5. Yang Harus Diisi Sebelum Dipakai Sungguhan

Seluruh data berikut masih **contoh** dan wajib diganti:

- [x] ~~Daftar layanan dan harga final~~ — sudah terpasang dari klien
- [x] ~~Daftar capster~~ — Cena, Lukman, Wanda sudah terpasang beserta akunnya
- [x] ~~Nama kasir dan PIN masing-masing~~ — Cena, Lukman, Wanda; PIN acak
      6 digit menggantikan contoh `1234/5678/9012`
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

**Foto absensi dapat dihapus owner, tetapi tidak dapat ditimpa.** Awalnya
tidak ada peran yang boleh menghapusnya sama sekali, dengan alasan bukti yang
dapat dihapus berhenti menjadi bukti. Pemilik sistem meminta kemampuan itu
diberikan, dan itu keputusannya. Yang tetap dijaga: kebijakan DELETE hanya
untuk owner — capster tidak dapat menghapus fotonya sendiri, sebab bila boleh,
yang terlambat tinggal menghapus buktinya sebelum owner sempat melihat.
Kebijakan UPDATE tetap tertutup untuk semua peran: foto boleh dihapus, tidak
boleh ditukar dengan gambar lain. Menghapus meninggalkan lubang yang terlihat;
menukar meninggalkan kebohongan yang tidak terlihat. Tiap penghapusan tercatat
di `deleted_photos` beserta pelaku, waktu, dan alasannya — dicatat lebih dulu,
baru berkasnya dihapus.

> **Konsekuensi yang perlu diketahui penerus:** sejak perubahan ini, foto
> absensi tidak lagi berlaku sebagai bukti yang tidak terbantahkan dalam
> sengketa kehadiran. Yang tersisa adalah jejak audit — cukup untuk menjawab
> "siapa menghapus dan kapan", tidak cukup untuk menjawab "apakah orang itu
> benar hadir".

**Catatan absensi boleh dihapus, fotonya tidak.** Owner perlu membersihkan data
uji, sementara foto harus tetap berlaku sebagai bukti. Keduanya didamaikan
dengan memisahkan dua hal yang selama ini dianggap satu: barisnya data
operasional dan boleh hilang, berkas fotonya tetap tinggal di penyimpanan.
Arsip `deleted_attendances` menyimpan seluruh isi baris beserta jalur fotonya,
sehingga bila suatu hari ada sengketa "saya masuk hari itu", barisnya masih ada
di arsip dan fotonya masih ada di bucket — keduanya dapat dipertemukan kembali.
Yang hilang hanya kemudahan membacanya, bukan buktinya.

**Penghapusan transaksi adalah pembatalan, bukan DELETE.** Satu transaksi
menyentuh item, buku besar poin, saldo member, dan klaim reward. Menghapus
barisnya saja meninggalkan poin yang tidak pernah dibelanjakan dan saldo yang
tidak cocok dengan riwayatnya. `delete_transaction()` mengunci baris member,
menarik poin yang diperoleh, mengembalikan poin yang ditukar, mengurangi
kunjungan dan belanja, menghitung ulang tier, melepaskan klaim reward, lalu
mengarsipkan sebelum menghapus.

**Sandi capster diganti lewat fungsi, bukan service_role.** Menulis ke
auth.users lewat API menuntut service_role — kunci yang melewati seluruh RLS
dan karena itu tidak boleh ada di frontend. `owner_set_capster_password()`
menjadi jalan sempit penggantinya: satu hal saja yang bisa dilakukannya, hanya
terhadap akun ber-role capster, dan hanya oleh owner.

**Kasir tidak di-seed dari berkas SQL.** Seed lama menanam PIN 1234/5678/9012
yang berurutan dan sering tertinggal sampai hari buka. Menggantinya dengan PIN
sungguhan di berkas yang sama justru lebih buruk — PIN itu akan hidup di
riwayat Git selamanya dan tidak bisa dicabut dengan mengeditnya. Kasir kini
hanya dibuat lewat dashboard owner. Pemasangan baru mendapati daftar kasir
kosong, dan POS menolak bertransaksi sampai orangnya didaftarkan.

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
- **Tidak ada pemisahan tugas.** Orang yang memotong rambut juga yang
  memasukkan transaksi dan memegang uangnya. Ini wajar untuk barbershop
  bertiga, tetapi menentukan apa yang sanggup dideteksi sistem: setoran kas
  buta menangkap **salah hitung**, bukan **transaksi yang tidak pernah
  dimasukkan**. Yang mendekati kontrol untuk hal itu adalah membandingkan
  jumlah transaksi tiap capster dengan hari kerjanya di rekap absensi —
  keduanya ada di `/rekap`, tetapi pembacaannya tetap pekerjaan owner, bukan
  sesuatu yang dihitung sistem.
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
| `supabase_migration_02..16_*.sql` | Migrasi berurutan; jalankan sesuai nomor. Nomor 15 sengaja belum dijalankan. |

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
