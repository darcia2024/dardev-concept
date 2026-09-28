-- ==============================================================================
-- MIGRASI 48 - Penautan akun karyawan, untuk dipakai Edge Function
--
-- Migrasi 47 memberi owner panel untuk menambah karyawan, tetapi akunnya tetap
-- dibuat manual di Supabase Dashboard. Membuat akun butuh service-role key, dan
-- kunci itu tidak boleh menyentuh peramban: publishable key yang dipakai layar
-- owner bersifat publik, siapa pun dapat membacanya dari sumber halaman.
--
-- Karena itu pembuatan akun dipindah ke Edge Function `buat-akun-karyawan`,
-- yang memegang service-role key di lingkungannya sendiri. Fungsi SQL di bawah
-- adalah sisi basis data dari alur itu: ia yang memutuskan boleh atau tidaknya
-- sebuah akun ditautkan, sehingga aturannya tinggal di tempat aturan lain
-- repositori ini tinggal, bukan tersebar ke berkas TypeScript.
--
-- HAK EKSEKUSINYA SENGAJA HANYA UNTUK service_role.
--
-- Fungsi ini berjalan SECURITY DEFINER dan menulis profiles.role. Bila
-- `authenticated` boleh memanggilnya, kapster mana pun dapat menautkan akunnya
-- sendiri ke baris karyawan lain, atau menulis ulang perannya. Satu-satunya
-- pemanggil yang sah adalah Edge Function, yang sudah lebih dulu memastikan
-- pemanggilnya owner.
-- ==============================================================================


CREATE OR REPLACE FUNCTION tautkan_akun_karyawan(
    p_karyawan_id  UUID,
    p_auth_user_id UUID
)
RETURNS TABLE (nama CHARACTER VARYING, email TEXT, jabatan CHARACTER VARYING)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $function$
DECLARE
    v_kar  capsters%ROWTYPE;
    v_mail TEXT;
BEGIN
    SELECT * INTO v_kar FROM capsters c WHERE c.id = p_karyawan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karyawan tidak ditemukan.';
    END IF;

    -- Menimpa tautan yang sudah ada berarti seseorang kehilangan aksesnya
    -- tanpa pernah diberi tahu, dan riwayat absennya berpindah diam-diam ke
    -- pemilik akun yang baru. Lebih baik menolak.
    IF v_kar.auth_user_id IS NOT NULL THEN
        RAISE EXCEPTION '% sudah punya akun. Lepaskan akun lamanya lebih dulu.', v_kar.name;
    END IF;

    SELECT u.email::TEXT INTO v_mail FROM auth.users u WHERE u.id = p_auth_user_id;
    IF v_mail IS NULL THEN
        RAISE EXCEPTION 'Akun yang hendak ditautkan tidak ditemukan.';
    END IF;

    -- Satu akun untuk satu orang. Indeks idx_capsters_auth_unik sudah
    -- menjaganya, tetapi galat indeks berbunyi seperti kerusakan; yang ini
    -- dapat dibaca owner.
    IF EXISTS (SELECT 1 FROM capsters c WHERE c.auth_user_id = p_auth_user_id) THEN
        RAISE EXCEPTION 'Akun % sudah dipakai karyawan lain.', v_mail;
    END IF;

    UPDATE capsters c SET auth_user_id = p_auth_user_id
     WHERE c.id = p_karyawan_id;

    -- Peran ditulis di sini, bukan hanya diserahkan kepada trigger
    -- handle_new_user(). Trigger itu membaca raw_user_meta_data, dan akun yang
    -- dibuat tanpa metadata akan berperan 'kasir' — akunnya tampak jadi,
    -- tetapi absennya menolak dan penggantian sandinya menolak, keduanya
    -- dengan pesan yang tidak menyebut sebabnya.
    --
    -- 'capster' di sini berarti "karyawan yang boleh absen", bukan "tukang
    -- cukur". Lihat migrasi 47: yang membedakan pekerjaan adalah kolom
    -- jabatan, bukan peran.
    INSERT INTO profiles (id, full_name, role)
    VALUES (p_auth_user_id, v_kar.name, 'capster')
    ON CONFLICT (id) DO UPDATE
        SET role = 'capster', full_name = EXCLUDED.full_name;

    RETURN QUERY SELECT v_kar.name, v_mail, v_kar.jabatan;
END $function$;

-- Dicabut dari semuanya lebih dulu, termasuk anon dan authenticated yang
-- Supabase berikan otomatis pada tiap fungsi baru.
REVOKE EXECUTE ON FUNCTION tautkan_akun_karyawan(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION tautkan_akun_karyawan(UUID, UUID) TO service_role;


-- ==============================================================================
-- MELEPAS AKUN
--
-- Dibutuhkan agar penolakan di atas punya jalan keluar. Melepas tautan tidak
-- menghapus akunnya di auth.users: karyawan yang kembali bekerja dapat
-- ditautkan lagi ke akun yang sama, dan riwayat absennya tetap utuh karena
-- absen menunjuk ke capsters.id, bukan ke akunnya.
--
-- Ini owner-only dan dipanggil langsung dari layar, jadi haknya di
-- `authenticated` dengan penjaga is_owner() di dalam.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_lepas_akun_karyawan(p_karyawan_id UUID)
RETURNS TABLE (nama CHARACTER VARYING)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_kar capsters%ROWTYPE;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh melepas akun karyawan.';
    END IF;

    SELECT * INTO v_kar FROM capsters c WHERE c.id = p_karyawan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karyawan tidak ditemukan.';
    END IF;
    IF v_kar.auth_user_id IS NULL THEN
        RAISE EXCEPTION '% memang belum punya akun.', v_kar.name;
    END IF;

    -- Batasi sasaran: fungsi ini tidak boleh dipakai melepas akun owner atau
    -- akun perangkat POS, meski id karyawannya ditebak-tebak.
    IF EXISTS (SELECT 1 FROM profiles p
                WHERE p.id = v_kar.auth_user_id AND p.role <> 'capster') THEN
        RAISE EXCEPTION 'Akun itu bukan akun karyawan.';
    END IF;

    UPDATE capsters c SET auth_user_id = NULL WHERE c.id = p_karyawan_id;
    RETURN QUERY SELECT v_kar.name;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_lepas_akun_karyawan(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_lepas_akun_karyawan(UUID) TO authenticated;
