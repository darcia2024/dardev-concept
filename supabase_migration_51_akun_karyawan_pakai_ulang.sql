-- ==============================================================================
-- MIGRASI 51 - owner_buat_akun_capster: perbaikan 49 dipulihkan, dan akun
--              karyawan yang tidak tertaut dapat dipakai ulang
--
-- DUA HAL YANG DITEMUKAN DI PRODUKSI (29 September 2026)
--
-- 1. Perbaikan migrasi 49 tidak berlaku. pg_get_functiondef menunjukkan fungsi
--    yang aktif masih versi migrasi 47, sehingga tombol "Buat" kembali gagal
--    dengan "duplicate key value violates unique constraint profiles_pkey"
--    untuk email apa pun. Penyebab yang paling mungkin: berkas 47 dijalankan
--    lagi sesudah 49. Keduanya mendefinisikan fungsi yang sama dengan
--    CREATE OR REPLACE, jadi yang terakhir dijalankan yang menang — tanpa
--    peringatan apa pun.
--
--    Migrasi ini membawa perbaikan 49 utuh. Menjalankannya memulihkan fungsi
--    yang benar, sudah atau belum 49 pernah jalan.
--
--    JANGAN jalankan ulang berkas 47 atau 49 sesudah ini. Keduanya akan
--    menimpa fungsi ini dengan versi lamanya.
--
-- 2. Akun karyawan yang dilepas tidak dapat dipakai lagi. owner_lepas_akun_
--    karyawan (migrasi 48) sengaja tidak menghapus akunnya — riwayat dan
--    kredensialnya tetap ada — dan komentarnya menjanjikan "akun yang sama
--    dapat ditautkan lagi". Jalur untuk itu dulu ada di Edge Function yang
--    kemudian dibuang, sehingga janji itu tidak punya tombol.
--
--    Kejadiannya: akun habibah@underrated.com dilepas dari baris Habibah yang
--    lama, baris itu dihapus, Habibah didaftarkan ulang — dan "Buat" menolak
--    karena emailnya sudah dipakai. Dipakai oleh akun yang tidak tertaut ke
--    siapa pun.
--
-- PERILAKU BARU UNTUK EMAIL YANG SUDAH ADA
--
--   * Milik akun karyawan yang TIDAK TERTAUT ke baris mana pun
--       -> akun itu ditautkan ke karyawan ini, sandinya diganti dengan yang
--          diketik owner, dan perannya dipastikan 'capster'.
--   * Sudah tertaut ke karyawan lain
--       -> ditolak, dengan nama karyawannya.
--   * Milik owner atau perangkat POS
--       -> ditolak. Jalur ini tidak boleh menjadi cara mengambil alih akun
--          yang bukan akun karyawan, seberapa pun emailnya ditebak.
--
-- Peran 'kasir' ikut boleh dipakai ulang. Kasir di sistem ini tidak punya
-- akun login sama sekali (migrasi 02 — kasir memakai PIN di perangkat POS),
-- jadi akun berperan kasir hanya lahir dari kekeliruan: akun karyawan yang
-- dibuat lewat Dashboard tanpa metadata role, atau versi 47 fungsi ini yang
-- lupa menulis role. Menolaknya akan membiarkan kekeliruan itu terkunci.
-- ==============================================================================

