-- ==============================================================================
-- MIGRASI 24 — Permintaan Booking dari Halaman Depan
--
-- BENTUKNYA PERMINTAAN, BUKAN PENGUNCIAN JADWAL
--
-- Booking di sini tidak memblokir slot dan tidak menetapkan kapster. Pelanggan
-- menyebutkan kapan ia ingin datang; kasir yang memutuskan. Pilihan itu
-- disengaja: toko berjalan dengan tiga kursi dan mayoritas walk-in, dan jadwal
-- yang mengunci kursi justru bertabrakan dengan pelanggan yang datang langsung.
--
-- SATU ENDPOINT YANG BOLEH DITULIS ORANG TANPA LOGIN
--
-- create_booking adalah satu-satunya jalan masuk anonim ke basis data ini,
-- sehingga ia menjadi permukaan serangan yang paling terbuka. Tabelnya sendiri
-- tertutup rapat — tidak ada kebijakan RLS untuk anon sama sekali — dan seluruh
-- penulisan hanya lewat fungsi ini, yang memeriksa:
--
--   * bentuk nama dan nomor telepon
--   * tanggal harus di rentang hari ini sampai 30 hari ke depan
--   * hari itu toko memang buka
--   * jamnya berada di dalam jam operasional hari tersebut
--   * layanannya benar-benar ada dan masih aktif
--   * pembatasan jumlah, supaya satu nomor tidak bisa membanjiri antrean
--
-- Tanpa pembatasan terakhir, satu skrip sederhana dapat mengisi antrean kasir
-- dengan ribuan permintaan palsu dalam semenit, dan kasir kehilangan satu-satunya
-- layar yang ia butuhkan pada jam sibuk.
--
-- YANG SENGAJA TIDAK DISIMPAN
--
-- Alamat IP pengunjung tidak dicatat. Pembatasan sudah dapat dilakukan lewat
-- nomor telepon, dan menyimpan IP berarti mengumpulkan data pribadi yang tidak
-- dibutuhkan untuk menjalankan barbershop.
-- ==============================================================================

