// Write the assembled design-system bundles to disk, for serving the mocks
// statically (the dev server assembles the same output per request, so you only
// need this when something other than dev-server.mjs is serving the folder).
//
//   node shared/build-ds.mjs
//
// Output: shared/dist/photonz-ds.css and shared/dist/photonz-ds.js
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SHARED = dirname(fileURLToPath(import.meta.url));
const DIR = join(SHARED, 'components');

async function assemble(kind) {
  const order = JSON.parse(await readFile(join(DIR, 'order.json'), 'utf8'));
  const parts = [await readFile(join(SHARED, `photonz-ds.${kind}`), 'utf8')];
  for (const name of order[kind] || []) {
    try {
      parts.push(`\n/* ===== component: ${name}.${kind} ===== */\n` +
        await readFile(join(DIR, `${name}.${kind}`), 'utf8'));
    } catch { /* a component may be CSS-only or JS-only */ }
  }
  return parts.join('\n');
}

const out = join(SHARED, 'dist');
await mkdir(out, { recursive: true });
for (const kind of ['css', 'js']) {
  const body = await assemble(kind);
  await writeFile(join(out, `photonz-ds.${kind}`), body);
  console.log(`shared/dist/photonz-ds.${kind}  ${(body.length / 1024).toFixed(1)} KB`);
}
