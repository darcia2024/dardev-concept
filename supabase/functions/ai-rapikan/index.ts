/**
 * ai-rapikan — merapikan coretan atau voice note owner lewat OpenRouter.
 *
 * Add-on AI, fitur 2 (#INV/BU-AI/2026/019). Owner mengetik catatan acak
 * atau merekam suara; fungsi ini mengembalikan to-do list tim, tabel, atau
 * langkah kerja dalam bentuk terstruktur.
 *
 * FUNGSI INI TIDAK MENYIMPAN APA PUN. Hasilnya dikembalikan ke layar owner
 * untuk diperiksa dan dibetulkan, dan baru tersimpan lewat
 * owner_simpan_catatan_rapi() saat owner menekan Simpan. Voice note yang salah
 * dengar ("jam 3" terdengar "jam 7") terlihat seperti instruksi yang sah
 * begitu tersimpan dan dibagikan ke tim.
 *
 * REKAMAN SUARA TIDAK DISIMPAN DI MANA PUN. Ia diteruskan ke model lalu
 * dibuang bersama permintaan ini. Hanya panjangnya (detik) yang dicatat di
 * ai_pemakaian, untuk menjelaskan tagihan.
 *
 * KUNCI DAN MODEL
 *   OPENROUTER_API_KEY disimpan sebagai secret Supabase, sama dengan ai-struk.
 *   Model dibaca dari MODEL_AI_RAPIKAN, lalu MODEL_AI, dengan bawaan
 *   google/gemini-3.5-flash-lite — mendukung masukan audio dan structured
 *   outputs (openrouter.ai/api/v1/models, Oktober 2026). Model pengganti
 *   harus mendukung keduanya bila voice note ingin tetap jalan.
 *
 * AUDIO
 *   OpenRouter menerima wav, mp3, aiff, aac, ogg, flac, m4a, pcm16, pcm24 —
 *   bukan webm, yang justru dihasilkan perekam di Chrome. Layar owner
 *   mengubah rekamannya menjadi WAV 16 kHz mono sebelum mengirim, sehingga
 *   fungsi ini hanya perlu menerima satu bentuk.
 *
 * BATAS HARIAN
 *   Setiap panggilan dicatat di ai_pemakaian dengan fitur 'rapikan'. Bila
 *   jumlah hari ini sudah mencapai BATAS_RAPIKAN_HARIAN (bawaan 40), panggilan
 *   berikutnya ditolak sebelum model AI dihubungi — jadi tidak ditagih.
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
const BATAS_HARIAN = Number(Deno.env.get('BATAS_RAPIKAN_HARIAN') ?? '40') || 40;

const MODEL = Deno.env.get('MODEL_AI_RAPIKAN') || Deno.env.get('MODEL_AI') || 'google/gemini-3.5-flash-lite';

/* Batas masukan. Teks 6000 karakter kira-kira dua halaman coretan — lebih
   panjang dari itu hampir pasti tempelan dokumen, bukan catatan. Audio
   dibatasi layar pada 3 menit; WAV 16 kHz mono 16-bit = 32 KB per detik,
   jadi 3 menit sekitar 5,8 MB, atau 7,7 MB setelah base64. */
const TEKS_MAKS = 6000;
const AUDIO_MAKS_BASE64 = 8_000_000;
const DETIK_MAKS = 185;

const BENTUK = ['otomatis', 'todo', 'tabel', 'langkah'] as const;
type Bentuk = typeof BENTUK[number];
const bentukSah = (b: string): b is Bentuk => (BENTUK as readonly string[]).includes(b);

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

/* Skema hasil rapian. Ketiga bentuk selalu ada; yang tidak dipakai berupa
   larik kosong. Tanpa null dan tanpa anyOf — alasannya sama dengan ai-struk:
   dukungan penyedia di belakang OpenRouter tidak merata. */
