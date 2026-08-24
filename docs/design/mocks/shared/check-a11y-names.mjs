/* Every control says its own name, out loud.
   Run:  node shared/check-a11y-names.mjs      (from docs/design/mocks)

   An icon button is a picture of a label. Hover it and the styled tooltip
   spells out "Measure"; reach it with VoiceOver instead and, until this rule
   existed, you got "button" — ten times in a row across a tool strip, which
   is the same as an unlabelled strip.

   shared/components/tooltip.js closes that at runtime: a `title` or a
   `data-tip` becomes the control's aria-label whenever the control has no
   other name, and the keystroke goes to aria-keyshortcuts. So the thing that
   has to hold in the SOURCE is simply that every icon-only control offers the
   tooltip something to work from. A button with no text inside it and none of
   `title`, `data-tip`, `aria-label`, `aria-labelledby` is anonymous no matter
   what any script does later, and that is what this catches.

   Scans .html pages and the .js that builds chrome from template strings,
   because a button written in a template literal is just as anonymous.

   Deliberately NOT caught: a button whose contents arrive from an
   interpolation (`${...}`), since the text may well be a perfectly good name
   and there is no way to tell from here; and the handful of controls a shared
   component names for the page at load (NAMED_AT_RUNTIME below). */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');

function files(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'dist' && e.name !== 'fixtures') files(p, out); }
    else if (/\.(html|js)$/.test(e.name) && !/^check-/.test(e.name)) out.push(p);
  }
  return out;
}

/* The span of one <button>…</button> / <a>…</a>, by counting same-tag nesting. */
function elements(src, tag) {
  const out = [];
  const open = new RegExp(`<${tag}\\b`, 'g');
  let m;
  while ((m = open.exec(src))) {
    const gt = src.indexOf('>', m.index);
    if (gt < 0) break;
    const attrs = src.slice(m.index, gt);
    let depth = 1, i = gt + 1;
    const walk = new RegExp(`<(/?)${tag}\\b`, 'g');
    walk.lastIndex = i;
    let w;
    while (depth > 0 && (w = walk.exec(src))) { depth += w[1] ? -1 : 1; i = walk.lastIndex; }
    out.push({ attrs, inner: src.slice(gt + 1, Math.max(gt + 1, i - tag.length - 2)), at: m.index });
  }
  return out;
}

const NAMES = /\b(aria-label|aria-labelledby|title|data-tip)\s*=/;
/* A shared component fills these in at load, so the source looks anonymous and
   is not. Each entry names the component that does it, because an unexplained
   exemption is how a real gap gets waved through. */
const NAMED_AT_RUNTIME = [
  { attrs: /\bclass="n"/, by: 'redline.js numbers the marker and labels it from its card' },
  { attrs: /\bdata-cp-slot=/, by: 'colorpicker.js writes the slot\'s hex into the button' },
];
/* JS carries these as prose in comments far more often than as real markup. */
const decomment = (s) => s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*\/\/.*$/gm, ' ');
/* Text a person would actually read: tags out, entities and glyph spans in.
   `.sc` keycaps and badges count — a button that reads only "3" is a separate
   problem from a button that reads nothing. */
const text = (s) => s.replace(/<[^>]*>/g, ' ').replace(/&[a-z]+;|&#\d+;/gi, 'x').replace(/\s+/g, ' ').trim();

const anon = [];
for (const file of files(ROOT).sort()) {
  const raw = readFileSync(file, 'utf8');
  const src = file.endsWith('.js') ? decomment(raw) : raw;
  for (const tag of ['button', 'a']) {
    for (const el of elements(src, tag)) {
      if (tag === 'a' && !/\bhref\s*=/.test(el.attrs)) continue;
      if (NAMES.test(el.attrs)) continue;
      if (el.attrs.includes('${') || el.inner.includes('${')) continue;   // can't tell
      if (NAMED_AT_RUNTIME.some((r) => r.attrs.test(el.attrs))) continue;
      if (text(el.inner)) continue;
      const line = src.slice(0, el.at).split('\n').length;
      anon.push({ file: relative(ROOT, file), line, html: `<${tag}${el.attrs.slice(tag.length + 1).replace(/\s+/g, ' ')}>`.slice(0, 90) });
    }
  }
}

if (anon.length) {
  console.error(`\n${anon.length} control(s) a screen reader would read as just "button":\n`);
  for (const a of anon) console.error(`  ${a.file}:${a.line}  ${a.html}`);
  console.error('\nGive it a title="Name (K)" or data-tip="Name|K"; tooltip.js turns that into the accessible name.\n');
  process.exit(1);
}
console.log('a11y names: every icon-only control has a name to read ✓');
