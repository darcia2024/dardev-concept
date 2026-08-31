const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const landing = fs.readFileSync(path.join(root, 'landing.html'), 'utf8');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase_migration_25_booking_hardening.sql'),
  'utf8'
);

function extractFunctionSource(source, functionName) {
  const start = source.indexOf(`function ${functionName}`);
  assert.notEqual(start, -1, `${functionName} harus tersedia`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Penutup ${functionName} tidak ditemukan`);
}

for (const [name, html] of [['landing.html', landing], ['pos.html', pos]]) {
  for (const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    if (match[1].trim()) new Function(match[1]);
  }
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length, `${name} tidak boleh punya ID ganda`);
}

const slotSource = extractFunctionSource(landing, 'buatSlotBooking');
const buatSlotBooking = new Function(`${slotSource}; return buatSlotBooking;`)();

assert.deepEqual(
  buatSlotBooking(600, 1260, 45, 600).slice(-2),
  ['19:30', '20:00'],
  'layanan 45 menit harus selesai sebelum pukul 21.00'
);
assert.equal(
  buatSlotBooking(600, 1260, 150, 600).at(-1),
  '18:30',
  'layanan 150 menit terakhir dimulai pukul 18.30'
);
assert.equal(buatSlotBooking(600, 1260, 30, 950)[0], '16:00');
assert.deepEqual(buatSlotBooking(600, 1260, 30, 1240), []);

assert.match(landing, /id="bkKirim" disabled>Menyiapkan/);
assert.match(landing, /function tampilkanGagalMuat/);
assert.doesNotMatch(landing, /pesan\(res\.error\.message/);
assert.match(landing, /assets\/og-landing\.jpg/);
assert.doesNotMatch(landing, /og:image" content="[^"]*og-kartu/);

assert.match(pos, /id="btnOpenBookings"/);
assert.match(pos, /id="bookingModal"/);
assert.match(pos, /sb\.rpc\('bookings_list'/);
assert.match(pos, /sb\.rpc\('decide_booking'/);
assert.match(pos, /Hubungi WhatsApp/);

assert.match(migration, /INTERVAL '30 minutes'/);
assert.match(migration, /make_interval\(mins => v_srv\.duration_minutes\)/);
assert.match(migration, /length\(COALESCE\(v_catatan, ''\)\) > 300/);
assert.match(migration, /pg_advisory_xact_lock/);
assert.match(migration, /REVOKE EXECUTE ON FUNCTION create_booking/);

console.log('Landing and booking tests: OK');
