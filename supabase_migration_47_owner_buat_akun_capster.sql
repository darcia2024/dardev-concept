-- =============================================================================
-- 47 · OWNER MEMBUAT SENDIRI AKUN KAPSTER
--
-- Menambah kapster di master data hanya mengerjakan sepertiga pekerjaan. Agar
-- ia dapat absen, tiga hal harus tersambung: baris di capsters, akun di
-- auth.users, dan profil ber-peran 'capster'. Dua yang terakhir selama ini
-- dikerjakan manual oleh pengembang, sehingga layar owner berbunyi "buatkan
-- dulu lewat Dardev" — dan tiap kapster baru menunggu orang lain.
--
-- MENGAPA MENULIS LANGSUNG KE auth.users. Membuat akun lewat jalur resmi
-- menuntut service_role key, dan kunci itu tidak boleh pernah berada di
-- halaman yang dibuka peramban: siapa pun yang membaca sumbernya menguasai
-- seluruh basis data. Jalur resmi lain adalah Edge Function, yang menuntut
-- penerapan terpisah di luar repositori ini. Fungsi SECURITY DEFINER menaruh
-- kuncinya di tempat yang tidak pernah meninggalkan server.
--
-- HARGANYA, DENGAN JUJUR. auth.users milik Supabase, bukan milik kita. Bila
-- mereka mengubah bentuknya pada pembaruan mendatang, fungsi ini akan GAGAL
-- dengan galat — bukan merusak data, sebab seluruh badan fungsi plpgsql
-- berjalan sebagai satu transaksi. Yang setengah jadi tidak pernah tersimpan.
--
-- Pembuatan sandi memakai extensions.crypt, sama persis dengan yang sudah
-- dipakai owner_set_capster_password sejak migrasi 12 dan terbukti jalan di
-- basis data ini. Bukan resep dari luar.
-- =============================================================================

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

    -- Menolak menimpa. Kapster yang sudah punya akun diubah sandinya lewat
    -- owner_set_capster_password, bukan dibuatkan akun kedua yang menggantung.
    IF v_cap.auth_user_id IS NOT NULL THEN
        RAISE EXCEPTION 'Kapster % sudah punya akun. Pakai penggantian sandi.', v_cap.name;
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v_mail) THEN
        RAISE EXCEPTION 'Email % sudah dipakai akun lain.', v_mail;
    END IF;

    -- ── Akun ────────────────────────────────────────────────────────────────
    -- email_confirmed_at diisi sekarang: tidak ada kotak surat sungguhan di
    -- balik alamat seperti amirul@underrated.com, jadi menunggu konfirmasi
    -- berarti akunnya tidak akan pernah dapat dipakai.
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
        jsonb_build_object('full_name', v_cap.name),
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
    -- Peran dipaku 'capster'. Fungsi ini tidak boleh menjadi jalan memunculkan
    -- owner atau kasir baru, seberapa pun parameternya diutak-atik.
    INSERT INTO profiles (id, full_name, role, is_active)
    VALUES (v_uid, v_cap.name, 'capster', TRUE);

    UPDATE capsters SET auth_user_id = v_uid WHERE id = p_capster_id;

    RETURN QUERY SELECT v_cap.name, v_mail;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) TO authenticated;
