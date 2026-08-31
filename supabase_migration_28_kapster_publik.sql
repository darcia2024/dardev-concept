-- ==============================================================================
-- MIGRASI 28 - Nama Kapster Ikut Dibaca Halaman Depan
--
-- public_landing sengaja tidak pernah menyentuh tabel capsters, karena tabel
-- itu memuat nomor telepon dan tautan ke akun autentikasi tiap karyawan.
-- Halaman depan sekarang memperkenalkan tim, jadi yang dibuka hanya namanya.
--
-- Nama depan kapster bukan data rahasia: ia tertulis di dinding toko dan
-- disebut pelanggan setiap hari. Yang tetap tertutup adalah nomor telepon,
-- id, dan tautan akunnya, karena tidak satu pun dibutuhkan pengunjung untuk
-- memilih siapa yang ingin ia temui.
--
-- Urutannya mengikuti nama supaya susunannya tidak berubah-ubah tiap muat.
-- ==============================================================================

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
                       'rupiah_per_poin', ls.rupiah_per_point,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    );
$function$;

GRANT EXECUTE ON FUNCTION public_landing() TO anon, authenticated;
