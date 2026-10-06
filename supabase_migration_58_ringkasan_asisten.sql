-- ==============================================================================
-- MIGRASI 58 - Ringkasan data toko untuk Asisten Internal (Add-on AI, fitur 5)
--
-- Penawaran #INV/BU-AI/2026/019, fitur 5 bagian "Internal Helper": owner
-- bertanya soal data operasional toko dengan bahasa sehari-hari — "omzet
-- minggu ini berapa?", "kapster siapa paling ramai bulan ini?", "produk apa
-- yang mau habis?".
--
-- AI TIDAK PERNAH MENULIS QUERY
--
-- Model tidak diberi akses ke basis data dan tidak diminta menyusun SQL.
-- SQL buatan model dapat salah hitung tanpa terlihat (diskon terlupa,
-- transaksi terhapus ikut terhitung, zona waktu meleset) atau lebih buruk,
-- dibujuk membaca hal yang bukan untuknya. Sebagai gantinya fungsi ini
-- menghitung satu ringkasan tetap dengan aturan yang sama dengan laporan
-- owner, dan model hanya MEMBACA ringkasan itu. Pertanyaan yang jawabannya
-- tidak ada di ringkasan dijawab "datanya tidak tersedia", bukan dikarang.
--
-- HANYA UNTUK SERVER
--
-- Fungsi ini tidak memeriksa is_owner(): ia dipanggil Edge Function
-- ai-asisten dengan kunci layanan, SESUDAH fungsi itu memastikan
-- pemanggilnya owner. Karena itu EXECUTE dicabut dari PUBLIC, anon, dan
-- authenticated, dan hanya diberikan ke service_role — tidak ada jalan
-- memanggilnya dari peramban, termasuk oleh owner sendiri.
--
-- Semua tanggal adalah tanggal operasional WIB (business_date), sama
-- dengan rekap harian. Nomor telepon dan nama pelanggan tidak ikut: asisten
-- tidak memerlukannya untuk menjawab soal operasional.
-- ==============================================================================

