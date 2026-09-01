-- ==============================================================================
-- MIGRASI 38 - Booking Terhubung ke Transaksi, dan Terlihat oleh Owner
--
-- MASALAH PERTAMA: BOOKING TIDAK PERNAH TERHUBUNG KE PENJUALANNYA
--
-- Kasir menandai booking "selesai" secara manual, dan itu satu-satunya jejak
-- bahwa orangnya benar-benar datang. Tidak ada apa pun yang mengaitkan
-- booking itu ke transaksi yang benar-benar terjadi, sehingga pertanyaan
-- paling dasar tentang program booking tidak dapat dijawab: dari sekian
-- booking yang dikonfirmasi, berapa yang benar-benar menjadi penjualan?
--
-- Tanpa angka itu, tidak ada cara mengetahui apakah booking online layak
-- diteruskan atau justru hanya memindahkan pekerjaan ke kasir.
--
-- Penghubungnya diletakkan di bookings, bukan di transactions. Satu transaksi
-- tidak pernah berasal dari dua booking, sedangkan kolom di transactions akan
-- kosong pada hampir semua baris sebab sebagian besar pelanggan datang tanpa
-- booking sama sekali.
--
-- MASALAH KEDUA: OWNER TIDAK PUNYA JALAN MELIHATNYA
--
-- Booking hanya ada di layar kasir, dan layar itu menuntut PIN kasir. Pemilik
-- yang ingin sekadar melihat berapa booking hari ini harus membuka mesin
-- kasir dan memasukkan PIN yang bukan miliknya.
-- ==============================================================================

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS transaction_id UUID REFERENCES transactions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS bookings_transaksi ON bookings (transaction_id);

COMMENT ON COLUMN bookings.transaction_id IS
  'Transaksi yang benar-benar terjadi dari booking ini. Kosong berarti '
  'orangnya belum datang, atau datang tanpa dikaitkan oleh kasir.';


-- ── Menutup booking sekaligus mengaitkannya ────────────────────────────────
CREATE OR REPLACE FUNCTION selesaikan_booking(p_id UUID, p_tx_id UUID DEFAULT NULL)
RETURNS TABLE (kode VARCHAR, nama VARCHAR, invoice_no VARCHAR)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_b bookings%ROWTYPE;
    v_t transactions%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perangkat belum terdaftar.'; END IF;

    SELECT * INTO v_b FROM bookings b WHERE b.id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking tidak ditemukan.'; END IF;
    IF v_b.status NOT IN ('baru', 'dikonfirmasi') THEN
        RAISE EXCEPTION 'Booking % sudah berstatus %.', v_b.kode, v_b.status;
    END IF;

    /* Kalau kasir tidak menyebutkan transaksinya, sistem mencarinya sendiri:
       transaksi hari ini dengan nomor telepon yang sama dan belum terkait
       booking mana pun. Menuntut kasir memilih transaksi secara manual berarti
       satu langkah tambahan pada saat paling sibuk, dan langkah yang dapat
       dilewati adalah langkah yang akan dilewati — pengaitannya lalu kosong
       selamanya tanpa ada yang menyadarinya.

       Yang terbaru dipilih bila ada lebih dari satu, sebab itu yang paling
       mungkin baru saja selesai di depan kasir. */
    IF p_tx_id IS NULL THEN
        SELECT t.id INTO p_tx_id
          FROM transactions t
         WHERE t.member_phone = v_b.telepon
           AND t.business_date = jakarta_today()
           AND NOT EXISTS (SELECT 1 FROM bookings b3 WHERE b3.transaction_id = t.id)
         ORDER BY t.created_at DESC
         LIMIT 1;
    END IF;

    IF p_tx_id IS NOT NULL THEN
        SELECT * INTO v_t FROM transactions t WHERE t.id = p_tx_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak ditemukan.'; END IF;

        -- Satu transaksi tidak boleh dipakai menutup dua booking. Tanpa
        -- penjagaan ini, satu penjualan dapat dihitung dua kali sebagai bukti
        -- bahwa dua orang datang.
        IF EXISTS (SELECT 1 FROM bookings b2
                    WHERE b2.transaction_id = p_tx_id AND b2.id <> p_id) THEN
            RAISE EXCEPTION 'Transaksi % sudah dikaitkan ke booking lain.', v_t.invoice_no;
        END IF;
    END IF;

    UPDATE bookings
       SET status = 'selesai', transaction_id = COALESCE(p_tx_id, transaction_id)
     WHERE id = p_id;

    RETURN QUERY SELECT v_b.kode, v_b.nama, v_t.invoice_no;
END $function$;


-- ── Ringkasan untuk owner: berapa yang benar-benar datang ──────────────────
CREATE OR REPLACE FUNCTION owner_booking_ringkas(p_bulan date DEFAULT NULL)
RETURNS TABLE (bulan date, diminta INT, dikonfirmasi INT, selesai INT,
               ditolak INT, batal INT, terkait_transaksi INT,
               nilai_terkait NUMERIC, persen_datang NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    WITH batas AS (
        SELECT date_trunc('month',
                 COALESCE(p_bulan, jakarta_today()))::date AS awal
    ), isi AS (
        SELECT b.* FROM bookings b, batas
         WHERE b.tanggal >= batas.awal
           AND b.tanggal < (batas.awal + INTERVAL '1 month')::date
    )
    SELECT (SELECT awal FROM batas),
           COUNT(*)::INT,
           COUNT(*) FILTER (WHERE status = 'dikonfirmasi')::INT,
           COUNT(*) FILTER (WHERE status = 'selesai')::INT,
           COUNT(*) FILTER (WHERE status = 'ditolak')::INT,
           COUNT(*) FILTER (WHERE status = 'batal')::INT,
           COUNT(*) FILTER (WHERE transaction_id IS NOT NULL)::INT,
           COALESCE((SELECT SUM(t.final_amount) FROM transactions t
                      WHERE t.id IN (SELECT transaction_id FROM isi
                                      WHERE transaction_id IS NOT NULL)), 0),
           -- Angka inti program booking: dari yang sudah dipastikan ke
           -- pelanggan, berapa persen yang benar-benar menjadi penjualan.
           CASE WHEN COUNT(*) FILTER (WHERE status IN ('dikonfirmasi','selesai')) = 0 THEN 0
                ELSE round(COUNT(*) FILTER (WHERE status = 'selesai') * 100.0
                     / COUNT(*) FILTER (WHERE status IN ('dikonfirmasi','selesai')), 1)
           END
      FROM isi
     WHERE is_owner()
$function$;


REVOKE EXECUTE ON FUNCTION selesaikan_booking(UUID, UUID)  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION owner_booking_ringkas(date)     FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION selesaikan_booking(UUID, UUID)  TO authenticated;
GRANT  EXECUTE ON FUNCTION owner_booking_ringkas(date)     TO authenticated;
