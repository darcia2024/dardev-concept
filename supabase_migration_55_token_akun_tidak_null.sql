-- =============================================================================
-- 55 · AKUN BUATAN SQL GAGAL MASUK: "Database error querying schema"
--
-- GEJALANYA. Akun yang dibuat lewat owner_buat_akun_capster tidak bisa masuk
-- sama sekali. /masuk menjawab "Gagal masuk: Database error querying schema",
-- sandinya benar atau salah.
--
-- SEBABNYA. Fungsi itu (migrasi 47, lalu 49 dan 51) mengisi auth.users kolom
-- demi kolom dan membiarkan kolom token (confirmation_token, recovery_token,
-- email_change, dst.) NULL. Server auth Supabase (GoTrue, ditulis dalam Go)
-- membaca kolom itu sebagai string yang tidak boleh kosong. Begitu bertemu
-- NULL, pembacaan barisnya gagal dan upaya masuk dijawab galat umum di atas.
-- Akun yang dibuat GoTrue sendiri tidak pernah kena, sebab GoTrue selalu
-- mengisinya dengan '' (string kosong).
--
-- MENGAPA TRIGGER, BUKAN MENULIS ULANG FUNGSINYA. owner_buat_akun_capster
-- sudah tiga kali diganti, dan pernah sekali tertimpa versi lama karena
-- berkas yang lebih tua dijalankan belakangan (lihat kepala migrasi 49).
-- Menulis versi keempat menambah satu lagi berkas yang berbahaya bila
-- dijalankan ulang. Trigger ini tidak menyentuh fungsi mana pun: siapa pun
-- yang menyisipkan ke auth.users — fungsi versi mana saja, atau SQL yang
-- diketik tangan di dashboard — kolom tokennya diluruskan sebelum tersimpan.
--
-- Aman dijalankan berulang kali, kapan pun, sebelum atau sesudah migrasi
-- lain. Hanya kolom yang memang ada di versi auth.users basis data ini yang
-- disentuh, dan hanya yang bernilai NULL.
-- =============================================================================

-- ── 1 · Luruskan akun yang sudah terlanjur dibuat ───────────────────────────
-- Daftar kolom dibaca dari information_schema, bukan ditulis mati: kolom yang
-- tersedia berbeda antarversi GoTrue, dan UPDATE ke kolom yang tidak ada akan
-- menggagalkan seluruh migrasi.
DO $perbaikan$
DECLARE
    v_kolom TEXT;
BEGIN
    FOR v_kolom IN
        SELECT c.column_name
          FROM information_schema.columns c
         WHERE c.table_schema = 'auth'
           AND c.table_name   = 'users'
           AND c.column_name IN (
                 'confirmation_token',
                 'recovery_token',
                 'email_change_token_new',
                 'email_change_token_current',
                 'email_change',
                 'phone_change',
                 'phone_change_token',
                 'reauthentication_token'
               )
    LOOP
        EXECUTE format('UPDATE auth.users SET %I = '''' WHERE %I IS NULL',
                       v_kolom, v_kolom);
    END LOOP;
END $perbaikan$;

-- ── 2 · Akun berikutnya tidak pernah tersimpan dengan token NULL ────────────
-- Baris diolah sebagai JSONB supaya kolom yang tidak ada di versi GoTrue ini
-- dilewati, bukan menggagalkan INSERT. Merujuk NEW.kolom_yang_tidak_ada
-- langsung akan membuat SETIAP pembuatan akun gagal — termasuk lewat GoTrue.
CREATE OR REPLACE FUNCTION auth_users_token_kosong()
RETURNS trigger
LANGUAGE plpgsql SET search_path = ''
AS $function$
DECLARE
    v_baris JSONB := to_jsonb(NEW);
    v_tambal JSONB := '{}'::JSONB;
    v_kolom TEXT;
BEGIN
    FOREACH v_kolom IN ARRAY ARRAY[
        'confirmation_token',
        'recovery_token',
        'email_change_token_new',
        'email_change_token_current',
        'email_change',
        'phone_change',
        'phone_change_token',
        'reauthentication_token'
    ] LOOP
        IF v_baris ? v_kolom AND jsonb_typeof(v_baris -> v_kolom) = 'null' THEN
            v_tambal := v_tambal || jsonb_build_object(v_kolom, '');
        END IF;
    END LOOP;

    IF v_tambal <> '{}'::JSONB THEN
        NEW := jsonb_populate_record(NEW, v_tambal);
    END IF;
    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS auth_users_token_kosong ON auth.users;
CREATE TRIGGER auth_users_token_kosong
    BEFORE INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION auth_users_token_kosong();

-- ── Sesudah dijalankan ──────────────────────────────────────────────────────
-- Harus mengembalikan 0 baris:
--
--   select email from auth.users
--    where confirmation_token is null or recovery_token is null
--       or email_change_token_new is null or email_change is null;
