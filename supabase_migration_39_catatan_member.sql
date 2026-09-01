-- ==============================================================================
-- MIGRASI 39 - Tanggal Lahir dan Catatan Potongan Akhirnya Terpakai
--
-- Migrasi 31 menambahkan birth_date dan cut_notes sesuai bagian 01
-- spesifikasi, tetapi tidak ada satu layar pun yang menulis maupun membacanya.
-- Kolom yang tidak pernah terisi sama saja tidak ada, dan lebih buruk: ia
-- terlihat seperti fitur yang sudah jadi.
--
-- SIAPA YANG BOLEH MENGISI
--
-- Kasir, bukan hanya owner. Catatan model potongan ditulis oleh orang yang
-- sedang berhadapan dengan pelanggannya, tepat setelah rambutnya selesai
-- dipotong. Menahannya di layar owner berarti catatan itu tidak akan pernah
-- terisi oleh siapa pun.
--
-- Tanggal lahir hanya disimpan. Apakah ia menghasilkan poin, dan apakah poin
-- itu ikut menaikkan level, adalah keputusan K-03 yang belum dijawab pemilik.
-- Datanya dikumpulkan lebih dulu supaya begitu keputusannya turun, tidak ada
-- yang perlu menunggu setahun untuk mengumpulkan ulang tanggal lahirnya.
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_member_catatan(
    p_member_id UUID, p_birth_date date, p_cut_notes TEXT)
RETURNS TABLE (member_no VARCHAR, name VARCHAR, birth_date date, cut_notes TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    IF p_birth_date IS NOT NULL AND
       (p_birth_date > jakarta_today() OR p_birth_date < '1900-01-01'::date) THEN
        RAISE EXCEPTION 'Tanggal lahir tidak masuk akal.';
    END IF;
    IF length(COALESCE(p_cut_notes, '')) > 500 THEN
        RAISE EXCEPTION 'Catatan potongan maksimal 500 karakter.';
    END IF;

    UPDATE members m
       SET birth_date = p_birth_date,
           cut_notes  = NULLIF(btrim(COALESCE(p_cut_notes, '')), ''),
           updated_at = now()
     WHERE m.id = p_member_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Member tidak ditemukan.'; END IF;

    RETURN QUERY SELECT m.member_no, m.name, m.birth_date, m.cut_notes
                   FROM members m WHERE m.id = p_member_id;
END $function$;

REVOKE EXECUTE ON FUNCTION update_member_catatan(UUID, date, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION update_member_catatan(UUID, date, TEXT) TO authenticated;


-- ── Kasir perlu melihat catatannya saat member terdeteksi ──────────────────
-- Ditulis sebagai plpgsql dengan RAISE, bukan sebagai SQL yang menyaring
-- auth.uid() di WHERE. Penyaringan diam menghasilkan larik kosong, dan layar
-- kasir membaca larik kosong sebagai "member tidak ditemukan" lalu menawarkan
-- pendaftaran baru — perangkat yang belum terdaftar akan diam-diam membuat
-- member kembar alih-alih memberi tahu bahwa ia belum masuk.
DROP FUNCTION IF EXISTS lookup_member(text);

CREATE OR REPLACE FUNCTION lookup_member(p_phone TEXT)
RETURNS TABLE (name VARCHAR, tier member_tier, visit_count INT, points_balance INT,
               member_code VARCHAR, member_no VARCHAR, member_id UUID,
               birth_date date, cut_notes TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    RETURN QUERY
    SELECT m.name, m.tier, m.visit_count, m.points_balance, m.member_code,
           m.member_no, m.id, m.birth_date, m.cut_notes
      FROM members m
     WHERE m.phone_wa = p_phone
     LIMIT 1;
END $function$;

REVOKE EXECUTE ON FUNCTION lookup_member(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION lookup_member(TEXT) TO authenticated;
