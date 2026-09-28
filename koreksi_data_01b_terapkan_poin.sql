-- =============================================================================
-- 01b · TERAPKAN — poin 7% menjadi 10%
--
-- JALANKAN 01a LEBIH DULU dan baca hasilnya. Skrip ini mengubah saldo poin
-- member sungguhan.
--
-- YANG DIUBAH, DAN MENGAPA BEGITU
--
--   1. loyalty_settings.earn_percent  ->  10
--      Supaya transaksi berikutnya memakai tarif baru.
--
--   2. transactions.points_earned     ->  angka 10%
--      Riwayat di kartu member membaca kolom ini, bukan buku besar. Tanpa
--      mengubahnya, saldo tertulis 7.000 sementara riwayat tetap berbunyi
--      "+4900 poin" — persis keluhan yang memulai semua ini.
--
--   3. point_ledger  <-  satu baris ADJUSTMENT per nota
--      Baris EARN aslinya TIDAK disentuh. Buku besarnya tetap jujur: 4.900
--      diperoleh pada tarif lama, 2.100 ditambahkan sebagai penyesuaian.
--      Menghapus jejak itu membuat pertanyaan "kenapa saldo saya berubah"
--      tidak lagi bisa dijawab enam bulan lagi.
--
--   4. members: saldo, poin seumur hidup, dan level dihitung ulang.
--
-- AMAN DIJALANKAN DUA KALI. Nota yang sudah punya baris ADJUSTMENT dengan
-- catatan yang sama dilewati, jadi tidak ada poin yang dobel.
--
-- PEMBULATAN. Poin baru dihitung sebagai floor(poin_lama * 10 / 7), bukan
-- dihitung ulang dari harga. Menghitung ulang menuntut penggolongan layanan
-- versus produk dan pembagian potongan persis seperti create_transaction —
-- satu langkah meleset, selisihnya ratusan poin.
--
-- Penskalaan diukur pada harga Rp 1 sampai Rp 2.000.000: 37% tepat sama,
-- sisanya meleset paling jauh DUA poin, dan SELALU ke bawah — tidak pernah
-- sekali pun memberi lebih daripada hitung ulang. Dua poin bernilai dua
-- rupiah, dan arah melesetnya berpihak pada toko, bukan sebaliknya.
-- =============================================================================

BEGIN;

-- ── 1 · Tarif untuk transaksi berikutnya ────────────────────────────────────
UPDATE loyalty_settings SET earn_percent = 10.00, updated_at = now();

-- ── 2 · Sesuaikan tiap nota yang belum pernah disesuaikan ───────────────────
DO $koreksi$
DECLARE
    r        RECORD;
    v_saldo  INT;
    v_nota   INT := 0;
    v_poin   INT := 0;
BEGIN
    FOR r IN
        SELECT t.id, t.member_id, t.points_earned,
               floor(t.points_earned * 10.0 / 7.0)::INT - t.points_earned AS tambahan
          FROM transactions t
         WHERE t.member_id IS NOT NULL
           AND t.points_earned > 0
           AND NOT EXISTS (SELECT 1 FROM point_ledger l
                            WHERE l.transaction_id = t.id
                              AND l.type  = 'ADJUSTMENT'
                              AND l.notes = 'Penyesuaian cashback 7% menjadi 10%')
         ORDER BY t.created_at
    LOOP
        CONTINUE WHEN r.tambahan <= 0;

        -- Saldo dan poin seumur hidup naik bersama: yang kedua menentukan level,
        -- dan level yang tidak ikut naik membuat kartunya bercerita dua hal.
        UPDATE members
           SET points_balance  = points_balance  + r.tambahan,
               lifetime_points = lifetime_points + r.tambahan
         WHERE id = r.member_id
        RETURNING points_balance INTO v_saldo;

        INSERT INTO point_ledger
               (member_id, transaction_id, type, points_amount, balance_after, notes)
        VALUES (r.member_id, r.id, 'ADJUSTMENT', r.tambahan, v_saldo,
                'Penyesuaian cashback 7% menjadi 10%');

        -- Kolom tampilan disamakan supaya riwayat di kartu member tidak
        -- bertentangan dengan saldonya.
        UPDATE transactions
           SET points_earned = points_earned + r.tambahan
         WHERE id = r.id;

        v_nota := v_nota + 1;
        v_poin := v_poin + r.tambahan;
    END LOOP;

    RAISE NOTICE 'Disesuaikan: % nota, % poin ditambahkan.', v_nota, v_poin;
END $koreksi$;

-- ── 3 · Level mengikuti poin seumur hidup yang baru ─────────────────────────
UPDATE members
   SET tier = compute_tier(lifetime_points)
 WHERE tier IS DISTINCT FROM compute_tier(lifetime_points);

COMMIT;


-- ── 4 · Hasil sesudah penerapan ─────────────────────────────────────────────
SELECT 'tarif poin' AS periksa, earn_percent::TEXT AS nilai FROM loyalty_settings
UNION ALL
SELECT 'nota disesuaikan',
       COUNT(*)::TEXT FROM point_ledger
 WHERE type = 'ADJUSTMENT' AND notes = 'Penyesuaian cashback 7% menjadi 10%'
UNION ALL
SELECT 'poin ditambahkan',
       COALESCE(SUM(points_amount), 0)::TEXT FROM point_ledger
 WHERE type = 'ADJUSTMENT' AND notes = 'Penyesuaian cashback 7% menjadi 10%'
UNION ALL
SELECT 'saldo cocok dengan buku besar',
       CASE WHEN NOT EXISTS (
              SELECT 1 FROM members m
               WHERE m.points_balance <> COALESCE(
                     (SELECT SUM(l.points_amount) FROM point_ledger l WHERE l.member_id = m.id), 0))
            THEN 'ya' ELSE 'TIDAK — laporkan ini' END;
