/**
 * ai-struk — membaca foto struk belanja dengan model AI lewat OpenRouter.
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
 * KUNCI DAN MODEL
 *   OPENROUTER_API_KEY disimpan sebagai secret Supabase. Tidak pernah dikirim
 *   ke peramban: siapa pun yang memegangnya dapat memakai saldo OpenRouter
 *   pemiliknya.
 *
 *   Modelnya dibaca dari secret MODEL_AI, sehingga dapat diganti dari dashboard
 *   tanpa mengubah kode. Bawaan: google/gemini-3.5-flash-lite — dipilih karena
 *   murah (sekitar $0,002 per struk menurut harga OpenRouter Oktober 2026) dan
 *   mendukung gambar, PDF, serta structured outputs. Model pengganti harus mendukung
 *   keduanya; lihat kolom supported_parameters di openrouter.ai/api/v1/models.
 *
 * BATAS HARIAN
 *   Setiap panggilan dicatat di ai_pemakaian. Bila jumlah panggilan hari ini
 *   sudah mencapai BATAS_STRUK_HARIAN (bawaan 60), panggilan berikutnya
 *   ditolak sebelum model AI dihubungi — jadi tidak ditagih.
 */

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

const MODEL = Deno.env.get('MODEL_AI') || 'google/gemini-3.5-flash-lite';

/* Foto, atau PDF untuk nota belanja online dan struk yang dikirim pemasok
   lewat WhatsApp. PDF dikirim ke model sebagai berkas, bukan gambar
   (openrouter.ai/docs/features/multimodal/pdfs): model yang membaca berkas
   sendiri ditagih sebagai token biasa; model lain dialihkan OpenRouter ke
   OCR, sekitar $2 per 1.000 halaman. */
const JENIS_GAMBAR = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'] as const;
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

/* Skema hasil bacaan, diberikan lewat structured outputs, sehingga jawabannya
   selalu JSON yang sah menurut skema ini. Semua angka dalam rupiah penuh.

   Sengaja TANPA nilai null (anyOf dengan null). OpenRouter meneruskan skema
   ke berbagai penyedia di belakangnya, dan dukungan mereka untuk anyOf tidak
   merata. Bagian yang tidak terbaca ditulis sebagai teks kosong atau 0 —
   layar owner memperlakukan keduanya sebagai "belum diisi". */
const SKEMA_STRUK = {
  type: 'object',
  properties: {
    toko: { type: 'string', description: 'Nama toko atau penjual, teks kosong bila tidak terbaca' },
    tanggal: { type: 'string', description: 'Tanggal belanja, format YYYY-MM-DD, teks kosong bila tidak terbaca' },
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
    total: { type: 'number', description: 'Total yang dibayar menurut struk, 0 bila tidak terbaca' },
    terbaca: { type: 'boolean', description: 'false bila gambar bukan struk atau sama sekali tidak terbaca' },
    catatan: { type: 'string', description: 'Bagian yang ragu atau tidak terbaca, singkat, bahasa Indonesia; teks kosong bila semua jelas' },
  },
  required: ['toko', 'tanggal', 'items', 'total', 'terbaca', 'catatan'],
  additionalProperties: false,
} as const;

