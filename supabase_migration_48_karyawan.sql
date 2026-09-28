-- ==============================================================================
-- MIGRASI 47 - Kapster naik pangkat jadi Karyawan
--
-- Absen selama ini hanya mengenal kapster. Bukan karena peran lain sengaja
-- ditutup, melainkan karena seluruh mesinnya berporos di satu titik:
-- check_in() mencari `capsters WHERE auth_user_id = auth.uid()`, dan
-- attendances.capster_id menunjuk langsung ke capsters(id).
--
-- Pemilik ingin karyawan non-cukur — admin, kebersihan, kasir murni — ikut
-- absen dari HP masing-masing, persis seperti kapster. Ada dua jalan ke sana.
--
-- Jalan pertama: bikin tabel karyawan tersendiri, lalu ajari absen, cuti, dan
-- arsip penghapusan mengenal dua sumber. Itu berarti mengubah kolom kunci pada
-- tabel produksi yang sudah terisi absen berbulan-bulan, dan setiap tempat
-- yang hari ini menulis `capster_id` harus tahu sedang bicara tentang siapa.
--
-- Jalan kedua, yang diambil di sini: akui saja bahwa `capsters` sudah menjadi
-- tabel karyawan sejak lama. Ia menyimpan nama, telepon, status aktif, dan
-- tautan akun — tidak satu pun khusus tukang cukur. Yang benar-benar khas
-- kapster hanyalah "boleh dipilih sebagai pencukur di kasir", dan itu sifat,
-- bukan jenis tabel. Maka sifat itu yang dijadikan kolom.
--
-- Konsekuensinya absen, cuti, koreksi absensi, kalender mangkir, dan arsip
-- penghapusan ikut bekerja untuk peran baru tanpa satu baris pun diubah.
--
-- Nama tabelnya tetap `capsters`. Mengganti nama tabel yang dirujuk lima
-- foreign key dan puluhan fungsi hanya demi kerapian penyebutan adalah risiko
-- yang tidak dibayar oleh manfaatnya. Yang dilihat orang adalah layarnya, dan
-- di layar ia disebut Karyawan.
-- ==============================================================================


-- ── 01 Dua kolom baru ──────────────────────────────────────────────────────
-- jabatan hanya sebutan untuk manusia: ia menentukan tulisan di layar absen
-- dan di dashboard, bukan hak akses. Yang menentukan apa yang boleh dilakukan
-- sebuah akun tetap profiles.role, dan itu sengaja tidak disentuh di sini.
--
-- ikut_pos memisahkan "karyawan" dari "pencukur yang boleh dipilih". Tukang
-- bersih-bersih perlu absen, tetapi tidak boleh muncul sebagai pilihan kapster
-- di kasir maupun di halaman booking pelanggan.
--
-- Keduanya diberi DEFAULT yang membuat seluruh baris lama tetap persis seperti
-- sebelumnya: semua yang sudah ada memang kapster, dan semuanya memang boleh
-- dipilih di kasir. Tidak ada yang berubah perilakunya karena migrasi ini.
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS jabatan  VARCHAR(40);
ALTER TABLE capsters ADD COLUMN IF NOT EXISTS ikut_pos BOOLEAN;

UPDATE capsters SET jabatan  = 'Kapster' WHERE jabatan  IS NULL;
UPDATE capsters SET ikut_pos = TRUE      WHERE ikut_pos IS NULL;

ALTER TABLE capsters ALTER COLUMN jabatan  SET DEFAULT 'Kapster';
ALTER TABLE capsters ALTER COLUMN ikut_pos SET DEFAULT TRUE;
ALTER TABLE capsters ALTER COLUMN jabatan  SET NOT NULL;
ALTER TABLE capsters ALTER COLUMN ikut_pos SET NOT NULL;

COMMENT ON TABLE capsters IS
  'Karyawan outlet. Namanya warisan dari saat isinya hanya tukang cukur. '
  'Baris dengan ikut_pos = true adalah yang boleh dipilih sebagai pencukur '
  'di kasir dan di halaman booking.';
COMMENT ON COLUMN capsters.jabatan IS
  'Sebutan untuk layar: Kapster, Kasir, Admin, Kebersihan, dan seterusnya. '
  'Bukan hak akses — yang mengatur hak tetap profiles.role.';
COMMENT ON COLUMN capsters.ikut_pos IS
  'true = muncul sebagai pilihan pencukur di kasir dan halaman booking. '
  'false = karyawan yang tetap absen tetapi tidak mencukur.';


