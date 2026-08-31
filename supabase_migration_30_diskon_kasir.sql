-- ==============================================================================
-- MIGRATION 30: PRESET DISKON KASIR
-- Owner menentukan preset. Kasir hanya memilih preset aktif, sedangkan nilai
-- akhirnya selalu dihitung ulang di server agar omzet tidak bergantung pada
-- angka yang dikirim browser.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.pos_discounts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(80) NOT NULL,
    kind            TEXT NOT NULL CHECK (kind IN ('percent', 'fixed')),
    value           NUMERIC(12,2) NOT NULL CHECK (value > 0),
    min_subtotal    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (min_subtotal >= 0),
    max_discount    NUMERIC(12,2) CHECK (max_discount IS NULL OR max_discount > 0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pos_discounts_percent_limit CHECK (kind <> 'percent' OR value <= 100)
);

CREATE UNIQUE INDEX IF NOT EXISTS pos_discounts_name_unique
    ON public.pos_discounts (lower(name));

ALTER TABLE public.pos_discounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pos_discounts_read ON public.pos_discounts;
CREATE POLICY pos_discounts_read ON public.pos_discounts
    FOR SELECT TO authenticated
    USING (is_owner() OR (is_pos_device() AND is_active));

DROP POLICY IF EXISTS pos_discounts_owner_insert ON public.pos_discounts;
CREATE POLICY pos_discounts_owner_insert ON public.pos_discounts
    FOR INSERT TO authenticated
    WITH CHECK (is_owner());

DROP POLICY IF EXISTS pos_discounts_owner_update ON public.pos_discounts;
CREATE POLICY pos_discounts_owner_update ON public.pos_discounts
    FOR UPDATE TO authenticated
    USING (is_owner()) WITH CHECK (is_owner());

DROP POLICY IF EXISTS pos_discounts_owner_delete ON public.pos_discounts;
CREATE POLICY pos_discounts_owner_delete ON public.pos_discounts
    FOR DELETE TO authenticated
    USING (is_owner());

REVOKE ALL ON TABLE public.pos_discounts FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.pos_discounts TO authenticated;

CREATE OR REPLACE FUNCTION public.touch_pos_discount_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO public
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pos_discounts_touch_updated_at ON public.pos_discounts;
CREATE TRIGGER pos_discounts_touch_updated_at
    BEFORE UPDATE ON public.pos_discounts
    FOR EACH ROW EXECUTE FUNCTION public.touch_pos_discount_updated_at();


ALTER TABLE public.transactions
    ADD COLUMN IF NOT EXISTS discount_id UUID REFERENCES public.pos_discounts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS discount_name VARCHAR(80),
    ADD COLUMN IF NOT EXISTS discount_manual NUMERIC(12,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'transactions_discount_manual_nonnegative'
    ) THEN
        ALTER TABLE public.transactions
            ADD CONSTRAINT transactions_discount_manual_nonnegative
            CHECK (discount_manual >= 0);
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS transactions_discount_id_idx
    ON public.transactions (discount_id)
    WHERE discount_id IS NOT NULL;


