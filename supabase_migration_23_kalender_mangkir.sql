-- ==============================================================================
-- MIGRASI 23 — Kalender Tim dan Hitungan Tidak Masuk
--
-- APA YANG BELUM ADA
--
-- Penawaran menjanjikan "total hadir, terlambat, dan tidak masuk per karyawan"
-- serta kalender bulanan yang memperlihatkan siapa cuti kapan. Yang terbangun
-- baru dua yang pertama: sistem mencatat siapa DATANG, tetapi tidak pernah
-- menghitung siapa TIDAK datang.
--
-- KENAPA MANGKIR TIDAK BISA DIHITUNG DARI TABEL ABSENSI SAJA
--
-- Tidak adanya baris absensi bukan berarti mangkir. Bisa jadi toko memang
-- tutup hari itu, atau karyawannya mengajukan izin dan disetujui, atau
-- harinya belum lewat. Mangkir hanya bisa disimpulkan dengan menyilangkan
-- tiga sumber: jam_operasional untuk hari buka, leave_requests untuk izin
-- yang disetujui, dan attendances untuk kehadiran.
--
-- HARI INI SENGAJA TIDAK DIHITUNG
--
-- Selama hari masih berjalan, orang yang belum absen belum tentu mangkir —
-- ia bisa datang satu jam lagi. Menyebutnya mangkir berarti menuduh sesuatu
-- yang belum terjadi, dan tuduhan itu muncul di layar owner setiap pagi.
-- Karena itu perhitungan berhenti di hari kemarin.
--
-- SEBELUM KARYAWAN ADA JUGA TIDAK DIHITUNG
--
-- capsters.created_at dipakai sebagai batas awal. Tanpa itu, karyawan yang
-- masuk pertengahan bulan langsung tercatat mangkir sepanjang paruh pertama
-- bulan tersebut — kesalahan yang paling terasa justru pada karyawan baru,
-- yang paling tidak bisa membela diri.
-- ==============================================================================


-- ==============================================================================
-- attendance_calendar — satu baris per karyawan per hari
--
-- Nilai status:
--   tutup     toko libur pada hari itu
--   hadir     absen tepat waktu
--   terlambat absen melewati toleransi
--   Izin      pengajuan izin yang disetujui
--   Libur     pengajuan libur yang disetujui
--   mangkir   toko buka, tidak ada absen, tidak ada izin
--   belum     hari ini atau sesudahnya, atau sebelum karyawan terdaftar
-- ==============================================================================
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

GRANT EXECUTE ON FUNCTION attendance_calendar(date) TO authenticated;


-- ==============================================================================
-- attendance_report — kolom tidak_masuk ditambahkan
--
-- Tipe kembalian berubah, sehingga fungsinya harus dibuang dulu: CREATE OR
-- REPLACE tidak dapat mengganti bentuk tabel hasil. Sisa isinya disalin apa
-- adanya dari definisi yang hidup — cuti_disetujui dan cuti_menunggu tetap
-- JUMLAH PENGAJUAN, bukan jumlah hari, dan tetap menghitung seluruh riwayat
-- tanpa disaring bulan. Keduanya dibiarkan supaya angka yang sudah dilihat
-- owner tidak bergeser karena alasan yang tidak ada hubungannya.
-- ==============================================================================
DROP FUNCTION IF EXISTS attendance_report(date);

CREATE OR REPLACE FUNCTION attendance_report(p_bulan date DEFAULT NULL::date)
RETURNS TABLE (
    capster_id uuid, nama character varying,
    hadir integer, terlambat integer, tidak_masuk integer,
    total_menit_kerja integer, cuti_disetujui integer,
    sisa_kuota_cuti integer, cuti_menunggu integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_awal date;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka rekap absensi.'; END IF;
    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;

    RETURN QUERY
    SELECT c.id, c.name,
           COALESCE(a.hadir, 0), COALESCE(a.telat, 0),
           COALESCE(k.mangkir, 0),
           COALESCE(a.menit, 0),
           COALESCE(l.setuju, 0),
           NULL::INT,                      -- kuota cuti tahunan tidak dipakai lagi
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
                   COUNT(*) FILTER (WHERE lr.status = 'menunggu')::INT AS tunggu
              FROM leave_requests lr WHERE lr.capster_id = c.id
      ) l ON true
      -- Mangkir dihitung dari kalender yang sama, supaya kedua layar tidak
      -- bisa saling bertentangan bila salah satu rumusnya kelak diubah.
      LEFT JOIN LATERAL (
            SELECT COUNT(*)::INT AS mangkir
              FROM attendance_calendar(v_awal) kal
             WHERE kal.capster_id = c.id AND kal.status = 'mangkir'
      ) k ON true
     WHERE c.is_active
     ORDER BY c.name;
END $function$;

GRANT EXECUTE ON FUNCTION attendance_report(date) TO authenticated, service_role;
