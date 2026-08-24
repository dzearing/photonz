/* A page must not borrow a design-system class name to mean its own thing.
   Run:  node shared/check-reserved.mjs        (from docs/design/mocks)
         node shared/check-reserved.mjs --list (show the hazard set and exit)

   WHAT GOES WRONG. tokens.css owns `.body{display:grid;grid-template-columns:
   220px 1fr}` — the app shell's rail plus content. A page that reuses `.body`
   for a card's lower half gets that grid for free: on lang-color the 230px
   swatch card inherited a 220px first column, so the description was laid out
   starting 3px PAST the card's right edge and, with the card clipping, simply
   vanished. Nothing in the page's own CSS looks wrong, which is why this is
   worth a gate rather than a code review.

   WHAT THIS CHECKS. Not "did you use a reserved word" — pages legitimately
   restyle real DS components all day (`#dashboard .db-ttrow .btn{…}`), and no
   amount of grep tells a refinement of a real `.btn` apart from a page that
   invented its own. What IS decidable is the damage:

     a DS stylesheet imposes a STRUCTURAL property on a bare class
     unconditionally (grid-template-columns/rows/area, float, position:
     absolute|fixed — the ones that move boxes rather than colour them),
     and a page styles that same bare class as its key selector
     WITHOUT redeclaring that property.

   Then the page's element is being positioned by a rule its author never
   wrote. That is either a bug already or one waiting for the DS to change.
   A page that DOES redeclare the property has taken ownership and is fine.

   THE ALLOWLIST is per class, not per page, and it is small on purpose. It
   names DS components that pages restyle in place so often that the check
   cannot see the difference — a `.sel-ring` inside a page's own `.mobj` really
   is the DS selection ring, and it wants its `position:absolute`. Adding a
   name here says "this class is used as itself"; it does not exempt a page
   that reuses the name for something new, so keep the list short and reasoned.

   See the RESERVED CLASS NAMES block at the top of shared/components/tokens.css
   for the naming rule this backs up, and the PREFIX rule in shared/AGENTS.md. */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CSS = join(HERE, 'components');
const PAGES = join(HERE, '..', 'pages');

/* Properties that move a box rather than paint it. Inheriting one of these by
   accident is the "mystery layout bug"; inheriting a colour is not. */
const STRUCTURAL = ['grid-template-columns', 'grid-template-rows', 'grid-area', 'float', 'position'];

/* DS components that pages restyle in place, where the DS structure is wanted.
   One line each saying what the class actually is, so the next reader can tell
   whether a new entry belongs. */
const USED_AS_ITSELF = {
  canvas: 'the shared artboard; every canvas page sizes and themes its own',
  'sel-ring': 'the selection ring, drawn inside a page-local selected object',
  handle: 'a selection resize handle, same',
  mtag: 'the measurement tag above a selection, same',
  cring: 'the component instance ring',
  cbadge: 'the component instance badge',
  'artboard-label': 'the label floated over an artboard',
  slrow: 'a slider row; the slider reference pages retune its label column',
  setrow: 'an inspector settings row',
  'cnv-hint': 'the transient hint centred on the canvas',
};

const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '');
/* Crude but sufficient: flatten at-rule openers so their inner rules are seen
   as ordinary rules. Leaves a stray `}` on the next selector, trimmed below. */
