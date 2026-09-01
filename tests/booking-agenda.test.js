const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const migrasi = fs.readFileSync(
  path.join(root, 'supabase_migration_35_agenda_booking.sql'),
  'utf8'
);

// Lencana booking pernah hanya menghitung status 'baru'. Akibatnya ia jatuh ke
// nol tepat setelah kasir menekan Konfirmasi, dan booking yang sudah dipastikan
// ke pelanggan justru yang paling tidak terlihat — orangnya datang pukul 12.30
// tanpa ada apa pun yang mengingatkan siapa pun.
assert.match(pos, /sb\.rpc\('bookings_agenda'\)/);
const sumberBadge = pos.slice(
  pos.indexOf('async function refreshBookingBadge'),
  pos.indexOf('async function loadBookings')
);
assert.match(sumberBadge, /bookings_agenda/, 'lencana harus menghitung agenda');
assert.doesNotMatch(
  sumberBadge,
  /p_status: 'baru'/,
  'lencana tidak boleh kembali menghitung hanya permintaan baru'
);

// Agenda harus jadi tampilan bawaan panel, bukan pilihan yang harus dicari.
const opsi = pos.slice(pos.indexOf('id="bookingStatusFilter"'));
const opsiPertama = opsi.slice(0, opsi.indexOf('</select>')).match(/<option value="([^"]*)"/);
assert.equal(opsiPertama[1], 'agenda', 'Agenda harus jadi pilihan pertama sekaligus bawaan');

// ── Isi agenda ─────────────────────────────────────────────────────────────
// Dua hal saja: permintaan yang belum diputuskan, dan booking terkonfirmasi
// yang hari ini atau sudah lewat. Booking terkonfirmasi untuk hari mendatang
// adalah kabar baik, bukan tugas; memasukkannya membuat lencana selalu
// berangka besar sampai kasir berhenti memperhatikannya.
assert.match(migrasi, /b\.status = 'baru'/);
assert.match(migrasi, /b\.status = 'dikonfirmasi' AND b\.tanggal <= jakarta_today\(\)/);
assert.doesNotMatch(migrasi, /b\.tanggal >= jakarta_today\(\)/);
assert.match(migrasi, /auth\.uid\(\) IS NOT NULL/, 'agenda hanya untuk perangkat yang sudah masuk');
assert.match(migrasi, /REVOKE EXECUTE ON FUNCTION bookings_agenda\(\) FROM PUBLIC, anon/);

// Selisih menit dihitung di server, dari zona Jakarta. Jam perangkat kasir
// dapat meleset, dan pengingat "sebentar lagi" yang meleset satu jam lebih
// buruk daripada tidak ada pengingat sama sekali.
assert.match(migrasi, /now\(\) AT TIME ZONE 'Asia\/Jakarta'/);
const sumberRender = pos.slice(pos.indexOf('let kapan = '), pos.indexOf('return \'<article class="booking-item'));
assert.match(sumberRender, /row\.menit_lagi/);
assert.doesNotMatch(sumberRender, /new Date\(\)/, 'selisih waktu tidak boleh dihitung dari jam perangkat');

// ── Penanda waktu yang dibaca kasir ────────────────────────────────────────
// Dibungkus jadi fungsi, bukan dijalankan lewat eval di lingkup ini: `let`
// di dalam eval membuat variabel barunya sendiri, sehingga nilai yang disusun
// tidak pernah keluar dan pengujiannya selalu membandingkan teks kosong.
const penanda = new Function('row', sumberRender + '; return kapan;');

assert.match(penanda({ menit_lagi: 35 }), /35 menit lagi/);
assert.match(penanda({ menit_lagi: 35 }), /segera/, 'kurang dari sejam harus ditandai segera');
assert.match(penanda({ menit_lagi: 259 }), /4 jam 19 menit lagi/);
assert.doesNotMatch(penanda({ menit_lagi: 259 }), /segera/, 'masih lama tidak boleh ditandai segera');
assert.match(penanda({ menit_lagi: 120 }), /2 jam lagi/, 'jam bulat tidak menyebut menit');
assert.match(penanda({ menit_lagi: -45 }), /Lewat 45 menit/);
assert.match(penanda({ menit_lagi: -45 }), /lewat/, 'yang sudah lewat harus ditandai lain');
assert.equal(penanda({ menit_lagi: null }), '', 'permintaan yang belum diputuskan tidak punya hitungan mundur');

console.log('Booking agenda tests: OK');
