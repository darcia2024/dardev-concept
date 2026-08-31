const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const rekap = fs.readFileSync(path.join(root, 'rekap.html'), 'utf8');
const queue = fs.readFileSync(path.join(root, 'sb-app.js'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase_migration_30_diskon_kasir.sql'),
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

for (const [name, html] of [['pos.html', pos], ['rekap.html', rekap]]) {
  for (const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    if (match[1].trim()) new Function(match[1]);
  }
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length, `${name} tidak boleh punya ID ganda`);
}

const calculateManualDiscount = new Function(
  `${extractFunctionSource(pos, 'calculateManualDiscount')}; return calculateManualDiscount;`
)();

assert.deepEqual(
  calculateManualDiscount({ kind: 'percent', value: 10, min_subtotal: 0, is_active: true }, 100000, 0),
  { amount: 10000, eligible: true }
);
assert.deepEqual(
  calculateManualDiscount({ kind: 'percent', value: 20, max_discount: 15000, is_active: true }, 100000, 0),
  { amount: 15000, eligible: true },
  'batas maksimal harus memotong hasil persen'
);
assert.deepEqual(
  calculateManualDiscount({ kind: 'fixed', value: 25000, min_subtotal: 100000, is_active: true }, 90000, 0),
  { amount: 0, eligible: false },
  'diskon tidak berlaku sebelum minimum belanja tercapai'
);
assert.deepEqual(
  calculateManualDiscount({ kind: 'fixed', value: 50000, is_active: true }, 60000, 20000),
  { amount: 40000, eligible: true },
  'gabungan poin dan diskon kasir tidak boleh membuat total negatif'
);
assert.equal(
  calculateManualDiscount({ kind: 'fixed', value: 10000, is_active: false }, 100000, 0).amount,
  0
);

assert.match(pos, /id="discountSection"/);
assert.match(pos, /id="selManualDiscount"/);
assert.match(pos, /payload\.p_discount_id = selectedDiscount\.id/);
assert.match(pos, /id="rcptManualDiscountRow"/);
assert.match(pos, /discount_manual: res\.tx/);
assert.match(rekap, /tx\.discount_manual/);
assert.match(rekap, /Diskon Kasir \(Rp\)/);

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.pos_discounts/);
assert.match(migration, /p_discount_id UUID DEFAULT NULL/);
assert.match(migration, /WHERE d\.id = p_discount_id AND d\.is_active/);
assert.match(migration, /p_subtotal < v_discount\.min_subtotal/);
assert.match(migration, /v_manual := LEAST\(v_manual, GREATEST\(p_subtotal - v_disc, 0\)\)/);
assert.match(migration, /v_final := GREATEST\(p_subtotal - v_disc - v_manual, 0\)/);
assert.match(migration, /total_spend = members\.total_spend \+ v_final/);
assert.match(migration, /v_earn := floor\(v_final/);
assert.match(migration, /discount_id, discount_name, discount_manual/);
assert.match(migration, /IF COALESCE\(p_cash_paid, 0\) < v_final/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);

assert.match(queue, /err\.code === 'P0001'/);

console.log('POS discount tests: OK');
