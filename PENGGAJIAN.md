# Jadwal, kasbon, dan slip gaji

Pembaruan dibuat dari commit `3b2a8fc` pada cabang `codex/karyawan-kasbon-slip-gaji`.
Kode ini belum dipasang ke Supabase atau Vercel produksi.

## Perilaku

- Kalender mengikuti bulan/tahun terpilih. Hari di luar `working_days` ditandai libur rutin dan tidak menjadi alpha dalam rekap/unduhan.
- Owner dapat menyimpan jadwal, gaji bulanan, dan rekening pada kartu karyawan atau form Ubah. Hari memakai ISO: Senin = 1 sampai Minggu = 7.
- Kuota kasbon mengikuti bulan kalender Asia/Jakarta. Rumus: `floor(gaji_pokok × hari_hadir × 0,30 / hari_kerja_wajib_sebulan)`, dikurangi pengajuan pending dan approved pada bulan pengajuan. Hadir dan terlambat dihitung satu kali per tanggal; pengajuan ditolak mengembalikan kuota.
- Server memvalidasi ulang nominal serta mengunci baris karyawan saat pengajuan/keputusan/pencairan. Kunci pengajuan mencegah pencatatan ganda saat pengiriman yang sama diulang.
- Alur kasbon: Menunggu → Disetujui/Ditolak. Setelah uang benar-benar diserahkan, owner memilih **Catat pencairan → Sudah dicairkan**. Tombol tersebut hanya mencatat pembayaran, tidak melakukan transfer bank.
- Sesuai koreksi owner, **hanya kasbon yang sudah dicairkan menjadi potongan gaji**, pada bulan pencairannya (WIB). Persetujuan saja belum dipotong. Kuota tetap mengikuti bulan pengajuan, termasuk saat owner memutuskan pengajuan bulan lama.
- Slip memakai gaji pokok flat; alpha tidak otomatis memotong gaji. Pendapatan tambahan, tip, bonus, dan potongan lain diisi owner; input tambahan direset saat karyawan/bulan diganti.
- Mandiri / Bank Mandiri (abaikan kapitalisasi dan spasi tepi) bebas biaya admin. Bank lain Rp2.500. Rekening kosong mencegah pembuatan slip.
- Slip menggunakan data terbaru saat **Buat pratinjau slip** ditekan. Slip tidak disimpan sebagai arsip permanen di database: simpan PDF final untuk arsip. Perubahan jadwal/gaji/rekening juga berlaku pada perhitungan ulang periode lama; belum ada riwayat tarif/jadwal per tanggal.

## Pemasangan

1. Gunakan repositori `darcia2024/dardev-concept` dan proyek yang memiliki domain `dardev-concept.vercel.app`. Proyek `dardev-concept-barber` bukan target rilis ini.
2. Pastikan database target sudah memakai migrasi aplikasi sampai 61. Simpan cadangan database dan deployment produksi saat ini.
3. Jalankan `supabase_migration_62_jadwal_penggajian.sql` lalu `supabase_migration_63_kasbon_slip_gaji.sql` di SQL Editor Supabase target. Masing-masing transaksi utuh; jangan hanya menjalankan sebagian. Jangan menjalankan fixture tes di produksi.
4. Tinjau perubahan pada cabang fitur, lalu terbitkan enam berkas frontend: `rekap.html`, `capster.html`, `payroll.js`, `payroll.css`, `payroll-owner.js`, dan `payroll-employee.js`. Merge ke `main` repositori asal `darcia2024/dardev-concept` memicu deployment Vercel pada konfigurasi saat ini. Fork `hilmyh09/dardev-concept` harus dihubungkan ke proyek Vercel terlebih dahulu bila akan dijadikan sumber deployment. Migrasi SQL harus selesai terlebih dahulu.
5. Buka Dashboard Owner → Karyawan. Isi jadwal, gaji, dan rekening tiap orang. Default jadwal tujuh hari mempertahankan perilaku lama; gaji awal nol sehingga kasbon belum tersedia sampai gaji diisi.
6. Uji dengan akun karyawan dan owner khusus pengujian: libur rutin, pengajuan melebihi kuota, persetujuan, pencatatan pencairan, lalu slip. Pilih Cetak / Simpan PDF, kertas A4 potret, skala default, dan matikan header/footer bawaan browser.

