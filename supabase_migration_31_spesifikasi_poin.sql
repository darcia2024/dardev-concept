-- ==============================================================================
-- MIGRASI 31 - Spesifikasi Poin & Level Member (MBR-UB-01-DEV Draf 1)
--
-- Menerapkan bagian 01 Model Data, 02 Rumus Poin, 03 Level & Pengali, dan
-- bagian 06 Data Transaksi dari spesifikasi klien.
--
-- SATUAN POIN BERUBAH, DAN INI BAGIAN PALING BERBAHAYA DI SELURUH MIGRASI
--
-- Aturan lama: Rp 10.000 belanja menghasilkan 1 poin, dan 1 poin bernilai
-- Rp 500 saat ditukar. Artinya setiap Rp 10.000 belanja mengembalikan Rp 500,
-- yaitu 5 persen.
--
-- Aturan baru: poin didapat 7 persen dari nilai yang dibayar, dan 1 poin
-- bernilai Rp 1. Setiap Rp 10.000 belanja menghasilkan 700 poin senilai
-- Rp 700, yaitu 7 persen.
--
-- Satuannya berubah 500 kali lipat. Kalau angka-angka lama dibiarkan apa
-- adanya, saldo 43 poin milik enam member yang tadinya bernilai Rp 21.500
-- mendadak hanya bernilai Rp 43. Karena itu SETIAP angka yang bersatuan poin
-- dikalikan 500: saldo member, total poin, buku besar poin, harga reward, dan
-- batas minimal penukaran. Yang TIDAK dikalikan hanyalah ambang level, sebab
-- angkanya ditetapkan langsung oleh klien di bagian 03 dan bukan hasil
-- konversi.
--
-- Buku besar ikut dikonversi, termasuk balance_after. Membiarkannya dalam
-- satuan lama akan membuat audit mutasi poin milik owner menampilkan saldo
-- yang tidak pernah cocok dengan saldo member yang sebenarnya, dan angka yang
-- tidak pernah cocok lebih merusak daripada riwayat yang dinyatakan ulang
-- secara terbuka. Satu baris penjelasan disisipkan ke tiap member supaya
-- perubahan ini terbaca di layar audit, bukan hanya ada di berkas ini.
--
-- YANG TIDAK DIKERJAKAN DI SINI
--
-- R-06 dan R-07 (kadaluarsa 12 bulan dengan kelompok perolehan FIFO) belum
-- dibangun. Itu membutuhkan tabel kelompok poin tersendiri beserta tugas
-- terjadwal, dan menumpangkannya ke migrasi ini akan membuat dua perubahan
-- besar bercampur dalam satu langkah yang tidak dapat dibalik sebagian.
--
-- K-01 (batas pakai poin) belum dijawab klien. Batas 25 persen yang sudah
-- berjalan DIPERTAHANKAN, bukan dilepas. Melepas batas adalah arah yang
-- berisiko: tanpa batas, member level atas dapat memotong tagihan sampai nol
-- sementara bagi hasil capster tetap dibayar penuh oleh pemilik.
-- ==============================================================================


-- ── 01 Model Data: field member yang belum ada ─────────────────────────────
-- tanggal_lahir memicu poin ulang tahun (K-03 belum dijawab, jadi baru
-- datanya yang disiapkan). catatan_potongan adalah benefit level Gold ke atas.
ALTER TABLE members ADD COLUMN IF NOT EXISTS birth_date date;
ALTER TABLE members ADD COLUMN IF NOT EXISTS cut_notes  text;

COMMENT ON COLUMN members.lifetime_points IS
  'total_poin pada spesifikasi: hanya bertambah, tidak pernah berkurang oleh '
  'penukaran maupun kadaluarsa. Angka ini yang menentukan level.';
COMMENT ON COLUMN members.points_balance IS
  'saldo_poin pada spesifikasi: bertambah dan berkurang. Tidak boleh negatif.';
COMMENT ON COLUMN members.tier IS
  'Nilai turunan dari lifetime_points lewat compute_tier(). Jangan diubah manual.';


-- ── 06 Data Transaksi: field audit yang belum ada ──────────────────────────
-- Pengali dan level disimpan apa adanya saat transaksi berjalan supaya
-- perhitungan tetap dapat diaudit ulang setelah ambang atau pengali diubah.
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS earn_multiplier_used NUMERIC(4,2);
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tier_before member_tier;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tier_after  member_tier;


-- ── 02 Rumus Poin: persentase menggantikan rupiah per poin ─────────────────
ALTER TABLE loyalty_settings
  ADD COLUMN IF NOT EXISTS earn_percent NUMERIC(5,2) NOT NULL DEFAULT 7.00;

ALTER TABLE loyalty_settings
  DROP CONSTRAINT IF EXISTS loyalty_settings_earn_percent_masuk_akal;
