-- ==============================================================================
-- MIGRASI 02 — Sistem Akses Owner & Kasir
--
-- Owner  : akun email + kata sandi, akses penuh ke seluruh sistem.
-- Kasir  : cukup PIN pribadi, tanpa email/kata sandi.
-- Jejak  : setiap transaksi mencatat nama & ID kasir pelakunya.
--
-- Catatan keamanan yang menentukan bentuk berkas ini:
--   PIN 4 digit hanya 10.000 kemungkinan. Bila PIN dijadikan kredensial
--   database, siapa pun yang tahu URL dapat menghabiskannya dalam hitungan
--   detik. Karena itu PIN TIDAK menjaga database — perangkat POS-lah yang
--   diautentikasi (sekali, saat setup). PIN hanya menentukan kasir mana yang
--   sedang bertugas, dan diverifikasi di server, bukan di browser.
--
--   PIN disimpan sebagai hash bcrypt. Daftar PIN tidak pernah dikirim ke
--   browser, dan tabel cashiers hanya terbaca oleh owner.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. PERAN PERANGKAT POS ------------------------------------------------------
-- Ditambahkan ke enum staff_role agar akun perangkat kasir bisa dibedakan
-- dari akun owner.
DO $$ BEGIN
    ALTER TYPE staff_role ADD VALUE IF NOT EXISTS 'pos_device';
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. HELPER PERAN -------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_owner()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role = 'owner' AND is_active
    )
$$;

-- 3. MASTER KASIR -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cashiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    pin_hash TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cashiers_name_unique ON cashiers(lower(name));

-- 4. PEMBATAS PERCOBAAN PIN ---------------------------------------------------
-- Tanpa ini, 10.000 kemungkinan PIN habis ditebak dari satu perangkat.
CREATE TABLE IF NOT EXISTS pin_attempts (
    device_id UUID PRIMARY KEY,
    fail_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ
);

