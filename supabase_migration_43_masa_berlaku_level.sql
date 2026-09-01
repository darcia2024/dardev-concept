-- ══════════════════════════════════════════════════════════════════════════
-- 43 · K-06 — Level berlaku satu tahun, lalu harus dikualifikasi ulang
-- ══════════════════════════════════════════════════════════════════════════
-- Keputusan pemilik atas K-06 pada spesifikasi MBR-UB-01-DEV:
--
--   "Level berlaku selama periode 1 tahun. Di akhir periode, level akan
--    dipotong sebesar point minimum tier untuk menjaga status membership di
--    tier tersebut. Jika berhasil upgrade tier, periode membership akan
--    otomatis diperpanjang selama 1 tahun lagi."
--
-- Artinya: untuk bertahan di sebuah level, member harus mengumpulkan kembali
-- sebanyak ambang level itu setiap tahun. Gold berambang 50.000, jadi tiap
-- tahun 50.000 poin seumur hidupnya dipotong; yang tersisa menentukan
-- levelnya. Yang terus naik tidak pernah membayar potongan itu, karena setiap
-- kenaikan level memulai periode satu tahun yang baru.
--
-- Silver berambang 0, jadi potongannya nol. Member Silver tidak pernah turun,
-- dan seluruh tujuh member yang ada hari ini masih Silver — pemberlakuan ini
-- tidak menurunkan siapa pun sekarang.
--
-- SALDO POIN TIDAK DISENTUH. Yang dipotong hanya poin seumur hidup, yaitu
-- angka yang menentukan level. Poin yang dapat dibelanjakan tetap milik
-- member; memotongnya berarti menarik kembali sesuatu yang sudah dijanjikan
-- dapat dipakai, dan pemilik tidak meminta itu.
--
-- Periode member yang sudah ada dimulai hari migrasi ini dijalankan, bukan
-- dari tanggal mereka bergabung. Menghitung mundur berarti menghukum orang
-- dengan aturan yang belum ada saat mereka mengumpulkan poinnya.
-- ══════════════════════════════════════════════════════════════════════════


-- ── Masa berlaku level ─────────────────────────────────────────────────────
ALTER TABLE members ADD COLUMN IF NOT EXISTS tier_period_end DATE;

UPDATE members SET tier_period_end = (jakarta_today() + INTERVAL '1 year')::date
 WHERE tier_period_end IS NULL;

-- DEFAULT dipasang di kolomnya, bukan di tiap fungsi yang membuat member.
-- Ada lebih dari satu jalan pendaftaran, dan menambal satu per satu berarti
-- jalan yang terlewat menghasilkan member tanpa masa berlaku.
ALTER TABLE members ALTER COLUMN tier_period_end
      SET DEFAULT ((jakarta_today() + INTERVAL '1 year')::date);
ALTER TABLE members ALTER COLUMN tier_period_end SET NOT NULL;

COMMENT ON COLUMN members.tier_period_end IS
  'Akhir periode satu tahun level ini. Pada tanggal itu poin seumur hidup '
  'dipotong sebesar ambang levelnya, lalu levelnya dihitung ulang. Naik level '
  'memulai periode baru.';

CREATE INDEX IF NOT EXISTS members_periode ON members (tier_period_end);


