-- ══════════════════════════════════════════════════════════════════════════
-- 41 · Owner mengisi nomor WhatsApp capster dari halaman pengaturan
-- ══════════════════════════════════════════════════════════════════════════
-- Kolom capsters.phone sudah ada sejak awal, tetapi tidak pernah ada jalan
-- bagi owner untuk mengisinya. Selama itu belum ada, notifikasi capster
-- (migrasi 40) bergantung pada nomor yang hanya dapat disunting lewat
-- dashboard Supabase — yang berarti pemilik toko tidak dapat mengurusnya
-- sendiri saat ada capster baru.
--
-- Nomor disimpan dalam satu bentuk saja: 62xxxxxxxxxx. Menerima campuran
-- '08...', '+62...', dan '62...' berarti menunda pertanyaan "yang mana yang
-- benar" sampai ke saat pengiriman, dan di sana kegagalannya sunyi.
-- ══════════════════════════════════════════════════════════════════════════


-- ── Penormal nomor ─────────────────────────────────────────────────────────
-- Dipakai bersama oleh penyunting dan pemeriksa, supaya keduanya tidak
-- pernah berbeda pendapat tentang apa yang disebut nomor yang sah.
CREATE OR REPLACE FUNCTION normalkan_nomor_wa(p_nomor TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $function$
DECLARE
    v TEXT;
BEGIN
    v := regexp_replace(COALESCE(p_nomor, ''), '[^0-9]', '', 'g');
    IF v = '' THEN RETURN NULL; END IF;

    IF left(v, 1) = '0' THEN
        v := '62' || substr(v, 2);
    ELSIF left(v, 2) <> '62' THEN
        -- Nomor tanpa awalan negara dianggap nomor Indonesia yang kehilangan
        -- angka nolnya, bukan nomor luar negeri: tidak ada capster di luar
        -- negeri, dan menebak sebaliknya menghasilkan nomor yang mustahil.
        v := '62' || v;
    END IF;

    IF v !~ '^62[0-9]{8,15}$' THEN RETURN NULL; END IF;
    RETURN v;
END $function$;

REVOKE EXECUTE ON FUNCTION normalkan_nomor_wa(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION normalkan_nomor_wa(TEXT) TO authenticated;


-- ── Daftar staf kini menyertakan nomornya ──────────────────────────────────
-- DROP diperlukan karena kolom keluaran bertambah. Supabase memberi anon hak
-- EXECUTE pada setiap fungsi yang baru dibuat, jadi haknya ditulis ulang
-- secara eksplisit di bawah — bukan hanya dicabut dari PUBLIC.
DROP FUNCTION IF EXISTS owner_staff_list();

CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (capster_id UUID, name CHARACTER VARYING, email TEXT,
               is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $function$
    SELECT c.id, c.name, u.email::TEXT, c.is_active, (c.auth_user_id IS NOT NULL), c.phone
      FROM capsters c
      LEFT JOIN auth.users u ON u.id = c.auth_user_id
     WHERE is_owner()
     ORDER BY c.name;
$function$;

REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_staff_list() TO authenticated;


-- ── Penyuntingnya ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_set_capster_phone(p_capster_id UUID, p_telepon TEXT)
RETURNS TABLE (capster_name CHARACTER VARYING, telepon CHARACTER VARYING)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_nomor TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah nomor capster.';
    END IF;

    -- Kosong berarti sengaja dikosongkan: capster yang tidak ingin dihubungi
    -- lewat WhatsApp harus punya cara menyatakannya.
    IF COALESCE(btrim(p_telepon), '') = '' THEN
        v_nomor := NULL;
    ELSE
        v_nomor := normalkan_nomor_wa(p_telepon);
        IF v_nomor IS NULL THEN
            RAISE EXCEPTION 'Nomor tidak dikenali. Contoh yang benar: 081297754581.';
        END IF;
    END IF;

    RETURN QUERY
    UPDATE capsters c SET phone = v_nomor
     WHERE c.id = p_capster_id
     RETURNING c.name, c.phone;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capster tidak ditemukan.';
    END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_set_capster_phone(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_set_capster_phone(UUID, TEXT) TO authenticated;


COMMENT ON COLUMN capsters.phone IS
  'Nomor WhatsApp capster dalam bentuk 62xxxxxxxxxx. Hanya dipakai server-side '
  'sebagai tujuan notifikasi booking; tidak pernah dikirim ke halaman publik.';