-- 5. VERIFIKASI PIN -----------------------------------------------------------
-- Mengembalikan identitas kasir bila PIN cocok, atau kosong bila tidak.
-- Tidak pernah membocorkan PIN mana yang ada.
CREATE OR REPLACE FUNCTION verify_cashier_pin(p_pin TEXT)
RETURNS TABLE (cashier_id UUID, cashier_name VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
    v_row     cashiers%ROWTYPE;
    v_att     pin_attempts%ROWTYPE;
    v_sisa    INT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Perangkat belum terdaftar. Hubungi owner untuk menyiapkan perangkat ini.';
    END IF;

    SELECT * INTO v_att FROM pin_attempts WHERE device_id = auth.uid();
    IF FOUND AND v_att.locked_until IS NOT NULL AND v_att.locked_until > now() THEN
        v_sisa := ceil(extract(epoch FROM (v_att.locked_until - now())));
        RAISE EXCEPTION 'Terlalu banyak percobaan. Coba lagi dalam % detik.', v_sisa;
    END IF;

    SELECT * INTO v_row
      FROM cashiers c
     WHERE c.is_active
       AND c.pin_hash = extensions.crypt(p_pin, c.pin_hash)
     LIMIT 1;

    IF NOT FOUND THEN
        INSERT INTO pin_attempts (device_id, fail_count)
        VALUES (auth.uid(), 1)
        ON CONFLICT (device_id) DO UPDATE
            SET fail_count   = pin_attempts.fail_count + 1,
                locked_until = CASE
                    WHEN pin_attempts.fail_count + 1 >= 5 THEN now() + interval '60 seconds'
                    ELSE NULL END;
        RETURN;
    END IF;

    DELETE FROM pin_attempts WHERE device_id = auth.uid();
    RETURN QUERY SELECT v_row.id, v_row.name;
END $$;

-- 6. KELOLA KASIR (KHUSUS OWNER) ----------------------------------------------
CREATE OR REPLACE FUNCTION upsert_cashier(
    p_name TEXT,
    p_pin  TEXT DEFAULT NULL,
    p_id   UUID DEFAULT NULL
)
RETURNS TABLE (id UUID, name VARCHAR, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola data kasir.';
    END IF;
    IF p_pin IS NOT NULL AND p_pin !~ '^[0-9]{4,8}$' THEN
        RAISE EXCEPTION 'PIN harus 4 sampai 8 digit angka.';
    END IF;

    IF p_id IS NULL THEN
        IF p_pin IS NULL THEN
            RAISE EXCEPTION 'PIN wajib diisi untuk kasir baru.';
        END IF;
        -- PIN kembar membuat sistem salah mengenali siapa yang bertransaksi
        IF EXISTS (SELECT 1 FROM cashiers c WHERE c.pin_hash = extensions.crypt(p_pin, c.pin_hash)) THEN
            RAISE EXCEPTION 'PIN itu sudah dipakai kasir lain. Pakai PIN yang berbeda.';
        END IF;
        INSERT INTO cashiers (name, pin_hash)
        VALUES (p_name, extensions.crypt(p_pin, extensions.gen_salt('bf')))
        RETURNING cashiers.id INTO v_id;
    ELSE
        IF p_pin IS NOT NULL AND EXISTS (
            SELECT 1 FROM cashiers c
             WHERE c.id <> p_id AND c.pin_hash = extensions.crypt(p_pin, c.pin_hash)
        ) THEN
            RAISE EXCEPTION 'PIN itu sudah dipakai kasir lain. Pakai PIN yang berbeda.';
        END IF;
        UPDATE cashiers SET
            name     = p_name,
            pin_hash = CASE WHEN p_pin IS NULL THEN cashiers.pin_hash
                            ELSE extensions.crypt(p_pin, extensions.gen_salt('bf')) END
        WHERE cashiers.id = p_id
        RETURNING cashiers.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Kasir tidak ditemukan.'; END IF;
    END IF;

    RETURN QUERY SELECT c.id, c.name, c.is_active FROM cashiers c WHERE c.id = v_id;
END $$;

-- 7. PENCARIAN MEMBER TANPA MEMBUKA SELURUH DAFTAR ----------------------------
-- Kasir perlu mengenali pelanggan dari nomor yang disebutkan, tetapi tidak
-- boleh bisa mengunduh seluruh basis data pelanggan.
CREATE OR REPLACE FUNCTION lookup_member(p_phone TEXT)
RETURNS TABLE (name VARCHAR, tier member_tier, visit_count INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Perangkat belum terdaftar.';
    END IF;
    IF p_phone IS NULL OR length(regexp_replace(p_phone, '\D', '', 'g')) < 9 THEN
        RETURN;
    END IF;
    RETURN QUERY
    SELECT m.name, m.tier, m.visit_count
      FROM members m
     WHERE m.phone_wa = p_phone
     LIMIT 1;
END $$;

-- 8. JEJAK KASIR PADA TRANSAKSI -----------------------------------------------
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cashier_ref_id UUID REFERENCES cashiers(id) ON DELETE SET NULL;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cashier_name VARCHAR(150);
CREATE INDEX IF NOT EXISTS idx_tx_cashier ON transactions(cashier_ref_id);

-- 9. RPC TRANSAKSI — kini wajib menyertakan kasir pelakunya --------------------
DROP FUNCTION IF EXISTS create_transaction(UUID, TEXT, TEXT, UUID, TEXT, JSONB, NUMERIC, NUMERIC, TEXT, TEXT, NUMERIC, NUMERIC, TIMESTAMPTZ);

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
    p_created_at     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    invoice_no VARCHAR,
    created_at TIMESTAMPTZ,
    member_tier member_tier,
    visit_count INT,
    cashier_name VARCHAR
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_member   members%ROWTYPE;
    v_cashier  cashiers%ROWTYPE;
    v_tx_id    UUID;
    v_inv      TEXT;
    v_at       TIMESTAMPTZ := COALESCE(p_created_at, now());
    v_summary  TEXT;
    v_item     JSONB;
    v_existing transactions%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Perangkat belum terdaftar.';
    END IF;

    -- Kasir wajib teridentifikasi: tanpa ini transaksi tidak punya penanggung jawab
    SELECT * INTO v_cashier FROM cashiers WHERE cashiers.id = p_cashier_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kasir tidak dikenali. Masukkan PIN ulang.';
    END IF;

    SELECT * INTO v_existing FROM transactions t WHERE t.client_uuid = p_client_uuid;
    IF FOUND THEN
        RETURN QUERY
        SELECT v_existing.id, v_existing.invoice_no, v_existing.created_at,
               v_existing.member_tier, COALESCE(m.visit_count, 0), v_existing.cashier_name
          FROM (SELECT 1) x
          LEFT JOIN members m ON m.id = v_existing.member_id;
        RETURN;
    END IF;

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

    SELECT string_agg(elem->>'name', ', ') INTO v_summary
      FROM jsonb_array_elements(p_items) elem;

    INSERT INTO transactions (
        client_uuid, invoice_no, member_id, member_name, member_phone, member_tier,
        capster_id, capster_name, service_summary,
        subtotal, final_amount, payment_method, payment_ref,
        cash_paid, cash_change, cashier_id, cashier_ref_id, cashier_name,
        created_at, business_date
    ) VALUES (
        p_client_uuid, v_inv, v_member.id, p_member_name, NULLIF(p_member_phone, '-'),
        COALESCE(v_member.tier, 'Silver'),
        p_capster_id, p_capster_name, v_summary,
        p_subtotal, p_final_amount, p_payment_method::payment_method_type, p_payment_ref,
        p_cash_paid, p_cash_change, auth.uid(), v_cashier.id, v_cashier.name,
        v_at, (v_at AT TIME ZONE 'Asia/Jakarta')::date
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
    SELECT t.id, t.invoice_no, t.created_at, t.member_tier,
           COALESCE(v_member.visit_count, 0), t.cashier_name
      FROM transactions t WHERE t.id = v_tx_id;
END $$;

-- ==============================================================================
-- 10. RLS BERBASIS PERAN
--     Perangkat POS hanya boleh melihat katalog dan mencatat transaksi.
--     Laporan, data pelanggan, data pegawai, dan pengaturan milik owner.
-- ==============================================================================
ALTER TABLE cashiers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE pin_attempts ENABLE ROW LEVEL SECURITY;
-- pin_attempts sengaja tanpa policy: hanya verify_cashier_pin (SECURITY DEFINER)
-- yang boleh menyentuhnya.

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'members', 'services', 'capsters', 'transactions',
        'transaction_items', 'point_ledger', 'products_hpp', 'attendances'
    ]
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS staff_all ON %I', t);
    END LOOP;
END $$;

-- Owner: akses penuh ke seluruh sistem
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'members', 'services', 'capsters', 'transactions', 'transaction_items',
        'point_ledger', 'products_hpp', 'attendances', 'cashiers'
    ]
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS owner_all ON %I', t);
        EXECUTE format(
            'CREATE POLICY owner_all ON %I FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner())', t
        );
    END LOOP;
END $$;

-- Perangkat POS: katalog layanan & capster boleh dibaca semua akun terautentikasi
DROP POLICY IF EXISTS pos_read_services ON services;
CREATE POLICY pos_read_services ON services
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pos_read_capsters ON capsters;
CREATE POLICY pos_read_capsters ON capsters
    FOR SELECT TO authenticated USING (true);

-- Catatan: members, transactions, transaction_items TIDAK mendapat policy untuk
-- perangkat POS. Pencatatan berjalan lewat create_transaction() dan pencarian
-- pelanggan lewat lookup_member() — keduanya SECURITY DEFINER — sehingga kasir
-- tidak pernah bisa mengunduh daftar pelanggan atau membaca omzet.

-- 11. SEED KASIR CONTOH -------------------------------------------------------
-- PIN contoh dari spesifikasi. Berurutan dan mudah ditebak — ganti lewat
-- dashboard owner sebelum dipakai melayani pelanggan.
INSERT INTO cashiers (name, pin_hash)
SELECT v.name, extensions.crypt(v.pin, extensions.gen_salt('bf'))
FROM (VALUES ('Ahmad', '1234'), ('Fikri', '5678'), ('Rizal', '9012')) AS v(name, pin)
WHERE NOT EXISTS (SELECT 1 FROM cashiers c WHERE lower(c.name) = lower(v.name));
