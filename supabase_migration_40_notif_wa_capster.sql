-- ==============================================================================
-- MIGRASI 40 - Notifikasi WhatsApp ke Capster Saat Ada Booking Baru
--
-- APA YANG SUDAH ADA, DAN APA YANG BELUM
--
-- Sudah ada: capsters.phone, dan ketiganya sudah terisi. Kolom itu tidak
-- pernah keluar ke publik — public_landing() hanya mengirim nama sejak
-- migrasi 28. Jadi tidak ada field baru yang perlu dibuat untuk nomornya.
--
-- Belum ada tiga hal, dan ketiganya menghalangi:
--
--   1. Booking tidak menyimpan pilihan capster sama sekali. Tombol "Pilih
--      Cena" di halaman depan hanya menempelkan kalimat ke kolom catatan.
--      Artinya tidak ada capster yang benar-benar "terhubung ke booking",
--      dan server tidak punya cara menentukan tujuan notifikasinya.
--
--   2. Tidak ada integrasi WhatsApp apa pun. Yang ada hanyalah tautan wa.me
--      yang harus ditekan manusia — itu membuka WhatsApp di perangkat kasir,
--      bukan mengirim apa pun dari server.
--
--   3. Basis datanya tidak dapat mengirim HTTP. pg_net belum terpasang.
--
-- NOMOR TUJUAN DITENTUKAN SERVER, TITIK
--
-- Fungsi pengirim hanya menerima id booking. Nomornya dicari sendiri lewat
-- bookings.capster_id -> capsters.phone di dalam fungsi SECURITY DEFINER.
-- Tidak ada satu pun jalur yang menerima nomor tujuan dari peramban, sehingga
-- tidak ada cara bagi siapa pun untuk mengarahkan notifikasi ke nomor lain.
--
-- Nomor capster juga tidak pernah ikut keluar: public_landing() menambahkan
-- id dan nama saja. Id adalah rujukan, bukan rahasia; nomor telepon adalah
-- rahasia, dan ia tidak pernah meninggalkan basis data.
--
-- KREDENSIAL DI VAULT, BUKAN DI TABEL
--
-- Token provider disimpan di Vault dan hanya dibaca di dalam fungsi
-- SECURITY DEFINER. Menyimpannya di tabel biasa berarti ia ikut terbaca oleh
-- siapa pun yang punya akses baca ke tabel itu, dan token WhatsApp yang bocor
-- dapat dipakai mengirim atas nama toko.
--
-- BOOKING TIDAK BOLEH GAGAL KARENA NOTIFIKASI
--
-- Seluruh isi fungsi pengirim dibungkus EXCEPTION WHEN OTHERS. Kalau nomornya
-- kosong, providernya mati, atau tokennya salah, kegagalannya dicatat di
-- baris bookingnya sendiri dan transaksinya tetap selesai. Pelanggan yang
-- sudah menekan kirim tidak boleh kehilangan bookingnya hanya karena
-- pemberitahuan internal gagal.
--
-- pg_net memang mengirim secara asinkron: ia menitipkan permintaan ke antrean
-- dan kembali seketika, jadi pelanggan tidak menunggu jaringan WhatsApp.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;


-- ── Booking menyimpan capster pilihan dan jejak notifikasinya ───────────────
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS capster_id UUID REFERENCES capsters(id);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notif_wa_at     TIMESTAMPTZ;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notif_wa_status TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notif_wa_error  TEXT;

COMMENT ON COLUMN bookings.capster_id IS
  'Capster yang diminta pelanggan. Kosong berarti pelanggan tidak memilih. '
  'Ini satu-satunya sumber nomor tujuan notifikasi.';
COMMENT ON COLUMN bookings.notif_wa_at IS
  'Penanda bahwa notifikasi sudah pernah diproses. Menjaga agar kirim ulang '
  'atau kirim ganda tidak menghasilkan pesan berulang.';

