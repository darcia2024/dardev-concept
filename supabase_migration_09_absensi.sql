-- ==============================================================================
-- MIGRASI 09 — Absensi & Cuti Karyawan (Fase 3)
--
-- PROTEKSI TERHADAP TITIP ABSEN (addendum bagian 04)
--   Empat penjagaan, dan tiga di antaranya HARUS berada di server. Yang
--   dikerjakan di browser dapat diubah orang yang berkepentingan mengubahnya.
--
--   1. Waktu diambil dari now() basis data. Mengubah jam ponsel tidak
--      berpengaruh — klien tidak pernah mengirimkan waktu absen.
--   2. Jarak ke outlet dihitung di server dari koordinat yang dikirim,
--      dibandingkan dengan radius yang ditetapkan owner.
--   3. Selfie wajib: clock_in menolak permintaan tanpa berkas.
--   4. Satu catatan per hari per karyawan, dijaga indeks unik — bukan
--      sekadar pemeriksaan di aplikasi yang bisa dilewati permintaan ganda.
--
--   Yang tidak dapat dijamin sistem: koordinat GPS dapat dipalsukan pada
--   perangkat yang sudah di-root atau memakai aplikasi mock location. Ini
--   batasan nyata dan disebutkan apa adanya, bukan dianggap tidak ada.
-- ==============================================================================

