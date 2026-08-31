const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const posHtml = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const makeQr = require(path.join(root, 'vendor', 'qrcode.js'));
const decodeQr = require(path.join(root, 'vendor', 'jsqr.js'));

function renderQrPixels(text) {
  const qr = makeQr(0, 'M');
  qr.addData(text);
  qr.make();

  const modules = qr.getModuleCount();
  const quiet = 4;
  const scale = 8;
  const size = (modules + quiet * 2) * scale;
  const pixels = new Uint8ClampedArray(size * size * 4);

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const moduleX = Math.floor(x / scale) - quiet;
      const moduleY = Math.floor(y / scale) - quiet;
      const dark = moduleX >= 0 && moduleY >= 0 &&
        moduleX < modules && moduleY < modules && qr.isDark(moduleY, moduleX);
      const value = dark ? 0 : 255;
      const offset = (y * size + x) * 4;
      pixels[offset] = value;
      pixels[offset + 1] = value;
      pixels[offset + 2] = value;
      pixels[offset + 3] = 255;
    }
  }

  return { pixels, size };
}

function extractFunctionSource(source, functionName) {
  const start = source.indexOf(`function ${functionName}`);
  assert.notEqual(start, -1, `${functionName} harus ada di pos.html`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;

  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }

  throw new Error(`Penutup ${functionName} tidak ditemukan`);
}

for (const payload of [
  'BKAB23CD45',
  'https://underratedbarbershop.com/kartu?c=BKAB23CD45'
]) {
  const { pixels, size } = renderQrPixels(payload);
  const result = decodeQr(pixels, size, size, { inversionAttempts: 'attemptBoth' });
  assert.ok(result, `QR ${payload} harus terbaca`);
  assert.equal(result.data, payload);
}

const extractSource = extractFunctionSource(posHtml, 'extractMemberCode');
const extractMemberCode = new Function(
  'location',
  `${extractSource}; return extractMemberCode;`
)({ origin: 'https://underratedbarbershop.com' });

assert.equal(extractMemberCode('BKAB23CD45'), 'BKAB23CD45');
assert.equal(
  extractMemberCode('https://underratedbarbershop.com/kartu?c=BKAB23CD45'),
  'BKAB23CD45'
);
assert.equal(
  extractMemberCode('https://dardev-concept.vercel.app/kartu?kode=bkab23cd45'),
  'BKAB23CD45'
);
assert.equal(extractMemberCode('https://example.com/random'), '');
assert.equal(extractMemberCode('bukan-kode-member'), '');

const jsQrIndex = posHtml.indexOf('<script src="vendor/jsqr.js"></script>');
const appIndex = posHtml.indexOf('<script src="sb-app.js"></script>');
assert.ok(jsQrIndex > -1 && jsQrIndex < appIndex, 'jsQR harus dimuat sebelum logika POS');
assert.match(posHtml, /id="qrScannerModal"/);
assert.match(posHtml, /id="btnOpenQrScanner"/);
assert.match(posHtml, /sb\.rpc\('lookup_member_by_code'/);

console.log('QR scanner tests: OK');
