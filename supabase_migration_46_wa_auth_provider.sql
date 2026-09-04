-- =============================================================================
-- 46 · SKEMA OTORISASI MENGIKUTI PROVIDER
--
-- kirim_wa_capster selalu mengirim 'Authorization: Bearer <token>'. Itu benar
-- untuk WhatsApp Cloud API milik Meta, tetapi Fonnte dan gateway sejenis
-- menuntut tokennya mentah tanpa awalan apa pun. Dengan awalan yang keliru,
-- gateway menolak dengan galat otorisasi yang tidak menyebutkan sebabnya —
-- pemilik hanya melihat "Gagal" di dasbor dan tidak punya petunjuk apa pun.
--
-- Tidak ada kolom baru dan tidak ada isian tambahan di layar pengaturan.
-- Kolom provider sudah memuat perbedaan itu: 'meta' memakai Bearer, selain itu
-- token mentah. Menambah pilihan sendiri hanya memindahkan keputusan teknis
-- ini ke pemilik, yang tidak punya cara mengetahui jawabannya.
--
-- Tanda tangan fungsinya tidak berubah, jadi CREATE OR REPLACE cukup dan hak
-- aksesnya tidak hilang. REVOKE dan GRANT tetap ditulis ulang sebagai penegasan.
-- =============================================================================


CREATE OR REPLACE FUNCTION kirim_wa_capster(p_booking_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $function$
DECLARE
    v_b      bookings%ROWTYPE;
    v_telp   TEXT;
    v_nama   TEXT;
    v_cfg    wa_config%ROWTYPE;
    v_token  TEXT;
    v_pesan  TEXT;
    v_body   JSONB;
    v_status TEXT;
    v_galat  TEXT;
BEGIN
    -- Baris dikunci: dua permintaan yang tiba bersamaan untuk booking yang
    -- sama akan berbaris, dan yang kedua melihat penanda dari yang pertama.
    SELECT * INTO v_b FROM bookings b WHERE b.id = p_booking_id FOR UPDATE;
    IF NOT FOUND OR v_b.notif_wa_at IS NOT NULL THEN RETURN; END IF;

    SELECT * INTO v_cfg FROM wa_config LIMIT 1;

    SELECT c.phone, c.name INTO v_telp, v_nama
      FROM capsters c WHERE c.id = v_b.capster_id AND c.is_active;

    IF v_b.capster_id IS NULL THEN
        v_status := 'tanpa_capster';
    ELSIF COALESCE(btrim(v_telp), '') !~ '^62[0-9]{8,15}$' THEN
        v_status := 'nomor_tidak_sah';
        v_galat  := 'Nomor capster kosong atau tidak berformat 62xxxxxxxxxx.';
    ELSIF NOT COALESCE(v_cfg.aktif, FALSE) THEN
        v_status := 'nonaktif';
    ELSE
        BEGIN
            SELECT decrypted_secret INTO v_token
              FROM vault.decrypted_secrets WHERE name = v_cfg.nama_rahasia;
            IF COALESCE(v_token, '') = '' THEN
                RAISE EXCEPTION 'Token % belum tersimpan di Vault.', v_cfg.nama_rahasia;
            END IF;

            v_pesan := 'Booking baru untuk ' || v_nama || '.' || chr(10)
                    || 'Nama: ' || v_b.nama || chr(10)
                    || 'Layanan: ' || v_b.service_name || chr(10)
                    || 'Tanggal: ' || to_char(v_b.tanggal, 'DD Mon YYYY') || chr(10)
                    || 'Jam: ' || to_char(v_b.jam, 'HH24:MI') || chr(10)
                    || 'Kode: ' || v_b.kode;

            -- Nomor pelanggan sengaja TIDAK disertakan. Capster tidak
            -- membutuhkannya untuk bersiap, dan kasirlah yang menghubungi
            -- pelanggan. Menyebarkannya ke beberapa ponsel memperbanyak
            -- tempat data itu dapat bocor tanpa menambah kegunaan.
            IF v_cfg.provider = 'meta' THEN
                v_body := jsonb_build_object(
                    'messaging_product', 'whatsapp',
                    'to', v_telp,
                    'type', 'template',
                    'template', jsonb_build_object(
                        'name', v_cfg.template,
                        'language', jsonb_build_object('code', v_cfg.bahasa),
                        'components', jsonb_build_array(jsonb_build_object(
                            'type', 'body',
                            'parameters', jsonb_build_array(
                                jsonb_build_object('type','text','text', v_b.nama),
                                jsonb_build_object('type','text','text', v_b.service_name),
                                jsonb_build_object('type','text','text', to_char(v_b.tanggal,'DD Mon YYYY')),
                                jsonb_build_object('type','text','text', to_char(v_b.jam,'HH24:MI')),
                                jsonb_build_object('type','text','text', v_b.kode)
                            )))));
            ELSE
                v_body := jsonb_build_object('target', v_telp, 'message', v_pesan);
            END IF;

            PERFORM net.http_post(
                url     := v_cfg.endpoint,
                body    := v_body,
                headers := jsonb_build_object(
                               'Content-Type', 'application/json',
                               'Authorization',
                               -- Meta memakai skema Bearer. Gateway Indonesia
                               -- (Fonnte, Wablas) menolaknya: token dikirim
                               -- mentah. Awalan yang keliru gagal sebagai galat
                               -- otorisasi yang tidak menyebut sebabnya.
                               CASE WHEN v_cfg.provider = 'meta'
                                    THEN 'Bearer ' || v_token
                                    ELSE v_token END));
            v_status := 'terkirim';
        EXCEPTION WHEN OTHERS THEN
            -- Booking tidak boleh gugur karena pemberitahuan internal gagal.
            v_status := 'gagal';
            v_galat  := left(SQLERRM, 500);
        END;
    END IF;

    UPDATE bookings
       SET notif_wa_at = now(), notif_wa_status = v_status, notif_wa_error = v_galat
     WHERE id = p_booking_id;
EXCEPTION WHEN OTHERS THEN
    -- Bahkan kegagalan di luar blok di atas pun tidak boleh menjatuhkan
    -- transaksi pemanggilnya.
    NULL;
END $function$;


REVOKE EXECUTE ON FUNCTION kirim_wa_capster(UUID) FROM PUBLIC, anon, authenticated;
