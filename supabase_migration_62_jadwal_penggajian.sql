-- Jadwal mingguan dan data penggajian. Jalankan setelah migrasi 61.
-- Gaji/rekening dipisahkan dari capsters yang juga dibaca perangkat kasir.
BEGIN;

CREATE OR REPLACE FUNCTION valid_working_days(p_days INTEGER[])
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path = public AS $function$
  SELECT p_days IS NOT NULL AND cardinality(p_days) BETWEEN 1 AND 7
    AND array_ndims(p_days) = 1
    AND NOT EXISTS (SELECT 1 FROM unnest(p_days) d WHERE d IS NULL OR d NOT BETWEEN 1 AND 7)
    AND cardinality(p_days) = (SELECT count(DISTINCT d) FROM unnest(p_days) d)
$function$;
REVOKE EXECUTE ON FUNCTION valid_working_days(INTEGER[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION valid_working_days(INTEGER[]) TO authenticated;

ALTER TABLE capsters ADD COLUMN IF NOT EXISTS working_days INTEGER[] NOT NULL DEFAULT ARRAY[1,2,3,4,5,6,7];
ALTER TABLE capsters DROP CONSTRAINT IF EXISTS capsters_working_days_valid;
ALTER TABLE capsters ADD CONSTRAINT capsters_working_days_valid CHECK (valid_working_days(working_days));
COMMENT ON COLUMN capsters.working_days IS 'ISO weekday: 1 Senin sampai 7 Minggu. Default tujuh hari mempertahankan jadwal lama.';

CREATE TABLE IF NOT EXISTS employee_payroll (
  capster_id UUID PRIMARY KEY REFERENCES capsters(id) ON DELETE RESTRICT,
  base_salary NUMERIC NOT NULL DEFAULT 0 CHECK (base_salary >= 0 AND base_salary <= 1000000000000 AND base_salary = trunc(base_salary)),
  bank_name TEXT NOT NULL DEFAULT '',
  bank_account_number TEXT NOT NULL DEFAULT '',
  bank_account_holder TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_payroll_bank_complete CHECK (
    (bank_name = '' AND bank_account_number = '' AND bank_account_holder = '') OR
    (length(bank_name) BETWEEN 1 AND 60 AND bank_account_number ~ '^[0-9]{5,34}$'
      AND length(btrim(bank_account_holder)) BETWEEN 1 AND 150)
  )
);
ALTER TABLE employee_payroll ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON employee_payroll FROM PUBLIC, anon, authenticated;
GRANT SELECT ON employee_payroll TO authenticated;
DROP POLICY IF EXISTS payroll_owner_read ON employee_payroll;
CREATE POLICY payroll_owner_read ON employee_payroll FOR SELECT TO authenticated USING (is_owner());

-- Satu patch untuk kartu maupun form Ubah. NULL/tidak dikirim = tidak diubah.
-- Ketiga kolom bank harus diisi/dikosongkan bersama, nomor disimpan sebagai teks.
CREATE OR REPLACE FUNCTION owner_set_employee_payroll(p_id UUID, p_patch JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_days INTEGER[]; v_salary NUMERIC; v_bank TEXT; v_number TEXT; v_holder TEXT;
BEGIN
  IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mengelola penggajian.'; END IF;
  IF p_patch IS NULL OR jsonb_typeof(p_patch) <> 'object' THEN RAISE EXCEPTION 'Data penggajian tidak valid.'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_patch) k WHERE k NOT IN
    ('working_days','base_salary','bank_name','bank_account_number','bank_account_holder')) THEN
    RAISE EXCEPTION 'Kolom penggajian tidak dikenali.';
  END IF;
  PERFORM 1 FROM capsters WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Karyawan tidak ditemukan.'; END IF;
  IF p_patch ? 'working_days' THEN
    IF jsonb_typeof(p_patch->'working_days') <> 'array' THEN RAISE EXCEPTION 'Pilih hari kerja.'; END IF;
    SELECT array_agg(d::INTEGER ORDER BY d::INTEGER) INTO v_days FROM jsonb_array_elements_text(p_patch->'working_days') d;
    IF NOT valid_working_days(v_days) THEN RAISE EXCEPTION 'Pilih minimal satu hari kerja tanpa duplikasi.'; END IF;
    UPDATE capsters SET working_days = v_days WHERE id = p_id;
  END IF;
  INSERT INTO employee_payroll(capster_id) VALUES(p_id) ON CONFLICT DO NOTHING;
  SELECT base_salary, bank_name, bank_account_number, bank_account_holder
    INTO v_salary, v_bank, v_number, v_holder FROM employee_payroll WHERE capster_id = p_id;
  IF p_patch ? 'base_salary' THEN
    IF jsonb_typeof(p_patch->'base_salary') <> 'number' THEN RAISE EXCEPTION 'Gaji pokok harus berupa angka rupiah.'; END IF;
    v_salary := (p_patch->>'base_salary')::NUMERIC;
    IF v_salary IS NULL OR v_salary < 0 OR v_salary > 1000000000000 OR v_salary <> trunc(v_salary) THEN
      RAISE EXCEPTION 'Gaji pokok harus rupiah utuh, minimal nol.';
    END IF;
  END IF;
  IF p_patch ?| ARRAY['bank_name','bank_account_number','bank_account_holder'] THEN
    IF NOT (p_patch ?& ARRAY['bank_name','bank_account_number','bank_account_holder'])
      OR jsonb_typeof(p_patch->'bank_name') <> 'string'
      OR jsonb_typeof(p_patch->'bank_account_number') <> 'string'
      OR jsonb_typeof(p_patch->'bank_account_holder') <> 'string' THEN
      RAISE EXCEPTION 'Isi nama bank, nomor rekening, dan atas nama sekaligus.';
    END IF;
    v_bank := btrim(p_patch->>'bank_name');
    v_number := btrim(p_patch->>'bank_account_number');
    v_holder := btrim(p_patch->>'bank_account_holder');
    IF lower(v_bank) IN ('mandiri', 'bank mandiri') THEN v_bank := 'Mandiri'; END IF;
    IF NOT ((v_bank = '' AND v_number = '' AND v_holder = '') OR
      (length(v_bank) BETWEEN 1 AND 60 AND v_number ~ '^[0-9]{5,34}$' AND length(v_holder) BETWEEN 1 AND 150)) THEN
      RAISE EXCEPTION 'Lengkapi rekening bank. Nomor rekening harus 5–34 digit.';
    END IF;
  END IF;
  UPDATE employee_payroll SET base_salary = v_salary, bank_name = v_bank,
    bank_account_number = v_number, bank_account_holder = v_holder, updated_at = now() WHERE capster_id = p_id;
END $function$;
REVOKE EXECUTE ON FUNCTION owner_set_employee_payroll(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owner_set_employee_payroll(UUID, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN);

DROP FUNCTION IF EXISTS owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TIME, TIME);

CREATE OR REPLACE FUNCTION owner_upsert_karyawan(
    p_id         UUID,
    p_nama       TEXT,
    p_telepon    TEXT,
    p_jabatan    TEXT,
    p_ikut_pos   BOOLEAN,
    p_aktif      BOOLEAN,
    p_jam_masuk  TIME DEFAULT NULL,
    p_jam_pulang TIME DEFAULT NULL,
    p_payroll JSONB DEFAULT NULL
)
RETURNS TABLE (karyawan_id UUID, nama CHARACTER VARYING, jabatan CHARACTER VARYING,
               telepon CHARACTER VARYING, ikut_pos BOOLEAN, is_active BOOLEAN,
               jam_masuk TIME, jam_pulang TIME)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_nama    TEXT;
    v_jabatan TEXT;
    v_nomor   TEXT;
    v_id      UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola data karyawan.';
    END IF;

    v_nama := btrim(COALESCE(p_nama, ''));
    IF v_nama = '' THEN
        RAISE EXCEPTION 'Nama karyawan wajib diisi.';
    END IF;
    IF length(v_nama) > 150 THEN
        RAISE EXCEPTION 'Nama karyawan terlalu panjang.';
    END IF;

    v_jabatan := btrim(COALESCE(p_jabatan, ''));
    IF v_jabatan = '' THEN v_jabatan := 'Kapster'; END IF;
    IF length(v_jabatan) > 40 THEN
        RAISE EXCEPTION 'Jabatan terlalu panjang.';
    END IF;

    IF btrim(COALESCE(p_telepon, '')) = '' THEN
        v_nomor := NULL;
    ELSE
        v_nomor := normalkan_nomor_wa(p_telepon);
        IF v_nomor IS NULL THEN
            RAISE EXCEPTION 'Nomor tidak dikenali. Contoh yang benar: 081297754581.';
        END IF;
    END IF;

    -- Diperiksa di sini dengan kalimat yang dapat dibaca owner. Constraint
    -- capsters_jam_kerja_utuh tetap menjaganya, tetapi galat constraint
    -- berbunyi seperti kerusakan, bukan seperti salah isi.
    IF (p_jam_masuk IS NULL) <> (p_jam_pulang IS NULL) THEN
        RAISE EXCEPTION 'Isi jam masuk dan jam pulang sekaligus, atau kosongkan keduanya untuk ikut jam toko.';
    END IF;
    IF p_jam_masuk IS NOT NULL AND p_jam_pulang <= p_jam_masuk THEN
        RAISE EXCEPTION 'Jam pulang harus setelah jam masuk.';
    END IF;

    IF EXISTS (SELECT 1 FROM capsters c
                WHERE lower(c.name) = lower(v_nama)
                  AND (p_id IS NULL OR c.id <> p_id)) THEN
        RAISE EXCEPTION 'Sudah ada karyawan bernama %.', v_nama;
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO capsters (name, phone, jabatan, ikut_pos, is_active, jam_masuk, jam_pulang)
        VALUES (v_nama, v_nomor, v_jabatan,
                COALESCE(p_ikut_pos, TRUE), COALESCE(p_aktif, TRUE),
                p_jam_masuk, p_jam_pulang)
        RETURNING capsters.id INTO v_id;
    ELSE
        UPDATE capsters c SET
            name       = v_nama,
            phone      = v_nomor,
            jabatan    = v_jabatan,
            ikut_pos   = COALESCE(p_ikut_pos, c.ikut_pos),
            is_active  = COALESCE(p_aktif, c.is_active),
            jam_masuk  = p_jam_masuk,
            jam_pulang = p_jam_pulang
        WHERE c.id = p_id
        RETURNING c.id INTO v_id;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Karyawan tidak ditemukan.';
        END IF;
    END IF;

    IF p_payroll IS NOT NULL THEN
        PERFORM owner_set_employee_payroll(v_id, p_payroll);
    END IF;

    RETURN QUERY
    SELECT c.id, c.name, c.jabatan, c.phone, c.ikut_pos, c.is_active, c.jam_masuk, c.jam_pulang
      FROM capsters c WHERE c.id = v_id;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TIME, TIME, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TIME, TIME, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS owner_staff_list();
CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (capster_id UUID, name CHARACTER VARYING, email TEXT,
  is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING,
  jabatan CHARACTER VARYING, ikut_pos BOOLEAN, jml_absen BIGINT,
  jam_masuk TIME, jam_pulang TIME, foto_path TEXT, working_days INTEGER[],
  base_salary NUMERIC, bank_name TEXT, bank_account_number TEXT, bank_account_holder TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $function$
  SELECT c.id, c.name, u.email::TEXT, c.is_active, c.auth_user_id IS NOT NULL,
    c.phone, c.jabatan, c.ikut_pos, (SELECT count(*) FROM attendances a WHERE a.capster_id = c.id),
    c.jam_masuk, c.jam_pulang, c.foto_path, c.working_days,
    COALESCE(p.base_salary,0), COALESCE(p.bank_name,''), COALESCE(p.bank_account_number,''), COALESCE(p.bank_account_holder,'')
  FROM capsters c LEFT JOIN auth.users u ON u.id = c.auth_user_id
  LEFT JOIN employee_payroll p ON p.capster_id = c.id
  WHERE is_owner() ORDER BY c.ikut_pos DESC, c.name
$function$;
REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owner_staff_list() TO authenticated;

CREATE OR REPLACE FUNCTION attendance_calendar(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    capster_id UUID,
    nama       VARCHAR,
    tanggal    date,
    status     TEXT,
    menit_telat INT,
    catatan    TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_awal date; v_akhir date; v_hariIni date;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuka kalender tim.';
    END IF;

    v_awal    := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    v_akhir   := (v_awal + interval '1 month' - interval '1 day')::date;
    v_hariIni := jakarta_today();

    RETURN QUERY
    SELECT c.id,
           c.name,
           d.hari::date,
           CASE
             WHEN NOT (EXTRACT(ISODOW FROM d.hari)::INTEGER = ANY(c.working_days)) THEN 'off'
             WHEN COALESCE(j.libur, false)              THEN 'tutup'
             WHEN a.status IS NOT NULL                  THEN a.status::TEXT
             WHEN lr.kind IS NOT NULL                   THEN lr.kind::TEXT
             WHEN d.hari::date >= v_hariIni             THEN 'belum'
             -- Hari pendaftaran itu sendiri ikut dikecualikan, bukan hanya
             -- hari sebelumnya. Karyawan yang datanya dibuat pukul 13.33 tidak
             -- mungkin sudah absen pukul 10.00 di hari yang sama; menghitungnya
             -- mangkir berarti menuduh orang pada hari ia baru didaftarkan.
             WHEN d.hari::date <= (c.created_at AT TIME ZONE 'Asia/Jakarta')::date THEN 'belum'
             ELSE 'mangkir'
           END,
           COALESCE(a.terlambat_menit, 0),
           CASE
             WHEN a.status IS NOT NULL AND a.check_in_time IS NOT NULL
               THEN to_char(a.check_in_time AT TIME ZONE 'Asia/Jakarta', 'HH24:MI')
             WHEN lr.kind IS NOT NULL THEN COALESCE(lr.alasan, '')
             ELSE ''
           END
      FROM capsters c
      CROSS JOIN generate_series(v_awal, v_akhir, interval '1 day') AS d(hari)
      LEFT JOIN jam_operasional j
             ON j.dow = EXTRACT(DOW FROM d.hari)::SMALLINT
      LEFT JOIN attendances a
             ON a.capster_id = c.id AND a.business_date = d.hari::date
      LEFT JOIN LATERAL (
            SELECT x.kind, x.alasan
              FROM leave_requests x
             WHERE x.capster_id = c.id
               AND x.status = 'disetujui'
               AND x.tanggal_mulai <= d.hari::date
               AND x.tanggal_selesai >= d.hari::date
             LIMIT 1
      ) lr ON true
     WHERE c.is_active
     ORDER BY c.name, d.hari;
END $function$;

REVOKE EXECUTE ON FUNCTION attendance_calendar(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION attendance_calendar(date) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
