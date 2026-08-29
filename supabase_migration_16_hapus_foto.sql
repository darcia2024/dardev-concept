-- ==============================================================================
-- MIGRASI 16 — Owner Dapat Menghapus Foto Absensi
--
-- APA YANG BERUBAH DARI KEPUTUSAN SEBELUMNYA
--
-- Migrasi 10 sengaja tidak memberi kebijakan DELETE pada bucket 'absensi',
-- dengan alasan: bukti yang dapat dihapus belakangan berhenti menjadi bukti.
-- Migrasi 13 mempertahankannya — catatan absensi boleh hilang, fotonya tidak.
--
-- Pemilik sistem meminta kemampuan itu tetap diberikan, dan itu keputusannya.
-- Yang masih bisa dijaga adalah jejaknya: penghapusan foto tidak boleh senyap.
--
-- Maka kebijakan DELETE diberikan HANYA kepada owner, dan tiap penghapusan
-- dicatat di deleted_photos beserta pelaku, waktu, dan alasannya. Yang hilang
-- gambarnya; catatan bahwa gambar itu pernah ada dan siapa yang menghapusnya
-- tetap tinggal.
--
-- Konsekuensi yang perlu diketahui penerus: sejak migrasi ini, foto absensi
-- tidak lagi dapat dipakai sebagai bukti yang tidak terbantahkan dalam
-- sengketa kehadiran. Yang tersisa adalah jejak audit — cukup untuk menjawab
-- "siapa menghapus", tidak cukup untuk menjawab "apakah dia benar hadir".
-- ==============================================================================


-- ==============================================================================
-- 1. ARSIP FOTO TERHAPUS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS deleted_photos (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jalur        TEXT        NOT NULL,
    capster_id   UUID,
    capster_name VARCHAR(150),
    business_date DATE,
    jenis        TEXT,        -- 'masuk' atau 'pulang'
    alasan       TEXT,
    dihapus_oleh UUID        NOT NULL REFERENCES auth.users(id),
    dihapus_pada TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dfoto_waktu ON deleted_photos(dihapus_pada DESC);

ALTER TABLE deleted_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_baca_arsip_foto ON deleted_photos;
CREATE POLICY owner_baca_arsip_foto ON deleted_photos
    FOR SELECT TO authenticated USING (is_owner());


-- ==============================================================================
-- 2. KEBIJAKAN HAPUS DI PENYIMPANAN — KHUSUS OWNER
--
-- Capster tetap tidak boleh menghapus fotonya sendiri. Kalau boleh, yang
-- terlambat tinggal menghapus buktinya sendiri sebelum owner sempat melihat,
-- dan absensi berhenti berarti sama sekali.
-- ==============================================================================
DROP POLICY IF EXISTS absensi_hapus_owner ON storage.objects;
CREATE POLICY absensi_hapus_owner ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'absensi' AND is_owner());

-- UPDATE tetap tidak diberikan kepada siapa pun: foto boleh dihapus, tetapi
-- tidak boleh DITUKAR dengan gambar lain. Menghapus meninggalkan lubang yang
-- terlihat; menukar meninggalkan kebohongan yang tidak terlihat.


-- ==============================================================================
-- 3. CATAT PENGHAPUSAN + LEPASKAN RUJUKANNYA
--
-- Dipanggil klien SEBELUM berkasnya dihapus lewat Storage API, selagi datanya
-- masih dapat dibaca. Fungsi ini juga mengosongkan selfie_url pada baris
-- absensi supaya laporan tidak lagi menampilkan "ada foto" untuk berkas yang
-- sudah tiada.
-- ==============================================================================
CREATE OR REPLACE FUNCTION log_delete_photo(
    p_jalur  TEXT,
    p_alasan TEXT DEFAULT NULL
)
RETURNS TABLE (capster_name VARCHAR, business_date DATE, jenis TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_cap_id  UUID;
    v_nama    VARCHAR;
    v_tgl     DATE;
    v_jenis   TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus foto absensi.';
    END IF;
    IF COALESCE(btrim(p_jalur), '') = '' THEN
        RAISE EXCEPTION 'Jalur foto kosong.';
    END IF;

    -- Segmen pertama jalur adalah id capster: <capster_id>/<tanggal>-<jenis>.<ext>
    BEGIN
        v_cap_id := split_part(p_jalur, '/', 1)::UUID;
    EXCEPTION WHEN others THEN
        v_cap_id := NULL;
    END;

    SELECT c.name INTO v_nama FROM capsters c WHERE c.id = v_cap_id;

    SELECT a.business_date,
           CASE WHEN a.selfie_url = p_jalur THEN 'masuk' ELSE 'pulang' END
      INTO v_tgl, v_jenis
      FROM attendances a
     WHERE a.selfie_url = p_jalur OR a.selfie_out_url = p_jalur
     LIMIT 1;

    INSERT INTO deleted_photos (jalur, capster_id, capster_name, business_date, jenis, alasan, dihapus_oleh)
    VALUES (p_jalur, v_cap_id, v_nama, v_tgl, v_jenis,
            NULLIF(btrim(COALESCE(p_alasan, '')), ''), auth.uid());

    -- Lepaskan rujukannya supaya laporan tidak menjanjikan foto yang tidak ada
    UPDATE attendances SET selfie_url     = NULL WHERE selfie_url     = p_jalur;
    UPDATE attendances SET selfie_out_url = NULL WHERE selfie_out_url = p_jalur;

    RETURN QUERY SELECT v_nama, v_tgl, v_jenis;
END $$;

GRANT EXECUTE ON FUNCTION log_delete_photo(TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION log_delete_photo(TEXT, TEXT) FROM anon;


-- ==============================================================================
-- 4. DAFTAR ARSIP FOTO
-- ==============================================================================
CREATE OR REPLACE FUNCTION deleted_photos_list(p_limit INT DEFAULT 50)
RETURNS TABLE (
    capster_name  VARCHAR,
    business_date DATE,
    jenis         TEXT,
    jalur         TEXT,
    alasan        TEXT,
    dihapus_pada  TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT d.capster_name, d.business_date, d.jenis, d.jalur, d.alasan, d.dihapus_pada
      FROM deleted_photos d
     WHERE is_owner()
     ORDER BY d.dihapus_pada DESC
     LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION deleted_photos_list(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION deleted_photos_list(INT) FROM anon;
