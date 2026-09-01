-- ==============================================================================
-- MIGRASI 35 - Agenda Booking: Yang Perlu Diurus Hari Ini
--
-- Lencana booking di kasir hanya menghitung permintaan berstatus 'baru'.
-- Akibatnya, begitu kasir menekan Konfirmasi, angkanya jatuh ke nol dan
-- booking itu lenyap dari pandangan. Panelnya pun terbuka dengan saringan
-- "Baru", sehingga yang sudah dikonfirmasi tidak muncul di mana pun kecuali
-- ada yang tahu harus mengganti saringannya sendiri.
--
-- Hasilnya persis kebalikan dari yang seharusnya: booking yang SUDAH
-- dipastikan ke pelanggan justru yang paling tidak terlihat, dan orangnya
-- datang pukul 12.30 tanpa ada apa pun yang mengingatkan siapa pun.
--
-- APA YANG MASUK AGENDA
--
-- Dua hal, dan hanya dua:
--
--   1. Permintaan yang belum diputuskan, berapa pun tanggalnya. Ini utang
--      jawaban kepada orang yang sedang menunggu kabar.
--   2. Booking terkonfirmasi yang tanggalnya hari ini atau sudah lewat.
--      Yang hari ini adalah tamu yang akan datang; yang sudah lewat adalah
--      pekerjaan yang belum ditutup dan akan menumpuk diam-diam kalau tidak
--      pernah ditagih.
--
-- Yang TIDAK masuk: booking terkonfirmasi untuk hari-hari mendatang. Itu
-- kabar baik, bukan tugas, dan memasukkannya membuat lencana selalu berangka
-- besar sampai kasir berhenti memperhatikannya.
--
-- SELISIH MENIT DIHITUNG DI SERVER
--
-- Jam perangkat kasir dapat meleset, dan pengingat "sebentar lagi" yang
-- meleset satu jam lebih buruk daripada tidak ada pengingat. Selisihnya
-- dihitung dari waktu server dalam zona Jakarta, lalu dikirim sebagai angka
-- menit yang tinggal ditampilkan.
-- ==============================================================================

CREATE OR REPLACE FUNCTION bookings_agenda()
RETURNS TABLE (
    id UUID, kode VARCHAR, nama VARCHAR, telepon VARCHAR,
    service_name VARCHAR, durasi_menit INT, harga NUMERIC,
    tanggal date, jam time, catatan TEXT, status VARCHAR,
    kelompok TEXT, menit_lagi INT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $function$
    SELECT b.id, b.kode, b.nama, b.telepon,
           b.service_name, b.durasi_menit, b.harga,
           b.tanggal, b.jam, b.catatan, b.status,
           CASE WHEN b.status = 'baru' THEN 'permintaan'
                WHEN b.tanggal < jakarta_today() THEN 'terlewat'
                ELSE 'hari_ini' END,
           -- Negatif berarti jamnya sudah lewat. NULL untuk permintaan yang
           -- belum diputuskan, sebab jamnya belum tentu jadi.
           CASE WHEN b.status = 'dikonfirmasi'
                THEN (EXTRACT(EPOCH FROM (
                        (b.tanggal + b.jam) - (now() AT TIME ZONE 'Asia/Jakarta')
                     )) / 60)::INT
           END
      FROM bookings b
     WHERE auth.uid() IS NOT NULL
       AND (
             b.status = 'baru'
             OR (b.status = 'dikonfirmasi' AND b.tanggal <= jakarta_today())
           )
     ORDER BY
       -- Yang sudah lewat jamnya naik ke atas: itu yang paling mungkin
       -- terlupakan, dan satu-satunya yang tidak bisa ditunda lagi.
       CASE WHEN b.status = 'dikonfirmasi' AND b.tanggal < jakarta_today() THEN 0
            WHEN b.status = 'dikonfirmasi' THEN 1
            ELSE 2 END,
       b.tanggal, b.jam
$function$;

REVOKE EXECUTE ON FUNCTION bookings_agenda() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION bookings_agenda() TO authenticated;
