-- ==============================================================================
-- MIGRASI 08 — Kalkulator HPP & Penjualan Produk (Fase 3)
--
-- Rumus mengikuti addendum bagian 03 apa adanya:
--   HPP          = Harga Beli + Ongkir + Kemasan + Overhead
--   Margin (Rp)  = Harga Jual - HPP
--   Margin (%)   = (Harga Jual - HPP) / Harga Jual * 100
--   Harga Jual   = HPP / (1 - Target Margin)
--   Diskon Aman  = Margin (%), batas sebelum laba menjadi nol
--
-- DUA KEPUTUSAN YANG MENENTUKAN BENTUK BERKAS INI
--
-- 1. PRODUK HARUS DAPAT DIJUAL DI KASIR.
--    Addendum menjanjikan "laba kotor per produk, terhubung ke laporan
--    penjualan harian". Tanpa penjualan produk, HPP hanya kalkulator yang
--    tidak pernah bertemu angka nyata. Karena itu transaction_items kini
--    membedakan layanan dan produk.
--
-- 2. HPP DIBEKUKAN SAAT PENJUALAN.
--    Harga supplier berubah dari waktu ke waktu. Bila laporan laba menghitung
--    ulang memakai HPP terkini, laba bulan lalu ikut berubah setiap kali owner
--    memperbarui harga beli — laporan yang sudah dicetak tidak lagi cocok.
--    Karena itu HPP disalin ke baris transaksi pada saat penjualan terjadi.
-- ==============================================================================

-- 1. JENIS BARIS TRANSAKSI ----------------------------------------------------
DO $$ BEGIN
    CREATE TYPE item_kind AS ENUM ('layanan', 'produk');
EXCEPTION WHEN duplicate_object THEN null; END $$;

ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS item_type item_kind NOT NULL DEFAULT 'layanan';
ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS product_id UUID
    REFERENCES products_hpp(id) ON DELETE SET NULL;
-- HPP pada saat transaksi terjadi; tidak ikut berubah bila harga beli direvisi
ALTER TABLE transaction_items ADD COLUMN IF NOT EXISTS hpp_snapshot NUMERIC(12,2);
CREATE INDEX IF NOT EXISTS idx_items_product ON transaction_items(product_id);
CREATE INDEX IF NOT EXISTS idx_items_type ON transaction_items(item_type);

-- 2. HPP SATU PRODUK ----------------------------------------------------------
CREATE OR REPLACE FUNCTION hpp_of(p_product_id UUID)
RETURNS NUMERIC
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(p.buy_price, 0) + COALESCE(p.shipping_per_unit, 0)
         + COALESCE(p.packaging_cost, 0) + COALESCE(p.overhead_cost, 0)
      FROM products_hpp p WHERE p.id = p_product_id
$$;

