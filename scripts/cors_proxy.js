// Local dev-only CORS proxy for testing the ecom hub from a browser.
// Forwards every request to https://myna.glassdata.ai, adding permissive
// CORS headers - the real server only allows the https://myna.glassdata.ai
// origin, which blocks browser-based testing from anywhere else (curl/
// Postman aren't browsers, so they don't hit this).
//
// Usage: node scripts/cors_proxy.js [port]
// Then point ECOM_HUB_*_URL at http://localhost:<port>/api/v1/ah/... - only
// used for local web testing, never for Android or production.

const http = require('http');
const https = require('https');

const PORT = process.argv[2] ? parseInt(process.argv[2], 10) : 5050;
const TARGET_HOST = 'myna.glassdata.ai';

const server = http.createServer((req, res) => {
  const corsHeaders = {
    'Access-Control-Allow-Origin': req.headers.origin || '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  };

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders);
    res.end();
    return;
  }

  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const proxyReq = https.request(
      {
        host: TARGET_HOST,
        path: req.url,
        method: req.method,
        headers: { ...req.headers, host: TARGET_HOST },
      },
      (proxyRes) => {
        res.writeHead(proxyRes.statusCode, { ...proxyRes.headers, ...corsHeaders });
        proxyRes.pipe(res);
      },
    );
    proxyReq.on('error', (error) => {
      res.writeHead(502, { 'Content-Type': 'application/json', ...corsHeaders });
      res.end(JSON.stringify({ error: error.message }));
    });
    if (body.length > 0) proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(PORT, () => {
  console.log(`CORS proxy listening on http://localhost:${PORT} -> https://${TARGET_HOST}`);
});