const flatten = (s) => s.replace(/@[a-z-]+[^{]*\{/g, '{');

function rules(css) {
  const out = [];
  for (const m of flatten(strip(css)).matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const decls = {};
    for (const d of m[2].split(';')) {
      const i = d.indexOf(':');
      if (i > 0) decls[d.slice(0, i).trim()] = d.slice(i + 1).trim();
    }
    for (const sel of m[1].split(',')) {
      const s = sel.trim().replace(/^[\s}]+/, '');
      if (s) out.push({ sel: s, decls });
    }
  }
  return out;
}

/* Which structural properties does this rule impose? `position:relative` is
   not one: it does not take the box out of flow. */
const imposed = (decls) =>
  STRUCTURAL.filter((p) => p in decls && (p !== 'position' || /absolute|fixed/.test(decls[p])));

/* The hazard set: a bare `.foo` rule in a DS stylesheet with no ancestor and no
   companion class, so it matches ANY element carrying that class. */
function hazards() {
  const haz = new Map();
  for (const f of readdirSync(CSS).filter((f) => f.endsWith('.css'))) {
    for (const r of rules(readFileSync(join(CSS, f), 'utf8'))) {
      if (!/^\.[a-zA-Z][\w-]*$/.test(r.sel)) continue;
      const bad = imposed(r.decls);
      if (!bad.length) continue;
      const cls = r.sel.slice(1);
      const e = haz.get(cls) || { files: new Set(), props: new Set() };
      e.files.add(f);
      bad.forEach((p) => e.props.add(p));
      haz.set(cls, e);
    }
  }
  return haz;
}

/* The class a selector actually targets: the last compound, and only when that
   compound is a single class. `.a .b.c` targets a `.b.c` pair, which is a
   refinement of a DS element rather than a new name for one. */
function keyClass(sel) {
  const compounds = sel.split(/\s*[\s>+~]\s*/).filter(Boolean);
  const key = compounds[compounds.length - 1];
  const cls = [...key.matchAll(/\.([a-zA-Z][\w-]*)/g)].map((m) => m[1]);
  return cls.length === 1 ? cls[0] : null;
}

const haz = hazards();

if (process.argv.includes('--list')) {
  console.log(`${haz.size} DS classes impose structure unconditionally:\n`);
  for (const [c, e] of [...haz].sort()) {
    const allowed = c in USED_AS_ITSELF ? '  (allowlisted: used as itself)' : '';
    console.log(`  .${c.padEnd(16)} ${[...e.props].join(', ').padEnd(24)} ${[...e.files].join(' ')}${allowed}`);
  }
  process.exit(0);
}

const violations = [];
for (const page of readdirSync(PAGES).filter((f) => f.endsWith('.html')).sort()) {
  const src = readFileSync(join(PAGES, page), 'utf8');
  const css = [...src.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');

  /* Everything the page declares for a given key class, across all its rules:
     a page may neutralise the DS grid in one rule and tune padding in another,
     and that is still ownership. */
  const owned = new Map();
  const where = new Map();
  for (const r of rules(css)) {
    const cls = keyClass(r.sel);
    if (!cls || !haz.has(cls) || cls in USED_AS_ITSELF) continue;
    if (!owned.has(cls)) { owned.set(cls, new Set()); where.set(cls, []); }
    Object.keys(r.decls).forEach((p) => owned.get(cls).add(p));
    where.get(cls).push(r.sel);
  }

  for (const [cls, props] of owned) {
    const inherited = [...haz.get(cls).props].filter((p) => !props.has(p));
    if (inherited.length) {
      violations.push({ page, cls, inherited, from: [...haz.get(cls).files].join(' '), sels: where.get(cls) });
    }
  }
}

if (violations.length) {
  console.error(`\n${violations.length} page rule(s) borrow a design-system class name and inherit its layout:\n`);
  for (const v of violations) {
    console.error(`  ${v.page} · .${v.cls}`);
    console.error(`    inherits ${v.inherited.join(', ')} from ${v.from}`);
    console.error(`    page rules: ${v.sels.join('  |  ')}`);
  }
  console.error(`
Rename the page-local class with a page tag (\`#lang-color .swbody\`), or, if the
element really IS that design-system component, add it to USED_AS_ITSELF in this
file with a line saying so. See RESERVED CLASS NAMES in shared/components/tokens.css.
`);
  process.exit(1);
}
console.log(`reserved names: no page borrows a design-system layout class (${haz.size} guarded, ${Object.keys(USED_AS_ITSELF).length} allowlisted) ✓`);
