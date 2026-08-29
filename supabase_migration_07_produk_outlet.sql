-- ==============================================================================
-- MIGRASI 07 — Katalog Produk & Lokasi Outlet (Fase 2)
--
-- SATU TABEL PRODUK, BUKAN DUA
--   products_hpp sudah ada untuk modul HPP Fase 3. Membuat tabel katalog
--   terpisah berarti dua daftar produk yang cepat atau lambat berbeda isi —
--   harga di katalog pelanggan tidak lagi sama dengan harga di perhitungan
--   margin owner. Karena itu kolom katalog ditambahkan ke tabel yang sama,
--   dan sisi pelanggan hanya melihatnya lewat RPC.
--
-- HARGA MODAL TIDAK PERNAH KELUAR
--   buy_price, shipping, packaging, overhead, dan target_margin adalah angka
--   internal. member_products() memilih kolom secara eksplisit sehingga tidak
--   ada jalan bagi sisi pelanggan untuk melihatnya, bahkan bila kolomnya
--   bertambah di kemudian hari.
-- ==============================================================================

-- 1. KOLOM KATALOG PADA TABEL PRODUK ------------------------------------------
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS hold_level INT
    CHECK (hold_level IS NULL OR (hold_level BETWEEN 0 AND 5));
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS shine_level INT
    CHECK (shine_level IS NULL OR (shine_level BETWEEN 0 AND 5));
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE products_hpp ADD COLUMN IF NOT EXISTS sort_order INT NOT NULL DEFAULT 0;

-- 2. OUTLET -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS outlets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    address TEXT,
    phone VARCHAR(30),
    latitude NUMERIC(10, 7),
    longitude NUMERIC(10, 7),
    -- Jam buka disimpan sebagai waktu lokal outlet, bukan timestamp
    open_time TIME NOT NULL DEFAULT '09:00',
    close_time TIME NOT NULL DEFAULT '21:00',
    -- Hari libur mingguan: 0=Minggu ... 6=Sabtu; kosong berarti buka tiap hari
    closed_days INT[] NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. KATALOG PRODUK UNTUK PELANGGAN -------------------------------------------
-- Kolom dipilih satu per satu. Kolom biaya internal tidak disebut sama sekali,
-- sehingga penambahan kolom baru di kemudian hari tidak diam-diam ikut bocor.
CREATE OR REPLACE FUNCTION member_products()
RETURNS TABLE (
    id UUID, name VARCHAR, description TEXT, category VARCHAR,
    price NUMERIC, hold_level INT, shine_level INT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT p.id, p.name, p.description, p.category,
           p.sell_price, p.hold_level, p.shine_level
      FROM products_hpp p
     WHERE p.is_active
     ORDER BY p.sort_order, p.name
$$;

-- 4. DAFTAR OUTLET ------------------------------------------------------------
-- Status buka dihitung terhadap waktu Jakarta di server, bukan jam perangkat
-- pelanggan yang bisa saja meleset atau sengaja diubah.
CREATE OR REPLACE FUNCTION member_outlets()
RETURNS TABLE (
    id UUID, name VARCHAR, address TEXT, phone VARCHAR,
    latitude NUMERIC, longitude NUMERIC,
    open_time TIME, close_time TIME,
    sedang_buka BOOLEAN, catatan TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT o.id, o.name, o.address, o.phone, o.latitude, o.longitude,
           o.open_time, o.close_time,
           (
             NOT (EXTRACT(DOW FROM (now() AT TIME ZONE 'Asia/Jakarta'))::INT = ANY(o.closed_days))
             AND (now() AT TIME ZONE 'Asia/Jakarta')::TIME BETWEEN o.open_time AND o.close_time
           ) AS sedang_buka,
           CASE
             WHEN EXTRACT(DOW FROM (now() AT TIME ZONE 'Asia/Jakarta'))::INT = ANY(o.closed_days)
               THEN 'Tutup hari ini'
             WHEN (now() AT TIME ZONE 'Asia/Jakarta')::TIME < o.open_time
               THEN 'Buka pukul ' || to_char(o.open_time, 'HH24:MI')
             WHEN (now() AT TIME ZONE 'Asia/Jakarta')::TIME > o.close_time
               THEN 'Sudah tutup'
             ELSE 'Tutup pukul ' || to_char(o.close_time, 'HH24:MI')
           END AS catatan
      FROM outlets o
     WHERE o.is_active
     ORDER BY o.sort_order, o.name
$$;

-- 5. CAPSTER YANG BERTUGAS ----------------------------------------------------
-- Hanya nama dan huruf awal; nomor telepon capster bukan urusan pelanggan.
CREATE OR REPLACE FUNCTION member_capsters()
RETURNS TABLE (name VARCHAR)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT c.name FROM capsters c WHERE c.is_active ORDER BY c.name
$$;

-- 6. HAK EKSEKUSI -------------------------------------------------------------
-- Katalog dan lokasi memang informasi publik; tidak ada data pribadi di sini.
GRANT EXECUTE ON FUNCTION member_products()  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION member_outlets()   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION member_capsters()  TO anon, authenticated;

-- 7. RLS ----------------------------------------------------------------------
ALTER TABLE outlets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS owner_all ON outlets;
CREATE POLICY owner_all ON outlets
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());
-- products_hpp sudah memakai kebijakan owner_all dari migrasi 02; sisi
-- pelanggan tidak menyentuh tabelnya sama sekali.

-- 8. SEED ---------------------------------------------------------------------
-- Contoh sementara sampai klien mengirim katalog produk dan alamat outletnya.
INSERT INTO products_hpp (name, description, category, buy_price, sell_price,
                          hold_level, shine_level, sort_order)
SELECT * FROM (VALUES
    ('Matte Clay Pomade', 'Hold kuat tanpa kilap, cocok untuk gaya tekstur harian',
     'Retail', 45000.00, 85000.00, 5, 1, 1),
    ('Water Based Pomade', 'Mudah dibilas, kilap sedang, rambut tetap lentur',
     'Retail', 42000.00, 78000.00, 3, 4, 2),
    ('Hair Tonic Ginseng', 'Menyegarkan kulit kepala setelah potong rambut',
     'Retail', 28000.00, 55000.00, 0, 0, 3),
    ('Beard Oil Sandalwood', 'Melembutkan janggut dan mengurangi gatal',
     'Retail', 38000.00, 72000.00, 0, 2, 4),
    ('Sea Salt Spray', 'Memberi volume dan tekstur alami sebelum styling',
     'Retail', 35000.00, 68000.00, 2, 1, 5)
) AS v(name, description, category, buy_price, sell_price, hold_level, shine_level, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM products_hpp);

INSERT INTO outlets (name, address, phone, latitude, longitude, open_time, close_time, sort_order)
SELECT * FROM (VALUES
    ('Underrated Barbershop',
     'Alamat menyusul dari klien',
     '6281200000000',
     -6.2000000, 106.8166667,
     '09:00'::TIME, '21:00'::TIME, 1)
) AS v(name, address, phone, latitude, longitude, open_time, close_time, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM outlets);
