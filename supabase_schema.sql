-- ==============================================================================
-- Barber Membership & Loyalty Management System
-- Database Schema for Supabase (PostgreSQL 17)
-- Fase 0 (Opening) s.d. Fase 3 (Full Release)
--
-- Catatan penting:
--   * Seluruh tabel memakai Row Level Security. Tidak ada akses anonim.
--     Kasir & owner wajib login (Supabase Auth) sebelum bisa membaca/menulis.
--   * Nomor nota dibuat di server (next_invoice_no) agar tidak bentrok
--     saat kasir dipakai di lebih dari satu perangkat.
--   * Seluruh pembatasan hari memakai zona Asia/Jakarta, bukan UTC.
-- ==============================================================================

-- 1. EXTENSIONS ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. ENUMS ---------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE member_tier AS ENUM ('Silver', 'Gold', 'Platinum', 'Infinite', 'Black');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE payment_method_type AS ENUM ('Tunai', 'QRIS', 'EDC', 'Transfer');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE staff_role AS ENUM ('owner', 'kasir', 'capster');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 3. HELPER: TANGGAL OPERASIONAL ----------------------------------------------
-- Outlet berada di WIB. toISOString()/now() UTC menggeser batas hari ke 07:00
-- pagi, sehingga transaksi dini hari masuk ke tanggal sebelumnya.
CREATE OR REPLACE FUNCTION jakarta_today()
RETURNS date
LANGUAGE sql STABLE
AS $$ SELECT (now() AT TIME ZONE 'Asia/Jakarta')::date $$;

-- 4. PROFILES (PEMETAAN AKUN AUTH -> PERAN) ------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name VARCHAR(150),
    role staff_role NOT NULL DEFAULT 'kasir',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Akun baru otomatis mendapat profil
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        COALESCE((NEW.raw_user_meta_data->>'role')::staff_role, 'kasir')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 5. MEMBERS -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    phone_wa VARCHAR(30) UNIQUE NOT NULL,
    tier member_tier NOT NULL DEFAULT 'Silver',
    points_balance INT NOT NULL DEFAULT 0,
    total_spend NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    visit_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_members_phone ON members(phone_wa);

