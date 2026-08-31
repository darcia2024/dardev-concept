-- ==============================================================================
-- MIGRASI 34 - Tangga Level untuk Kartu Member
--
-- Member hanya melihat levelnya sendiri dan sisa poin menuju level berikutnya.
-- Ia tidak pernah melihat seluruh tangganya: ada berapa tingkat, seperti apa
-- kartunya nanti, dan apa yang terbuka di tiap tingkat. Tanpa itu, angka
-- "45.000 poin lagi menuju Gold" hanyalah beban, bukan tujuan.
--
-- Ambang dan pengali level adalah keterangan program, bukan data pribadi
-- siapa pun, jadi fungsi ini terbuka untuk anon sebagaimana kartu membernya
-- sendiri. Yang tidak ikut keluar adalah kolom catatan internal pada
-- tier_rules, sebab isinya ditulis untuk pemilik dan bukan untuk dibaca
-- pelanggan.
--
-- Tabel tier_rules sendiri tetap tertutup RLS. Membuka tabelnya untuk anon
-- akan ikut membuka kolom catatan itu, dan setiap kolom yang ditambahkan
-- kelak akan ikut terbuka tanpa ada yang memutuskannya.
-- ==============================================================================

CREATE OR REPLACE FUNCTION tier_ladder()
RETURNS TABLE (tier member_tier, min_points INT, multiplier NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT tr.tier, tr.min_lifetime_points, tr.earn_multiplier
      FROM tier_rules tr
     ORDER BY tr.min_lifetime_points
$function$;

REVOKE EXECUTE ON FUNCTION tier_ladder() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION tier_ladder() TO anon, authenticated;
