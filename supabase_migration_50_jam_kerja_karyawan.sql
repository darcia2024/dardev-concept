-- ==============================================================================
-- MIGRASI 50 - Jam kerja per karyawan
--
-- PERMINTAAN PEMILIK
--   Karyawan selain kapster bekerja 09.00 - 17.00, bukan mengikuti jam buka
--   toko (10.00 - 21.00, Jumat 13.00 - 21.00).
--
-- KEADAAN SEBELUMNYA
--
-- Migrasi 18 sengaja menyatukan jam masuk karyawan dengan jam buka toko:
-- "jam buka toko dan jam masuk karyawan pada dasarnya adalah hal yang sama".
-- Untuk kapster itu benar, dan penyatuannya mencegah laporan menuduh orang
-- terlambat tiga jam setiap Jumat. Sejak migrasi 48, tabel capsters juga
-- memuat admin dan tim sosial media, dan untuk mereka anggapan itu tidak lagi
-- berlaku.
--
-- Akibat bila dibiarkan: clock_in() mengukur keterlambatan dari jam buka toko.
-- Karyawan 09.00 yang datang 10.10 tercatat TEPAT WAKTU, sebab acuannya 10.00
-- dengan toleransi 15 menit. Hari Jumat lebih parah — acuannya 13.00, jadi ia
-- boleh datang tengah hari tanpa pernah tercatat terlambat. Laporan absensi
-- bulanan lalu menyatakan disiplin yang tidak pernah terjadi.
--
-- RANCANGANNYA
--
-- Jam kerja disimpan PER KARYAWAN, bukan per jabatan. Kosong berarti tetap
-- mengikuti jadwal toko hari itu, persis seperti sebelumnya — sehingga tidak
-- satu pun kapster berubah perilakunya karena migrasi ini. Per karyawan
-- dipilih ketimbang per jabatan karena jabatan di sini teks bebas: dua orang
-- dengan jabatan "Admin" yang masuk jam berbeda tidak boleh memaksa pemilik
-- membuat dua jabatan palsu.
--
-- Jam yang diisi berlaku SETIAP HARI, termasuk Jumat. Karyawan 09.00 - 17.00
-- tidak ikut bergeser ke 13.00 saat toko buka lebih siang; justru itulah
-- alasan jamnya dipisahkan.
--
-- YANG TIDAK BERUBAH
--
--   * Toleransi keterlambatan tetap satu untuk semua (work_rules).
--   * jam_pulang dicatat dan ditampilkan, tetapi tidak menilai apa pun —
--     sama seperti untuk kapster sejak awal. Tidak ada "pulang cepat" di
--     sistem ini, dan menambahkannya adalah keputusan tersendiri.
--   * Hari libur tetap mengikuti hari libur toko. Karyawan dengan hari kerja
--     berbeda dari toko belum dapat dinyatakan di sini.
--   * Absensi yang sudah tercatat tidak dihitung ulang. Saat migrasi ini
--     ditulis, karyawan non-kapster belum pernah absen.
-- ==============================================================================


-- ── 01 Kolom ───────────────────────────────────────────────────────────────
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS jam_masuk  TIME;
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS jam_pulang TIME;

-- Keduanya diisi atau keduanya kosong. Jam masuk tanpa jam pulang menghasilkan
-- karyawan yang separuh ikut toko dan separuh tidak, dan layar tidak punya
-- cara jujur untuk menampilkannya.
ALTER TABLE capsters DROP CONSTRAINT IF EXISTS capsters_jam_kerja_utuh;
ALTER TABLE capsters ADD CONSTRAINT capsters_jam_kerja_utuh CHECK (
    (jam_masuk IS NULL AND jam_pulang IS NULL)
    OR (jam_masuk IS NOT NULL AND jam_pulang IS NOT NULL AND jam_pulang > jam_masuk)
);

COMMENT ON COLUMN capsters.jam_masuk IS
  'Jam masuk khusus karyawan ini, berlaku tiap hari. NULL = ikut jadwal toko '
  'hari itu (jam_operasional). Dipakai clock_in() untuk menilai keterlambatan.';
COMMENT ON COLUMN capsters.jam_pulang IS
  'Jam pulang khusus karyawan ini. Dicatat dan ditampilkan; tidak menilai apa pun.';


