/* Does the canvas draw the selection the page PROMISES?
   Run:  node shared/check-selection.mjs             (from docs/design/mocks)
         node shared/check-selection.mjs --self-test (prove the gate still bites)

   This exists because one defect kept coming back. Five separate tasks in a
   single cycle each fixed the same thing on a different page: the copy said
   something was selected, the Layers row lit up, Properties filled in — and the
   canvas drew nothing at all. Every fix was correct and every fix was local, so
   the sixth page made the same mistake.

   The reason it kept happening is that drawing a selection used to be four
   lines of markup retyped by hand (`.sel-ring` + four `.handle`s + `.mtag`).
   `data-sel-frame` (selection.js) removed the retyping; this removes the
   forgetting.

   THREE GATES, and the first two are the same question asked two ways:

     A · a page that SELECTS A LAYER on canvas must draw a frame.
         A walkthrough step that lights a Layers row is asserting the
         three-place selection — canvas, Layers, Properties. Two of the three
         are in the markup; this checks the third. Selecting a timeline clip or
         a library tile is NOT this claim, so only `.lrow` targets count.

     B · a page whose COPY names the ring must draw a frame.
         Only phrases that promise the drawn thing ("the ring on the canvas",
         "selected on the canvas") — a page is allowed to discuss selection as
         a concept, list a "Selection ring" motion timing, or say a tile can be
         dropped "on the canvas or into a frame" without owing a picture.

     C · no NEW hand-drawn frames.
         A ratchet, not a ban: the pages that already hand-author their frame
         are fine where they are, and the count may only ever go down. Declare
         new ones with `data-sel-frame` and this number stays honest.

   Pages with no canvas are exempt from A and B: a spec or language page talks
   about the selection frame for a living and has no document to draw it on. */

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MOCKS = join(dirname(fileURLToPath(import.meta.url)), '..');
const PAGES = join(MOCKS, 'pages');
const FIXTURES = join(MOCKS, 'shared', 'fixtures');

/* Hand-authored `.sel-ring`s left in pages/. Lower it when you convert a page
   to `data-sel-frame`; never raise it. */
const HANDWRITTEN_MAX = 81;

/* The copy that promises a DRAWN frame. Deliberately narrow: a false failure
   here teaches people to switch the gate off. */
const CLAIMS = [
  /\bthe (?:selection )?ring on the canvas\b/i,
  /\bselection (?:ring|frame|handles) on the canvas\b/i,
  /\bselected on the canvas\b/i,
  /\bcanvas (?:ring|selection frame)\b/i,
  /\bring (?:appears|lands|shows) on the canvas\b/i
];

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/* The visible words, with page CSS, page script and authoring comments taken
   out — a comment saying "draw the ring on the canvas here" is a note to the
   next author, not a promise to the reader. */
function copyOf(src) {
  return src
    .replace(/<(style|script)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&[a-z]+;/g, ' ')
    .replace(/\s+/g, ' ');
}

export function inspect(src) {
  const hasCanvas = /class="[^"]*\b(?:canvas|cnv)\b/.test(src);

  // Both spellings of a drawn frame: the markup, and the declaration that
  // builds the markup.
  const handwritten = (src.match(/class="[^"]*\bsel-ring\b/g) || []).length;
  const declared = (src.match(/\bdata-sel-frame\b/g) || []).length;

  // Walkthrough steps that select something, resolved to the elements they name.
  const ids = new Set();
  for (const m of src.matchAll(/data-select="([^"]+)"/g)) {
    for (const one of m[1].split(',')) ids.add(one.trim().replace(/^#/, ''));
  }
  const rows = [...ids].filter((id) => {
    const tag = src.match(new RegExp('<[a-z]+[^>]*\\bid="' + esc(id) + '"[^>]*>'));
    return tag && /class="[^"]*\blrow\b/.test(tag[0]);
  });

  const copy = copyOf(src);
  const claim = CLAIMS.map((re) => copy.match(re)).find(Boolean);

  const frames = handwritten + declared;
  const failures = [];
  if (hasCanvas && !frames) {
    if (rows.length) {
      failures.push(
        `selects ${rows.length === 1 ? 'the Layers row' : rows.length + ' Layers rows'} ` +
        `(${rows.map((r) => '#' + r).join(', ')}) but the canvas draws no selection frame`
      );
    }
    if (claim) failures.push(`the copy says "${claim[0]}" but the canvas draws no selection frame`);
  }
  return { hasCanvas, handwritten, declared, rows, claim: claim ? claim[0] : null, failures };
}

