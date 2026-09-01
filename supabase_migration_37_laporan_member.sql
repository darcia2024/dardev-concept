-- ==============================================================================
-- MIGRASI 37 - Tiga Laporan Member yang Diminta Spesifikasi
--
-- Bagian 07 spesifikasi menyebut tujuh laporan. Empat sudah ada lewat
-- owner_point_summary dan owner_point_audit: poin yang ditukar, poin yang
-- diterbitkan, saldo beredar, dan riwayat per member. Tiga sisanya belum
-- pernah dibangun, dan ketiganya menjawab pertanyaan yang berbeda sifatnya:
-- bukan "berapa biaya programnya" melainkan "siapa yang harus dihubungi".
--
--   L-04  Jumlah member per level. Bentuk piramidanya memberi tahu apakah
--         ambang levelnya masuk akal. Kalau seluruh member menumpuk di
--         Silver bertahun-tahun, ambangnya terlalu tinggi dan programnya
--         tidak pernah terasa oleh siapa pun.
--
--   L-06  Member yang tinggal sedikit lagi naik level. Ini daftar orang yang
--         paling mungkin datang kalau diingatkan, dan satu-satunya laporan di
--         sini yang langsung dapat ditindaklanjuti hari itu juga.
--
--   L-07  Member yang lama tidak datang. Dihitung dari transaksi terakhirnya,
--         bukan dari tanggal bergabung: member yang mendaftar tahun lalu dan
--         masih rutin datang bukan member yang hilang.
--
-- SEMUA MENGHITUNG DARI DATA, TIDAK ADA YANG DISIMPAN
--
-- Tidak ada kolom baru dan tidak ada tugas terjadwal. Ketiganya diturunkan
-- saat dipanggil, sehingga tidak mungkin basi dan tidak menambah satu pun
-- tempat yang harus dijaga tetap sinkron.
-- ==============================================================================


-- ── L-04 Jumlah member per level ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_members_per_tier()
RETURNS TABLE (tier TEXT, min_points INT, jumlah INT, persen NUMERIC, saldo_poin BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    -- tier_rules jadi sisi kiri supaya level yang belum berpenghuni tetap
    -- muncul dengan angka nol. Level kosong justru keterangan yang penting:
    -- ia memberi tahu sampai mana tangganya benar-benar terpakai.
    SELECT tr.tier::TEXT, tr.min_lifetime_points,
           COUNT(m.id)::INT,
           CASE WHEN (SELECT COUNT(*) FROM members) = 0 THEN 0
                ELSE round(COUNT(m.id) * 100.0 / (SELECT COUNT(*) FROM members), 1)
           END,
           COALESCE(SUM(m.points_balance), 0)::BIGINT
      FROM tier_rules tr
      LEFT JOIN members m ON m.tier = tr.tier
     WHERE is_owner()
     GROUP BY tr.tier, tr.min_lifetime_points
     ORDER BY tr.min_lifetime_points
$function$;


-- ── L-06 Member yang hampir naik level ─────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_members_hampir_naik(p_limit INT DEFAULT 50)
RETURNS TABLE (member_no VARCHAR, nama VARCHAR, telepon VARCHAR, tier TEXT,
               tier_berikut TEXT, lifetime_points INT, kurang INT,
               belanja_setara NUMERIC, terakhir date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    WITH berikut AS (
        SELECT m.id, m.member_no, m.name, m.phone_wa, m.tier, m.lifetime_points,
               (SELECT tr.tier FROM tier_rules tr
                 WHERE tr.min_lifetime_points > m.lifetime_points
                 ORDER BY tr.min_lifetime_points LIMIT 1) AS tier_naik,
               (SELECT tr.min_lifetime_points FROM tier_rules tr
                 WHERE tr.min_lifetime_points > m.lifetime_points
                 ORDER BY tr.min_lifetime_points LIMIT 1) AS ambang
          FROM members m
    )
    SELECT b.member_no, b.name, b.phone_wa, b.tier::TEXT, b.tier_naik::TEXT,
           b.lifetime_points, (b.ambang - b.lifetime_points)::INT,
           -- Sisa poin diterjemahkan ke rupiah belanja, sebab itu yang dapat
           -- disebut ke pelanggan. "Kurang 45.000 poin" tidak berarti apa pun
           -- bagi orang yang tidak menghitung poin di kepalanya.
           round((b.ambang - b.lifetime_points)
                 / (SELECT ls.earn_percent / 100 FROM loyalty_settings ls)) ,
           (SELECT MAX(t.business_date) FROM transactions t WHERE t.member_id = b.id)
      FROM berikut b
     WHERE is_owner() AND b.tier_naik IS NOT NULL
     ORDER BY (b.ambang - b.lifetime_points)
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 500)
$function$;


-- ── L-07 Member yang lama tidak datang ─────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_members_lama_hilang(p_bulan INT DEFAULT 3)
RETURNS TABLE (member_no VARCHAR, nama VARCHAR, telepon VARCHAR, tier TEXT,
               points_balance INT, total_spend NUMERIC,
               terakhir date, hari_sejak INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    WITH akhir AS (
        SELECT m.id, m.member_no, m.name, m.phone_wa, m.tier,
               m.points_balance, m.total_spend, m.created_at,
               (SELECT MAX(t.business_date) FROM transactions t
                 WHERE t.member_id = m.id) AS terakhir
          FROM members m
    )
    SELECT a.member_no, a.name, a.phone_wa, a.tier::TEXT,
           a.points_balance, a.total_spend,
           a.terakhir,
           (jakarta_today() - COALESCE(a.terakhir,
                (a.created_at AT TIME ZONE 'Asia/Jakarta')::date))::INT
      FROM akhir a
     WHERE is_owner()
       -- Member yang belum pernah bertransaksi dihitung dari tanggal
       -- bergabungnya. Kalau tidak, ia tidak akan pernah muncul di daftar ini
       -- justru karena tidak pernah datang sama sekali.
       AND COALESCE(a.terakhir, (a.created_at AT TIME ZONE 'Asia/Jakarta')::date)
           <= jakarta_today() - (GREATEST(COALESCE(p_bulan, 3), 1) * 30)
     ORDER BY COALESCE(a.terakhir,
                (a.created_at AT TIME ZONE 'Asia/Jakarta')::date)
$function$;


REVOKE EXECUTE ON FUNCTION owner_members_per_tier()          FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION owner_members_hampir_naik(INT)    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION owner_members_lama_hilang(INT)    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_members_per_tier()       TO authenticated;
GRANT  EXECUTE ON FUNCTION owner_members_hampir_naik(INT) TO authenticated;
GRANT  EXECUTE ON FUNCTION owner_members_lama_hilang(INT) TO authenticated;
