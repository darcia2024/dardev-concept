-- ==============================================================================
-- MIGRASI 57 - Stok produk (Add-on AI, fitur 3 bagian stok)
--
-- Penawaran #INV/BU-AI/2026/019, fitur 3: data belanja dan stok masuk ke
-- sistem tanpa diketik ulang. Belanja sudah ditangani struk (migrasi 53).
-- Migrasi ini menambahkan stok: berapa sisa tiap produk retail, dari mana
-- angkanya, dan produk mana yang menipis.
--
-- STOK ADALAH JUMLAH MUTASI, BUKAN ANGKA YANG DITIMPA
--
-- Tidak ada kolom "stok" yang diubah-ubah. Setiap perubahan dicatat sebagai
-- satu baris di stok_mutasi, dan stok adalah jumlah seluruh barisnya. Angka
-- yang ditimpa tidak dapat dijelaskan ketika selisih ditemukan; deretan
-- mutasi dapat: "masuk 24 dari struk Toko Jaya, terjual 3, hitung fisik
-- 20 — selisih -1".
--
-- YANG BERJALAN SENDIRI, LEWAT TRIGGER
--
--   · Penjualan produk di POS mengurangi stok.
--   · Transaksi yang dihapus owner mengembalikannya.
--   · Barang belanja (struk) yang owner tautkan ke produk katalog menambah
--     stok; pengeluaran yang dihapus menariknya kembali.
--
-- Sengaja lewat trigger, BUKAN dengan menulis ulang create_transaction atau
-- owner_simpan_pengeluaran. create_transaction sudah ditulis ulang di banyak
-- migrasi; versi kesekian yang menyertakan stok adalah satu lagi berkas yang
-- dapat menimpa perbaikan yang lebih baru bila dijalankan belakangan —
-- persis kejadian owner_buat_akun_capster (lihat kepala migrasi 49).
-- Trigger tetap bekerja versi fungsi mana pun yang sedang aktif.
--
-- STOK AWAL DARI HITUNG FISIK, BUKAN DARI MASA LALU
--
-- Penjualan sebelum migrasi ini TIDAK dihitung mundur. Stok yang ada di rak
-- hari ini tidak pernah tercatat, jadi mengurangkan penjualan lama dari nol
-- hanya menghasilkan angka negatif yang tidak berarti. Owner memulai dengan
-- satu kali hitung fisik; sampai itu terjadi, produknya ditandai "belum
-- dihitung" alih-alih menampilkan angka yang terlihat pasti padahal tidak.
--
-- SATU OUTLET
--
-- Stok dihitung per produk, tidak per outlet. outlet_aktif() (migrasi 36)
-- menolak bila ada lebih dari satu outlet aktif, jadi hari ini memang hanya
-- ada satu rak. Bila cabang kedua dibuka, stok perlu dipecah per outlet.
-- ==============================================================================


-- ── 01 Batas menipis per produk ────────────────────────────────────────────
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS stok_minimum NUMERIC(12, 3) NOT NULL DEFAULT 0
    CHECK (stok_minimum >= 0);


-- ── 02 Mutasi ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stok_mutasi (
    id          BIGSERIAL PRIMARY KEY,
    product_id  UUID NOT NULL REFERENCES products_hpp(id) ON DELETE CASCADE,
    jenis       TEXT NOT NULL CHECK (jenis IN (
                    'hitung',       -- hitung fisik; qty_delta = hasil hitung - stok sebelumnya
                    'masuk',        -- barang datang, diketik owner
                    'keluar',       -- rusak, hilang, dipakai sendiri
                    'belanja',      -- dari baris struk yang ditautkan ke produk
                    'batal_belanja',
                    'jual',         -- dari POS
                    'batal_jual'    -- transaksi dihapus owner
                )),
    qty_delta   NUMERIC(12, 3) NOT NULL,
    -- Untuk 'hitung': angka yang benar-benar dihitung di rak, supaya riwayat
    -- dapat menyebut "dihitung 20" dan bukan hanya "-1".
    qty_hitung  NUMERIC(12, 3),
    sumber      TEXT NOT NULL DEFAULT 'manual' CHECK (sumber IN ('manual', 'ai', 'pos', 'struk')),
    -- Baris asal (transaction_items.id atau pengeluaran_item.id). Bukan
    -- foreign key: barisnya memang dihapus saat transaksi atau pengeluaran
    -- dibatalkan, dan mutasi pembatalannya justru harus tetap ada.
    ref_id      UUID,
    catatan     TEXT,
    dibuat_oleh UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stok_mutasi_produk ON stok_mutasi(product_id, created_at DESC);

ALTER TABLE stok_mutasi ENABLE ROW LEVEL SECURITY;
-- Owner hanya membaca langsung. Semua tulisan lewat fungsi dan trigger di
-- bawah, supaya mutasi tidak dapat disunting diam-diam dari peramban.
DROP POLICY IF EXISTS owner_baca ON stok_mutasi;
CREATE POLICY owner_baca ON stok_mutasi FOR SELECT TO authenticated USING (is_owner());


-- ── 03 Penjualan dan pembatalannya ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION stok_dari_penjualan()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.item_type = 'produk' AND NEW.product_id IS NOT NULL THEN
            INSERT INTO stok_mutasi (product_id, jenis, qty_delta, sumber, ref_id, catatan)
            VALUES (NEW.product_id, 'jual', -NEW.qty, 'pos', NEW.id, NEW.service_name);
        END IF;
        RETURN NEW;
    END IF;

    -- DELETE: transaksi dihapus owner (delete_transaction, migrasi 12). Hanya baris
    -- yang dulu benar-benar mengurangi stok yang dikembalikan, sehingga
    -- penjualan dari sebelum migrasi ini tidak menambah stok dari udara.
    IF OLD.item_type = 'produk' AND OLD.product_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM stok_mutasi m WHERE m.ref_id = OLD.id AND m.jenis = 'jual')
       AND EXISTS (SELECT 1 FROM products_hpp p WHERE p.id = OLD.product_id) THEN
        INSERT INTO stok_mutasi (product_id, jenis, qty_delta, sumber, ref_id, catatan)
        VALUES (OLD.product_id, 'batal_jual', OLD.qty, 'pos', OLD.id, 'Transaksi dihapus: ' || OLD.service_name);
    END IF;
    RETURN OLD;