const SKEMA_RAPI = {
  type: 'object',
  properties: {
    terbaca: { type: 'boolean', description: 'false bila masukan kosong, tidak terdengar, atau bukan catatan kerja sama sekali' },
    judul: { type: 'string', description: 'Judul singkat, paling banyak 8 kata, bahasa Indonesia' },
    ringkasan: { type: 'string', description: 'Satu sampai tiga kalimat inti catatan; teks kosong bila tidak perlu' },
    todo: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          tugas: { type: 'string', description: 'Satu tugas, kalimat perintah singkat' },
          untuk: { type: 'string', description: 'Nama orang yang disebut bertugas; teks kosong bila tidak disebut' },
          kapan: { type: 'string', description: 'Waktu atau tenggat seperti disebut; teks kosong bila tidak disebut' },
        },
        required: ['tugas', 'untuk', 'kapan'],
        additionalProperties: false,
      },
    },
    tabel: {
      type: 'object',
      properties: {
        kolom: { type: 'array', items: { type: 'string' } },
        baris: { type: 'array', items: { type: 'array', items: { type: 'string' } } },
      },
      required: ['kolom', 'baris'],
      additionalProperties: false,
    },
    langkah: { type: 'array', items: { type: 'string', description: 'Satu langkah kerja berurutan' } },
    transkrip: { type: 'string', description: 'Tulisan apa adanya dari rekaman suara; teks kosong bila tidak ada rekaman' },
    catatan: { type: 'string', description: 'Bagian yang ragu atau tidak terdengar jelas, singkat; teks kosong bila semua jelas' },
  },
  required: ['terbaca', 'judul', 'ringkasan', 'todo', 'tabel', 'langkah', 'transkrip', 'catatan'],
  additionalProperties: false,
} as const;

const PETUNJUK_BENTUK: Record<Bentuk, string> = {
  otomatis: 'Pilih sendiri bentuk yang paling cocok dengan isinya. Boleh lebih dari satu bila isinya campuran — misalnya to-do list ditambah tabel harga.',
  todo: 'Pemilik toko meminta TO-DO LIST. Isi todo; tabel dan langkah dibiarkan kosong kecuali isinya benar-benar tidak dapat dijadikan tugas.',
  tabel: 'Pemilik toko meminta TABEL. Isi tabel dengan kolom yang masuk akal untuk datanya; todo dan langkah dibiarkan kosong.',
  langkah: 'Pemilik toko meminta INSTRUKSI KERJA berurutan. Isi langkah; todo dan tabel dibiarkan kosong.',
};

