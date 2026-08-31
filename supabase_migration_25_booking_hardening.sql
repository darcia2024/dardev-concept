-- ==============================================================================
-- MIGRASI 25 - Validasi Waktu dan Pengamanan Booking Publik
--
-- Migrasi 24 sudah pernah dijalankan di production. Perubahan fungsi dipisah
-- di sini agar riwayat database tetap dapat dijalankan berurutan pada database
-- lama maupun instalasi baru.
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
    v_catatan TEXT;
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

    v_telp := regexp_replace(COALESCE(p_telepon, ''), '[^0-9]', '', 'g');
    IF left(v_telp, 1) = '0' THEN v_telp := '62' || substring(v_telp from 2); END IF;
    IF left(v_telp, 1) = '8' THEN v_telp := '62' || v_telp; END IF;
    IF v_telp !~ '^628[0-9]{7,13}$' THEN
        RAISE EXCEPTION 'Nomor WhatsApp tidak dikenali. Contoh: 081510474646';
    END IF;

    v_catatan := NULLIF(btrim(COALESCE(p_catatan, '')), '');
    IF length(COALESCE(v_catatan, '')) > 300 THEN
        RAISE EXCEPTION 'Catatan maksimal 300 karakter.';
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
    IF p_jam IS NULL
       OR EXTRACT(MINUTE FROM p_jam)::INT % 30 <> 0
       OR EXTRACT(SECOND FROM p_jam)::INT <> 0 THEN
        RAISE EXCEPTION 'Jam booking harus berada pada interval 30 menit.';
    END IF;
    IF p_jam < v_jam.buka
       OR p_jam + make_interval(mins => v_srv.duration_minutes) > v_jam.tutup THEN
        RAISE EXCEPTION 'Layanan ini harus selesai sebelum toko tutup pukul %.',
            to_char(v_jam.tutup, 'HH24:MI');
    END IF;
    IF p_tanggal = jakarta_today()
       AND p_tanggal + p_jam
           < (now() AT TIME ZONE 'Asia/Jakarta') + INTERVAL '30 minutes' THEN
        RAISE EXCEPTION 'Pilih jam minimal 30 menit dari sekarang.';
    END IF;

    -- Serialisasi kuota per nomor menutup celah beberapa request paralel yang
    -- sama-sama lolos COUNT sebelum salah satunya sempat melakukan INSERT.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_telp, 0));

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

    LOOP
        v_coba := v_coba + 1;
        v_kode := 'BK' || upper(substring(replace(gen_random_uuid()::TEXT, '-', '') from 1 for 5));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM bookings b WHERE b.kode = v_kode);
        IF v_coba > 12 THEN RAISE EXCEPTION 'Gagal membuat kode booking. Coba lagi.'; END IF;
    END LOOP;

    INSERT INTO bookings (kode, nama, telepon, service_id, service_name, harga,
                          durasi_menit, tanggal, jam, catatan)
    VALUES (v_kode, v_nama, v_telp, v_srv.id, v_srv.name, v_srv.price,
            v_srv.duration_minutes, p_tanggal, p_jam, v_catatan);

    RETURN QUERY SELECT v_kode::VARCHAR, p_tanggal, p_jam, v_srv.name;
END $function$;

-- SECURITY DEFINER tidak boleh mewarisi hak EXECUTE bawaan untuk PUBLIC.
REVOKE EXECUTE ON FUNCTION public_landing() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID, date, time, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION bookings_list(TEXT, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION decide_booking(UUID, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public_landing() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID, date, time, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION bookings_list(TEXT, date) TO authenticated;
GRANT EXECUTE ON FUNCTION decide_booking(UUID, TEXT, TEXT) TO authenticated;
