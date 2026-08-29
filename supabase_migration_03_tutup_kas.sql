-- ==============================================================================
-- MIGRASI 03 — Tutup Kas Harian (Setoran Tunai Kasir)
--
-- Alur: kasir selesai bertugas -> menghitung fisik uang tunai -> menyetorkan
-- angkanya. Owner melihat perbandingan dan menyesuaikan bila ada selisih.
--
-- Prinsip yang menentukan bentuk berkas ini — HITUNGAN BUTA:
--   Kasir TIDAK BOLEH melihat angka yang diharapkan sistem sebelum menyetor.
--   Bila ia bisa melihatnya, hitungan itu berhenti menjadi kontrol: siapa pun
--   tinggal mengetik ulang angka yang sudah tertera. Karena itu:
--     * expected_amount dihitung di server saat penyetoran, bukan dikirim dulu
--       ke browser;
--     * RPC penyetoran mengembalikan konfirmasi saja — tanpa ekspektasi,
--       tanpa selisih;
--     * tabel ini tidak dapat dibaca perangkat kasir sama sekali (RLS).
--
--   Angka asli dari kasir tidak pernah ditimpa. Penyesuaian owner disimpan di
--   kolom terpisah agar jejak auditnya utuh.
-- ==============================================================================

-- 1. TABEL SETORAN ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cash_closings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_date date NOT NULL,

    cashier_ref_id UUID REFERENCES cashiers(id) ON DELETE SET NULL,
    cashier_name VARCHAR(150) NOT NULL,

    -- Diisi kasir
    counted_amount NUMERIC(12, 2) NOT NULL CHECK (counted_amount >= 0),
    cashier_notes TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Dihitung server saat penyetoran; kasir tidak pernah menerimanya
    expected_amount NUMERIC(12, 2) NOT NULL,
    tx_count INT NOT NULL DEFAULT 0,

    -- Diisi owner saat memeriksa. Angka kasir di atas tidak pernah diubah.
    owner_adjustment NUMERIC(12, 2) NOT NULL DEFAULT 0,
    owner_notes TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Satu setoran per kasir per hari operasional. Tanpa ini, kasir bisa menyetor
-- berulang kali dan meninggalkan catatan yang saling bertentangan.
CREATE UNIQUE INDEX IF NOT EXISTS idx_closing_unik
    ON cash_closings(business_date, cashier_ref_id);
CREATE INDEX IF NOT EXISTS idx_closing_tanggal ON cash_closings(business_date DESC);

-- Selisih selalu diturunkan, tidak pernah diketik manusia
CREATE OR REPLACE VIEW cash_closings_view AS
SELECT c.*,
       (c.counted_amount - c.expected_amount)                      AS difference,
       (c.counted_amount + c.owner_adjustment - c.expected_amount)  AS difference_after_adjust,
       CASE
           WHEN c.counted_amount = c.expected_amount THEN 'sesuai'
           WHEN c.counted_amount >  c.expected_amount THEN 'lebih'
           ELSE 'kurang'
       END AS status_selisih
  FROM cash_closings c;

