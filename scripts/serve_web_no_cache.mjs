// Static file server for build/web with caching fully disabled. Flutter's
// web output has no cache-busting on main.dart.js, so a plain static server
// (e.g. `python -m http.server`) can silently keep serving an old build
// after a rebuild until the browser is hard-refreshed - this sends explicit
// no-store headers on every response so a normal reload always gets the
// latest build. Usage: node scripts/serve_web_no_cache.mjs [port]
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', 'build', 'web');
const PORT = Number(process.argv[2]) || 8768;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

const server = createServer(async (req, res) => {
  try {
    let urlPath = decodeURIComponent(req.url.split('?')[0]);
    if (urlPath === '/') urlPath = '/index.html';
    let filePath = join(ROOT, urlPath);

    let st;
    try {
      st = await stat(filePath);
    } catch {
      // SPA fallback for path-based deep links (the app itself uses hash
      // routing, so this mainly covers a bare unknown path).
      filePath = join(ROOT, 'index.html');
      st = await stat(filePath);
    }
    if (st.isDirectory()) filePath = join(filePath, 'index.html');

    const data = await readFile(filePath);
    res.writeHead(200, {
      'Content-Type': MIME[extname(filePath)] || 'application/octet-stream',
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      Pragma: 'no-cache',
      Expires: '0',
    });
    res.end(data);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
});

server.listen(PORT, () => console.log(`Serving build/web on http://localhost:${PORT} (no-cache)`));
