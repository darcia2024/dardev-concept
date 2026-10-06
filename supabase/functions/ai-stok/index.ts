/**
 * ai-stok — catatan stok dari ketikan, voice note, atau foto, lewat OpenRouter.
 *
 * Add-on AI, fitur 3 bagian stok (#INV/BU-AI/2026/019). Owner menulis
 * "pomade sisa 12, clay datang 2 lusin", merekam suara sambil menghitung rak,
 * atau memotret catatan stok tulisan tangan. Fungsi ini mencocokkan setiap
 * baris dengan produk di katalog dan mengembalikan usulan mutasi.
 *
 * FUNGSI INI TIDAK MENYIMPAN APA PUN. Usulannya dikembalikan ke layar owner
 * untuk diperiksa, dan baru tercatat lewat owner_stok_catat() saat owner
 * menekan Simpan. Nama yang salah dicocokkan ("clay" ke Matte Clay padahal
 * maksudnya Clay Wax) menggeser stok dua produk sekaligus tanpa terlihat.
 *
 * PRODUK DICOCOKKAN DI SINI, BUKAN DIPERCAYA DARI MODEL. Model hanya boleh
 * menyebut nama yang persis ada di daftar katalog; nama itu dipetakan ke id
 * oleh kode ini. Nama yang tidak cocok dikembalikan tanpa id, dan layar owner
 * memintanya memilih produknya sendiri. Id produk tidak pernah dikarang model.
 *
 * Rekaman suara dan foto tidak disimpan di mana pun.
 *
 * KUNCI, MODEL, DAN BATAS
 *   OPENROUTER_API_KEY sama dengan ai-struk. Model: MODEL_AI_STOK, lalu
 *   MODEL_AI, bawaan google/gemini-3.5-flash-lite (menerima gambar, audio,
 *   dan structured outputs). Batas: BATAS_STOK_HARIAN, bawaan 40, dihitung
 *   di ai_pemakaian dengan fitur 'stok' sebelum model AI dihubungi.
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
const BATAS_HARIAN = Number(Deno.env.get('BATAS_STOK_HARIAN') ?? '40') || 40;

const MODEL = Deno.env.get('MODEL_AI_STOK') || Deno.env.get('MODEL_AI') || 'google/gemini-3.5-flash-lite';

// Batasnya sama dengan ai-rapikan (teks, audio) dan ai-struk (gambar).
const TEKS_MAKS = 6000;
const AUDIO_MAKS_BASE64 = 8_000_000;
const DETIK_MAKS = 185;
const GAMBAR_MAKS_BASE64 = 7_000_000;
const JENIS_GAMBAR = ['image/jpeg', 'image/png', 'image/webp'];

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

/* Tanpa null dan tanpa anyOf — alasannya sama dengan ai-struk. Nama produk
   yang tidak dikenali ditulis sebagai teks kosong. */
const SKEMA_STOK = {
  type: 'object',
  properties: {
    terbaca: { type: 'boolean', description: 'false bila masukan kosong, tidak terdengar, atau bukan catatan stok' },
    baris: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          produk: { type: 'string', description: 'Nama produk PERSIS seperti di daftar katalog; teks kosong bila tidak ada yang cocok' },
          disebut: { type: 'string', description: 'Nama barang seperti ditulis atau diucapkan pemilik' },
          jenis: { type: 'string', enum: ['hitung', 'masuk', 'keluar'] },
          qty: { type: 'number', description: 'Jumlah dalam satuan (pcs), bukan lusin atau dus' },
        },
        required: ['produk', 'disebut', 'jenis', 'qty'],
        additionalProperties: false,
      },
    },
    catatan: { type: 'string', description: 'Bagian yang ragu, singkat; teks kosong bila semua jelas' },
  },
  required: ['terbaca', 'baris', 'catatan'],
  additionalProperties: false,
} as const;

