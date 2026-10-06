/* Keluar hanya dari perangkat ini, dan sesi yang mati diumumkan.
 *
 * Laporan owner: dashboard termuat normal, tetapi panel pengeluaran menjawab
 * "permission denied for function owner_pengeluaran_list" dan struk AI
 * menjawab "Sesi login sudah habis". Keduanya berarti permintaan terkirim
 * tanpa login. Sebabnya: sb.auth.signOut() tanpa opsi berlingkup 'global'
 * dan mencabut sesi akun yang sama di semua perangkat — menekan Keluar di
 * satu laptop mematikan dashboard di tempat lain begitu tokennya kedaluwarsa.
 */

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const baca = (f) => fs.readFileSync(path.join(root, f), 'utf8');

/* ── 1 · Setiap signOut berlingkup lokal ─────────────────────────────────── */
const berkas = fs.readdirSync(root).filter((f) => /\.(html|js)$/.test(f));
let jumlah = 0;
for (const f of berkas) {
  for (const m of baca(f).matchAll(/\.auth\.signOut\(([^)]*)\)/g)) {
    jumlah++;
    assert.match(m[1], /scope:\s*'local'/, `${f}: signOut tanpa scope 'local' mengeluarkan semua perangkat`);
  }
}
assert.ok(jumlah >= 2, 'sbSignOut dan tombol keluar kapster harus tetap ada');

/* ── 2 · Sesi yang hilang memuat ulang halaman ───────────────────────────── */
const app = baca('sb-app.js');
const pasang = app.slice(app.indexOf('sb.auth.onAuthStateChange'), app.indexOf('});', app.indexOf('sb.auth.onAuthStateChange')) + 3);

function jalankan(event, keluarSendiri) {
  let dimuatUlang = 0, pendengar;
  const sb = { auth: { onAuthStateChange: (fn) => { pendengar = fn; } } };
  const location = { reload: () => { dimuatUlang++; } };
  new Function('sb', 'location', `let sbKeluarSendiri = ${keluarSendiri};` + pasang)(sb, location);
  pendengar(event, null);
  return dimuatUlang;
}
assert.equal(jalankan('SIGNED_OUT', false), 1, 'sesi dicabut dari luar: layar masuk harus muncul');
assert.equal(jalankan('SIGNED_OUT', true), 0, 'Keluar di perangkat ini diurus sbSignOut sendiri');
// Kasir bekerja luring. Token yang gagal diperbarui karena jaringan tidak
// memicu SIGNED_OUT; peristiwa lain pun tidak boleh memuat ulang.
for (const ev of ['INITIAL_SESSION', 'SIGNED_IN', 'TOKEN_REFRESHED', 'USER_UPDATED']) {
  assert.equal(jalankan(ev, false), 0, `${ev} tidak boleh memuat ulang halaman`);
}

// Penanda dipasang SEBELUM signOut, sebab SIGNED_OUT terpancar di dalamnya.
for (const [f, kode] of [['sb-app.js', app], ['capster.html', baca('capster.html')]]) {
  const iTanda = kode.indexOf('sbKeluarSendiri = true');
  const iKeluar = kode.indexOf('.auth.signOut(');
  assert.ok(iTanda > 0 && iTanda < iKeluar, `${f}: sbKeluarSendiri harus dipasang sebelum signOut`);
}
// capster.html memakai variabel itu, jadi sb-app.js harus termuat lebih dulu.
const capster = baca('capster.html');
assert.ok(capster.indexOf('<script src="sb-app.js"></script>') < capster.indexOf('sbKeluarSendiri'));

console.log('keluar-sesi: semua pemeriksaan lolos');
