-- ==============================================================================
-- MIGRASI 59 - Rincian transaksi untuk Asisten Internal (Add-on AI, fitur 5)
--
-- Laporan owner: asisten menjawab "pemasukan 12 September" dengan benar
-- (omzet dan jumlah transaksi), tetapi ketika ditanya "6 transaksi itu
-- detailnya bagaimana" menjawab "data transaksi satu per satu tidak tersedia".
-- Pertanyaan itu wajar dari seorang owner, dan jawabannya ada di basis data.
--
-- FUNGSI TERPISAH, BUKAN MENULIS ULANG ringkasan_asisten
--
-- ringkasan_asisten (migrasi 58) panjang dan sudah dipakai. Menulis ulang
-- seluruhnya hanya untuk menambah satu kunci membuat satu berkas lagi yang
-- dapat menimpa perbaikan yang lebih baru bila dijalankan belakangan (persis
-- kejadian owner_buat_akun_capster, lihat kepala migrasi 49). Fungsi baru ini
-- berdiri sendiri; Edge Function ai-asisten memanggil keduanya, dan bila
-- migrasi ini belum dijalankan asisten tetap menjawab dari ringkasan lama.
--
-- YANG IKUT DAN YANG TIDAK
--
-- Ikut: nomor nota, tanggal dan jam (WIB), metode bayar, total, diskon,
-- kapster, dan isi nota (layanan/produk beserta jumlahnya).
-- Tidak ikut: nama dan nomor telepon pelanggan. Asisten tidak memerlukannya
-- untuk menjawab soal operasional, dan data pelanggan tidak perlu singgah di
-- layanan AI pihak ketiga. Transaksi member hanya ditandai "member: true".
--
-- Tujuh puluh lima baris per hari tidak mungkin terjadi di toko ini, tetapi
-- batas 500 baris menjaga ukuran permintaan ke model tetap terkendali.
--
-- HANYA UNTUK SERVER, seperti ringkasan_asisten: dipanggil dengan kunci
-- layanan SESUDAH ai-asisten memastikan pemanggilnya owner.
-- ==============================================================================

CREATE OR REPLACE FUNCTION transaksi_asisten(p_hari_ini DATE)
RETURNS JSONB
LANGUAGE plpgsql STABLE SET search_path = public
AS $function$
BEGIN
    IF p_hari_ini IS NULL THEN
        RAISE EXCEPTION 'Tanggal hari ini wajib diisi.';
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(x ORDER BY x.tanggal DESC, x.jam DESC), '[]'::JSONB)
          FROM (
            SELECT t.business_date                                              AS tanggal,
                   to_char(t.created_at AT TIME ZONE 'Asia/Jakarta', 'HH24:MI') AS jam,
                   t.invoice_no                                                 AS nota,
                   t.payment_method::TEXT                                       AS metode,
                   t.final_amount                                               AS total,
                   COALESCE(t.discount_points, 0) + COALESCE(t.discount_manual, 0) AS diskon,
                   t.capster_name                                               AS kapster,
                   (t.member_id IS NOT NULL)                                    AS member,
                   (SELECT string_agg(i.service_name || ' x' || i.qty
                                      || ' (' || i.price::BIGINT || ')', ', ' ORDER BY i.created_at, i.service_name)
                      FROM transaction_items i WHERE i.transaction_id = t.id)   AS isi
              FROM transactions t
             WHERE t.business_date BETWEEN p_hari_ini - 59 AND p_hari_ini
             ORDER BY t.business_date DESC, t.created_at DESC
             LIMIT 500
          ) x
    );
END $function$;

REVOKE EXECUTE ON FUNCTION transaksi_asisten(DATE) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION transaksi_asisten(DATE) TO service_role;