const INSTRUKSI = `Anda membaca struk belanja sebuah barbershop di Indonesia, berupa foto atau PDF — nota toko grosir, minimarket, struk kasir, nota tulisan tangan, atau invoice belanja online.

Tuliskan setiap barang yang dibeli apa adanya seperti di struk. Angka rupiah ditulis sebagai angka penuh tanpa titik pemisah ribuan: "Rp 12.500" menjadi 12500. Bila hanya subtotal yang tertera, harga_satuan adalah subtotal dibagi qty. Bila qty tidak tertulis, anggap 1.

Jangan menebak. Bila sebuah angka atau nama tidak terbaca jelas, tetap tuliskan bacaan terbaik Anda lalu sebutkan keraguannya di catatan, supaya pemilik toko tahu baris mana yang harus ia periksa. Diskon, pajak, dan biaya layanan bukan barang: jangan dimasukkan ke items, tetapi total tetap total yang benar-benar dibayar.

Bagian yang sama sekali tidak terbaca: toko dan tanggal ditulis sebagai teks kosong, total ditulis 0. Catatan berisi teks kosong bila semuanya jelas.

Bila PDF berisi beberapa halaman, baca semua barang dari semua halaman sebagai satu belanja.

Bila gambar atau PDF bukan struk belanja, kembalikan terbaca: false dengan items kosong.`;

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
    // Alasan dari Auth dicatat dan ikut dikirim. Tanpa itu "sesi tidak
    // dikenali" tidak dapat dibedakan antara token kedaluwarsa dan kunci
    // layanan yang salah. Isinya teks galat Auth, bukan data siapa pun.
    console.error('ai-struk: getUser', galatJwt?.status, galatJwt?.message);
    return jawab({
      error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.',
      alasan: String(galatJwt?.message ?? 'pengguna tidak ditemukan').slice(0, 120),
    }, 401, asal);
  }
  const { data: profil } = await sbSrv.from('profiles').select('role').eq('id', pengguna.user.id).single();
  if (profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh membaca struk.' }, 403, asal);
  }

  /* ── Batas harian, diperiksa SEBELUM model AI dihubungi ──────────── */
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
    return jawab({ error: 'Format harus foto (JPEG, PNG, WebP) atau PDF.' }, 400, asal);
  }
  if (!gambar || !/^[A-Za-z0-9+/=]+$/.test(gambar)) {
    return jawab({ error: 'Berkas tidak terbaca.' }, 400, asal);
  }
  if (gambar.length > UKURAN_MAKS_BASE64) {
    return jawab({ error: jenis === 'application/pdf'
      ? 'PDF terlalu besar (maksimal sekitar 5 MB).'
      : 'Foto terlalu besar. Potret ulang lebih dekat ke struknya.' }, 413, asal);
  }

  /* ── OpenRouter ───────────────────────────────────────────────────── */
  const kunciAi = Deno.env.get('OPENROUTER_API_KEY') ?? '';
  if (!kunciAi) {
    return jawab({ error: 'Kunci AI belum dipasang (secret OPENROUTER_API_KEY). Hubungi pengembang.' }, 503, asal);
  }

  let res: Response;
  try {
    res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${kunciAi}`,
        'Content-Type': 'application/json',
        // Atribusi aplikasi di dasbor OpenRouter. Tidak memuat data apa pun.
        'HTTP-Referer': 'https://underratedbarbershop.com',
        'X-Title': 'Underrated Barbershop',
      },
      body: JSON.stringify({
        model: MODEL,
        // Token reasoning ikut memakan max_tokens. Model bawaan memakai
        // reasoning wajib dengan upaya "minimal"; 4000 memberi ruang lega
        // untuk itu ditambah JSON hasil bacaan struk yang panjang.
        max_tokens: 4000,
        // Teks lebih dulu, lalu gambar — urutan yang direkomendasikan
        // OpenRouter karena cara isinya diurai.
        messages: [
          { role: 'system', content: INSTRUKSI },
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Baca struk ini.' },
              jenis === 'application/pdf'
                ? { type: 'file', file: { filename: 'struk.pdf', file_data: `data:application/pdf;base64,${gambar}` } }
                : { type: 'image_url', image_url: { url: `data:${jenis};base64,${gambar}` } },
            ],
          },
        ],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'struk', strict: true, schema: SKEMA_STRUK },
        },
        // Hanya diarahkan ke penyedia yang benar-benar mendukung
        // response_format. Tanpa ini, OpenRouter boleh memilih penyedia yang
        // mengabaikan skema, dan jawabannya bisa berupa kalimat bebas.
        //
        // Parameter reasoning sengaja TIDAK dikirim: require_parameters juga
        // akan menuntutnya, sehingga mengganti MODEL_AI ke model tanpa
        // reasoning mendadak gagal dirutekan.
        provider: { require_parameters: true },
      }),
    });
  } catch (e) {
    console.error('ai-struk: jaringan', e instanceof Error ? e.message : e);
    await catatPemakaian(sbSrv, {
      fitur: 'struk', berhasil: false, model: MODEL, pemanggil: pengguna.user.id, keterangan: 'galat jaringan',
    });
    return jawab({ error: 'Layanan AI tidak dapat dihubungi. Coba lagi sebentar lagi.' }, 502, asal);
  }

  // deno-lint-ignore no-explicit-any
  let data: any = null;
  try { data = await res.json(); } catch { /* ditangani di bawah */ }

  /* Galat sebelum model mulai menjawab datang sebagai status HTTP; galat di
     tengah jalan datang sebagai status 200 dengan objek error di badannya.
     Keduanya diperiksa. Pesan teknisnya tidak diteruskan ke layar owner —
     ia tidak dapat menindaklanjutinya — tetapi dicatat. */
  const kodeGalat: number = !res.ok ? res.status : (data?.error ? Number(data.error.code) || 502 : 0);
  if (kodeGalat) {
    let pesan = 'Pembacaan struk gagal. Coba lagi sebentar lagi.';
    let status = 502;
    if (kodeGalat === 401) {
      pesan = 'Kunci AI tidak berlaku. Hubungi pengembang.'; status = 503;
    } else if (kodeGalat === 402) {
      // Saldo OpenRouter habis. Disebut terang-terangan: bukan kerusakan,
      // dan pengembang perlu tahu untuk mengisi ulang.
      pesan = 'Saldo layanan AI habis. Hubungi pengembang untuk mengisi ulang. Sementara itu, isi pengeluaran secara manual.';
      status = 503;
    } else if (kodeGalat === 429) {
      pesan = 'Layanan AI sedang sibuk. Coba lagi dalam satu menit.'; status = 429;
    } else if (kodeGalat === 400 || kodeGalat === 403) {
      pesan = jenis === 'application/pdf'
        ? 'PDF ditolak oleh layanan AI. Coba foto struknya saja.'
        : 'Gambar ditolak oleh layanan AI. Coba foto lain.';
      status = 400;
    }
    console.error('ai-struk: openrouter', kodeGalat, data?.error?.message);
    await catatPemakaian(sbSrv, {
      fitur: 'struk', berhasil: false, model: MODEL, pemanggil: pengguna.user.id,
      keterangan: `openrouter ${kodeGalat}`,
    });
    return jawab({ error: pesan }, status, asal);
  }

  const pilihan = data?.choices?.[0];
  const biaya = typeof data?.usage?.cost === 'number' ? ` biaya $${data.usage.cost}` : '';
  const pakai = {
    fitur: 'struk', model: data?.model ?? MODEL, pemanggil: pengguna.user.id,
    input_tokens: data?.usage?.prompt_tokens ?? 0,
    output_tokens: data?.usage?.completion_tokens ?? 0,
  };

  if (pilihan?.message?.refusal) {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'refusal' + biaya });
    return jawab({ error: jenis === 'application/pdf'
      ? 'PDF ini tidak dapat dibaca. Coba foto struknya saja.'
      : 'Gambar ini tidak dapat dibaca. Coba potret ulang struknya saja, tanpa latar lain.' }, 422, asal);
  }
  // "length": jatah token habis, sering karena reasoning — isinya kosong atau
  // terpotong dan JSON-nya tidak utuh.
  if (pilihan?.finish_reason === 'length') {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'length' + biaya });
    return jawab({ error: 'Struk terlalu panjang untuk dibaca sekaligus. Potret per bagian.' }, 422, asal);
  }

  const teks = typeof pilihan?.message?.content === 'string' ? pilihan.message.content : '';
  let hasil: unknown;
  try {
    hasil = JSON.parse(teks);
  } catch {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: 'json tidak sah' + biaya });
    return jawab({ error: 'Hasil bacaan tidak dapat diolah. Coba lagi.' }, 502, asal);
  }

  await catatPemakaian(sbSrv, { ...pakai, berhasil: true, keterangan: biaya.trim() || null });
  return jawab({ hasil, sisa_hari_ini: Math.max(0, BATAS_HARIAN - (dipakai ?? 0) - 1) }, 200, asal);
});
