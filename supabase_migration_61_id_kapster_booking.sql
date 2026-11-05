-- ==============================================================================
-- MIGRASI 61 - Pilihan Kapster di Halaman Booking Tersimpan Lagi
--
-- Migrasi 40 membuat public_landing() mengirim id kapster supaya pilihan
-- pelanggan tersimpan di bookings.capster_id, dan dari situ kirim_wa_capster()
-- menemukan nomor tujuan. Migrasi 48 menulis ulang fungsi itu dari salinan
-- migrasi 28, sehingga id-nya hilang tanpa ada tes yang gagal.
--
-- Akibatnya halaman booking mengirim p_capster_id NULL, booking tersimpan tanpa
-- kapster, dan notifikasinya berhenti dengan status 'tanpa_capster'. Nama yang
-- dipilih pelanggan hanya tersisa sebagai kalimat di kolom catatan.
--
-- Id dikirim lewat kunci baru. 'kapster' tetap daftar nama karena fungsi ai-tanya
-- membacanya sebagai untai, dan fungsi itu dideploy terpisah dari migrasi ini.
-- Nomor telepon tetap tidak pernah keluar.
--
-- Migrasi ini tidak mengisi ulang booking lama. Notifikasinya sudah lewat, dan
-- menebak kapster dari kalimat catatan bisa salah.
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
              FROM capsters c WHERE c.is_active AND c.ikut_pos
        ), '[]'::jsonb),
        'kapster_id', COALESCE((
            SELECT jsonb_object_agg(c.name, c.id)
              FROM capsters c WHERE c.is_active AND c.ikut_pos
        ), '{}'::jsonb),
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
