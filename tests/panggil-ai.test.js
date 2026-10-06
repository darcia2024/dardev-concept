/* Pemanggilan fungsi AI dari dashboard owner (panggilAi).
 *
 * Kegagalannya pernah terbaca owner sebagai "Sesi tidak dikenali. Masuk lagi
 * lalu coba ulang." padahal dashboard tampak normal dan datanya termuat —
 * pesan yang tidak memberi petunjuk apa pun. Penyebabnya bisa sesi yang habis
 * di HP, token yang tidak terkirim, atau server; ketiganya harus dapat
 * dibedakan dari pesan yang tampil. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');

const a = rekap.indexOf('async function panggilAi(');
const b = rekap.indexOf('function keBase64', a);
assert.ok(a > 0 && b > a, 'panggilAi harus ditemukan');
const kode = rekap.slice(a, b);

function buat(sb) { return new Function('sb', kode + '; return panggilAi;')(sb); }
const galat = (status, isi) => ({
  message: 'Edge Function returned a non-2xx status code',
  context: { status, json: async () => { if (isi === undefined) throw new Error('bukan json'); return isi; } }
});
function sbPalsu({ sesi, balasan, getUserError }) {
  const catatan = { invoke: [], getUser: 0 };
  return {
    catatan,
    sb: {
      auth: {
        getSession: async () => ({ data: { session: sesi === undefined ? { access_token: 'TOKEN-OWNER' } : sesi } }),
        getUser: async () => { catatan.getUser++; return { error: getUserError || null }; }
      },
      functions: { invoke: async (nama, o) => { catatan.invoke.push({ nama, o }); return balasan; } }
    }
  };
}

(async () => {
  // 1 · Tanpa sesi: dikatakan terus terang, dan tidak ada yang dikirim.
  {
    const t = sbPalsu({ sesi: null, balasan: { data: {}, error: null } });
    await assert.rejects(buat(t.sb)('ai-struk', {}), /Sesi login sudah habis\. Tekan Keluar/);
    assert.equal(t.catatan.invoke.length, 0, 'tanpa sesi, server tidak dihubungi');
  }
  // 2 · Berhasil: token login dikirim EKSPLISIT, bukan diserahkan ke jalur otomatis.
  {
    const t = sbPalsu({ balasan: { data: { hasil: 1 }, error: null } });
    const r = await buat(t.sb)('ai-stok', { teks: 'x' });
    assert.deepEqual(r, { hasil: 1 });
    assert.equal(t.catatan.invoke[0].nama, 'ai-stok');
    assert.deepEqual(t.catatan.invoke[0].o.body, { teks: 'x' });
    assert.equal(t.catatan.invoke[0].o.headers.Authorization, 'Bearer TOKEN-OWNER', 'token sesi harus dikirim eksplisit');
    assert.equal(t.catatan.getUser, 0, 'jalur sukses tidak boleh menambah panggilan ke Auth');
  }
  // 3 · 401 dan Auth sendiri menolak sesinya: sebabnya sesi yang habis.
  {
    const t = sbPalsu({ balasan: { data: null, error: galat(401, { error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.' }) }, getUserError: { message: 'invalid claim' } });
    await assert.rejects(buat(t.sb)('ai-struk', {}), /Sesi login sudah habis\. Tekan Keluar, lalu masuk lagi\./);
    assert.equal(t.catatan.getUser, 1);
  }
  // 4 · 401 tetapi Auth menerima sesinya: sebabnya di server; alasannya ditampilkan.
  {
    const t = sbPalsu({ balasan: { data: null, error: galat(401, { error: 'Sesi tidak dikenali. Masuk lagi lalu coba ulang.', alasan: 'Invalid API key' }) } });
    await assert.rejects(buat(t.sb)('ai-struk', {}), /Sesi tidak dikenali\. Masuk lagi lalu coba ulang\. \[Invalid API key\]/);
  }
  // 5 · Galat selain 401 meneruskan pesan server apa adanya, tanpa memanggil Auth.
  {
    const t = sbPalsu({ balasan: { data: null, error: galat(429, { error: 'Batas 60 struk per hari sudah tercapai.' }) } });
    await assert.rejects(buat(t.sb)('ai-struk', {}), /^Error: Batas 60 struk per hari sudah tercapai\.$/);
    assert.equal(t.catatan.getUser, 0, '429 bukan urusan sesi');
  }
  // 6 · Badan galat bukan JSON: jatuh ke pesan umum, tidak melempar galat lain.
  {
    const t = sbPalsu({ balasan: { data: null, error: galat(502, undefined) } });
    await assert.rejects(buat(t.sb)('ai-struk', {}), /non-2xx/);
  }

  // Keempat pemanggil memakai pintu yang sama; tidak ada yang kembali ke jalur otomatis.
  assert.equal((rekap.match(/sb\.functions\.invoke\(/g) || []).length, 1, 'hanya panggilAi yang boleh memanggil fungsi AI');
  for (const f of ['ai-struk', 'ai-rapikan', 'ai-stok', 'ai-asisten']) {
    assert.match(rekap, new RegExp(`panggilAi\\('${f}'`), `${f} harus lewat panggilAi`);
    const fn = fs.readFileSync(path.join(root, `supabase/functions/${f}/index.ts`), 'utf8');
    assert.match(fn, /alasan: String\(galatJwt\?\.message \?\? 'pengguna tidak ditemukan'\)\.slice\(0, 120\)/, `${f}: alasan 401 harus dikirim`);
    assert.match(fn, new RegExp(`console\\.error\\('${f}: getUser'`), `${f}: alasan 401 harus dicatat di log`);
  }

  console.log('panggil-ai: semua pemeriksaan lolos');
})().catch((e) => { console.error(e); process.exit(1); });