-- ── Jejak tiap perpanjangan ────────────────────────────────────────────────
-- Bukan di point_ledger: buku besar itu mencatat pergerakan SALDO, dan
-- perpanjangan tidak menyentuh saldo. Menaruhnya di sana membuat setiap
-- pembacaan saldo berikutnya salah.
CREATE TABLE IF NOT EXISTS perpanjangan_level (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id         UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    tanggal           DATE NOT NULL,
    tier_sebelum      member_tier NOT NULL,
    tier_sesudah      member_tier NOT NULL,
    poin_sebelum      INT NOT NULL,
    potongan          INT NOT NULL,
    poin_sesudah      INT NOT NULL,
    periode_berikut   DATE NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE perpanjangan_level ENABLE ROW LEVEL SECURITY;
-- Tanpa policy: hanya terbaca lewat fungsi SECURITY DEFINER milik owner.

CREATE INDEX IF NOT EXISTS perpanjangan_member ON perpanjangan_level (member_id, tanggal DESC);


-- ── Mesin perpanjangannya ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION perpanjang_masa_level()
RETURNS TABLE (diproses INT, turun INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    m           members%ROWTYPE;
    v_min       INT;
    v_sebelum   INT;
    v_sesudah   INT;
    v_tier_baru member_tier;
    v_tier_lama member_tier;
    v_putar     INT;
    v_diproses  INT := 0;
    v_turun     INT := 0;
BEGIN
    FOR m IN
        SELECT * FROM members WHERE tier_period_end <= jakarta_today()
        ORDER BY tier_period_end
        FOR UPDATE
    LOOP
        -- Satu member dapat tertinggal lebih dari satu periode bila tugas
        -- terjadwal sempat mati. Tiap periode yang terlewat diselesaikan di
        -- sini juga, dengan batas putaran supaya data yang aneh tidak
        -- membuat gelung ini berputar selamanya.
        v_putar := 0;
        WHILE m.tier_period_end <= jakarta_today() AND v_putar < 20 LOOP
            v_putar := v_putar + 1;

            SELECT tr.min_lifetime_points INTO v_min
              FROM tier_rules tr WHERE tr.tier = m.tier;
            v_min := COALESCE(v_min, 0);

            v_sebelum   := m.lifetime_points;
            v_tier_lama := m.tier;
            v_sesudah   := GREATEST(v_sebelum - v_min, 0);
            v_tier_baru := compute_tier(v_sesudah);

            UPDATE members SET
                lifetime_points = v_sesudah,
                tier            = v_tier_baru,
                tier_period_end = (members.tier_period_end + INTERVAL '1 year')::date,
                updated_at      = now()
             WHERE members.id = m.id
             RETURNING * INTO m;

            INSERT INTO perpanjangan_level (
                member_id, tanggal, tier_sebelum, tier_sesudah,
                poin_sebelum, potongan, poin_sesudah, periode_berikut)
            VALUES (m.id, jakarta_today(), v_tier_lama, v_tier_baru,
                    v_sebelum, v_sebelum - v_sesudah, v_sesudah, m.tier_period_end);

            v_diproses := v_diproses + 1;
            IF v_tier_baru <> v_tier_lama THEN
                v_turun := v_turun + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN QUERY SELECT v_diproses, v_turun;
END $function$;

-- Hanya owner yang boleh menjalankannya secara manual; tugas terjadwal
-- berjalan sebagai postgres dan tidak lewat PostgREST.
REVOKE EXECUTE ON FUNCTION perpanjang_masa_level() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION owner_jalankan_perpanjangan()
RETURNS TABLE (diproses INT, turun INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menjalankan perpanjangan level.';
    END IF;
    RETURN QUERY SELECT * FROM perpanjang_masa_level();
END $function$;

REVOKE EXECUTE ON FUNCTION owner_jalankan_perpanjangan() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_jalankan_perpanjangan() TO authenticated;


CREATE OR REPLACE FUNCTION owner_perpanjangan_level(p_limit INT DEFAULT 100)
RETURNS TABLE (tanggal DATE, member_no CHARACTER VARYING, nama CHARACTER VARYING,
               tier_sebelum member_tier, tier_sesudah member_tier,
               poin_sebelum INT, potongan INT, poin_sesudah INT,
               periode_berikut DATE)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT p.tanggal, m.member_no, m.name, p.tier_sebelum, p.tier_sesudah,
           p.poin_sebelum, p.potongan, p.poin_sesudah, p.periode_berikut
      FROM perpanjangan_level p JOIN members m ON m.id = p.member_id
     WHERE is_owner()
     ORDER BY p.tanggal DESC, p.created_at DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
$function$;

REVOKE EXECUTE ON FUNCTION owner_perpanjangan_level(INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_perpanjangan_level(INT) TO authenticated;


-- ── Dijalankan sendiri tiap hari ───────────────────────────────────────────
-- 18:00 UTC = 01:00 WIB, jauh dari jam buka toko.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('perpanjang-masa-level')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'perpanjang-masa-level');

SELECT cron.schedule('perpanjang-masa-level', '0 18 * * *',
                     $$SELECT perpanjang_masa_level()$$);


-- ── create_transaction: kenaikan level memulai periode baru ──────────────
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
    v_naik         BOOLEAN := FALSE;
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

        -- K-06: kenaikan level memulai periode satu tahun yang baru.
        -- Dibandingkan lewat ambangnya, bukan lewat urutan enum: urutan enum
        -- kebetulan sejalan sekarang, tetapi ia tidak menjanjikan apa-apa bila
        -- kelak ada level yang disisipkan di tengah.
        SELECT (SELECT tr.min_lifetime_points FROM tier_rules tr WHERE tr.tier = v_tier_baru)
             > (SELECT tr.min_lifetime_points FROM tier_rules tr WHERE tr.tier = v_tier_lama)
          INTO v_naik;
        v_naik := COALESCE(v_naik, FALSE);

        UPDATE members SET
            tier = v_tier_baru,
            tier_period_end = CASE WHEN v_naik
                                   THEN (jakarta_today() + INTERVAL '1 year')::date
                                   ELSE members.tier_period_end END,
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

-- ── member_card: masa berlaku ikut terbaca ────────────────────────────────
DROP FUNCTION IF EXISTS member_card(TEXT);
CREATE OR REPLACE FUNCTION public.member_card(p_code text)
 RETURNS TABLE(member_no character varying, member_code character varying, name character varying, phone_masked text, tier member_tier, points_balance integer, lifetime_points integer, visit_count integer, total_spend numeric, tier_berikut member_tier, poin_ke_tier_berikut integer, member_sejak timestamp with time zone, masa_berlaku date, ambang_bertahan integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    m members%ROWTYPE;
    v_next member_tier;
    v_need INT;
BEGIN
    SELECT * INTO m FROM members WHERE members.member_code = upper(btrim(p_code));
    IF NOT FOUND THEN RETURN; END IF;

    SELECT tr.tier, tr.min_lifetime_points - m.lifetime_points
      INTO v_next, v_need
      FROM tier_rules tr
     WHERE tr.min_lifetime_points > m.lifetime_points
     ORDER BY tr.min_lifetime_points ASC
     LIMIT 1;

    RETURN QUERY SELECT
        m.member_no, m.member_code, m.name,
        -- Nomor disamarkan: pemegang tautan tidak perlu nomor lengkapnya
        CASE WHEN length(m.phone_wa) > 6
             THEN left(m.phone_wa, 4) || repeat('*', length(m.phone_wa) - 6) || right(m.phone_wa, 2)
             ELSE '****' END,
        m.tier, m.points_balance, m.lifetime_points,
        m.visit_count, m.total_spend,
        v_next, GREATEST(COALESCE(v_need, 0), 0), m.created_at,
        -- K-06: yang perlu diketahui member bukan cuma kapan periodenya
        -- berakhir, tetapi berapa yang harus ia kumpulkan supaya levelnya
        -- bertahan. Tanggal tanpa angka itu hanya menakut-nakuti.
        m.tier_period_end,
        (SELECT tr.min_lifetime_points FROM tier_rules tr WHERE tr.tier = m.tier);
END $function$
;


-- member_card sengaja tetap terbuka untuk anon: kartunya dibuka lewat tautan
-- tanpa login. DROP di atas memulihkan hak bawaan Supabase, jadi haknya
-- ditulis ulang di sini secara eksplisit.
REVOKE EXECUTE ON FUNCTION member_card(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION member_card(TEXT) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION create_transaction(uuid, text, text, uuid, text, jsonb,
    numeric, numeric, text, uuid, text, numeric, numeric, timestamptz, integer, uuid)
    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION create_transaction(uuid, text, text, uuid, text, jsonb,
    numeric, numeric, text, uuid, text, numeric, numeric, timestamptz, integer, uuid)
    TO authenticated;
