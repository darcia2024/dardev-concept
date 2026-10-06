/**
 * ai-struk — membaca foto struk belanja dengan Claude.
 *
 * Add-on AI, fitur 1 (#INV/BU-AI/2026/019). Owner memotret struk kulakan,
 * fungsi ini mengembalikan barang, jumlah, harga, tanggal, dan total dalam
 * bentuk terstruktur.
 *
 * FUNGSI INI TIDAK MENYIMPAN APA PUN KE PEMBUKUAN. Hasilnya dikembalikan ke
 * layar owner untuk diperiksa dan dibetulkan, dan baru tersimpan lewat
 * owner_simpan_pengeluaran() saat owner menekan Simpan. Struk kusut dan nota
 * tulisan tangan adalah keadaan biasa; pengeluaran yang salah tercatat terlihat
 * seperti fakta, dan itu lebih merusak daripada mengetik sendiri.
 *
 * KUNCI API
 *   ANTHROPIC_API_KEY disimpan sebagai secret Supabase. Tidak pernah dikirim ke
 *   peramban: siapa pun yang memegangnya dapat memakai akun API itu atas tagihan
 *   pemiliknya.
 *
 * BATAS HARIAN
 *   Setiap panggilan dicatat di ai_pemakaian. Bila jumlah panggilan hari ini
 *   sudah mencapai BATAS_STRUK_HARIAN (bawaan 60), panggilan berikutnya
 *   ditolak sebelum Claude dihubungi — jadi tidak ditagih.
 */

import Anthropic from 'npm:@anthropic-ai/sdk';
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

/* Kunci layanan, dari yang paling diutamakan:

   1. KUNCI_LAYANAN — secret yang dipasang owner sendiri, bila suatu saat
      perlu memakai kunci tertentu.
   2. SUPABASE_SECRET_KEYS — kunci jenis baru (sb_secret_), disuntikkan
      Supabase sebagai kamus JSON. Diambil nilai pertamanya alih-alih
      menebak nama kuncinya di dalam kamus itu.
   3. SUPABASE_SERVICE_ROLE_KEY — kunci jenis lama. Dashboard menandainya
      DEPRECATED: masih disuntikkan hari ini, tetapi akan hilang begitu
      kunci lama dimatikan. Hanya cadangan terakhir.

   URL proyek jatuh ke alamat yang memang sudah publik di sb-app.js bila
   SUPABASE_URL tidak ada. */
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
const BATAS_HARIAN = Number(Deno.env.get('BATAS_STRUK_HARIAN') ?? '60') || 60;

const MODEL = 'claude-opus-5-5';

const JENIS_GAMBAR = ['image/jpeg', 'image/png', 'image/webp'] as const;
type JenisGambar = typeof JENIS_GAMBAR[number];
const jenisSah = (j: string): j is JenisGambar => (JENIS_GAMBAR as readonly string[]).includes(j);

/* Foto dari kamera HP bisa 4-8 MB. Layar sudah memperkecilnya sebelum
   mengirim; batas ini menjaga dari klien yang tidak melakukannya. */
const UKURAN_MAKS_BASE64 = 7_000_000;

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

/* Skema hasil bacaan. Diberikan ke Claude lewat structured outputs, sehingga
   jawabannya selalu JSON yang sah menurut skema ini — tidak perlu menebak
   apakah ia menyisipkan kalimat pengantar. Semua angka dalam rupiah penuh. */
const SKEMA_STRUK = {
  type: 'object',
  properties: {
    toko: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Nama toko atau penjual, null bila tidak terbaca' },
    tanggal: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Tanggal belanja, format YYYY-MM-DD, null bila tidak terbaca' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          nama: { type: 'string' },
          qty: { type: 'number' },
          harga_satuan: { type: 'number', description: 'Rupiah per satuan' },
          subtotal: { type: 'number', description: 'Rupiah untuk baris ini' },
        },
        required: ['nama', 'qty', 'harga_satuan', 'subtotal'],
        additionalProperties: false,
      },
    },
    total: { anyOf: [{ type: 'number' }, { type: 'null' }], description: 'Total yang dibayar menurut struk, null bila tidak terbaca' },
    terbaca: { type: 'boolean', description: 'false bila gambar bukan struk atau sama sekali tidak terbaca' },
    catatan: { anyOf: [{ type: 'string' }, { type: 'null' }], description: 'Bagian yang ragu atau tidak terbaca, singkat, bahasa Indonesia' },
  },
  required: ['toko', 'tanggal', 'items', 'total', 'terbaca', 'catatan'],
  additionalProperties: false,
} as const;

