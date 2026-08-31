-- ==============================================================================
-- MIGRASI 27 - Fungsi Khusus Staf Tidak Lagi Dapat Dijalankan Anon
--
-- bookings_list dan decide_booking sudah menolak pemanggil yang bukan kasir
-- atau owner di dalam badannya, dan penolakan itu sudah diuji. Jadi ini bukan
-- menutup lubang yang terbuka, melainkan mengecilkan permukaan.
--
-- Bedanya menjadi penting sejak akar situs berubah menjadi halaman publik:
-- kunci publishable kini tersebar ke setiap pengunjung, dan setiap fungsi yang
-- boleh dijalankan anon menjadi sesuatu yang dapat dicoba orang asing berulang
-- kali. Fungsi yang memang tidak pernah dimaksudkan untuk mereka sebaiknya
-- ditolak di lapisan hak akses, bukan hanya di dalam badannya.
--
-- Dua fungsi publik dibiarkan apa adanya: public_landing memang dibaca
-- pengunjung, dan create_booking memang satu-satunya pintu tulis mereka.
-- ==============================================================================

REVOKE EXECUTE ON FUNCTION bookings_list(TEXT, date) FROM anon;
REVOKE EXECUTE ON FUNCTION decide_booking(UUID, TEXT, TEXT) FROM anon;

-- Ditegaskan ulang supaya berkas ini tetap benar bila dijalankan pada
-- instalasi baru yang belum pernah menerima hibah dari migrasi 24.
GRANT EXECUTE ON FUNCTION bookings_list(TEXT, date) TO authenticated;
GRANT EXECUTE ON FUNCTION decide_booking(UUID, TEXT, TEXT) TO authenticated;
