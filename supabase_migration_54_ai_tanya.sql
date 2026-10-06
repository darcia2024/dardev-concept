-- ==============================================================================
-- MIGRASI 54 - Batas per pengunjung untuk chat pelanggan (Add-on AI, fitur 5 + 4)
--
-- Chat di halaman depan terbuka untuk siapa pun tanpa login, dan setiap
-- pertanyaannya ditagih ke saldo OpenRouter pengembang. Tanpa batas per
-- pengunjung, satu skrip iseng dapat menghabiskan saldo itu dalam semalam.
--
-- Edge Function ai-tanya menghitung pemakaian per pengunjung lewat kolom di
-- bawah. Yang disimpan BUKAN alamat IP, melainkan sidik SHA-256 dari alamat
-- itu bersama tanggal hari ini: cukup untuk menghitung "orang yang sama hari
-- ini", tidak cukup untuk menelusuri siapa orangnya, dan berubah tiap hari
-- sehingga tidak dapat dipakai menyambung kunjungan antar hari.
--
-- Isi percakapannya tidak disimpan di mana pun.
-- ==============================================================================

ALTER TABLE ai_pemakaian ADD COLUMN IF NOT EXISTS pengunjung TEXT;

COMMENT ON COLUMN ai_pemakaian.pengunjung IS
  'Sidik SHA-256 dari IP pengunjung + tanggal (chat publik). Bukan IP, tidak '
  'dapat dibalik, berganti tiap hari. NULL untuk fitur yang dipakai owner.';

CREATE INDEX IF NOT EXISTS idx_ai_pemakaian_pengunjung
    ON ai_pemakaian(fitur, pengunjung, created_at DESC);