const INSTRUKSI = `Anda membaca foto struk belanja sebuah barbershop di Indonesia — nota toko grosir, minimarket, struk kasir, atau nota tulisan tangan.

Tuliskan setiap barang yang dibeli apa adanya seperti di struk. Angka rupiah ditulis sebagai angka penuh tanpa titik pemisah ribuan: "Rp 12.500" menjadi 12500. Bila hanya subtotal yang tertera, harga_satuan adalah subtotal dibagi qty. Bila qty tidak tertulis, anggap 1.

Jangan menebak. Bila sebuah angka atau nama tidak terbaca jelas, tetap tuliskan bacaan terbaik Anda lalu sebutkan keraguannya di catatan, supaya pemilik toko tahu baris mana yang harus ia periksa. Diskon, pajak, dan biaya layanan bukan barang: jangan dimasukkan ke items, tetapi total tetap total yang benar-benar dibayar.

Bila gambar bukan struk belanja, kembalikan terbaca: false dengan items kosong.`;

async function catatPemakaian(
  // deno-lint-ignore no-explicit-any
  sbSrv: SupabaseClient<any, any, any>,
  baris: Record<string, unknown>,
) {
  // Kegagalan mencatat tidak boleh menggagalkan jawaban kepada owner, tetapi
  // juga tidak boleh ditelan diam-diam: tanpa catatan, batas harian bocor.
  const { error } = await sbSrv.from('ai_pemakaian').insert(baris);
  if (error) console.error('ai_pemakaian gagal dicatat:', error.message);
}

