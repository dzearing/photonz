// Photonz mock dev server + livereload. Stable repo path so it survives context resets.
// Start (detached):  cd docs/design/mocks && nohup node dev-server.mjs >/tmp/photonz-mock-server.log 2>&1 & disown
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { watch } from 'node:fs';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const ROOT = dirname(fileURLToPath(import.meta.url)); // docs/design/mocks
const TYPES = { '.html': 'text/html;charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.json': 'application/json' };
// dev livereload: inject an SSE client that reloads the page on any file change
const LR = `<script>(function(){try{var e=new EventSource('/__reload');e.onmessage=function(){location.reload();};e.onerror=function(){setTimeout(function(){location.reload();},1500);};}catch(_){}})();</script>`;
const clients = new Set();
watch(ROOT, { recursive: true }, () => { for (const res of clients) { try { res.write('data: change\n\n'); } catch (_) {} } });
// The two shared bundles are ASSEMBLED per request from the base file plus one
// file per component (shared/components/, ordered by order.json). Components get
// their own small files; pages keep the same two URLs and the same execution
// order, so a page's inline <script> still runs after the DS. See
// shared/components/README.md. `node shared/build-ds.mjs` writes the same output.
export async function assemble(kind) {
  const dir = join(ROOT, 'shared', 'components');
  let order = { css: [], js: [] };
  try { order = JSON.parse(await readFile(join(dir, 'order.json'), 'utf8')); } catch (_) {}
  const parts = [await readFile(join(ROOT, 'shared', `photonz-ds.${kind}`), 'utf8')];
  for (const name of order[kind] || []) {
    try {
      parts.push(`\n/* ===== component: ${name}.${kind} ===== */\n` +
        await readFile(join(dir, `${name}.${kind}`), 'utf8'));
    } catch (_) { /* a component may be CSS-only or JS-only */ }
  }
  return parts.join('\n');
}

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  const bundle = url === '/shared/photonz-ds.css' ? 'css'
    : url === '/shared/photonz-ds.js' ? 'js' : null;
  if (bundle) {
    try {
      const out = await assemble(bundle);
      res.writeHead(200, { 'content-type': TYPES['.' + bundle], 'cache-control': 'no-store' });
      return res.end(out);
    } catch (e) { res.writeHead(500); return res.end(String(e)); }
  }
  if (url === '/__reload') {
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', 'connection': 'keep-alive' });
    res.write(':ok\n\n'); clients.add(res); req.on('close', () => clients.delete(res)); return;
  }
  try {
    let p = decodeURIComponent(url); if (p === '/') p = '/index.html';
    const file = normalize(join(ROOT, p));
    if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end('no'); }
    let buf = await readFile(file);
    const type = TYPES[extname(file)] || 'application/octet-stream';
    if (extname(file) === '.html') buf = Buffer.from(buf.toString().replace('</body>', LR + '</body>'));
    res.writeHead(200, { 'content-type': type, 'cache-control': 'no-store' });
    res.end(buf);
  } catch (e) { res.writeHead(404); res.end('not found'); }
});
server.listen(8791, '127.0.0.1', () => console.log('photonz mock dev server + livereload on http://127.0.0.1:8791/'));
