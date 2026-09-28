/**
 * buat-akun-karyawan — membuat akun login untuk seorang karyawan.
 *
 * KENAPA INI TIDAK BISA DIKERJAKAN DARI PERAMBAN
 *
 * Membuat pengguna di auth.users butuh service-role key. Kunci itu memintas
 * seluruh Row Level Security, dan layar owner memakai publishable key yang
 * memang dirancang untuk publik — siapa pun dapat membacanya dari sumber
 * halaman. Menaruh service-role key di sana sama dengan menyerahkan seluruh
 * basis data, termasuk nama dan nomor WhatsApp setiap pelanggan.
 *
 * Maka kunci itu tinggal di sini, di lingkungan fungsi, dan peramban hanya
 * mengirim permintaan bersama JWT miliknya sendiri.
 *
 * TIGA PENJAGA
 *
 *   1. Pemanggilnya harus owner. Diverifikasi dari JWT yang ia kirim, bukan
 *      dari apa pun di badan permintaan.
 *   2. Perannya ditulis tetap 'capster'. Tidak pernah dibaca dari permintaan,
 *      sehingga endpoint ini tidak dapat dipakai mencetak owner baru walau
 *      penjaga pertama suatu saat bocor.
 *   3. Keputusan boleh-tidaknya menautkan ada di basis data, pada
 *      tautkan_akun_karyawan() (migrasi 48), bukan di berkas ini.
 *
 * Bila penautan gagal setelah akunnya terlanjur dibuat, akun itu dihapus lagi.
 * Akun menganggur yang tidak tertaut ke siapa pun adalah kredensial hidup yang
 * tidak muncul di layar mana pun — tidak ada yang akan menemukannya kembali.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

const URL_SB     = Deno.env.get('SUPABASE_URL')!;
const KUNCI_ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const KUNCI_SRV  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/* Asal yang boleh memanggil. Dapat diganti lewat secret ORIGIN_DIIZINKAN
   (dipisah koma) tanpa menyunting berkas ini — misalnya saat menambah domain
   pratinjau. Asal yang tidak terdaftar tidak mendapat header CORS sama sekali,
   sehingga perambannya sendiri yang menolak jawabannya. */
const ASAL_BAWAAN = [
  'https://underratedbarbershop.com',
  'https://www.underratedbarbershop.com',
  'http://localhost:3000',
];
const ASAL_BOLEH = (Deno.env.get('ORIGIN_DIIZINKAN') ?? '')
  .split(',').map((s) => s.trim()).filter(Boolean);
const DAFTAR_ASAL = ASAL_BOLEH.length ? ASAL_BOLEH : ASAL_BAWAAN;

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

/* Sandi acak untuk owner yang tidak ingin memikirkannya sendiri. Memakai
   crypto.getRandomValues, bukan Math.random: yang kedua dapat ditebak dari
   keluaran sebelumnya, dan ini sandi sungguhan untuk orang sungguhan.

   Huruf yang mudah tertukar saat dibacakan — 0/O, 1/l/I — dikeluarkan, sebab
   sandi ini memang akan dibacakan owner kepada karyawannya. */
function sandiAcak(panjang = 14): string {
  const abjad = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const acak = new Uint32Array(panjang);
  crypto.getRandomValues(acak);
  return Array.from(acak, (n) => abjad[n % abjad.length]).join('');
}