Data gaji/rekening disimpan di tabel privat `employee_payroll`, bukan kolom `capsters` yang juga dibaca kasir. RLS dan RPC membatasi pengaturan/penggajian ke owner serta kasbon ke karyawan pemiliknya. Frontend tidak memakai service-role key.

Jika frontend perlu dipulihkan, rollback deployment frontend saja; jangan menghapus tabel kasbon yang sudah berisi pengajuan/pencairan. Fungsi Ubah tetap menerima parameter lama melalui nilai default.

## Pengujian

- 36 suite JavaScript lulus, termasuk tes jadwal/tahun kabisat, pembulatan 30%, bank, terbilang, validasi nominal/tanggal, dan escaping cetakan.
- `tests/payroll-db.test.js` menjalankan migrasi/RPC nyata dalam PostgreSQL WASM (PGlite) terisolasi: RLS, penolakan akses lintas pengguna, libur/alpha, atomic save, kuota, idempotensi, keputusan, pencairan, statistik slip, dan reset bulanan. Ini bukan pengujian database produksi atau uji beban multi-koneksi.
- Alur browser memakai HTML/JS aplikasi dan RPC SQL di fixture lokal: pengajuan → persetujuan → pencairan → potongan slip, penyimpanan kartu/form Ubah, Mandiri tanpa biaya, dan pergantian bulan. PDF dari tombol cetak Chrome diverifikasi satu halaman A4, lengkap sampai tanda tangan/footer.

Jalankan semua tes JavaScript dari akar repo dengan Node.js. Tes database memerlukan `@electric-sql/pglite@0.3.14`; instal di direktori alat terpisah dan gunakan variabel `PGLITE_MODULE` dengan path paket tersebut:

```sh
node tests/payroll.test.js
PGLITE_MODULE=/path/alat/node_modules/@electric-sql/pglite node tests/payroll-db.test.js
PGLITE_MODULE=/path/alat/node_modules/@electric-sql/pglite node tests/payroll-preview-server.cjs
```

Server pratinjau hanya mengikat `127.0.0.1:8765`. Data uji disimpan di memori dan hilang setelah server berhenti. Halaman owner: `/rekap.html#karyawan`, karyawan: `/capster.html`. Autentikasi fixture sengaja diganti untuk QA lokal; jangan menjalankan server ini sebagai aplikasi publik. `.vercelignore` mengecualikan tes, SQL, dan dokumentasi dari deployment.

## Hambatan akses saat serah terima (7 November 2026)

- GitHub menolak `push --dry-run`: akun `hilmyh09` belum memiliki akses menulis ke `darcia2024/dardev-concept` (403).
- Fork publik `hilmyh09/dardev-concept` sudah terverifikasi berasal dari repositori tersebut dan memiliki dasar kode yang sama. Cabang fitur dapat ditinjau di fork; membuat fork saja tidak mengubah deployment produksi.
- Koneksi Vercel hanya menampilkan proyek `dardev-concept-barber` di tim `hafizhhilmy30-1389s-projects`, bukan target produksi di atas.
- Belum ada akses pengelolaan database Supabase target untuk menjalankan migrasi 62 dan 63.

Tim dapat menerima perubahan dari fork atau memberi akses menulis repo asal kepada `hilmyh09`, mengundang `hafizh.hilmy30@gmail.com` ke proyek/tim Vercel yang benar, serta menjalankan dua migrasi melalui pengelola Supabase yang sudah berwenang. Tidak perlu mengirim kata sandi atau service-role key melalui chat.
