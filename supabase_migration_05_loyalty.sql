-- ==============================================================================
-- MIGRASI 05 — Loyalty Engine (Fase 1)
--
-- Menyalakan mesin poin: cashback otomatis, penukaran poin jadi diskon,
-- 5-tier naik level otomatis, dan buku besar mutasi poin.
--
-- Dua keputusan yang menentukan bentuk berkas ini:
--
-- 1. ATURAN DISIMPAN SEBAGAI DATA, BUKAN KODE.
--    Rasio poin dan syarat naik tier belum dikonfirmasi klien. Menuliskannya
--    sebagai konstanta berarti setiap perubahan menuntut rilis ulang. Di sini
--    keduanya menjadi baris yang dapat diubah owner dari dashboard.
--
-- 2. SALDO POIN TIDAK PERNAH DIHITUNG DARI PENJUMLAHAN RIWAYAT.
--    Penukaran memakai penguncian baris (FOR UPDATE) di dalam satu transaksi
--    basis data. Tanpa itu, dua perangkat kasir yang menukarkan poin pada
--    detik yang sama dapat membelanjakan saldo yang sama dua kali.
-- ==============================================================================

-- 1. PENGATURAN LOYALITAS (SATU BARIS) ----------------------------------------
CREATE TABLE IF NOT EXISTS loyalty_settings (
    id BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),   -- kunci: hanya satu baris

    -- "Setiap belanja Rp 10.000 memperoleh 1 poin"
    rupiah_per_point INT NOT NULL DEFAULT 10000 CHECK (rupiah_per_point > 0),
    -- "1 poin setara berapa rupiah diskon"
    rupiah_per_point_redeem INT NOT NULL DEFAULT 500 CHECK (rupiah_per_point_redeem > 0),

    min_redeem_points INT NOT NULL DEFAULT 10 CHECK (min_redeem_points >= 0),
    -- Batas diskon terhadap subtotal, menjaga transaksi tidak menjadi nol rupiah
    -- 25%: dipilih setelah skema bagi hasil 60-40 ditetapkan. Pada batas 50%
    -- dan diskon poin ditanggung toko, sisa toko untuk Speciality jatuh ke
    -- sekitar 1% dari harga — capster tetap menerima 40% penuh karena
    -- pekerjaannya penuh, sehingga seluruh diskon jatuh ke sisi toko.
    max_redeem_percent NUMERIC(5,2) NOT NULL DEFAULT 25.00
        CHECK (max_redeem_percent > 0 AND max_redeem_percent <= 100),

    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO loyalty_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- 2. SYARAT NAIK TIER ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS tier_rules (
    tier member_tier PRIMARY KEY,
    min_lifetime_points INT NOT NULL CHECK (min_lifetime_points >= 0),
    earn_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (earn_multiplier > 0),
    note TEXT
);

-- Angka sementara sampai klien mengonfirmasi (butir 07 addendum).
INSERT INTO tier_rules (tier, min_lifetime_points, earn_multiplier, note) VALUES
    ('Silver',   0,    1.00, 'Tier awal seluruh member baru'),
    ('Gold',     100,  1.10, 'Sementara — menunggu konfirmasi klien'),
    ('Platinum', 300,  1.25, 'Sementara — menunggu konfirmasi klien'),
    ('Infinite', 700,  1.50, 'Sementara — menunggu konfirmasi klien'),
    ('Black',    1500, 2.00, 'Sementara — menunggu konfirmasi klien')
ON CONFLICT (tier) DO NOTHING;

-- 3. KOLOM TAMBAHAN PADA MEMBER -----------------------------------------------
-- points_balance turun saat penukaran; tier tidak boleh ikut turun,
-- jadi peringkat memakai akumulasi seumur hidup yang terpisah.
ALTER TABLE members ADD COLUMN IF NOT EXISTS lifetime_points INT NOT NULL DEFAULT 0;
ALTER TABLE members ADD COLUMN IF NOT EXISTS member_code VARCHAR(12) UNIQUE;