CREATE OR REPLACE FUNCTION public.pos_discounts()
RETURNS TABLE(
    id UUID,
    name VARCHAR,
    kind TEXT,
    value NUMERIC,
    min_subtotal NUMERIC,
    max_discount NUMERIC,
    is_active BOOLEAN
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT (is_owner() OR is_pos_device()) THEN
        RAISE EXCEPTION 'Perangkat ini tidak boleh membuka daftar diskon.';
    END IF;

    RETURN QUERY
    SELECT d.id, d.name, d.kind, d.value, d.min_subtotal, d.max_discount, d.is_active
      FROM public.pos_discounts d
     WHERE d.is_active
     ORDER BY lower(d.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.owner_pos_discounts_list()
RETURNS TABLE(
    id UUID,
    name VARCHAR,
    kind TEXT,
    value NUMERIC,
    min_subtotal NUMERIC,
    max_discount NUMERIC,
    is_active BOOLEAN
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola diskon.';
    END IF;

    RETURN QUERY
    SELECT d.id, d.name, d.kind, d.value, d.min_subtotal, d.max_discount, d.is_active
      FROM public.pos_discounts d
     ORDER BY d.is_active DESC, lower(d.name);
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_pos_discount(
    p_id UUID DEFAULT NULL,
    p_name TEXT DEFAULT NULL,
    p_kind TEXT DEFAULT NULL,
    p_value NUMERIC DEFAULT NULL,
    p_min_subtotal NUMERIC DEFAULT 0,
    p_max_discount NUMERIC DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_id UUID;
    v_name TEXT := btrim(COALESCE(p_name, ''));
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola diskon.';
    END IF;
    IF v_name = '' OR length(v_name) > 80 THEN
        RAISE EXCEPTION 'Nama diskon wajib diisi, maksimal 80 karakter.';
    END IF;
    IF p_kind NOT IN ('percent', 'fixed') THEN
        RAISE EXCEPTION 'Jenis diskon tidak valid.';
    END IF;
    IF COALESCE(p_value, 0) <= 0 THEN
        RAISE EXCEPTION 'Nilai diskon harus lebih dari nol.';
    END IF;
    IF p_kind = 'percent' AND p_value > 100 THEN
        RAISE EXCEPTION 'Diskon persen maksimal 100 persen.';
    END IF;
    IF COALESCE(p_min_subtotal, 0) < 0 OR (p_max_discount IS NOT NULL AND p_max_discount <= 0) THEN
        RAISE EXCEPTION 'Batas diskon tidak valid.';
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO public.pos_discounts(name, kind, value, min_subtotal, max_discount, is_active)
        VALUES (v_name, p_kind, p_value, COALESCE(p_min_subtotal, 0), p_max_discount, COALESCE(p_is_active, TRUE))
        RETURNING pos_discounts.id INTO v_id;
    ELSE
        UPDATE public.pos_discounts d
           SET name = v_name,
               kind = p_kind,
               value = p_value,
               min_subtotal = COALESCE(p_min_subtotal, 0),
               max_discount = p_max_discount,
               is_active = COALESCE(p_is_active, TRUE)
         WHERE d.id = p_id
        RETURNING d.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Diskon tidak ditemukan.'; END IF;
    END IF;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_pos_discount(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus diskon.';
    END IF;
    DELETE FROM public.pos_discounts d WHERE d.id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Diskon tidak ditemukan.'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.pos_discounts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.owner_pos_discounts_list() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_pos_discount(UUID, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_pos_discount(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pos_discounts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.owner_pos_discounts_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_pos_discount(UUID, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_pos_discount(UUID) TO authenticated;


-- RETURNS TABLE berubah, jadi fungsi lama perlu dijatuhkan sebelum definisi
-- baru dibuat. Argumen terakhir memiliki default agar POS versi lama tetap hidup.
DROP FUNCTION IF EXISTS public.create_transaction(
    UUID, TEXT, TEXT, UUID, TEXT, JSONB, NUMERIC, NUMERIC, TEXT, UUID,
    TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, INTEGER
);

CREATE FUNCTION public.create_transaction(
    p_client_uuid UUID,
    p_member_name TEXT,
    p_member_phone TEXT,
    p_capster_id UUID,
    p_capster_name TEXT,
    p_items JSONB,
    p_subtotal NUMERIC,
    p_final_amount NUMERIC,
    p_payment_method TEXT,
    p_cashier_id UUID,
    p_payment_ref TEXT DEFAULT NULL,
    p_cash_paid NUMERIC DEFAULT 0,
    p_cash_change NUMERIC DEFAULT 0,
    p_created_at TIMESTAMPTZ DEFAULT NULL,
    p_redeem_points INTEGER DEFAULT 0,
    p_discount_id UUID DEFAULT NULL
)
RETURNS TABLE(
    id UUID,
    invoice_no VARCHAR,
    created_at TIMESTAMPTZ,
    member_tier member_tier,
    visit_count INTEGER,
    cashier_name VARCHAR,
    points_earned INTEGER,
    points_balance INTEGER,
    discount_points NUMERIC,
    final_amount NUMERIC,
    tier_naik BOOLEAN,
    discount_manual NUMERIC,
    discount_name VARCHAR,
    cash_paid NUMERIC,
    cash_change NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
    v_member       members%ROWTYPE;
    v_cashier      cashiers%ROWTYPE;
    v_set          loyalty_settings%ROWTYPE;
    v_discount     pos_discounts%ROWTYPE;
    v_tx_id        UUID;
    v_inv          TEXT;
    v_at           TIMESTAMPTZ := COALESCE(p_created_at, now());
    v_summary      TEXT;
    v_item         JSONB;
    v_existing     transactions%ROWTYPE;
    v_redeem       INT := GREATEST(COALESCE(p_redeem_points, 0), 0);
    v_disc         NUMERIC(12,2) := 0;
    v_manual       NUMERIC(12,2) := 0;
    v_final        NUMERIC(12,2);
    v_cash_change  NUMERIC(12,2) := 0;
    v_items_total  NUMERIC(12,2);
    v_earn         INT := 0;
    v_mult         NUMERIC(4,2) := 1.00;
    v_tier_lama    member_tier;
    v_tier_baru    member_tier;
    v_pid          UUID;
    v_kind         item_kind;
    v_icap         UUID;
    v_iname        TEXT;
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
               v_existing.discount_points, v_existing.final_amount, false,
               v_existing.discount_manual, v_existing.discount_name,
               v_existing.cash_paid, v_existing.cash_change
          FROM (SELECT 1) x LEFT JOIN members m ON m.id = v_existing.member_id;
        RETURN;
    END IF;

    IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Transaksi harus memiliki minimal satu item.';
    END IF;
    SELECT COALESCE(SUM((elem->>'price')::NUMERIC), 0)
      INTO v_items_total
      FROM jsonb_array_elements(p_items) elem;
    IF p_subtotal < 0 OR abs(v_items_total - p_subtotal) > 0.01 THEN
        RAISE EXCEPTION 'Subtotal tidak cocok dengan jumlah item.';
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

    IF p_discount_id IS NOT NULL THEN
        SELECT * INTO v_discount
          FROM public.pos_discounts d
         WHERE d.id = p_discount_id AND d.is_active;
        IF NOT FOUND THEN RAISE EXCEPTION 'Diskon tidak ditemukan atau sedang nonaktif.'; END IF;
        IF p_subtotal < v_discount.min_subtotal THEN
            RAISE EXCEPTION 'Diskon % membutuhkan subtotal minimal %.', v_discount.name, v_discount.min_subtotal;
        END IF;

        IF v_discount.kind = 'percent' THEN
            v_manual := round(p_subtotal * v_discount.value / 100, 2);
        ELSE
            v_manual := v_discount.value;
        END IF;
        IF v_discount.max_discount IS NOT NULL THEN
            v_manual := LEAST(v_manual, v_discount.max_discount);
        END IF;
        v_manual := LEAST(v_manual, GREATEST(p_subtotal - v_disc, 0));
    END IF;

    v_final := GREATEST(p_subtotal - v_disc - v_manual, 0);

    IF p_payment_method = 'Tunai' THEN
        IF COALESCE(p_cash_paid, 0) < v_final THEN
            RAISE EXCEPTION 'Uang tunai yang diterima kurang dari total tagihan.';
        END IF;
        v_cash_change := GREATEST(COALESCE(p_cash_paid, 0) - v_final, 0);
    END IF;

    IF v_member.id IS NOT NULL AND v_set.is_active THEN
        SELECT tr.earn_multiplier INTO v_mult FROM tier_rules tr WHERE tr.tier = v_member.tier;
        v_earn := floor(v_final / v_set.rupiah_per_point * COALESCE(v_mult, 1.00));
    END IF;

    v_inv := next_invoice_no();
    SELECT string_agg(elem->>'name', ', ') INTO v_summary FROM jsonb_array_elements(p_items) elem;

    INSERT INTO transactions (
        client_uuid, invoice_no, member_id, member_name, member_phone, member_tier,
        capster_id, capster_name, service_summary,
        subtotal, discount_points, discount_id, discount_name, discount_manual,
        final_amount, payment_method, payment_ref, cash_paid, cash_change, points_earned,
        cashier_id, cashier_ref_id, cashier_name, created_at, business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'), p_capster_id, p_capster_name, v_summary,
        p_subtotal, v_disc, v_discount.id, v_discount.name, v_manual,
        v_final, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, v_cash_change, v_earn,
        auth.uid(), v_cashier.id, v_cashier.name, v_at,
        (v_at AT TIME ZONE 'Asia/Jakarta')::date
    ) RETURNING transactions.id INTO v_tx_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_kind := COALESCE(NULLIF(v_item->>'item_type','')::item_kind, 'layanan');
        v_pid  := CASE WHEN v_item->>'product_id' ~ '^[0-9a-fA-F-]{36}$'
                       THEN (v_item->>'product_id')::UUID ELSE NULL END;
        v_icap := CASE WHEN v_item->>'capster_id' ~ '^[0-9a-fA-F-]{36}$'
                       THEN (v_item->>'capster_id')::UUID ELSE p_capster_id END;
        v_iname := COALESCE(NULLIF(btrim(COALESCE(v_item->>'capster_name','')), ''), p_capster_name);

        INSERT INTO transaction_items (transaction_id, service_id, product_id, item_type,
                                       service_name, category, price, hpp_snapshot,
                                       capster_id, capster_name)
        VALUES (
            v_tx_id,
            CASE WHEN v_kind = 'layanan' AND v_item->>'service_id' ~ '^[0-9a-fA-F-]{36}$'
                 THEN (v_item->>'service_id')::UUID ELSE NULL END,
            v_pid, v_kind, v_item->>'name', v_item->>'category',
            COALESCE((v_item->>'price')::NUMERIC, 0),
            CASE WHEN v_kind = 'produk' AND v_pid IS NOT NULL THEN hpp_of(v_pid) ELSE NULL END,
            v_icap, v_iname
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
            UPDATE members SET points_balance = members.points_balance + v_earn,
                               lifetime_points = members.lifetime_points + v_earn
             WHERE members.id = v_member.id RETURNING * INTO v_member;
            INSERT INTO point_ledger (member_id, transaction_id, type, points_amount, balance_after, notes)
            VALUES (v_member.id, v_tx_id, 'EARN', v_earn, v_member.points_balance,
                    'Cashback poin dari ' || v_inv);
        END IF;

        v_tier_baru := compute_tier(v_member.lifetime_points);
        UPDATE members SET
            tier = v_tier_baru,
            total_spend = members.total_spend + v_final,
            visit_count = members.visit_count + 1,
            name = COALESCE(NULLIF(btrim(p_member_name), ''), members.name),
            updated_at = now()
        WHERE members.id = v_member.id
        RETURNING * INTO v_member;

        UPDATE transactions SET member_tier = v_tier_baru WHERE transactions.id = v_tx_id;
    END IF;

    RETURN QUERY
    SELECT t.id, t.invoice_no, t.created_at, t.member_tier,
           COALESCE(v_member.visit_count, 0), t.cashier_name,
           t.points_earned, COALESCE(v_member.points_balance, 0),
           t.discount_points, t.final_amount,
           (v_tier_baru IS DISTINCT FROM v_tier_lama AND v_tier_lama IS NOT NULL),
           t.discount_manual, t.discount_name, t.cash_paid, t.cash_change
      FROM transactions t WHERE t.id = v_tx_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_transaction(
    UUID, TEXT, TEXT, UUID, TEXT, JSONB, NUMERIC, NUMERIC, TEXT, UUID,
    TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, INTEGER, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transaction(
    UUID, TEXT, TEXT, UUID, TEXT, JSONB, NUMERIC, NUMERIC, TEXT, UUID,
    TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ, INTEGER, UUID
) TO authenticated;

NOTIFY pgrst, 'reload schema';
