-- ==============================================================================
-- MIGRASI 56 - Catatan acak dirapikan AI (Add-on AI, fitur 2)
--
-- Penawaran #INV/BU-AI/2026/019, fitur 2: owner menulis coretan atau merekam
-- voice note, AI merapikannya menjadi to-do list tim, tabel, atau langkah
-- kerja yang siap dijalankan.
--
-- AI MERAPIKAN, OWNER YANG MENYIMPAN
--
-- Edge Function ai-rapikan hanya MENGEMBALIKAN hasil rapian ke layar. Tidak
-- ada yang tersimpan sebelum owner memeriksanya, membetulkannya, lalu menekan
-- Simpan — pola yang sama dengan struk belanja (migrasi 53). Voice note yang
-- salah dengar ("jam 3" terdengar "jam 7") terlihat seperti instruksi yang
-- sah begitu tersimpan dan dibagikan ke tim.
--
-- REKAMAN SUARA TIDAK PERNAH DISIMPAN
--
-- Rekaman dikirim ke Edge Function, diteruskan ke model AI, lalu dibuang.
-- Tidak ada kolom audio di sini dan tidak ada bucket penyimpanan. Penawaran
-- menjanjikan rekaman "hanya dapat diakses owner"; cara paling pasti menepati
-- janji itu adalah tidak menyimpannya sama sekali. Yang tersimpan hanya hasil
-- rapian yang owner setujui, dan transkripnya bila owner membiarkannya.
--
-- BENTUK ISI
--
-- isi menyimpan ketiga bentuk sekaligus supaya hasil yang campuran (to-do
-- plus tabel harga, misalnya) tidak kehilangan separuhnya:
--   { "ringkasan": "...",
--     "todo":    [{ "tugas": "...", "untuk": "...", "kapan": "...", "selesai": false }],
--     "tabel":   { "kolom": ["..."], "baris": [["..."]] },
--     "langkah": ["..."],
--     "transkrip": "..." }
-- Bentuknya diperiksa owner_simpan_catatan_rapi, bukan dipercaya dari
-- peramban.
--
-- BATAS PEMAKAIAN HARIAN
--
-- Dicatat di ai_pemakaian (migrasi 53) dengan fitur 'rapikan', diatur lewat
-- secret BATAS_RAPIKAN_HARIAN di Edge Function.
-- ==============================================================================