-- 1. ATURAN KERJA (SATU BARIS) ------------------------------------------------
CREATE TABLE IF NOT EXISTS work_rules (
    id BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),
    jam_masuk TIME NOT NULL DEFAULT '09:00',
    jam_pulang TIME NOT NULL DEFAULT '21:00',
    toleransi_menit INT NOT NULL DEFAULT 15 CHECK (toleransi_menit >= 0),
    kuota_cuti_tahunan INT NOT NULL DEFAULT 12 CHECK (kuota_cuti_tahunan >= 0),
    radius_absen_m INT NOT NULL DEFAULT 100 CHECK (radius_absen_m > 0),
    wajib_selfie BOOLEAN NOT NULL DEFAULT true,
    -- Bila outlet belum berkoordinat, validasi lokasi dilewati agar absensi
    -- tidak macet total; owner diberi tahu lewat kolom ini.
    wajib_lokasi BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO work_rules (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

-- 2. KOLOM TAMBAHAN PADA ABSENSI ----------------------------------------------
DO $$ BEGIN
    CREATE TYPE attend_status AS ENUM ('hadir', 'terlambat');
EXCEPTION WHEN duplicate_object THEN null; END $$;

ALTER TABLE attendances ADD COLUMN IF NOT EXISTS status attend_status NOT NULL DEFAULT 'hadir';
ALTER TABLE attendances ADD COLUMN IF NOT EXISTS terlambat_menit INT NOT NULL DEFAULT 0;
ALTER TABLE attendances ADD COLUMN IF NOT EXISTS menit_kerja INT;
ALTER TABLE attendances ADD COLUMN IF NOT EXISTS jarak_m INT;
ALTER TABLE attendances ADD COLUMN IF NOT EXISTS selfie_out_url TEXT;
ALTER TABLE attendances ADD COLUMN IF NOT EXISTS outlet_id UUID REFERENCES outlets(id) ON DELETE SET NULL;

-- Satu catatan per karyawan per hari operasional. Dijaga basis data, bukan
-- aplikasi: dua permintaan yang tiba bersamaan tetap hanya menghasilkan satu.
CREATE UNIQUE INDEX IF NOT EXISTS idx_absen_harian
    ON attendances(capster_id, business_date);

-- 3. JARAK DUA KOORDINAT (HAVERSINE, METER) -----------------------------------
CREATE OR REPLACE FUNCTION jarak_meter(
    lat1 NUMERIC, lon1 NUMERIC, lat2 NUMERIC, lon2 NUMERIC
) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
    SELECT 6371000 * 2 * asin(sqrt(
        power(sin(radians(lat2 - lat1) / 2), 2) +
        cos(radians(lat1)) * cos(radians(lat2)) *
        power(sin(radians(lon2 - lon1) / 2), 2)
    ))
$$;

-- 4. ABSEN MASUK --------------------------------------------------------------
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
    v_now   TIMESTAMPTZ := now();          -- waktu server, bukan kiriman klien
    v_wib   TIME;
    v_date  date := jakarta_today();
    v_jarak NUMERIC;
    v_lambat INT := 0;
    v_stat  attend_status := 'hadir';
BEGIN
    SELECT * INTO v_cap FROM capsters c WHERE c.auth_user_id = auth.uid() AND c.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan aktif.';
    END IF;

    SELECT * INTO v_rule FROM work_rules wr WHERE wr.id;

    IF v_rule.wajib_selfie AND COALESCE(btrim(p_selfie_url), '') = '' THEN
        RAISE EXCEPTION 'Foto selfie wajib diambil sebelum absen.';
    END IF;

    -- Validasi lokasi terhadap outlet berkoordinat
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

    v_wib := (v_now AT TIME ZONE 'Asia/Jakarta')::TIME;
    IF v_wib > (v_rule.jam_masuk + make_interval(mins => v_rule.toleransi_menit)) THEN
        v_lambat := EXTRACT(EPOCH FROM (v_wib - v_rule.jam_masuk)) / 60;
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

-- 5. ABSEN PULANG -------------------------------------------------------------
CREATE OR REPLACE FUNCTION clock_out(
    p_selfie_url TEXT DEFAULT NULL,
    p_lat NUMERIC DEFAULT NULL,
    p_lng NUMERIC DEFAULT NULL
)
RETURNS TABLE (waktu TIMESTAMPTZ, menit_kerja INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_cap capsters%ROWTYPE;
    v_row attendances%ROWTYPE;
    v_now TIMESTAMPTZ := now();
    v_min INT;
BEGIN
    SELECT * INTO v_cap FROM capsters c WHERE c.auth_user_id = auth.uid() AND c.is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan aktif.'; END IF;

    SELECT * INTO v_row FROM attendances a
     WHERE a.capster_id = v_cap.id AND a.business_date = jakarta_today()
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Belum ada absen masuk hari ini.'; END IF;
    IF v_row.check_out_time IS NOT NULL THEN
        RAISE EXCEPTION 'Anda sudah absen pulang pada %.',
            to_char(v_row.check_out_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI');
    END IF;

    v_min := GREATEST(0, EXTRACT(EPOCH FROM (v_now - v_row.check_in_time)) / 60)::INT;

    UPDATE attendances SET check_out_time = v_now,
                           selfie_out_url = NULLIF(btrim(p_selfie_url), ''),
                           menit_kerja = v_min
     WHERE attendances.id = v_row.id;

    RETURN QUERY SELECT v_now, v_min;
END $$;

-- 6. ABSENSI SAYA -------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_attendance(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    business_date date, check_in_time TIMESTAMPTZ, check_out_time TIMESTAMPTZ,
    status attend_status, terlambat_menit INT, menit_kerja INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID; v_awal date;
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan.'; END IF;
    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    RETURN QUERY
    SELECT a.business_date, a.check_in_time, a.check_out_time,
           a.status, a.terlambat_menit, a.menit_kerja
      FROM attendances a
     WHERE a.capster_id = v_id
       AND a.business_date >= v_awal
       AND a.business_date < (v_awal + interval '1 month')
     ORDER BY a.business_date DESC;
END $$;

-- 7. PENGAJUAN CUTI -----------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE leave_kind AS ENUM ('Cuti Tahunan', 'Izin', 'Sakit');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE leave_status AS ENUM ('menunggu', 'disetujui', 'ditolak', 'dibatalkan');
EXCEPTION WHEN duplicate_object THEN null; END $$;

CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    capster_id UUID NOT NULL REFERENCES capsters(id) ON DELETE CASCADE,
    capster_name VARCHAR(150) NOT NULL,
    kind leave_kind NOT NULL,
    tanggal_mulai date NOT NULL,
    tanggal_selesai date NOT NULL,
    jumlah_hari INT NOT NULL CHECK (jumlah_hari > 0),
    alasan TEXT,
    lampiran_url TEXT,
    status leave_status NOT NULL DEFAULT 'menunggu',
    catatan_owner TEXT,
    diputus_oleh UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    diputus_pada TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (tanggal_selesai >= tanggal_mulai)
);
CREATE INDEX IF NOT EXISTS idx_cuti_capster ON leave_requests(capster_id);
CREATE INDEX IF NOT EXISTS idx_cuti_status ON leave_requests(status);

CREATE OR REPLACE FUNCTION request_leave(
    p_kind TEXT, p_mulai date, p_selesai date,
    p_alasan TEXT DEFAULT NULL, p_lampiran TEXT DEFAULT NULL
)
RETURNS TABLE (id UUID, jumlah_hari INT, sisa_kuota INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_cap capsters%ROWTYPE;
    v_rule work_rules%ROWTYPE;
    v_hari INT;
    v_pakai INT;
    v_id UUID;
BEGIN
    SELECT * INTO v_cap FROM capsters c WHERE c.auth_user_id = auth.uid() AND c.is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan aktif.'; END IF;
    IF p_selesai < p_mulai THEN RAISE EXCEPTION 'Tanggal selesai tidak boleh sebelum tanggal mulai.'; END IF;

    v_hari := (p_selesai - p_mulai) + 1;
    SELECT * INTO v_rule FROM work_rules wr WHERE wr.id;

    -- Rentang yang bertindih membuat kalender tim salah baca
    IF EXISTS (
        SELECT 1 FROM leave_requests lr
         WHERE lr.capster_id = v_cap.id
           AND lr.status IN ('menunggu', 'disetujui')
           AND lr.tanggal_mulai <= p_selesai
           AND lr.tanggal_selesai >= p_mulai
    ) THEN
        RAISE EXCEPTION 'Sudah ada pengajuan pada rentang tanggal itu.';
    END IF;

    -- Kuota hanya berlaku untuk cuti tahunan; izin dan sakit tidak memotongnya.
    -- Pengajuan yang masih MENUNGGU ikut dihitung: bila hanya yang disetujui
    -- yang dijumlah, karyawan dapat mengirim beberapa pengajuan sekaligus di
    -- rentang berbeda yang masing-masing lolos, lalu semuanya disetujui dan
    -- kuota terlampaui.
    IF p_kind = 'Cuti Tahunan' THEN
        SELECT COALESCE(SUM(lr.jumlah_hari), 0) INTO v_pakai
          FROM leave_requests lr
         WHERE lr.capster_id = v_cap.id AND lr.kind = 'Cuti Tahunan'
           AND lr.status IN ('disetujui', 'menunggu')
           AND EXTRACT(YEAR FROM lr.tanggal_mulai) = EXTRACT(YEAR FROM p_mulai);
        IF v_pakai + v_hari > v_rule.kuota_cuti_tahunan THEN
            RAISE EXCEPTION 'Kuota cuti tahunan tidak cukup. Terpakai % dari % hari.',
                v_pakai, v_rule.kuota_cuti_tahunan;
        END IF;
    END IF;

    INSERT INTO leave_requests (capster_id, capster_name, kind, tanggal_mulai,
                                tanggal_selesai, jumlah_hari, alasan, lampiran_url)
    VALUES (v_cap.id, v_cap.name, p_kind::leave_kind, p_mulai, p_selesai,
            v_hari, NULLIF(btrim(p_alasan), ''), NULLIF(btrim(p_lampiran), ''))
    RETURNING leave_requests.id INTO v_id;

    RETURN QUERY SELECT v_id, v_hari,
        GREATEST(0, v_rule.kuota_cuti_tahunan - COALESCE(v_pakai, 0) - CASE WHEN p_kind = 'Cuti Tahunan' THEN v_hari ELSE 0 END);
END $$;

CREATE OR REPLACE FUNCTION my_leaves()
RETURNS TABLE (
    id UUID, kind leave_kind, tanggal_mulai date, tanggal_selesai date,
    jumlah_hari INT, alasan TEXT, status leave_status, catatan_owner TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN RETURN; END IF;
    RETURN QUERY
    SELECT lr.id, lr.kind, lr.tanggal_mulai, lr.tanggal_selesai, lr.jumlah_hari,
           lr.alasan, lr.status, lr.catatan_owner, lr.created_at
      FROM leave_requests lr WHERE lr.capster_id = v_id
     ORDER BY lr.created_at DESC LIMIT 50;
END $$;

-- 8. PERSETUJUAN OWNER --------------------------------------------------------
CREATE OR REPLACE FUNCTION decide_leave(p_id UUID, p_setuju BOOLEAN, p_catatan TEXT DEFAULT NULL)
RETURNS TABLE (id UUID, status leave_status)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_row leave_requests%ROWTYPE;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh memutus pengajuan cuti.'; END IF;

    SELECT * INTO v_row FROM leave_requests lr WHERE lr.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan.'; END IF;
    IF v_row.status <> 'menunggu' THEN
        RAISE EXCEPTION 'Pengajuan ini sudah diputus (%).', v_row.status;
    END IF;

    UPDATE leave_requests SET
        status = CASE WHEN p_setuju THEN 'disetujui'::leave_status ELSE 'ditolak'::leave_status END,
        catatan_owner = NULLIF(btrim(p_catatan), ''),
        diputus_oleh = auth.uid(), diputus_pada = now()
    WHERE leave_requests.id = p_id;

    RETURN QUERY SELECT lr.id, lr.status FROM leave_requests lr WHERE lr.id = p_id;
END $$;

-- 9. REKAP BULANAN (OWNER) ----------------------------------------------------
CREATE OR REPLACE FUNCTION attendance_report(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    capster_id UUID, nama VARCHAR,
    hadir INT, terlambat INT, total_menit_kerja INT,
    cuti_disetujui INT, sisa_kuota_cuti INT, cuti_menunggu INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_awal date; v_rule work_rules%ROWTYPE;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka rekap absensi.'; END IF;
    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    SELECT * INTO v_rule FROM work_rules wr WHERE wr.id;

    RETURN QUERY
    SELECT c.id, c.name,
           COALESCE(a.hadir, 0), COALESCE(a.telat, 0), COALESCE(a.menit, 0),
           COALESCE(l.setuju, 0),
           GREATEST(0, v_rule.kuota_cuti_tahunan - COALESCE(l.tahunan, 0)),
           COALESCE(l.tunggu, 0)
      FROM capsters c
      LEFT JOIN LATERAL (
            SELECT COUNT(*)::INT AS hadir,
                   COUNT(*) FILTER (WHERE at.status = 'terlambat')::INT AS telat,
                   COALESCE(SUM(at.menit_kerja), 0)::INT AS menit
              FROM attendances at
             WHERE at.capster_id = c.id
               AND at.business_date >= v_awal
               AND at.business_date < (v_awal + interval '1 month')
      ) a ON true
      LEFT JOIN LATERAL (
            SELECT COUNT(*) FILTER (WHERE lr.status = 'disetujui')::INT AS setuju,
                   COUNT(*) FILTER (WHERE lr.status = 'menunggu')::INT AS tunggu,
                   COALESCE(SUM(lr.jumlah_hari) FILTER (
                       WHERE lr.status = 'disetujui' AND lr.kind = 'Cuti Tahunan'
                         AND EXTRACT(YEAR FROM lr.tanggal_mulai) = EXTRACT(YEAR FROM v_awal)
                   ), 0)::INT AS tahunan
              FROM leave_requests lr WHERE lr.capster_id = c.id
      ) l ON true
     WHERE c.is_active
     ORDER BY c.name;
END $$;

-- 10. PENGAJUAN YANG MENUNGGU (OWNER) -----------------------------------------
CREATE OR REPLACE FUNCTION pending_leaves()
RETURNS TABLE (
    id UUID, capster_name VARCHAR, kind leave_kind,
    tanggal_mulai date, tanggal_selesai date, jumlah_hari INT,
    alasan TEXT, lampiran_url TEXT, status leave_status, created_at TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka daftar pengajuan cuti.'; END IF;
    RETURN QUERY
    SELECT lr.id, lr.capster_name, lr.kind, lr.tanggal_mulai, lr.tanggal_selesai,
           lr.jumlah_hari, lr.alasan, lr.lampiran_url, lr.status, lr.created_at
      FROM leave_requests lr
     ORDER BY (lr.status = 'menunggu') DESC, lr.created_at DESC
     LIMIT 100;
END $$;

-- 11. STATUS ABSEN HARI INI ---------------------------------------------------
CREATE OR REPLACE FUNCTION my_today_attendance()
RETURNS TABLE (
    sudah_masuk BOOLEAN, sudah_pulang BOOLEAN,
    check_in_time TIMESTAMPTZ, check_out_time TIMESTAMPTZ,
    status attend_status, terlambat_menit INT, menit_kerja INT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN
        RETURN QUERY SELECT false, false, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ,
                            NULL::attend_status, 0, NULL::INT;
        RETURN;
    END IF;
    RETURN QUERY
    SELECT true, (a.check_out_time IS NOT NULL),
           a.check_in_time, a.check_out_time, a.status, a.terlambat_menit, a.menit_kerja
      FROM attendances a
     WHERE a.capster_id = v_id AND a.business_date = jakarta_today();
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, false, NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ,
                            NULL::attend_status, 0, NULL::INT;
    END IF;
END $$;

-- 12. RLS & HAK EKSEKUSI ------------------------------------------------------
ALTER TABLE work_rules     ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_all ON work_rules;
CREATE POLICY owner_all ON work_rules
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
-- Karyawan perlu tahu jam masuk dan radius agar tahu apa yang diharapkan
DROP POLICY IF EXISTS read_work_rules ON work_rules;
CREATE POLICY read_work_rules ON work_rules FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS owner_all ON leave_requests;
CREATE POLICY owner_all ON leave_requests
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
-- Karyawan tidak membaca tabel ini langsung; my_leaves() menyaring per akun,
-- sehingga tidak ada jalan melihat pengajuan rekan kerja.

DROP POLICY IF EXISTS owner_all ON attendances;
CREATE POLICY owner_all ON attendances
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());

GRANT EXECUTE ON FUNCTION clock_in(TEXT,NUMERIC,NUMERIC)   TO authenticated;
GRANT EXECUTE ON FUNCTION clock_out(TEXT,NUMERIC,NUMERIC)  TO authenticated;
GRANT EXECUTE ON FUNCTION my_attendance(date)              TO authenticated;
GRANT EXECUTE ON FUNCTION my_today_attendance()            TO authenticated;
GRANT EXECUTE ON FUNCTION request_leave(TEXT,date,date,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION my_leaves()                      TO authenticated;
GRANT EXECUTE ON FUNCTION decide_leave(UUID,BOOLEAN,TEXT)  TO authenticated;
GRANT EXECUTE ON FUNCTION attendance_report(date)          TO authenticated;
GRANT EXECUTE ON FUNCTION pending_leaves()                 TO authenticated;

REVOKE EXECUTE ON FUNCTION clock_in(TEXT,NUMERIC,NUMERIC)  FROM anon;
REVOKE EXECUTE ON FUNCTION attendance_report(date)         FROM anon;
REVOKE EXECUTE ON FUNCTION pending_leaves()                FROM anon;
