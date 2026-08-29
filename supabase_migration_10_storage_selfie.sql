-- ==============================================================================
-- MIGRASI 10 — Penyimpanan Foto Selfie Absensi
--
-- Selfie absensi adalah foto wajah karyawan di jam kerja. Itu data pribadi,
-- bukan sekadar lampiran teknis. Karena itu:
--
--   * Bucket bersifat PRIVAT. Tidak ada URL publik; foto hanya dapat dibuka
--     lewat signed URL berumur pendek yang diminta pihak berhak.
--   * Karyawan hanya boleh mengunggah ke foldernya sendiri, dan hanya boleh
--     membaca fotonya sendiri. Jalur berkas diawali id capster, dan kebijakan
--     di bawah mencocokkannya dengan akun pemanggil.
--   * Owner boleh membaca semuanya — ia yang memeriksa bila ada sengketa.
--   * Tidak ada satu pun peran yang boleh MENGUBAH atau MENGHAPUS foto yang
--     sudah masuk. Bukti yang bisa diganti belakangan bukan bukti.
-- ==============================================================================

-- 1. BUCKET -------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('absensi', 'absensi', false, 3145728, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE
   SET public = false,
       file_size_limit = 3145728,
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp'];

-- 2. PEMILIK FOLDER -----------------------------------------------------------
-- Jalur berkas: <capster_id>/<tanggal>-<masuk|pulang>.jpg
-- Segmen pertama menentukan pemiliknya.
CREATE OR REPLACE FUNCTION storage_folder_milik_saya(p_name TEXT)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, storage
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.capsters c
         WHERE c.auth_user_id = auth.uid()
           AND c.id::text = split_part(p_name, '/', 1)
    )
$$;

-- 3. KEBIJAKAN ----------------------------------------------------------------
DROP POLICY IF EXISTS absensi_unggah_sendiri ON storage.objects;
CREATE POLICY absensi_unggah_sendiri ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'absensi' AND storage_folder_milik_saya(name));

DROP POLICY IF EXISTS absensi_baca_sendiri ON storage.objects;
CREATE POLICY absensi_baca_sendiri ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'absensi' AND (storage_folder_milik_saya(name) OR is_owner()));

-- Sengaja tidak ada kebijakan UPDATE maupun DELETE untuk bucket ini.
-- Foto absensi berfungsi sebagai bukti kehadiran; bila dapat ditimpa atau
-- dihapus oleh karyawan yang bersangkutan, nilainya sebagai bukti hilang.

-- 4. URL BERTANDA UNTUK OWNER -------------------------------------------------
-- Owner membuka foto lewat klien Supabase (createSignedUrl). Fungsi ini
-- menyediakan daftar jalur berkas absensi satu bulan agar owner tidak perlu
-- menebak-nebak nama berkas.
CREATE OR REPLACE FUNCTION attendance_photos(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    capster_name VARCHAR, business_date date,
    selfie_url TEXT, selfie_out_url TEXT,
    check_in_time TIMESTAMPTZ, status attend_status
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_awal date;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuka foto absensi.';
    END IF;
    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    RETURN QUERY
    SELECT c.name, a.business_date, a.selfie_url, a.selfie_out_url,
           a.check_in_time, a.status
      FROM attendances a JOIN capsters c ON c.id = a.capster_id
     WHERE a.business_date >= v_awal
       AND a.business_date < (v_awal + interval '1 month')
       AND a.selfie_url IS NOT NULL
     ORDER BY a.business_date DESC, c.name;
END $$;

GRANT EXECUTE ON FUNCTION attendance_photos(date) TO authenticated;
REVOKE EXECUTE ON FUNCTION attendance_photos(date) FROM anon;
