# Barber Membership & Loyalty Management System

Sistem Manajemen Membership Digital, Kasir POS & Loyalitas 5-Tier berbasis Web PWA & QR Code untuk Barbershop, dilengkapi opsi penawaran **Smart NFC Onboarding di Meja Kasir**.

---

## 📘 Dokumen Serah Terima

Panduan operasional lengkap — siapa masuk lewat mana, apa yang dilihat tiap
peran, daftar data yang wajib diisi sebelum dipakai sungguhan, keputusan
teknis yang perlu diketahui penerus, dan batasan yang diakui apa adanya:

**[SERAH-TERIMA.md](SERAH-TERIMA.md)**

---

## 🌐 Live Production Deployment (Vercel)

* **Pintu Masuk Sistem:** [https://dardev-concept.vercel.app/masuk](https://dardev-concept.vercel.app/masuk)
* **Slide Presentasi Scope & Blueprint:** [https://dardev-concept.vercel.app](https://dardev-concept.vercel.app)
* **Live Demo Mobile Web App (PWA):** [https://dardev-concept.vercel.app/app.html](https://dardev-concept.vercel.app/app.html)
* **Addendum Penawaran Final (Revisi 02):** [https://dardev-concept.vercel.app/finalpenawaran](https://dardev-concept.vercel.app/finalpenawaran)
* **POS Kasir Mode Opening (Fase 0):** [https://dardev-concept.vercel.app/pos](https://dardev-concept.vercel.app/pos)
* **Dashboard Rekap Owner:** [https://dardev-concept.vercel.app/rekap](https://dardev-concept.vercel.app/rekap)
* **Kinerja Capster:** [https://dardev-concept.vercel.app/capster](https://dardev-concept.vercel.app/capster)
* **Kartu Member Digital:** `https://dardev-concept.vercel.app/kartu?c=KODE_KARTU`

---

## 🎯 Ringkasan Eksekutif & Sasaran

1. **Digital Loyalty Card & QR Scanner:** Menggantikan kartu fisik kertas dengan kartu digital di smartphone pelanggan.
2. **Transaksi Kasir Cepat (Sub-60 Detik):** Kasir memindai QR member, memilih layanan & capster, serta memproses penukaran poin diskon secara otomatis.
3. **Sistem 5-Tier Leveling Otomatis:** Member otomatis naik level (*Silver, Gold, Platinum, Infinite, Black*) seiring akumulasi poin transaksi.
4. **Smart NFC Onboarding di Meja Kasir:** 1 unit kartu/standee NFC pintar dipegang kasir. Pelanggan cukup *tap* ponsel sehabis cukur untuk mendaftar instan dengan Nama & WhatsApp serta otomatis mengklaim poin cashback perdana.
5. **Dashboard Owner Multi-Cabang:** Visibilitas omzet harian/bulanan, performa capster, dan audit mutasi poin secara real-time.

---

## 📱 Struktur Aplikasi (5 Tab PWA Mobile-First)

1. **Home:** Kartu member eksklusif monokrom, progress bar level tier, 3 pintasan aksi cepat, dan timeline riwayat potong rambut.
2. **Reward:** Katalog voucher diskon cukur, produk gratis, dan paket treatment dengan tombol penukaran poin interaktif.
3. **Scan QR (Center Action):** Kartu identitas digital member dengan kode QR vektor beresolusi tinggi + simulasi tap NFC.
4. **Product:** Katalog produk retail grooming (Pomade, Matte Clay, Tonic, Beard Oil) dengan indikator *hold/shine*.
5. **Store:** Daftar cabang outlet, indikator jam buka, daftar capster bertugas, dan integrasi GPS Google Maps.

---

## 💰 Struktur Paket Penawaran (Rentang Rp 3 – 7 Juta)

| Paket Penawaran | Estimasi Biaya | Keterangan Scope |
| :--- | :---: | :--- |
| **1. Paket Basic (Core MVP)** | **Rp 3.000.000 – Rp 3.800.000** | Digital Loyalty 1 Outlet, Kartu QR, Poin Kasir, Tier Standar (Silver/Gold), Dashboard Admin & Kasir. |
| **2. Paket Full (Omnichannel PWA)** | **Rp 4.900.000 – Rp 5.800.000** | **Rekomendasi Utama:** 5-Tab PWA Lengkap, 5-Tier Gamifikasi (Silver s.d. Black), Modul Reward, Produk, Store Locator & Multi-Cabang. |
| **3. Paket Ultimate + NFC Kasir** | **Rp 6.200.000 – Rp 6.900.000** | **All-in PWA + Smart NFC:** PWA 5-Tab + Setup 1 Unit Master Kartu/Standee NFC di meja kasir untuk onboarding instan (Nama + No WA). |

---

## 🛠️ Spesifikasi Arsitektur Teknologi

* **Frontend:** HTML statis mobile-first (Fase 0). Library Supabase di-*host* sendiri di `vendor/`, bukan CDN, agar kasir tetap jalan bila jaringan luar terganggu.
* **Database & Auth:** Supabase (PostgreSQL 17) — Row Level Security aktif di seluruh tabel, akses anonim ditolak penuh.
* **Hosting:** Vercel Global Edge Network
* **Keamanan:** Login wajib untuk kasir & owner, `client_uuid` unik sebagai kunci idempotensi antrean offline, nomor nota dibuat server (anti-bentrok multi perangkat), dan seluruh batas hari memakai zona `Asia/Jakarta`.

### Berkas inti Fase 0

| Berkas | Peran |
| :--- | :--- |
| `supabase_schema.sql` | Skema dasar: tabel, RLS, fungsi `next_invoice_no()` & RPC `create_transaction()`. |
| `supabase_migration_02_akses.sql` | Sistem akses Owner & Kasir: tabel `cashiers`, PIN ter-hash, RLS per peran. |
| `supabase_migration_03_tutup_kas.sql` | Tutup kas harian: setoran tunai kasir (hitungan buta) & rekonsiliasi owner. |
| `sb-app.js` | Lapisan data bersama: konfigurasi, gerbang login, antrean offline, indikator koneksi. |
| `vendor/supabase.js` | Library Supabase yang di-*host* sendiri. |
| `pos.html` | POS kasir. |
| `rekap.html` | Dashboard owner. |

### Sistem Akses Owner & Kasir

| Peran | Cara masuk | Akses |
| :--- | :--- | :--- |
| **Owner** | Email + kata sandi | Seluruh sistem: POS, laporan, data pegawai, layanan, pelanggan, pengaturan |
| **Perangkat POS** | Email + kata sandi, **sekali saat setup** oleh owner | Hanya katalog layanan & capster + mencatat transaksi |
| **Kasir** | **PIN pribadi**, tanpa email/kata sandi | POS, atas nama dirinya sendiri |

Alur kasir: buka POS → masukkan PIN → sistem mengenali → mulai transaksi.
Ganti kasir cukup menekan nama kasir di kanan atas, tanpa keluar dari perangkat.

Setiap transaksi mencatat **nama kasir, ID kasir, waktu, nomor transaksi, total, dan metode pembayaran**,
sehingga selisih kas dapat ditelusuri ke orangnya.

#### Tutup Kas Harian

Selesai bertugas, kasir menghitung fisik uang tunai dan menyetorkan angkanya lewat tombol
**💰 Tutup Kas**. Owner melihat perbandingannya di dashboard dan menyesuaikan bila ada selisih.

> **Hitungan buta:** layar kasir tidak pernah menampilkan berapa yang seharusnya ada.
> Bila kasir dapat melihat angka sistem, hitungan fisiknya berhenti menjadi kontrol —
> siapa pun tinggal mengetik ulang angka yang sudah tertera. Ekspektasi dihitung di
> server saat penyetoran, dan tabel setoran tidak dapat dibaca perangkat kasir sama sekali.

Setoran hanya bisa dikirim sekali per kasir per hari. Angka asli kasir tidak pernah
ditimpa — penyesuaian owner disimpan di kolom terpisah agar jejak auditnya utuh.

> **Mengapa PIN tidak dipakai sebagai kredensial database:** PIN 4 digit hanya 10.000
> kemungkinan dan akan habis ditebak dalam hitungan detik bila menjadi satu-satunya
> penjaga. Karena itu **perangkat** yang diautentikasi (sekali, oleh owner), sementara
> **PIN** hanya menentukan kasir mana yang bertugas. PIN disimpan sebagai hash bcrypt,
> diverifikasi di server, dan dibatasi 5 percobaan per menit.

> **Catatan kunci:** `sb-app.js` memuat *publishable key* yang memang dirancang untuk publik dan aman berada di HTML. Yang menjaga data adalah RLS di database. **Jangan pernah** menaruh `service_role` atau `sb_secret_...` di berkas frontend.

---

## 🚀 Cara Menjalankan Prototipe Lokal

Buka terminal di direktori proyek dan jalankan web server:

```bash
# Menggunakan Python built-in server
python -m http.server 3000
```

> Server bawaan Python bersifat *single-thread* dan dapat memutus transfer berkas besar
> (`vendor/supabase.js`). Bila `pos.html` gagal memuat, pakai server lain — misalnya
> `npx serve -l 3000`.

Akses melalui browser:
* **Slide Presentasi Scope & Arsitektur:** `http://localhost:3000/index.html`
* **Mobile Web App Demo (PWA):** `http://localhost:3000/app.html`
* **POS Kasir Mode Opening (Fase 0):** `http://localhost:3000/pos.html`
* **Dashboard Rekap Owner (Fase 0):** `http://localhost:3000/rekap.html`
* **Addendum Penawaran Final:** `http://localhost:3000/finalpenawaran.html`
