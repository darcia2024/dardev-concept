-- ==============================================================================
-- MIGRASI 19 — Koreksi Catatan Absensi yang Diukur dari Jam yang Salah
--
-- APA YANG DIPERBAIKI
--
-- Catatan absensi 30 Agustus 2026 dibuat ketika sistem masih mengira toko buka
-- pukul 09.00. Jam buka sebenarnya — 10.00 pada hari biasa, 13.00 pada Jumat —
-- baru diterima dari klien sesudahnya (migrasi 18).
--
-- Akibatnya dua dari tiga catatan menuduh orang yang tidak bersalah:
--
--   Lukman  masuk 09:48  tercatat terlambat 48 menit  -> sebenarnya belum buka
--   Wanda   masuk 09:52  tercatat terlambat 53 menit  -> sebenarnya belum buka
--   Cena    masuk 10:32  tercatat terlambat 93 menit  -> sebenarnya 32 menit
--
-- Keduanya datang SEBELUM toko buka, lalu dicatat terlambat. Kekeliruan itu
-- ada pada sistemnya, bukan pada orangnya, dan membiarkannya berarti catatan
-- kehadiran pertama yang dimiliki sistem ini adalah catatan yang salah.
--
-- CARA MENGHITUNGNYA
--
-- Tidak ada angka yang diketik tangan. Status dihitung ulang memakai rumus yang
-- persis sama dengan clock_in(): terlambat bila kedatangan melewati jam buka
-- ditambah toleransi, dan menitnya diukur dari JAM BUKA — bukan dari batas
-- toleransi. Sumber jam buka adalah jam_operasional, tabel yang sama yang
-- dipakai absensi sejak hari ini.
--
-- LINGKUPNYA SEMPIT DENGAN SENGAJA
--
-- Hanya menyentuh baris yang tanggalnya SEBELUM hari ini, sehingga absensi
-- yang dibuat sesudah migrasi 18 — yang sudah memakai jam benar — tidak ikut
-- dihitung ulang. Berkas ini juga sekali pakai: ia bukan alat yang bisa
-- dijalankan lagi kapan saja, karena alat semacam itu suatu hari akan
-- dijalankan orang terhadap data yang sudah benar.
-- ==============================================================================

-- Rekam keadaan sebelum diubah, supaya perbandingannya bisa dibaca kembali
CREATE TABLE IF NOT EXISTS koreksi_absensi_20260831 AS
SELECT a.id,
       c.name                                   AS capster_name,
       a.business_date,
       (a.check_in_time AT TIME ZONE 'Asia/Jakarta')::TIME AS jam_masuk,
       a.status::TEXT                           AS status_lama,
       a.terlambat_menit                        AS terlambat_lama
  FROM attendances a
  JOIN capsters c ON c.id = a.capster_id
 WHERE a.business_date < jakarta_today();

-- Hitung ulang dengan rumus yang sama persis seperti clock_in()
WITH aturan AS (
    SELECT toleransi_menit FROM work_rules LIMIT 1
),
hitung AS (
    SELECT a.id,
           j.buka,
           (a.check_in_time AT TIME ZONE 'Asia/Jakarta')::TIME AS datang,
           r.toleransi_menit AS tol
      FROM attendances a
      CROSS JOIN aturan r
      JOIN jam_operasional j
        ON j.dow = EXTRACT(DOW FROM a.business_date)::SMALLINT
     WHERE a.business_date < jakarta_today()
       AND a.check_in_time IS NOT NULL
)
UPDATE attendances a
   SET terlambat_menit = CASE
           WHEN h.datang > h.buka + make_interval(mins => h.tol)
           THEN (EXTRACT(EPOCH FROM (h.datang - h.buka)) / 60)::INT
           ELSE 0 END,
       status = CASE
           WHEN h.datang > h.buka + make_interval(mins => h.tol)
           THEN 'terlambat'::attend_status
           ELSE 'hadir'::attend_status END
  FROM hitung h
 WHERE a.id = h.id;