CREATE OR REPLACE FUNCTION ringkasan_asisten(p_hari_ini DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SET search_path = public
AS $function$
DECLARE
    v_bulan  JSONB := '[]'::JSONB;
    v_awal   DATE;
    v_akhir  DATE;
    v_m      INT;
    v_satu   JSONB;
BEGIN
    IF p_hari_ini IS NULL THEN
        RAISE EXCEPTION 'Tanggal hari ini wajib diisi.';
    END IF;

    -- ── Tiga bulan terakhir, bulan berjalan sampai hari ini ──────────────
    FOR v_m IN REVERSE 2 .. 0 LOOP
        v_awal  := (date_trunc('month', p_hari_ini) - make_interval(months => v_m))::DATE;
        v_akhir := LEAST((v_awal + INTERVAL '1 month - 1 day')::DATE, p_hari_ini);

        SELECT jsonb_build_object(
            'bulan',  to_char(v_awal, 'YYYY-MM'),
            'dari',   v_awal,
            'sampai', v_akhir,
            'transaksi', (SELECT count(*) FROM transactions t
                           WHERE t.business_date BETWEEN v_awal AND v_akhir),
            'omzet', (SELECT COALESCE(sum(t.final_amount), 0) FROM transactions t
                       WHERE t.business_date BETWEEN v_awal AND v_akhir),
            'per_metode', (SELECT COALESCE(jsonb_object_agg(x.metode, x.omzet), '{}'::JSONB) FROM (
                              SELECT t.payment_method::TEXT AS metode, sum(t.final_amount) AS omzet
                                FROM transactions t
                               WHERE t.business_date BETWEEN v_awal AND v_akhir
                               GROUP BY 1) x),
            'diskon_poin', (SELECT COALESCE(sum(t.discount_points), 0) FROM transactions t
                             WHERE t.business_date BETWEEN v_awal AND v_akhir),
            'diskon_kasir', (SELECT COALESCE(sum(t.discount_manual), 0) FROM transactions t
                              WHERE t.business_date BETWEEN v_awal AND v_akhir),
            'transaksi_member', (SELECT count(*) FROM transactions t
                                  WHERE t.business_date BETWEEN v_awal AND v_akhir AND t.member_id IS NOT NULL),
            'member_baru', (SELECT count(*) FROM members m
                             WHERE (m.created_at AT TIME ZONE 'Asia/Jakarta')::DATE BETWEEN v_awal AND v_akhir),
            'pengeluaran', (SELECT COALESCE(sum(p.total), 0) FROM pengeluaran p
                             WHERE p.tanggal BETWEEN v_awal AND v_akhir),
            'booking', (SELECT COALESCE(jsonb_object_agg(x.status, x.n), '{}'::JSONB) FROM (
                           SELECT b.status::TEXT AS status, count(*) AS n FROM bookings b
                            WHERE b.tanggal BETWEEN v_awal AND v_akhir GROUP BY 1) x),
            -- Per kapster dari baris barang, bukan dari kepala transaksi:
            -- satu nota bisa dikerjakan dua orang (migrasi 17).
            'kapster', (SELECT COALESCE(jsonb_agg(x ORDER BY x.nilai DESC), '[]'::JSONB) FROM (
                           SELECT COALESCE(i.capster_name, t.capster_name, '(tanpa kapster)') AS nama,
                                  count(*) FILTER (WHERE i.item_type = 'layanan') AS layanan,
                                  sum(i.price) AS nilai
                             FROM transaction_items i JOIN transactions t ON t.id = i.transaction_id
                            WHERE t.business_date BETWEEN v_awal AND v_akhir
                            GROUP BY 1) x),
            'layanan_teratas', (SELECT COALESCE(jsonb_agg(x ORDER BY x.jumlah DESC, x.nilai DESC), '[]'::JSONB) FROM (
                                   SELECT i.service_name AS nama, sum(i.qty) AS jumlah, sum(i.price) AS nilai
                                     FROM transaction_items i JOIN transactions t ON t.id = i.transaction_id
                                    WHERE t.business_date BETWEEN v_awal AND v_akhir AND i.item_type = 'layanan'
                                    GROUP BY 1 ORDER BY 2 DESC, 3 DESC LIMIT 10) x),
            'produk_terjual', (SELECT COALESCE(jsonb_agg(x ORDER BY x.jumlah DESC), '[]'::JSONB) FROM (
                                  SELECT i.service_name AS nama, sum(i.qty) AS jumlah, sum(i.price) AS nilai
                                    FROM transaction_items i JOIN transactions t ON t.id = i.transaction_id
                                   WHERE t.business_date BETWEEN v_awal AND v_akhir AND i.item_type = 'produk'
                                   GROUP BY 1 ORDER BY 2 DESC LIMIT 15) x)
        ) INTO v_satu;
        v_bulan := v_bulan || jsonb_build_array(v_satu);
    END LOOP;

    RETURN jsonb_build_object(
        'hari_ini', p_hari_ini,
        'bulanan', v_bulan,

        -- Hari tanpa transaksi tidak dicantumkan; artinya nol.
        'harian_60_hari', (SELECT COALESCE(jsonb_agg(x ORDER BY x.tanggal), '[]'::JSONB) FROM (
                              SELECT t.business_date AS tanggal, count(*) AS transaksi, sum(t.final_amount) AS omzet
                                FROM transactions t
                               WHERE t.business_date BETWEEN p_hari_ini - 59 AND p_hari_ini
                               GROUP BY 1) x),

        -- Sama dengan owner_stok_list (migrasi 57), hanya produk aktif.
        'stok', (SELECT COALESCE(jsonb_agg(x ORDER BY x.produk), '[]'::JSONB) FROM (
                    SELECT p.name AS produk, s.stok, p.stok_minimum AS batas_menipis,
                           CASE WHEN s.terakhir_dihitung IS NULL THEN 'belum dihitung'
                                WHEN s.stok <= 0 THEN 'habis'
                                WHEN s.stok <= p.stok_minimum THEN 'menipis'
                                ELSE 'aman' END AS status
                      FROM products_hpp p
                      CROSS JOIN LATERAL (
                          SELECT COALESCE(sum(m.qty_delta), 0) AS stok,
                                 max(m.created_at) FILTER (WHERE m.jenis = 'hitung') AS terakhir_dihitung
                            FROM stok_mutasi m WHERE m.product_id = p.id) s
                     WHERE p.is_active) x),

        'pengeluaran_terakhir', (SELECT COALESCE(jsonb_agg(x ORDER BY x.tanggal DESC), '[]'::JSONB) FROM (
                                    SELECT p.tanggal, p.toko, p.total,
                                           (SELECT string_agg(i.nama, ', ' ORDER BY i.urutan)
                                              FROM pengeluaran_item i WHERE i.pengeluaran_id = p.id) AS barang
                                      FROM pengeluaran p
                                     ORDER BY p.tanggal DESC, p.created_at DESC LIMIT 15) x),

        -- Bulan berjalan. Hari izin/libur dihitung hanya yang disetujui
        -- dan hanya bagian yang jatuh di bulan ini.
        'absensi_bulan_ini', (SELECT COALESCE(jsonb_agg(x ORDER BY x.nama), '[]'::JSONB) FROM (
                                 SELECT c.name AS nama, c.jabatan,
                                        (SELECT count(DISTINCT a.business_date) FROM attendances a
                                          WHERE a.capster_id = c.id
                                            AND a.business_date BETWEEN date_trunc('month', p_hari_ini)::DATE AND p_hari_ini) AS hari_masuk,
                                        (SELECT count(*) FROM attendances a
                                          WHERE a.capster_id = c.id AND a.status = 'terlambat'
                                            AND a.business_date BETWEEN date_trunc('month', p_hari_ini)::DATE AND p_hari_ini) AS kali_terlambat,
                                        (SELECT COALESCE(sum(a.terlambat_menit), 0) FROM attendances a
                                          WHERE a.capster_id = c.id
                                            AND a.business_date BETWEEN date_trunc('month', p_hari_ini)::DATE AND p_hari_ini) AS total_menit_terlambat,
                                        (SELECT COALESCE(sum(LEAST(l.tanggal_selesai, p_hari_ini)
                                                             - GREATEST(l.tanggal_mulai, date_trunc('month', p_hari_ini)::DATE) + 1), 0)
                                           FROM leave_requests l
                                          WHERE l.capster_id = c.id AND l.status = 'disetujui'
                                            AND l.tanggal_mulai <= p_hari_ini
                                            AND l.tanggal_selesai >= date_trunc('month', p_hari_ini)::DATE) AS hari_izin_libur
                                   FROM capsters c WHERE c.is_active) x),

        'member', jsonb_build_object(
            'total', (SELECT count(*) FROM members),
            'per_tingkat', (SELECT COALESCE(jsonb_object_agg(x.tier, x.n), '{}'::JSONB) FROM (
                               SELECT m.tier::TEXT AS tier, count(*) AS n FROM members m GROUP BY 1) x)),

        'booking_7_hari_ke_depan', (SELECT COALESCE(jsonb_agg(x ORDER BY x.tanggal), '[]'::JSONB) FROM (
                                       SELECT b.tanggal, count(*) AS jumlah,
                                              count(*) FILTER (WHERE b.status = 'baru') AS belum_dikonfirmasi
                                         FROM bookings b
                                        WHERE b.tanggal BETWEEN p_hari_ini AND p_hari_ini + 6
                                          AND b.status IN ('baru', 'dikonfirmasi')
                                        GROUP BY 1) x),

        'karyawan', (SELECT COALESCE(jsonb_agg(x ORDER BY x.nama), '[]'::JSONB) FROM (
                        SELECT c.name AS nama, c.jabatan FROM capsters c WHERE c.is_active) x)
    );
END $function$;

REVOKE EXECUTE ON FUNCTION ringkasan_asisten(DATE) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION ringkasan_asisten(DATE) TO service_role;