-- 6. SERVICES ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'Haircut',
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    duration_minutes INT NOT NULL DEFAULT 30 CHECK (duration_minutes > 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_services_name_unique ON services(lower(name));

-- 7. CAPSTERS ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS capsters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(30),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_capsters_name_unique ON capsters(lower(name));

-- 8. PENOMORAN NOTA (ANTI-BENTROK MULTI PERANGKAT) -----------------------------
CREATE TABLE IF NOT EXISTS invoice_counters (
    day date PRIMARY KEY,
    last_seq INT NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION next_invoice_no()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE d date; s int;
BEGIN
    d := jakarta_today();
    INSERT INTO invoice_counters AS ic (day, last_seq)
    VALUES (d, 1)
    ON CONFLICT (day) DO UPDATE SET last_seq = ic.last_seq + 1
    RETURNING ic.last_seq INTO s;
    RETURN 'INV-' || to_char(d, 'YYMMDD') || '-' || lpad(s::text, 3, '0');
END $$;

-- 9. TRANSACTIONS --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- dikirim kasir; membuat pengiriman ulang antrean offline bersifat idempoten
    client_uuid UUID UNIQUE NOT NULL,
    invoice_no VARCHAR(50) UNIQUE NOT NULL,

    member_id UUID REFERENCES members(id) ON DELETE SET NULL,
    member_name VARCHAR(150),
    member_phone VARCHAR(30),
    member_tier member_tier,

    capster_id UUID REFERENCES capsters(id) ON DELETE SET NULL,
    capster_name VARCHAR(150),

    -- ringkasan layanan agar rekap & nota tidak perlu join
    service_summary TEXT,

    subtotal NUMERIC(12, 2) NOT NULL,
    discount_points NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    final_amount NUMERIC(12, 2) NOT NULL,

    payment_method payment_method_type NOT NULL,
    payment_ref VARCHAR(100),
    cash_paid NUMERIC(12, 2) DEFAULT 0.00,
    cash_change NUMERIC(12, 2) DEFAULT 0.00,

    points_earned INT NOT NULL DEFAULT 0,

    cashier_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    -- waktu transaksi sebenarnya (bisa mundur bila hasil sinkron antrean offline)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- tanggal operasional WIB, dipakai seluruh rekap harian
    business_date date NOT NULL DEFAULT jakarta_today(),
    synced_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_business_date ON transactions(business_date DESC);
CREATE INDEX IF NOT EXISTS idx_tx_created_at ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_member ON transactions(member_id);

-- 10. TRANSACTION ITEMS (SATU TRANSAKSI BISA BANYAK LAYANAN) -------------------
CREATE TABLE IF NOT EXISTS transaction_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    service_id UUID REFERENCES services(id) ON DELETE SET NULL,
    service_name VARCHAR(150) NOT NULL,
    category VARCHAR(50),
    price NUMERIC(12, 2) NOT NULL,
    qty INT NOT NULL DEFAULT 1 CHECK (qty > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_items_tx ON transaction_items(transaction_id);

-- 11. POINT LEDGER (FASE 1) ----------------------------------------------------
CREATE TABLE IF NOT EXISTS point_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('EARN', 'REDEEM', 'ADJUSTMENT', 'BONUS')),
    points_amount INT NOT NULL,
    balance_after INT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_member ON point_ledger(member_id);

-- 12. PRODUCTS & HPP (FASE 3) --------------------------------------------------
CREATE TABLE IF NOT EXISTS products_hpp (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    category VARCHAR(50) DEFAULT 'Retail',
    buy_price NUMERIC(12, 2) NOT NULL,
    shipping_per_unit NUMERIC(12, 2) DEFAULT 0.00,
    packaging_cost NUMERIC(12, 2) DEFAULT 0.00,
    overhead_cost NUMERIC(12, 2) DEFAULT 0.00,
    sell_price NUMERIC(12, 2) NOT NULL,
    target_margin_percent NUMERIC(5, 2) DEFAULT 40.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 13. ATTENDANCE (FASE 3) ------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    capster_id UUID NOT NULL REFERENCES capsters(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    selfie_url TEXT,
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    is_valid_location BOOLEAN DEFAULT true,
    business_date date NOT NULL DEFAULT jakarta_today(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==============================================================================
-- 14. RPC: SIMPAN TRANSAKSI SECARA ATOMIK
--     Satu panggilan menangani: daftar/perbarui member, nomor nota, header
--     transaksi, dan seluruh baris layanan. Aman diulang (client_uuid unik),
--     sehingga antrean offline boleh mengirim ulang tanpa menggandakan data.
-- ==============================================================================
CREATE OR REPLACE FUNCTION create_transaction(
    p_client_uuid   UUID,
    p_member_name   TEXT,
    p_member_phone  TEXT,
    p_capster_id    UUID,
    p_capster_name  TEXT,
    p_items         JSONB,
    p_subtotal      NUMERIC,
    p_final_amount  NUMERIC,
    p_payment_method TEXT,
    p_payment_ref   TEXT DEFAULT NULL,
    p_cash_paid     NUMERIC DEFAULT 0,
    p_cash_change   NUMERIC DEFAULT 0,
    p_created_at    TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    invoice_no VARCHAR,
    created_at TIMESTAMPTZ,
    member_tier member_tier,
    visit_count INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_member  members%ROWTYPE;
    v_tx_id   UUID;
    v_inv     TEXT;
    v_at      TIMESTAMPTZ := COALESCE(p_created_at, now());
    v_summary TEXT;
    v_item    JSONB;
    v_existing transactions%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Harus login untuk menyimpan transaksi';
    END IF;

    -- Sudah pernah masuk (pengiriman ulang antrean) -> kembalikan yang lama
    SELECT * INTO v_existing FROM transactions t WHERE t.client_uuid = p_client_uuid;
    IF FOUND THEN
        RETURN QUERY
        SELECT v_existing.id, v_existing.invoice_no, v_existing.created_at,
               v_existing.member_tier, COALESCE(m.visit_count, 0)
        FROM (SELECT 1) x
        LEFT JOIN members m ON m.id = v_existing.member_id;
        RETURN;
    END IF;

    -- Member: daftar bila baru, perbarui bila sudah ada
    IF p_member_phone IS NOT NULL AND p_member_phone <> '' AND p_member_phone <> '-' THEN
        INSERT INTO members (name, phone_wa, total_spend, visit_count)
        VALUES (p_member_name, p_member_phone, p_final_amount, 1)
        ON CONFLICT (phone_wa) DO UPDATE
            SET name        = EXCLUDED.name,
                total_spend = members.total_spend + EXCLUDED.total_spend,
                visit_count = members.visit_count + 1,
                updated_at  = now()
        RETURNING * INTO v_member;
    END IF;

    v_inv := next_invoice_no();

    SELECT string_agg(elem->>'name', ', ')
      INTO v_summary
      FROM jsonb_array_elements(p_items) elem;

    INSERT INTO transactions (
        client_uuid, invoice_no, member_id, member_name, member_phone, member_tier,
        capster_id, capster_name, service_summary,
        subtotal, final_amount, payment_method, payment_ref,
        cash_paid, cash_change, cashier_id, created_at,
        business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'),
        p_capster_id, p_capster_name, v_summary,
        p_subtotal, p_final_amount, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, p_cash_change, auth.uid(), v_at,
        (v_at AT TIME ZONE 'Asia/Jakarta')::date
    )
    RETURNING transactions.id INTO v_tx_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO transaction_items (transaction_id, service_id, service_name, category, price)
        VALUES (
            v_tx_id,
            CASE WHEN v_item->>'service_id' ~ '^[0-9a-fA-F-]{36}$'
                 THEN (v_item->>'service_id')::UUID ELSE NULL END,
            v_item->>'name',
            v_item->>'category',
            COALESCE((v_item->>'price')::NUMERIC, 0)
        );
    END LOOP;

    RETURN QUERY
    SELECT t.id, t.invoice_no, t.created_at, t.member_tier, COALESCE(v_member.visit_count, 0)
    FROM transactions t WHERE t.id = v_tx_id;
END $$;

-- ==============================================================================
-- 15. ROW LEVEL SECURITY
--     Kunci privasi: publishable key bersifat publik, sehingga tanpa RLS
--     nama & nomor WhatsApp pelanggan dapat dibaca siapa pun. Seluruh akses
--     dibatasi pada pengguna yang sudah login.
-- ==============================================================================
ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE members           ENABLE ROW LEVEL SECURITY;
ALTER TABLE services          ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsters          ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE point_ledger      ENABLE ROW LEVEL SECURITY;
ALTER TABLE products_hpp      ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendances       ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_counters  ENABLE ROW LEVEL SECURITY;
-- invoice_counters sengaja tanpa policy: hanya boleh disentuh
-- next_invoice_no() yang berjalan SECURITY DEFINER.

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'members', 'services', 'capsters', 'transactions',
        'transaction_items', 'point_ledger', 'products_hpp', 'attendances'
    ]
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS staff_all ON %I', t);
        EXECUTE format(
            'CREATE POLICY staff_all ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)', t
        );
    END LOOP;
END $$;

DROP POLICY IF EXISTS own_profile ON profiles;
CREATE POLICY own_profile ON profiles
    FOR SELECT TO authenticated USING (true);

-- ==============================================================================
-- 16. SEED MASTER DATA
--     Placeholder sampai daftar layanan & capster final dari klien masuk.
-- ==============================================================================
INSERT INTO services (name, category, price, duration_minutes) VALUES
('Haircut',      'Haircut',     85000.00, 45),
('Hairwash',     'Haircut',     15000.00, 15),
('Rootlift',     'Speciality', 115000.00, 60),
('Down Perm',    'Speciality', 175000.00, 90),
('Warrior Perm', 'Speciality', 315000.00, 120),
('Design Perm',  'Speciality', 415000.00, 150)
ON CONFLICT (lower(name)) DO NOTHING;

INSERT INTO capsters (name, phone) VALUES
('Cena',   '6281297754581'),
('Lukman', '6283170353824'),
('Wanda',  '6282119614135')
ON CONFLICT (lower(name)) DO NOTHING;
