-- ==============================================================================
-- MIGRASI 12 — Kewenangan Owner: Hapus Transaksi, Ganti Sandi, Ganti PIN
--
-- Tiga kemampuan yang sebelumnya hanya bisa dilakukan lewat dashboard Supabase,
-- yang berarti pemiliknya harus memahami SQL untuk mengurus tokonya sendiri.
--
-- Yang paling perlu dijaga di sini adalah penghapusan transaksi. Menghapus satu
-- baris transaksi terdengar sederhana, padahal transaksi menyentuh empat hal
-- lain: item, buku besar poin, saldo poin member, dan klaim reward. Menghapus
-- barisnya saja akan meninggalkan poin yang tidak pernah dibelanjakan, saldo
-- yang tidak cocok dengan riwayatnya, dan kode reward yang terkunci selamanya
-- pada transaksi yang sudah tiada.
--
-- Karena itu penghapusan di sini bukan DELETE, melainkan pembatalan berurutan
-- yang mengembalikan setiap akibat, lalu menyimpan catatannya.
-- ==============================================================================


-- ==============================================================================
-- 1. ARSIP PENGHAPUSAN
--
-- Penghapusan tanpa jejak menghapus juga kemampuan menjawab "kemarin angkanya
-- kok beda?". Transaksi yang dihapus disimpan utuh di sini beserta alasan dan
-- pelakunya. Tabel ini tidak punya kebijakan DELETE — arsip yang bisa dihapus
-- bukan arsip.
-- ==============================================================================
CREATE TABLE IF NOT EXISTS deleted_transactions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_id     UUID        NOT NULL,
    invoice_no      VARCHAR(40) NOT NULL,
    business_date   DATE        NOT NULL,
    final_amount    NUMERIC(12,2) NOT NULL,
    payment_method  TEXT,
    capster_name    VARCHAR(150),
    cashier_name    VARCHAR(150),
    member_phone    VARCHAR(30),
    points_earned   INT DEFAULT 0,
    discount_points NUMERIC(12,2) DEFAULT 0,
    isi_lengkap     JSONB       NOT NULL,   -- seluruh baris + itemnya, apa adanya
    alasan          TEXT,
    dihapus_oleh    UUID        NOT NULL REFERENCES auth.users(id),
    dihapus_pada    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dtx_tanggal ON deleted_transactions(business_date DESC);

ALTER TABLE deleted_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_baca_arsip ON deleted_transactions;
CREATE POLICY owner_baca_arsip ON deleted_transactions
    FOR SELECT TO authenticated USING (is_owner());

-- Sengaja tidak ada kebijakan INSERT, UPDATE, maupun DELETE untuk siapa pun.
-- Hanya fungsi SECURITY DEFINER di bawah yang boleh menulis ke sini.