ALTER TABLE loyalty_settings
  ADD CONSTRAINT loyalty_settings_earn_percent_masuk_akal
  CHECK (earn_percent > 0 AND earn_percent <= 100);


-- ── Konversi satuan poin: 1 poin lama = Rp 500 = 500 poin baru ─────────────
-- Dijalankan sekali saja. Penanda disimpan di loyalty_settings supaya migrasi
-- yang tidak sengaja dijalankan dua kali tidak melipatgandakan saldo member.
ALTER TABLE loyalty_settings
  ADD COLUMN IF NOT EXISTS redenominated_at timestamptz;

DO $redenominasi$
DECLARE
    v_faktor CONSTANT INT := 500;
    v_sudah  timestamptz;
BEGIN
    SELECT redenominated_at INTO v_sudah FROM loyalty_settings LIMIT 1;
    IF v_sudah IS NOT NULL THEN
        RAISE NOTICE 'Redenominasi sudah dijalankan pada %, dilewati.', v_sudah;
        RETURN;
    END IF;

    -- Jejak dulu, baru angkanya diubah. Kalau urutannya dibalik, catatan
    -- saldo sebelum konversi sudah tidak dapat dibaca lagi.
    INSERT INTO point_ledger (member_id, transaction_id, type, points_amount,
                              balance_after, notes)
    SELECT m.id, NULL, 'ADJUSTMENT', m.points_balance * (v_faktor - 1),
           m.points_balance * v_faktor,
           'Penyesuaian satuan poin: 1 poin lama senilai Rp 500 menjadi 500 poin '
           || 'baru senilai Rp 1 masing-masing. Saldo sebelum penyesuaian '
           || m.points_balance || ' poin, nilainya tetap Rp '
           || (m.points_balance * 500) || '.'
      FROM members m
     WHERE m.points_balance > 0;

    UPDATE point_ledger
       SET points_amount = points_amount * v_faktor,
           balance_after = balance_after * v_faktor
     WHERE type <> 'ADJUSTMENT' OR notes NOT LIKE 'Penyesuaian satuan poin:%';

    UPDATE members
       SET points_balance  = points_balance  * v_faktor,
           lifetime_points = lifetime_points * v_faktor;

    UPDATE transactions SET points_earned = points_earned * v_faktor
     WHERE points_earned > 0;

    -- Harga reward ikut naik supaya nilai rupiahnya tidak berubah: reward
    -- 20 poin yang dulu setara Rp 10.000 kini berharga 10.000 poin.
    UPDATE rewards SET point_cost = point_cost * v_faktor;

    UPDATE loyalty_settings
       SET min_redeem_points = min_redeem_points * v_faktor,
           redenominated_at  = now();
END
$redenominasi$;


-- ── 02 Rumus Poin: nilai tukar dan minimal penukaran ───────────────────────
-- max_redeem_percent sengaja tidak disentuh. Lihat catatan K-01 di kepala
-- berkas ini.
UPDATE loyalty_settings
   SET earn_percent            = 7.00,
       rupiah_per_point_redeem = 1;


-- ── 03 Level & Pengali ─────────────────────────────────────────────────────
-- Ambang diambil apa adanya dari spesifikasi, bukan hasil konversi satuan.
-- Kebetulan ambang Gold lama (100 poin) berkonversi tepat ke 50.000, tetapi
-- tiga level di atasnya justru diturunkan klien sehingga lebih mudah dicapai.
UPDATE tier_rules SET min_lifetime_points =      0, earn_multiplier = 1.00,
       note = 'Tier awal seluruh member baru' WHERE tier = 'Silver';
UPDATE tier_rules SET min_lifetime_points =  50000, earn_multiplier = 1.20,
       note = 'Setara belanja sekitar Rp 710.000' WHERE tier = 'Gold';
UPDATE tier_rules SET min_lifetime_points = 100000, earn_multiplier = 1.35,
       note = 'Setara belanja sekitar Rp 1.310.000' WHERE tier = 'Platinum';
UPDATE tier_rules SET min_lifetime_points = 200000, earn_multiplier = 1.50,
       note = 'Setara belanja sekitar Rp 2.370.000' WHERE tier = 'Infinite';
UPDATE tier_rules SET min_lifetime_points = 350000, earn_multiplier = 2.00,
       note = 'Setara belanja sekitar Rp 3.800.000' WHERE tier = 'Black';

-- R-12: level tidak pernah turun pada rancangan ini, tetapi ambangnya baru
-- saja berubah. Seluruh member dihitung ulang sekali agar levelnya benar
-- menurut aturan yang berlaku sekarang.
UPDATE members SET tier = compute_tier(lifetime_points), updated_at = now()
 WHERE tier IS DISTINCT FROM compute_tier(lifetime_points);


