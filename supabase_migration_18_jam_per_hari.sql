-- ==============================================================================
-- MIGRASI 18 — Jam Operasional Berbeda Tiap Hari
--
-- KETERANGAN BARU DARI KLIEN
--   Senin–Kamis dan Sabtu–Minggu : 10.00 – 21.00
--   Jumat                        : 13.00 – 21.00
--
-- KENAPA INI BUKAN SEKADAR MENGGANTI ANGKA
--
-- Skema lama hanya punya SATU jam buka untuk seluruh minggu, tersimpan di dua
-- tempat terpisah: outlets.open_time untuk aplikasi pelanggan, dan
-- work_rules.jam_masuk untuk perhitungan keterlambatan. Keduanya tidak pernah
-- saling memeriksa.
--
-- Akibatnya bila hanya angkanya diganti:
--   * Tab Store menyatakan toko BUKA sejak pukul 10.00 pada hari Jumat,
--     padahal pintunya baru dibuka pukul 13.00.
--   * Setiap Jumat, ketiga capster tercatat TERLAMBAT 180 MENIT — bukan karena
--     mereka telat, melainkan karena sistem mengukur dari jam yang salah.
--
-- Yang kedua paling merusak: laporan absensi bulanan akan menuduh orang yang
-- datang tepat waktu, empat sampai lima kali sebulan, dan tuduhan itu terlihat
-- seperti fakta karena angkanya dihitung mesin.
--
-- SATU SUMBER, BUKAN DUA
--
-- Jadwal dipindahkan ke satu tabel yang dibaca oleh keduanya. Jam buka toko dan
-- jam masuk karyawan pada dasarnya adalah hal yang sama; menyimpannya dua kali
-- berarti suatu hari nanti yang satu diperbarui dan yang lain tidak.
-- ==============================================================================


-- ==============================================================================
-- 1. JADWAL PER HARI
--
-- dow mengikuti EXTRACT(DOW): 0 = Minggu, 1 = Senin, ... 5 = Jumat, 6 = Sabtu.
-- ==============================================================================
CREATE TABLE IF NOT EXISTS jam_operasional (
    dow    SMALLINT PRIMARY KEY CHECK (dow BETWEEN 0 AND 6),
    buka   TIME NOT NULL,
    tutup  TIME NOT NULL,
    libur  BOOLEAN NOT NULL DEFAULT false,
    CHECK (libur OR tutup > buka)
);

ALTER TABLE jam_operasional ENABLE ROW LEVEL SECURITY;

-- Pelanggan perlu tahu jam buka tanpa login, sama seperti katalog layanan.
DROP POLICY IF EXISTS jam_baca_semua ON jam_operasional;
CREATE POLICY jam_baca_semua ON jam_operasional
    FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS jam_kelola_owner ON jam_operasional;
CREATE POLICY jam_kelola_owner ON jam_operasional
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());

-- Seed sesuai keterangan klien
INSERT INTO jam_operasional (dow, buka, tutup, libur) VALUES
    (0, '10:00', '21:00', false),   -- Minggu
    (1, '10:00', '21:00', false),   -- Senin
    (2, '10:00', '21:00', false),   -- Selasa
    (3, '10:00', '21:00', false),   -- Rabu
    (4, '10:00', '21:00', false),   -- Kamis
    (5, '13:00', '21:00', false),   -- Jumat — buka lebih siang
    (6, '10:00', '21:00', false)    -- Sabtu
ON CONFLICT (dow) DO UPDATE
   SET buka = EXCLUDED.buka, tutup = EXCLUDED.tutup, libur = EXCLUDED.libur;


