/**
 * ai-asisten — owner bertanya soal data operasional toko, lewat OpenRouter.
 *
 * Add-on AI, fitur 5 bagian "Internal Helper" (#INV/BU-AI/2026/019).
 * "Omzet minggu ini berapa?", "kapster siapa paling ramai bulan ini?",
 * "produk apa yang mau habis?" — dijawab dari data toko yang sebenarnya.
 *
 * MODEL HANYA MEMBACA RINGKASAN. Data diambil dari ringkasan_asisten()
 * (migrasi 58), satu ringkasan tetap yang dihitung basis data. Model tidak
 * pernah menulis query dan tidak punya akses ke tabel mana pun. Pertanyaan
 * yang jawabannya tidak ada di ringkasan harus dijawab "datanya tidak
 * tersedia" — angka karangan dalam laporan keuangan lebih merusak daripada
 * tidak ada jawaban.
 *
 * HANYA OWNER. Ringkasan memuat omzet, pengeluaran, dan absensi karyawan.
 * ringkasan_asisten() hanya dapat dipanggil service_role, dan fungsi ini
 * memanggilnya SESUDAH memastikan pemanggilnya owner.
 *
 * Isi percakapan tidak disimpan di mana pun.
 *
 * KUNCI, MODEL, DAN BATAS
 *   OPENROUTER_API_KEY sama dengan ai-struk. Model: MODEL_AI_ASISTEN, lalu
 *   MODEL_AI, bawaan google/gemini-3.5-flash-lite. Batas: BATAS_ASISTEN_HARIAN,
 *   bawaan 100 pertanyaan per hari, dihitung di ai_pemakaian dengan fitur
 *   'asisten' sebelum model AI dihubungi.
 */

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

// Kunci layanan dan URL: urutan dan alasannya sama dengan ai-struk.
function kunciRahasiaBaru(): string {
  try {
    const kamus = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}');
    const nilai = Object.values(kamus ?? {}).find((v) => typeof v === 'string' && v.length > 0);
    return typeof nilai === 'string' ? nilai : '';
  } catch {
    return '';
  }
}
const URL_SB    = Deno.env.get('SUPABASE_URL') ?? 'https://grzjfnqljjzjkvmgtohe.supabase.co';
const KUNCI_SRV = Deno.env.get('KUNCI_LAYANAN') || kunciRahasiaBaru()
               || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const BATAS_HARIAN = Number(Deno.env.get('BATAS_ASISTEN_HARIAN') ?? '100') || 100;

const MODEL = Deno.env.get('MODEL_AI_ASISTEN') || Deno.env.get('MODEL_AI') || 'google/gemini-3.5-flash-lite';

const MAKS_PESAN = 10;          // riwayat yang dikirim ulang tiap pertanyaan
const MAKS_PANJANG = 600;       // karakter per pesan
const PANJANG_MAKS_JAWABAN = 2000;

const ASAL_BAWAAN = [
  'https://underratedbarbershop.com',
  'https://www.underratedbarbershop.com',
  'http://localhost:3000',
];
const ASAL_ENV = (Deno.env.get('ORIGIN_DIIZINKAN') ?? '')
  .split(',').map((s) => s.trim()).filter(Boolean);
const DAFTAR_ASAL = ASAL_ENV.length ? ASAL_ENV : ASAL_BAWAAN;

function headerCors(asal: string | null): Record<string, string> {
  const h: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
  if (asal && DAFTAR_ASAL.includes(asal)) h['Access-Control-Allow-Origin'] = asal;
  return h;
}

function jawab(isi: unknown, status: number, asal: string | null): Response {
  return new Response(JSON.stringify(isi), {
    status,
    headers: { ...headerCors(asal), 'Content-Type': 'application/json' },
  });
}

const SKEMA_JAWABAN = {
  type: 'object',
  properties: {
    data_cukup: { type: 'boolean', description: 'false bila jawabannya tidak ada di DATA TOKO' },
    jawaban: { type: 'string', description: 'Jawaban singkat, bahasa Indonesia sehari-hari, teks biasa tanpa markdown' },
  },
  required: ['data_cukup', 'jawaban'],
  additionalProperties: false,
} as const;