-- ── 02 Penyunting karyawan untuk owner ─────────────────────────────────────
-- Owner sebenarnya sudah bisa menulis ke capsters lewat policy owner_all, dan
-- layar /pos memakai jalan itu. Fungsi ini tetap dibuat karena tiga hal yang
-- tidak bisa dijamin oleh policy:
--
--   1. Nomor telepon dinormalkan ke bentuk 62xxx di satu tempat. Lewat tulis
--      langsung, layar baru bisa menyimpan '0812...' dan notifikasi WhatsApp
--      diam-diam gagal karena providernya tidak mengenali bentuk itu.
--   2. Nama kembar ditolak dengan kalimat yang bisa dibaca, bukan dengan kode
--      galat 23505 yang harus diterjemahkan ulang di setiap layar.
--   3. Jabatan dan ikut_pos divalidasi bersama-sama.
CREATE OR REPLACE FUNCTION owner_upsert_karyawan(
    p_id       UUID,
    p_nama     TEXT,
    p_telepon  TEXT,
    p_jabatan  TEXT,
    p_ikut_pos BOOLEAN,
    p_aktif    BOOLEAN
)
RETURNS TABLE (karyawan_id UUID, nama CHARACTER VARYING, jabatan CHARACTER VARYING,
               telepon CHARACTER VARYING, ikut_pos BOOLEAN, is_active BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_nama    TEXT;
    v_jabatan TEXT;
    v_nomor   TEXT;
    v_id      UUID;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh mengelola data karyawan.';
    END IF;

    v_nama := btrim(COALESCE(p_nama, ''));
    IF v_nama = '' THEN
        RAISE EXCEPTION 'Nama karyawan wajib diisi.';
    END IF;
    IF length(v_nama) > 150 THEN
        RAISE EXCEPTION 'Nama karyawan terlalu panjang.';
    END IF;

    v_jabatan := btrim(COALESCE(p_jabatan, ''));
    IF v_jabatan = '' THEN v_jabatan := 'Kapster'; END IF;
    IF length(v_jabatan) > 40 THEN
        RAISE EXCEPTION 'Jabatan terlalu panjang.';
    END IF;

    -- Nomor boleh kosong: karyawan yang tidak menerima notifikasi booking
    -- tidak perlu dipaksa punya WhatsApp. Yang tidak boleh adalah nomor terisi
    -- tetapi tidak dikenali, sebab itu gagal diam-diam saat mengirim.
    IF btrim(COALESCE(p_telepon, '')) = '' THEN
        v_nomor := NULL;
    ELSE
        v_nomor := normalkan_nomor_wa(p_telepon);
        IF v_nomor IS NULL THEN
            RAISE EXCEPTION 'Nomor tidak dikenali. Contoh yang benar: 081297754581.';
        END IF;
    END IF;

    -- Nama kembar membuat kasir salah memilih orang, dan membuat laporan
    -- produktivitas menumpuk dua orang jadi satu baris.
    IF EXISTS (SELECT 1 FROM capsters c
                WHERE lower(c.name) = lower(v_nama)
                  AND (p_id IS NULL OR c.id <> p_id)) THEN
        RAISE EXCEPTION 'Sudah ada karyawan bernama %.', v_nama;
    END IF;

    IF p_id IS NULL THEN
        INSERT INTO capsters (name, phone, jabatan, ikut_pos, is_active)
        VALUES (v_nama, v_nomor, v_jabatan,
                COALESCE(p_ikut_pos, TRUE), COALESCE(p_aktif, TRUE))
        RETURNING capsters.id INTO v_id;
    ELSE
        UPDATE capsters c SET
            name     = v_nama,
            phone    = v_nomor,
            jabatan  = v_jabatan,
            ikut_pos = COALESCE(p_ikut_pos, c.ikut_pos),
            is_active = COALESCE(p_aktif, c.is_active)
        WHERE c.id = p_id
        RETURNING c.id INTO v_id;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Karyawan tidak ditemukan.';
        END IF;
    END IF;

    RETURN QUERY
    SELECT c.id, c.name, c.jabatan, c.phone, c.ikut_pos, c.is_active
      FROM capsters c WHERE c.id = v_id;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_upsert_karyawan(UUID, TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) TO authenticated;


-- ── 03 Penghapusan yang tidak diam-diam membuang riwayat absen ─────────────
-- attendances.capster_id dan leave_requests.capster_id keduanya ON DELETE
-- CASCADE. Menghapus satu karyawan berarti menghapus seluruh absen dan
-- pengajuan cutinya sekaligus, tanpa jejak, dan arsip deleted_attendances
-- tidak ikut terisi karena arsip itu hanya diisi oleh jalur hapus absensi.
--
-- Layar /pos hari ini menawarkan tombol hapus dengan kalimat "Transaksi lama
-- tetap menyimpan namanya". Itu benar untuk transaksi, yang memang ON DELETE
-- SET NULL, tetapi tidak benar untuk absen. Fungsi ini menolak menghapus
-- karyawan yang sudah punya riwayat, dan menyarankan menonaktifkan.
CREATE OR REPLACE FUNCTION owner_hapus_karyawan(p_id UUID)
RETURNS TABLE (nama CHARACTER VARYING)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_kar     capsters%ROWTYPE;
    v_absen   BIGINT;
    v_cuti    BIGINT;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh menghapus karyawan.';
    END IF;

    SELECT * INTO v_kar FROM capsters c WHERE c.id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karyawan tidak ditemukan.';
    END IF;

    SELECT count(*) INTO v_absen FROM attendances a WHERE a.capster_id = p_id;
    SELECT count(*) INTO v_cuti  FROM leave_requests l WHERE l.capster_id = p_id;

    IF v_absen > 0 OR v_cuti > 0 THEN
        RAISE EXCEPTION
            '% punya % catatan absen dan % pengajuan cuti. Menghapusnya ikut '
            'menghapus semuanya tanpa bisa dikembalikan. Nonaktifkan saja '
            'supaya riwayatnya tetap utuh.',
            v_kar.name, v_absen, v_cuti;
    END IF;

    IF v_kar.auth_user_id IS NOT NULL THEN
        RAISE EXCEPTION
            '% masih tertaut ke sebuah akun. Lepaskan akunnya lebih dulu, atau '
            'nonaktifkan saja karyawannya.', v_kar.name;
    END IF;

    DELETE FROM capsters c WHERE c.id = p_id;
    RETURN QUERY SELECT v_kar.name;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_hapus_karyawan(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_hapus_karyawan(UUID) TO authenticated;


-- ── 04 Daftar staf ikut membawa jabatan dan penandanya ─────────────────────
-- DROP diperlukan karena kolom keluaran bertambah. Supabase memberi anon hak
-- EXECUTE pada tiap fungsi yang baru dibuat, jadi haknya ditulis ulang secara
-- eksplisit, bukan hanya dicabut dari PUBLIC.
DROP FUNCTION IF EXISTS owner_staff_list();

CREATE OR REPLACE FUNCTION owner_staff_list()
RETURNS TABLE (capster_id UUID, name CHARACTER VARYING, email TEXT,
               is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING,
               jabatan CHARACTER VARYING, ikut_pos BOOLEAN,
               jml_absen BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth
AS $function$
    SELECT c.id, c.name, u.email::TEXT, c.is_active, (c.auth_user_id IS NOT NULL),
           c.phone, c.jabatan, c.ikut_pos,
           (SELECT count(*) FROM attendances a WHERE a.capster_id = c.id)
      FROM capsters c
      LEFT JOIN auth.users u ON u.id = c.auth_user_id
     WHERE is_owner()
     ORDER BY c.ikut_pos DESC, c.name;
$function$;

REVOKE EXECUTE ON FUNCTION owner_staff_list() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_staff_list() TO authenticated;


-- ── 05 Yang bukan pencukur tidak ditawarkan sebagai pencukur ───────────────
-- Dua daftar ini yang dilihat pelanggan. Tanpa saringan ikut_pos, karyawan
-- kebersihan akan muncul di halaman booking sebagai orang yang bisa dipilih
-- untuk mencukur, dan pelanggan yang memilihnya akan datang ke janji yang
-- tidak bisa dipenuhi siapa pun.
CREATE OR REPLACE FUNCTION member_capsters()
RETURNS TABLE (name CHARACTER VARYING)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT c.name FROM capsters c
     WHERE c.is_active AND c.ikut_pos
     ORDER BY c.name
$function$;

REVOKE EXECUTE ON FUNCTION member_capsters() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION member_capsters() TO anon, authenticated;


-- public_landing() disalin utuh dari migrasi 28 dengan satu perubahan pada
-- bagian 'kapster'. Fungsi ini mengembalikan satu jsonb, jadi tidak ada cara
-- menambal sebagiannya tanpa menulis ulang seluruhnya.
CREATE OR REPLACE FUNCTION public_landing()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT jsonb_build_object(
        'layanan', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', s.id, 'nama', s.name, 'kategori', s.category,
                       'harga', s.price, 'menit', s.duration_minutes)
                   ORDER BY s.price)
              FROM services s WHERE s.is_active
        ), '[]'::jsonb),
        'kapster', COALESCE((
            SELECT jsonb_agg(c.name ORDER BY c.name)
              FROM capsters c WHERE c.is_active AND c.ikut_pos
        ), '[]'::jsonb),
        'outlet', (
            SELECT jsonb_build_object(
                       'nama', o.name, 'alamat', o.address, 'telepon', o.phone,
                       'lat', o.latitude, 'lng', o.longitude)
              FROM outlets o WHERE o.is_active ORDER BY o.sort_order LIMIT 1
        ),
        'jam', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'dow', j.dow, 'buka', j.buka, 'tutup', j.tutup, 'libur', j.libur)
                   ORDER BY j.dow)
              FROM jam_operasional j
        ), '[]'::jsonb),
        'poin', (
            SELECT jsonb_build_object(
                       'rupiah_per_poin', ls.rupiah_per_point,
                       'nilai_poin', ls.rupiah_per_point_redeem,
                       'aktif', ls.is_active)
              FROM loyalty_settings ls LIMIT 1
        )
    )