Deno.serve(async (req: Request) => {
  const asal = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: headerCors(asal) });
  if (req.method !== 'POST') return jawab({ error: 'Metode tidak didukung.' }, 405, asal);

  // Tanpa kunci layanan, fungsi ini tidak dapat memeriksa siapa pemanggilnya.
  // Lebih baik berhenti dengan pesan yang menyebut sebabnya daripada galat
  // "Invalid API key" yang tidak dapat ditindaklanjuti siapa pun.
  if (!KUNCI_SRV) {
    return jawab({ error: 'Fungsi belum lengkap dipasang: secret KUNCI_LAYANAN belum diisi. Hubungi pengembang.' }, 503, asal);
  }

  /* ── Pemanggilnya owner ─────────────────────────────────────────────── */
  const otorisasi = req.headers.get('Authorization') ?? '';
  const jwt = otorisasi.startsWith('Bearer ') ? otorisasi.slice(7) : '';
  if (!jwt) return jawab({ error: 'Tidak ada sesi. Masuk lagi lalu coba ulang.' }, 401, asal);

  /* JWT pemanggil diverifikasi dengan klien service-role yang sama, bukan
     dengan klien anon. Proyek ini memakai kunci jenis baru (sb_publishable_),
     dan SUPABASE_ANON_KEY adalah kunci jenis lama yang dapat dimatikan dari
     dashboard — fungsi yang bergantung padanya akan berhenti tanpa ada yang
     mengubah kodenya. */
  const sbSrv = createClient(URL_SB, KUNCI_SRV, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: pengguna, error: galatJwt } = await sbSrv.auth.getUser(jwt);
  if (galatJwt || !pengguna?.user) {
    return jawab({ error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.' }, 401, asal);
  }
  const { data: profil } = await sbSrv.from('profiles').select('role').eq('id', pengguna.user.id).single();
  if (profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh membaca struk.' }, 403, asal);
  }

  /* ── Batas harian, diperiksa SEBELUM Claude dihubungi ──────────────── */
  // Tanggal hari ini menurut jam outlet, lalu tengah malamnya dalam WIB.
  // WIB tidak punya musim panas, jadi +07:00 selalu benar.
  const hariIni = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(new Date());
  const sejakUtc = new Date(hariIni + 'T00:00:00+07:00');
  const { count: dipakai } = await sbSrv.from('ai_pemakaian')
    .select('id', { count: 'exact', head: true })
    .eq('fitur', 'struk').gte('created_at', sejakUtc.toISOString());
  if ((dipakai ?? 0) >= BATAS_HARIAN) {
    return jawab({
      error: `Batas ${BATAS_HARIAN} struk per hari sudah tercapai. Coba lagi besok, atau isi pengeluaran secara manual.`,
    }, 429, asal);
  }

  /* ── Masukan ──────────────────────────────────────────────────────── */
  let badan: Record<string, unknown>;
  try { badan = await req.json(); } catch { return jawab({ error: 'Permintaan tidak terbaca.' }, 400, asal); }

  const gambar = String(badan.gambar ?? '');
  const jenis = String(badan.jenis ?? 'image/jpeg');
  if (!jenisSah(jenis)) {
    return jawab({ error: 'Format gambar harus JPEG, PNG, atau WebP.' }, 400, asal);
  }
  if (!gambar || !/^[A-Za-z0-9+/=]+$/.test(gambar)) {
    return jawab({ error: 'Gambar tidak terbaca.' }, 400, asal);
  }
  if (gambar.length > UKURAN_MAKS_BASE64) {
    return jawab({ error: 'Foto terlalu besar. Potret ulang lebih dekat ke struknya.' }, 413, asal);
  }

  /* ── Claude ───────────────────────────────────────────────────────── */
  const claude = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') });

  try {
    const res = await claude.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      // Pembacaan struk tidak menuntut penalaran panjang, tetapi struk kusut
      // dan tulisan tangan butuh ketelitian. medium adalah bawaan model ini;
      // ditulis eksplisit supaya pilihan itu terlihat dan dapat disetel.
      output_config: {
        effort: 'medium',
        format: { type: 'json_schema', schema: SKEMA_STRUK },
      },
      // Bila pemeriksa keamanan model menolak sebuah gambar secara keliru,
      // server mencoba ulang dengan model cadangan yang direkomendasikan,
      // alih-alih owner menerima penolakan tanpa penjelasan.
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: INSTRUKSI,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: jenis, data: gambar } },
          { type: 'text', text: 'Baca struk ini.' },
        ],
      }],
    });

    const pakai = {
      fitur: 'struk', model: res.model, pemanggil: pengguna.user.id,
      input_tokens: res.usage?.input_tokens ?? 0,
      output_tokens: res.usage?.output_tokens ?? 0,
    };

    if (res.stop_reason === 'refusal') {
      await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'refusal' });
      return jawab({ error: 'Gambar ini tidak dapat dibaca. Coba potret ulang struknya saja, tanpa latar lain.' }, 422, asal);
    }
    if (res.stop_reason === 'max_tokens') {
      await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'max_tokens' });
      return jawab({ error: 'Struk terlalu panjang untuk dibaca sekaligus. Potret per bagian.' }, 422, asal);
    }

    const teks = res.content.find((b) => b.type === 'text');
    let hasil: unknown;
    try {
      hasil = JSON.parse(teks && teks.type === 'text' ? teks.text : '');
    } catch {
      await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'json tidak sah' });
      return jawab({ error: 'Hasil bacaan tidak dapat diolah. Coba lagi.' }, 502, asal);
    }

    await catatPemakaian(sbSrv, { ...pakai, berhasil: true });
    return jawab({ hasil, sisa_hari_ini: Math.max(0, BATAS_HARIAN - (dipakai ?? 0) - 1) }, 200, asal);
  } catch (e) {
    // Urutan dari yang paling khusus. Pesan teknisnya tidak diteruskan ke
    // layar owner — ia tidak dapat menindaklanjutinya — tetapi dicatat.
    let pesan = 'Pembacaan struk gagal. Coba lagi sebentar lagi.';
    let status = 502;
    if (e instanceof Anthropic.AuthenticationError) {
      pesan = 'Kunci API AI belum dipasang atau sudah tidak berlaku. Hubungi pengembang.';
      status = 503;
    } else if (e instanceof Anthropic.RateLimitError) {
      pesan = 'Layanan AI sedang sibuk. Coba lagi dalam satu menit.';
      status = 429;
    } else if (e instanceof Anthropic.BadRequestError) {
      pesan = 'Gambar ditolak oleh layanan AI. Coba foto lain.';
      status = 400;
    }
    console.error('ai-struk:', e instanceof Error ? e.message : e);
    await catatPemakaian(sbSrv, {
      fitur: 'struk', berhasil: false, model: MODEL, pemanggil: pengguna.user.id,
      keterangan: e instanceof Anthropic.APIError ? `api ${e.status}` : 'galat jaringan',
    });
    return jawab({ error: pesan }, status, asal);
  }
});
