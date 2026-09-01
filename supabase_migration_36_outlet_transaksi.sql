-- ==============================================================================
-- MIGRASI 36 - Asal Cabang pada Setiap Transaksi
--
-- Transaksi tidak pernah mencatat berasal dari cabang mana. Selama tokonya
-- satu, itu tidak terasa. Begitu cabang kedua buka, seluruh riwayat lama
-- menjadi tidak dapat dipisahkan lagi: tidak ada satu pun cara mengetahui
-- transaksi mana milik cabang mana, dan omzet dua tahun pertama akan
-- selamanya tercampur.
--
-- Itulah alasan migrasi ini dikerjakan sekarang, bukan nanti ketika cabang
-- keduanya benar-benar dibuka. Sepuluh baris yang ada sekarang dapat diisi
-- mundur dengan yakin sebab outletnya memang cuma satu; sepuluh ribu baris
-- dari dua cabang tidak bisa.
--
-- OUTLET DIPUTUSKAN, BUKAN DITEBAK
--
-- Tidak ada yang mengikat perangkat kasir maupun akun kasir ke sebuah outlet.
-- Karena itu outlet_aktif() mengembalikan satu-satunya outlet yang aktif, dan
-- MENOLAK dengan galat yang jelas begitu ada lebih dari satu.
--
-- Ini disengaja. Alternatifnya adalah memilih diam-diam yang pertama
-- berdasarkan sort_order, dan itu berarti pada hari cabang kedua dibuka,
-- seluruh transaksinya akan tercatat atas nama cabang pertama tanpa ada yang
-- menyadarinya sampai berbulan-bulan kemudian. Kesalahan yang berteriak jauh
-- lebih murah daripada kesalahan yang diam.
-- ==============================================================================

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS outlet_id UUID REFERENCES outlets(id);

CREATE INDEX IF NOT EXISTS transactions_outlet_tanggal
  ON transactions (outlet_id, business_date);

COMMENT ON COLUMN transactions.outlet_id IS
  'Cabang tempat transaksi terjadi. Diisi saat transaksi dibuat, tidak pernah '
  'diubah setelahnya.';


-- ── Penentu outlet ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION outlet_aktif()
RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_id     UUID;
    v_jumlah INT;
BEGIN
    SELECT COUNT(*) INTO v_jumlah FROM outlets WHERE is_active;

    IF v_jumlah = 0 THEN
        RAISE EXCEPTION 'Belum ada outlet aktif. Daftarkan outlet lebih dulu di layar master data.';
    END IF;

    IF v_jumlah > 1 THEN
        RAISE EXCEPTION 'Ada % outlet aktif dan perangkat ini belum terikat ke salah satunya. '
                        'Tetapkan outlet perangkat sebelum melanjutkan transaksi.', v_jumlah;
    END IF;

    SELECT o.id INTO v_id FROM outlets o WHERE o.is_active;
    RETURN v_id;
END $function$;

REVOKE EXECUTE ON FUNCTION outlet_aktif() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION outlet_aktif() TO authenticated;


-- ── Pengisian mundur ───────────────────────────────────────────────────────
-- Aman dilakukan hanya karena outletnya memang tunggal. Kalau suatu saat
-- migrasi ini dijalankan ulang di basis data yang sudah bercabang, baris lama
-- dibiarkan apa adanya daripada diisi dengan tebakan.
DO $isi_mundur$
DECLARE
    v_jumlah INT;
    v_id     UUID;
    v_baris  INT;
BEGIN
    SELECT COUNT(*) INTO v_jumlah FROM outlets WHERE is_active;
    IF v_jumlah <> 1 THEN
        RAISE NOTICE 'Outlet aktif berjumlah %, pengisian mundur dilewati.', v_jumlah;
        RETURN;
    END IF;

    SELECT o.id INTO v_id FROM outlets o WHERE o.is_active;
    UPDATE transactions SET outlet_id = v_id WHERE outlet_id IS NULL;
    GET DIAGNOSTICS v_baris = ROW_COUNT;
    RAISE NOTICE '% transaksi lama diisi outletnya.', v_baris;
END
$isi_mundur$;


-- ── create_transaction mencatat asal cabangnya ─────────────────────────────
-- Ditambal dari definisi yang sedang berjalan. outlet_aktif() dipanggil di
-- dalam transaksi basis data yang sama, jadi kalau outletnya sudah ambigu,
-- transaksinya gagal utuh dan tidak ada baris setengah jadi yang tertinggal.
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
        -- R-09: v_final sudah dikurangi potongan poin, jadi poin dihitung dari
        -- nilai yang benar-benar dibayar. R-11: pembulatan selalu ke bawah.
        v_earn := floor(v_final * v_set.earn_percent / 100 * v_mult);
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
$function$
;