$function$;

REVOKE EXECUTE ON FUNCTION public_landing() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public_landing() TO anon, authenticated;


-- ── 06 Layar absen menyebut jabatan yang sebenarnya ────────────────────────
-- capster.html menulis "Capster" sebagai label tetap. Untuk tukang bersih
-- bersih yang membuka layar absennya sendiri, label itu keliru. me_capster()
-- kini ikut membawa jabatannya supaya layar tidak perlu menebak.
DROP FUNCTION IF EXISTS me_capster();

CREATE OR REPLACE FUNCTION me_capster()
RETURNS TABLE (id UUID, name CHARACTER VARYING, is_active BOOLEAN,
               jabatan CHARACTER VARYING, ikut_pos BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT c.id, c.name, c.is_active, c.jabatan, c.ikut_pos
      FROM capsters c
     WHERE c.auth_user_id = auth.uid()
     LIMIT 1
$function$;

REVOKE EXECUTE ON FUNCTION me_capster() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION me_capster() TO authenticated;


-- ==============================================================================
-- MELEPAS AKUN KARYAWAN
--
-- owner_buat_akun_capster() pada migrasi 47 menolak karyawan yang sudah punya
-- akun. Penolakan itu benar — membuat akun kedua meninggalkan akun pertama
-- menggantung tanpa pemilik — tetapi tanpa jalan keluar ia jadi buntu: akun
-- yang salah tertaut tidak dapat diperbaiki dari layar mana pun.
--
-- Melepas tidak menghapus akunnya di auth.users. Karyawan yang kembali
-- bekerja dapat ditautkan lagi, dan riwayat absennya tetap utuh karena absen
-- menunjuk ke capsters.id, bukan ke akunnya.
-- ==============================================================================
CREATE OR REPLACE FUNCTION owner_lepas_akun_karyawan(p_karyawan_id UUID)
RETURNS TABLE (nama CHARACTER VARYING)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_kar capsters%ROWTYPE;
BEGIN
    IF NOT is_owner() THEN
        RAISE EXCEPTION 'Hanya owner yang boleh melepas akun karyawan.';
    END IF;

    SELECT * INTO v_kar FROM capsters c WHERE c.id = p_karyawan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karyawan tidak ditemukan.';
    END IF;
    IF v_kar.auth_user_id IS NULL THEN
        RAISE EXCEPTION '% memang belum punya akun.', v_kar.name;
    END IF;

    -- Batasi sasaran: fungsi ini tidak boleh dipakai melepas akun owner atau
    -- akun perangkat POS, meski id karyawannya ditebak-tebak.
    IF EXISTS (SELECT 1 FROM profiles p
                WHERE p.id = v_kar.auth_user_id AND p.role <> 'capster') THEN
        RAISE EXCEPTION 'Akun itu bukan akun karyawan.';
    END IF;

    UPDATE capsters c SET auth_user_id = NULL WHERE c.id = p_karyawan_id;
    RETURN QUERY SELECT v_kar.name;
END $function$;

REVOKE EXECUTE ON FUNCTION owner_lepas_akun_karyawan(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION owner_lepas_akun_karyawan(UUID) TO authenticated;