function instruksi(bentuk: Bentuk, hariIni: string, namaTim: string[]): string {
  return `Anda membantu pemilik Underrated Barbershop merapikan catatan kerja. Masukannya bisa berupa coretan yang diketik asal-asalan, rekaman suara (voice note), atau keduanya — dalam bahasa Indonesia sehari-hari, sering bercampur bahasa daerah atau singkatan.

Tugas Anda MERAPIKAN, bukan menambah. Setiap tugas, angka, nama, dan waktu di hasil harus berasal dari masukan. Jangan menambahkan tugas yang tidak disebut, jangan mengarang harga, jumlah, atau jam. Bila sesuatu tidak terdengar atau tidak terbaca jelas, tulis bacaan terbaik Anda lalu sebutkan keraguannya di catatan, supaya pemilik tahu bagian mana yang harus ia periksa.

${PETUNJUK_BENTUK[bentuk]}

Aturan bentuk:
- todo: satu tugas per butir, kalimat perintah singkat ("Beli pomade 2 lusin"). Isi untuk hanya bila orangnya disebut. Isi kapan seperti disebut ("besok pagi", "sebelum Sabtu"); jangan menerjemahkannya menjadi tanggal.
- tabel: kolom berupa judul pendek; setiap baris memuat isian sebanyak jumlah kolom, sel yang tidak diketahui ditulis teks kosong. Angka rupiah ditulis tanpa "Rp" dan tanpa titik ribuan (45000).
- langkah: urutan kerja, satu tindakan per langkah.
- Bentuk yang tidak dipakai ditulis sebagai larik kosong; tabel yang tidak dipakai berupa kolom dan baris kosong.
- transkrip: bila ada rekaman suara, tuliskan apa adanya yang diucapkan, tanpa dirapikan. Bila tidak ada rekaman, teks kosong.

Bila masukan kosong, tidak terdengar sama sekali, atau sama sekali bukan catatan kerja, kembalikan terbaca: false dengan semua bentuk kosong.

Hari ini ${hariIni}.${namaTim.length ? ` Nama tim di toko ini: ${namaTim.join(', ')}. Pakai ejaan ini bila nama yang terdengar mirip.` : ''}`;
}

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
    return jawab({ error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.' }, 401, asal);
  }
  const { data: profil } = await sbSrv.from('profiles').select('role').eq('id', pengguna.user.id).single();
  if (profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh merapikan catatan.' }, 403, asal);
  }

  /* ── Batas harian, diperiksa SEBELUM model AI dihubungi ──────────── */
  const hariIni = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(new Date());
  const sejakUtc = new Date(hariIni + 'T00:00:00+07:00');
  const { count: dipakai } = await sbSrv.from('ai_pemakaian')
    .select('id', { count: 'exact', head: true })
    .eq('fitur', 'rapikan').gte('created_at', sejakUtc.toISOString());
  if ((dipakai ?? 0) >= BATAS_HARIAN) {
    return jawab({
      error: `Batas ${BATAS_HARIAN} kali merapikan per hari sudah tercapai. Coba lagi besok.`,
    }, 429, asal);
  }

  /* ── Masukan ──────────────────────────────────────────────────────── */
  let badan: Record<string, unknown>;
  try { badan = await req.json(); } catch { return jawab({ error: 'Permintaan tidak terbaca.' }, 400, asal); }

  const teks = String(badan.teks ?? '').trim();
  const audio = String(badan.audio ?? '');
  const detik = Math.round(Number(badan.detik) || 0);
  const bentukMasuk = String(badan.bentuk ?? 'otomatis');
  const bentuk: Bentuk = bentukSah(bentukMasuk) ? bentukMasuk : 'otomatis';

  if (!teks && !audio) {
    return jawab({ error: 'Tulis catatannya atau rekam suara dulu.' }, 400, asal);
  }
  if (teks.length > TEKS_MAKS) {
    return jawab({ error: `Catatan terlalu panjang (lebih dari ${TEKS_MAKS} huruf). Pecah jadi beberapa bagian.` }, 413, asal);
  }
  if (audio) {
    if (!/^[A-Za-z0-9+/=]+$/.test(audio)) {
      return jawab({ error: 'Rekaman tidak terbaca. Rekam ulang.' }, 400, asal);
    }
    if (audio.length > AUDIO_MAKS_BASE64 || detik > DETIK_MAKS) {
      return jawab({ error: 'Rekaman terlalu panjang. Paling lama 3 menit per rekaman.' }, 413, asal);
    }
  }

  // Nama tim membantu model mengeja nama yang diucapkan ("Wanda", bukan
  // "Wonda"). Kegagalan membacanya tidak menggagalkan apa pun.
  const { data: tim } = await sbSrv.from('capsters').select('name').eq('is_active', true).limit(40);
  const namaTim = (tim ?? []).map((t: { name: string }) => t.name).filter(Boolean);

  /* ── OpenRouter ───────────────────────────────────────────────────── */
  const kunciAi = Deno.env.get('OPENROUTER_API_KEY') ?? '';
  if (!kunciAi) {
    return jawab({ error: 'Kunci AI belum dipasang (secret OPENROUTER_API_KEY). Hubungi pengembang.' }, 503, asal);
  }

  // Teks lebih dulu, lalu audio — urutan yang sama dengan ai-struk.
  const isiPengguna: unknown[] = [
    { type: 'text', text: teks ? `Catatan yang diketik:\n${teks}` : 'Rapikan rekaman suara ini.' },
  ];
  if (audio) isiPengguna.push({ type: 'input_audio', input_audio: { data: audio, format: 'wav' } });

  const pakaiDasar = {
    fitur: 'rapikan', pemanggil: pengguna.user.id,
    // Hanya panjang rekamannya yang dicatat, tidak pernah isinya.
    keterangan: audio ? `suara ${detik} detik` : 'teks',
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
        // Transkrip 3 menit bicara bisa 2.500 token sendiri, ditambah hasil
        // rapian dan token reasoning model bawaan.
        max_tokens: 6000,
        messages: [
          { role: 'system', content: instruksi(bentuk, hariIni, namaTim) },
          { role: 'user', content: isiPengguna },
        ],
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'catatan_rapi', strict: true, schema: SKEMA_RAPI },
        },
        // Lihat ai-struk: tanpa require_parameters OpenRouter boleh memilih
        // penyedia yang mengabaikan skema. Parameter reasoning sengaja tidak
        // dikirim karena require_parameters akan ikut menuntutnya.
        provider: { require_parameters: true },
      }),
    });
  } catch (e) {
    console.error('ai-rapikan: jaringan', e instanceof Error ? e.message : e);
    await catatPemakaian(sbSrv, { ...pakaiDasar, berhasil: false, model: MODEL, keterangan: pakaiDasar.keterangan + ', galat jaringan' });
    return jawab({ error: 'Layanan AI tidak dapat dihubungi. Coba lagi sebentar lagi.' }, 502, asal);
  }

  // deno-lint-ignore no-explicit-any
  let data: any = null;
  try { data = await res.json(); } catch { /* ditangani di bawah */ }

  const kodeGalat: number = !res.ok ? res.status : (data?.error ? Number(data.error.code) || 502 : 0);
  if (kodeGalat) {
    let pesan = 'Merapikan catatan gagal. Coba lagi sebentar lagi.';
    let status = 502;
    if (kodeGalat === 401) {
      pesan = 'Kunci AI tidak berlaku. Hubungi pengembang.'; status = 503;
    } else if (kodeGalat === 402) {
      pesan = 'Saldo layanan AI habis. Hubungi pengembang untuk mengisi ulang.'; status = 503;
    } else if (kodeGalat === 429) {
      pesan = 'Layanan AI sedang sibuk. Coba lagi dalam satu menit.'; status = 429;
    } else if (kodeGalat === 400 || kodeGalat === 403) {
      pesan = audio
        ? 'Rekaman ditolak oleh layanan AI. Coba rekam ulang, atau ketik catatannya.'
        : 'Catatan ditolak oleh layanan AI. Coba ubah kalimatnya.';
      status = 400;
    }
    console.error('ai-rapikan: openrouter', kodeGalat, data?.error?.message);
    await catatPemakaian(sbSrv, {
      ...pakaiDasar, berhasil: false, model: MODEL, keterangan: `${pakaiDasar.keterangan}, openrouter ${kodeGalat}`,
    });
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
    return jawab({ error: 'Catatan ini tidak dapat dirapikan. Coba tulis ulang dengan kalimat lain.' }, 422, asal);
  }
  if (pilihan?.finish_reason === 'length') {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: pakai.keterangan + ', length' + biaya });
    return jawab({ error: 'Catatannya terlalu panjang untuk dirapikan sekaligus. Pecah jadi beberapa bagian.' }, 422, asal);
  }

  const isiJawaban = typeof pilihan?.message?.content === 'string' ? pilihan.message.content : '';
  let hasil: unknown;
  try {
    hasil = JSON.parse(isiJawaban);
  } catch {
    await catatPemakaian(sbSrv, { ...pakai, berhasil: false, keterangan: pakai.keterangan + ', json tidak sah' + biaya });
    return jawab({ error: 'Hasil rapian tidak dapat diolah. Coba lagi.' }, 502, asal);
  }

  await catatPemakaian(sbSrv, { ...pakai, berhasil: true, keterangan: pakai.keterangan + biaya });
  return jawab({ hasil, sisa_hari_ini: Math.max(0, BATAS_HARIAN - (dipakai ?? 0) - 1) }, 200, asal);
});
