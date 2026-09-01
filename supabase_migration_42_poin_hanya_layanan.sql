-- ══════════════════════════════════════════════════════════════════════════
-- 42 · K-04 — Pembelian produk tidak menghasilkan poin
-- ══════════════════════════════════════════════════════════════════════════
-- Keputusan pemilik atas K-04 pada spesifikasi MBR-UB-01-DEV: program poin
-- hanya berlaku untuk layanan.
--
-- Sebelum ini poin dihitung dari seluruh tagihan, jadi membeli pomade pun
-- menghasilkan 7%. Tidak ada satu pun produk yang pernah terjual sampai hari
-- ini (9 item terjual, semuanya layanan), sehingga perubahan ini tidak
-- membatalkan poin siapa pun secara surut.
--
-- Yang TIDAK berubah: penukaran poin tetap boleh memotong tagihan apa pun,
-- termasuk produk. Yang diputuskan pemilik adalah soal memperoleh poin, dan
-- melarang pemakaiannya pada produk berarti membuat aturan kedua yang tidak
-- pernah ia minta.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_transaction(p_client_uuid uuid, p_member_name text, p_member_phone text, p_capster_id uuid, p_capster_name text, p_items jsonb, p_subtotal numeric, p_final_amount numeric, p_payment_method text, p_cashier_id uuid, p_payment_ref text DEFAULT NULL::text, p_cash_paid numeric DEFAULT 0, p_cash_change numeric DEFAULT 0, p_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_redeem_points integer DEFAULT 0, p_discount_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, invoice_no character varying, created_at timestamp with time zone, member_tier member_tier, visit_count integer, cashier_name character varying, points_earned integer, points_balance integer, discount_points numeric, final_amount numeric, tier_naik boolean, discount_manual numeric, discount_name character varying, cash_paid numeric, cash_change numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_layanan      NUMERIC(12,2) := 0;
    v_dasar        NUMERIC(12,2) := 0;
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
    SELECT COALESCE(SUM((elem->>'price')::NUMERIC), 0),
           COALESCE(SUM((elem->>'price')::NUMERIC) FILTER (
               WHERE COALESCE(NULLIF(elem->>'item_type',''), 'layanan') = 'layanan'), 0)
      INTO v_items_total, v_layanan
      FROM jsonb_array_elements(p_items) elem;
    IF p_subtotal < 0 OR abs(v_items_total - p_subtotal) > 0.01 THEN
        RAISE EXCEPTION 'Subtotal tidak cocok dengan jumlah item.';
    END IF;

    SELECT * INTO v_set FROM loyalty_settings ls WHERE ls.id;

    IF p_member_phone IS NOT NULL AND p_member_phone <> '' AND p_member_phone <> '-' THEN
        SELECT * INTO v_member FROM members WHERE phone_wa = p_member_phone FOR UPDATE;
        IF NOT FOUND THEN
            -- Dua kunci dengan tugas berbeda: member_no adalah nomor yang
            -- disebut orang, member_code adalah kunci rahasia tautan kartu.
            INSERT INTO members (name, phone_wa, member_code, member_no)
            VALUES (p_member_name, p_member_phone, generate_member_code(),
                    next_member_no())
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
        -- R-10: pengali diambil dari level SEBELUM transaksi. Level baru
        -- berlaku mulai transaksi berikutnya, bukan pada transaksi yang
        -- menaikkannya.
        SELECT tr.earn_multiplier INTO v_mult FROM tier_rules tr WHERE tr.tier = v_member.tier;
        v_mult := COALESCE(v_mult, 1.00);
        -- K-04: pembelian produk tidak menghasilkan poin. Margin produk
        -- berbeda dari margin jasa, dan program ini dibiayai dari margin jasa.
        --
        -- Potongan (poin maupun diskon kasir) dibagi menurut porsi masing-
        -- masing, bukan dibebankan seluruhnya ke salah satu sisi. Membebankan
        -- ke layanan berarti pelanggan yang membeli pomade diam-diam kehilangan
        -- poin potong rambutnya; membebankan ke produk berarti toko membayar
        -- poin atas uang yang tidak pernah masuk. Pembagian sebanding tidak
        -- memihak keduanya, dan pada keranjang yang seluruhnya layanan
        -- hasilnya sama persis dengan perhitungan sebelumnya.
        --
        -- R-09: v_final sudah dikurangi potongan poin, jadi poin dihitung dari
        -- nilai yang benar-benar dibayar. R-11: pembulatan selalu ke bawah.
        v_dasar := CASE WHEN p_subtotal > 0
                        THEN v_final * v_layanan / p_subtotal
                        ELSE 0 END;
        v_earn := floor(v_dasar * v_set.earn_percent / 100 * v_mult);
    END IF;

    v_inv := next_invoice_no();
    SELECT string_agg(elem->>'name', ', ') INTO v_summary FROM jsonb_array_elements(p_items) elem;

    INSERT INTO transactions (
        client_uuid, invoice_no, member_id, member_name, member_phone, member_tier,
        capster_id, capster_name, service_summary,
        subtotal, discount_points, discount_id, discount_name, discount_manual,
        final_amount, payment_method, payment_ref, cash_paid, cash_change, points_earned,
        earn_multiplier_used, tier_before, outlet_id,
        cashier_id, cashier_ref_id, cashier_name, created_at, business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'), p_capster_id, p_capster_name, v_summary,
        p_subtotal, v_disc, v_discount.id, v_discount.name, v_manual,
        v_final, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, v_cash_change, v_earn,
        CASE WHEN v_member.id IS NOT NULL THEN v_mult END, v_tier_lama,
        outlet_aktif(),
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

        UPDATE transactions
           SET member_tier = v_tier_baru, tier_after = v_tier_baru
         WHERE transactions.id = v_tx_id;
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
$function$;


REVOKE EXECUTE ON FUNCTION create_transaction(uuid, text, text, uuid, text, jsonb,
    numeric, numeric, text, uuid, text, numeric, numeric, timestamptz, integer, uuid)
    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION create_transaction(uuid, text, text, uuid, text, jsonb,
    numeric, numeric, text, uuid, text, numeric, numeric, timestamptz, integer, uuid)
    TO authenticated;
