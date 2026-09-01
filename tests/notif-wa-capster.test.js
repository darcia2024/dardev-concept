/* Notifikasi WhatsApp ke capster.
 *
 * Yang dijaga di sini bukan "apakah pesannya terkirim" — itu urusan provider —
 * melainkan empat janji yang bila dilanggar tidak akan terlihat sampai
 * kerusakannya sudah terjadi:
 *
 *   1. Nomor capster tidak pernah sampai ke pengunjung.
 *   2. Tujuan pengiriman ditentukan server dari booking, bukan dari peramban.
 *   3. Booking tetap berhasil walau notifikasinya gagal.
 *   4. Satu booking hanya menghasilkan satu pesan.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const landing = fs.readFileSync(path.join(root, 'landing.html'), 'utf8');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const m40 = fs.readFileSync(
  path.join(root, 'supabase_migration_40_notif_wa_capster.sql'), 'utf8');
const m41 = fs.readFileSync(
  path.join(root, 'supabase_migration_41_telepon_capster.sql'), 'utf8');

function potongFungsi(sumber, nama) {
  const mulai = sumber.indexOf(`function ${nama}`);
  assert.notEqual(mulai, -1, `${nama} harus tersedia`);
  const buka = sumber.indexOf('{', mulai);
  let dalam = 0;
  for (let i = buka; i < sumber.length; i += 1) {
    if (sumber[i] === '{') dalam += 1;
    if (sumber[i] === '}') dalam -= 1;
    if (dalam === 0) return sumber.slice(mulai, i + 1);
  }
  throw new Error(`Penutup ${nama} tidak ditemukan`);
}

/* ── 1 · Nomor capster tidak boleh bocor ke halaman publik ────────────────
   Diuji dengan menjalankan perendernya atas muatan yang sengaja membawa
   nomor. Memeriksa berkas SQL saja tidak cukup: yang menentukan apa yang
   dilihat pengunjung adalah kode ini, bukan bentuk balasan hari ini. */
