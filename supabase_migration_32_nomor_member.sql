-- ==============================================================================
-- MIGRASI 32 - Nomor Member UB-0000, Reward Diskon Dibuang, Minimal Tukar
--
-- Tiga perubahan yang diminta pemilik setelah spesifikasi MBR-UB-01-DEV.
--
-- 1. NOMOR MEMBER BERFORMAT UB-0000
--
-- Spesifikasi bagian 01 menyebut member_id sebagai "nomor member dengan
-- format UB-0000, unik dan tidak pernah berubah". Itu nomor identitas yang
-- disebut orang, dicetak di kartu, dan dibaca kasir.
--
-- member_code yang acak TIDAK diganti, dan ini bukan penolakan terhadap
-- permintaan itu melainkan pemisahan dua tugas yang berbeda. member_code
-- adalah kunci tautan kartu digital, dan member_card() dapat dipanggil oleh
-- anon. Kalau kuncinya berubah menjadi UB-0001, siapa pun dapat menyusuri
-- UB-0001 sampai UB-9999 dan membaca nama, nomor tersamar, saldo poin, level,
-- serta total belanja setiap member. Spesifikasinya sendiri tidak pernah
-- meminta tautan kartu memakai nomor itu.
--
-- Nomor diberikan lewat sequence, bukan lewat "MAX(nomor) + 1". Dua kasir
-- yang mendaftarkan member pada detik yang sama akan membaca MAX yang sama
-- dan menghasilkan nomor kembar; sequence tidak pernah memberikan angka yang
-- sama dua kali sekalipun transaksinya berguling balik.
--
-- 2. REWARD DISKON RUPIAH DIBUANG
--
-- Sesudah satuan poin berubah, "Diskon Rp 10.000" berharga 10.000 poin dan
-- memberi potongan Rp 10.000. Persis sama dengan memakai poin langsung di
-- kasir, hanya lewat jalan memutar yang membuat kasir ragu memilih.
--
-- "Diskon Rp 25.000" lebih dari sekadar kembar: ia jalan pintas. redeem_reward
-- tidak tunduk pada max_redeem_percent maupun min_redeem_points, sehingga
-- batas 25 persen yang dijaga di kasir dapat dilewati lewat kartu member.
-- Keduanya belum pernah diklaim sekali pun, jadi dibuang tanpa meninggalkan
-- riwayat yang menggantung.
--
-- Reward berupa layanan dan produk tetap ada. Nilainya memang di atas satu
-- banding satu, dan justru itu yang membuat orang mengumpulkan poin alih-alih
-- membelanjakannya receh demi receh.
--
-- 3. MINIMAL TUKAR 5.000 MENJADI 2.500
--
-- Hairwash berharga Rp 15.000, dan batas 25 persen hanya mengizinkan 3.750
-- poin. Dengan minimal 5.000, poin tidak akan pernah dapat dipakai di layanan
-- itu: kasir menerima dua pesan yang saling meniadakan tanpa penjelasan.
-- Angka baru harus berada di bawah 3.750 sekaligus cukup tinggi untuk
-- mencegah penukaran receh. Nilai ini terikat pada harga layanan termurah,
-- jadi perlu ditinjau lagi bila ada layanan yang lebih murah.
-- ==============================================================================


-- ── 1. Nomor member UB-0000 ────────────────────────────────────────────────
ALTER TABLE members ADD COLUMN IF NOT EXISTS member_no VARCHAR(8);

CREATE SEQUENCE IF NOT EXISTS member_no_seq AS INT START WITH 1;

CREATE OR REPLACE FUNCTION next_member_no()
RETURNS VARCHAR
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT ('UB-' || lpad(nextval('member_no_seq')::TEXT, 4, '0'))::VARCHAR
$function$;

COMMENT ON COLUMN members.member_no IS
  'member_id pada spesifikasi: nomor identitas yang disebut orang dan dicetak '
  'di kartu. Berbeda dari member_code yang merupakan kunci rahasia tautan '
  'kartu digital dan tidak boleh dapat ditebak.';

-- Member yang sudah ada dinomori menurut urutan bergabung, supaya nomor kecil
-- benar-benar berarti bergabung lebih awal.
DO $nomori$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM members WHERE member_no IS NULL ORDER BY created_at, id
    LOOP
        UPDATE members SET member_no = next_member_no() WHERE id = r.id;
    END LOOP;
END
$nomori$;

-- Dipasang sesudah pengisian, sebab kolomnya masih kosong sebelum itu.
ALTER TABLE members ALTER COLUMN member_no SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS members_member_no_unik ON members (member_no);

-- Sequence dimajukan melewati nomor yang sudah terpakai supaya member
-- berikutnya tidak menabrak nomor yang sudah ada.
SELECT setval('member_no_seq',
              GREATEST((SELECT COALESCE(MAX(substring(member_no from 4)::INT), 0)
                          FROM members), 1));


-- ── 2. Reward diskon rupiah dibuang ────────────────────────────────────────
DELETE FROM rewards
 WHERE name IN ('Diskon Rp 10.000', 'Diskon Rp 25.000')
   AND NOT EXISTS (SELECT 1 FROM reward_claims rc WHERE rc.reward_id = rewards.id);


-- ── 3. Minimal tukar mengikuti layanan termurah ────────────────────────────
UPDATE loyalty_settings SET min_redeem_points = 2500;


