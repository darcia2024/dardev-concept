-- =============================================================================
-- 44 · QRIS DINAMIS: PAYLOAD DI SERVER, KONFIRMASI TERCATAT
--
-- Dua hal yang sebelumnya hanya hidup di peramban kasir dipindahkan ke sini.
--
-- 1. Payload QRIS statis outlet. Sebelumnya di localStorage tiap perangkat,
--    sehingga menambah satu perangkat kasir berarti menempelkannya lagi, dan
--    membersihkan data situs menghapusnya diam-diam.
--
-- 2. Konfirmasi kasir bahwa dana QRIS terlihat masuk. Sebelumnya gerbang itu
--    hanya menahan tombol simpan lalu hilang tanpa jejak — pemilik tidak punya
--    cara memeriksa nota QRIS mana yang benar-benar diverifikasi.
--
-- YANG SENGAJA TIDAK DILAKUKAN: menambah parameter ke create_transaction.
-- Fungsi itu 306 baris dengan 16 parameter dan sudah ditulis ulang enam kali;
-- menyalinnya ulang demi satu kolom menaruh seluruh jalur penjualan pada
-- risiko demi sebuah penanda laporan. Penandaan dipisah ke RPC sendiri yang
-- dipanggil sesudah notanya tersimpan. Konsekuensinya jujur: bila panggilan
-- kedua gagal, notanya tetap tersimpan tanpa penanda dan muncul sebagai
-- "belum tercatat" di dasbor. Itu lubang pelaporan, bukan lubang uang —
-- gerbangnya sendiri tetap ditegakkan di kasir sebelum nota disimpan.
-- =============================================================================


