-- ══════════════════════════════════════════════════════════════════════════
-- 44 · Masa berlaku level, dari sisi orang yang melihatnya
-- ══════════════════════════════════════════════════════════════════════════
-- Migrasi 43 memasang mesinnya. Ini memberi angka yang perlu dibaca dua
-- pihak: member yang levelnya sedang berjalan, dan owner yang harus dapat
-- menjelaskan mengapa seseorang turun.
--
-- Angka untuk member bukan ambang levelnya, melainkan berapa poin lagi yang
-- masih kurang agar levelnya bertahan. Pada akhir periode poin seumur hidup
-- dipotong sebesar ambang, jadi supaya sisanya masih mencapai ambang itu
-- lagi, member perlu DUA KALI ambang. Menampilkan ambangnya saja membuat
-- orang mengira ia sudah aman padahal kurang separuh.
-- ══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS member_card(TEXT);
CREATE OR REPLACE FUNCTION public.member_card(p_code text)
 RETURNS TABLE(member_no character varying, member_code character varying, name character varying, phone_masked text, tier member_tier, points_balance integer, lifetime_points integer, visit_count integer, total_spend numeric, tier_berikut member_tier, poin_ke_tier_berikut integer, member_sejak timestamp with time zone, masa_berlaku date, poin_agar_bertahan integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    m members%ROWTYPE;
    v_next member_tier;
    v_need INT;
BEGIN
    SELECT * INTO m FROM members WHERE members.member_code = upper(btrim(p_code));
    IF NOT FOUND THEN RETURN; END IF;

    SELECT tr.tier, tr.min_lifetime_points - m.lifetime_points
      INTO v_next, v_need
      FROM tier_rules tr
     WHERE tr.min_lifetime_points > m.lifetime_points
     ORDER BY tr.min_lifetime_points ASC
     LIMIT 1;

    RETURN QUERY SELECT
        m.member_no, m.member_code, m.name,
        -- Nomor disamarkan: pemegang tautan tidak perlu nomor lengkapnya
        CASE WHEN length(m.phone_wa) > 6
             THEN left(m.phone_wa, 4) || repeat('*', length(m.phone_wa) - 6) || right(m.phone_wa, 2)
             ELSE '****' END,
        m.tier, m.points_balance, m.lifetime_points,
        m.visit_count, m.total_spend,
        v_next, GREATEST(COALESCE(v_need, 0), 0), m.created_at,
        -- K-06: yang perlu diketahui member bukan cuma kapan periodenya
        -- berakhir, tetapi berapa yang harus ia kumpulkan supaya levelnya
        -- bertahan. Tanggal tanpa angka itu hanya menakut-nakuti.
        m.tier_period_end,
        -- Silver berambang 0, jadi hasilnya nol: tidak ada yang perlu
        -- dikejar, dan layar member memang tidak menampilkan apa pun.
        GREATEST((SELECT tr.min_lifetime_points * 2 FROM tier_rules tr
                   WHERE tr.tier = m.tier) - m.lifetime_points, 0);
END $function$
;

DROP FUNCTION IF EXISTS owner_members_list(INT);
CREATE OR REPLACE FUNCTION public.owner_members_list(p_limit integer DEFAULT 200)
 RETURNS TABLE(member_id uuid, member_no character varying, name character varying, phone_wa character varying, tier text, points_balance integer, visit_count integer, total_spend numeric, jumlah_transaksi bigint, terakhir date, masa_berlaku date, poin_agar_bertahan integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT m.id, m.member_no, m.name, m.phone_wa, m.tier::TEXT, m.points_balance,
           m.visit_count, m.total_spend,
           COUNT(t.id), MAX(t.business_date),
           m.tier_period_end,
           GREATEST((SELECT tr.min_lifetime_points * 2 FROM tier_rules tr
                      WHERE tr.tier = m.tier) - m.lifetime_points, 0)
      FROM members m
      LEFT JOIN transactions t ON t.member_id = m.id
     WHERE is_owner()
     GROUP BY m.id
     ORDER BY m.created_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 500));
$function$
;


-- DROP memulihkan hak bawaan Supabase, yang mencakup anon. Keduanya ditulis
-- ulang di sini secara sengaja: kartu member memang dibuka lewat tautan tanpa
-- login, daftar member owner tidak boleh.
REVOKE EXECUTE ON FUNCTION member_card(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION member_card(TEXT) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION owner_members_list(INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_members_list(INT) TO authenticated;
