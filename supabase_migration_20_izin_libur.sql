-- ==============================================================================
-- MIGRASI 20 — Jenis Pengajuan Menjadi Izin dan Libur
--
-- PERMINTAAN KLIEN
--   Hanya dua jenis: Izin dan Libur. Cuti Tahunan tidak dipakai dulu.
--   Ditambah satu kolom keterangan yang benar-benar terlihat saat mengajukan.
--
-- KOLOM KETERANGANNYA SEBENARNYA SUDAH ADA
--
-- leave_requests.alasan sudah ada sejak migrasi 09. Yang tidak ada adalah
-- tempat yang layak untuk mengisinya: antarmuka lama memakai empat dialog
-- prompt() beruntun, dan keterangan adalah dialog keempat — sesudah tiga
-- dialog lain. Di ponsel dialog itu praktis tidak pernah sampai terlihat.
-- Perbaikan utamanya karena itu ada di capster.html, bukan di berkas ini.
--
-- KUOTA CUTI TAHUNAN IKUT BERHENTI
--
-- Kuota kehilangan artinya begitu jenisnya dihapus. Membiarkannya tampil
-- berarti owner melihat "sisa kuota 12 hari" untuk sesuatu yang tidak pernah
-- bisa diajukan siapa pun. Kolom work_rules.kuota_cuti_tahunan tetap ada
-- supaya bisa dinyalakan lagi tanpa migrasi baru; yang berhenti hanya
-- pemakaiannya.
--
-- ENUM DIGANTI LEWAT PENAMAAN ULANG, BUKAN DROP LANGSUNG
--
-- DROP TYPE akan gagal: my_leaves() dan pending_leaves() memakai leave_kind
-- sebagai tipe kolom hasilnya, dan DROP ... CASCADE akan ikut menghapus kedua
-- fungsi itu tanpa menggantinya. Jadi tipenya dinamai ulang lebih dulu, kedua
-- fungsi dibuang dengan sengaja, kolomnya dipindah, lalu keduanya dibangun
-- kembali persis seperti definisi yang hidup sekarang.
-- ==============================================================================

-- Berhenti bila ternyata sudah ada pengajuan tersimpan: mengganti enum akan
-- menghapus artinya. Lebih baik gagal terang-terangan daripada diam-diam.
DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM leave_requests;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'Ada % pengajuan tersimpan. Tangani datanya lebih dulu.', v_n;
    END IF;
END $$;

ALTER TYPE leave_kind RENAME TO leave_kind_lama;
CREATE TYPE leave_kind AS ENUM ('Izin', 'Libur');

DROP FUNCTION IF EXISTS my_leaves();
DROP FUNCTION IF EXISTS pending_leaves();

ALTER TABLE leave_requests
    ALTER COLUMN kind TYPE leave_kind USING kind::TEXT::leave_kind;

DROP TYPE leave_kind_lama;