END $function$;

DROP TRIGGER IF EXISTS stok_dari_penjualan ON transaction_items;
CREATE TRIGGER stok_dari_penjualan
    AFTER INSERT OR DELETE ON transaction_items
    FOR EACH ROW EXECUTE FUNCTION stok_dari_penjualan();


-- ── 04 Belanja dari struk dan pembatalannya ────────────────────────────────
CREATE OR REPLACE FUNCTION stok_dari_belanja()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.produk_id IS NOT NULL THEN
            INSERT INTO stok_mutasi (product_id, jenis, qty_delta, sumber, ref_id, catatan, dibuat_oleh)
            VALUES (NEW.produk_id, 'belanja', NEW.qty, 'struk', NEW.id, NEW.nama, auth.uid());
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.produk_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM stok_mutasi m WHERE m.ref_id = OLD.id AND m.jenis = 'belanja')
       AND EXISTS (SELECT 1 FROM products_hpp p WHERE p.id = OLD.produk_id) THEN
        INSERT INTO stok_mutasi (product_id, jenis, qty_delta, sumber, ref_id, catatan, dibuat_oleh)
        VALUES (OLD.produk_id, 'batal_belanja', -OLD.qty, 'struk', OLD.id, 'Pengeluaran dihapus: ' || OLD.nama, auth.uid());
    END IF;
    RETURN OLD;
END $function$;

DROP TRIGGER IF EXISTS stok_dari_belanja ON pengeluaran_item;
CREATE TRIGGER stok_dari_belanja
    AFTER INSERT OR DELETE ON pengeluaran_item
    FOR EACH ROW EXECUTE FUNCTION stok_dari_belanja();


