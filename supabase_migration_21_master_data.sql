-- ==============================================================================
-- MIGRASI 21 — Owner Mengelola Master Data Sendiri
--
-- KEADAAN SEBELUMNYA
--
-- Reward, aturan tier, rasio poin, dan outlet hanya bisa diubah lewat SQL.
-- Setiap kali klien ingin mengganti satu reward atau menggeser ambang tier,
-- pekerjaan itu kembali ke pengembang. Modal Pengaturan di POS hanya
-- mengelola layanan, capster, dan nama kasir.
--
-- KENAPA LEWAT RPC, PADAHAL RLS SUDAH MENGIZINKAN OWNER
--
-- Kebijakan owner_all memang sudah membolehkan owner menulis langsung ke
-- kelima tabel ini. Yang tidak bisa dijaga oleh RLS adalah keutuhan antar
-- barisnya: ambang tier harus menaik, Silver harus tetap di titik nol,
-- persentase penukaran harus masuk akal, dan baris yang sudah pernah dipakai
-- tidak boleh lenyap begitu saja. Fungsi di bawah ini ada untuk aturan-aturan
-- itu, bukan untuk perizinan.
--
-- MENGHAPUS YANG SUDAH TERPAKAI
--
-- Ketiga kunci asing menunjuk ke sini dengan NO ACTION, sehingga menghapus
-- baris yang sudah dipakai akan gagal dengan pesan basis data yang tidak bisa
-- dibaca siapa pun. Lebih buruk lagi bila berhasil: transaksi lama kehilangan
-- nama produknya, dan klaim reward kehilangan hadiah yang diklaim.
--
-- Karena itu setiap penghapusan memeriksa dulu. Bila barisnya sudah menyentuh
-- riwayat, ia dinonaktifkan — hilang dari semua daftar pilihan, tetapi
-- riwayatnya tetap utuh. Bila belum pernah dipakai, ia benar-benar dihapus.
-- Fungsi mengembalikan mana yang terjadi, supaya owner tidak menebak.
-- ==============================================================================


