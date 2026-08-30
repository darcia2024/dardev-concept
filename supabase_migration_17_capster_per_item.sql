-- ==============================================================================
-- MIGRASI 17 — Capster Dicatat Per Layanan, Bukan Per Transaksi
--
-- MENGAPA SEKARANG, BUKAN NANTI
--
-- Mulai bulan ketiga capster dibayar bagi hasil 60-40, dan aturannya berbeda
-- untuk tiap jenis layanan: Haircut dibagi langsung, Speciality dipotong 15%
-- lebih dulu, Hairwash flat Rp5.000, produk tidak ikut sama sekali. Perhitungan
-- semacam itu mustahil dilakukan bila satu transaksi hanya menyimpan SATU nama
-- capster — padahal Cena bisa memotong sementara Lukman yang mencuci, dan
-- keduanya masuk di nota yang sama.
--
-- Ada alasan kedua yang lebih mendesak dan tidak bisa dikejar belakangan.
-- Selama dua bulan pertama gaji masih flat, sehingga tidak ada seorang pun
-- yang punya alasan mencatat tidak sesuai. Data dua bulan itu adalah satu-
-- satunya pembanding jujur yang akan pernah dimiliki sistem ini. Bila kolom
-- ini baru ditambahkan bulan ketiga, dua bulan itu tidak punya rinciannya, dan
-- pembandingnya hilang selamanya.
--
-- BAGAIMANA KOMPATIBILITAS DIJAGA
--
-- Kolom baru boleh kosong, dan create_transaction mengisinya dengan capster
-- transaksi bila item tidak menyebut siapa-siapa. Artinya POS lama yang belum
-- diperbarui tetap bekerja dan tetap menghasilkan data yang benar — hanya
-- tanpa kemampuan memisah. Tidak ada versi yang harus dirilis serentak.
-- ==============================================================================


-- ==============================================================================
-- 1. KOLOM BARU
-- ==============================================================================
ALTER TABLE transaction_items
    ADD COLUMN IF NOT EXISTS capster_id UUID REFERENCES capsters(id) ON DELETE SET NULL;

-- Nama ikut disimpan, sama seperti pada transactions: capster bisa dihapus
-- atau berganti nama, sementara nota lama harus tetap terbaca apa adanya.
ALTER TABLE transaction_items
    ADD COLUMN IF NOT EXISTS capster_name VARCHAR(150);

CREATE INDEX IF NOT EXISTS idx_items_capster ON transaction_items(capster_id);


-- ==============================================================================
-- 2. ISI MUNDUR DARI TRANSAKSINYA
--
-- Seluruh item yang sudah ada mewarisi capster transaksinya. Itu memang yang
-- terjadi sebenarnya: sampai hari ini satu transaksi hanya punya satu capster.
-- ==============================================================================
UPDATE transaction_items ti
   SET capster_id   = t.capster_id,
       capster_name = t.capster_name
  FROM transactions t
 WHERE ti.transaction_id = t.id
   AND ti.capster_id IS NULL;


-- ==============================================================================
-- 3. create_transaction MENERIMA CAPSTER PER ITEM
--
-- p_items kini boleh memuat "capster_id" dan "capster_name" pada tiap elemen.
-- Bila tidak ada, dipakai capster transaksinya — sehingga pemanggil lama tidak
-- perlu berubah apa pun.
-- ==============================================================================
-- Definisi di bawah BUKAN tulisan ulang. Ia diambil apa adanya dari fungsi yang
-- sedang hidup di basis data, lalu disisipi tiga hal saja: dua variabel, penentu
-- capster tiap item, dan dua kolom pada INSERT.
--
-- Menulis ulangnya dari ingatan sempat dicoba dan akan menghilangkan pengali
-- tier (v_mult), deteksi kenaikan tier (v_tier_lama/v_tier_baru), v_final, serta
-- salah menulis jenis mutasi 'REDEEM' menjadi huruf kecil. Fungsi sepanjang ini
-- terlalu mahal untuk disusun ulang dari kepala.

