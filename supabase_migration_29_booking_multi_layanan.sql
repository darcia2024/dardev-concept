-- ==============================================================================
-- MIGRASI 29 - Satu Booking Dapat Memuat Beberapa Layanan
--
-- Pelanggan yang datang untuk potong sekaligus cuci rambut sebelumnya harus
-- memilih salah satu, dan kasir baru mengetahui sisanya saat orangnya sudah
-- duduk. Durasi yang diperkirakan pun jadi salah: 45 menit yang dipesan
-- ternyata 60 menit yang dikerjakan.
--
-- BENTUK PENYIMPANANNYA
--
-- service_ids menyimpan pilihannya, sementara service_name, harga, dan
-- durasi_menit tetap diisi sebagai ringkasan gabungan. Ketiganya sudah dibaca
-- panel booking di POS, dan membiarkannya tetap terisi berarti layar kasir
-- tidak perlu ikut diubah untuk sekadar menampilkan dua layanan.
--
-- Fungsi lama dibuang, bukan dibiarkan berdampingan. Dua jalur masuk yang
-- mengerjakan hal sama akan berbeda perlakuan begitu salah satunya diperbaiki
-- dan yang lain terlupakan.
--
-- BATAS EMPAT LAYANAN
--
-- Bukan angka keramat, melainkan penahan. Tanpa batas, satu permintaan dapat
-- memuat sepuluh layanan dan mengunci seorang kapster sepanjang hari lewat
-- formulir yang dibuka tanpa login.
-- ==============================================================================

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS service_ids UUID[];

-- Baris lama diisi dari kolom tunggalnya supaya bentuk datanya seragam.
UPDATE bookings
   SET service_ids = ARRAY[service_id]
 WHERE service_ids IS NULL AND service_id IS NOT NULL;

DROP FUNCTION IF EXISTS create_booking(TEXT, TEXT, UUID, date, time, TEXT);

CREATE OR REPLACE FUNCTION create_booking(
    p_nama TEXT, p_telepon TEXT, p_service_ids UUID[],
    p_tanggal date, p_jam time, p_catatan TEXT DEFAULT NULL
)
RETURNS TABLE (kode VARCHAR, tanggal date, jam time, layanan TEXT, durasi INT, total NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_nama    TEXT;
    v_telp    TEXT;
    v_catatan TEXT;
    v_ids     UUID[];
    v_nama_gab TEXT;
    v_durasi  INT;
    v_total   NUMERIC;
    v_jumlah  INT;
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

    -- Pilihan ganda dirapikan dulu: duplikat dibuang, NULL disingkirkan.
    SELECT array_agg(DISTINCT x) INTO v_ids
      FROM unnest(COALESCE(p_service_ids, ARRAY[]::UUID[])) AS x
     WHERE x IS NOT NULL;

    IF v_ids IS NULL OR array_length(v_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Pilih minimal satu layanan.';
    END IF;
    IF array_length(v_ids, 1) > 4 THEN
        RAISE EXCEPTION 'Maksimal 4 layanan dalam satu booking.';
    END IF;

    SELECT string_agg(s.name, ' + ' ORDER BY s.price),
           SUM(s.duration_minutes)::INT,
           SUM(s.price),
           COUNT(*)::INT
      INTO v_nama_gab, v_durasi, v_total, v_jumlah
      FROM services s
     WHERE s.id = ANY(v_ids) AND s.is_active;

    IF v_jumlah IS NULL OR v_jumlah <> array_length(v_ids, 1) THEN
        RAISE EXCEPTION 'Ada layanan yang tidak ditemukan atau sudah tidak tersedia.';
    END IF;
    v_durasi := COALESCE(v_durasi, 30);

    IF p_tanggal IS NULL OR p_tanggal < jakarta_today() THEN
        RAISE EXCEPTION 'Tanggal booking tidak boleh di masa lalu.';
    END IF;
    IF p_tanggal > jakarta_today() + 30 THEN
        RAISE EXCEPTION 'Booking hanya dapat dilakukan sampai 30 hari ke depan.';
    END IF;

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

    -- Dihitung dalam menit sejak tengah malam. Penjumlahan pada tipe time
    -- berputar melewati tengah malam, dan itu pernah membuat booking pukul
    -- 23.30 lolos seluruh pemeriksaan.
    IF p_jam < v_jam.buka
       OR (EXTRACT(EPOCH FROM p_jam) / 60 + v_durasi)
          > (EXTRACT(EPOCH FROM v_jam.tutup) / 60) THEN
        RAISE EXCEPTION 'Rangkaian layanan ini butuh % menit dan tidak selesai sebelum toko tutup pukul %.',
            v_durasi, to_char(v_jam.tutup, 'HH24:MI');
    END IF;

    IF p_tanggal = jakarta_today()
       AND p_tanggal + p_jam
           < (now() AT TIME ZONE 'Asia/Jakarta') + INTERVAL '30 minutes' THEN
        RAISE EXCEPTION 'Pilih jam minimal 30 menit dari sekarang.';
    END IF;

    -- Serialisasi kuota per nomor menutup celah beberapa permintaan paralel
    -- yang sama-sama lolos COUNT sebelum salah satunya sempat menyisipkan.
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

    INSERT INTO bookings (kode, nama, telepon, service_id, service_ids, service_name,
                          harga, durasi_menit, tanggal, jam, catatan)
    VALUES (v_kode, v_nama, v_telp, v_ids[1], v_ids, v_nama_gab,
            v_total, v_durasi, p_tanggal, p_jam, v_catatan);

    RETURN QUERY SELECT v_kode::VARCHAR, p_tanggal, p_jam, v_nama_gab, v_durasi, v_total;
END $function$;

GRANT EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID[], date, time, TEXT) TO anon, authenticated;

-- Fungsi baru lahir dengan hak EXECUTE untuk PUBLIC. Tiga fungsi booking
-- lainnya sudah dicabut haknya di migrasi 25, dan menyisakan satu yang tidak
-- berarti setiap peran yang ditambahkan kelak ikut mewarisi akses tanpa ada
-- yang memutuskannya.
REVOKE EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID[], date, time, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID[], date, time, TEXT) TO anon, authenticated;
