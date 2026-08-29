-- ==============================================================================
-- MIGRASI 14 — Hapus Member Tanpa Menghapus Omzet
--
-- DUA PRINSIP YANG MENGATUR SELURUH BERKAS INI
--
-- 1. Menghapus member TIDAK BOLEH menghapus omzet. Transaksinya benar-benar
--    terjadi dan uangnya benar-benar masuk. Yang dihapus hanyalah hubungan
--    keanggotaannya: poin, riwayat poin, dan klaim reward. Baris transaksinya
--    tetap tinggal beserta nama dan nomor yang tersimpan di dalamnya, sehingga
--    laporan omzet bulan itu tidak berubah hanya karena seorang member dihapus.
--
-- 2. Penghapusan selalu terarsip. Member yang dihapus tersimpan utuh beserta
--    alasan dan pelakunya, termasuk berapa transaksi yang terlepas darinya.
-- ==============================================================================


-- ==============================================================================
-- 1. ARSIP MEMBER TERHAPUS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS deleted_members (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_id    UUID        NOT NULL,
    name           VARCHAR(150),
    phone_wa       VARCHAR(30),
    member_code    VARCHAR(20),
    tier           TEXT,
    points_balance INT,
    lifetime_points INT,
    visit_count    INT,
    total_spend    NUMERIC(14,2),
    jumlah_transaksi INT,          -- transaksinya TIDAK ikut dihapus
    isi_lengkap    JSONB       NOT NULL,
    alasan         TEXT,
    dihapus_oleh   UUID        NOT NULL REFERENCES auth.users(id),
    dihapus_pada   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE deleted_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_baca_arsip_member ON deleted_members;
CREATE POLICY owner_baca_arsip_member ON deleted_members
    FOR SELECT TO authenticated USING (is_owner());


-- ==============================================================================
-- 2. DAFTAR MEMBER UNTUK OWNER
--
-- Disertai jumlah transaksinya, supaya owner tahu apa yang akan terputus
-- sebelum menekan hapus.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_members_list(p_limit INT DEFAULT 200)
RETURNS TABLE (
    member_id      UUID,
    name           VARCHAR,
    phone_wa       VARCHAR,
    tier           TEXT,
    points_balance INT,
    visit_count    INT,
    total_spend    NUMERIC,
    jumlah_transaksi BIGINT,
    terakhir       DATE
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT m.id, m.name, m.phone_wa, m.tier::TEXT, m.points_balance,
           m.visit_count, m.total_spend,
           COUNT(t.id), MAX(t.business_date)
      FROM members m
      LEFT JOIN transactions t ON t.member_id = m.id
     WHERE is_owner()
     GROUP BY m.id
     ORDER BY m.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 500));
$$;

GRANT EXECUTE ON FUNCTION owner_members_list(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION owner_members_list(INT) FROM anon;


-- ==============================================================================
-- 3. HAPUS MEMBER — TANPA MENYENTUH OMZET
-- ==============================================================================
CREATE OR REPLACE FUNCTION delete_member(
    p_member_id UUID,
    p_alasan    TEXT DEFAULT NULL
)
RETURNS TABLE (
    name             VARCHAR,
    phone_wa         VARCHAR,
    transaksi_dilepas BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_m    members%ROWTYPE;
    v_jml  BIGINT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus member.';
    END IF;

    SELECT * INTO v_m FROM members m WHERE m.id = p_member_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Member tidak ditemukan. Mungkin sudah dihapus sebelumnya.';
    END IF;

    SELECT COUNT(*) INTO v_jml FROM transactions t WHERE t.member_id = p_member_id;

    INSERT INTO deleted_members (
        original_id, name, phone_wa, member_code, tier, points_balance,
        lifetime_points, visit_count, total_spend, jumlah_transaksi,
        isi_lengkap, alasan, dihapus_oleh
    ) VALUES (
        v_m.id, v_m.name, v_m.phone_wa, v_m.member_code, v_m.tier::TEXT,
        v_m.points_balance, v_m.lifetime_points, v_m.visit_count, v_m.total_spend,
        v_jml, to_jsonb(v_m), NULLIF(btrim(COALESCE(p_alasan, '')), ''), auth.uid()
    );

    -- Transaksinya DILEPAS, bukan dihapus. Nama dan nomor sudah tersimpan pada
    -- baris transaksi itu sendiri, sehingga laporan omzet tetap utuh dan
    -- nota lama masih bisa dibaca. Menghapus member tidak boleh mengubah
    -- angka penjualan bulan yang sudah lewat.
    UPDATE transactions SET member_id = NULL WHERE member_id = p_member_id;

    DELETE FROM point_ledger  WHERE member_id = p_member_id;
    DELETE FROM reward_claims WHERE member_id = p_member_id;
    DELETE FROM members       WHERE id = p_member_id;

    RETURN QUERY SELECT v_m.name, v_m.phone_wa, v_jml;
END $$;

GRANT EXECUTE ON FUNCTION delete_member(UUID, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION delete_member(UUID, TEXT) FROM anon;


-- ==============================================================================
-- 4. DAFTAR ARSIP MEMBER
-- ==============================================================================
CREATE OR REPLACE FUNCTION deleted_members_list(p_limit INT DEFAULT 50)
RETURNS TABLE (
    name         VARCHAR,
    phone_wa     VARCHAR,
    points_balance INT,
    jumlah_transaksi INT,
    alasan       TEXT,
    dihapus_pada TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT d.name, d.phone_wa, d.points_balance, d.jumlah_transaksi,
           d.alasan, d.dihapus_pada
      FROM deleted_members d
     WHERE is_owner()
     ORDER BY d.dihapus_pada DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION deleted_members_list(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION deleted_members_list(INT) FROM anon;
