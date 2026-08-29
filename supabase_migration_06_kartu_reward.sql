-- ==============================================================================
-- MIGRASI 06 — Kartu Member Digital & Katalog Reward (Fase 2)
--
-- MODEL AKSES KARTU MEMBER
--   Pelanggan barbershop tidak akan membuat akun, dan OTP WhatsApp menuntut
--   gateway berbayar yang berada di luar scope. Kartu memakai pola loyalty
--   card yang lazim: satu tautan pribadi berisi member_code, dikirim lewat
--   struk WhatsApp. Kode itulah kredensialnya.
--
--   Konsekuensinya diakui, bukan disembunyikan: pemegang tautan dapat melihat
--   poin dan riwayat member tersebut. Karena itu:
--     * kartu hanya menampilkan data milik pemegang kode — tidak ada daftar,
--       tidak ada penelusuran, tidak ada member lain;
--     * nomor WhatsApp disamarkan sebagian;
--     * penukaran reward TIDAK menyelesaikan dirinya sendiri. Ia menghasilkan
--       kode klaim yang harus divalidasi kasir di meja, sehingga orang yang
--       memegang tautan tetap tidak bisa membelanjakan poin dari jauh.
--
--   Seluruh fungsi di bawah berjalan SECURITY DEFINER dan hanya menerima
--   member_code sebagai kunci; tidak ada tabel yang dibuka untuk anon.
-- ==============================================================================

-- 1. KATALOG REWARD -----------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE reward_kind AS ENUM ('Diskon', 'Produk', 'Layanan');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS rewards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    description TEXT,
    kind reward_kind NOT NULL DEFAULT 'Diskon',
    point_cost INT NOT NULL CHECK (point_cost > 0),
    -- Nilai rupiah untuk reward berjenis diskon; nol untuk produk/layanan
    discount_value NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
    min_tier member_tier NOT NULL DEFAULT 'Silver',
    stock INT,                       -- NULL = tak terbatas
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. KLAIM PENUKARAN ----------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE claim_status AS ENUM ('menunggu', 'dipakai', 'batal', 'kedaluwarsa');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS reward_claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    claim_code VARCHAR(12) UNIQUE NOT NULL,
    member_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    reward_id UUID REFERENCES rewards(id) ON DELETE SET NULL,
    reward_name VARCHAR(150) NOT NULL,
    point_cost INT NOT NULL,
    discount_value NUMERIC(12,2) NOT NULL DEFAULT 0,
    status claim_status NOT NULL DEFAULT 'menunggu',
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    used_by_cashier UUID REFERENCES cashiers(id) ON DELETE SET NULL,
    transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_claims_member ON reward_claims(member_id);
CREATE INDEX IF NOT EXISTS idx_claims_status ON reward_claims(status);

CREATE OR REPLACE FUNCTION generate_claim_code()
RETURNS VARCHAR
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v VARCHAR(12);
BEGIN
    LOOP
        v := 'RW' || upper(translate(substr(encode(extensions.gen_random_bytes(5),'base64'),1,6),
                                     '+/=OI01lo','ABCDEFGHJ'));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM reward_claims rc WHERE rc.claim_code = v);
    END LOOP;
    RETURN v;
END $$;

