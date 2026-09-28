-- =============================================================================
-- 01a · PRATINJAU — poin 7% menjadi 10%  (HANYA MEMBACA, tidak mengubah apa pun)
--
-- Jalankan ini LEBIH DULU dan baca hasilnya. Baru sesudah angkanya masuk akal,
-- jalankan koreksi_data_01b_terapkan_poin.sql.
--
-- Yang perlu diperiksa mata sendiri:
--   · Apakah jumlah notanya wajar? Barbershop baru buka, seharusnya sedikit.
--   · Apakah "poin_seharusnya" tepat 10/7 kali "poin_sekarang"?
--   · Apakah ada nota yang poinnya diperoleh pada tarif SELAIN 7%? Tarif tidak
--     disimpan per nota, jadi hanya mata yang dapat menangkapnya. Nota yang
--     rasionya terlihat aneh jangan diterapkan — kabari lebih dulu.
-- =============================================================================

-- ── Tarif yang berlaku sekarang ─────────────────────────────────────────────
SELECT 'tarif poin saat ini' AS periksa,
       earn_percent::TEXT     AS nilai,
       CASE WHEN earn_percent = 10 THEN 'sudah 10%'
            ELSE 'MASIH ' || earn_percent || '% — skrip 01b akan menaikkannya' END AS keterangan
  FROM loyalty_settings;

-- ── Nota yang akan disesuaikan ──────────────────────────────────────────────
SELECT t.invoice_no                                        AS nota,
       t.business_date                                     AS tanggal,
       m.name                                              AS member,
       t.member_phone                                      AS whatsapp,
       t.final_amount                                      AS dibayar,
       t.points_earned                                     AS poin_sekarang,
       floor(t.points_earned * 10.0 / 7.0)::INT            AS poin_seharusnya,
       floor(t.points_earned * 10.0 / 7.0)::INT
         - t.points_earned                                 AS tambahan,
       round(t.points_earned * 100.0 / NULLIF(t.final_amount, 0), 2) AS persen_terpakai
  FROM transactions t
  JOIN members m ON m.id = t.member_id
 WHERE t.member_id IS NOT NULL
   AND t.points_earned > 0
   AND NOT EXISTS (SELECT 1 FROM point_ledger l
                    WHERE l.transaction_id = t.id
                      AND l.type  = 'ADJUSTMENT'
                      AND l.notes = 'Penyesuaian cashback 7% menjadi 10%')
 ORDER BY t.created_at;

-- ── Ringkasan per member ────────────────────────────────────────────────────
SELECT m.name                        AS member,
       m.tier                        AS level_sekarang,
       m.points_balance              AS saldo_sekarang,
       m.lifetime_points             AS seumur_hidup_sekarang,
       SUM(floor(t.points_earned * 10.0 / 7.0)::INT - t.points_earned) AS tambahan,
       m.points_balance
         + SUM(floor(t.points_earned * 10.0 / 7.0)::INT - t.points_earned) AS saldo_setelah,
       compute_tier((m.lifetime_points
         + SUM(floor(t.points_earned * 10.0 / 7.0)::INT - t.points_earned))::INT) AS level_setelah
  FROM transactions t
  JOIN members m ON m.id = t.member_id
 WHERE t.member_id IS NOT NULL
   AND t.points_earned > 0
   AND NOT EXISTS (SELECT 1 FROM point_ledger l
                    WHERE l.transaction_id = t.id
                      AND l.type  = 'ADJUSTMENT'
                      AND l.notes = 'Penyesuaian cashback 7% menjadi 10%')
 GROUP BY m.id, m.name, m.tier, m.points_balance, m.lifetime_points
 ORDER BY m.name;