function instruksi(katalog: string[]): string {
  return `Anda membantu pemilik Underrated Barbershop mencatat stok produk retail (pomade, clay, hair tonic, dan sejenisnya). Masukannya bisa berupa ketikan asal-asalan, rekaman suara, atau foto catatan stok tulisan tangan — dalam bahasa Indonesia sehari-hari.

Ubah setiap barang yang disebut menjadi satu baris:
- jenis "hitung": pemilik menyebut SISA atau jumlah yang ADA di rak ("pomade sisa 12", "clay tinggal 3", "tonic ada 7"). qty adalah jumlah yang dihitung itu.
- jenis "masuk": barang DATANG atau DITAMBAH ("clay datang 24", "restock tonic 10").
- jenis "keluar": barang RUSAK, HILANG, KADALUARSA, atau DIPAKAI SENDIRI ("pomade pecah 1").
- Penjualan ke pelanggan BUKAN tugas Anda — kasir sudah mencatatnya. Bila pemilik menyebut "laku" atau "terjual", jangan dibuat baris; sebutkan di catatan.

qty selalu dalam satuan buah. "2 lusin" = 24, "setengah lusin" = 6, "1 dus isi 12" = 12. Bila isi dus tidak disebut, tulis bacaan terbaik dan sebutkan keraguannya di catatan.

Kolom produk HARUS salah satu nama di daftar katalog di bawah, ditulis persis sama. Bila barang yang disebut tidak jelas cocok dengan satu nama, atau cocok dengan lebih dari satu nama, tulis produk sebagai teks kosong dan sebutkan di catatan — pemilik akan memilihnya sendiri. Jangan menebak. Kolom disebut selalu berisi nama seperti yang ditulis atau diucapkan pemilik.

Jangan menambah barang yang tidak disebut, dan jangan mengarang angka. Bila masukan kosong, tidak terdengar, atau bukan catatan stok, kembalikan terbaca: false dengan baris kosong.

Daftar katalog:
${katalog.length ? katalog.map((n) => '- ' + n).join('\n') : '(kosong)'}`;
}

async function catatPemakaian(
  // deno-lint-ignore no-explicit-any
  sbSrv: SupabaseClient<any, any, any>,
  baris: Record<string, unknown>,
) {
  const { error } = await sbSrv.from('ai_pemakaian').insert(baris);
  if (error) console.error('ai_pemakaian gagal dicatat:', error.message);
}

