/* Guard the field wrappers.
   Run:  node shared/check-fieldwrap.mjs      (from docs/design/mocks)

   Several components in this system are a WELL with the real control inside it:

     <label class="input"><input placeholder="Name"></label>
     <div class="stepper"><span class="k">W</span><input value="320"></div>
     <label class="switch"><input type="checkbox"><i></i></label>

   The class styles the wrapper; a child rule (`.input>input`, `.stepper>input`,
   `.switch>input`) styles the control. Put the class on the control itself and
   you get half a component: the dark recessed well paints, but the `color`,
   `font` and `background:transparent` rules never match, so on a dark theme you
   type black text into a black box and cannot read a word of it. That is what
   happened on the dashboard: four fields, all invisible while typing.

   Nothing in the markup says which is which, so this check reads it out of the
   CSS: any class with a `> input | textarea | select` child rule is a wrapper,
   and no bare form control may wear one.

   If a component ever wants to be legal on a bare element, give the bare form
   its own rule in the component file (`input.foo{...}`) and add it to LEGAL_BARE
   below with a note. Adding a colour rule for bare elements WITHOUT saying so
   here is how the rule rots. */
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const COMPONENTS = join(ROOT, 'shared', 'components');

// classes the design system deliberately styles in both forms, with the reason
const LEGAL_BARE = new Set([]);

// ---- 1. which classes are wrappers? ask the CSS ----
const wrappers = new Map();                       // class -> component file
for (const file of readdirSync(COMPONENTS).filter((f) => f.endsWith('.css'))) {
  const src = readFileSync(join(COMPONENTS, file), 'utf8');
  // strip comments so the prose examples above a component do not count
  const css = src.replace(/\/\*[\s\S]*?\*\//g, '');
  for (const m of css.matchAll(/\.([a-z][a-z0-9-]*)(?:[^\s{},]*)?\s*>\s*(?:input|textarea|select)\b/g)) {
    if (!wrappers.has(m[1])) wrappers.set(m[1], file);
  }
}

// ---- 2. does any markup put one on the control itself? ----
const files = [];
for (const dir of ['pages', 'shared', '.']) {
  const abs = join(ROOT, dir);
  for (const f of readdirSync(abs)) {
    if (/\.(html|js)$/.test(f)) files.push([dir === '.' ? f : `${dir}/${f}`, join(abs, f)]);
  }
}

const offenders = [];
for (const [label, abs] of files) {
  const src = readFileSync(abs, 'utf8');
  const lines = src.split('\n');
  lines.forEach((line, i) => {
    // markup is written literally and inside JS strings, so quotes may be escaped
    for (const m of line.matchAll(/<(input|textarea|select)\b[^>]*?class=\\?["']([^"'\\]*)/g)) {
      for (const cls of m[2].split(/\s+/)) {
        if (!wrappers.has(cls) || LEGAL_BARE.has(cls)) continue;
        offenders.push({ label, line: i + 1, tag: m[1], cls, css: wrappers.get(cls) });
      }
    }
  });
}

if (offenders.length) {
  console.error(`\n${offenders.length} wrapper class(es) on a bare form control — wrap the field instead:\n`);
  for (const o of offenders) {
    console.error(`  ${(o.label + ':' + o.line).padEnd(40)} <${o.tag} class="${o.cls}">   (.${o.cls} is a wrapper, see components/${o.css})`);
  }
  console.error('\nWrite <label class="X"><input …></label>, so the field inherits its ink.\n');
  process.exit(1);
}
console.log(`field wrappers: ${wrappers.size} wrapper classes (${[...wrappers.keys()].sort().join(', ')}), none worn by a bare control ✓`);
