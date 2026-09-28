-- =============================================================================
-- 45 · ID TRANSAKSI PADA DAFTAR PANTAU QRIS
--
-- Panel "QRIS Belum Terkonfirmasi" memberi tahu nota mana yang tersimpan tanpa
-- jejak pemeriksaan, tetapi pemiliknya lalu harus mencarinya lagi satu per satu
-- di tabel bawah untuk menghapusnya. Jarak itu yang membuat daftar temuan
-- berhenti ditindaklanjuti.
--
-- Yang ditambahkan hanya kolom id pada hasilnya, supaya panel itu dapat
-- memanggil delete_transaction() yang sudah ada. Aturan penghapusannya sendiri
-- tidak disentuh sedikit pun: tetap milik owner, tetap menarik poin member,
-- tetap masuk arsip beserta alasannya.
--
-- CREATE OR REPLACE tidak dapat mengubah RETURNS TABLE, jadi fungsinya
-- dijatuhkan lebih dulu. DROP ikut menghapus hak aksesnya, maka REVOKE dan
-- GRANT ditulis ulang di bawah — tanpa itu fungsinya kembali terbuka ke
-- bawaan Supabase.
-- =============================================================================

DROP FUNCTION IF EXISTS owner_qris_belum_konfirmasi(DATE);

CREATE OR REPLACE FUNCTION owner_qris_belum_konfirmasi(p_tanggal DATE DEFAULT NULL)
RETURNS TABLE (id UUID, invoice_no VARCHAR, created_at TIMESTAMPTZ,
               capster_name VARCHAR, member_name VARCHAR,
               final_amount NUMERIC, payment_ref VARCHAR)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membaca daftar ini.';
    END IF;

    RETURN QUERY
    SELECT t.id, t.invoice_no, t.created_at, t.capster_name,
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
