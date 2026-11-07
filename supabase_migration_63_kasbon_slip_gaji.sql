-- Kasbon bulanan, keputusan owner, pencatatan pencairan, dan sumber slip gaji.
-- Jalankan setelah migrasi 62. Tidak melakukan transfer uang ke bank.
BEGIN;

CREATE TABLE IF NOT EXISTS cash_advances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  capster_id UUID NOT NULL REFERENCES capsters(id) ON DELETE RESTRICT,
  request_key UUID NOT NULL,
  period DATE NOT NULL CHECK (period = date_trunc('month', period)::DATE),
  amount NUMERIC NOT NULL CHECK (amount > 0 AND amount <= 1000000000000 AND amount = trunc(amount)),
  reason TEXT NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  decided_by UUID REFERENCES auth.users(id),
  decision_note TEXT NOT NULL DEFAULT '' CHECK (length(decision_note) <= 500),
  disbursed_at TIMESTAMPTZ,
  disbursed_by UUID REFERENCES auth.users(id),
  payment_reference TEXT NOT NULL DEFAULT '' CHECK (length(payment_reference) <= 150),
  bank_snapshot JSONB,
  UNIQUE (capster_id, request_key),
  CHECK ((status = 'pending' AND decided_at IS NULL AND decided_by IS NULL) OR
         (status <> 'pending' AND decided_at IS NOT NULL AND decided_by IS NOT NULL)),
  CHECK ((disbursed_at IS NULL AND disbursed_by IS NULL) OR
         (status = 'approved' AND disbursed_at IS NOT NULL AND disbursed_by IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS cash_advances_employee_period ON cash_advances(capster_id, period, status);
CREATE INDEX IF NOT EXISTS cash_advances_disbursed ON cash_advances(capster_id, disbursed_at) WHERE disbursed_at IS NOT NULL;
ALTER TABLE cash_advances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON cash_advances FROM PUBLIC, anon, authenticated;
GRANT SELECT ON cash_advances TO authenticated;
DROP POLICY IF EXISTS cash_advances_read ON cash_advances;
CREATE POLICY cash_advances_read ON cash_advances FOR SELECT TO authenticated USING (
  is_owner() OR EXISTS (SELECT 1 FROM capsters c WHERE c.id = capster_id AND c.auth_user_id = auth.uid() AND c.is_active)
);

-- Helper internal: tidak dapat dipanggil lewat API untuk membaca gaji orang lain.
CREATE OR REPLACE FUNCTION cash_advance_summary(p_id UUID, p_month DATE)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_month DATE := date_trunc('month',p_month)::DATE;
  v_salary NUMERIC; v_days INTEGER[]; v_required INT; v_attended INT;
  v_approved NUMERIC; v_pending NUMERIC; v_limit NUMERIC; v_daily NUMERIC;
BEGIN
  SELECT c.working_days, COALESCE(p.base_salary,0) INTO v_days,v_salary
    FROM capsters c LEFT JOIN employee_payroll p ON p.capster_id=c.id WHERE c.id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Karyawan tidak ditemukan.'; END IF;
  SELECT count(*)::INT INTO v_required
    FROM generate_series(v_month::TIMESTAMP, (v_month + interval '1 month - 1 day')::TIMESTAMP, interval '1 day') d
    WHERE EXTRACT(ISODOW FROM d)::INTEGER = ANY(v_days);
  SELECT count(DISTINCT a.business_date)::INT INTO v_attended FROM attendances a
    WHERE a.capster_id=p_id AND a.business_date >= v_month AND a.business_date < v_month + interval '1 month'
      AND a.business_date <= jakarta_today() AND a.check_in_time IS NOT NULL
      AND a.status::TEXT IN ('hadir','terlambat');
  SELECT COALESCE(sum(amount) FILTER (WHERE status='approved'),0),
         COALESCE(sum(amount) FILTER (WHERE status='pending'),0)
    INTO v_approved,v_pending FROM cash_advances WHERE capster_id=p_id AND period=v_month;
  v_daily := CASE WHEN v_required > 0 THEN v_salary / v_required ELSE 0 END;
  -- Jangan bulatkan gaji per hari sebelum menghitung limit.
  v_limit := CASE WHEN v_required > 0 THEN floor(v_salary * v_attended * 0.30 / v_required) ELSE 0 END;
  RETURN jsonb_build_object('period',to_char(v_month,'YYYY-MM'), 'base_salary',v_salary,
    'total_hari_kerja_wajib',v_required, 'gaji_per_hari',v_daily,
    'jumlah_hari_masuk',v_attended,'gaji_prorata_terkumpul',v_attended*v_daily,
    'limit_kasbon_30_persen',v_limit,'total_kasbon_disetujui',v_approved,
    'total_kasbon_pending',v_pending,'sisa_limit_kasbon_tersedia',v_limit-v_approved-v_pending);
END $function$;
REVOKE EXECUTE ON FUNCTION cash_advance_summary(UUID,DATE) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION my_cash_advances()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_id UUID; v_month DATE := date_trunc('month',jakarta_today())::DATE;
BEGIN
  SELECT id INTO v_id FROM capsters WHERE auth_user_id=auth.uid() AND is_active;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke karyawan aktif.'; END IF;
  RETURN jsonb_build_object('summary',cash_advance_summary(v_id,v_month), 'requests',COALESCE((
    SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (
      SELECT id,amount,reason,status,created_at,decision_note,disbursed_at FROM cash_advances
       WHERE capster_id=v_id AND period=v_month
    ) r), '[]'::JSONB));
END $function$;
REVOKE EXECUTE ON FUNCTION my_cash_advances() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION my_cash_advances() TO authenticated;

CREATE OR REPLACE FUNCTION request_cash_advance(p_amount NUMERIC, p_reason TEXT, p_request_key UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_id UUID; v_existing cash_advances%ROWTYPE; v_new UUID; v_summary JSONB;
  v_month DATE := date_trunc('month',jakarta_today())::DATE;
BEGIN
  -- Semua pengajuan/keputusan/pencairan karyawan ini memakai kunci yang sama.
  -- Dua perangkat tidak bisa menghabiskan sisa kuota yang sama bersamaan.
  SELECT id INTO v_id FROM capsters WHERE auth_user_id=auth.uid() AND is_active FOR UPDATE;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke karyawan aktif.'; END IF;
  IF p_request_key IS NULL THEN RAISE EXCEPTION 'Identitas pengajuan wajib tersedia.'; END IF;
  SELECT * INTO v_existing FROM cash_advances WHERE capster_id=v_id AND request_key=p_request_key;
  IF FOUND THEN
    IF v_existing.amount IS DISTINCT FROM p_amount OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
      RAISE EXCEPTION 'Pengajuan sebelumnya sudah tersimpan dengan isi berbeda. Muat ulang riwayat.';
    END IF;
    RETURN v_existing.id;
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount > 1000000000000 OR p_amount <> trunc(p_amount) THEN
    RAISE EXCEPTION 'Nominal kasbon harus rupiah utuh dan lebih dari nol.';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Isi alasan 1–500 karakter.'; END IF;
  v_summary := cash_advance_summary(v_id,v_month);
  IF p_amount > (v_summary->>'sisa_limit_kasbon_tersedia')::NUMERIC THEN
    RAISE EXCEPTION 'Nominal melebihi sisa limit kasbon bulan ini: Rp %.', greatest(0,(v_summary->>'sisa_limit_kasbon_tersedia')::NUMERIC);
  END IF;
  INSERT INTO cash_advances(capster_id,request_key,period,amount,reason)
    VALUES(v_id,p_request_key,v_month,p_amount,btrim(p_reason)) RETURNING id INTO v_new;
  RETURN v_new;
END $function$;
REVOKE EXECUTE ON FUNCTION request_cash_advance(NUMERIC,TEXT,UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION request_cash_advance(NUMERIC,TEXT,UUID) TO authenticated;

CREATE OR REPLACE FUNCTION owner_cash_advances(p_month DATE DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_month DATE := date_trunc('month',COALESCE(p_month,jakarta_today()))::DATE;
BEGIN
  IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka pengajuan kasbon.'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY (r.status='pending') DESC,r.created_at DESC) FROM (
    SELECT a.*,c.name,c.jabatan,c.is_active, cash_advance_summary(c.id,v_month) AS summary,
      COALESCE(p.bank_name,'') AS bank_name, COALESCE(p.bank_account_number,'') AS bank_account_number,
      COALESCE(p.bank_account_holder,'') AS bank_account_holder
    FROM cash_advances a JOIN capsters c ON c.id=a.capster_id
    LEFT JOIN employee_payroll p ON p.capster_id=c.id WHERE a.period=v_month
  ) r),'[]'::JSONB);
END $function$;
REVOKE EXECUTE ON FUNCTION owner_cash_advances(DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owner_cash_advances(DATE) TO authenticated;

CREATE OR REPLACE FUNCTION decide_cash_advance(p_id UUID,p_approve BOOLEAN,p_note TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_row cash_advances%ROWTYPE; v_employee UUID; v_summary JSONB; v_active BOOLEAN;
BEGIN
  IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh memutuskan kasbon.'; END IF;
  IF p_approve IS NULL OR length(COALESCE(p_note,'')) > 500 THEN RAISE EXCEPTION 'Keputusan tidak valid.'; END IF;
  SELECT capster_id INTO v_employee FROM cash_advances WHERE id=p_id;
  IF v_employee IS NULL THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan.'; END IF;
  SELECT is_active INTO v_active FROM capsters WHERE id=v_employee FOR UPDATE;
  SELECT * INTO v_row FROM cash_advances WHERE id=p_id FOR UPDATE;
  IF v_row.status <> 'pending' THEN
    IF v_row.status = (CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END) THEN RETURN; END IF;
    RAISE EXCEPTION 'Pengajuan sudah diputuskan. Muat ulang daftar.';
  END IF;
  IF p_approve THEN
    IF NOT v_active THEN RAISE EXCEPTION 'Karyawan sudah nonaktif.'; END IF;
    v_summary := cash_advance_summary(v_employee,v_row.period);
    IF (v_summary->>'sisa_limit_kasbon_tersedia')::NUMERIC < 0 THEN
      RAISE EXCEPTION 'Kuota berubah setelah koreksi absensi/gaji. Tinjau dan tolak pengajuan yang melebihi limit.';
    END IF;
  END IF;
  UPDATE cash_advances SET status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
    decision_note=btrim(COALESCE(p_note,'')),decided_at=now(),decided_by=auth.uid() WHERE id=p_id;
END $function$;
REVOKE EXECUTE ON FUNCTION decide_cash_advance(UUID,BOOLEAN,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION decide_cash_advance(UUID,BOOLEAN,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION disburse_cash_advance(p_id UUID,p_reference TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_row cash_advances%ROWTYPE; v_employee UUID;
BEGIN
  IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh mencatat pencairan kasbon.'; END IF;
  IF length(COALESCE(p_reference,'')) > 150 THEN RAISE EXCEPTION 'Referensi pembayaran maksimal 150 karakter.'; END IF;
  SELECT capster_id INTO v_employee FROM cash_advances WHERE id=p_id;
  IF v_employee IS NULL THEN RAISE EXCEPTION 'Pengajuan tidak ditemukan.'; END IF;
  PERFORM 1 FROM capsters WHERE id=v_employee FOR UPDATE;
  SELECT * INTO v_row FROM cash_advances WHERE id=p_id FOR UPDATE;
  IF v_row.status <> 'approved' THEN RAISE EXCEPTION 'Hanya kasbon disetujui yang dapat dicatat cair.'; END IF;
  IF v_row.disbursed_at IS NOT NULL THEN RETURN; END IF;
  UPDATE cash_advances SET disbursed_at=now(),disbursed_by=auth.uid(),
    payment_reference=btrim(COALESCE(p_reference,'')),bank_snapshot=(
      SELECT jsonb_build_object('bank_name',p.bank_name,'bank_account_number',p.bank_account_number,
        'bank_account_holder',p.bank_account_holder) FROM employee_payroll p WHERE p.capster_id=v_employee)
    WHERE id=p_id;
END $function$;
REVOKE EXECUTE ON FUNCTION disburse_cash_advance(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION disburse_cash_advance(UUID,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION owner_payroll_data(p_id UUID,p_month DATE)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_month DATE := date_trunc('month',p_month)::DATE; v_employee JSONB; v_attendance JSONB;
  v_leave INT; v_haircut BIGINT; v_hairwash BIGINT; v_paid NUMERIC;
BEGIN
  IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka slip gaji.'; END IF;
  IF v_month IS NULL THEN RAISE EXCEPTION 'Pilih periode slip gaji.'; END IF;
  SELECT jsonb_build_object('id',c.id,'name',c.name,'jabatan',c.jabatan,'working_days',c.working_days,
    'base_salary',COALESCE(p.base_salary,0),'bank_name',COALESCE(p.bank_name,''),
    'bank_account_number',COALESCE(p.bank_account_number,''),'bank_account_holder',COALESCE(p.bank_account_holder,''))
    INTO v_employee FROM capsters c LEFT JOIN employee_payroll p ON p.capster_id=c.id WHERE c.id=p_id;
  IF v_employee IS NULL THEN RAISE EXCEPTION 'Karyawan tidak ditemukan.'; END IF;
  SELECT jsonb_build_object('hadir',count(DISTINCT a.business_date),
    'terlambat',count(DISTINCT a.business_date) FILTER (WHERE a.status::TEXT='terlambat'),
    'menit_kerja',floor(COALESCE(sum(greatest(0,extract(epoch FROM (a.check_out_time-a.check_in_time))/60))
      FILTER (WHERE a.check_out_time IS NOT NULL),0)))
    INTO v_attendance FROM attendances a WHERE a.capster_id=p_id
      AND a.business_date >= v_month AND a.business_date < v_month + interval '1 month'
      AND a.business_date <= jakarta_today() AND a.status::TEXT IN ('hadir','terlambat');
  -- Izin melintasi batas bulan dipotong ke bulan laporan; tanggal tumpang tindih dihitung sekali.
  SELECT count(DISTINCT d)::INT INTO v_leave FROM leave_requests l
    CROSS JOIN LATERAL generate_series(greatest(l.tanggal_mulai,v_month)::TIMESTAMP,
      least(l.tanggal_selesai,(v_month+interval '1 month - 1 day')::DATE)::TIMESTAMP,interval '1 day') d
    WHERE l.capster_id=p_id AND l.status::TEXT='disetujui'
      AND l.tanggal_mulai < v_month+interval '1 month' AND l.tanggal_selesai >= v_month;
  SELECT COALESCE(sum(i.qty) FILTER (WHERE lower(btrim(i.service_name))='haircut'),0),
         COALESCE(sum(i.qty) FILTER (WHERE lower(btrim(i.service_name))='hairwash'),0)
    INTO v_haircut,v_hairwash FROM transaction_items i JOIN transactions t ON t.id=i.transaction_id
    WHERE i.capster_id=p_id AND t.business_date >= v_month AND t.business_date < v_month+interval '1 month';
  -- Koreksi pemilik: hanya kasbon CAIR menjadi potongan, pada bulan pencairannya.
  -- Kuota pengajuan tetap memakai period asal, sehingga bulan baru tidak membawa saldo kuota lama.
  SELECT COALESCE(sum(amount),0) INTO v_paid FROM cash_advances WHERE capster_id=p_id AND status='approved'
    AND disbursed_at >= (v_month::TIMESTAMP AT TIME ZONE 'Asia/Jakarta')
    AND disbursed_at < ((v_month+interval '1 month')::TIMESTAMP AT TIME ZONE 'Asia/Jakarta');
  RETURN jsonb_build_object('period',to_char(v_month,'YYYY-MM'),'employee',v_employee,
    'attendance',v_attendance,'izin_disetujui',v_leave,'haircut',v_haircut,'hairwash',v_hairwash,
    'kasbon_dicairkan',v_paid,'generated_at',now());
END $function$;
REVOKE EXECUTE ON FUNCTION owner_payroll_data(UUID,DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owner_payroll_data(UUID,DATE) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