-- ── 01 Tabel ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catatan_rapi (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    judul       VARCHAR(150) NOT NULL CHECK (btrim(judul) <> ''),
    isi         JSONB NOT NULL CHECK (jsonb_typeof(isi) = 'object'),
    sumber      TEXT NOT NULL DEFAULT 'teks' CHECK (sumber IN ('teks', 'suara')),
    dibuat_oleh UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_catatan_rapi_baru ON catatan_rapi(created_at DESC);

-- Hanya dibaca lewat fungsi di bawah. RLS tetap dipasang supaya tabel ini
-- tidak terbuka bila suatu saat ada yang memberinya GRANT langsung.
ALTER TABLE catatan_rapi ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS owner_all ON catatan_rapi;
CREATE POLICY owner_all ON catatan_rapi
    FOR ALL TO authenticated USING (is_owner()) WITH CHECK (is_owner());


-- ── 02 Merapikan bentuk isi ────────────────────────────────────────────────
-- Dipakai saat menyimpan dan saat mengubah. Hanya kunci yang dikenal yang
-- dibawa, setiap teks dipangkas dan dibatasi panjangnya, dan baris kosong
-- dibuang. Apa pun yang dikirim peramban, yang tersimpan selalu berbentuk ini.
CREATE OR REPLACE FUNCTION catatan_rapi_bersihkan(p_isi JSONB)
RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE SET search_path = public
AS $function$
DECLARE
    v_todo    JSONB := '[]'::JSONB;
    v_kolom   JSONB := '[]'::JSONB;
    v_baris   JSONB := '[]'::JSONB;
    v_langkah JSONB := '[]'::JSONB;
    v_el      JSONB;
    v_sel     JSONB;
    v_satu    JSONB;
    v_teks    TEXT;
    v_n       INT;
BEGIN
    IF p_isi IS NULL OR jsonb_typeof(p_isi) <> 'object' THEN
        RAISE EXCEPTION 'Isi catatan tidak sah.';
    END IF;

    IF jsonb_typeof(p_isi->'todo') = 'array' THEN
        FOR v_el IN SELECT * FROM jsonb_array_elements(p_isi->'todo') LIMIT 100 LOOP
            CONTINUE WHEN jsonb_typeof(v_el) <> 'object';
            v_teks := left(btrim(COALESCE(v_el->>'tugas', '')), 300);
            CONTINUE WHEN v_teks = '';
            v_todo := v_todo || jsonb_build_array(jsonb_build_object(
                'tugas',   v_teks,
                'untuk',   left(btrim(COALESCE(v_el->>'untuk', '')), 80),
                'kapan',   left(btrim(COALESCE(v_el->>'kapan', '')), 80),
                'selesai', COALESCE(v_el->>'selesai', 'false') = 'true'
            ));
        END LOOP;
    END IF;

    IF jsonb_typeof(p_isi->'tabel') = 'object'
       AND jsonb_typeof(p_isi->'tabel'->'kolom') = 'array' THEN
        FOR v_el IN SELECT * FROM jsonb_array_elements(p_isi->'tabel'->'kolom') LIMIT 12 LOOP
            v_kolom := v_kolom || to_jsonb(left(btrim(COALESCE(v_el #>> '{}', '')), 80));
        END LOOP;
        v_n := jsonb_array_length(v_kolom);
        IF v_n > 0 AND jsonb_typeof(p_isi->'tabel'->'baris') = 'array' THEN
            FOR v_el IN SELECT * FROM jsonb_array_elements(p_isi->'tabel'->'baris') LIMIT 200 LOOP
                CONTINUE WHEN jsonb_typeof(v_el) <> 'array';
                v_satu := '[]'::JSONB;
                -- Setiap baris dipaksa sepanjang kolomnya: kurang diisi
                -- kosong, lebih dipotong. Tabel yang barisnya bergerigi tidak
                -- dapat ditampilkan dengan benar.
                FOR i IN 0 .. v_n - 1 LOOP
                    v_sel := v_el->i;
                    v_satu := v_satu || to_jsonb(left(btrim(COALESCE(v_sel #>> '{}', '')), 300));
                END LOOP;
                CONTINUE WHEN NOT EXISTS (
                    SELECT 1 FROM jsonb_array_elements_text(v_satu) s WHERE s <> '');
                v_baris := v_baris || jsonb_build_array(v_satu);
            END LOOP;
        END IF;
    END IF;

    IF jsonb_typeof(p_isi->'langkah') = 'array' THEN
        FOR v_el IN SELECT * FROM jsonb_array_elements(p_isi->'langkah') LIMIT 100 LOOP
            v_teks := left(btrim(COALESCE(v_el #>> '{}', '')), 500);
            CONTINUE WHEN v_teks = '';
            v_langkah := v_langkah || to_jsonb(v_teks);
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'ringkasan', left(btrim(COALESCE(p_isi->>'ringkasan', '')), 1000),
        'todo',      v_todo,
        'tabel',     jsonb_build_object('kolom', CASE WHEN jsonb_array_length(v_baris) > 0
                                                      THEN v_kolom ELSE '[]'::JSONB END,
                                        'baris', v_baris),
        'langkah',   v_langkah,
        'transkrip', left(btrim(COALESCE(p_isi->>'transkrip', '')), 8000)
    );
END $function$;

REVOKE EXECUTE ON FUNCTION catatan_rapi_bersihkan(JSONB) FROM PUBLIC, anon;


-- ── 03 Menyimpan hasil yang sudah diperiksa owner ──────────────────────────
-- p_id NULL membuat catatan baru; berisi id mengubah yang sudah ada (dipakai
-- saat owner mencentang to-do yang selesai).
CREATE OR REPLACE FUNCTION owner_simpan_catatan_rapi(
    p_id     UUID,
    p_judul  TEXT,
    p_isi    JSONB,
    p_sumber TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_id    UUID;
    v_judul TEXT := left(btrim(COALESCE(p_judul, '')), 150);
    v_isi   JSONB;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menyimpan catatan.';
    END IF;
    IF v_judul = '' THEN
        RAISE EXCEPTION 'Judul catatan wajib diisi.';
    END IF;

    v_isi := catatan_rapi_bersihkan(p_isi);
    IF v_isi->>'ringkasan' = ''
       AND jsonb_array_length(v_isi->'todo') = 0
       AND jsonb_array_length(v_isi->'tabel'->'baris') = 0
       AND jsonb_array_length(v_isi->'langkah') = 0 THEN
        RAISE EXCEPTION 'Catatan masih kosong.';
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO catatan_rapi (judul, isi, sumber, dibuat_oleh)
        VALUES (v_judul, v_isi,
                CASE WHEN p_sumber = 'suara' THEN 'suara' ELSE 'teks' END,
                auth.uid())
        RETURNING id INTO v_id;
    ELSE
        -- Sumber tidak ikut diubah: catatan dari voice note tetap tercatat
        -- dari voice note walaupun isinya kemudian disunting.
        UPDATE catatan_rapi
           SET judul = v_judul, isi = v_isi, updated_at = now()
         WHERE id = p_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Catatan tidak ditemukan.';
        END IF;
    END IF;

    RETURN v_id;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_simpan_catatan_rapi(UUID, TEXT, JSONB, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_simpan_catatan_rapi(UUID, TEXT, JSONB, TEXT) TO authenticated;


-- ── 04 Daftar ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_catatan_rapi_list()
RETURNS TABLE (id UUID, judul VARCHAR, isi JSONB, sumber TEXT,
               created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT c.id, c.judul, c.isi, c.sumber, c.created_at, c.updated_at
      FROM catatan_rapi c
     WHERE is_owner()
     ORDER BY c.created_at DESC
     LIMIT 200
$function$;

REVOKE EXECUTE ON FUNCTION owner_catatan_rapi_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_catatan_rapi_list() TO authenticated;


-- ── 05 Menghapus ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION owner_hapus_catatan_rapi(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus catatan.';
    END IF;
    DELETE FROM catatan_rapi WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Catatan tidak ditemukan.';
    END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_hapus_catatan_rapi(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_hapus_catatan_rapi(UUID) TO authenticated;