DO $$ BEGIN
    CREATE TYPE booking_status AS ENUM ('baru', 'dikonfirmasi', 'ditolak', 'selesai', 'batal');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS bookings (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kode           VARCHAR(10) UNIQUE NOT NULL,
    nama           VARCHAR(80)  NOT NULL,
    telepon        VARCHAR(20)  NOT NULL,
    service_id     UUID REFERENCES services(id),
    service_name   VARCHAR(120),
    harga          NUMERIC(12,2),
    durasi_menit   INT,
    tanggal        date NOT NULL,
    jam            time NOT NULL,
    catatan        TEXT,
    status         booking_status NOT NULL DEFAULT 'baru',
    catatan_kasir  TEXT,
    diputus_oleh   UUID,
    diputus_pada   timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS bookings_tanggal_idx ON bookings (tanggal, status);
CREATE INDEX IF NOT EXISTS bookings_telepon_idx ON bookings (telepon, created_at);

ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Sengaja hanya satu kebijakan, dan hanya untuk pembacaan oleh orang dalam.
-- Anon tidak punya kebijakan apa pun di sini: ia hanya boleh lewat RPC.
DROP POLICY IF EXISTS bookings_baca_orang_dalam ON bookings;
CREATE POLICY bookings_baca_orang_dalam ON bookings
    FOR SELECT TO authenticated
    USING (is_owner() OR is_pos_device());


-- ==============================================================================
-- public_landing — satu-satunya jalan halaman depan membaca isi toko
--
-- Tabel services, outlets, dan capsters tertutup bagi pengunjung anonim, dan
-- itu benar: daftar pelanggan dan data karyawan ada di basis data yang sama.
-- Fungsi ini membuka persis yang perlu dilihat orang di halaman depan, tidak
-- lebih — nama layanan, harga, durasi, alamat, jam, dan nomor WhatsApp toko.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public_landing()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT jsonb_build_object(
        'layanan', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', s.id, 'nama', s.name, 'kategori', s.category,
                       'harga', s.price, 'menit', s.duration_minutes)
                   ORDER BY s.price)
              FROM services s WHERE s.is_active
        ), '[]'::jsonb),
        'outlet', (
            SELECT jsonb_build_object(
                       'nama', o.name, 'alamat', o.address, 'telepon', o.phone,
                       'lat', o.latitude, 'lng', o.longitude)
              FROM outlets o WHERE o.is_active ORDER BY o.sort_order LIMIT 1
        ),
        'jam', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'dow', j.dow, 'buka', j.buka, 'tutup', j.tutup, 'libur', j.libur)
                   ORDER BY j.dow)
              FROM jam_operasional j
        ), '[]'::jsonb),
        'poin', (
            SELECT jsonb_build_object(
                       'rupiah_per_poin', ls.rupiah_per_point,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    );
$function$;

GRANT EXECUTE ON FUNCTION public_landing() TO anon, authenticated;


-- ==============================================================================
-- create_booking — satu-satunya penulisan anonim
-- ==============================================================================
CREATE OR REPLACE FUNCTION create_booking(
    p_nama TEXT, p_telepon TEXT, p_service_id UUID,
    p_tanggal date, p_jam time, p_catatan TEXT DEFAULT NULL
)
RETURNS TABLE (kode VARCHAR, tanggal date, jam time, layanan VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_nama    TEXT;
    v_telp    TEXT;
    v_srv     services%ROWTYPE;
    v_jam     jam_operasional%ROWTYPE;
    v_kode    TEXT;
    v_antre   INT;
    v_harian  INT;
    v_coba    INT := 0;
BEGIN
    v_nama := btrim(COALESCE(p_nama, ''));
    IF length(v_nama) < 2 OR length(v_nama) > 80 THEN
        RAISE EXCEPTION 'Nama harus antara 2 dan 80 huruf.';
    END IF;

    -- Nomor dinormalkan ke bentuk 62..., sama seperti seluruh sistem
    v_telp := regexp_replace(COALESCE(p_telepon, ''), '[^0-9]', '', 'g');
    IF left(v_telp, 1) = '0' THEN v_telp := '62' || substring(v_telp from 2); END IF;
    IF left(v_telp, 1) = '8' THEN v_telp := '62' || v_telp; END IF;
    IF v_telp !~ '^628[0-9]{7,13}$' THEN
        RAISE EXCEPTION 'Nomor WhatsApp tidak dikenali. Contoh: 081510474646';
    END IF;

    IF p_tanggal IS NULL OR p_tanggal < jakarta_today() THEN
        RAISE EXCEPTION 'Tanggal booking tidak boleh di masa lalu.';
    END IF;
    IF p_tanggal > jakarta_today() + 30 THEN
        RAISE EXCEPTION 'Booking hanya dapat dilakukan sampai 30 hari ke depan.';
    END IF;

    SELECT * INTO v_srv FROM services s WHERE s.id = p_service_id AND s.is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Layanan tidak ditemukan atau sudah tidak tersedia.'; END IF;

    SELECT * INTO v_jam FROM jam_operasional j
     WHERE j.dow = EXTRACT(DOW FROM p_tanggal)::SMALLINT;
    IF NOT FOUND OR v_jam.libur THEN
        RAISE EXCEPTION 'Toko tutup pada tanggal itu. Silakan pilih hari lain.';
    END IF;
    IF p_jam IS NULL OR p_jam < v_jam.buka OR p_jam > v_jam.tutup THEN
        RAISE EXCEPTION 'Pada hari itu toko buka pukul % sampai %.',
            to_char(v_jam.buka, 'HH24:MI'), to_char(v_jam.tutup, 'HH24:MI');
    END IF;

    -- Pembatasan: menahan banjir permintaan dari satu nomor
    SELECT COUNT(*) INTO v_antre FROM bookings b
     WHERE b.telepon = v_telp AND b.status = 'baru';
    IF v_antre >= 3 THEN
        RAISE EXCEPTION 'Sudah ada 3 permintaan booking yang belum dikonfirmasi dari nomor ini. Tunggu kabar dari kami dulu.';
    END IF;

    SELECT COUNT(*) INTO v_harian FROM bookings b
     WHERE b.telepon = v_telp
       AND (b.created_at AT TIME ZONE 'Asia/Jakarta')::date = jakarta_today();
    IF v_harian >= 6 THEN
        RAISE EXCEPTION 'Terlalu banyak permintaan hari ini dari nomor ini. Coba lagi besok atau hubungi kami lewat WhatsApp.';
    END IF;

    -- Kode singkat yang mudah disebutkan lewat telepon
    LOOP
        v_coba := v_coba + 1;
        v_kode := 'BK' || upper(substring(replace(gen_random_uuid()::TEXT, '-', '') from 1 for 5));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM bookings b WHERE b.kode = v_kode);
        IF v_coba > 12 THEN RAISE EXCEPTION 'Gagal membuat kode booking. Coba lagi.'; END IF;
    END LOOP;

    INSERT INTO bookings (kode, nama, telepon, service_id, service_name, harga,
                          durasi_menit, tanggal, jam, catatan)
    VALUES (v_kode, v_nama, v_telp, v_srv.id, v_srv.name, v_srv.price,
            v_srv.duration_minutes, p_tanggal, p_jam,
            NULLIF(btrim(COALESCE(p_catatan, '')), ''));

    RETURN QUERY SELECT v_kode::VARCHAR, p_tanggal, p_jam, v_srv.name;
END $function$;

GRANT EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID, date, time, TEXT) TO anon, authenticated;