-- ==============================================================================
-- REWARD
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_rewards_list()
RETURNS TABLE (
    id UUID, name VARCHAR, description TEXT, kind TEXT, point_cost INT,
    discount_value NUMERIC, min_tier TEXT, stock INT, is_active BOOLEAN,
    sort_order INT, dipakai INT, menunggu INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka daftar reward.'; END IF;
    RETURN QUERY
    SELECT r.id, r.name, r.description, r.kind::TEXT, r.point_cost,
           r.discount_value, r.min_tier::TEXT, r.stock, r.is_active, r.sort_order,
           COALESCE(k.dipakai, 0), COALESCE(k.menunggu, 0)
      FROM rewards r
      LEFT JOIN LATERAL (
            SELECT COUNT(*) FILTER (WHERE rc.status = 'dipakai')::INT   AS dipakai,
                   COUNT(*) FILTER (WHERE rc.status = 'menunggu')::INT  AS menunggu
              FROM reward_claims rc WHERE rc.reward_id = r.id
      ) k ON true
     ORDER BY r.is_active DESC, r.sort_order, r.point_cost;
END $function$;

GRANT EXECUTE ON FUNCTION owner_rewards_list() TO authenticated;


CREATE OR REPLACE FUNCTION upsert_reward(
    p_name TEXT, p_kind TEXT, p_point_cost INT,
    p_discount_value NUMERIC DEFAULT 0, p_min_tier TEXT DEFAULT 'Silver',
    p_stock INT DEFAULT NULL, p_description TEXT DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT TRUE, p_id UUID DEFAULT NULL
)
RETURNS TABLE (id UUID, name VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_id UUID; v_urut INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mengelola reward.'; END IF;
    IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'Nama reward wajib diisi.'; END IF;
    IF p_point_cost IS NULL OR p_point_cost <= 0 THEN
        RAISE EXCEPTION 'Poin yang dibutuhkan harus lebih dari nol.';
    END IF;

    -- Nilai diskon hanya berarti pada reward berjenis Diskon. Dibiarkan
    -- terisi pada jenis lain, angka itu akan muncul di layar penukaran dan
    -- menjanjikan potongan yang tidak pernah diberikan.
    IF p_kind = 'Diskon' AND (p_discount_value IS NULL OR p_discount_value <= 0) THEN
        RAISE EXCEPTION 'Reward berjenis Diskon harus punya nilai diskon.';
    END IF;

    IF p_id IS NULL THEN
        SELECT COALESCE(MAX(r.sort_order), 0) + 1 INTO v_urut FROM rewards r;
        INSERT INTO rewards (name, description, kind, point_cost, discount_value,
                             min_tier, stock, is_active, sort_order)
        VALUES (btrim(p_name), NULLIF(btrim(COALESCE(p_description, '')), ''),
                p_kind::reward_kind, p_point_cost,
                CASE WHEN p_kind = 'Diskon' THEN p_discount_value ELSE 0 END,
                p_min_tier::member_tier, p_stock, p_is_active, v_urut)
        RETURNING rewards.id INTO v_id;
    ELSE
        UPDATE rewards SET
            name = btrim(p_name),
            description = NULLIF(btrim(COALESCE(p_description, '')), ''),
            kind = p_kind::reward_kind,
            point_cost = p_point_cost,
            discount_value = CASE WHEN p_kind = 'Diskon' THEN p_discount_value ELSE 0 END,
            min_tier = p_min_tier::member_tier,
            stock = p_stock,
            is_active = p_is_active
        WHERE rewards.id = p_id
        RETURNING rewards.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Reward tidak ditemukan.'; END IF;
    END IF;

    RETURN QUERY SELECT r.id, r.name FROM rewards r WHERE r.id = v_id;
END $function$;

GRANT EXECUTE ON FUNCTION upsert_reward(TEXT, TEXT, INT, NUMERIC, TEXT, INT, TEXT, BOOLEAN, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION delete_reward(p_id UUID)
RETURNS TABLE (aksi TEXT, pesan TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_nama TEXT; v_klaim INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh menghapus reward.'; END IF;

    SELECT r.name INTO v_nama FROM rewards r WHERE r.id = p_id;
    IF v_nama IS NULL THEN RAISE EXCEPTION 'Reward tidak ditemukan.'; END IF;

    SELECT COUNT(*) INTO v_klaim FROM reward_claims rc WHERE rc.reward_id = p_id;

    IF v_klaim > 0 THEN
        UPDATE rewards SET is_active = FALSE WHERE rewards.id = p_id;
        RETURN QUERY SELECT 'nonaktif'::TEXT,
            ('"' || v_nama || '" sudah pernah diklaim ' || v_klaim
             || ' kali, jadi dinonaktifkan — bukan dihapus. Ia hilang dari pilihan member, riwayat klaimnya tetap utuh.')::TEXT;
    ELSE
        DELETE FROM rewards WHERE rewards.id = p_id;
        RETURN QUERY SELECT 'hapus'::TEXT,
            ('"' || v_nama || '" belum pernah diklaim siapa pun, jadi dihapus permanen.')::TEXT;
    END IF;
END $function$;

GRANT EXECUTE ON FUNCTION delete_reward(UUID) TO authenticated;


-- ==============================================================================
-- PRODUK — upsert_product sudah bisa menambah sejak awal (saat p_id NULL);
-- yang belum pernah ada hanyalah penghapusannya.
-- ==============================================================================
CREATE OR REPLACE FUNCTION delete_product(p_id UUID)
RETURNS TABLE (aksi TEXT, pesan TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_nama TEXT; v_terjual INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh menghapus produk.'; END IF;

    SELECT p.name INTO v_nama FROM products_hpp p WHERE p.id = p_id;
    IF v_nama IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan.'; END IF;

    SELECT COUNT(*) INTO v_terjual FROM transaction_items ti WHERE ti.product_id = p_id;

    IF v_terjual > 0 THEN
        UPDATE products_hpp SET is_active = FALSE WHERE products_hpp.id = p_id;
        RETURN QUERY SELECT 'nonaktif'::TEXT,
            ('"' || v_nama || '" sudah terjual ' || v_terjual
             || ' kali, jadi dinonaktifkan — bukan dihapus. Menghapusnya akan membuat transaksi lama kehilangan nama produknya.')::TEXT;
    ELSE
        DELETE FROM products_hpp WHERE products_hpp.id = p_id;
        RETURN QUERY SELECT 'hapus'::TEXT,
            ('"' || v_nama || '" belum pernah terjual, jadi dihapus permanen.')::TEXT;
    END IF;
END $function$;

GRANT EXECUTE ON FUNCTION delete_product(UUID) TO authenticated;


-- ==============================================================================
-- ATURAN TIER
--
-- Barisnya selalu lima, mengikuti enum member_tier — tidak bisa ditambah atau
-- dihapus, hanya diubah. compute_tier() memilih tier tertinggi yang ambangnya
-- sudah terlampaui, sehingga ambang yang tidak menaik membuat sebagian tier
-- mustahil dicapai, dan Silver yang tidak bernilai nol membuat member baru
-- tidak punya tier sama sekali.
-- ==============================================================================
CREATE OR REPLACE FUNCTION update_tier_rule(
    p_tier TEXT, p_min_points INT, p_multiplier NUMERIC, p_note TEXT DEFAULT NULL
)
RETURNS TABLE (tier TEXT, min_lifetime_points INT, earn_multiplier NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_urut INT; v_sebelum INT; v_sesudah INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mengubah aturan tier.'; END IF;
    IF p_min_points IS NULL OR p_min_points < 0 THEN
        RAISE EXCEPTION 'Ambang poin tidak boleh negatif.';
    END IF;
    IF p_multiplier IS NULL OR p_multiplier <= 0 THEN
        RAISE EXCEPTION 'Pengali poin harus lebih dari nol.';
    END IF;

    v_urut := array_position(enum_range(NULL::member_tier), p_tier::member_tier);
    IF v_urut IS NULL THEN RAISE EXCEPTION 'Tier "%" tidak dikenali.', p_tier; END IF;

    IF v_urut = 1 AND p_min_points <> 0 THEN
        RAISE EXCEPTION 'Tier terendah harus tetap di 0 poin — itulah titik masuk setiap member baru.';
    END IF;

    -- Ambang harus tetap menaik terhadap tetangganya
    SELECT tr.min_lifetime_points INTO v_sebelum FROM tier_rules tr
     WHERE array_position(enum_range(NULL::member_tier), tr.tier) = v_urut - 1;
    SELECT tr.min_lifetime_points INTO v_sesudah FROM tier_rules tr
     WHERE array_position(enum_range(NULL::member_tier), tr.tier) = v_urut + 1;

    IF v_sebelum IS NOT NULL AND p_min_points <= v_sebelum THEN
        RAISE EXCEPTION 'Ambang % harus lebih besar dari tier di bawahnya (%).', p_tier, v_sebelum;
    END IF;
    IF v_sesudah IS NOT NULL AND p_min_points >= v_sesudah THEN
        RAISE EXCEPTION 'Ambang % harus lebih kecil dari tier di atasnya (%).', p_tier, v_sesudah;
    END IF;

    UPDATE tier_rules tr SET
        min_lifetime_points = p_min_points,
        earn_multiplier = p_multiplier,
        note = NULLIF(btrim(COALESCE(p_note, '')), '')
     WHERE tr.tier = p_tier::member_tier;

    RETURN QUERY SELECT tr.tier::TEXT, tr.min_lifetime_points, tr.earn_multiplier
                   FROM tier_rules tr WHERE tr.tier = p_tier::member_tier;
END $function$;

GRANT EXECUTE ON FUNCTION update_tier_rule(TEXT, INT, NUMERIC, TEXT) TO authenticated;


-- ==============================================================================
-- RASIO POIN
-- ==============================================================================
CREATE OR REPLACE FUNCTION update_loyalty_settings(
    p_rupiah_per_point INT, p_rupiah_per_point_redeem INT,
    p_min_redeem_points INT, p_max_redeem_percent NUMERIC,
    p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (rupiah_per_point INT, rupiah_per_point_redeem INT,
               min_redeem_points INT, max_redeem_percent NUMERIC, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mengubah rasio poin.'; END IF;

    IF p_rupiah_per_point IS NULL OR p_rupiah_per_point <= 0 THEN
        RAISE EXCEPTION 'Rupiah per poin harus lebih dari nol — nol berarti setiap transaksi menghasilkan poin tak terhingga.';
    END IF;
    IF p_rupiah_per_point_redeem IS NULL OR p_rupiah_per_point_redeem <= 0 THEN
        RAISE EXCEPTION 'Nilai tukar satu poin harus lebih dari nol.';
    END IF;
    IF p_min_redeem_points IS NULL OR p_min_redeem_points < 0 THEN
        RAISE EXCEPTION 'Minimal poin untuk menukar tidak boleh negatif.';
    END IF;
    IF p_max_redeem_percent IS NULL OR p_max_redeem_percent <= 0 OR p_max_redeem_percent > 100 THEN
        RAISE EXCEPTION 'Batas penukaran harus antara 1 dan 100 persen.';
    END IF;

    UPDATE loyalty_settings ls SET
        rupiah_per_point = p_rupiah_per_point,
        rupiah_per_point_redeem = p_rupiah_per_point_redeem,
        min_redeem_points = p_min_redeem_points,
        max_redeem_percent = p_max_redeem_percent,
        is_active = p_is_active,
        updated_at = now()
     WHERE ls.id;

    RETURN QUERY SELECT ls.rupiah_per_point, ls.rupiah_per_point_redeem,
                        ls.min_redeem_points, ls.max_redeem_percent, ls.is_active
                   FROM loyalty_settings ls WHERE ls.id;
END $function$;

GRANT EXECUTE ON FUNCTION update_loyalty_settings(INT, INT, INT, NUMERIC, BOOLEAN) TO authenticated;


-- ==============================================================================
-- OUTLET
--
-- Jam buka TIDAK diurus di sini. Sejak migrasi 18 sumbernya adalah tabel
-- jam_operasional per hari; kolom open_time/close_time pada outlets tinggal
-- menjadi cadangan bila tabel itu kosong. Menyediakan kolom jam di layar
-- outlet akan membuat owner mengubah angka yang tidak dibaca siapa pun.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_outlets_list()
RETURNS TABLE (
    id UUID, name VARCHAR, address TEXT, phone VARCHAR,
    latitude NUMERIC, longitude NUMERIC, is_active BOOLEAN, sort_order INT,
    jumlah_absensi INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka daftar outlet.'; END IF;
    RETURN QUERY
    SELECT o.id, o.name, o.address, o.phone, o.latitude, o.longitude,
           o.is_active, o.sort_order,
           COALESCE((SELECT COUNT(*)::INT FROM attendances a WHERE a.outlet_id = o.id), 0)
      FROM outlets o
     ORDER BY o.is_active DESC, o.sort_order;
END $function$;

GRANT EXECUTE ON FUNCTION owner_outlets_list() TO authenticated;


CREATE OR REPLACE FUNCTION upsert_outlet(
    p_name TEXT, p_address TEXT DEFAULT NULL, p_phone TEXT DEFAULT NULL,
    p_lat NUMERIC DEFAULT NULL, p_lng NUMERIC DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT TRUE, p_id UUID DEFAULT NULL
)
RETURNS TABLE (id UUID, name VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_id UUID; v_urut INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mengelola outlet.'; END IF;
    IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'Nama outlet wajib diisi.'; END IF;

    -- Koordinat menentukan diterima atau tidaknya absensi karyawan. Salah
    -- ketik satu digit membuat seluruh tim tertolak absen keesokan harinya,
    -- jadi rentangnya diperiksa di sini, bukan dipercayakan ke ketelitian.
    IF p_lat IS NOT NULL AND (p_lat < -90 OR p_lat > 90) THEN
        RAISE EXCEPTION 'Latitude harus antara -90 dan 90.';
    END IF;
    IF p_lng IS NOT NULL AND (p_lng < -180 OR p_lng > 180) THEN
        RAISE EXCEPTION 'Longitude harus antara -180 dan 180.';
    END IF;
    IF (p_lat IS NULL) <> (p_lng IS NULL) THEN
        RAISE EXCEPTION 'Latitude dan longitude harus diisi berpasangan.';
    END IF;

    IF p_id IS NULL THEN
        SELECT COALESCE(MAX(o.sort_order), 0) + 1 INTO v_urut FROM outlets o;
        INSERT INTO outlets (name, address, phone, latitude, longitude, is_active, sort_order)
        VALUES (btrim(p_name), NULLIF(btrim(COALESCE(p_address, '')), ''),
                NULLIF(btrim(COALESCE(p_phone, '')), ''), p_lat, p_lng, p_is_active, v_urut)
        RETURNING outlets.id INTO v_id;
    ELSE
        UPDATE outlets SET
            name = btrim(p_name),
            address = NULLIF(btrim(COALESCE(p_address, '')), ''),
            phone = NULLIF(btrim(COALESCE(p_phone, '')), ''),
            latitude = p_lat, longitude = p_lng, is_active = p_is_active
        WHERE outlets.id = p_id
        RETURNING outlets.id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Outlet tidak ditemukan.'; END IF;
    END IF;

    RETURN QUERY SELECT o.id, o.name FROM outlets o WHERE o.id = v_id;
END $function$;

GRANT EXECUTE ON FUNCTION upsert_outlet(TEXT, TEXT, TEXT, NUMERIC, NUMERIC, BOOLEAN, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION delete_outlet(p_id UUID)
RETURNS TABLE (aksi TEXT, pesan TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_nama TEXT; v_absen INT; v_sisa INT;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh menghapus outlet.'; END IF;

    SELECT o.name INTO v_nama FROM outlets o WHERE o.id = p_id;
    IF v_nama IS NULL THEN RAISE EXCEPTION 'Outlet tidak ditemukan.'; END IF;

    -- Tanpa satu pun outlet aktif, tab Store pelanggan kosong dan absensi
    -- kehilangan titik acuan jaraknya — seluruh tim tertolak absen.
    SELECT COUNT(*) INTO v_sisa FROM outlets o WHERE o.is_active AND o.id <> p_id;
    IF v_sisa = 0 THEN
        RAISE EXCEPTION 'Ini satu-satunya outlet aktif. Menonaktifkannya membuat absensi kehilangan titik acuan dan tab Store pelanggan kosong.';
    END IF;

    SELECT COUNT(*) INTO v_absen FROM attendances a WHERE a.outlet_id = p_id;

    IF v_absen > 0 THEN
        UPDATE outlets SET is_active = FALSE WHERE outlets.id = p_id;
        RETURN QUERY SELECT 'nonaktif'::TEXT,
            ('"' || v_nama || '" sudah punya ' || v_absen
             || ' catatan absensi, jadi dinonaktifkan — bukan dihapus. Riwayat absensinya tetap utuh.')::TEXT;
    ELSE
        DELETE FROM outlets WHERE outlets.id = p_id;
        RETURN QUERY SELECT 'hapus'::TEXT,
            ('"' || v_nama || '" belum punya catatan absensi, jadi dihapus permanen.')::TEXT;
    END IF;
END $function$;

GRANT EXECUTE ON FUNCTION delete_outlet(UUID) TO authenticated;