CREATE INDEX IF NOT EXISTS bookings_capster ON bookings (capster_id, tanggal);


-- ── Pengaturan provider ────────────────────────────────────────────────────
-- Sengaja tidak mengunci diri ke satu provider. Yang berubah antar-provider
-- hanyalah alamat, bentuk muatan, dan nama tokennya; ketiganya data, bukan
-- kode. Mengganti provider kelak tidak perlu menyentuh fungsi ini.
CREATE TABLE IF NOT EXISTS wa_config (
    id           BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    aktif        BOOLEAN     NOT NULL DEFAULT FALSE,
    provider     TEXT        NOT NULL DEFAULT 'meta',   -- 'meta' | 'generik'
    endpoint     TEXT,
    nama_rahasia TEXT        NOT NULL DEFAULT 'WA_TOKEN',
    template     TEXT        NOT NULL DEFAULT 'booking_baru',
    bahasa       TEXT        NOT NULL DEFAULT 'id',
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE wa_config ENABLE ROW LEVEL SECURITY;
-- Tanpa policy apa pun: hanya terbaca lewat fungsi SECURITY DEFINER.

INSERT INTO wa_config (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;


CREATE OR REPLACE FUNCTION owner_wa_config()
RETURNS TABLE (aktif BOOLEAN, provider TEXT, endpoint TEXT, nama_rahasia TEXT,
               template TEXT, bahasa TEXT, token_terisi BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    -- Tokennya sendiri tidak pernah dikembalikan, hanya keterangan bahwa ia
    -- sudah terisi. Layar pengaturan tidak perlu tahu isinya untuk dapat
    -- memberi tahu pemilik bahwa kredensialnya sudah dipasang.
    SELECT c.aktif, c.provider, c.endpoint, c.nama_rahasia, c.template, c.bahasa,
           EXISTS (SELECT 1 FROM vault.decrypted_secrets v WHERE v.name = c.nama_rahasia)
      FROM wa_config c
     WHERE is_owner()
$function$;

CREATE OR REPLACE FUNCTION set_wa_config(
    p_aktif BOOLEAN, p_provider TEXT, p_endpoint TEXT,
    p_template TEXT, p_bahasa TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah pengaturan WhatsApp.';
    END IF;
    IF p_aktif AND COALESCE(btrim(p_endpoint), '') = '' THEN
        RAISE EXCEPTION 'Alamat pengiriman wajib diisi sebelum notifikasi diaktifkan.';
    END IF;

    UPDATE wa_config
       SET aktif    = COALESCE(p_aktif, FALSE),
           provider = COALESCE(NULLIF(btrim(p_provider), ''), 'meta'),
           endpoint = NULLIF(btrim(p_endpoint), ''),
           template = COALESCE(NULLIF(btrim(p_template), ''), 'booking_baru'),
           bahasa   = COALESCE(NULLIF(btrim(p_bahasa), ''), 'id'),
           updated_at = now();
    RETURN 'Pengaturan WhatsApp tersimpan.';
END $function$;


-- ── Pengirim ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION kirim_wa_capster(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $function$
DECLARE
    v_b      bookings%ROWTYPE;
    v_telp   TEXT;
    v_nama   TEXT;
    v_cfg    wa_config%ROWTYPE;
    v_token  TEXT;
    v_pesan  TEXT;
    v_body   JSONB;
    v_status TEXT;
    v_galat  TEXT;
BEGIN
    -- Baris dikunci: dua permintaan yang tiba bersamaan untuk booking yang
    -- sama akan berbaris, dan yang kedua melihat penanda dari yang pertama.
    SELECT * INTO v_b FROM bookings b WHERE b.id = p_booking_id FOR UPDATE;
    IF NOT FOUND OR v_b.notif_wa_at IS NOT NULL THEN RETURN; END IF;

    SELECT * INTO v_cfg FROM wa_config LIMIT 1;

    SELECT c.phone, c.name INTO v_telp, v_nama
      FROM capsters c WHERE c.id = v_b.capster_id AND c.is_active;

    IF v_b.capster_id IS NULL THEN
        v_status := 'tanpa_capster';
    ELSIF COALESCE(btrim(v_telp), '') !~ '^62[0-9]{8,15}$' THEN
        v_status := 'nomor_tidak_sah';
        v_galat  := 'Nomor capster kosong atau tidak berformat 62xxxxxxxxxx.';
    ELSIF NOT COALESCE(v_cfg.aktif, FALSE) THEN
        v_status := 'nonaktif';
    ELSE
        BEGIN
            SELECT decrypted_secret INTO v_token
              FROM vault.decrypted_secrets WHERE name = v_cfg.nama_rahasia;
            IF COALESCE(v_token, '') = '' THEN
                RAISE EXCEPTION 'Token % belum tersimpan di Vault.', v_cfg.nama_rahasia;
            END IF;

            v_pesan := 'Booking baru untuk ' || v_nama || '.' || chr(10)
                    || 'Nama: ' || v_b.nama || chr(10)
                    || 'Layanan: ' || v_b.service_name || chr(10)
                    || 'Tanggal: ' || to_char(v_b.tanggal, 'DD Mon YYYY') || chr(10)
                    || 'Jam: ' || to_char(v_b.jam, 'HH24:MI') || chr(10)
                    || 'Kode: ' || v_b.kode;

            -- Nomor pelanggan sengaja TIDAK disertakan. Capster tidak
            -- membutuhkannya untuk bersiap, dan kasirlah yang menghubungi
            -- pelanggan. Menyebarkannya ke beberapa ponsel memperbanyak
            -- tempat data itu dapat bocor tanpa menambah kegunaan.
            IF v_cfg.provider = 'meta' THEN
                v_body := jsonb_build_object(
                    'messaging_product', 'whatsapp',
                    'to', v_telp,
                    'type', 'template',
                    'template', jsonb_build_object(
                        'name', v_cfg.template,
                        'language', jsonb_build_object('code', v_cfg.bahasa),
                        'components', jsonb_build_array(jsonb_build_object(
                            'type', 'body',
                            'parameters', jsonb_build_array(
                                jsonb_build_object('type','text','text', v_b.nama),
                                jsonb_build_object('type','text','text', v_b.service_name),
                                jsonb_build_object('type','text','text', to_char(v_b.tanggal,'DD Mon YYYY')),
                                jsonb_build_object('type','text','text', to_char(v_b.jam,'HH24:MI')),
                                jsonb_build_object('type','text','text', v_b.kode)
                            )))));
            ELSE
                v_body := jsonb_build_object('target', v_telp, 'message', v_pesan);
            END IF;

            PERFORM net.http_post(
                url     := v_cfg.endpoint,
                body    := v_body,
                headers := jsonb_build_object(
                               'Content-Type', 'application/json',
                               'Authorization', 'Bearer ' || v_token));
            v_status := 'terkirim';
        EXCEPTION WHEN OTHERS THEN
            -- Booking tidak boleh gugur karena pemberitahuan internal gagal.
            v_status := 'gagal';
            v_galat  := left(SQLERRM, 500);
        END;
    END IF;

    UPDATE bookings
       SET notif_wa_at = now(), notif_wa_status = v_status, notif_wa_error = v_galat
     WHERE id = p_booking_id;
EXCEPTION WHEN OTHERS THEN
    -- Bahkan kegagalan di luar blok di atas pun tidak boleh menjatuhkan
    -- transaksi pemanggilnya.
    NULL;
END $function$;

REVOKE EXECUTE ON FUNCTION kirim_wa_capster(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION owner_wa_config()       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION set_wa_config(BOOLEAN, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_wa_config()       TO authenticated;
GRANT  EXECUTE ON FUNCTION set_wa_config(BOOLEAN, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ── Riwayat notifikasi untuk owner ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_notif_wa(p_limit INT DEFAULT 50)
RETURNS TABLE (waktu TIMESTAMPTZ, kode VARCHAR, capster VARCHAR,
               status TEXT, galat TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT b.notif_wa_at, b.kode, c.name, b.notif_wa_status, b.notif_wa_error
      FROM bookings b LEFT JOIN capsters c ON c.id = b.capster_id
     WHERE is_owner() AND b.notif_wa_at IS NOT NULL
     ORDER BY b.notif_wa_at DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
$function$;

REVOKE EXECUTE ON FUNCTION owner_notif_wa(INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_notif_wa(INT) TO authenticated;


-- ── create_booking menerima capster pilihan ────────────────────────────────
-- Ditambal dari definisi yang sedang berjalan, bukan ditulis ulang.
DROP FUNCTION IF EXISTS create_booking(TEXT, TEXT, UUID[], date, time, TEXT);
CREATE OR REPLACE FUNCTION public.create_booking(p_nama text, p_telepon text, p_service_ids uuid[], p_tanggal date, p_jam time without time zone, p_catatan text DEFAULT NULL::text, p_capster_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(kode character varying, tanggal date, jam time without time zone, layanan text, durasi integer, total numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
    v_tx_id   UUID;
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

    -- Capster pilihan diperiksa keberadaannya, bukan diterima apa adanya.
    -- Id yang tidak dikenal dibiarkan kosong daripada menggagalkan booking:
    -- pelanggan tidak seharusnya kehilangan jadwalnya karena daftar capster
    -- di layarnya sudah usang.
    IF p_capster_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM capsters c WHERE c.id = p_capster_id AND c.is_active) THEN
        p_capster_id := NULL;
    END IF;

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
                          harga, durasi_menit, tanggal, jam, catatan, capster_id)
    VALUES (v_kode, v_nama, v_telp, v_ids[1], v_ids, v_nama_gab,
            v_total, v_durasi, p_tanggal, p_jam, v_catatan, p_capster_id)
    RETURNING id INTO v_tx_id;

    -- Notifikasi dipicu di sini, sesudah bookingnya benar-benar tersimpan.
    -- Fungsinya menelan seluruh galatnya sendiri, jadi pemanggilan ini tidak
    -- dapat menjatuhkan transaksi. pg_net pun menitipkan permintaannya ke
    -- antrean dan kembali seketika, sehingga pelanggan tidak menunggu
    -- jaringan WhatsApp sebelum melihat kode bookingnya.
    PERFORM kirim_wa_capster(v_tx_id);

    RETURN QUERY SELECT v_kode::VARCHAR, p_tanggal, p_jam, v_nama_gab, v_durasi, v_total;
END $function$
;


REVOKE EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID[], date, time, TEXT, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION create_booking(TEXT, TEXT, UUID[], date, time, TEXT, UUID) TO anon, authenticated;


-- ── public_landing menyertakan id capster, bukan nomornya ──────
CREATE OR REPLACE FUNCTION public.public_landing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT jsonb_build_object(
        'layanan', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', s.id, 'nama', s.name, 'kategori', s.category,
                       'harga', s.price, 'menit', s.duration_minutes)
                   ORDER BY s.price)
              FROM services s WHERE s.is_active
        ), '[]'::jsonb),
        -- id ikut keluar supaya pilihan pelanggan dapat disimpan sebagai
        -- rujukan yang benar, bukan sebagai kalimat bebas di kolom catatan.
        -- Nomor teleponnya TIDAK pernah ikut: id adalah rujukan, nomor adalah
        -- rahasia, dan yang kedua tidak pernah meninggalkan basis data.
        'kapster', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('id', c.id, 'nama', c.name)
                             ORDER BY c.name)
              FROM capsters c WHERE c.is_active
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
                       'persen_poin', ls.earn_percent,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    );
$function$
;

REVOKE EXECUTE ON FUNCTION public_landing() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public_landing() TO anon, authenticated;