-- Tipe keluaran bertambah satu kolom, jadi versi lama dibuang lebih dulu.
DROP FUNCTION IF EXISTS owner_buat_akun_capster(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION owner_buat_akun_capster(
    p_capster_id UUID,
    p_email      TEXT,
    p_password   TEXT
)
RETURNS TABLE (capster_name VARCHAR, email TEXT, akun_lama BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions
AS $function$
DECLARE
    v_cap    capsters%ROWTYPE;
    v_mail   TEXT := lower(btrim(p_email));
    v_uid    UUID;
    v_peran  TEXT;
    v_pemilik VARCHAR;
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

    -- Menolak menimpa. Kapster yang sudah punya akun diubah sandinya lewat
    -- owner_set_capster_password, bukan dibuatkan akun kedua yang menggantung.
    IF v_cap.auth_user_id IS NOT NULL THEN
        RAISE EXCEPTION 'Kapster % sudah punya akun. Pakai penggantian sandi.', v_cap.name;
    END IF;

    -- ── Email yang sudah ada ────────────────────────────────────────────────
    SELECT u.id INTO v_uid FROM auth.users u WHERE lower(u.email) = v_mail LIMIT 1;

    IF v_uid IS NOT NULL THEN
        SELECT k.name INTO v_pemilik FROM capsters k WHERE k.auth_user_id = v_uid LIMIT 1;
        IF v_pemilik IS NOT NULL THEN
            RAISE EXCEPTION 'Email % sudah dipakai karyawan %.', v_mail, v_pemilik;
        END IF;

        SELECT pr.role::TEXT INTO v_peran FROM profiles pr WHERE pr.id = v_uid;
        IF v_peran IS NULL OR v_peran NOT IN ('capster', 'kasir') THEN
            -- Owner, perangkat POS, atau akun tanpa profil sama sekali.
            RAISE EXCEPTION 'Email % sudah dipakai akun lain yang bukan akun karyawan.', v_mail;
        END IF;

        -- Akun karyawan yang tidak dipakai siapa pun: dipakai ulang. Sandinya
        -- diganti karena sandi lamanya belum tentu diketahui siapa pun lagi;
        -- yang diketik owner di layar inilah yang akan ia bacakan.
        UPDATE auth.users
           SET encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
               email_confirmed_at = COALESCE(email_confirmed_at, now()),
               raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::JSONB)
                                    || jsonb_build_object('full_name', v_cap.name, 'role', 'capster'),
               updated_at = now()
         WHERE id = v_uid;

        -- Akun yang dibuat lewat jalur lama bisa saja tanpa baris identitas,
        -- dan tanpa itu ia tidak pernah bisa masuk.
        IF NOT EXISTS (SELECT 1 FROM auth.identities i
                        WHERE i.user_id = v_uid AND i.provider = 'email') THEN
            INSERT INTO auth.identities (
                id, user_id, identity_data, provider, provider_id,
                last_sign_in_at, created_at, updated_at
            ) VALUES (
                gen_random_uuid(), v_uid,
                jsonb_build_object('sub', v_uid::TEXT, 'email', v_mail),
                'email', v_uid::TEXT,
                NULL, now(), now()
            );
        END IF;

        UPDATE profiles
           SET role = 'capster', full_name = v_cap.name, is_active = TRUE
         WHERE id = v_uid;

        UPDATE capsters SET auth_user_id = v_uid WHERE id = p_capster_id;

        RETURN QUERY SELECT v_cap.name, v_mail, TRUE;
        RETURN;
    END IF;

    -- ── Akun baru ───────────────────────────────────────────────────────────
    v_uid := gen_random_uuid();

    -- role ikut ditulis ke metadata: trigger on_auth_user_created membacanya,
    -- dan tanpanya ia memberi peran 'kasir' (migrasi 49).
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
    ) VALUES (
        v_uid,
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', v_mail,
        extensions.crypt(p_password, extensions.gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        jsonb_build_object('full_name', v_cap.name, 'role', 'capster'),
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

    -- ON CONFLICT, bukan INSERT polos: trigger on_auth_user_created sudah
    -- membuat barisnya. INSERT polos di sini adalah galat profiles_pkey yang
    -- membuat tombol Buat selalu gagal (migrasi 49).
    INSERT INTO profiles (id, full_name, role, is_active)
    VALUES (v_uid, v_cap.name, 'capster', TRUE)
    ON CONFLICT (id) DO UPDATE
        SET full_name = EXCLUDED.full_name,
            role      = 'capster',
            is_active = TRUE;

    UPDATE capsters SET auth_user_id = v_uid WHERE id = p_capster_id;

    RETURN QUERY SELECT v_cap.name, v_mail, FALSE;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) TO authenticated;
