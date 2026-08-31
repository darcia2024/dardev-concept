# Tutorial Diskon Kasir

Panduan ini dipakai oleh owner untuk membuat aturan diskon dan oleh kasir untuk menerapkannya pada transaksi.

## Sebelum digunakan

Fitur diskon harus sudah aktif di database melalui `supabase_migration_30_diskon_kasir.sql`. Bila bagian Diskon Kasir menampilkan pesan bahwa fitur belum aktif, migrasi tersebut belum dijalankan.

## A. Membuat diskon sebagai owner

1. Buka halaman POS dan masuk menggunakan akun owner.
2. Tekan **Pengaturan** di kanan atas.
3. Cari bagian **Diskon Kasir**.
4. Tekan **+ Tambah Diskon**.
5. Isi nama diskon yang mudah dikenali kasir, misalnya `Promo Opening`.
6. Pilih jenis diskon:
   - **Persen (%)** untuk potongan berdasarkan persentase subtotal.
   - **Nominal (Rp)** untuk potongan dengan nilai rupiah tetap.
7. Isi nilai diskon.
8. Isi **Minimal belanja** bila diskon hanya berlaku mulai subtotal tertentu.
9. Untuk diskon persen, isi **Maks. potongan** bila nilai potongannya perlu dibatasi.
10. Pastikan **Aktif dan dapat dipilih kasir** tercentang.
11. Tekan **Simpan**.

Diskon aktif langsung muncul di pilihan pembayaran kasir. Diskon nonaktif tetap tersimpan di Pengaturan, tetapi tidak dapat dipilih saat transaksi.

## B. Memberikan diskon sebagai kasir

1. Pilih capster dan layanan seperti transaksi biasa.
2. Isi data pelanggan bila diperlukan.
3. Pilih metode pembayaran.
4. Di bagian **Diskon Kasir**, pilih preset yang diberikan owner.
5. Periksa nilai potongan di sisi kanan pilihan diskon.
6. Periksa **Total Tagihan** setelah diskon.
7. Untuk pembayaran tunai, masukkan uang yang diterima. Pilihan Uang Pas dan nilai Kembalian sudah mengikuti total setelah diskon.
8. Tekan **Proses Transaksi**.

Kasir tidak dapat mengetik nominal diskon sendiri. Sistem hanya menerima preset aktif yang dibuat owner.

## Contoh hitungan

### Diskon persen

Aturan:

- Nama: `Promo Opening`
- Nilai: `10%`
- Minimal belanja: `Rp 100.000`
- Maksimal potongan: `Rp 20.000`

Transaksi dengan subtotal `Rp 150.000` mendapat potongan `Rp 15.000`. Total tagihannya menjadi `Rp 135.000`.

Transaksi dengan subtotal `Rp 300.000` seharusnya menghasilkan potongan `Rp 30.000`, tetapi batas maksimalnya `Rp 20.000`. Total tagihannya menjadi `Rp 280.000`.

### Diskon nominal

Aturan:

- Nama: `Voucher 15K`
- Nilai: `Rp 15.000`
- Minimal belanja: `Rp 75.000`

Transaksi dengan subtotal `Rp 100.000` mendapat potongan `Rp 15.000`. Total tagihannya menjadi `Rp 85.000`.

## Diskon dan poin member

Diskon kasir dapat dipakai bersama potongan poin. Sistem membatasi total potongan agar tagihan tidak menjadi negatif. Poin baru dihitung dari nilai akhir yang benar-benar dibayar pelanggan.

Pada struk, kedua potongan tampil terpisah:

```text
Subtotal:          Rp 150.000
Diskon poin:       - Rp 10.000
Diskon Promo:      - Rp 15.000
TOTAL:             Rp 125.000
```

## Mengecek diskon sebagai owner

1. Buka halaman **Rekap Omzet**.
2. Cari transaksi berdasarkan nomor nota atau pelanggan.
3. Nilai akhir tampil di kolom total.
4. Nama diskon, potongan kasir, dan potongan poin tampil di bawah nilai akhir.
5. Tekan **Unduh CSV** bila data perlu diperiksa di Excel. File CSV memiliki kolom terpisah untuk subtotal, diskon poin, diskon kasir, nama diskon, dan total.

## Mengubah atau menghentikan diskon

- Tekan ikon pensil pada baris diskon untuk mengubah aturan.
- Tekan ikon status untuk mengaktifkan atau menonaktifkan diskon.
- Gunakan nonaktif bila promo hanya dihentikan sementara.
- Hapus diskon hanya bila preset tersebut tidak akan dipakai lagi.

Transaksi lama tetap menyimpan nama dan nilai diskon saat transaksi dibuat. Mengubah atau menghapus preset tidak mengubah rekap lama.

## Bila diskon tidak muncul

Periksa hal berikut:

1. Diskon masih berstatus aktif di Pengaturan.
2. Subtotal transaksi sudah mencapai minimal belanja.
3. Perangkat kasir sedang memakai data master terbaru. Tekan **Muat Ulang** di Pengaturan bila owner baru mengubah preset dari perangkat lain.
4. Perangkat memiliki koneksi internet saat owner membuat atau mengubah preset.
5. Migrasi 30 sudah dijalankan bila muncul pesan fitur diskon belum aktif.

## Pemeriksaan sebelum transaksi selesai

- Nama diskon sesuai promo yang diberikan.
- Nilai potongan sesuai aturan.
- Total tagihan sudah berkurang.
- Uang diterima dan kembalian sudah benar.
- Struk menampilkan diskon setelah transaksi berhasil.