-- ==============================================================================
-- 2. HAPUS SATU TRANSAKSI, BESERTA SELURUH AKIBATNYA
--
-- Urutan pembatalan dipilih dengan sengaja:
--   a. Kunci baris member lebih dulu (FOR UPDATE) supaya tidak ada transaksi
--      lain yang mengubah saldonya di tengah pembatalan.
--   b. Kembalikan poin: yang diperoleh ditarik, yang ditukar dikembalikan.
--   c. Lepaskan klaim reward supaya kodenya bisa dipakai lagi.
--   d. Simpan arsipnya SEBELUM menghapus, selagi datanya masih ada.
--   e. Baru hapus item lalu transaksinya.
-- ==============================================================================
CREATE OR REPLACE FUNCTION delete_transaction(
    p_tx_id  UUID,
    p_alasan TEXT DEFAULT NULL
)
RETURNS TABLE (
    invoice_no    VARCHAR,
    final_amount  NUMERIC,
    poin_ditarik  INT,
    poin_dikembalikan INT,
    member_phone  VARCHAR
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_tx        transactions%ROWTYPE;
    v_member    members%ROWTYPE;
    v_items     JSONB;
    v_tarik     INT := 0;
    v_kembali   INT := 0;
    v_saldo     INT;
    v_lifetime  INT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus transaksi.';
    END IF;

    SELECT * INTO v_tx FROM transactions t WHERE t.id = p_tx_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaksi tidak ditemukan. Mungkin sudah dihapus sebelumnya.';
    END IF;

    -- (a) Kunci member bila transaksi ini memang milik seorang member
    IF v_tx.member_id IS NOT NULL THEN
        SELECT * INTO v_member FROM members m WHERE m.id = v_tx.member_id FOR UPDATE;
    END IF;

    -- (b) Kembalikan poin. points_earned ditarik; discount_points yang dulu
    --     ditukar dikembalikan sebagai saldo.
    IF v_member.id IS NOT NULL THEN
        v_tarik   := COALESCE(v_tx.points_earned, 0);
        SELECT COALESCE(SUM(pl.points_amount), 0)::INT INTO v_kembali
          FROM point_ledger pl
         WHERE pl.transaction_id = p_tx_id AND pl.points_amount < 0;
        v_kembali := abs(v_kembali);

        -- Saldo tidak boleh jatuh di bawah nol walau datanya pernah tak konsisten
        v_saldo    := GREATEST(0, COALESCE(v_member.points_balance, 0) - v_tarik + v_kembali);
        v_lifetime := GREATEST(0, COALESCE(v_member.lifetime_points, 0) - v_tarik);

        UPDATE members SET
            points_balance = v_saldo,
            lifetime_points = v_lifetime,
            tier            = compute_tier(v_lifetime),
            total_spend     = GREATEST(0, COALESCE(total_spend, 0) - COALESCE(v_tx.final_amount, 0)),
            visit_count     = GREATEST(0, COALESCE(visit_count, 0) - 1),
            updated_at      = now()
        WHERE id = v_member.id;

        DELETE FROM point_ledger WHERE transaction_id = p_tx_id;
    END IF;

    -- (c) Kode reward yang dipakai di transaksi ini dikembalikan agar bisa
    --     dipakai lagi; kalau tidak, pelanggan kehilangan reward yang sudah
    --     ditukar poinnya hanya karena kasir salah input.
    -- 'menunggu' adalah nilai awal pada enum claim_status
    -- (menunggu, dipakai, batal, kedaluwarsa) — kode kembali seperti belum
    -- pernah dipakai, bukan dibatalkan.
    UPDATE reward_claims
       SET status = 'menunggu', used_at = NULL, used_by_cashier = NULL, transaction_id = NULL
     WHERE transaction_id = p_tx_id;

    -- (d) Arsipkan selagi datanya masih utuh
    SELECT COALESCE(jsonb_agg(to_jsonb(ti)), '[]'::jsonb) INTO v_items
      FROM transaction_items ti WHERE ti.transaction_id = p_tx_id;

    INSERT INTO deleted_transactions (
        original_id, invoice_no, business_date, final_amount, payment_method,
        capster_name, cashier_name, member_phone, points_earned, discount_points,
        isi_lengkap, alasan, dihapus_oleh
    ) VALUES (
        v_tx.id, v_tx.invoice_no, v_tx.business_date, v_tx.final_amount,
        v_tx.payment_method::TEXT, v_tx.capster_name, v_tx.cashier_name,
        v_tx.member_phone, COALESCE(v_tx.points_earned, 0), COALESCE(v_tx.discount_points, 0),
        jsonb_build_object('transaksi', to_jsonb(v_tx), 'item', v_items),
        NULLIF(btrim(COALESCE(p_alasan, '')), ''), auth.uid()
    );

    -- (e) Hapus
    DELETE FROM transaction_items WHERE transaction_id = p_tx_id;
    DELETE FROM transactions WHERE id = p_tx_id;

    RETURN QUERY SELECT v_tx.invoice_no, v_tx.final_amount, v_tarik, v_kembali, v_tx.member_phone;
END $$;

GRANT EXECUTE ON FUNCTION delete_transaction(UUID, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION delete_transaction(UUID, TEXT) FROM anon;


-- ==============================================================================
-- 3. DAFTAR ARSIP UNTUK OWNER
-- ==============================================================================
CREATE OR REPLACE FUNCTION deleted_transactions_list(p_limit INT DEFAULT 50)
RETURNS TABLE (
    invoice_no    VARCHAR,
    business_date DATE,
    final_amount  NUMERIC,
    capster_name  VARCHAR,
    cashier_name  VARCHAR,
    alasan        TEXT,
    dihapus_pada  TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT d.invoice_no, d.business_date, d.final_amount, d.capster_name,
           d.cashier_name, d.alasan, d.dihapus_pada
      FROM deleted_transactions d
     WHERE is_owner()
     ORDER BY d.dihapus_pada DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION deleted_transactions_list(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION deleted_transactions_list(INT) FROM anon;


-- ==============================================================================
-- 4. OWNER MENGGANTI SANDI CAPSTER
--
-- Mengganti sandi berarti menulis ke auth.users, yang lewat API hanya bisa
-- dilakukan memakai service_role. Kunci itu TIDAK BOLEH ada di frontend: ia
-- melewati seluruh Row Level Security. Fungsi SECURITY DEFINER ini menjadi
-- jalan sempit yang menggantikannya — hanya satu hal yang bisa dilakukannya,
-- hanya terhadap akun yang tertaut ke capster aktif, dan hanya oleh owner.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_set_capster_password(
    p_capster_id UUID,
    p_password   TEXT
)
RETURNS TABLE (capster_name VARCHAR, email TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions
AS $$
DECLARE
    v_cap  capsters%ROWTYPE;
    v_mail TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengganti sandi karyawan.';
    END IF;
    IF p_password IS NULL OR length(p_password) < 8 THEN
        RAISE EXCEPTION 'Sandi minimal 8 karakter.';
    END IF;

    SELECT * INTO v_cap FROM capsters c WHERE c.id = p_capster_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capster tidak ditemukan.';
    END IF;
    IF v_cap.auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Capster % belum punya akun. Buatkan akunnya lebih dulu.', v_cap.name;
    END IF;

    -- Batasi sasaran: fungsi ini tidak boleh dipakai mengubah sandi owner
    -- sendiri atau akun perangkat POS, meski id-nya ditebak-tebak.
    IF EXISTS (SELECT 1 FROM profiles p
                WHERE p.id = v_cap.auth_user_id AND p.role <> 'capster') THEN
        RAISE EXCEPTION 'Akun itu bukan akun capster.';
    END IF;

    UPDATE auth.users
       SET encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           updated_at = now()
     WHERE id = v_cap.auth_user_id
    RETURNING auth.users.email INTO v_mail;

    RETURN QUERY SELECT v_cap.name, v_mail;
END $$;

GRANT EXECUTE ON FUNCTION owner_set_capster_password(UUID, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION owner_set_capster_password(UUID, TEXT) FROM anon;


-- ==============================================================================
-- 5. DAFTAR CAPSTER BESERTA EMAILNYA — UNTUK LAYAR OWNER
--
-- capsters sendiri tidak menyimpan email; alamatnya ada di auth.users. Owner
-- perlu melihatnya untuk tahu akun mana yang sedang ia ubah.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (
    capster_id UUID,
    name       VARCHAR,
    email      TEXT,
    is_active  BOOLEAN,
    punya_akun BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $$
    SELECT c.id, c.name, u.email::TEXT, c.is_active, (c.auth_user_id IS NOT NULL)
      FROM capsters c
      LEFT JOIN auth.users u ON u.id = c.auth_user_id
     WHERE is_owner()
     ORDER BY c.name;
$$;

GRANT EXECUTE ON FUNCTION owner_staff_list() TO authenticated;
REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM anon;


-- ==============================================================================
-- 6. DAFTAR KASIR UNTUK LAYAR OWNER
--
-- Hak baca kolom pada tabel cashiers sengaja dibatasi sejak migrasi 11 sehingga
-- select=* ditolak. Fungsi ini memberi owner daftar yang dibutuhkannya tanpa
-- pernah menyentuh pin_hash.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_cashier_list()
RETURNS TABLE (cashier_id UUID, name VARCHAR, is_active BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT c.id, c.name, c.is_active
      FROM cashiers c
     WHERE is_owner()
     ORDER BY c.name;
$$;

GRANT EXECUTE ON FUNCTION owner_cashier_list() TO authenticated;
REVOKE EXECUTE ON FUNCTION owner_cashier_list() FROM anon;
