-- ==============================================================================
-- MIGRASI 53 - Pengeluaran toko dari foto struk (Add-on AI, fitur 1)
--
-- Penawaran #INV/BU-AI/2026/019, fitur 1: owner memotret struk belanja
-- kulakan, AI membaca barang, jumlah, tanggal, dan total, lalu tercatat
-- sebagai pengeluaran dan ikut memperbarui harga modal (HPP) produk.
--
-- AI MEMBACA, OWNER YANG MENYIMPAN
--
-- Edge Function ai-struk hanya MENGEMBALIKAN hasil bacaan. Tidak ada satu baris
-- pun yang ditulis ke pembukuan sebelum owner melihatnya, membetulkannya bila
-- perlu, lalu menekan Simpan. Struk yang kusut, tulisan tangan di nota warung,
-- atau angka yang terbaca 8 padahal 3 adalah keadaan biasa, bukan
-- pengecualian — dan pengeluaran yang salah tercatat lebih merusak daripada
-- pengeluaran yang harus diketik sendiri, sebab ia terlihat seperti fakta.
--
-- Karena itu fungsi penyimpan di bawah tidak tahu dan tidak peduli apakah
-- angkanya datang dari AI atau diketik owner. Kolom sumber hanya catatan.
--
-- HPP DIPERBARUI HANYA UNTUK BARIS YANG DITAUTKAN OWNER
--
-- Nama barang di struk ("POMADE MRS 80G") jarang sama dengan nama produk di
-- katalog ("Matte Clay Pomade"). Menebak pasangannya lalu mengubah harga modal
-- diam-diam akan merusak laporan laba tanpa ada yang menyadarinya. Maka harga
-- modal hanya berubah untuk baris yang owner sendiri tautkan ke sebuah produk.
--
-- BATAS PEMAKAIAN HARIAN
--
-- Setiap foto yang dibaca ditagih ke akun API pengembang. ai_pemakaian
-- mencatat tiap panggilan beserta token-nya, dan Edge Function menolak
-- panggilan berikutnya bila batas harian sudah tercapai. Batasnya diatur
-- lewat secret BATAS_STRUK_HARIAN di Edge Function, bukan di sini, supaya
-- dapat diubah tanpa migrasi.
-- ==============================================================================