-- 3. LAPORAN HPP & MARGIN (KHUSUS OWNER) --------------------------------------
CREATE OR REPLACE FUNCTION hpp_report()
RETURNS TABLE (
    id UUID, name VARCHAR, category VARCHAR,
    buy_price NUMERIC, shipping_per_unit NUMERIC, packaging_cost NUMERIC, overhead_cost NUMERIC,
    hpp NUMERIC, sell_price NUMERIC,
    margin_rp NUMERIC, margin_persen NUMERIC, markup_persen NUMERIC,
    target_margin_percent NUMERIC, harga_jual_disarankan NUMERIC,
    diskon_aman_persen NUMERIC, diskon_aman_rp NUMERIC,
    terjual INT, laba_kotor NUMERIC, is_active BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuka laporan HPP.';
    END IF;

    RETURN QUERY
    SELECT p.id, p.name, p.category,
           p.buy_price, p.shipping_per_unit, p.packaging_cost, p.overhead_cost,
           h.hpp,
           p.sell_price,
           (p.sell_price - h.hpp) AS margin_rp,
           CASE WHEN p.sell_price > 0
                THEN round((p.sell_price - h.hpp) / p.sell_price * 100, 2) ELSE 0 END AS margin_persen,
           -- Markup dihitung terhadap modal, bukan terhadap harga jual.
           -- Keduanya kerap tertukar dan menghasilkan angka yang jauh berbeda.
           CASE WHEN h.hpp > 0
                THEN round((p.sell_price - h.hpp) / h.hpp * 100, 2) ELSE 0 END AS markup_persen,
           p.target_margin_percent,
           -- Harga Jual = HPP / (1 - target). Target 100% mustahil dicapai.
           CASE WHEN p.target_margin_percent < 100
                THEN round(h.hpp / (1 - p.target_margin_percent / 100), 0) ELSE NULL END AS harga_jual_disarankan,
           CASE WHEN p.sell_price > 0
                THEN round((p.sell_price - h.hpp) / p.sell_price * 100, 2) ELSE 0 END AS diskon_aman_persen,
           (p.sell_price - h.hpp) AS diskon_aman_rp,
           COALESCE(s.qty, 0)::INT AS terjual,
           COALESCE(s.laba, 0) AS laba_kotor,
           p.is_active
      FROM products_hpp p
      CROSS JOIN LATERAL (SELECT hpp_of(p.id) AS hpp) h
      LEFT JOIN LATERAL (
            SELECT SUM(i.qty)::INT AS qty,
                   SUM(i.price - COALESCE(i.hpp_snapshot, 0) * i.qty) AS laba
              FROM transaction_items i
             WHERE i.product_id = p.id AND i.item_type = 'produk'
      ) s ON true
     ORDER BY COALESCE(s.laba, 0) DESC, p.name;
END $$;

-- 4. SIMULASI HARGA JUAL ------------------------------------------------------
-- Menjawab pertanyaan owner sebelum menetapkan harga: "kalau target margin
-- sekian persen, harga jualnya berapa, dan diskon poin maksimal berapa?"
CREATE OR REPLACE FUNCTION hpp_simulate(
    p_buy NUMERIC, p_shipping NUMERIC DEFAULT 0, p_packaging NUMERIC DEFAULT 0,
    p_overhead NUMERIC DEFAULT 0, p_target_margin NUMERIC DEFAULT 40,
    p_diskon_poin NUMERIC DEFAULT 0
)
RETURNS TABLE (
    hpp NUMERIC, harga_jual NUMERIC, margin_rp NUMERIC, margin_persen NUMERIC,
    diskon_aman_persen NUMERIC, diskon_aman_rp NUMERIC,
    sisa_margin_rp NUMERIC, sisa_margin_persen NUMERIC, masih_untung BOOLEAN
)
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    v_hpp   NUMERIC;
    v_jual  NUMERIC;
    v_sisa  NUMERIC;
    v_bayar NUMERIC;
BEGIN
    IF p_target_margin >= 100 OR p_target_margin < 0 THEN
        RAISE EXCEPTION 'Target margin harus antara 0 dan 99,99 persen.';
    END IF;

    v_hpp  := COALESCE(p_buy,0) + COALESCE(p_shipping,0) + COALESCE(p_packaging,0) + COALESCE(p_overhead,0);
    v_jual := round(v_hpp / (1 - p_target_margin / 100), 0);
    v_bayar := v_jual - COALESCE(p_diskon_poin, 0);
    v_sisa := v_bayar - v_hpp;

    RETURN QUERY SELECT
        v_hpp,
        v_jual,
        (v_jual - v_hpp),
        CASE WHEN v_jual > 0 THEN round((v_jual - v_hpp) / v_jual * 100, 2) ELSE 0 END,
        CASE WHEN v_jual > 0 THEN round((v_jual - v_hpp) / v_jual * 100, 2) ELSE 0 END,
        (v_jual - v_hpp),
        v_sisa,
        CASE WHEN v_bayar > 0 THEN round(v_sisa / v_bayar * 100, 2) ELSE 0 END,
        (v_sisa > 0);
END $$;

-- 5. KELOLA PRODUK (KHUSUS OWNER) ---------------------------------------------
CREATE OR REPLACE FUNCTION upsert_product(
    p_name TEXT, p_sell NUMERIC,
    p_buy NUMERIC DEFAULT 0, p_shipping NUMERIC DEFAULT 0,
    p_packaging NUMERIC DEFAULT 0, p_overhead NUMERIC DEFAULT 0,
    p_target_margin NUMERIC DEFAULT 40,
    p_description TEXT DEFAULT NULL, p_category TEXT DEFAULT 'Retail',
    p_hold INT DEFAULT NULL, p_shine INT DEFAULT NULL,
    p_id UUID DEFAULT NULL
)
RETURNS TABLE (id UUID, name VARCHAR, hpp NUMERIC, sell_price NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola data produk.';
    END IF;
    IF btrim(COALESCE(p_name,'')) = '' THEN RAISE EXCEPTION 'Nama produk wajib diisi.'; END IF;
    IF p_sell IS NULL OR p_sell < 0 THEN RAISE EXCEPTION 'Harga jual tidak boleh negatif.'; END IF;

    IF p_id IS NULL THEN
        INSERT INTO products_hpp (name, description, category, buy_price, shipping_per_unit,
                                  packaging_cost, overhead_cost, sell_price, target_margin_percent,
                                  hold_level, shine_level)
        VALUES (btrim(p_name), p_description, p_category, p_buy, p_shipping,
                p_packaging, p_overhead, p_sell, p_target_margin, p_hold, p_shine)
        RETURNING products_hpp.id INTO v_id;
    ELSE
        UPDATE products_hpp SET
            name = btrim(p_name), description = p_description, category = p_category,
            buy_price = p_buy, shipping_per_unit = p_shipping,
            packaging_cost = p_packaging, overhead_cost = p_overhead,
            sell_price = p_sell, target_margin_percent = p_target_margin,
            hold_level = p_hold, shine_level = p_shine
        WHERE products_hpp.id = p_id
        RETURNING products_hpp.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan.'; END IF;
    END IF;

    RETURN QUERY SELECT p.id, p.name, hpp_of(p.id), p.sell_price
                   FROM products_hpp p WHERE p.id = v_id;
END $$;

-- 6. KATALOG PRODUK UNTUK KASIR -----------------------------------------------
-- Kasir perlu daftar produk untuk dijual, tetapi tidak perlu — dan tidak
-- boleh — melihat harga modalnya.
CREATE OR REPLACE FUNCTION pos_products()
RETURNS TABLE (id UUID, name VARCHAR, category VARCHAR, price NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    RETURN QUERY
    SELECT p.id, p.name, p.category, p.sell_price
      FROM products_hpp p WHERE p.is_active
     ORDER BY p.sort_order, p.name;
END $$;
GRANT EXECUTE ON FUNCTION pos_products() TO authenticated;

-- ==============================================================================
-- 7. RPC TRANSAKSI — kini menerima produk sekaligus layanan
--    Setiap baris produk membekukan HPP-nya pada saat penjualan.
-- ==============================================================================
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
-- Catatan: RETURNS TABLE mendeklarasikan parameter keluaran bernama sama
-- dengan kolom tabel (id, points_balance, visit_count, ...). Setiap rujukan
-- kolom tersebut di badan fungsi WAJIB dikualifikasi nama tabelnya, jika
-- tidak PostgreSQL menolaknya sebagai ambigu (42702).
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
    v_pid      UUID;
    v_kind     item_kind;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    SELECT * INTO v_cashier FROM cashiers WHERE cashiers.id = p_cashier_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kasir tidak dikenali. Masukkan PIN ulang.'; END IF;

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

    SELECT * INTO v_set FROM loyalty_settings ls WHERE ls.id;

    IF p_member_phone IS NOT NULL AND p_member_phone <> '' AND p_member_phone <> '-' THEN
        SELECT * INTO v_member FROM members WHERE phone_wa = p_member_phone FOR UPDATE;
        IF NOT FOUND THEN
            INSERT INTO members (name, phone_wa, member_code)
            VALUES (p_member_name, p_member_phone, generate_member_code())
            RETURNING * INTO v_member;
        END IF;
        v_tier_lama := v_member.tier;

        IF v_redeem > 0 THEN
            IF NOT v_set.is_active THEN RAISE EXCEPTION 'Program poin sedang nonaktif.'; END IF;
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
        v_kind := COALESCE(NULLIF(v_item->>'item_type','')::item_kind, 'layanan');
        v_pid  := CASE WHEN v_item->>'product_id' ~ '^[0-9a-fA-F-]{36}$'
                       THEN (v_item->>'product_id')::UUID ELSE NULL END;

        INSERT INTO transaction_items (transaction_id, service_id, product_id, item_type,
                                       service_name, category, price, hpp_snapshot)
        VALUES (
            v_tx_id,
            CASE WHEN v_kind = 'layanan' AND v_item->>'service_id' ~ '^[0-9a-fA-F-]{36}$'
                 THEN (v_item->>'service_id')::UUID ELSE NULL END,
            v_pid,
            v_kind,
            v_item->>'name',
            v_item->>'category',
            COALESCE((v_item->>'price')::NUMERIC, 0),
            -- HPP dibekukan di sini; revisi harga beli tidak mengubah laba lampau
            CASE WHEN v_kind = 'produk' AND v_pid IS NOT NULL THEN hpp_of(v_pid) ELSE NULL END
        );
    END LOOP;

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

-- 8. HPP UNTUK TRANSAKSI LAMA -------------------------------------------------
-- Baris produk yang tercatat sebelum migrasi ini belum punya snapshot.
UPDATE transaction_items SET hpp_snapshot = hpp_of(product_id)
 WHERE item_type = 'produk' AND product_id IS NOT NULL AND hpp_snapshot IS NULL;

-- 9. HAK EKSEKUSI -------------------------------------------------------------
GRANT EXECUTE ON FUNCTION hpp_report()   TO authenticated;
GRANT EXECUTE ON FUNCTION hpp_simulate(NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_product(TEXT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,TEXT,TEXT,INT,INT,UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION hpp_report() FROM anon;