const normal = (s: string) => s.toLowerCase().replace(/\s+/g, ' ').trim();

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
    console.error('ai-stok: getUser', galatJwt?.status, galatJwt?.message);
    return jawab({
      error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.',
      alasan: String(galatJwt?.message ?? 'pengguna tidak ditemukan').slice(0, 120),
    }, 401, asal);
  }
  const { data: profil } = await sbSrv.from('profiles').select('role').eq('id', pengguna.user.id).single();
  if (profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh mencatat stok.' }, 403, asal);
  }

  /* ── Batas harian, diperiksa SEBELUM model AI dihubungi ──────────── */
  const hariIni = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(new Date());
  const sejakUtc = new Date(hariIni + 'T00:00:00+07:00');
  const { count: dipakai } = await sbSrv.from('ai_pemakaian')
    .select('id', { count: 'exact', head: true })
    .eq('fitur', 'stok').gte('created_at', sejakUtc.toISOString());
  if ((dipakai ?? 0) >= BATAS_HARIAN) {
    return jawab({ error: `Batas ${BATAS_HARIAN} kali per hari sudah tercapai. Coba lagi besok, atau isi stok secara manual.` }, 429, asal);
  }

  /* ── Masukan ──────────────────────────────────────────────────────── */
  let badan: Record<string, unknown>;
  try { badan = await req.json(); } catch { return jawab({ error: 'Permintaan tidak terbaca.' }, 400, asal); }

  const teks = String(badan.teks ?? '').trim();
  const audio = String(badan.audio ?? '');
  const detik = Math.round(Number(badan.detik) || 0);
  const gambar = String(badan.gambar ?? '');
  const jenisGambar = String(badan.jenis_gambar ?? 'image/jpeg');

  if (!teks && !audio && !gambar) {
    return jawab({ error: 'Tulis, rekam, atau foto catatan stoknya dulu.' }, 400, asal);
  }
  if (teks.length > TEKS_MAKS) {
    return jawab({ error: `Catatan terlalu panjang (lebih dari ${TEKS_MAKS} huruf).` }, 413, asal);
  }
  if (audio && (!/^[A-Za-z0-9+/=]+$/.test(audio) || audio.length > AUDIO_MAKS_BASE64 || detik > DETIK_MAKS)) {
    return jawab({ error: 'Rekaman tidak terbaca atau lebih dari 3 menit. Rekam ulang.' }, 400, asal);
  }
  if (gambar && (!JENIS_GAMBAR.includes(jenisGambar) || !/^[A-Za-z0-9+/=]+$/.test(gambar) || gambar.length > GAMBAR_MAKS_BASE64)) {
    return jawab({ error: 'Foto tidak terbaca atau terlalu besar. Potret ulang.' }, 400, asal);
  }

  // Katalog dibaca di server, bukan dikirim peramban: daftar inilah yang
  // menjadi satu-satunya nama yang boleh disebut model.
  const { data: produk, error: galatProduk } = await sbSrv.from('products_hpp')
    .select('id, name').eq('is_active', true).order('name').limit(300);
  if (galatProduk) {
    console.error('ai-stok: katalog', galatProduk.message);
    return jawab({ error: 'Katalog produk tidak dapat dibaca. Coba lagi.' }, 502, asal);
  }
  const katalog = (produk ?? []) as { id: string; name: string }[];
  if (!katalog.length) {
    return jawab({ error: 'Belum ada produk aktif di katalog. Tambahkan dulu di HPP & Laba Produk.' }, 400, asal);
  }

  /* ── OpenRouter ───────────────────────────────────────────────────── */
  const kunciAi = Deno.env.get('OPENROUTER_API_KEY') ?? '';
  if (!kunciAi) {
    return jawab({ error: 'Kunci AI belum dipasang (secret OPENROUTER_API_KEY). Hubungi pengembang.' }, 503, asal);
  }

  // Teks lebih dulu, lalu gambar dan audio — urutan yang sama dengan ai-struk.
  const isiPengguna: unknown[] = [
    { type: 'text', text: teks ? `Catatan stok:\n${teks}` : 'Catat stok dari lampiran ini.' },
  ];
  if (gambar) isiPengguna.push({ type: 'image_url', image_url: { url: `data:${jenisGambar};base64,${gambar}` } });
  if (audio) isiPengguna.push({ type: 'input_audio', input_audio: { data: audio, format: 'wav' } });

  const pakaiDasar = {
    fitur: 'stok', pemanggil: pengguna.user.id,
    // Hanya bentuk masukannya yang dicatat, tidak pernah isinya.
    keterangan: [teks ? 'teks' : '', gambar ? 'foto' : '', audio ? `suara ${detik} detik` : ''].filter(Boolean).join('+'),
  };

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
        max_tokens: 5000,
        messages: [
          { role: 'system', content: instruksi(katalog.map((p) => p.name)) },
          { role: 'user', content: isiPengguna },
        ],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'catatan_stok', strict: true, schema: SKEMA_STOK },
        },
        // Lihat ai-struk: require_parameters tanpa parameter reasoning.
        provider: { require_parameters: true },
      }),
    });
  } catch (e) {
    console.error('ai-stok: jaringan', e instanceof Error ? e.message : e);
    await catatPemakaian(sbSrv, { ...pakaiDasar, berhasil: false, model: MODEL, keterangan: pakaiDasar.keterangan + ', galat jaringan' });
    return jawab({ error: 'Layanan AI tidak dapat dihubungi. Coba lagi sebentar lagi.' }, 502, asal);
  }

  // deno-lint-ignore no-explicit-any
  let data: any = null;
  try { data = await res.json(); } catch { /* ditangani di bawah */ }

  const kodeGalat: number = !res.ok ? res.status : (data?.error ? Number(data.error.code) || 502 : 0);
  if (kodeGalat) {
    let pesan = 'Mencatat stok gagal. Coba lagi sebentar lagi.';
    let status = 502;
    if (kodeGalat === 401) {
      pesan = 'Kunci AI tidak berlaku. Hubungi pengembang.'; status = 503;
    } else if (kodeGalat === 402) {
      pesan = 'Saldo layanan AI habis. Hubungi pengembang untuk mengisi ulang. Sementara itu, isi stok secara manual.'; status = 503;
    } else if (kodeGalat === 429) {
      pesan = 'Layanan AI sedang sibuk. Coba lagi dalam satu menit.'; status = 429;
    } else if (kodeGalat === 400 || kodeGalat === 403) {
      pesan = 'Masukan ditolak oleh layanan AI. Coba foto atau rekaman lain, atau ketik saja.'; status = 400;
    }
    console.error('ai-stok: openrouter', kodeGalat, data?.error?.message);
    await catatPemakaian(sbSrv, { ...pakaiDasar, berhasil: false, model: MODEL, keterangan: `${pakaiDasar.keterangan}, openrouter ${kodeGalat}` });
    return jawab({ error: pesan }, status, asal);
  }

  const pilihan = data?.choices?.[0];
  const biaya = typeof data?.usage?.cost === 'number' ? `, biaya $${data.usage.cost}` : '';
  const pakai = {
    ...pakaiDasar, model: data?.model ?? MODEL,
    input_tokens: data?.usage?.prompt_tokens ?? 0,
    output_tokens: data?.usage?.completion_tokens ?? 0,
  };

  if (pilihan?.message?.refusal) {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: pakai.keterangan + ', refusal' + biaya });
    return jawab({ error: 'Catatan ini tidak dapat dibaca. Coba tulis ulang.' }, 422, asal);
  }
  if (pilihan?.finish_reason === 'length') {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: pakai.keterangan + ', length' + biaya });
    return jawab({ error: 'Catatannya terlalu panjang. Pecah jadi beberapa bagian.' }, 422, asal);
  }

  const isiJawaban = typeof pilihan?.message?.content === 'string' ? pilihan.message.content : '';
  // deno-lint-ignore no-explicit-any
  let hasil: any;
  try {
    hasil = JSON.parse(isiJawaban);
  } catch {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: pakai.keterangan + ', json tidak sah' + biaya });
    return jawab({ error: 'Hasil bacaan tidak dapat diolah. Coba lagi.' }, 502, asal);
  }

  /* ── Nama produk dipetakan ke id oleh kode ini ────────────────────── */
  const peta = new Map(katalog.map((p) => [normal(p.name), p]));
  const JENIS = ['hitung', 'masuk', 'keluar'];
  const baris = (Array.isArray(hasil?.baris) ? hasil.baris : []).slice(0, 200).map((b: Record<string, unknown>) => {
    const cocok = peta.get(normal(String(b?.produk ?? '')));
    const qty = Number(b?.qty);
    return {
      product_id: cocok ? cocok.id : '',
      produk: cocok ? cocok.name : '',
      disebut: String(b?.disebut ?? '').slice(0, 150),
      jenis: JENIS.includes(String(b?.jenis)) ? String(b.jenis) : 'hitung',
      qty: Number.isFinite(qty) && qty >= 0 ? qty : 0,
    };
  });

  await catatPemakaian(sbSrv, { ...pakai, berhasil: true, keterangan: pakai.keterangan + biaya });
  return jawab({
    hasil: { terbaca: hasil?.terbaca !== false, baris, catatan: String(hasil?.catatan ?? '').slice(0, 500) },
    sisa_hari_ini: Math.max(0, BATAS_HARIAN - (dipakai ?? 0) - 1),
  }, 200, asal);
});
