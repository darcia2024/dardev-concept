-- ==============================================================================
-- MIGRASI 60 - Owner Mengunggah Foto Kapster Sendiri
--
-- Foto kapster selama ini berkas di folder assets/ yang dicocokkan dengan nama
-- di dalam kode. Akibatnya tiap kapster baru harus menunggu orang mengubah kode,
-- dan sampai itu terjadi halaman booking hanya menampilkan huruf depan namanya.
--
-- Bucket ini PUBLIK, berbeda dengan bucket absensi yang privat. Foto ini memang
-- dipajang di halaman depan untuk pengunjung yang tidak login, jadi signed URL
-- berumur pendek tidak memberi perlindungan apa pun. Selfie absensi tetap di
-- bucketnya sendiri dan tidak disentuh.
--
-- Nama berkas acak dan tidak memuat id karyawan, sebab jalurnya ikut terbaca
-- publik lewat public_landing(). Berkas baru selalu bernama baru, jadi foto
-- boleh disimpan lama oleh peramban tanpa perlu penanda versi.
-- ==============================================================================


-- ── 01 Kolom dan bucket ────────────────────────────────────────────────────
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS foto_path TEXT;

COMMENT ON COLUMN capsters.foto_path IS
  'Nama berkas di bucket foto-kapster. NULL = belum diunggah; layar memakai foto '
  'bawaan di assets/ bila ada, atau huruf depan nama.';

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('foto-kapster', 'foto-kapster', true, 2097152, ARRAY['image/webp','image/jpeg'])
ON CONFLICT (id) DO UPDATE
   SET public = true,
       file_size_limit = 2097152,
       allowed_mime_types = ARRAY['image/webp','image/jpeg'];


-- ── 02 Hanya owner yang menulis ────────────────────────────────────────────
-- Tampil di bucket publik tidak butuh kebijakan SELECT untuk pengunjung, dan
-- tanpa kebijakan itu isi bucket tidak dapat didaftar oleh anon. Owner butuh
-- SELECT karena penghapusan berkas di Storage memeriksanya.
DROP POLICY IF EXISTS foto_kapster_owner ON storage.objects;
CREATE POLICY foto_kapster_owner ON storage.objects
    FOR ALL TO authenticated
    USING (bucket_id = 'foto-kapster' AND is_owner())
    WITH CHECK (bucket_id = 'foto-kapster' AND is_owner());


-- ── 03 Memasang foto ───────────────────────────────────────────────────────
-- Mengembalikan jalur lama supaya layar dapat membuang berkas yang tidak terpakai.
-- Berkas di Storage tidak dihapus dari SQL karena isinya ada di luar basis data.
CREATE OR REPLACE FUNCTION owner_set_foto_karyawan(p_id UUID, p_foto_path TEXT)
RETURNS TABLE (foto_lama TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_lama TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah foto karyawan.';
    END IF;

    SELECT c.foto_path INTO v_lama FROM capsters c WHERE c.id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karyawan tidak ditemukan.';
    END IF;

    IF p_foto_path IS NOT NULL THEN
        IF p_foto_path !~ '^[0-9a-f]{32}\.(webp|jpg)$' THEN
            RAISE EXCEPTION 'Nama berkas foto tidak valid.';
        END IF;
        -- Foto yang tidak ada akan tampil sebagai gambar rusak di halaman booking.
        IF NOT EXISTS (SELECT 1 FROM storage.objects o
                        WHERE o.bucket_id = 'foto-kapster' AND o.name = p_foto_path) THEN
            RAISE EXCEPTION 'Berkas foto belum terunggah.';
        END IF;
    END IF;

    UPDATE capsters c SET foto_path = p_foto_path WHERE c.id = p_id;
    RETURN QUERY SELECT v_lama;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_set_foto_karyawan(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_set_foto_karyawan(UUID, TEXT) TO authenticated;


-- ── 04 Daftar staf membawa fotonya ─────────────────────────────────────────
DROP FUNCTION IF EXISTS owner_staff_list();

CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (capster_id UUID, name CHARACTER VARYING, email TEXT,
               is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING,
               jabatan CHARACTER VARYING, ikut_pos BOOLEAN,
               jml_absen BIGINT, jam_masuk TIME, jam_pulang TIME, foto_path TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $function$
    SELECT c.id, c.name, u.email::TEXT, c.is_active, (c.auth_user_id IS NOT NULL),
           c.phone, c.jabatan, c.ikut_pos,
           (SELECT count(*) FROM attendances a WHERE a.capster_id = c.id),
           c.jam_masuk, c.jam_pulang, c.foto_path
      FROM capsters c
      LEFT JOIN auth.users u ON u.id = c.auth_user_id
     WHERE is_owner()
     ORDER BY c.ikut_pos DESC, c.name;
$function$;

REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_staff_list() TO authenticated;


-- ── 05 Layar absen karyawan menampilkan fotonya ────────────────────────────
DROP FUNCTION IF EXISTS me_capster();

CREATE OR REPLACE FUNCTION me_capster()
RETURNS TABLE (id UUID, name CHARACTER VARYING, is_active BOOLEAN,
               jabatan CHARACTER VARYING, ikut_pos BOOLEAN, foto_path TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT c.id, c.name, c.is_active, c.jabatan, c.ikut_pos, c.foto_path
      FROM capsters c
     WHERE c.auth_user_id = auth.uid()
     LIMIT 1
$function$;

REVOKE EXECUTE ON FUNCTION me_capster() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION me_capster() TO authenticated;


-- ── 06 Halaman booking membaca fotonya ─────────────────────────────────────
-- Disalin dari migrasi 48 dengan satu kunci baru. 'kapster' sengaja tetap daftar
-- nama: fungsi ai-tanya membacanya sebagai untai, dan mengubah bentuknya akan
-- merusak jawaban asisten pelanggan.
CREATE OR REPLACE FUNCTION public_landing()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
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
              FROM capsters c WHERE c.is_active AND c.ikut_pos
        ), '[]'::jsonb),
        'kapster_foto', COALESCE((
            SELECT jsonb_object_agg(c.name, c.foto_path)
              FROM capsters c
             WHERE c.is_active AND c.ikut_pos AND c.foto_path IS NOT NULL
        ), '{}'::jsonb),
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
                       'rupiah_per_poin', ls.rupiah_per_point,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    )
$function$;

REVOKE EXECUTE ON FUNCTION public_landing() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public_landing() TO anon, authenticated;