Deno.serve(async (req: Request) => {
  const asal = req.headers.get('Origin');

  if (req.method === 'OPTIONS') return new Response('ok', { headers: headerCors(asal) });
  if (req.method !== 'POST') {
    return jawab({ error: 'Metode tidak didukung.' }, 405, asal);
  }

  /* ── Penjaga 1: pemanggilnya owner ────────────────────────────────────── */
  const otorisasi = req.headers.get('Authorization') ?? '';
  const jwt = otorisasi.startsWith('Bearer ') ? otorisasi.slice(7) : '';
  if (!jwt) return jawab({ error: 'Tidak ada sesi. Masuk lagi lalu coba ulang.' }, 401, asal);

  const sbAnon = createClient(URL_SB, KUNCI_ANON);
  const { data: pengguna, error: galatJwt } = await sbAnon.auth.getUser(jwt);
  if (galatJwt || !pengguna?.user) {
    return jawab({ error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.' }, 401, asal);
  }

  const sbSrv = createClient(URL_SB, KUNCI_SRV, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  /* Peran dibaca dengan service-role dari id yang sudah diverifikasi, bukan
     dari klaim di dalam JWT: klaim dapat basi bila peran seseorang dicabut,
     sedangkan tabelnya tidak. */
  const { data: profil, error: galatProfil } = await sbSrv
    .from('profiles').select('role').eq('id', pengguna.user.id).single();

  if (galatProfil || profil?.role !== 'owner') {
    return jawab({ error: 'Hanya owner yang boleh membuatkan akun karyawan.' }, 403, asal);
  }

  /* ── Masukan ──────────────────────────────────────────────────────────── */
  let badan: Record<string, unknown>;
  try {
    badan = await req.json();
  } catch {
    return jawab({ error: 'Permintaan tidak terbaca.' }, 400, asal);
  }

  const karyawanId = String(badan.karyawan_id ?? '').trim();
  const email = String(badan.email ?? '').trim().toLowerCase();
  const sandiDiminta = badan.sandi == null ? '' : String(badan.sandi);

  if (!/^[0-9a-f-]{36}$/i.test(karyawanId)) {
    return jawab({ error: 'Karyawan tidak dikenali.' }, 400, asal);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jawab({ error: 'Alamat email tidak valid.' }, 400, asal);
  }
  if (sandiDiminta && sandiDiminta.length < 8) {
    return jawab({ error: 'Sandi minimal 8 karakter.' }, 400, asal);
  }

  /* Diperiksa lebih dulu supaya akun tidak terlanjur dibuat untuk karyawan
     yang memang sudah punya. tautkan_akun_karyawan() memeriksanya lagi — yang
     ini hanya agar kegagalannya tidak menyisakan pekerjaan untuk dibatalkan. */
  const { data: karyawan, error: galatKaryawan } = await sbSrv
    .from('capsters').select('id, name, auth_user_id').eq('id', karyawanId).single();

  if (galatKaryawan || !karyawan) {
    return jawab({ error: 'Karyawan tidak ditemukan.' }, 404, asal);
  }
  if (karyawan.auth_user_id) {
    return jawab({ error: `${karyawan.name} sudah punya akun.` }, 409, asal);
  }

  /* ── Penjaga 2: perannya ditulis tetap ────────────────────────────────── */
  const sandi = sandiDiminta || sandiAcak();
  const { data: dibuat, error: galatBuat } = await sbSrv.auth.admin.createUser({
    email,
    password: sandi,
    email_confirm: true,
    user_metadata: { full_name: karyawan.name, role: 'capster' },
  });

  if (galatBuat || !dibuat?.user) {
    const pesan = (galatBuat?.message ?? '').toLowerCase();
    const sudahAda = pesan.includes('already') || pesan.includes('registered')
      || pesan.includes('exists');
    return jawab(
      { error: sudahAda ? `Email ${email} sudah dipakai akun lain.`
                        : `Gagal membuat akun: ${galatBuat?.message ?? 'tidak diketahui'}` },
      sudahAda ? 409 : 500,
      asal,
    );
  }

  /* ── Penjaga 3: keputusan penautan ada di basis data ──────────────────── */
  const { error: galatTaut } = await sbSrv.rpc('tautkan_akun_karyawan', {
    p_karyawan_id: karyawanId,
    p_auth_user_id: dibuat.user.id,
  });

  if (galatTaut) {
    /* Akunnya sudah terlanjur ada tetapi tidak menempel pada siapa pun.
       Dibiarkan, ia jadi kredensial hidup yang tidak tampil di layar mana pun.
       Kegagalan menghapusnya pun dilaporkan, supaya tidak ada yang tertinggal
       diam-diam. */
    const { error: galatBersih } = await sbSrv.auth.admin.deleteUser(dibuat.user.id);
    return jawab({
      error: galatBersih
        ? `Gagal menautkan akun: ${galatTaut.message}. Akun ${email} terlanjur `
          + `dibuat dan gagal dihapus — hapus manual lewat Supabase Dashboard.`
        : `Gagal menautkan akun: ${galatTaut.message}`,
    }, 500, asal);
  }

  /* Sandi hanya dikembalikan bila fungsi ini yang membuatnya. Sandi yang
     diketik owner tidak dipantulkan balik: ia sudah memilikinya, dan
     memantulkannya hanya menambah satu tempat lagi ia dapat bocor. */
  return jawab({
    email,
    nama: karyawan.name,
    sandi_dibuat: sandiDiminta ? null : sandi,
  }, 200, asal);
});