-- ── 05 Daftar stok ─────────────────────────────────────────────────────────
-- status: 'belum' (belum pernah dihitung fisik), 'habis' (<= 0), 'menipis'
-- (<= minimum), 'aman'.
CREATE OR REPLACE FUNCTION owner_stok_list()
RETURNS TABLE (product_id UUID, name VARCHAR, is_active BOOLEAN, stok NUMERIC,
               stok_minimum NUMERIC, terakhir_dihitung TIMESTAMPTZ, status TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT p.id, p.name, p.is_active, s.stok, p.stok_minimum, s.terakhir_dihitung,
           CASE WHEN s.terakhir_dihitung IS NULL THEN 'belum'
                WHEN s.stok <= 0 THEN 'habis'
                WHEN s.stok <= p.stok_minimum THEN 'menipis'
                ELSE 'aman' END
      FROM products_hpp p
      CROSS JOIN LATERAL (
          SELECT COALESCE(sum(m.qty_delta), 0) AS stok,
                 max(m.created_at) FILTER (WHERE m.jenis = 'hitung') AS terakhir_dihitung
            FROM stok_mutasi m WHERE m.product_id = p.id
      ) s
     WHERE is_owner()
     ORDER BY p.is_active DESC, p.sort_order, p.name
$function$;

REVOKE EXECUTE ON FUNCTION owner_stok_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_stok_list() TO authenticated;


-- ── 06 Mencatat hasil yang sudah diperiksa owner ───────────────────────────
-- p_items: [{ "product_id": "...", "jenis": "hitung"|"masuk"|"keluar",
--             "qty": 12, "catatan": "..." }, ...]
-- Satu transaksi: semua baris masuk atau tidak sama sekali. Untuk 'hitung',
-- qty adalah hasil hitung di rak dan selisihnya dihitung DI SINI terhadap
-- stok saat itu — bukan oleh peramban, yang angkanya bisa sudah basi bila
-- kasir menjual sesuatu sementara owner menghitung.
CREATE OR REPLACE FUNCTION owner_stok_catat(p_items JSONB, p_sumber TEXT)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_item   JSONB;
    v_urut   INT := 0;
    v_produk UUID;
    v_jenis  TEXT;
    v_qty    NUMERIC;
    v_stok   NUMERIC;
    v_sumber TEXT := CASE WHEN p_sumber = 'ai' THEN 'ai' ELSE 'manual' END;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mencatat stok.';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Isi minimal satu baris stok.';
    END IF;
    IF jsonb_array_length(p_items) > 200 THEN
        RAISE EXCEPTION 'Terlalu banyak baris sekaligus (maksimal 200).';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_urut   := v_urut + 1;
        v_produk := CASE WHEN v_item->>'product_id' ~ '^[0-9a-fA-F-]{36}$'
                         THEN (v_item->>'product_id')::UUID END;
        v_jenis  := v_item->>'jenis';
        v_qty    := CASE WHEN v_item->>'qty' ~ '^-?[0-9]+(\.[0-9]+)?$'
                         THEN (v_item->>'qty')::NUMERIC END;

        IF v_produk IS NULL OR NOT EXISTS (SELECT 1 FROM products_hpp p WHERE p.id = v_produk) THEN
            RAISE EXCEPTION 'Baris ke-%: pilih produknya dulu.', v_urut;
        END IF;
        IF v_jenis NOT IN ('hitung', 'masuk', 'keluar') THEN
            RAISE EXCEPTION 'Baris ke-%: jenis harus hitung, masuk, atau keluar.', v_urut;
        END IF;
        IF v_qty IS NULL OR v_qty < 0 OR (v_jenis <> 'hitung' AND v_qty = 0) THEN
            RAISE EXCEPTION 'Baris ke-%: jumlah tidak sah.', v_urut;
        END IF;

        IF v_jenis = 'hitung' THEN
            -- Dikunci supaya dua hitungan atas produk yang sama tidak saling
            -- membaca stok yang sama lalu sama-sama menulis selisih.
            PERFORM 1 FROM products_hpp WHERE id = v_produk FOR UPDATE;
            SELECT COALESCE(sum(qty_delta), 0) INTO v_stok FROM stok_mutasi WHERE product_id = v_produk;
            INSERT INTO stok_mutasi (product_id, jenis, qty_delta, qty_hitung, sumber, catatan, dibuat_oleh)
            VALUES (v_produk, 'hitung', v_qty - v_stok, v_qty, v_sumber,
                    NULLIF(left(btrim(COALESCE(v_item->>'catatan', '')), 300), ''), auth.uid());
        ELSE
            INSERT INTO stok_mutasi (product_id, jenis, qty_delta, sumber, catatan, dibuat_oleh)
            VALUES (v_produk, v_jenis, CASE WHEN v_jenis = 'keluar' THEN -v_qty ELSE v_qty END, v_sumber,
                    NULLIF(left(btrim(COALESCE(v_item->>'catatan', '')), 300), ''), auth.uid());
        END IF;
    END LOOP;

    RETURN v_urut;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_stok_catat(JSONB, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_stok_catat(JSONB, TEXT) TO authenticated;


-- ── 07 Riwayat satu produk ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_stok_riwayat(p_product_id UUID, p_limit INT DEFAULT 30)
RETURNS TABLE (created_at TIMESTAMPTZ, jenis TEXT, qty_delta NUMERIC, qty_hitung NUMERIC,
               sumber TEXT, catatan TEXT, stok_sesudah NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT r.created_at, r.jenis, r.qty_delta, r.qty_hitung, r.sumber, r.catatan, r.stok_sesudah
      FROM (
          SELECT m.*, sum(m.qty_delta) OVER (ORDER BY m.created_at, m.id) AS stok_sesudah
            FROM stok_mutasi m
           WHERE m.product_id = p_product_id
      ) r
     WHERE is_owner()
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 200)
$function$;

REVOKE EXECUTE ON FUNCTION owner_stok_riwayat(UUID, INT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_stok_riwayat(UUID, INT) TO authenticated;


-- ── 08 Batas menipis ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_set_stok_minimum(p_product_id UUID, p_minimum NUMERIC)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengubah batas stok.';
    END IF;
    IF p_minimum IS NULL OR p_minimum < 0 THEN
        RAISE EXCEPTION 'Batas minimum tidak sah.';
    END IF;
    UPDATE products_hpp SET stok_minimum = p_minimum WHERE id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produk tidak ditemukan.';
    END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_set_stok_minimum(UUID, NUMERIC) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_set_stok_minimum(UUID, NUMERIC) TO authenticated;
