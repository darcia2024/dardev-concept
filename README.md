# Barber Membership & Loyalty Management System

Sistem Manajemen Membership Digital, Kasir POS & Loyalitas 5-Tier berbasis Web PWA & QR Code untuk Barbershop, dilengkapi opsi penawaran **Smart NFC Onboarding di Meja Kasir**.

---

## 🌐 Live Production Deployment (Vercel)

* **Slide Presentasi Scope & Blueprint:** [https://dardev-concept.vercel.app](https://dardev-concept.vercel.app)
* **Live Demo Mobile Web App (PWA):** [https://dardev-concept.vercel.app/app.html](https://dardev-concept.vercel.app/app.html)

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

* **Frontend:** Next.js (App Router) + Tailwind CSS (PWA Mobile-First)
* **Database & Auth:** Supabase (PostgreSQL with Row Level Security & RBAC)
* **Hosting:** Vercel Global Edge Network
* **Keamanan:** UUID anti-double spend, ledger audit mutasi saldo poin, dan daily automated backup.

---

## 🚀 Cara Menjalankan Prototipe Lokal

Buka terminal di direktori proyek dan jalankan web server:

```bash
# Menggunakan Python built-in server
python -m http.server 3000
```

Akses melalui browser:
* **Slide Presentasi Scope & Arsitektur:** `http://localhost:3000/index.html`
* **Mobile Web App Demo (PWA):** `http://localhost:3000/app.html`