const INSTRUKSI = `Anda asisten internal pemilik Underrated Barbershop. Pemilik bertanya soal data operasional tokonya dengan bahasa sehari-hari.

SATU-SATUNYA SUMBER FAKTA adalah DATA TOKO di bawah (JSON). Aturannya:
- Setiap angka di jawaban harus berasal dari DATA TOKO, atau dihitung langsung darinya (menjumlah, mengurangi, membandingkan, merata-rata). Bila Anda menghitung, sebutkan dasarnya singkat.
- Bila jawabannya tidak ada di DATA TOKO, katakan terus terang bahwa datanya tidak tersedia di asisten ini, sebutkan data apa yang tersedia, dan isi data_cukup: false. JANGAN mengarang, memperkirakan, atau menebak angka.
- DATA TOKO hanya mencakup: ringkasan per bulan untuk tiga bulan terakhir (bulan berjalan sampai hari ini), omzet harian 60 hari terakhir, stok produk saat ini, 15 pengeluaran terakhir, absensi bulan ini, jumlah member, booking 7 hari ke depan, dan daftar karyawan aktif. Data lain (nama atau nomor pelanggan, transaksi satu per satu, gaji, data lebih lama) tidak tersedia.
- Hari tanpa baris di harian_60_hari berarti tidak ada transaksi (omzet 0).
- "Minggu ini" berarti Senin sampai hari ini. "Kemarin", "minggu lalu", dan sejenisnya dihitung dari hari_ini.
- omzet adalah jumlah yang benar-benar dibayar pelanggan, sesudah diskon. nilai di kapster, layanan_teratas, dan produk_terjual adalah harga sebelum diskon nota.
- Rupiah ditulis "Rp 1.250.000". Tanggal ditulis "6 Oktober".
- Jawab singkat dan langsung ke angkanya. Teks biasa, tanpa markdown, tanpa tabel; daftar pendek boleh memakai baris baru dan tanda "-".
- Hanya soal operasional toko ini. Pertanyaan di luar itu dijawab bahwa Anda hanya membantu soal data toko.`;

async function catatPemakaian(
  // deno-lint-ignore no-explicit-any
  sbSrv: SupabaseClient<any, any, any>,
  baris: Record<string, unknown>,
) {
  const { error } = await sbSrv.from('ai_pemakaian').insert(baris);
  if (error) console.error('ai_pemakaian gagal dicatat:', error.message);
}