-- ── Member baru langsung bernomor ──────────────────────────────────────────
-- Ditambal dari definisi yang sedang berjalan. Tanpa ini, member_no yang
-- NOT NULL akan menolak setiap pendaftaran member baru di kasir.
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
        earn_multiplier_used, tier_before,
        cashier_id, cashier_ref_id, cashier_name, created_at, business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'), p_capster_id, p_capster_name, v_summary,
        p_subtotal, v_disc, v_discount.id, v_discount.name, v_manual,
        v_final, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, v_cash_change, v_earn,
        CASE WHEN v_member.id IS NOT NULL THEN v_mult END, v_tier_lama,
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


-- ── Nomor member ikut sampai ke layar ──────────────────────────────────────
-- Nomor yang tidak pernah terlihat sama saja tidak ada. Keempat fungsi ini
-- yang memasok kartu member, layar kasir, pemindai kartu, dan daftar member
-- milik owner. Tanda tangannya berubah, jadi masing-masing dibuang dulu
-- sebelum dibuat ulang; CREATE OR REPLACE menolak perubahan tipe hasil.
DROP FUNCTION IF EXISTS member_card(text);
DROP FUNCTION IF EXISTS lookup_member(text);
DROP FUNCTION IF EXISTS lookup_member_by_code(text);
DROP FUNCTION IF EXISTS owner_members_list(integer);

CREATE OR REPLACE FUNCTION public.member_card(p_code text)
 RETURNS TABLE(member_no character varying, member_code character varying, name character varying, phone_masked text, tier member_tier, points_balance integer, lifetime_points integer, visit_count integer, total_spend numeric, tier_berikut member_tier, poin_ke_tier_berikut integer, member_sejak timestamp with time zone)
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
        v_next, GREATEST(COALESCE(v_need, 0), 0), m.created_at;
END $function$
;

CREATE OR REPLACE FUNCTION public.lookup_member(p_phone text)
 RETURNS TABLE(name character varying, tier member_tier, visit_count integer, points_balance integer, member_code character varying, member_no character varying)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    IF p_phone IS NULL OR length(regexp_replace(p_phone, '\D', '', 'g')) < 9 THEN RETURN; END IF;
    RETURN QUERY
    SELECT m.name, m.tier, m.visit_count, m.points_balance, m.member_code, m.member_no
      FROM members m WHERE m.phone_wa = p_phone LIMIT 1;
END $function$
;

CREATE OR REPLACE FUNCTION public.lookup_member_by_code(p_code text)
 RETURNS TABLE(name character varying, phone_wa character varying, tier member_tier, points_balance integer, visit_count integer, member_code character varying, member_no character varying)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    RETURN QUERY
    SELECT m.name, m.phone_wa, m.tier, m.points_balance, m.visit_count, m.member_code, m.member_no
      FROM members m WHERE m.member_code = upper(btrim(p_code)) LIMIT 1;
END $function$
;

CREATE OR REPLACE FUNCTION public.owner_members_list(p_limit integer DEFAULT 200)
 RETURNS TABLE(member_id uuid, member_no character varying, name character varying, phone_wa character varying, tier text, points_balance integer, visit_count integer, total_spend numeric, jumlah_transaksi bigint, terakhir date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT m.id, m.member_no, m.name, m.phone_wa, m.tier::TEXT, m.points_balance,
           m.visit_count, m.total_spend,
           COUNT(t.id), MAX(t.business_date)
      FROM members m
      LEFT JOIN transactions t ON t.member_id = m.id
     WHERE is_owner()
     GROUP BY m.id
     ORDER BY m.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 500));
$function$
;

-- ── Hak akses dirapikan sesudah DROP ───────────────────────────────────────
-- Membuang lalu membuat ulang fungsi mengembalikan hak EXECUTE ke PUBLIC,
-- dan PUBLIC mencakup anon. Ketiga fungsi selain kartu member hanya dipanggil
-- dari layar yang sudah login, jadi haknya dipersempit mengikuti pola yang
-- sudah dipakai migrasi 25 dan 27.
--
-- owner_members_list sebenarnya sudah dijaga is_owner() di dalam dan hanya
-- mengembalikan larik kosong untuk anon, tetapi menyandarkan kerahasiaan pada
-- satu penjaga di dalam fungsi berarti kesalahan kecil pada penjaga itu
-- langsung membuka seluruh daftar member.
REVOKE EXECUTE ON FUNCTION member_card(text)            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION lookup_member(text)          FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION lookup_member_by_code(text)  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION owner_members_list(integer)  FROM PUBLIC;

-- Kartu member dibuka lewat tautan tanpa login, jadi anon tetap perlu.
GRANT EXECUTE ON FUNCTION member_card(text) TO anon, authenticated;

-- Sisanya hanya dipanggil dari POS dan layar owner yang sudah login.
GRANT EXECUTE ON FUNCTION lookup_member(text)         TO authenticated;
GRANT EXECUTE ON FUNCTION lookup_member_by_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION owner_members_list(integer) TO authenticated;

-- Supabase memasang default privileges yang memberi EXECUTE kepada anon pada
-- SETIAP fungsi yang baru dibuat. Mencabut dari PUBLIC saja tidak cukup:
-- anon adalah peran tersendiri dan haknya harus dicabut sendiri, persis
-- seperti yang dilakukan migrasi 27 untuk bookings_list dan decide_booking.
REVOKE EXECUTE ON FUNCTION lookup_member(text)          FROM anon;
REVOKE EXECUTE ON FUNCTION lookup_member_by_code(text)  FROM anon;
REVOKE EXECUTE ON FUNCTION owner_members_list(integer)  FROM anon;
