-- ==============================================================================
-- MIGRASI 52 - Layar absen menampilkan jam kerja milik orangnya sendiri
--
-- GEJALANYA (29 September 2026)
--   Habibah, yang jam kerjanya 09.00 - 17.00 di dashboard owner, melihat
--   "10:00-21:00" di layar absennya sendiri.
--
-- SEBABNYA
--   capster.html membaca work_rules.jam_masuk dan jam_pulang: satu angka
--   umum untuk semua orang. Migrasi 50 mengubah cara clock_in() MENILAI
--   keterlambatan — dari jam orangnya sendiri — tetapi tulisan jam di layar
--   tidak pernah ikut. Penilaiannya benar; yang salah kalimat yang dibaca
--   karyawannya.
--
-- BUG LAMA YANG IKUT KETAHUAN
--   Label yang sama juga salah untuk kapster setiap Jumat, sejak migrasi 18.
--   Toko baru buka 13.00 dan keterlambatan diukur dari 13.00, tetapi layar
--   tetap menulis 10:00 dari work_rules. Kapster yang membaca layarnya akan
--   datang tiga jam lebih awal dari yang diperlukan.
--
-- PERBAIKANNYA
--   Satu fungsi yang menjawab "jam berapa SAYA masuk dan pulang HARI INI",
--   memakai urutan cadangan yang sama persis dengan yang dipakai clock_in():
--   jam milik karyawan itu, lalu jadwal toko hari itu, lalu work_rules.
--   Jam masuk diambil dari jam_masuk_karyawan() yang sudah ada (migrasi 50),
--   bukan ditulis ulang, sehingga tulisan di layar dan penilaiannya tidak
--   mungkin menyimpang satu sama lain.
-- ==============================================================================


-- Pasangan jam_masuk_karyawan(). Urutannya sengaja sama.
CREATE OR REPLACE FUNCTION jam_pulang_karyawan(p_capster_id UUID, p_tanggal DATE)
RETURNS TIME
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT COALESCE(
        (SELECT c.jam_pulang FROM capsters c WHERE c.id = p_capster_id),
        (SELECT jh.tutup FROM jam_hari_ini(p_tanggal) jh),
        (SELECT wr.jam_pulang FROM work_rules wr WHERE wr.id)
    )
$function$;

REVOKE EXECUTE ON FUNCTION jam_pulang_karyawan(UUID, DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION jam_pulang_karyawan(UUID, DATE) TO authenticated;


-- Hanya untuk pemanggil sendiri. Tidak menerima id siapa pun: tidak ada
-- alasan seorang karyawan menanyakan jam kerja rekannya, dan fungsi yang
-- menerima id akan menjawab pertanyaan itu untuk siapa saja yang login.
--
-- sumber memberi tahu layar apakah jam itu milik orangnya sendiri atau ikut
-- jadwal toko. Layar tidak memakainya untuk menilai apa pun.
CREATE OR REPLACE FUNCTION jam_kerja_saya()
RETURNS TABLE (jam_masuk TIME, jam_pulang TIME, sumber TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT jam_masuk_karyawan(c.id, jakarta_today()),
           jam_pulang_karyawan(c.id, jakarta_today()),
           CASE WHEN c.jam_masuk IS NOT NULL THEN 'sendiri' ELSE 'toko' END
      FROM capsters c
     WHERE c.auth_user_id = auth.uid()
     LIMIT 1
$function$;

REVOKE EXECUTE ON FUNCTION jam_kerja_saya() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION jam_kerja_saya() TO authenticated;
