-- ==============================================================================
-- MIGRASI 22 — Audit Mutasi Poin untuk Owner
--
-- KEADAAN SEBELUMNYA
--
-- point_ledger sudah mencatat setiap pergerakan poin sejak migrasi 05, dan
-- member_ledger() sudah ada untuk membacanya. Tetapi member_ledger menerima
-- satu nomor telepon: untuk mengaudit, owner harus membuka member satu per
-- satu. Tidak ada satu pun layar yang memperlihatkan pergerakan poin secara
-- menyeluruh, sehingga pertanyaan paling wajar — "siapa memberi poin sebanyak
-- itu kemarin?" — tidak punya jawaban.
--
-- KENAPA NAMA KASIR IKUT DIBAWA
--
-- Poin lahir dari transaksi, dan transaksi punya kasir. Tanpa kolom itu,
-- audit hanya bisa melihat BAHWA poin bertambah, bukan SIAPA yang
-- menambahkannya — padahal justru itu satu-satunya alasan orang membuka
-- layar audit. Nama kasir diambil lewat transaction_id yang memang sudah
-- tersimpan di tiap baris buku besar.
--
-- YANG TIDAK TERLIHAT DI SINI, DAN ITU DISENGAJA
--
-- delete_transaction() menghapus baris buku besar milik transaksi yang
-- dihapus, bukan menulis baris pembalikan. Itu menjaga kolom saldo_sesudah
-- tetap masuk akal terhadap barisnya sendiri, tetapi berarti poin yang pernah
-- terbit lalu ditarik tidak muncul di layar ini. Jejaknya tidak hilang — ia
-- pindah ke arsip deleted_transactions beserta alasan penghapusannya. Panel
-- di dashboard menyebutkan hal ini apa adanya supaya angka di sini tidak
-- dikira riwayat yang lengkap.
-- ==============================================================================


-- ==============================================================================
-- owner_point_audit — seluruh pergerakan poin dalam satu bulan
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_point_audit(
    p_bulan date DEFAULT NULL,
    p_tipe  TEXT DEFAULT NULL,
    p_cari  TEXT DEFAULT NULL
)
RETURNS TABLE (
    waktu        timestamptz,
    member_name  VARCHAR,
    member_phone VARCHAR,
    member_code  VARCHAR,
    tipe         VARCHAR,
    poin         INT,
    saldo_sesudah INT,
    invoice_no   VARCHAR,
    kasir        VARCHAR,
    capster      VARCHAR,
    catatan      TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_awal date; v_cari TEXT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuka audit poin.';
    END IF;

    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    v_cari := NULLIF(btrim(COALESCE(p_cari, '')), '');

    RETURN QUERY
    SELECT pl.created_at,
           m.name, m.phone_wa, m.member_code,
           pl.type, pl.points_amount, pl.balance_after,
           t.invoice_no, t.cashier_name, t.capster_name,
           pl.notes
      FROM point_ledger pl
      JOIN members m       ON m.id = pl.member_id
      LEFT JOIN transactions t ON t.id = pl.transaction_id
     WHERE (pl.created_at AT TIME ZONE 'Asia/Jakarta')::date >= v_awal
       AND (pl.created_at AT TIME ZONE 'Asia/Jakarta')::date < (v_awal + interval '1 month')
       AND (p_tipe IS NULL OR p_tipe = '' OR pl.type = p_tipe)
       AND (v_cari IS NULL
            OR m.name       ILIKE '%' || v_cari || '%'
            OR m.phone_wa   ILIKE '%' || v_cari || '%'
            OR m.member_code ILIKE '%' || v_cari || '%'
            OR COALESCE(t.invoice_no, '')  ILIKE '%' || v_cari || '%'
            OR COALESCE(t.cashier_name, '') ILIKE '%' || v_cari || '%')
     ORDER BY pl.created_at DESC
     LIMIT 1000;
END $function$;

GRANT EXECUTE ON FUNCTION owner_point_audit(date, TEXT, TEXT) TO authenticated;


-- ==============================================================================
-- owner_point_summary — ringkasan sebulan
--
-- saldo_beredar sengaja dihitung dari saldo member yang berlaku sekarang,
-- bukan dijumlahkan dari mutasi bulan ini. Ia menjawab pertanyaan yang
-- berbeda: berapa banyak poin yang masih dipegang pelanggan dan suatu saat
-- akan ditagihkan sebagai potongan. Angka itu tidak mengenal batas bulan.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_point_summary(p_bulan date DEFAULT NULL)
RETURNS TABLE (
    poin_terbit    INT,
    poin_ditukar   INT,
    poin_bonus     INT,
    jumlah_mutasi  INT,
    saldo_beredar  INT,
    nilai_beredar  NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v_awal date; v_nilai INT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membuka audit poin.';
    END IF;

    v_awal := date_trunc('month', COALESCE(p_bulan, jakarta_today()))::date;
    SELECT ls.rupiah_per_point_redeem INTO v_nilai FROM loyalty_settings ls LIMIT 1;

    RETURN QUERY
    SELECT
        COALESCE(SUM(pl.points_amount) FILTER (WHERE pl.type = 'EARN'), 0)::INT,
        -- Baris REDEEM tersimpan negatif; dibalik supaya terbaca sebagai jumlah
        COALESCE(-SUM(pl.points_amount) FILTER (WHERE pl.type = 'REDEEM'), 0)::INT,
        COALESCE(SUM(pl.points_amount) FILTER (WHERE pl.type = 'BONUS'), 0)::INT,
        COUNT(*)::INT,
        (SELECT COALESCE(SUM(m.points_balance), 0)::INT FROM members m),
        -- SUM() atas kolom integer menghasilkan bigint; tanpa cast, tanda
        -- tangan fungsi tidak cocok dan PostgREST menolak seluruh panggilan.
        (SELECT (COALESCE(SUM(m.points_balance), 0) * COALESCE(v_nilai, 0))::NUMERIC FROM members m)
      FROM point_ledger pl
     WHERE (pl.created_at AT TIME ZONE 'Asia/Jakarta')::date >= v_awal
       AND (pl.created_at AT TIME ZONE 'Asia/Jakarta')::date < (v_awal + interval '1 month');
END $function$;

GRANT EXECUTE ON FUNCTION owner_point_summary(date) TO authenticated;