const esc = s => String(s).replace(/[&<>"']/g, c => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function pasangDom(kapster) {
  const el = {
    tim: { hidden: true },
    kapsterDaftar: { innerHTML: '', _simak: [],
      addEventListener(_, f) { this._simak.push(f); },
      querySelectorAll() { return []; } },
    bkCatatan: { value: '' },
    booking: { scrollIntoView() {} }
  };
  return {
    $: id => el[id],
    ISI: { kapster },
    el
  };
}

function jalankanIsiKapster(kapster) {
  const dom = pasangDom(kapster);
  const peta = landing.slice(landing.indexOf('const FOTO_KAPSTER'));
  const src = peta.slice(0, peta.indexOf('};') + 2)
            + '\n' + potongFungsi(landing, 'isiKapster')
            + '\n' + potongFungsi(landing, 'tandaiKapsterPilih')
            + '\n' + potongFungsi(landing, 'cariFotoKapster')
            + '\n' + potongFungsi(landing, 'gambarKapster');
  new Function('$', 'ISI', 'esc', 'kapsterPilih',
    `${src}; isiKapster();`)(dom.$, dom.ISI, esc, null);
  return dom.el.kapsterDaftar.innerHTML;
}

const markah = jalankanIsiKapster([
  { id: '5f331709-bfea-4c19-9b7c-01ed75210d15', nama: 'Cena',
    phone: '6281297754581', telepon: '6281297754581' }
]);
assert.match(markah, /data-kapster-id="5f331709-bfea-4c19-9b7c-01ed75210d15"/);
assert.doesNotMatch(markah, /6281297754581/,
  'nomor capster tidak boleh muncul di markup halaman depan');

// Bentuk lama (untai nama saja) masih dirender, supaya halaman yang sudah
// terunduh tidak jatuh saat balasan servernya berubah bentuk.
assert.match(jalankanIsiKapster(['Lukman']), /Pilih Lukman/);

// public_landing hanya boleh mengembalikan id dan nama.
const landingSql = m40.slice(m40.indexOf('FUNCTION public.public_landing'));
const blokKapster = landingSql.slice(landingSql.indexOf("'kapster'"),
                                     landingSql.indexOf("'kapster'") + 400);
assert.match(blokKapster, /jsonb_build_object\('id', c\.id, 'nama', c\.name\)/);
assert.doesNotMatch(blokKapster, /c\.phone/,
  'public_landing tidak boleh menyertakan nomor capster');

/* ── 2 · Tujuan ditentukan server, bukan peramban ─────────────────────────
   Yang dikirim halaman depan hanyalah id capster. Nomornya dicari server
   dari baris capsters, sehingga peramban tidak punya cara menunjuk nomor
   sembarangan sebagai tujuan. */
assert.match(landing, /p_capster_id: kapsterPilih \? kapsterPilih\.id : null/);
assert.doesNotMatch(landing, /p_telepon_capster|p_nomor_capster|p_wa_tujuan/,
  'permintaan booking tidak boleh membawa nomor tujuan');

const pengirim = m40.slice(m40.indexOf('FUNCTION kirim_wa_capster'),
                           m40.indexOf('REVOKE EXECUTE ON FUNCTION kirim_wa_capster'));
assert.match(pengirim,
  /SELECT c\.phone, c\.name INTO v_telp, v_nama\s+FROM capsters c WHERE c\.id = v_b\.capster_id/,
  'nomor harus diambil dari capster yang terhubung ke booking');
assert.match(pengirim, /\^62\[0-9\]\{8,15\}\$/, 'nomor harus divalidasi bentuknya');

// Pengirimnya tidak boleh dapat dipanggil dari peramban sama sekali.
assert.match(m40,
  /REVOKE EXECUTE ON FUNCTION kirim_wa_capster\(UUID\) FROM PUBLIC, anon, authenticated;/);
assert.doesNotMatch(m40, /GRANT\s+EXECUTE ON FUNCTION kirim_wa_capster/);

/* ── 3 · Isi pesan terbatas pada yang disepakati ──────────────────────────
   Nomor pelanggan sengaja tidak ikut: capster tidak membutuhkannya, dan
   menyebarkannya menambah tempat data itu dapat bocor. */
for (const bagian of ["'Nama: ' || v_b.nama", "'Layanan: ' || v_b.service_name",
                      "v_b.tanggal, 'DD Mon YYYY'", "v_b.jam, 'HH24:MI'",
                      'Booking baru untuk ']) {
  assert.ok(pengirim.includes(bagian), `pesan harus memuat ${bagian}`);
}
assert.doesNotMatch(pengirim, /v_b\.telepon/,
  'nomor pelanggan tidak boleh ikut dalam pesan ke capster');

/* ── 4 · Booking tidak boleh gugur karena notifikasi ──────────────────────
   Dua lapis: blok pengiriman punya EXCEPTION-nya sendiri, dan seluruh fungsi
   dibungkus sekali lagi. Tanpa lapis kedua, galat di luar blok pengiriman
   (misalnya saat menulis penanda) tetap menjatuhkan transaksi pemanggil. */
assert.equal((pengirim.match(/EXCEPTION WHEN OTHERS THEN/g) || []).length, 2,
  'kirim_wa_capster harus menelan galat di dua lapis');
assert.match(pengirim, /v_status := 'gagal'/);
assert.match(pengirim, /v_status := 'nomor_tidak_sah'/);
assert.match(pengirim, /v_status := 'tanpa_capster'/);

// Capster yang tidak dikenal dikosongkan, bukan dijadikan alasan menolak.
const cb = m40.slice(m40.indexOf('FUNCTION public.create_booking'));
assert.match(cb,
  /IF p_capster_id IS NOT NULL\s+AND NOT EXISTS \(SELECT 1 FROM capsters c WHERE c\.id = p_capster_id AND c\.is_active\) THEN\s+p_capster_id := NULL;/);
// Jangkarnya harus awal baris. Tanpa itu, baris yang dikomentari dengan '--'
// tetap cocok dan penjaga ini diam saat pemicunya justru dimatikan.
const pemicu = cb.match(/^[ \t]*PERFORM kirim_wa_capster\(v_tx_id\);/m);
assert.ok(pemicu, 'create_booking harus memanggil kirim_wa_capster');
// Pemicunya harus sesudah INSERT, bukan sebelum: sebelum berarti mengabarkan
// booking yang masih bisa gagal.
assert.ok(cb.indexOf('INSERT INTO bookings') < pemicu.index,
  'notifikasi harus dipicu setelah booking tersimpan');

/* ── 5 · Satu booking, satu pesan ─────────────────────────────────────────
   Penanda dibaca di bawah kunci baris. Tanpa FOR UPDATE, dua permintaan yang
   tiba bersamaan sama-sama membaca penanda kosong dan sama-sama mengirim. */
assert.match(pengirim, /FROM bookings b WHERE b\.id = p_booking_id FOR UPDATE/);
assert.match(pengirim, /IF NOT FOUND OR v_b\.notif_wa_at IS NOT NULL THEN RETURN; END IF;/);
assert.match(pengirim, /SET notif_wa_at = now\(\)/);

/* ── 6 · Token tidak pernah sampai ke peramban ────────────────────────────*/
const cfg = m40.slice(m40.indexOf('FUNCTION owner_wa_config'),
                      m40.indexOf('FUNCTION set_wa_config'));
assert.match(cfg, /EXISTS \(SELECT 1 FROM vault\.decrypted_secrets/,
  'layar owner hanya boleh tahu tokennya terisi atau tidak');
assert.doesNotMatch(cfg, /SELECT[^)]*decrypted_secret\b(?!s)/,
  'owner_wa_config tidak boleh mengembalikan isi token');
assert.doesNotMatch(rekap, /decrypted_secret/,
  'rekap.html tidak boleh menyentuh isi token');
assert.match(rekap, /waData\.token_terisi/);

// wa_config terkunci: RLS menyala tanpa policy, jadi hanya terbaca lewat
// fungsi SECURITY DEFINER milik owner.
assert.match(m40, /ALTER TABLE wa_config ENABLE ROW LEVEL SECURITY;/);
assert.doesNotMatch(m40, /CREATE POLICY[\s\S]*wa_config/);
for (const f of ['owner_wa_config\\(\\)', 'set_wa_config\\(BOOLEAN, TEXT, TEXT, TEXT, TEXT\\)',
                 'owner_notif_wa\\(INT\\)']) {
  assert.match(m40, new RegExp(`REVOKE EXECUTE ON FUNCTION ${f}\\s+FROM PUBLIC, anon;`),
    `${f} harus dicabut dari anon`);
}

/* ── 7 · Owner dapat mengisi nomor capster sendiri ────────────────────────*/
assert.match(m41, /RETURNS TABLE \(capster_id UUID, name CHARACTER VARYING, email TEXT,\s+is_active BOOLEAN, punya_akun BOOLEAN, telepon CHARACTER VARYING\)/);
assert.match(m41, /IF NOT is_owner\(\) THEN\s+RAISE EXCEPTION 'Hanya owner yang boleh mengubah nomor capster\.';/);
// DROP FUNCTION memulihkan hak bawaan Supabase, yang mencakup anon. Mencabut
// dari PUBLIC saja tidak menutupnya.
assert.match(m41, /REVOKE EXECUTE ON FUNCTION owner_staff_list\(\) FROM PUBLIC, anon;/);
assert.match(m41, /REVOKE EXECUTE ON FUNCTION owner_set_capster_phone\(UUID, TEXT\) FROM PUBLIC, anon;/);
assert.match(rekap, /sb\.rpc\('owner_set_capster_phone'/);
assert.match(rekap, /data-telp-input="/);

/* Penormal nomor: satu bentuk simpan, apa pun yang diketik owner. */
const norm = m41.slice(m41.indexOf('FUNCTION normalkan_nomor_wa'));
assert.match(norm, /regexp_replace\(COALESCE\(p_nomor, ''\), '\[\^0-9\]', '', 'g'\)/);
assert.match(norm, /IF left\(v, 1\) = '0' THEN\s+v := '62' \|\| substr\(v, 2\);/);
assert.match(norm, /IF v !~ '\^62\[0-9\]\{8,15\}\$' THEN RETURN NULL; END IF;/);

console.log('Notifikasi WA capster tests: OK');