-- ── Pengaturan poin milik owner ikut mengenal persentase ───────────────────
DROP FUNCTION IF EXISTS update_loyalty_settings(INT, INT, INT, NUMERIC, BOOLEAN);

CREATE OR REPLACE FUNCTION update_loyalty_settings(
    p_earn_percent NUMERIC,
    p_rupiah_per_point_redeem INT,
    p_min_redeem_points INT,
    p_max_redeem_percent NUMERIC,
    p_is_active BOOLEAN
)
RETURNS TABLE (earn_percent NUMERIC, rupiah_per_point_redeem INT,
               min_redeem_points INT, max_redeem_percent NUMERIC, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profiles p
                    WHERE p.id = auth.uid() AND p.role = 'owner') THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah pengaturan poin.';
    END IF;

    IF p_earn_percent IS NULL OR p_earn_percent <= 0 OR p_earn_percent > 100 THEN
        RAISE EXCEPTION 'Persentase perolehan poin harus antara 0 dan 100.';
    END IF;
    IF p_rupiah_per_point_redeem IS NULL OR p_rupiah_per_point_redeem < 1 THEN
        RAISE EXCEPTION 'Nilai tukar satu poin minimal Rp 1.';
    END IF;
    IF p_min_redeem_points IS NULL OR p_min_redeem_points < 0 THEN
        RAISE EXCEPTION 'Minimal penukaran tidak boleh negatif.';
    END IF;
    IF p_max_redeem_percent IS NULL
       OR p_max_redeem_percent <= 0 OR p_max_redeem_percent > 100 THEN
        RAISE EXCEPTION 'Batas diskon poin harus antara 0 dan 100 persen.';
    END IF;

    UPDATE loyalty_settings s
       SET earn_percent            = p_earn_percent,
           rupiah_per_point_redeem = p_rupiah_per_point_redeem,
           min_redeem_points       = p_min_redeem_points,
           max_redeem_percent      = p_max_redeem_percent,
           is_active               = COALESCE(p_is_active, s.is_active),
           updated_at              = now();

    RETURN QUERY
    SELECT s.earn_percent, s.rupiah_per_point_redeem, s.min_redeem_points,
           s.max_redeem_percent, s.is_active
      FROM loyalty_settings s;
END $function$;

REVOKE EXECUTE ON FUNCTION update_loyalty_settings(NUMERIC, INT, INT, NUMERIC, BOOLEAN) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION update_loyalty_settings(NUMERIC, INT, INT, NUMERIC, BOOLEAN) TO authenticated;


-- ── 02 Rumus Poin & 06 Data Transaksi di dalam create_transaction ──────────
-- Ditambal dari definisi yang sedang berjalan di produksi, bukan ditulis
-- ulang dari ingatan. Tiga hal yang berubah: rumus perolehan memakai persen
-- dari nilai dibayar, pengali yang dipakai ikut disimpan, dan level sebelum
-- serta sesudah transaksi dicatat terpisah.
--
-- Urutan operasi R-09 sampai R-11 sebenarnya sudah benar sejak awal: potongan
-- poin memang sudah dikurangi lebih dulu lewat v_final, pengali memang sudah
-- diambil dari v_member.tier yang dibaca sebelum transaksi, dan pembulatan
-- memang sudah floor. Yang keliru hanya tetapannya.

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


-- ── Halaman depan ikut mengabarkan aturan yang baru ────────────────────────
-- Tanpa ini pengunjung membaca "setiap belanja Rp 10.000 menghasilkan 1 poin,
-- tiap poin bernilai Rp 1" — kolom rupiah_per_point sudah tidak dipakai rumus
-- apa pun, dan digabung dengan nilai tukar yang baru kalimatnya membuat
-- program poinnya terdengar tidak berharga.
CREATE OR REPLACE FUNCTION public.public_landing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT jsonb_build_object(
        'layanan', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', s.id, 'nama', s.name, 'kategori', s.category,
                       'harga', s.price, 'menit', s.duration_minutes)
                   ORDER BY s.price)
              FROM services s WHERE s.is_active
        ), '[]'::jsonb),
        'kapster', COALESCE((
            SELECT jsonb_agg(c.name ORDER BY c.name)
              FROM capsters c WHERE c.is_active
        ), '[]'::jsonb),
        'outlet', (
            SELECT jsonb_build_object(
                       'nama', o.name, 'alamat', o.address, 'telepon', o.phone,
                       'lat', o.latitude, 'lng', o.longitude)
              FROM outlets o WHERE o.is_active ORDER BY o.sort_order LIMIT 1
        ),
        'jam', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'dow', j.dow, 'buka', j.buka, 'tutup', j.tutup, 'libur', j.libur)
                   ORDER BY j.dow)
              FROM jam_operasional j
        ), '[]'::jsonb),
        'poin', (
            SELECT jsonb_build_object(
                       'persen_poin', ls.earn_percent,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    );
$function$
;
