-- ==============================================================================
-- MIGRASI 33 - Ganti Capster Tanpa Menghapus Transaksi
--
-- Sampai sekarang, satu-satunya cara membetulkan kasir yang salah pilih
-- capster adalah menghapus notanya lalu memasukkan ulang. Itu menarik poin
-- member, dapat menurunkan levelnya, dan menghapus buku besar poinnya sampai
-- tidak bersisa satu baris pun. Harga yang terlalu mahal untuk kesalahan yang
-- tidak menyentuh uang sama sekali.
--
-- POIN MEMBER TIDAK DISENTUH
--
-- Poin milik member, bukan capster. Ikhsan tetap memperoleh poin yang sama
-- entah yang mencukur Cena atau Lukman. Yang berpindah hanyalah atribusi
-- omzet dan jumlah kepala, dan keduanya diturunkan dari kolom capster, bukan
-- disimpan sebagai angka tersendiri. Karena itu fungsi ini sama sekali tidak
-- menyentuh members, point_ledger, maupun tier.
--
-- DUA TEMPAT, SATU LANGKAH
--
-- Capster tercatat di transactions DAN di transaction_items. Mengubah satu
-- saja membuat dua layar menampilkan angka berbeda untuk orang yang sama:
-- dasbor capster membaca transaction_items, sementara laporan owner membaca
-- transactions. Keduanya diubah dalam satu transaksi basis data.
--
-- PER ITEM ATAU SEKALIGUS
--
-- POS sudah mendukung capster berbeda per item: potong sama Cena, cuci sama
-- Lukman. Karena itu p_item_id boleh diisi untuk memindahkan satu item saja.
-- Kalau dikosongkan, seluruh item pada nota itu berpindah, dan capster nota
-- ikut berubah. Kalau hanya sebagian item yang dipindahkan, capster pada
-- level nota dibiarkan menunjuk pemilik item terbanyak, sebab kolom itu hanya
-- ringkasan dan tidak boleh dipakai untuk menghitung bagi hasil.
-- ==============================================================================


