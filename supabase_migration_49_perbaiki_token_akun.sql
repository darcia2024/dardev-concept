-- =============================================================================
-- 49 · AKUN BUATAN OWNER GAGAL MASUK: "Database error querying schema"
--
-- GEJALA. Kapster yang akunnya dibuat lewat owner_buat_akun_capster (migrasi
-- 47) tidak bisa masuk sama sekali. Layar /masuk menampilkan
-- "Gagal masuk: Database error querying schema", sandinya benar atau salah.
--
-- SEBABNYA. Migrasi 47 mengisi auth.users kolom demi kolom dan membiarkan
-- kolom token (confirmation_token, recovery_token, email_change, dst.) NULL.
-- Server auth Supabase (GoTrue, ditulis dalam Go) membaca kolom-kolom itu
-- sebagai string biasa, bukan string yang boleh kosong. Begitu bertemu NULL,
-- pembacaan barisnya gagal dan seluruh upaya masuk dijawab dengan galat
-- umum di atas. Akun yang dibuat lewat jalur resmi tidak pernah kena, sebab
-- GoTrue sendiri selalu mengisi kolom itu dengan '' (string kosong).
--
-- PERBAIKANNYA, dua bagian:
--   1. Baris yang sudah terlanjur dibuat diluruskan: NULL menjadi ''.
--   2. owner_buat_akun_capster ditulis ulang supaya kolom itu diisi '' sejak
--      awal, sehingga akun baru tidak mewarisi masalah yang sama.
--
-- Aman dijalankan berulang kali. Bagian 1 hanya menyentuh kolom yang masih
-- NULL, dan hanya kolom yang memang ada di versi auth.users basis data ini.
-- =============================================================================

-- ── 1 · Luruskan akun yang sudah terlanjur dibuat ───────────────────────────
-- Dibaca dari information_schema, bukan ditulis mati: kolom yang tersedia
-- berbeda antarversi GoTrue, dan UPDATE ke kolom yang tidak ada akan
-- menggagalkan seluruh migrasi.
DO $perbaikan$
DECLARE
    v_kolom TEXT;
BEGIN
    FOR v_kolom IN
        SELECT c.column_name
          FROM information_schema.columns c
         WHERE c.table_schema = 'auth'
           AND c.table_name   = 'users'
           AND c.column_name IN (
                 'confirmation_token',
                 'recovery_token',
                 'email_change_token_new',
                 'email_change_token_current',
                 'email_change',
                 'phone_change',
                 'phone_change_token',
                 'reauthentication_token'
               )
    LOOP
        EXECUTE format('UPDATE auth.users SET %I = '''' WHERE %I IS NULL',
                       v_kolom, v_kolom);
    END LOOP;
END $perbaikan$;

-- ── 2 · Fungsi pembuat akun, kini dengan token terisi ───────────────────────
-- Isinya sama dengan migrasi 47. Bedanya hanya kolom token di INSERT
-- auth.users, yang kini diisi '' persis seperti yang dilakukan GoTrue.
CREATE OR REPLACE FUNCTION owner_buat_akun_capster(
    p_capster_id UUID,
    p_email      TEXT,
    p_password   TEXT
)
RETURNS TABLE (capster_name VARCHAR, email TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions
AS $function$
DECLARE
    v_cap   capsters%ROWTYPE;
    v_mail  TEXT := lower(btrim(p_email));
    v_uid   UUID := gen_random_uuid();
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuat akun kapster.';
    END IF;

    -- ── Penjagaan sebelum menyentuh apa pun ─────────────────────────────────
    IF v_mail IS NULL OR v_mail !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' THEN
        RAISE EXCEPTION 'Alamat email tidak sah: %', COALESCE(p_email, '(kosong)');
    END IF;
    IF p_password IS NULL OR length(p_password) < 8 THEN
        RAISE EXCEPTION 'Sandi minimal 8 karakter.';
    END IF;

    SELECT * INTO v_cap FROM capsters c WHERE c.id = p_capster_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kapster tidak ditemukan.';
    END IF;

    IF v_cap.auth_user_id IS NOT NULL THEN
        RAISE EXCEPTION 'Kapster % sudah punya akun. Pakai penggantian sandi.', v_cap.name;
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v_mail) THEN
        RAISE EXCEPTION 'Email % sudah dipakai akun lain.', v_mail;
    END IF;

    -- ── Akun ────────────────────────────────────────────────────────────────
    -- Kolom token WAJIB '' dan bukan NULL: GoTrue menolak membaca NULL di
    -- sana, dan akunnya lalu tidak pernah bisa masuk ("Database error
    -- querying schema"). Lihat kepala berkas ini.
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        confirmation_token, recovery_token,
        email_change_token_new, email_change,
        created_at, updated_at
    ) VALUES (
        v_uid,
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', v_mail,
        extensions.crypt(p_password, extensions.gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        jsonb_build_object('full_name', v_cap.name),
        '', '',
        '', '',
        now(), now()
    );

    -- Tanpa baris identitas, akunnya ada tetapi tidak pernah bisa masuk.
    INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id,
        last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(), v_uid,
        jsonb_build_object('sub', v_uid::TEXT, 'email', v_mail),
        'email', v_uid::TEXT,
        NULL, now(), now()
    );

    -- ── Peran dan penautan ──────────────────────────────────────────────────
    INSERT INTO profiles (id, full_name, role, is_active)
    VALUES (v_uid, v_cap.name, 'capster', TRUE);

    UPDATE capsters SET auth_user_id = v_uid WHERE id = p_capster_id;

    RETURN QUERY SELECT v_cap.name, v_mail;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) TO authenticated;

-- ── Sesudah dijalankan ──────────────────────────────────────────────────────
-- Harus mengembalikan 0 baris. Bila masih ada, akun itu belum tersentuh
-- bagian 1 di atas.
--
--   select email from auth.users
--    where confirmation_token is null or recovery_token is null
--       or email_change_token_new is null or email_change is null;
