-- !!! JANGAN DIJALANKAN ULANG. owner_buat_akun_capster di berkas ini sudah
-- !!! digantikan migrasi 51. Menjalankan berkas ini sekarang akan MENIMPA versi
-- !!! yang benar dengan versi lama tanpa peringatan apa pun — itu pernah terjadi
-- !!! di produksi pada 29 September 2026, dan tombol Buat akun kembali rusak.
-- !!! Berkas ini disimpan sebagai riwayat, bukan untuk dijalankan.
-- ==============================================================================
-- MIGRASI 49 - Perbaikan owner_buat_akun_capster: bentrok dengan trigger profil
--
-- GEJALANYA
--
--   Gagal: duplicate key value violates unique constraint "profiles_pkey"
--
-- Tombol "Buat" pada kartu kapster selalu gagal. Tidak kadang-kadang —
-- selalu, sejak migrasi 47 dipasang.
--
-- SEBABNYA
--
-- supabase_schema.sql memasang trigger on_auth_user_created pada auth.users.
-- Tiap baris baru di sana otomatis membuatkan barisnya sendiri di profiles:
--
--     INSERT INTO public.profiles (id, full_name, role)
--     VALUES (NEW.id, ..., COALESCE((raw_user_meta_data->>'role')::staff_role,
--                                   'kasir'))
--     ON CONFLICT (id) DO NOTHING;
--
-- Migrasi 47 tidak mengetahui trigger itu. Ia menyisipkan ke auth.users —
-- trigger langsung membuat profilnya — lalu menyisipkan ke profiles sekali
-- lagi untuk id yang sama, tanpa ON CONFLICT. Tabrakan itulah galatnya.
--
-- CACAT KEDUA, YANG BERSEMBUNYI DI BALIK YANG PERTAMA
--
-- Metadata yang ditulis migrasi 47 hanya memuat full_name, tanpa role. Maka
-- trigger memberi profil itu peran 'kasir', bukan 'capster'. Baris INSERT
-- yang gagal tadi justru baris yang seharusnya membetulkannya.
--
-- Artinya seandainya bentrokan pertama diperbaiki sendirian — misalnya dengan
-- menghapus INSERT yang kedua — akunnya akan terbentuk sebagai kasir dan
-- gagal secara diam-diam: kapster tidak bisa absen, penggantian sandi ditolak
-- dengan "Akun itu bukan akun capster", dan tidak ada yang menunjuk sebabnya.
-- Keduanya harus diperbaiki bersama.
--
-- TIDAK ADA YANG PERLU DIBERESKAN DARI KEGAGALAN SEBELUMNYA
--
-- Seluruh badan fungsi plpgsql berjalan sebagai satu transaksi. Ketika INSERT
-- ke profiles melempar, sisipan ke auth.users dan auth.identities ikut
-- dibatalkan. Tidak ada akun setengah jadi, dan capsters.auth_user_id tidak
-- pernah tersentuh.
--
-- PERBAIKANNYA MEMAKAI DUA LAPIS, BUKAN SATU
--
--   1. role ikut ditulis ke raw_user_meta_data, sehingga trigger membuat
--      profil yang sudah benar sejak awal.
--   2. INSERT ke profiles menjadi ON CONFLICT DO UPDATE, sehingga fungsi ini
--      tetap menjadi penentu akhir perannya — baik ketika trigger sudah
--      mendahuluinya, maupun bila trigger itu suatu saat dicabut.
--
-- Satu lapis saja cukup untuk membuatnya berjalan hari ini. Dua lapis membuat
-- ia tetap benar ketika salah satu asumsinya berubah.
-- ==============================================================================

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
    --
    -- role IKUT DITULIS di raw_user_meta_data. Trigger on_auth_user_created
    -- membaca kunci itu; tanpanya ia memberi peran 'kasir', dan kapsternya
    -- tidak akan pernah bisa absen.
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

    -- ── Peran dan penautan ──────────────────────────────────────────────────
    -- Peran dipaku 'capster'. Fungsi ini tidak boleh menjadi jalan memunculkan
    -- owner atau kasir baru, seberapa pun parameternya diutak-atik.
    --
    -- ON CONFLICT DO UPDATE, bukan INSERT polos: trigger on_auth_user_created
    -- hampir pasti sudah membuat barisnya beberapa mikrodetik lalu. INSERT
    -- polos di sini bertabrakan dengan barisnya sendiri — itulah galat
    -- profiles_pkey yang membuat tombol Buat selalu gagal.
    INSERT INTO profiles (id, full_name, role, is_active)
    VALUES (v_uid, v_cap.name, 'capster', TRUE)
    ON CONFLICT (id) DO UPDATE
        SET full_name = EXCLUDED.full_name,
            role      = 'capster',
            is_active = TRUE;

    UPDATE capsters SET auth_user_id = v_uid WHERE id = p_capster_id;

    RETURN QUERY SELECT v_cap.name, v_mail;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_buat_akun_capster(UUID, TEXT, TEXT) TO authenticated;


-- ==============================================================================
-- MEMBETULKAN AKUN YANG TERLANJUR BERPERAN 'kasir'
--
-- Bila ada akun yang sudah tertaut ke sebuah baris capsters tetapi profilnya
-- berperan kasir — akibat jalur lama, atau pembuatan manual lewat Supabase
-- Dashboard tanpa mengisi User Metadata — ia tidak akan bisa absen dan
-- penggantian sandinya ditolak. Keduanya gagal tanpa menyebut sebabnya.
--
-- Sasarannya sengaja sempit: HANYA yang sudah tertaut ke capsters, dan HANYA
-- yang sedang berperan kasir. Akun owner dan akun perangkat POS tidak pernah
-- tertaut ke capsters, jadi tidak mungkin ikut tersentuh.
-- ==============================================================================
UPDATE profiles p
   SET role = 'capster'
  FROM capsters c
 WHERE c.auth_user_id = p.id
   AND p.role = 'kasir';