-- ==============================================================================
-- bookings_list — dibaca kasir dan owner
-- ==============================================================================
CREATE OR REPLACE FUNCTION bookings_list(
    p_status TEXT DEFAULT NULL, p_tanggal date DEFAULT NULL
)
RETURNS TABLE (
    id UUID, kode VARCHAR, nama VARCHAR, telepon VARCHAR,
    service_name VARCHAR, harga NUMERIC, durasi_menit INT,
    tanggal date, jam time, catatan TEXT, status TEXT,
    catatan_kasir TEXT, created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT (is_owner() OR is_pos_device()) THEN
        RAISE EXCEPTION 'Hanya kasir dan owner yang boleh membuka daftar booking.';
    END IF;
    RETURN QUERY
    SELECT b.id, b.kode, b.nama, b.telepon, b.service_name, b.harga, b.durasi_menit,
           b.tanggal, b.jam, b.catatan, b.status::TEXT, b.catatan_kasir, b.created_at
      FROM bookings b
     WHERE (p_status IS NULL OR p_status = '' OR b.status::TEXT = p_status)
       AND (p_tanggal IS NULL OR b.tanggal = p_tanggal)
     ORDER BY (b.status = 'baru') DESC, b.tanggal, b.jam
     LIMIT 300;
END $function$;

GRANT EXECUTE ON FUNCTION bookings_list(TEXT, date) TO authenticated;


-- ==============================================================================
-- decide_booking — kasir mengonfirmasi, menolak, atau menandai selesai
-- ==============================================================================
CREATE OR REPLACE FUNCTION decide_booking(
    p_id UUID, p_status TEXT, p_catatan TEXT DEFAULT NULL
)
RETURNS TABLE (id UUID, kode VARCHAR, status TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_row bookings%ROWTYPE;
BEGIN
    IF NOT (is_owner() OR is_pos_device()) THEN
        RAISE EXCEPTION 'Hanya kasir dan owner yang boleh memutus booking.';
    END IF;
    IF p_status NOT IN ('dikonfirmasi', 'ditolak', 'selesai', 'batal') THEN
        RAISE EXCEPTION 'Status "%" tidak dikenali.', p_status;
    END IF;

    SELECT * INTO v_row FROM bookings b WHERE b.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking tidak ditemukan.'; END IF;

    UPDATE bookings SET
        status        = p_status::booking_status,
        catatan_kasir = NULLIF(btrim(COALESCE(p_catatan, '')), ''),
        diputus_oleh  = auth.uid(),
        diputus_pada  = now()
     WHERE bookings.id = p_id;

    RETURN QUERY SELECT b.id, b.kode, b.status::TEXT FROM bookings b WHERE b.id = p_id;
END $function$;

GRANT EXECUTE ON FUNCTION decide_booking(UUID, TEXT, TEXT) TO authenticated;
