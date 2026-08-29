-- ==============================================================================
-- MIGRASI 13 — Owner Menghapus Catatan Absensi
--
-- KETEGANGAN YANG DISELESAIKAN DI SINI
--
-- Migrasi 10 sengaja membuat foto absensi tidak dapat diubah maupun dihapus
-- oleh siapa pun, termasuk owner, dengan alasan yang masih berlaku: bukti yang
-- dapat diganti belakangan bukan lagi bukti. Sementara itu owner memang perlu
-- membersihkan data uji sebelum toko benar-benar buka.
--
-- Keduanya didamaikan dengan memisahkan dua hal yang selama ini dianggap satu:
--
--   * CATATAN absensi boleh dihapus — ia data operasional.
--   * FOTO-nya tetap tinggal di penyimpanan, tidak tersentuh.
--
-- Ditambah arsip yang menyimpan seluruh isi baris beserta jalur fotonya. Jadi
-- bila suatu hari ada sengketa "saya masuk hari itu", jawabannya masih ada:
-- barisnya di arsip, fotonya di bucket, keduanya bisa dipertemukan kembali.
--
-- Yang hilang hanyalah kemudahan membacanya, bukan buktinya.
-- ==============================================================================


-- ==============================================================================
-- 1. ARSIP ABSENSI TERHAPUS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS deleted_attendances (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_id    UUID        NOT NULL,
    capster_id     UUID,
    capster_name   VARCHAR(150),
    business_date  DATE        NOT NULL,
    check_in_time  TIMESTAMPTZ,
    check_out_time TIMESTAMPTZ,
    status         TEXT,
    selfie_url     TEXT,       -- jalur foto; berkasnya TIDAK ikut dihapus
    selfie_out_url TEXT,
    isi_lengkap    JSONB       NOT NULL,
    alasan         TEXT,
    dihapus_oleh   UUID        NOT NULL REFERENCES auth.users(id),
    dihapus_pada   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dabs_tanggal ON deleted_attendances(business_date DESC);

ALTER TABLE deleted_attendances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_baca_arsip_absen ON deleted_attendances;
CREATE POLICY owner_baca_arsip_absen ON deleted_attendances
    FOR SELECT TO authenticated USING (is_owner());

-- Tanpa kebijakan INSERT/UPDATE/DELETE untuk peran mana pun. Hanya fungsi
-- SECURITY DEFINER di bawah yang menulis ke sini.


-- ==============================================================================
-- 2. DAFTAR ABSENSI PER BARIS
--
-- attendance_report() mengembalikan rekap per karyawan — berguna untuk
-- membaca bulan berjalan, tetapi tidak memberi cara menunjuk satu catatan
-- untuk dihapus. Fungsi ini memberi barisnya satu per satu.
-- ==============================================================================
CREATE OR REPLACE FUNCTION attendance_rows(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    id             UUID,
    capster_name   VARCHAR,
    business_date  DATE,
    check_in_time  TIMESTAMPTZ,
    check_out_time TIMESTAMPTZ,
    status         TEXT,
    terlambat_menit INT,
    menit_kerja    INT,
    jarak_m        INT,
    ada_foto       BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT a.id, c.name, a.business_date, a.check_in_time, a.check_out_time,
           a.status::TEXT, a.terlambat_menit, a.menit_kerja, a.jarak_m,
           (a.selfie_url IS NOT NULL OR a.selfie_out_url IS NOT NULL)
      FROM attendances a
      JOIN capsters c ON c.id = a.capster_id
     WHERE is_owner()
       AND a.business_date >= COALESCE(p_bulan, date_trunc('month', jakarta_today())::date)
       AND a.business_date <  COALESCE(p_bulan, date_trunc('month', jakarta_today())::date) + INTERVAL '1 month'
     ORDER BY a.business_date DESC, c.name;
$$;

GRANT EXECUTE ON FUNCTION attendance_rows(date) TO authenticated;
REVOKE EXECUTE ON FUNCTION attendance_rows(date) FROM anon;


-- ==============================================================================
-- 3. HAPUS SATU CATATAN ABSENSI
--
-- Berbeda dari transaksi, absensi tidak menyentuh saldo apa pun, sehingga
-- tidak ada yang perlu dibatalkan. Yang perlu dijaga hanya satu: fotonya
-- tidak boleh ikut terhapus, dan jalurnya harus tersimpan supaya masih bisa
-- ditemukan kembali.
-- ==============================================================================
CREATE OR REPLACE FUNCTION delete_attendance(
    p_id     UUID,
    p_alasan TEXT DEFAULT NULL
)
RETURNS TABLE (capster_name VARCHAR, business_date DATE, foto_disimpan BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_abs  attendances%ROWTYPE;
    v_nama VARCHAR;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus catatan absensi.';
    END IF;

    SELECT * INTO v_abs FROM attendances a WHERE a.id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Catatan absensi tidak ditemukan. Mungkin sudah dihapus sebelumnya.';
    END IF;

    SELECT c.name INTO v_nama FROM capsters c WHERE c.id = v_abs.capster_id;

    INSERT INTO deleted_attendances (
        original_id, capster_id, capster_name, business_date,
        check_in_time, check_out_time, status, selfie_url, selfie_out_url,
        isi_lengkap, alasan, dihapus_oleh
    ) VALUES (
        v_abs.id, v_abs.capster_id, v_nama, v_abs.business_date,
        v_abs.check_in_time, v_abs.check_out_time, v_abs.status::TEXT,
        v_abs.selfie_url, v_abs.selfie_out_url,
        to_jsonb(v_abs), NULLIF(btrim(COALESCE(p_alasan, '')), ''), auth.uid()
    );

    -- Hanya barisnya. Berkas foto di bucket 'absensi' sengaja dibiarkan:
    -- jalurnya sudah tersimpan di arsip, sehingga bukti kehadiran masih dapat
    -- dipertemukan kembali bila suatu saat dipersoalkan.
    DELETE FROM attendances WHERE id = p_id;

    RETURN QUERY SELECT v_nama, v_abs.business_date,
                        (v_abs.selfie_url IS NOT NULL OR v_abs.selfie_out_url IS NOT NULL);
END $$;

GRANT EXECUTE ON FUNCTION delete_attendance(UUID, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION delete_attendance(UUID, TEXT) FROM anon;


-- ==============================================================================
-- 4. DAFTAR ARSIP ABSENSI UNTUK OWNER
-- ==============================================================================
CREATE OR REPLACE FUNCTION deleted_attendances_list(p_limit INT DEFAULT 50)
RETURNS TABLE (
    capster_name  VARCHAR,
    business_date DATE,
    status        TEXT,
    punya_foto    BOOLEAN,
    alasan        TEXT,
    dihapus_pada  TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT d.capster_name, d.business_date, d.status,
           (d.selfie_url IS NOT NULL OR d.selfie_out_url IS NOT NULL),
           d.alasan, d.dihapus_pada
      FROM deleted_attendances d
     WHERE is_owner()
     ORDER BY d.dihapus_pada DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION deleted_attendances_list(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION deleted_attendances_list(INT) FROM anon;
