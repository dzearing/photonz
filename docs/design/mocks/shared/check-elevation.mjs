/* Guard the elevation ladder.
   Run:  node shared/check-elevation.mjs      (from docs/design/mocks)

   Chrome must take its depth from a token (see shared/components/elevation.css):
     --shadow-1  raised a hair      --shadow     the window
     --shadow-2  the hover lift     --lg-shadow  a float over live content
     --glow*     a filled/selected control, in its own colour
     --lg-shadow-3  a surface ON a float        --ring  focus (not elevation)

   This existed because the ladder had drifted badly: `.elev-1` and `.elev-2`
   were each defined twice with different shadows, `.seg button.on` three times,
   and 20+ rules hand-rolled the two rungs that had no token. Splitting the
   megafile made it visible; this keeps it visible.

   Canvas ARTWORK is exempt: a hero card's glow or a photo's sun is content, not
   chrome, and it is allowed to invent its own light. */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), 'components');

// selectors that draw pictures rather than chrome
const ARTWORK = /hero-card|\.photo|\.vframe|\.uibtn|\.shot|\.wshot|hc-cta|\.sun\b|\.pv\b|artboard|gx-plate|ig-board|\.px\b|\.ti\b/;
const TOKEN = /--shadow|--lg-shadow|--glow|--ring|--ctl-gloss|--cp-card-shadow/;

const offenders = [];
for (const file of readdirSync(DIR).filter((f) => f.endsWith('.css'))) {
  const src = readFileSync(join(DIR, file), 'utf8');
  for (const m of src.matchAll(/([^\n{}]+)\{[^}]*?box-shadow:\s*([^;}]+)/g)) {
    const sel = m[1].replace(/\s+/g, ' ').trim();
    const val = m[2].replace(/\s+/g, ' ').trim();
    // only the OUTER shadow is elevation; inset is a surface highlight
    const outer = val.split(',').filter((p) => !p.includes('inset')).join(',').trim();
    if (!outer || TOKEN.test(outer)) continue;
    if (!/\d+px/.test(outer)) continue;             // no blur = not a shadow
    if (/^0 0 0 [\d.]+px/.test(outer)) continue;    // a ring/hairline, not depth
    if (ARTWORK.test(sel)) continue;                // content, not chrome
    offenders.push({ file, sel: sel.slice(-46), outer: outer.slice(0, 56) });
  }
}

if (offenders.length) {
  console.error(`\n${offenders.length} hand-written shadow(s) on chrome — use a ladder token:\n`);
  for (const o of offenders) console.error(`  ${o.file.padEnd(18)} ${o.sel.padEnd(46)} ${o.outer}`);
  console.error('\nSee shared/components/elevation.css.\n');
  process.exit(1);
}
console.log('elevation: every chrome shadow comes from the ladder ✓');
