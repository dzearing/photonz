/* One key means one tool, inside one tool bar.
   Run:  node shared/check-shortcuts.mjs      (from docs/design/mocks)

   Every tool bar teaches its keys twice: as `title="Name (K)"` on the button
   and as a `.sc` keycap in the overflow menu. If two DIFFERENT tools in the
   SAME bar print the same keystroke, one of them can never be reached from
   the keyboard, and the bar is lying about the other. That is the bug this
   catches.

   What it deliberately does NOT catch:
   - The same letter in two UNRELATED bars. Several pages render a gallery of
     mode-specific bars side by side (app-shell.html, lang-toolbars.html), so
     C = Crop in an image bar and C = Component insert in a UI bar is
     mode-dependent, not a collision.
   - A tool printing the same key in two places in one bar (button + its own
     overflow row). That is the bar agreeing with itself, which is the point.

   Letters follow Photoshop wherever Photoshop has the same tool, and where it
   does not, `Sources/PhotonzCore/Tools.swift` is the source of truth. A tool
   that shares a Photoshop group with another tool shown in the same bar takes
   the shifted form (Heal J, Patch ⇧J), which is the keystroke that actually
   reaches it. See shared/AGENTS.md, "One key means one tool". */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PAGES = join(HERE, '..', 'pages');

/* The span of one `<div class="tbar…">`, by counting div nesting. */
function barRegions(src) {
  const regions = [];
  for (const open of src.matchAll(/<div class="tbar[^"]*"/g)) {
    let depth = 0;
    const tag = /<(\/?)div\b/g;
    tag.lastIndex = open.index;
    let m;
    while ((m = tag.exec(src))) {
      depth += m[1] ? -1 : 1;
      if (depth === 0) break;
    }
    regions.push(src.slice(open.index, m ? tag.lastIndex : src.length));
  }
  return regions;
}

/* Every (label, keystroke) a bar teaches. */
function hints(bar) {
  const out = [];
  for (const m of bar.matchAll(/title="([^"]*?)\s*\(([A-Z0-9⇧⌥⌃⌘]{1,4})\)"/g)) {
    out.push({ label: m[1].trim(), key: m[2] });
  }
  for (const m of bar.matchAll(/<div class="menuitem"[^>]*>(.*?)<\/div>/g)) {
    const key = /<span class="sc">([^<]+)<\/span>/.exec(m[1]);
    if (!key) continue;
    const label = m[1]
      .replace(/<span class="sc">[^<]*<\/span>/g, ' ')
      .replace(/<[^>]*>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    out.push({ label, key: key[1].trim() });
  }
  return out;
}

/* Menu rows read "Clone stamp" where the button reads "Clone stamp (S)";
   normalise enough that a bar is not reported as colliding with itself. */
const norm = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '');

const collisions = [];
for (const page of readdirSync(PAGES).filter((f) => f.endsWith('.html')).sort()) {
  const src = readFileSync(join(PAGES, page), 'utf8');
  barRegions(src).forEach((bar, i) => {
    const byKey = new Map();
    for (const h of hints(bar)) {
      if (!byKey.has(h.key)) byKey.set(h.key, new Map());
      byKey.get(h.key).set(norm(h.label), h.label);
    }
    for (const [key, labels] of byKey) {
      if (labels.size > 1) collisions.push({ page, bar: i + 1, key, labels: [...labels.values()] });
    }
  });
}

if (collisions.length) {
  console.error(`\n${collisions.length} tool bar(s) give one key to two tools:\n`);
  for (const c of collisions) {
    console.error(`  ${c.page} · bar ${c.bar} · ${c.key}  →  ${c.labels.join('  |  ')}`);
  }
  console.error('\nSee shared/AGENTS.md, "One key means one tool".\n');
  process.exit(1);
}
console.log('shortcuts: every tool bar gives each key to exactly one tool ✓');
