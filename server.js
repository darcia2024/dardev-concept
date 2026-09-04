import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = process.env.PORT || 7800;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
};

const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0];

  if (reqPath === '/demo' || reqPath === '/demo/' || reqPath === '/almadraj/demo' || reqPath === '/almadraj/demo/') {
    reqPath = '/demo.html';
  } else if (reqPath === '/' || reqPath === '' || reqPath === '/almadraj' || reqPath === '/almadraj/') {
    reqPath = '/proposal.html';
  }

  let filePath = path.join(__dirname, reqPath);

  // If path doesn't exist, check public folder or fallback to proposal.html
  if (!fs.existsSync(filePath)) {
    const publicPath = path.join(__dirname, 'public', reqPath);
    if (fs.existsSync(publicPath)) {
      filePath = publicPath;
    } else {
      filePath = path.join(__dirname, 'proposal.html');
    }
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Server Error');
    } else {
      res.writeHead(200, { 
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*'
      });
      res.end(content);
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Platform Kelas Al Madroj berjalan di:`);
  console.log(`👉 Proposal: http://localhost:${PORT}/almadraj`);
  console.log(`👉 Demo UI Paket Standard: http://localhost:${PORT}/demo`);
  console.log(`👉 Demo UI via Slug: http://localhost:${PORT}/almadraj/demo\n`);
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    const nextPort = Number(PORT) + 1;
    console.log(`Port ${PORT} sedang dipakai, mencoba port ${nextPort}...`);
    server.listen(nextPort, '0.0.0.0');
  } else {
    console.error('Server error:', err);
  }
});