-- 3. ISI KARTU MEMBER ---------------------------------------------------------
CREATE OR REPLACE FUNCTION member_card(p_code TEXT)
RETURNS TABLE (
    member_code VARCHAR, name VARCHAR, phone_masked TEXT,
    tier member_tier, points_balance INT, lifetime_points INT,
    visit_count INT, total_spend NUMERIC,
    tier_berikut member_tier, poin_ke_tier_berikut INT, member_sejak TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
        m.member_code, m.name,
        -- Nomor disamarkan: pemegang tautan tidak perlu nomor lengkapnya
        CASE WHEN length(m.phone_wa) > 6
             THEN left(m.phone_wa, 4) || repeat('*', length(m.phone_wa) - 6) || right(m.phone_wa, 2)
             ELSE '****' END,
        m.tier, m.points_balance, m.lifetime_points,
        m.visit_count, m.total_spend,
        v_next, GREATEST(COALESCE(v_need, 0), 0), m.created_at;
END $$;

-- 4. RIWAYAT KUNJUNGAN PADA KARTU ---------------------------------------------
-- Tanpa nomor nota internal dan tanpa nama kasir: pelanggan hanya perlu tahu
-- kapan ia datang, dilayani siapa, dan berapa poin yang ia peroleh.
CREATE OR REPLACE FUNCTION member_card_history(p_code TEXT)
RETURNS TABLE (
    waktu TIMESTAMPTZ, layanan TEXT, capster VARCHAR,
    dibayar NUMERIC, poin INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    SELECT m.id INTO v_id FROM members m WHERE m.member_code = upper(btrim(p_code));
    IF v_id IS NULL THEN RETURN; END IF;
    RETURN QUERY
    SELECT t.created_at, t.service_summary, t.capster_name, t.final_amount, t.points_earned
      FROM transactions t WHERE t.member_id = v_id
     ORDER BY t.created_at DESC LIMIT 30;
END $$;

-- 5. KATALOG REWARD YANG DAPAT DILIHAT MEMBER ---------------------------------
CREATE OR REPLACE FUNCTION member_rewards(p_code TEXT)
RETURNS TABLE (
    id UUID, name VARCHAR, description TEXT, kind reward_kind,
    point_cost INT, discount_value NUMERIC, min_tier member_tier,
    stock INT, cukup_poin BOOLEAN, tier_memenuhi BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE m members%ROWTYPE;
BEGIN
    SELECT * INTO m FROM members WHERE members.member_code = upper(btrim(p_code));
    RETURN QUERY
    SELECT r.id, r.name, r.description, r.kind, r.point_cost, r.discount_value,
           r.min_tier, r.stock,
           COALESCE(m.points_balance, 0) >= r.point_cost,
           CASE WHEN m.id IS NULL THEN false ELSE
                (SELECT tra.min_lifetime_points FROM tier_rules tra WHERE tra.tier = m.tier)
                >= (SELECT trb.min_lifetime_points FROM tier_rules trb WHERE trb.tier = r.min_tier)
           END
      FROM rewards r
     WHERE r.is_active AND (r.stock IS NULL OR r.stock > 0)
     ORDER BY r.sort_order, r.point_cost;
END $$;

-- 6. PENUKARAN REWARD ---------------------------------------------------------
-- Poin dipotong saat klaim dibuat agar tidak dapat dibelanjakan dua kali,
-- tetapi hadiahnya baru berpindah setelah kasir memvalidasi kode klaim.
CREATE OR REPLACE FUNCTION redeem_reward(p_code TEXT, p_reward_id UUID)
RETURNS TABLE (
    claim_code VARCHAR, reward_name VARCHAR, point_cost INT,
    expires_at TIMESTAMPTZ, points_balance INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    m       members%ROWTYPE;
    r       rewards%ROWTYPE;
    v_claim VARCHAR(12);
    v_min   INT;
    v_cur   INT;
BEGIN
    -- Kunci baris member: mencegah dua permintaan bersamaan memakai poin sama
    SELECT * INTO m FROM members WHERE members.member_code = upper(btrim(p_code)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kartu tidak dikenali.'; END IF;

    SELECT * INTO r FROM rewards WHERE rewards.id = p_reward_id AND is_active FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reward tidak tersedia.'; END IF;
    IF r.stock IS NOT NULL AND r.stock <= 0 THEN RAISE EXCEPTION 'Stok reward habis.'; END IF;
    IF m.points_balance < r.point_cost THEN
        RAISE EXCEPTION 'Poin belum cukup. Saldo Anda % poin, reward ini butuh % poin.',
            m.points_balance, r.point_cost;
    END IF;

    SELECT tra.min_lifetime_points INTO v_min FROM tier_rules tra WHERE tra.tier = r.min_tier;
    SELECT trb.min_lifetime_points INTO v_cur FROM tier_rules trb WHERE trb.tier = m.tier;
    IF v_cur < v_min THEN
        RAISE EXCEPTION 'Reward ini khusus member % ke atas.', r.min_tier;
    END IF;

    -- Satu klaim aktif per reward per member: mencegah menumpuk klaim
    -- yang tidak pernah ditebus sambil terus memotong poin.
    IF EXISTS (
        SELECT 1 FROM reward_claims rc
         WHERE rc.member_id = m.id AND rc.reward_id = r.id
           AND rc.status = 'menunggu' AND rc.expires_at > now()
    ) THEN
        RAISE EXCEPTION 'Anda masih punya klaim aktif untuk reward ini. Tunjukkan kodenya ke kasir.';
    END IF;

    v_claim := generate_claim_code();

    UPDATE members SET points_balance = members.points_balance - r.point_cost
     WHERE members.id = m.id RETURNING * INTO m;

    IF r.stock IS NOT NULL THEN
        UPDATE rewards SET stock = rewards.stock - 1 WHERE rewards.id = r.id;
    END IF;

    INSERT INTO reward_claims (claim_code, member_id, reward_id, reward_name,
                               point_cost, discount_value, expires_at)
    VALUES (v_claim, m.id, r.id, r.name, r.point_cost, r.discount_value,
            now() + interval '7 days');

    INSERT INTO point_ledger (member_id, transaction_id, type, points_amount, balance_after, notes)
    VALUES (m.id, NULL, 'REDEEM', -r.point_cost, m.points_balance,
            'Tukar reward "' || r.name || '" (klaim ' || v_claim || ')');

    RETURN QUERY SELECT v_claim, r.name, r.point_cost,
                        (now() + interval '7 days')::TIMESTAMPTZ, m.points_balance;
END $$;

-- 7. KLAIM AKTIF MILIK MEMBER -------------------------------------------------
CREATE OR REPLACE FUNCTION member_claims(p_code TEXT)
RETURNS TABLE (
    claim_code VARCHAR, reward_name VARCHAR, status claim_status,
    expires_at TIMESTAMPTZ, used_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    SELECT m.id INTO v_id FROM members m WHERE m.member_code = upper(btrim(p_code));
    IF v_id IS NULL THEN RETURN; END IF;
    RETURN QUERY
    SELECT rc.claim_code, rc.reward_name,
           CASE WHEN rc.status = 'menunggu' AND rc.expires_at <= now()
                THEN 'kedaluwarsa'::claim_status ELSE rc.status END,
           rc.expires_at, rc.used_at
      FROM reward_claims rc WHERE rc.member_id = v_id
     ORDER BY rc.created_at DESC LIMIT 20;
END $$;

-- 8. VALIDASI KLAIM OLEH KASIR ------------------------------------------------
CREATE OR REPLACE FUNCTION validate_claim(p_claim_code TEXT, p_cashier_id UUID)
RETURNS TABLE (
    reward_name VARCHAR, kind reward_kind, discount_value NUMERIC, member_name VARCHAR
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE rc reward_claims%ROWTYPE; v_kind reward_kind; v_name VARCHAR;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM cashiers c WHERE c.id = p_cashier_id AND c.is_active) THEN
        RAISE EXCEPTION 'Kasir tidak dikenali. Masukkan PIN ulang.';
    END IF;

    SELECT * INTO rc FROM reward_claims
     WHERE claim_code = upper(btrim(p_claim_code)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kode klaim tidak ditemukan.'; END IF;
    IF rc.status = 'dipakai' THEN
        RAISE EXCEPTION 'Kode klaim ini sudah dipakai pada %.',
            to_char(rc.used_at AT TIME ZONE 'Asia/Jakarta', 'DD Mon YYYY HH24:MI');
    END IF;
    IF rc.status <> 'menunggu' THEN RAISE EXCEPTION 'Kode klaim sudah tidak berlaku.'; END IF;
    IF rc.expires_at <= now() THEN
        UPDATE reward_claims SET status = 'kedaluwarsa' WHERE reward_claims.id = rc.id;
        RAISE EXCEPTION 'Kode klaim sudah kedaluwarsa.';
    END IF;

    UPDATE reward_claims SET status = 'dipakai', used_at = now(), used_by_cashier = p_cashier_id
     WHERE reward_claims.id = rc.id;

    SELECT r.kind INTO v_kind FROM rewards r WHERE r.id = rc.reward_id;
    SELECT m.name INTO v_name FROM members m WHERE m.id = rc.member_id;

    RETURN QUERY SELECT rc.reward_name, COALESCE(v_kind, 'Diskon'::reward_kind),
                        rc.discount_value, v_name;
END $$;

-- 9. HAK EKSEKUSI -------------------------------------------------------------
-- Kartu dibuka tanpa sesi login, sehingga fungsinya harus dapat dipanggil
-- peran anon. Yang menjaga adalah member_code, bukan tabelnya — tidak ada
-- satu pun tabel yang dibuka untuk anon.
GRANT EXECUTE ON FUNCTION member_card(TEXT)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION member_card_history(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION member_rewards(TEXT)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION member_claims(TEXT)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION redeem_reward(TEXT, UUID) TO anon, authenticated;
REVOKE EXECUTE ON FUNCTION validate_claim(TEXT, UUID) FROM anon;

-- 10. RLS ---------------------------------------------------------------------
ALTER TABLE rewards       ENABLE ROW LEVEL SECURITY;
ALTER TABLE reward_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_all ON rewards;
CREATE POLICY owner_all ON rewards
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
DROP POLICY IF EXISTS pos_read_rewards ON rewards;
CREATE POLICY pos_read_rewards ON rewards
    FOR SELECT TO authenticated USING (is_pos_device());

DROP POLICY IF EXISTS owner_all ON reward_claims;
CREATE POLICY owner_all ON reward_claims
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
-- Perangkat kasir tidak membaca tabel klaim langsung; validasi lewat
-- validate_claim() yang SECURITY DEFINER, sehingga kasir tidak dapat
-- menelusuri klaim milik member lain.

-- 11. SEED KATALOG REWARD -----------------------------------------------------
-- Contoh sementara sampai klien mengirim daftar rewardnya sendiri.
INSERT INTO rewards (name, description, kind, point_cost, discount_value, min_tier, sort_order)
SELECT * FROM (VALUES
    ('Diskon Rp 10.000',      'Potongan langsung untuk sekali cukur',        'Diskon'::reward_kind,  20,  10000.00, 'Silver'::member_tier, 1),
    ('Diskon Rp 25.000',      'Potongan langsung untuk sekali cukur',        'Diskon'::reward_kind,  45,  25000.00, 'Silver'::member_tier, 2),
    ('Hair Tonic Gratis',     'Tonic styling setelah potong rambut',         'Layanan'::reward_kind, 30,      0.00, 'Silver'::member_tier, 3),
    ('Cukur Gratis',          'Satu kali Express Haircut tanpa biaya',       'Layanan'::reward_kind, 70,      0.00, 'Gold'::member_tier,   4),
    ('Pomade Travel Size',    'Produk retail ukuran perjalanan',             'Produk'::reward_kind,  90,      0.00, 'Gold'::member_tier,   5),
    ('Paket VIP Grooming',    'Complete VIP Grooming Package gratis',        'Layanan'::reward_kind, 180,     0.00, 'Platinum'::member_tier, 6)
) AS v(name, description, kind, point_cost, discount_value, min_tier, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM rewards);

-- 12. member_code PADA HASIL TRANSAKSI ----------------------------------------
-- Struk WhatsApp membawa tautan kartu; tanpa kode ini kasir tidak punya
-- cara mengirimkan kartu kepada pelanggan yang baru terdaftar.
CREATE OR REPLACE FUNCTION tx_member_code(p_tx_id UUID)
RETURNS VARCHAR
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT m.member_code FROM transactions t
      JOIN members m ON m.id = t.member_id
     WHERE t.id = p_tx_id
$$;
GRANT EXECUTE ON FUNCTION tx_member_code(UUID) TO authenticated;
