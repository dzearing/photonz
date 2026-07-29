// Photonz mock dev server + livereload. Stable repo path so it survives context resets.
// Start (detached):  cd docs/design/mocks && nohup node dev-server.mjs >/tmp/photonz-mock-server.log 2>&1 & disown
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { watch } from 'node:fs';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const ROOT = dirname(fileURLToPath(import.meta.url)); // docs/design/mocks
const TYPES = { '.html': 'text/html;charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.json': 'application/json' };
// dev livereload: poll a change counter and reload when it moves.
//
// This used to be an SSE stream, and that is what made mock pages "hang on
// load" with no error anywhere. An SSE stream never ends, and a browser allows
// only ~6 concurrent HTTP/1.1 connections per origin. One permanent stream per
// open page meant that at about five tabs — and index.html costs two by itself,
// one for the shell and one for its iframe — the next request to this origin
// never got a connection. It was queued, not failing, so there was nothing in
// the console and the page just sat there. The long-standing "lang-resize.html
// hangs the tab" note was this; it was never about that page.
//
// Gating the stream on document.hidden was the first fix and it was not enough:
// background tabs kept the connection anyway. A 1s poll cannot starve the pool
// at all, because each request is short-lived — which matters more here than
// the elegance of a push, on localhost, for a mock server.
const LR = `<script>(function(){
var rev=null;
function tick(){
  if(document.hidden)return;
  fetch('/__rev',{cache:'no-store'}).then(function(r){return r.text();}).then(function(t){
    if(rev!==null&&t!==rev){location.reload();return;}
    rev=t;
  }).catch(function(){});
}
tick();setInterval(tick,1000);
document.addEventListener('visibilitychange',function(){if(!document.hidden)tick();});
})();</script>`;
let rev = 0;
watch(ROOT, { recursive: true }, () => { rev++; });
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
  if (url === '/__rev') {
    res.writeHead(200, { 'content-type': 'text/plain', 'cache-control': 'no-store' });
    return res.end(String(rev));
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