-- ── 1 · Payload QRIS statis milik outlet ────────────────────────────────────
-- Mengikuti pola wa_config: satu baris, tanpa policy, hanya terbaca lewat
-- fungsi SECURITY DEFINER. Payload ini bukan rahasia — ia tercetak pada stiker
-- di meja kasir — tetapi tidak ada alasan menyiarkannya ke anon.
CREATE TABLE IF NOT EXISTS qris_config (
    id             BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    payload_statis TEXT,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE qris_config ENABLE ROW LEVEL SECURITY;

INSERT INTO qris_config (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

COMMENT ON COLUMN qris_config.payload_statis IS
'Isi QRIS statis outlet apa adanya (EMVCo TLV). POS menyuntikkan tag 54 dan '
'mengubah tag 01 menjadi 12 untuk tiap nota, lalu menghitung ulang CRC tag 63. '
'NULL berarti kasir kembali memakai stiker di meja.';


CREATE OR REPLACE FUNCTION pos_qris_config()
RETURNS TABLE (payload_statis TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;
    RETURN QUERY SELECT q.payload_statis FROM qris_config q WHERE q.id;
END $function$;

REVOKE EXECUTE ON FUNCTION pos_qris_config() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION pos_qris_config() TO authenticated;


CREATE OR REPLACE FUNCTION owner_set_qris(p_payload TEXT)
RETURNS TABLE (payload_statis TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_bersih TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah QRIS outlet.';
    END IF;

    -- Hanya baris baru dan tab yang dibuang; itu sampah dari salin-tempel.
    -- Spasi TIDAK ikut dibuang: nama merchant sah mengandungnya
    -- ("Underrated Barbershop"), dan membuangnya merusak payload sekaligus
    -- panjang tag yang sudah tertulis di dalamnya.
    v_bersih := NULLIF(btrim(regexp_replace(COALESCE(p_payload, ''), '[\r\n\t]', '', 'g')), '');

    -- Pemeriksaan bentuk seadanya. Checksum CRC16 yang sesungguhnya diperiksa
    -- di POS sebelum dikirim ke sini; yang di bawah hanya menahan isian yang
    -- jelas bukan QRIS agar tidak tersimpan diam-diam.
    IF v_bersih IS NOT NULL THEN
        IF left(v_bersih, 6) <> '000201' THEN
            RAISE EXCEPTION 'Payload QRIS harus diawali 000201.';
        END IF;
        IF length(v_bersih) < 20
           OR substr(v_bersih, length(v_bersih) - 7, 4) <> '6304' THEN
            RAISE EXCEPTION 'Payload QRIS harus diakhiri 6304 dan empat karakter checksum.';
        END IF;
    END IF;

    UPDATE qris_config q
       SET payload_statis = v_bersih,
           updated_at     = now()
     WHERE q.id;

    RETURN QUERY SELECT q.payload_statis FROM qris_config q WHERE q.id;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_set_qris(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_set_qris(TEXT) TO authenticated;


-- ── 2 · Konfirmasi dana QRIS ────────────────────────────────────────────────
-- Sistem tidak punya jalur untuk mendengar dana QRIS masuk; yang menutup celah
-- itu mata kasir. Kolom ini merekam kapan ia menyatakannya, sehingga pemilik
-- dapat memisahkan nota QRIS yang sudah diperiksa dari yang lolos begitu saja.
ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS qris_konfirmasi_at TIMESTAMPTZ;

COMMENT ON COLUMN transactions.qris_konfirmasi_at IS
'Waktu kasir menyatakan dana QRIS terlihat masuk di aplikasi merchant. NULL '
'pada nota non-QRIS, dan pada nota QRIS berarti penandaannya tidak sampai — '
'bukan berarti dananya tidak masuk.';

-- Hanya nota QRIS yang punya penanda. Nota tunai/EDC/transfer harus tetap NULL
-- supaya laporan "belum terkonfirmasi" tidak tercemar baris yang memang tidak
-- pernah membutuhkannya.
CREATE INDEX IF NOT EXISTS idx_tx_qris_belum_konfirmasi
    ON transactions (business_date)
 WHERE payment_method = 'QRIS' AND qris_konfirmasi_at IS NULL;


CREATE OR REPLACE FUNCTION tandai_qris_konfirmasi(p_client_uuid UUID)
RETURNS TABLE (invoice_no VARCHAR, qris_konfirmasi_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    -- COALESCE menahan waktunya: penandaan ulang — antrean luring yang terkirim
    -- dua kali, kasir yang menekan lagi — tidak boleh menggeser waktu
    -- pemeriksaan yang sebenarnya ke saat pengiriman ulang.
    UPDATE transactions t
       SET qris_konfirmasi_at = COALESCE(t.qris_konfirmasi_at, now())
     WHERE t.client_uuid = p_client_uuid
       AND t.payment_method = 'QRIS';

    RETURN QUERY
    SELECT t.invoice_no, t.qris_konfirmasi_at
      FROM transactions t
     WHERE t.client_uuid = p_client_uuid;
END $function$;

REVOKE EXECUTE ON FUNCTION tandai_qris_konfirmasi(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION tandai_qris_konfirmasi(UUID) TO authenticated;


-- ── 3 · Daftar pantau untuk pemilik ─────────────────────────────────────────
-- Yang dicari pemilik bukan daftar seluruh nota QRIS, melainkan yang belum
-- diperiksa siapa pun. Daftar yang memuat semuanya akan dibaca sekali lalu
-- diabaikan selamanya.
CREATE OR REPLACE FUNCTION owner_qris_belum_konfirmasi(p_tanggal DATE DEFAULT NULL)
RETURNS TABLE (invoice_no VARCHAR, created_at TIMESTAMPTZ, capster_name VARCHAR,
               member_name VARCHAR, final_amount NUMERIC, payment_ref VARCHAR)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membaca daftar ini.';
    END IF;

    RETURN QUERY
    SELECT t.invoice_no, t.created_at, t.capster_name,
           t.member_name, t.final_amount, t.payment_ref
      FROM transactions t
     WHERE t.payment_method = 'QRIS'
       AND t.qris_konfirmasi_at IS NULL
       AND (p_tanggal IS NULL OR t.business_date = p_tanggal)
     ORDER BY t.created_at DESC
     LIMIT 200;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_qris_belum_konfirmasi(DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_qris_belum_konfirmasi(DATE) TO authenticated;
