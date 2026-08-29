-- ==============================================================================
-- MIGRASI 04 — Akun Capster & Halaman "Kinerja Saya"
--
-- Capster memakai akun email + kata sandi, bukan PIN. Alasannya bukan
-- ketidakkonsistenan: PIN kasir bekerja karena perangkat kasir sudah
-- didaftarkan sekali, sedangkan capster membuka angkanya dari ponsel
-- pribadi yang tidak boleh punya izin membuat transaksi. Sesi Supabase
-- bertahan, jadi capster tetap hanya login sekali.
--
-- Prinsip: capster hanya boleh melihat DIRINYA SENDIRI.
--   * Tidak ada omzet outlet, tidak ada angka capster lain.
--   * Tidak ada nama/nomor WhatsApp pelanggan — capster tidak butuh itu
--     untuk mengetahui kinerjanya, dan itu data pribadi orang lain.
--   * Seluruh akses lewat RPC SECURITY DEFINER yang menyaring berdasarkan
--     auth.uid(), sehingga penyaringan tidak bergantung pada sisi klien.
-- ==============================================================================

-- 1. TAUTAN AKUN -> CAPSTER ---------------------------------------------------
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS auth_user_id UUID
    REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_capsters_auth_unik
    ON capsters(auth_user_id) WHERE auth_user_id IS NOT NULL;

-- 2. IDENTITAS CAPSTER YANG SEDANG LOGIN --------------------------------------
CREATE OR REPLACE FUNCTION me_capster()
RETURNS TABLE (id UUID, name VARCHAR, is_active BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT c.id, c.name, c.is_active
      FROM capsters c
     WHERE c.auth_user_id = auth.uid()
     LIMIT 1
$$;

-- 3. RINGKASAN HARIAN ---------------------------------------------------------
-- Hanya baris milik capster pemanggil. Rentang dibatasi 92 hari agar satu
-- panggilan tidak menarik seluruh riwayat outlet.
CREATE OR REPLACE FUNCTION my_capster_daily(
    p_from date DEFAULT NULL,
    p_to   date DEFAULT NULL
)
RETURNS TABLE (
    business_date date,
    heads BIGINT,
    services_done BIGINT,
    revenue NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
    SELECT t.business_date,
           COUNT(DISTINCT t.id)                       AS heads,
           COALESCE(SUM(item.jml), 0)::BIGINT         AS services_done,
           COALESCE(SUM(t.final_amount), 0)           AS revenue
      FROM transactions t
      LEFT JOIN LATERAL (
            SELECT COUNT(*) AS jml FROM transaction_items i WHERE i.transaction_id = t.id
      ) item ON true
     WHERE t.capster_id = v_id
       AND t.business_date BETWEEN v_from AND v_to
     GROUP BY t.business_date
     ORDER BY t.business_date DESC;
END $$;

-- 4. RINCIAN LAYANAN SATU HARI ------------------------------------------------
-- Sengaja tanpa kolom pelanggan: capster tidak perlu tahu siapa, hanya apa.
CREATE OR REPLACE FUNCTION my_capster_services(p_date date DEFAULT NULL)
RETURNS TABLE (
    waktu TIMESTAMPTZ,
    invoice_no VARCHAR,
    service_name VARCHAR,
    price NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
     WHERE t.capster_id = v_id
       AND t.business_date = v_d
     ORDER BY t.created_at DESC;
END $$;

-- 5. TAUTKAN AKUN (KHUSUS OWNER) ----------------------------------------------
CREATE OR REPLACE FUNCTION link_capster_account(p_capster_id UUID, p_email TEXT)
RETURNS TABLE (capster_name VARCHAR, email TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID; v_name VARCHAR;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menautkan akun capster.';
    END IF;

    SELECT u.id INTO v_uid FROM auth.users u WHERE lower(u.email) = lower(btrim(p_email));
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Akun dengan email itu belum ada. Buat akunnya lebih dulu.';
    END IF;

    UPDATE capsters SET auth_user_id = v_uid WHERE capsters.id = p_capster_id
    RETURNING capsters.name INTO v_name;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Capster tidak ditemukan.';
    END IF;

    UPDATE profiles SET role = 'capster' WHERE profiles.id = v_uid;
    RETURN QUERY SELECT v_name, btrim(p_email);
END $$;

-- 6. HAK AKSES ----------------------------------------------------------------
-- Capster tidak mendapat policy tabel apa pun. Seluruh datanya mengalir
-- lewat keempat fungsi di atas, yang menyaring berdasarkan auth.uid().
-- Kebijakan owner_all pada capsters sudah ada dari migrasi 02; pos_read_capsters
-- tetap dibutuhkan agar POS dapat menampilkan daftar capster bertugas.

-- 7. RAPATKAN AKSES DAFTAR CAPSTER --------------------------------------------
-- Kebijakan pos_read_capsters semula terbuka untuk seluruh akun terautentikasi,
-- sehingga capster dapat membaca daftar rekan kerjanya beserta nomor telepon.
-- Yang benar-benar membutuhkan daftar itu hanya perangkat POS (untuk memilih
-- capster bertugas) dan owner.
CREATE OR REPLACE FUNCTION is_pos_device()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role = 'pos_device' AND is_active
    )
$$;

DROP POLICY IF EXISTS pos_read_capsters ON capsters;
CREATE POLICY pos_read_capsters ON capsters
    FOR SELECT TO authenticated USING (is_pos_device());

DROP POLICY IF EXISTS pos_read_services ON services;
CREATE POLICY pos_read_services ON services
    FOR SELECT TO authenticated USING (is_pos_device());
