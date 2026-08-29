-- ==============================================================================
-- MIGRASI 15 — Bersihkan Seluruh Data Uji  (BELUM DITERAPKAN)
--
-- Berkas ini SENGAJA belum dijalankan. Isinya satu fungsi yang menghapus
-- seluruh data operasional dalam satu panggilan, dan itu jenis kemampuan yang
-- sebaiknya dipasang secara sadar oleh pemiliknya sendiri, bukan menyelip di
-- antara migrasi lain.
--
-- Jalankan lewat SQL Editor di dashboard Supabase bila memang diinginkan.
-- ==============================================================================

-- ==============================================================================
-- 5. BERSIHKAN SELURUH DATA UJI
--
-- Ini yang dibutuhkan pada hari pemasangan: menyapu semua yang terjadi selama
-- percobaan supaya hari pertama benar-benar dimulai dari nol, termasuk
-- mengembalikan nomor nota ke 001.
--
-- Yang DISAPU  : transaksi, item, buku besar poin, member, klaim reward,
--                setoran kas, absensi, penghitung nota, dan seluruh arsip.
-- Yang DIJAGA  : layanan, produk, capster, kasir beserta PIN-nya, outlet,
--                aturan poin, tier, dan aturan kerja — semua itu master data
--                yang justru sudah disiapkan, bukan hasil percobaan.
--
-- Menuntut kalimat konfirmasi yang harus diketik persis. Fungsi sekali panggil
-- yang menyapu satu toko tidak boleh bisa terpicu oleh klik yang ragu-ragu.
-- ==============================================================================
CREATE OR REPLACE FUNCTION reset_test_data(p_konfirmasi TEXT)
RETURNS TABLE (tabel TEXT, baris_terhapus BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_n BIGINT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh membersihkan data.';
    END IF;
    IF COALESCE(p_konfirmasi, '') <> 'HAPUS SEMUA DATA UJI' THEN
        RAISE EXCEPTION 'Konfirmasi tidak cocok. Ketik persis: HAPUS SEMUA DATA UJI';
    END IF;

    -- Urutan mengikuti ketergantungan: anak lebih dulu, induk belakangan.
    DELETE FROM reward_claims;      GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'reward_claims';       baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM point_ledger;       GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'point_ledger';        baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM transaction_items;  GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'transaction_items';   baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM transactions;       GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'transactions';        baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM members;            GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'members';             baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM cash_closings;      GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'cash_closings';       baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM attendances;        GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'attendances';         baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM leave_requests;     GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'leave_requests';      baris_terhapus := v_n; RETURN NEXT;

    -- Nomor nota kembali ke 001 pada hari pertama
    DELETE FROM invoice_counters;   GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'invoice_counters';    baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM pin_attempts;       GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'pin_attempts';        baris_terhapus := v_n; RETURN NEXT;

    -- Arsip ikut disapu: setelah reset, tidak ada lagi yang perlu dijelaskan.
    DELETE FROM deleted_transactions; GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'deleted_transactions';  baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM deleted_attendances;  GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'deleted_attendances';   baris_terhapus := v_n; RETURN NEXT;

    DELETE FROM deleted_members;      GET DIAGNOSTICS v_n = ROW_COUNT;
    tabel := 'deleted_members';       baris_terhapus := v_n; RETURN NEXT;

    RETURN;
END $$;

GRANT EXECUTE ON FUNCTION reset_test_data(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION reset_test_data(TEXT) FROM anon;
