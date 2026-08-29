-- ==============================================================================
-- MIGRASI 11 — Menutup Kebocoran Hash PIN
--
-- TEMUAN
--   Kolom pin_hash ikut terkirim ke klien saat owner memanggil
--   /rest/v1/cashiers?select=*. Hash-nya bcrypt biaya 6. Dengan hash di
--   tangan, seluruh 10.000 kemungkinan PIN 4 digit dapat dicoba secara
--   luring — diukur langsung: ketiga PIN pulih dalam 92 detik. Pembatas
--   5 percobaan per menit di verify_cashier_pin sepenuhnya terlewati,
--   karena penyerang tidak lagi perlu bertanya ke server.
--
-- MENGAPA INI PENTING MESKI HANYA OWNER YANG BISA MEMBACANYA
--   Seluruh gunanya PIN adalah pertanggungjawaban: setiap transaksi punya
--   nama orang di belakangnya. Bila owner dapat memulihkan PIN Ahmad, owner
--   dapat bertransaksi sebagai Ahmad, dan jejak audit menuding orang yang
--   salah. Yang rusak bukan kerahasiaan owner — melainkan kemampuan sistem
--   membuktikan siapa melakukan apa.
--
-- DUA LAPIS PERBAIKAN
--   1. Hash tidak pernah keluar dari basis data. Hak baca kolom dicabut,
--      sehingga select=* pun tidak menyertakannya.
--   2. Biaya bcrypt dinaikkan dari 6 ke 11 untuk PIN yang dibuat setelah ini.
--      Lapis pertama yang sesungguhnya menutup celah; lapis kedua memperkecil
--      kerugian bila hash bocor lewat jalan lain di kemudian hari.
-- ==============================================================================

-- 1. HASH TIDAK BOLEH TERBACA SIAPA PUN LEWAT API ------------------------------
-- Hak diberikan per kolom. Fungsi SECURITY DEFINER (verify_cashier_pin,
-- upsert_cashier) tetap dapat membacanya karena berjalan sebagai pemilik.
REVOKE SELECT ON cashiers FROM anon, authenticated;
GRANT SELECT (id, name, is_active, created_at) ON cashiers TO authenticated;

-- Kolom lain tetap dapat ditulis owner lewat RPC; penulisan langsung
-- ke pin_hash tidak pernah dibutuhkan klien.
REVOKE INSERT, UPDATE ON cashiers FROM anon, authenticated;
GRANT UPDATE (name, is_active) ON cashiers TO authenticated;
GRANT DELETE ON cashiers TO authenticated;

-- 2. BIAYA BCRYPT LEBIH MAHAL UNTUK PIN BARU ----------------------------------
CREATE OR REPLACE FUNCTION upsert_cashier(
    p_name TEXT,
    p_pin  TEXT DEFAULT NULL,
    p_id   UUID DEFAULT NULL
)
RETURNS TABLE (id UUID, name VARCHAR, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola data kasir.';
    END IF;
    IF p_pin IS NOT NULL AND p_pin !~ '^[0-9]{4,8}$' THEN
        RAISE EXCEPTION 'PIN harus 4 sampai 8 digit angka.';
    END IF;

    IF p_id IS NULL THEN
        IF p_pin IS NULL THEN
            RAISE EXCEPTION 'PIN wajib diisi untuk kasir baru.';
        END IF;
        IF EXISTS (SELECT 1 FROM cashiers c WHERE c.pin_hash = extensions.crypt(p_pin, c.pin_hash)) THEN
            RAISE EXCEPTION 'PIN itu sudah dipakai kasir lain. Pakai PIN yang berbeda.';
        END IF;
        -- Biaya 11: sekitar 32x lebih mahal dari sebelumnya
        INSERT INTO cashiers (name, pin_hash)
        VALUES (p_name, extensions.crypt(p_pin, extensions.gen_salt('bf', 11)))
        RETURNING cashiers.id INTO v_id;
    ELSE
        IF p_pin IS NOT NULL AND EXISTS (
            SELECT 1 FROM cashiers c
             WHERE c.id <> p_id AND c.pin_hash = extensions.crypt(p_pin, c.pin_hash)
        ) THEN
            RAISE EXCEPTION 'PIN itu sudah dipakai kasir lain. Pakai PIN yang berbeda.';
        END IF;
        UPDATE cashiers SET
            name     = p_name,
            pin_hash = CASE WHEN p_pin IS NULL THEN cashiers.pin_hash
                            ELSE extensions.crypt(p_pin, extensions.gen_salt('bf', 11)) END
        WHERE cashiers.id = p_id
        RETURNING cashiers.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Kasir tidak ditemukan.'; END IF;
    END IF;

    RETURN QUERY SELECT c.id, c.name, c.is_active FROM cashiers c WHERE c.id = v_id;
END $$;

GRANT EXECUTE ON FUNCTION upsert_cashier(TEXT, TEXT, UUID) TO authenticated;