Deno.serve(async (req: Request) => {
  const asal = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: headerCors(asal) });
  if (req.method !== 'POST') return jawab({ error: 'Metode tidak didukung.' }, 405, asal);

  if (!KUNCI_SRV) {
    return jawab({ error: 'Fungsi belum lengkap dipasang: secret KUNCI_LAYANAN belum diisi. Hubungi pengembang.' }, 503, asal);
  }

  /* ── Pemanggilnya owner ─────────────────────────────────────────────── */
  const otorisasi = req.headers.get('Authorization') ?? '';
  const jwt = otorisasi.startsWith('Bearer ') ? otorisasi.slice(7) : '';
  if (!jwt) return jawab({ error: 'Tidak ada sesi. Masuk lagi lalu coba ulang.' }, 401, asal);

  const sbSrv = createClient(URL_SB, KUNCI_SRV, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: pengguna, error: galatJwt } = await sbSrv.auth.getUser(jwt);
  if (galatJwt || !pengguna?.user) {
    // Alasan dari Auth dicatat dan ikut dikirim. Tanpa itu "sesi tidak
    // dikenali" tidak dapat dibedakan antara token kedaluwarsa dan kunci
    // layanan yang salah. Isinya teks galat Auth, bukan data siapa pun.
    console.error('ai-asisten: getUser', galatJwt?.status, galatJwt?.message);
    return jawab({
      error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.',
      alasan: String(galatJwt?.message ?? 'pengguna tidak ditemukan').slice(0, 120),
    }, 401, asal);
  }
  const { data: profil } = await sbSrv.from('profiles').select('role').eq('id', pengguna.user.id).single();
  if (profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh memakai asisten ini.' }, 403, asal);
  }

  /* ── Batas harian, diperiksa SEBELUM model AI dihubungi ──────────── */
  const hariIni = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(new Date());
  const namaHari = new Intl.DateTimeFormat('id-ID', { timeZone: 'Asia/Jakarta', weekday: 'long' }).format(new Date());
  const sejakUtc = new Date(hariIni + 'T00:00:00+07:00');
  const { count: dipakai } = await sbSrv.from('ai_pemakaian')
    .select('id', { count: 'exact', head: true })
    .eq('fitur', 'asisten').gte('created_at', sejakUtc.toISOString());
  if ((dipakai ?? 0) >= BATAS_HARIAN) {
    return jawab({ error: `Batas ${BATAS_HARIAN} pertanyaan per hari sudah tercapai. Coba lagi besok.` }, 429, asal);
  }

  /* ── Masukan ──────────────────────────────────────────────────────── */
  let badan: Record<string, unknown>;
  try { badan = await req.json(); } catch { return jawab({ error: 'Permintaan tidak terbaca.' }, 400, asal); }

  const mentah = Array.isArray(badan.pesan) ? badan.pesan : [];
  const pesan = mentah.slice(-MAKS_PESAN)
    .filter((p): p is { peran: string; teks: string } =>
      !!p && typeof p === 'object' && typeof (p as { teks?: unknown }).teks === 'string')
    .map((p) => ({
      role: p.peran === 'asisten' ? 'assistant' : 'user',
      content: p.teks.slice(0, p.peran === 'asisten' ? PANJANG_MAKS_JAWABAN : MAKS_PANJANG),
    }));
  if (!pesan.length || pesan[pesan.length - 1].role !== 'user' || !pesan[pesan.length - 1].content.trim()) {
    return jawab({ error: 'Tulis pertanyaannya dulu.' }, 400, asal);
  }

  /* ── Data toko ────────────────────────────────────────────────────── */
  const { data: ringkasan, error: galatData } = await sbSrv.rpc('ringkasan_asisten', { p_hari_ini: hariIni });
  if (galatData || !ringkasan) {
    console.error('ai-asisten: ringkasan', galatData?.message);
    return jawab({ error: 'Data toko tidak dapat dibaca. Pastikan migrasi 58 sudah dijalankan, lalu coba lagi.' }, 502, asal);
  }

  /* ── OpenRouter ───────────────────────────────────────────────────── */
  const kunciAi = Deno.env.get('OPENROUTER_API_KEY') ?? '';
  if (!kunciAi) {
    return jawab({ error: 'Kunci AI belum dipasang (secret OPENROUTER_API_KEY). Hubungi pengembang.' }, 503, asal);
  }

  const sistem = `${INSTRUKSI}\n\nHari ini ${namaHari}, ${hariIni}.\n\nDATA TOKO\n${JSON.stringify(ringkasan)}`;
  const pakaiDasar = { fitur: 'asisten', pemanggil: pengguna.user.id };

  let res: Response;
  try {
    res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${kunciAi}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://underratedbarbershop.com',
        'X-Title': 'Underrated Barbershop',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 3000,
        messages: [{ role: 'system', content: sistem }, ...pesan],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'jawaban_asisten', strict: true, schema: SKEMA_JAWABAN },
        },
        // Lihat ai-struk: require_parameters tanpa parameter reasoning.
        provider: { require_parameters: true },
      }),
    });
  } catch (e) {
    console.error('ai-asisten: jaringan', e instanceof Error ? e.message : e);
    await catatPemakaian(sbSrv, { ...pakaiDasar, berhasil: false, model: MODEL, keterangan: 'galat jaringan' });
    return jawab({ error: 'Layanan AI tidak dapat dihubungi. Coba lagi sebentar lagi.' }, 502, asal);
  }

  // deno-lint-ignore no-explicit-any
  let data: any = null;
  try { data = await res.json(); } catch { /* ditangani di bawah */ }

  const kodeGalat: number = !res.ok ? res.status : (data?.error ? Number(data.error.code) || 502 : 0);
  if (kodeGalat) {
    let pesanGalat = 'Asisten gagal menjawab. Coba lagi sebentar lagi.';
    let status = 502;
    if (kodeGalat === 401) {
      pesanGalat = 'Kunci AI tidak berlaku. Hubungi pengembang.'; status = 503;
    } else if (kodeGalat === 402) {
      pesanGalat = 'Saldo layanan AI habis. Hubungi pengembang untuk mengisi ulang.'; status = 503;
    } else if (kodeGalat === 429) {
      pesanGalat = 'Layanan AI sedang sibuk. Coba lagi dalam satu menit.'; status = 429;
    } else if (kodeGalat === 400 || kodeGalat === 403) {
      pesanGalat = 'Pertanyaan ditolak oleh layanan AI. Coba tanyakan dengan kalimat lain.'; status = 400;
    }
    console.error('ai-asisten: openrouter', kodeGalat, data?.error?.message);
    await catatPemakaian(sbSrv, { ...pakaiDasar, berhasil: false, model: MODEL, keterangan: `openrouter ${kodeGalat}` });
    return jawab({ error: pesanGalat }, status, asal);
  }

  const pilihan = data?.choices?.[0];
  const biaya = typeof data?.usage?.cost === 'number' ? `biaya $${data.usage.cost}` : '';
  const pakai = {
    ...pakaiDasar, model: data?.model ?? MODEL,
    input_tokens: data?.usage?.prompt_tokens ?? 0,
    output_tokens: data?.usage?.completion_tokens ?? 0,
  };

  if (pilihan?.message?.refusal) {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: ['refusal', biaya].filter(Boolean).join(', ') });
    return jawab({ error: 'Pertanyaan ini tidak dapat dijawab. Coba tanyakan dengan kalimat lain.' }, 422, asal);
  }
  if (pilihan?.finish_reason === 'length') {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: ['length', biaya].filter(Boolean).join(', ') });
    return jawab({ error: 'Jawabannya terlalu panjang. Coba persempit pertanyaannya.' }, 422, asal);
  }

  const isiJawaban = typeof pilihan?.message?.content === 'string' ? pilihan.message.content : '';
  // deno-lint-ignore no-explicit-any
  let hasil: any;
  try {
    hasil = JSON.parse(isiJawaban);
  } catch {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: ['json tidak sah', biaya].filter(Boolean).join(', ') });
    return jawab({ error: 'Jawaban tidak dapat diolah. Coba lagi.' }, 502, asal);
  }

  const teks = String(hasil?.jawaban ?? '').trim().slice(0, PANJANG_MAKS_JAWABAN);
  await catatPemakaian(sbSrv, { ...pakai, berhasil: true, keterangan: biaya || null });
  return jawab({
    jawaban: teks || 'Maaf, saya tidak bisa menjawab itu dari data toko.',
    data_cukup: hasil?.data_cukup !== false,
    sisa_hari_ini: Math.max(0, BATAS_HARIAN - (dipakai ?? 0) - 1),
  }, 200, asal);
});