-- ==============================================================================
-- my_leaves — dibangun kembali persis seperti sebelumnya
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.my_leaves()
RETURNS TABLE(id uuid, kind leave_kind, tanggal_mulai date, tanggal_selesai date,
              jumlah_hari integer, alasan text, status leave_status,
              catatan_owner text, created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id UUID;
BEGIN
    SELECT c.id INTO v_id FROM capsters c WHERE c.auth_user_id = auth.uid();
    IF v_id IS NULL THEN RETURN; END IF;
    RETURN QUERY
    SELECT lr.id, lr.kind, lr.tanggal_mulai, lr.tanggal_selesai, lr.jumlah_hari,
           lr.alasan, lr.status, lr.catatan_owner, lr.created_at
      FROM leave_requests lr WHERE lr.capster_id = v_id
     ORDER BY lr.created_at DESC LIMIT 50;
END $function$;

GRANT EXECUTE ON FUNCTION my_leaves() TO authenticated, anon, service_role;


-- ==============================================================================
-- pending_leaves — dibangun kembali persis seperti sebelumnya
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.pending_leaves()
RETURNS TABLE(id uuid, capster_name character varying, kind leave_kind,
              tanggal_mulai date, tanggal_selesai date, jumlah_hari integer,
              alasan text, lampiran_url text, status leave_status,
              created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka daftar pengajuan cuti.'; END IF;
    RETURN QUERY
    SELECT lr.id, lr.capster_name, lr.kind, lr.tanggal_mulai, lr.tanggal_selesai,
           lr.jumlah_hari, lr.alasan, lr.lampiran_url, lr.status, lr.created_at
      FROM leave_requests lr
     ORDER BY (lr.status = 'menunggu') DESC, lr.created_at DESC
     LIMIT 100;
END $function$;

GRANT EXECUTE ON FUNCTION pending_leaves() TO authenticated, service_role;


-- ==============================================================================
-- request_leave — pemeriksaan kuota dilepas, keterangan dirapikan
--
-- Selain kuota, isinya sama dengan yang hidup sekarang: pemeriksaan karyawan
-- aktif, urutan tanggal, dan penolakan rentang yang bertindih tetap ada.
-- ==============================================================================
CREATE OR REPLACE FUNCTION request_leave(
    p_kind TEXT, p_mulai date, p_selesai date,
    p_alasan TEXT DEFAULT NULL, p_lampiran TEXT DEFAULT NULL
)
RETURNS TABLE (id UUID, jumlah_hari INT, sisa_kuota INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_cap  capsters%ROWTYPE;
    v_hari INT;
    v_id   UUID;
BEGIN
    SELECT * INTO v_cap FROM capsters c WHERE c.auth_user_id = auth.uid() AND c.is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Akun Anda belum ditautkan ke data karyawan aktif.'; END IF;
    IF p_selesai < p_mulai THEN RAISE EXCEPTION 'Tanggal selesai tidak boleh sebelum tanggal mulai.'; END IF;

    v_hari := (p_selesai - p_mulai) + 1;

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

    INSERT INTO leave_requests (capster_id, capster_name, kind, tanggal_mulai, tanggal_selesai,
                                jumlah_hari, alasan, lampiran_url, status)
    VALUES (v_cap.id, v_cap.name, p_kind::leave_kind, p_mulai, p_selesai,
            v_hari, NULLIF(btrim(COALESCE(p_alasan, '')), ''),
            NULLIF(btrim(COALESCE(p_lampiran, '')), ''), 'menunggu')
    RETURNING leave_requests.id INTO v_id;

    -- sisa_kuota sengaja NULL: tidak ada lagi jenis pengajuan yang memakainya.
    -- Kolomnya dipertahankan supaya tanda tangan fungsi tidak ikut berubah.
    RETURN QUERY SELECT v_id, v_hari, NULL::INT;
END $function$;

GRANT EXECUTE ON FUNCTION request_leave(TEXT, date, date, TEXT, TEXT) TO authenticated, anon, service_role;


-- ==============================================================================
-- attendance_report — hanya kolom kuota yang berubah
--
-- Disalin dari definisi yang hidup, lalu satu baris diganti. Perlu ditegaskan
-- karena mudah salah dibaca: cuti_disetujui dan cuti_menunggu adalah JUMLAH
-- PENGAJUAN (COUNT), bukan jumlah hari, dan keduanya menghitung seluruh
-- riwayat capster tanpa disaring bulan. Keduanya dibiarkan apa adanya —
-- mengubahnya di sini akan menggeser angka yang dilihat owner karena alasan
-- yang tidak ada hubungannya dengan permintaan klien.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.attendance_report(p_bulan date DEFAULT NULL::date)
RETURNS TABLE(capster_id uuid, nama character varying, hadir integer,
              terlambat integer, total_menit_kerja integer, cuti_disetujui integer,
              sisa_kuota_cuti integer, cuti_menunggu integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_awal date;
BEGIN
    IF NOT is_owner() THEN RAISE EXCEPTION 'Hanya owner yang boleh membuka rekap absensi.'; END IF;
    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;

    RETURN QUERY
    SELECT c.id, c.name,
           COALESCE(a.hadir, 0), COALESCE(a.telat, 0), COALESCE(a.menit, 0),
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
     WHERE c.is_active
     ORDER BY c.name;
END $function$;

GRANT EXECUTE ON FUNCTION attendance_report(date) TO authenticated, service_role;