-- ── 01 Pengeluaran ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pengeluaran (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tanggal     DATE NOT NULL,
    toko        VARCHAR(150),
    total       NUMERIC(14, 2) NOT NULL CHECK (total >= 0),
    catatan     TEXT,
    sumber      TEXT NOT NULL DEFAULT 'manual' CHECK (sumber IN ('manual', 'struk_ai')),
    dibuat_oleh UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pengeluaran_tanggal ON pengeluaran(tanggal DESC);

CREATE TABLE IF NOT EXISTS pengeluaran_item (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pengeluaran_id UUID NOT NULL REFERENCES pengeluaran(id) ON DELETE CASCADE,
    nama           VARCHAR(200) NOT NULL,
    qty            NUMERIC(12, 3) NOT NULL CHECK (qty > 0),
    harga_satuan   NUMERIC(14, 2) NOT NULL CHECK (harga_satuan >= 0),
    subtotal       NUMERIC(14, 2) NOT NULL CHECK (subtotal >= 0),
    -- Produk katalog yang owner tautkan ke baris ini. NULL untuk barang yang
    -- bukan barang jual: kopi, deterjen, handuk, pisau cukur.
    produk_id      UUID REFERENCES products_hpp(id) ON DELETE SET NULL,
    urutan         INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_pengeluaran_item_induk ON pengeluaran_item(pengeluaran_id);

ALTER TABLE pengeluaran      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pengeluaran_item ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS owner_all ON pengeluaran;
CREATE POLICY owner_all ON pengeluaran
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
DROP POLICY IF EXISTS owner_all ON pengeluaran_item;
CREATE POLICY owner_all ON pengeluaran_item
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());


-- ── 02 Catatan pemakaian AI ────────────────────────────────────────────────
-- Hanya Edge Function (service_role) yang menulis ke sini. Owner boleh
-- membaca, supaya biaya bulanannya tidak pernah menjadi kejutan.
CREATE TABLE IF NOT EXISTS ai_pemakaian (
    id            BIGSERIAL PRIMARY KEY,
    fitur         TEXT NOT NULL,
    berhasil      BOOLEAN NOT NULL,
    model         TEXT,
    input_tokens  INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    pemanggil     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    keterangan    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_pemakaian_hari ON ai_pemakaian(fitur, created_at DESC);

ALTER TABLE ai_pemakaian ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS owner_baca ON ai_pemakaian;
CREATE POLICY owner_baca ON ai_pemakaian FOR SELECT TO authenticated USING (is_owner());


-- ── 03 Menyimpan hasil yang sudah diperiksa owner ──────────────────────────
-- Satu transaksi: kepala, seluruh baris, dan pembaruan harga modal masuk
-- bersama atau tidak sama sekali. Pengeluaran tanpa barisnya, atau harga
-- modal yang berubah untuk pengeluaran yang gagal tersimpan, sama-sama
-- meninggalkan pembukuan yang tidak dapat dijelaskan.
CREATE OR REPLACE FUNCTION owner_simpan_pengeluaran(
    p_tanggal DATE,
    p_toko    TEXT,
    p_total   NUMERIC,
    p_catatan TEXT,
    p_sumber  TEXT,
    p_items   JSONB
)
RETURNS TABLE (pengeluaran_id UUID, jml_item INT, hpp_diperbarui INT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_id     UUID;
    v_item   JSONB;
    v_urut   INT := 0;
    v_hpp    INT := 0;
    v_nama   TEXT;
    v_qty    NUMERIC;
    v_harga  NUMERIC;
    v_sub    NUMERIC;
    v_produk UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mencatat pengeluaran.';
    END IF;
    IF p_tanggal IS NULL THEN
        RAISE EXCEPTION 'Tanggal belanja wajib diisi.';
    END IF;
    IF p_tanggal > jakarta_today() THEN
        RAISE EXCEPTION 'Tanggal belanja tidak boleh di masa depan.';
    END IF;
    IF p_total IS NULL OR p_total < 0 THEN
        RAISE EXCEPTION 'Total belanja tidak sah.';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Isi minimal satu barang.';
    END IF;

    INSERT INTO pengeluaran (tanggal, toko, total, catatan, sumber, dibuat_oleh)
    VALUES (p_tanggal, NULLIF(btrim(COALESCE(p_toko, '')), ''), p_total,
            NULLIF(btrim(COALESCE(p_catatan, '')), ''),
            CASE WHEN p_sumber = 'struk_ai' THEN 'struk_ai' ELSE 'manual' END,
            auth.uid())
    RETURNING id INTO v_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_urut  := v_urut + 1;
        v_nama  := btrim(COALESCE(v_item->>'nama', ''));
        v_qty   := NULLIF(v_item->>'qty', '')::NUMERIC;
        v_harga := NULLIF(v_item->>'harga_satuan', '')::NUMERIC;
        v_sub   := NULLIF(v_item->>'subtotal', '')::NUMERIC;
        v_produk := NULLIF(v_item->>'produk_id', '')::UUID;

        IF v_nama = '' THEN
            RAISE EXCEPTION 'Barang ke-% belum bernama.', v_urut;
        END IF;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Jumlah "%" harus lebih dari nol.', v_nama;
        END IF;
        IF v_harga IS NULL OR v_harga < 0 THEN
            RAISE EXCEPTION 'Harga satuan "%" tidak sah.', v_nama;
        END IF;
        v_sub := COALESCE(v_sub, v_qty * v_harga);

        IF v_produk IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM products_hpp p WHERE p.id = v_produk) THEN
            RAISE EXCEPTION 'Produk yang ditautkan ke "%" tidak ditemukan.', v_nama;
        END IF;

        INSERT INTO pengeluaran_item (pengeluaran_id, nama, qty, harga_satuan, subtotal, produk_id, urutan)
        VALUES (v_id, v_nama, v_qty, v_harga, v_sub, v_produk, v_urut);

        -- Harga modal hanya berubah untuk baris yang owner tautkan sendiri.
        -- Harga nol tidak menimpa: struk promo "gratis 1" bukan harga modal.
        IF v_produk IS NOT NULL AND v_harga > 0 THEN
            UPDATE products_hpp SET buy_price = v_harga WHERE id = v_produk;
            v_hpp := v_hpp + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_id, v_urut, v_hpp;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_simpan_pengeluaran(DATE, TEXT, NUMERIC, TEXT, TEXT, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_simpan_pengeluaran(DATE, TEXT, NUMERIC, TEXT, TEXT, JSONB) TO authenticated;


-- ── 04 Daftar pengeluaran ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_pengeluaran_list(p_dari DATE, p_sampai DATE)
RETURNS TABLE (id UUID, tanggal DATE, toko VARCHAR, total NUMERIC, sumber TEXT,
               catatan TEXT, jml_item BIGINT, ringkasan TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT p.id, p.tanggal, p.toko, p.total, p.sumber, p.catatan,
           (SELECT count(*) FROM pengeluaran_item i WHERE i.pengeluaran_id = p.id),
           (SELECT string_agg(i.nama, ', ' ORDER BY i.urutan)
              FROM (SELECT nama, urutan FROM pengeluaran_item
                     WHERE pengeluaran_id = p.id ORDER BY urutan LIMIT 4) i)
      FROM pengeluaran p
     WHERE is_owner()
       AND (p_dari   IS NULL OR p.tanggal >= p_dari)
       AND (p_sampai IS NULL OR p.tanggal <= p_sampai)
     ORDER BY p.tanggal DESC, p.created_at DESC
$function$;

REVOKE EXECUTE ON FUNCTION owner_pengeluaran_list(DATE, DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_pengeluaran_list(DATE, DATE) TO authenticated;


-- ── 05 Menghapus ───────────────────────────────────────────────────────────
-- Harga modal yang sudah diperbarui oleh pengeluaran ini TIDAK dikembalikan.
-- Harga sebelumnya tidak tersimpan di mana pun, dan menebaknya lebih buruk
-- daripada membiarkannya — owner dapat membetulkannya di panel HPP.
CREATE OR REPLACE FUNCTION owner_hapus_pengeluaran(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus pengeluaran.';
    END IF;
    DELETE FROM pengeluaran WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pengeluaran tidak ditemukan.';
    END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_hapus_pengeluaran(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_hapus_pengeluaran(UUID) TO authenticated;