-- 2. PENYETORAN OLEH KASIR ----------------------------------------------------
-- Mengembalikan konfirmasi saja. Tidak ada ekspektasi, tidak ada selisih.
CREATE OR REPLACE FUNCTION submit_cash_closing(
    p_cashier_id UUID,
    p_counted    NUMERIC,
    p_notes      TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    cashier_name VARCHAR,
    counted_amount NUMERIC,
    business_date date,
    submitted_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_cashier  cashiers%ROWTYPE;
    v_date     date := jakarta_today();
    v_expected NUMERIC(12,2);
    v_count    INT;
    v_id       UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Perangkat belum terdaftar.';
    END IF;
    IF p_counted IS NULL OR p_counted < 0 THEN
        RAISE EXCEPTION 'Jumlah uang tidak boleh kosong atau negatif.';
    END IF;

    SELECT * INTO v_cashier FROM cashiers WHERE cashiers.id = p_cashier_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kasir tidak dikenali. Masukkan PIN ulang.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM cash_closings cc
         WHERE cc.business_date = v_date AND cc.cashier_ref_id = p_cashier_id
    ) THEN
        RAISE EXCEPTION 'Anda sudah menyetor hitungan hari ini. Hubungi owner bila perlu diperbaiki.';
    END IF;

    -- Uang yang seharusnya ada di laci = seluruh transaksi TUNAI kasir ini
    -- hari ini. Kembalian sudah diserahkan ke pelanggan, sehingga yang
    -- tertinggal adalah final_amount, bukan cash_paid.
    SELECT COALESCE(SUM(t.final_amount), 0), COUNT(*)
      INTO v_expected, v_count
      FROM transactions t
     WHERE t.business_date = v_date
       AND t.cashier_ref_id = p_cashier_id
       AND t.payment_method = 'Tunai';

    INSERT INTO cash_closings (
        business_date, cashier_ref_id, cashier_name,
        counted_amount, cashier_notes, expected_amount, tx_count
    ) VALUES (
        v_date, v_cashier.id, v_cashier.name,
        p_counted, NULLIF(btrim(p_notes), ''), v_expected, v_count
    )
    RETURNING cash_closings.id INTO v_id;

    RETURN QUERY
    SELECT c.id, c.cashier_name, c.counted_amount, c.business_date, c.submitted_at
      FROM cash_closings c WHERE c.id = v_id;
END $$;

-- 3. STATUS SETORAN SENDIRI ---------------------------------------------------
-- Kasir boleh tahu ia sudah menyetor dan berapa yang ia setorkan,
-- tetapi tetap tidak boleh tahu ekspektasi maupun selisihnya.
CREATE OR REPLACE FUNCTION my_closing_status(p_cashier_id UUID)
RETURNS TABLE (
    sudah_setor BOOLEAN,
    counted_amount NUMERIC,
    submitted_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Perangkat belum terdaftar.';
    END IF;
    RETURN QUERY
    SELECT true, c.counted_amount, c.submitted_at
      FROM cash_closings c
     WHERE c.business_date = jakarta_today()
       AND c.cashier_ref_id = p_cashier_id
     LIMIT 1;
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::NUMERIC, NULL::TIMESTAMPTZ;
    END IF;
END $$;

-- 4. PEMERIKSAAN OLEH OWNER ---------------------------------------------------
CREATE OR REPLACE FUNCTION review_cash_closing(
    p_id         UUID,
    p_adjustment NUMERIC DEFAULT 0,
    p_notes      TEXT DEFAULT NULL
)
RETURNS TABLE (id UUID, reviewed_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh memeriksa setoran kas.';
    END IF;

    UPDATE cash_closings SET
        owner_adjustment = COALESCE(p_adjustment, 0),
        owner_notes      = NULLIF(btrim(p_notes), ''),
        reviewed_by      = auth.uid(),
        reviewed_at      = now()
    WHERE cash_closings.id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Setoran tidak ditemukan.';
    END IF;

    RETURN QUERY
    SELECT c.id, c.reviewed_at FROM cash_closings c WHERE c.id = p_id;
END $$;

-- 5. RLS ----------------------------------------------------------------------
ALTER TABLE cash_closings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_all ON cash_closings;
CREATE POLICY owner_all ON cash_closings
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());

-- Sengaja tidak ada policy untuk perangkat kasir. Penyetoran berjalan lewat
-- submit_cash_closing() yang SECURITY DEFINER, sehingga kasir dapat menyetor
-- tanpa pernah bisa membaca ekspektasi, selisih, atau setoran kasir lain.

-- View mewarisi hak tabel di baliknya; batasi juga secara eksplisit.
REVOKE ALL ON cash_closings_view FROM anon, authenticated;
GRANT SELECT ON cash_closings_view TO authenticated;
ALTER VIEW cash_closings_view SET (security_invoker = on);