CREATE OR REPLACE FUNCTION public.create_transaction(p_client_uuid uuid, p_member_name text, p_member_phone text, p_capster_id uuid, p_capster_name text, p_items jsonb, p_subtotal numeric, p_final_amount numeric, p_payment_method text, p_cashier_id uuid, p_payment_ref text DEFAULT NULL::text, p_cash_paid numeric DEFAULT 0, p_cash_change numeric DEFAULT 0, p_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_redeem_points integer DEFAULT 0)
 RETURNS TABLE(id uuid, invoice_no character varying, created_at timestamp with time zone, member_tier member_tier, visit_count integer, cashier_name character varying, points_earned integer, points_balance integer, discount_points numeric, final_amount numeric, tier_naik boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_icap     UUID;
    v_iname    TEXT;
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

        -- Capster per item. Bila item tidak menyebut siapa pun, dipakai capster
        -- transaksinya -- sehingga POS lama yang belum diperbarui tetap
        -- menghasilkan data yang sama benarnya, hanya tanpa kemampuan memisah.
        v_icap  := CASE WHEN v_item->>'capster_id' ~ '^[0-9a-fA-F-]{36}$'
                        THEN (v_item->>'capster_id')::UUID ELSE p_capster_id END;
        v_iname := COALESCE(NULLIF(btrim(COALESCE(v_item->>'capster_name','')), ''), p_capster_name);

        INSERT INTO transaction_items (transaction_id, service_id, product_id, item_type,
                                       service_name, category, price, hpp_snapshot,
                                       capster_id, capster_name)
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
            CASE WHEN v_kind = 'produk' AND v_pid IS NOT NULL THEN hpp_of(v_pid) ELSE NULL END,
            v_icap,
            v_iname
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
END $function$;


-- ==============================================================================
-- 4. KINERJA CAPSTER DARI ITEM, BUKAN DARI TRANSAKSI
--
-- Selama satu transaksi hanya punya satu capster, kedua cara memberi angka
-- yang sama. Begitu satu nota dikerjakan dua orang, hanya cara ini yang benar.
-- ==============================================================================
CREATE OR REPLACE FUNCTION capster_item_report(
    p_from date DEFAULT NULL,
    p_to   date DEFAULT NULL
)
RETURNS TABLE (
    capster_name  VARCHAR,
    layanan       BIGINT,
    produk        BIGINT,
    omzet_layanan NUMERIC,
    omzet_produk  NUMERIC,
    pelanggan     BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT COALESCE(ti.capster_name, '(tanpa capster)')::VARCHAR,
           COUNT(*) FILTER (WHERE ti.item_type = 'layanan'),
           COUNT(*) FILTER (WHERE ti.item_type = 'produk'),
           COALESCE(SUM(ti.price) FILTER (WHERE ti.item_type = 'layanan'), 0),
           COALESCE(SUM(ti.price) FILTER (WHERE ti.item_type = 'produk'), 0),
           COUNT(DISTINCT ti.transaction_id)
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
     WHERE is_owner()
       AND t.business_date >= COALESCE(p_from, jakarta_today())
       AND t.business_date <= COALESCE(p_to,   jakarta_today())
     GROUP BY 1
     ORDER BY 4 DESC;
$$;

GRANT EXECUTE ON FUNCTION capster_item_report(date, date) TO authenticated;
REVOKE EXECUTE ON FUNCTION capster_item_report(date, date) FROM anon;


-- ==============================================================================
-- 5. KINERJA SENDIRI UNTUK CAPSTER — IKUT MEMAKAI ITEM
--
-- Kedua definisi di bawah juga diambil dari fungsi yang hidup, lalu ditambal
-- pada satu tempat saja. Tanda tangannya sengaja tidak diubah: capster.html
-- membaca kolom bernama waktu/invoice_no/service_name/price, dan mengubahnya
-- akan mematikan halaman capster tanpa ada yang tahu sampai seseorang membuka
-- ponselnya.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.my_capster_services(p_date date DEFAULT NULL::date)
 RETURNS TABLE(waktu timestamp with time zone, invoice_no character varying, service_name character varying, price numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id UUID;
    v_d  date := COALESCE(p_date, jakarta_today());
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Akun ini belum ditautkan ke data capster mana pun.';
    END IF;

    RETURN QUERY
    SELECT t.created_at, t.invoice_no, i.service_name, i.price
      FROM transactions t
      JOIN transaction_items i ON i.transaction_id = t.id
     -- Sumber capster pindah ke item: bila satu nota dikerjakan dua orang,
     -- masing-masing hanya melihat bagiannya sendiri. Tanda tangannya tidak
     -- berubah, sehingga halaman capster tidak perlu ikut dirilis.
     WHERE i.capster_id = v_id
       AND t.business_date = v_d
     ORDER BY t.created_at DESC;
END $function$;

GRANT EXECUTE ON FUNCTION my_capster_services(date) TO authenticated;


CREATE OR REPLACE FUNCTION public.my_capster_daily(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(business_date date, heads bigint, services_done bigint, revenue numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id   UUID;
    v_to   date := COALESCE(p_to, jakarta_today());
    v_from date := COALESCE(p_from, v_to - 29);
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Akun ini belum ditautkan ke data capster mana pun.';
    END IF;
    IF v_to - v_from > 92 THEN
        RAISE EXCEPTION 'Rentang maksimal 92 hari.';
    END IF;

    RETURN QUERY
    -- Dihitung dari item, bukan dari nota. Sebelumnya seluruh final_amount
    -- satu nota masuk ke capster transaksinya -- keliru begitu ada nota yang
    -- dikerjakan dua orang, karena yang mencuci ikut menerima nilai potongnya.
    --
    -- final_amount tidak dipakai lagi di sini karena ia nilai satu NOTA, bukan
    -- satu item; yang dijumlahkan adalah harga item miliknya sendiri. Akibatnya
    -- jumlah ini tidak memperhitungkan diskon poin, dan memang seharusnya
    -- begitu: diskon ditanggung toko, bukan mengurangi hasil kerja capster.
    SELECT t.business_date,
           COUNT(DISTINCT t.id)                       AS heads,
           COUNT(i.id)::BIGINT                        AS services_done,
           COALESCE(SUM(i.price), 0)                  AS revenue
      FROM transaction_items i
      JOIN transactions t ON t.id = i.transaction_id
     WHERE i.capster_id = v_id
       AND t.business_date BETWEEN v_from AND v_to
     GROUP BY t.business_date
     ORDER BY t.business_date DESC;
END $function$;

GRANT EXECUTE ON FUNCTION my_capster_daily(date, date) TO authenticated;