-- ── 02 Satu sumber jam masuk ───────────────────────────────────────────────
-- Satu fungsi yang menjawab "jam berapa orang ini seharusnya masuk pada
-- tanggal itu". Bila suatu hari laporan atau layar lain perlu jawaban yang
-- sama, ia memanggil ini — bukan menulis ulang urutan cadangannya dan
-- perlahan menyimpang dari yang dipakai clock_in().
CREATE OR REPLACE FUNCTION jam_masuk_karyawan(p_capster_id UUID, p_tanggal DATE)
RETURNS TIME
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT COALESCE(
        (SELECT c.jam_masuk FROM capsters c WHERE c.id = p_capster_id),
        (SELECT jh.buka FROM jam_hari_ini(p_tanggal) jh),
        (SELECT wr.jam_masuk FROM work_rules wr WHERE wr.id)
    )
$function$;

REVOKE EXECUTE ON FUNCTION jam_masuk_karyawan(UUID, DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION jam_masuk_karyawan(UUID, DATE) TO authenticated;


-- ── 03 clock_in menilai dari jam orangnya sendiri ──────────────────────────
-- Disalin utuh dari migrasi 18. Yang berubah hanya satu: asal v_masuk.
CREATE OR REPLACE FUNCTION clock_in(
    p_selfie_url TEXT,
    p_lat NUMERIC DEFAULT NULL,
    p_lng NUMERIC DEFAULT NULL
)
RETURNS TABLE (
    waktu TIMESTAMPTZ, status attend_status, terlambat_menit INT, jarak_m INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
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

    -- Jam masuk milik ORANG INI pada hari ini: jamnya sendiri bila diisi,
    -- selain itu jadwal toko hari itu (migrasi 18), selain itu work_rules.
    v_masuk := jam_masuk_karyawan(v_cap.id, v_date);

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
END $function$;

GRANT EXECUTE ON FUNCTION clock_in(TEXT, NUMERIC, NUMERIC) TO authenticated;


-- ── 04 Penyunting karyawan ikut mengenal jam kerja ─────────────────────────
-- Tanda tangannya berubah, jadi versi enam parameter DIBUANG lebih dulu.
-- Membiarkannya berdampingan dengan versi baru membuat PostgREST tidak dapat
-- memilih di antara keduanya dan setiap simpan gagal.
--
-- Dua parameter baru diberi DEFAULT NULL. NULL berarti "ikut jadwal toko" —
-- bukan "biarkan apa adanya" — sebab formulir selalu mengirim keduanya, dan
-- mengosongkan kolom jam di formulir memang dimaksudkan untuk kembali ikut
-- jadwal toko.
DROP FUNCTION IF EXISTS owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION owner_upsert_karyawan(
    p_id         UUID,
    p_nama       TEXT,
    p_telepon    TEXT,
    p_jabatan    TEXT,
    p_ikut_pos   BOOLEAN,
    p_aktif      BOOLEAN,
    p_jam_masuk  TIME DEFAULT NULL,
    p_jam_pulang TIME DEFAULT NULL
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

    RETURN QUERY
    SELECT c.id, c.name, c.jabatan, c.phone, c.ikut_pos, c.is_active, c.jam_masuk, c.jam_pulang
      FROM capsters c WHERE c.id = v_id;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TIME, TIME) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN, TIME, TIME) TO authenticated;


-- ── 05 Daftar staf membawa jam kerjanya ────────────────────────────────────
DROP FUNCTION IF EXISTS owner_staff_list();

CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (capster_id UUID, name CHARACTER VARYING, email TEXT,
               is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING,
               jabatan CHARACTER VARYING, ikut_pos BOOLEAN,
               jml_absen BIGINT, jam_masuk TIME, jam_pulang TIME)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $function$
    SELECT c.id, c.name, u.email::TEXT, c.is_active, (c.auth_user_id IS NOT NULL),
           c.phone, c.jabatan, c.ikut_pos,
           (SELECT count(*) FROM attendances a WHERE a.capster_id = c.id),
           c.jam_masuk, c.jam_pulang
      FROM capsters c
      LEFT JOIN auth.users u ON u.id = c.auth_user_id
     WHERE is_owner()
     ORDER BY c.ikut_pos DESC, c.name;
$function$;

REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_staff_list() TO authenticated;