-- Kode kartu: dipakai pada QR, tidak membocorkan id internal.
CREATE OR REPLACE FUNCTION generate_member_code()
RETURNS VARCHAR
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_code VARCHAR(12);
BEGIN
    LOOP
        -- Tanpa huruf/angka yang mudah tertukar saat dibacakan (0/O, 1/I)
        v_code := 'BK' || upper(
            translate(substr(encode(extensions.gen_random_bytes(6), 'base64'), 1, 8),
                      '+/=OI01lo', 'ABCDEFGHJ')
        );
        EXIT WHEN NOT EXISTS (SELECT 1 FROM members m WHERE m.member_code = v_code);
    END LOOP;
    RETURN v_code;
END $$;

UPDATE members SET member_code = generate_member_code() WHERE member_code IS NULL;

-- 4. PERHITUNGAN TIER ---------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_tier(p_lifetime_points INT)
RETURNS member_tier
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT tr.tier FROM tier_rules tr
     WHERE tr.min_lifetime_points <= COALESCE(p_lifetime_points, 0)
     ORDER BY tr.min_lifetime_points DESC
     LIMIT 1
$$;

-- 5. PENCARIAN MEMBER LEWAT KODE KARTU / QR -----------------------------------
CREATE OR REPLACE FUNCTION lookup_member_by_code(p_code TEXT)
RETURNS TABLE (
    name VARCHAR, phone_wa VARCHAR, tier member_tier,
    points_balance INT, visit_count INT, member_code VARCHAR
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    RETURN QUERY
    SELECT m.name, m.phone_wa, m.tier, m.points_balance, m.visit_count, m.member_code
      FROM members m WHERE m.member_code = upper(btrim(p_code)) LIMIT 1;
END $$;

-- Pencarian lewat nomor kini ikut mengembalikan saldo poin & kode kartu.
-- Bentuk kembaliannya berubah, jadi definisi lama harus dilepas dulu.
DROP FUNCTION IF EXISTS lookup_member(TEXT);
CREATE OR REPLACE FUNCTION lookup_member(p_phone TEXT)
RETURNS TABLE (
    name VARCHAR, tier member_tier, visit_count INT,
    points_balance INT, member_code VARCHAR
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    IF p_phone IS NULL OR length(regexp_replace(p_phone, '\D', '', 'g')) < 9 THEN RETURN; END IF;
    RETURN QUERY
    SELECT m.name, m.tier, m.visit_count, m.points_balance, m.member_code
      FROM members m WHERE m.phone_wa = p_phone LIMIT 1;
END $$;

-- ==============================================================================
-- 6. RPC TRANSAKSI — kini menghitung poin, menukar poin, dan menaikkan tier
-- ==============================================================================
DROP FUNCTION IF EXISTS create_transaction(UUID, TEXT, TEXT, UUID, TEXT, JSONB, NUMERIC, NUMERIC, TEXT, UUID, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION create_transaction(
    p_client_uuid    UUID,
    p_member_name    TEXT,
    p_member_phone   TEXT,
    p_capster_id     UUID,
    p_capster_name   TEXT,
    p_items          JSONB,
    p_subtotal       NUMERIC,
    p_final_amount   NUMERIC,
    p_payment_method TEXT,
    p_cashier_id     UUID,
    p_payment_ref    TEXT DEFAULT NULL,
    p_cash_paid      NUMERIC DEFAULT 0,
    p_cash_change    NUMERIC DEFAULT 0,
    p_created_at     TIMESTAMPTZ DEFAULT NULL,
    p_redeem_points  INT DEFAULT 0
)
RETURNS TABLE (
    id UUID, invoice_no VARCHAR, created_at TIMESTAMPTZ,
    member_tier member_tier, visit_count INT, cashier_name VARCHAR,
    points_earned INT, points_balance INT, discount_points NUMERIC,
    final_amount NUMERIC, tier_naik BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
-- Catatan: RETURNS TABLE di atas mendeklarasikan parameter keluaran bernama
-- sama dengan kolom tabel (id, points_balance, visit_count, ...). Setiap
-- rujukan kolom tersebut di badan fungsi WAJIB dikualifikasi nama tabelnya,
-- jika tidak PostgreSQL menolaknya sebagai ambigu (42702).
DECLARE
    v_member   members%ROWTYPE;
    v_cashier  cashiers%ROWTYPE;
    v_set      loyalty_settings%ROWTYPE;
    v_tx_id    UUID;
    v_inv      TEXT;
    v_at       TIMESTAMPTZ := COALESCE(p_created_at, now());
    v_summary  TEXT;
    v_item     JSONB;
    v_existing transactions%ROWTYPE;
    v_redeem   INT := GREATEST(COALESCE(p_redeem_points, 0), 0);
    v_disc     NUMERIC(12,2) := 0;
    v_final    NUMERIC(12,2);
    v_earn     INT := 0;
    v_mult     NUMERIC(4,2) := 1.00;
    v_tier_lama member_tier;
    v_tier_baru member_tier;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    SELECT * INTO v_cashier FROM cashiers WHERE cashiers.id = p_cashier_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kasir tidak dikenali. Masukkan PIN ulang.'; END IF;

    -- Pengiriman ulang antrean offline: kembalikan yang lama, jangan hitung dua kali
    SELECT * INTO v_existing FROM transactions t WHERE t.client_uuid = p_client_uuid;
    IF FOUND THEN
        RETURN QUERY
        SELECT v_existing.id, v_existing.invoice_no, v_existing.created_at,
               v_existing.member_tier, COALESCE(m.visit_count, 0), v_existing.cashier_name,
               v_existing.points_earned, COALESCE(m.points_balance, 0),
               v_existing.discount_points, v_existing.final_amount, false
          FROM (SELECT 1) x LEFT JOIN members m ON m.id = v_existing.member_id;
        RETURN;
    END IF;

    -- Kolom dikualifikasi: RETURNS TABLE mendeklarasikan parameter keluaran
    -- bernama id, sehingga `WHERE id` menjadi ambigu.
    SELECT * INTO v_set FROM loyalty_settings ls WHERE ls.id;

    -- ---------------------------------------------------------------------
    -- Member: kunci barisnya sebelum menyentuh saldo. Inilah yang mencegah
    -- dua kasir membelanjakan poin yang sama pada saat bersamaan.
    -- ---------------------------------------------------------------------
    IF p_member_phone IS NOT NULL AND p_member_phone <> '' AND p_member_phone <> '-' THEN
        SELECT * INTO v_member FROM members WHERE phone_wa = p_member_phone FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO members (name, phone_wa, member_code)
            VALUES (p_member_name, p_member_phone, generate_member_code())
            RETURNING * INTO v_member;
        END IF;

        v_tier_lama := v_member.tier;

        -- Penukaran poin
        IF v_redeem > 0 THEN
            IF NOT v_set.is_active THEN
                RAISE EXCEPTION 'Program poin sedang nonaktif.';
            END IF;
            IF v_redeem > v_member.points_balance THEN
                RAISE EXCEPTION 'Poin tidak cukup. Saldo tersedia: % poin.', v_member.points_balance;
            END IF;
            IF v_redeem < v_set.min_redeem_points THEN
                RAISE EXCEPTION 'Penukaran minimal % poin.', v_set.min_redeem_points;
            END IF;

            v_disc := v_redeem * v_set.rupiah_per_point_redeem;
            IF v_disc > p_subtotal * v_set.max_redeem_percent / 100 THEN
                RAISE EXCEPTION 'Diskon poin maksimal % persen dari subtotal.', v_set.max_redeem_percent;
            END IF;
        END IF;
    ELSIF v_redeem > 0 THEN
        RAISE EXCEPTION 'Penukaran poin membutuhkan nomor member.';
    END IF;

    v_final := p_subtotal - v_disc;

    -- Poin diperoleh dari nominal yang benar-benar dibayar
    IF v_member.id IS NOT NULL AND v_set.is_active THEN
        SELECT tr.earn_multiplier INTO v_mult FROM tier_rules tr WHERE tr.tier = v_member.tier;
        v_earn := floor(v_final / v_set.rupiah_per_point * COALESCE(v_mult, 1.00));
    END IF;

    v_inv := next_invoice_no();
    SELECT string_agg(elem->>'name', ', ') INTO v_summary FROM jsonb_array_elements(p_items) elem;

    INSERT INTO transactions (
        client_uuid, invoice_no, member_id, member_name, member_phone, member_tier,
        capster_id, capster_name, service_summary,
        subtotal, discount_points, final_amount, payment_method, payment_ref,
        cash_paid, cash_change, points_earned,
        cashier_id, cashier_ref_id, cashier_name, created_at, business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'),
        p_capster_id, p_capster_name, v_summary,
        p_subtotal, v_disc, v_final, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, p_cash_change, v_earn,
        auth.uid(), v_cashier.id, v_cashier.name, v_at,
        (v_at AT TIME ZONE 'Asia/Jakarta')::date
    ) RETURNING transactions.id INTO v_tx_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO transaction_items (transaction_id, service_id, service_name, category, price)
        VALUES (v_tx_id,
            CASE WHEN v_item->>'service_id' ~ '^[0-9a-fA-F-]{36}$'
                 THEN (v_item->>'service_id')::UUID ELSE NULL END,
            v_item->>'name', v_item->>'category',
            COALESCE((v_item->>'price')::NUMERIC, 0));
    END LOOP;

    -- ---------------------------------------------------------------------
    -- Mutasi poin: setiap perubahan saldo meninggalkan satu baris buku besar,
    -- sehingga saldo selalu dapat ditelusuri asal-usulnya.
    -- ---------------------------------------------------------------------
    IF v_member.id IS NOT NULL THEN
        IF v_redeem > 0 THEN
            UPDATE members SET points_balance = members.points_balance - v_redeem
             WHERE members.id = v_member.id RETURNING * INTO v_member;
            INSERT INTO point_ledger (member_id, transaction_id, type, points_amount, balance_after, notes)
            VALUES (v_member.id, v_tx_id, 'REDEEM', -v_redeem, v_member.points_balance,
                    'Tukar poin jadi diskon ' || v_disc::TEXT || ' pada ' || v_inv);
        END IF;

        IF v_earn > 0 THEN
            UPDATE members SET points_balance  = members.points_balance + v_earn,
                               lifetime_points = members.lifetime_points + v_earn
             WHERE members.id = v_member.id RETURNING * INTO v_member;
            INSERT INTO point_ledger (member_id, transaction_id, type, points_amount, balance_after, notes)
            VALUES (v_member.id, v_tx_id, 'EARN', v_earn, v_member.points_balance,
                    'Cashback poin dari ' || v_inv);
        END IF;

        v_tier_baru := compute_tier(v_member.lifetime_points);
        UPDATE members SET
            tier        = v_tier_baru,
            total_spend = members.total_spend + v_final,
            visit_count = members.visit_count + 1,
            name        = COALESCE(NULLIF(btrim(p_member_name), ''), members.name),
            updated_at  = now()
        WHERE members.id = v_member.id
        RETURNING * INTO v_member;

        UPDATE transactions SET member_tier = v_tier_baru WHERE transactions.id = v_tx_id;
    END IF;

    RETURN QUERY
    SELECT t.id, t.invoice_no, t.created_at, t.member_tier,
           COALESCE(v_member.visit_count, 0), t.cashier_name,
           t.points_earned, COALESCE(v_member.points_balance, 0),
           t.discount_points, t.final_amount,
           (v_tier_baru IS DISTINCT FROM v_tier_lama AND v_tier_lama IS NOT NULL)
      FROM transactions t WHERE t.id = v_tx_id;
END $$;

-- ==============================================================================
-- 7. BACKFILL — janji addendum: transaksi Fase 0 dihitung mundur
--    "pelanggan yang didaftarkan saat opening akan otomatis menerima poin
--     secara retroaktif begitu loyalty engine diaktifkan di Fase 1."
--    Aman diulang: transaksi yang sudah punya baris buku besar dilewati.
-- ==============================================================================
CREATE OR REPLACE FUNCTION backfill_loyalty()
RETURNS TABLE (transaksi_diproses INT, poin_diberikan INT, member_terdampak INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_set   loyalty_settings%ROWTYPE;
    v_tx    RECORD;
    v_earn  INT;
    v_bal   INT;
    v_n     INT := 0;
    v_total INT := 0;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menjalankan backfill poin.';
    END IF;
    SELECT * INTO v_set FROM loyalty_settings WHERE id;

    FOR v_tx IN
        SELECT t.id, t.member_id, t.final_amount, t.invoice_no
          FROM transactions t
         WHERE t.member_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM point_ledger pl WHERE pl.transaction_id = t.id)
         ORDER BY t.created_at
    LOOP
        v_earn := floor(v_tx.final_amount / v_set.rupiah_per_point);
        IF v_earn <= 0 THEN CONTINUE; END IF;

        UPDATE members SET points_balance  = points_balance + v_earn,
                           lifetime_points = lifetime_points + v_earn
         WHERE members.id = v_tx.member_id
        RETURNING points_balance INTO v_bal;

        INSERT INTO point_ledger (member_id, transaction_id, type, points_amount, balance_after, notes)
        VALUES (v_tx.member_id, v_tx.id, 'BONUS', v_earn, v_bal,
                'Poin retroaktif Fase 0 dari ' || v_tx.invoice_no);

        UPDATE transactions SET points_earned = v_earn WHERE transactions.id = v_tx.id;
        v_n := v_n + 1;
        v_total := v_total + v_earn;
    END LOOP;

    -- Tier disegarkan setelah seluruh poin masuk
    UPDATE members SET tier = compute_tier(lifetime_points) WHERE lifetime_points > 0;

    RETURN QUERY
    SELECT v_n, v_total, (SELECT COUNT(DISTINCT pl.member_id)::INT FROM point_ledger pl WHERE pl.type = 'BONUS');
END $$;

-- 8. RIWAYAT MUTASI POIN (OWNER) ----------------------------------------------
CREATE OR REPLACE FUNCTION member_ledger(p_phone TEXT)
RETURNS TABLE (
    waktu TIMESTAMPTZ, tipe VARCHAR, poin INT, saldo_sesudah INT, catatan TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka mutasi poin.'; END IF;
    RETURN QUERY
    SELECT pl.created_at, pl.type, pl.points_amount, pl.balance_after, pl.notes
      FROM point_ledger pl JOIN members m ON m.id = pl.member_id
     WHERE m.phone_wa = p_phone
     ORDER BY pl.created_at DESC LIMIT 200;
END $$;

-- 9. RLS ----------------------------------------------------------------------
ALTER TABLE loyalty_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE tier_rules       ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_all ON loyalty_settings;
CREATE POLICY owner_all ON loyalty_settings
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());

-- Aturan tier bukan rahasia: kasir perlu menjelaskannya kepada pelanggan.
DROP POLICY IF EXISTS read_tier_rules ON tier_rules;
CREATE POLICY read_tier_rules ON tier_rules FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS owner_write_tier_rules ON tier_rules;
CREATE POLICY owner_write_tier_rules ON tier_rules
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());

-- 10. AKSES BACA PENGATURAN POIN ----------------------------------------------
-- Kasir perlu tahu nilai tukar poin untuk menampilkan pratinjau diskon dan
-- menjelaskannya kepada pelanggan; angka ini memang bukan rahasia. Yang tetap
-- dikunci adalah hak mengubahnya.
DROP POLICY IF EXISTS owner_all ON loyalty_settings;
DROP POLICY IF EXISTS read_loyalty_settings ON loyalty_settings;
CREATE POLICY read_loyalty_settings ON loyalty_settings
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS owner_write_loyalty ON loyalty_settings;
CREATE POLICY owner_write_loyalty ON loyalty_settings
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