-- ==============================================================================
-- 2. JAM HARI INI — SATU FUNGSI YANG DIPAKAI SEMUA
-- ==============================================================================
CREATE OR REPLACE FUNCTION jam_hari_ini(p_tanggal date DEFAULT NULL)
RETURNS TABLE (buka TIME, tutup TIME, libur BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT j.buka, j.tutup, j.libur
      FROM jam_operasional j
     WHERE j.dow = EXTRACT(DOW FROM COALESCE(p_tanggal, jakarta_today()))::SMALLINT;
$$;

GRANT EXECUTE ON FUNCTION jam_hari_ini(date) TO anon, authenticated;


-- ==============================================================================
-- 3. OUTLET IKUT JADWAL HARIAN
--
-- open_time/close_time pada tabel outlets dipertahankan sebagai cadangan bila
-- tabel jadwal kosong, tetapi jadwal harian yang menang.
-- ==============================================================================
CREATE OR REPLACE FUNCTION member_outlets()
RETURNS TABLE (
    id UUID, name VARCHAR, address TEXT, phone VARCHAR,
    latitude NUMERIC, longitude NUMERIC,
    open_time TIME, close_time TIME,
    sedang_buka BOOLEAN, catatan TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    WITH j AS (
        SELECT jo.buka, jo.tutup, jo.libur
          FROM jam_operasional jo
         WHERE jo.dow = EXTRACT(DOW FROM (now() AT TIME ZONE 'Asia/Jakarta'))::SMALLINT
    )
    SELECT o.id, o.name, o.address, o.phone, o.latitude, o.longitude,
           COALESCE((SELECT buka  FROM j), o.open_time),
           COALESCE((SELECT tutup FROM j), o.close_time),
           (
             NOT COALESCE((SELECT libur FROM j), false)
             AND NOT (EXTRACT(DOW FROM (now() AT TIME ZONE 'Asia/Jakarta'))::INT = ANY(o.closed_days))
             AND (now() AT TIME ZONE 'Asia/Jakarta')::TIME
                 BETWEEN COALESCE((SELECT buka FROM j), o.open_time)
                     AND COALESCE((SELECT tutup FROM j), o.close_time)
           ) AS sedang_buka,
           CASE
             WHEN COALESCE((SELECT libur FROM j), false) THEN 'Tutup hari ini'
             WHEN (now() AT TIME ZONE 'Asia/Jakarta')::TIME
                  < COALESCE((SELECT buka FROM j), o.open_time)
               THEN 'Buka pukul ' || to_char(COALESCE((SELECT buka FROM j), o.open_time), 'HH24:MI')
             WHEN (now() AT TIME ZONE 'Asia/Jakarta')::TIME
                  > COALESCE((SELECT tutup FROM j), o.close_time)
               THEN 'Sudah tutup'
             ELSE 'Sedang buka'
           END AS catatan
      FROM outlets o
     WHERE o.is_active
     ORDER BY o.sort_order;
$$;

GRANT EXECUTE ON FUNCTION member_outlets() TO anon, authenticated;


-- ==============================================================================
-- 4. KETERLAMBATAN DIUKUR DARI JAM HARI ITU
--
-- Definisi diambil dari fungsi yang hidup lalu ditambal pada satu tempat saja:
-- sumber jam masuk. Sisanya — selfie wajib, validasi lokasi, satu catatan per
-- hari — tidak disentuh.
-- ==============================================================================
CREATE OR REPLACE FUNCTION clock_in(
    p_selfie_url TEXT,
    p_lat NUMERIC DEFAULT NULL,
    p_lng NUMERIC DEFAULT NULL
)
RETURNS TABLE (
    waktu TIMESTAMPTZ, status attend_status, terlambat_menit INT, jarak_m INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_cap   capsters%ROWTYPE;
    v_rule  work_rules%ROWTYPE;
    v_out   outlets%ROWTYPE;
    v_now   TIMESTAMPTZ := now();
    v_date  date := jakarta_today();
    v_wib   TIME;
    v_jarak NUMERIC;
    v_lambat INT := 0;
    v_stat  attend_status := 'hadir';
    v_masuk TIME;
BEGIN
    SELECT * INTO v_cap FROM capsters c WHERE c.auth_user_id = auth.uid() AND c.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan aktif.';
    END IF;

    SELECT * INTO v_rule FROM work_rules wr WHERE wr.id;

    IF v_rule.wajib_selfie AND COALESCE(btrim(p_selfie_url), '') = '' THEN
        RAISE EXCEPTION 'Foto selfie wajib diambil sebelum absen.';
    END IF;

    SELECT * INTO v_out FROM outlets o
     WHERE o.is_active AND o.latitude IS NOT NULL AND o.longitude IS NOT NULL
     ORDER BY o.sort_order LIMIT 1;

    IF v_rule.wajib_lokasi AND FOUND THEN
        IF p_lat IS NULL OR p_lng IS NULL THEN
            RAISE EXCEPTION 'Lokasi tidak terbaca. Izinkan akses lokasi lalu coba lagi.';
        END IF;
        v_jarak := jarak_meter(p_lat, p_lng, v_out.latitude, v_out.longitude);
        IF v_jarak > v_rule.radius_absen_m THEN
            RAISE EXCEPTION 'Anda berada % meter dari outlet. Absen hanya bisa dalam radius % meter.',
                round(v_jarak)::INT, v_rule.radius_absen_m;
        END IF;
    END IF;

    -- Jam masuk diambil dari jadwal HARI ITU, bukan satu angka untuk seminggu.
    -- Tanpa ini, setiap Jumat seluruh capster tercatat terlambat tiga jam
    -- padahal mereka datang tepat pada jam buka.
    SELECT jh.buka INTO v_masuk FROM jam_hari_ini(v_date) jh;
    v_masuk := COALESCE(v_masuk, v_rule.jam_masuk);

    v_wib := (v_now AT TIME ZONE 'Asia/Jakarta')::TIME;
    IF v_wib > (v_masuk + make_interval(mins => v_rule.toleransi_menit)) THEN
        v_lambat := EXTRACT(EPOCH FROM (v_wib - v_masuk)) / 60;
        v_stat := 'terlambat';
    END IF;

    BEGIN
        INSERT INTO attendances (capster_id, check_in_time, selfie_url,
                                 latitude, longitude, is_valid_location,
                                 status, terlambat_menit, jarak_m,
                                 outlet_id, business_date)
        VALUES (v_cap.id, v_now, NULLIF(btrim(p_selfie_url), ''),
                p_lat, p_lng, true,
                v_stat, v_lambat, round(COALESCE(v_jarak, 0))::INT,
                v_out.id, v_date);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'Anda sudah absen masuk hari ini.';
    END;

    RETURN QUERY SELECT v_now, v_stat, v_lambat, round(COALESCE(v_jarak, 0))::INT;
END $$;

GRANT EXECUTE ON FUNCTION clock_in(TEXT, NUMERIC, NUMERIC) TO authenticated;


-- ==============================================================================
-- 5. JADWAL LENGKAP UNTUK LAYAR OWNER & PELANGGAN
-- ==============================================================================
CREATE OR REPLACE FUNCTION jadwal_mingguan()
RETURNS TABLE (dow SMALLINT, hari TEXT, buka TIME, tutup TIME, libur BOOLEAN, hari_ini BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT j.dow,
           (ARRAY['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'])[j.dow + 1],
           j.buka, j.tutup, j.libur,
           j.dow = EXTRACT(DOW FROM jakarta_today())::SMALLINT
      FROM jam_operasional j
     ORDER BY CASE WHEN j.dow = 0 THEN 7 ELSE j.dow END;
$$;

GRANT EXECUTE ON FUNCTION jadwal_mingguan() TO anon, authenticated;


-- ==============================================================================
-- 6. SELARASKAN ANGKA LAMA
--
-- outlets dan work_rules tetap menyimpan jam sebagai cadangan; nilainya
-- disamakan dengan hari biasa supaya cadangan itu tidak menyesatkan bila suatu
-- saat terpakai.
-- ==============================================================================
UPDATE outlets     SET open_time = '10:00', close_time = '21:00';
UPDATE work_rules  SET jam_masuk = '10:00', jam_pulang = '21:00';