function readPages(dir) {
  return readdirSync(dir)
    .filter((f) => f.endsWith('.html'))
    .sort()
    .map((f) => ({ name: f, src: readFileSync(join(dir, f), 'utf8') }));
}

/* ---- the gate the study runs ---- */
function run() {
  const pages = readPages(PAGES);
  const bad = [];
  let handwritten = 0;
  let declared = 0;
  let framed = 0;

  for (const { name, src } of pages) {
    const r = inspect(src);
    handwritten += r.handwritten;
    declared += r.declared;
    if (r.handwritten + r.declared) framed++;
    if (r.failures.length) bad.push({ name, failures: r.failures });
  }

  if (bad.length) {
    console.error(`\n${bad.length} page(s) promise a selection the canvas never draws:\n`);
    for (const b of bad) for (const f of b.failures) console.error(`  ${b.name.padEnd(26)} ${f}`);
    console.error(
      '\nDeclare it once and the frame builds itself:\n' +
      '  <div class="selwrap" data-sel-frame="Frame · 268 × 95"></div>\n' +
      'See shared/components/selection.js.\n'
    );
    process.exit(1);
  }

  if (handwritten > HANDWRITTEN_MAX) {
    console.error(
      `\n${handwritten} hand-drawn selection frames in pages/, and the ratchet is ${HANDWRITTEN_MAX}.\n` +
      'A new frame is declared, not drawn:  data-sel-frame="Frame · 268 × 95"\n' +
      'See shared/components/selection.js.\n'
    );
    process.exit(1);
  }

  console.log(
    `selection: ${framed} page(s) draw a frame — ${declared} declared, ${handwritten} hand-drawn ` +
    `(ratchet ${HANDWRITTEN_MAX}); every canvas that promises a selection draws one ✓`
  );
}

/* ---- the gate checking itself ----
   A gate nobody has seen fail is a gate nobody knows works. These fixtures are
   pages built to be wrong (and to be right in the ways that look wrong). */
function selfTest() {
  const EXPECT = {
    'claims-selection-draws-none.html': true,   // must be caught
    'claims-selection-draws-it.html': false,    // the same page, declared
    'talks-about-selection.html': false         // prose about selection, no canvas
  };
  let failed = 0;
  for (const { name, src } of readPages(FIXTURES)) {
    const want = EXPECT[name];
    if (want === undefined) {
      console.error(`  ${name.padEnd(34)} no expectation recorded — add one`);
      failed++;
      continue;
    }
    const got = inspect(src).failures;
    const ok = want === (got.length > 0);
    console.log(`  ${ok ? '✓' : '✗'} ${name.padEnd(34)} ${want ? 'caught' : 'passed'}: ${got.length ? got.join('; ') : 'no complaint'}`);
    if (!ok) failed++;
  }
  if (failed) {
    console.error(`\nself-test: ${failed} fixture(s) came out wrong — the gate is not doing its job.\n`);
    process.exit(1);
  }
  console.log('\nselection self-test: the gate catches a page that claims a selection and draws none ✓');
}

// `inspect` is exported so the self-test — and anything that wants to judge a
// page it is holding rather than one on disk — can reuse the one rule set.
// Only run the sweep when this file IS the command.
const invoked = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  if (process.argv.includes('--self-test')) selfTest();
  else run();
}