-- ── Arsip perubahan ────────────────────────────────────────────────────────
-- Mengubah siapa yang dibayar adalah keputusan yang menyentuh uang orang.
-- Tanpa jejak, seorang capster yang omzetnya berpindah tidak punya cara
-- mengetahui bahwa itu terjadi, apalagi menanyakannya.
CREATE TABLE IF NOT EXISTS capster_edits (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL,
    invoice_no    VARCHAR(32),
    item_id       UUID,
    item_name     TEXT,
    dari_capster  VARCHAR(80),
    ke_capster    VARCHAR(80),
    nilai         NUMERIC(12,2),
    alasan        TEXT,
    diubah_oleh   UUID,
    diubah_pada   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE capster_edits ENABLE ROW LEVEL SECURITY;
-- Tanpa policy apa pun, tabel ini hanya terbaca lewat fungsi SECURITY DEFINER.

CREATE INDEX IF NOT EXISTS capster_edits_waktu ON capster_edits (diubah_pada DESC);


-- ── Fungsi utama ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION edit_transaction_capster(
    p_tx_id      UUID,
    p_capster_id UUID,
    p_alasan     TEXT DEFAULT NULL,
    p_item_id    UUID DEFAULT NULL
)
RETURNS TABLE (invoice_no VARCHAR, item_dipindah INT, dari_capster VARCHAR,
               ke_capster VARCHAR, nilai_dipindah NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_tx      transactions%ROWTYPE;
    v_baru    capsters%ROWTYPE;
    v_alasan  TEXT;
    v_jumlah  INT := 0;
    v_nilai   NUMERIC(12,2) := 0;
    v_dari    VARCHAR(80);
    v_utama   UUID;
    v_utama_n VARCHAR(80);
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh memindahkan capster.';
    END IF;

    v_alasan := NULLIF(btrim(COALESCE(p_alasan, '')), '');
    IF v_alasan IS NULL THEN
        RAISE EXCEPTION 'Alasan pemindahan wajib diisi.';
    END IF;

    SELECT * INTO v_tx FROM transactions t WHERE t.id = p_tx_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak ditemukan.'; END IF;

    SELECT * INTO v_baru FROM capsters c WHERE c.id = p_capster_id AND c.is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capster tujuan tidak dikenali atau sudah tidak aktif.';
    END IF;

    -- Item yang sudah menjadi milik capster tujuan tidak ikut diproses, supaya
    -- arsipnya tidak dipenuhi baris "dari Cena ke Cena".
    IF p_item_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM transaction_items i
                        WHERE i.id = p_item_id AND i.transaction_id = p_tx_id) THEN
            RAISE EXCEPTION 'Item itu bukan bagian dari nota ini.';
        END IF;
    END IF;

    -- Ringkasannya dihitung dari itemnya sendiri SEBELUM diubah. Membacanya
    -- kembali dari capster_edits sesudahnya akan menuntut penyaringan waktu,
    -- dan now() bernilai sama untuk seluruh baris dalam satu transaksi
    -- sehingga penyaring seperti itu ikut menangkap baris milik orang lain.
    SELECT COUNT(*)::INT, COALESCE(SUM(i.price), 0),
           string_agg(DISTINCT i.capster_name, ', ')
      INTO v_jumlah, v_nilai, v_dari
      FROM transaction_items i
     WHERE i.transaction_id = p_tx_id
       AND (p_item_id IS NULL OR i.id = p_item_id)
       AND i.capster_id IS DISTINCT FROM p_capster_id;

    IF v_jumlah = 0 THEN
        RAISE EXCEPTION 'Tidak ada yang berubah: item itu sudah milik %.', v_baru.name;
    END IF;

    INSERT INTO capster_edits (transaction_id, invoice_no, item_id, item_name,
                               dari_capster, ke_capster, nilai, alasan, diubah_oleh)
    SELECT v_tx.id, v_tx.invoice_no, i.id, i.service_name,
           i.capster_name, v_baru.name, i.price, v_alasan, auth.uid()
      FROM transaction_items i
     WHERE i.transaction_id = p_tx_id
       AND (p_item_id IS NULL OR i.id = p_item_id)
       AND i.capster_id IS DISTINCT FROM p_capster_id;

    UPDATE transaction_items i
       SET capster_id = p_capster_id, capster_name = v_baru.name
     WHERE i.transaction_id = p_tx_id
       AND (p_item_id IS NULL OR i.id = p_item_id)
       AND i.capster_id IS DISTINCT FROM p_capster_id;

    -- Kolom capster pada nota hanyalah ringkasan. Diisi ulang dari pemilik
    -- item terbanyak supaya tidak pernah menunjuk orang yang sudah tidak
    -- mengerjakan apa pun pada nota itu.
    SELECT i.capster_id, i.capster_name INTO v_utama, v_utama_n
      FROM transaction_items i
     WHERE i.transaction_id = p_tx_id
     GROUP BY i.capster_id, i.capster_name
     ORDER BY COUNT(*) DESC, SUM(i.price) DESC
     LIMIT 1;

    UPDATE transactions t
       SET capster_id = COALESCE(v_utama, p_capster_id),
           capster_name = COALESCE(v_utama_n, v_baru.name)
     WHERE t.id = p_tx_id;

    RETURN QUERY SELECT v_tx.invoice_no, v_jumlah, v_dari,
                        v_baru.name::VARCHAR, v_nilai;
END $function$;

REVOKE EXECUTE ON FUNCTION edit_transaction_capster(UUID, UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION edit_transaction_capster(UUID, UUID, TEXT, UUID) TO authenticated;


-- ── Riwayat pemindahan untuk layar owner ───────────────────────────────────
CREATE OR REPLACE FUNCTION owner_capster_edits(p_limit INT DEFAULT 100)
RETURNS TABLE (waktu TIMESTAMPTZ, invoice_no VARCHAR, item_name TEXT,
               dari_capster VARCHAR, ke_capster VARCHAR, nilai NUMERIC, alasan TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT ce.diubah_pada, ce.invoice_no, ce.item_name,
           ce.dari_capster, ce.ke_capster, ce.nilai, ce.alasan
      FROM capster_edits ce
     WHERE is_owner()
     ORDER BY ce.diubah_pada DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500)
$function$;

REVOKE EXECUTE ON FUNCTION owner_capster_edits(INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_capster_edits(INT) TO authenticated;
