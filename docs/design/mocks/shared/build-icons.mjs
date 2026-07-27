/* Regenerate everything downstream of shared/icons.mjs.
   Run:  node shared/build-icons.mjs      (from docs/design/mocks)

   Writes three GENERATED regions, each fenced by BEGIN/END markers:
     shared/components/icons.css   the .ic-* mask rules
     pages/iconography.html  the searchable grid
     shared/AGENTS.md        the available-names list

   Nothing else in those files is touched. */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CATEGORIES, ICONS, ALIASES, STROKE } from './icons.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');

/* Minimal, valid percent-encoding for an SVG data URI inside url("..."). */
function enc(svg) {
  return svg
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/%/g, '%25')
    .replace(/</g, '%3C')
    .replace(/>/g, '%3E')
    .replace(/#/g, '%23')
    .replace(/"/g, '%22');
}

function dataUri(inner) {
  const svg =
    `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' ` +
    `stroke-width='${STROKE}' stroke-linecap='round' stroke-linejoin='round'>${inner}</svg>`;
  return `url("data:image/svg+xml,${enc(svg)}")`;
}

function splice(file, marker, body) {
  const path = join(ROOT, file);
  const src = readFileSync(path, 'utf8');
  const begin = `${marker}:BEGIN`;
  const end = `${marker}:END`;
  const i = src.indexOf(begin);
  const j = src.indexOf(end);
  if (i === -1 || j === -1) throw new Error(`${file}: missing ${begin}/${end} markers`);
  const head = src.slice(0, src.indexOf('\n', i) + 1);
  const tail = src.slice(src.lastIndexOf('\n', j) + 1);
  writeFileSync(path, head + body + '\n' + tail);
  return path;
}

/* ---- 1 · the CSS mask rules --------------------------------------- */

const cssLines = [];
for (const cat of CATEGORIES) {
  cssLines.push(`/* ${cat.name} */`);
  for (const [name, svg] of cat.icons) cssLines.push(`.ic-${name}{--i:${dataUri(svg)}}`);
}
cssLines.push('/* Aliases — older names, same mask */');
for (const [from, to] of Object.entries(ALIASES)) {
  const target = ICONS.find((i) => i.name === to);
  if (!target) throw new Error(`alias ${from} points at unknown icon ${to}`);
  cssLines.push(`.ic-${from}{--i:${dataUri(target.svg)}}`);
}
splice('shared/components/icons.css', '/* ICONS', cssLines.join('\n'));

/* ---- 2 · the searchable grid on the iconography page --------------- */

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const grid = CATEGORIES.map((cat) => {
  const cells = cat.icons
    .map(
      ([name, , blurb, keywords]) =>
        `        <button class="icell" data-name="${name}" data-terms="${esc(name + ' ' + (keywords || '') + ' ' + blurb).toLowerCase()}" title="${esc(blurb)}">` +
        `<i class="ic ic-${name}"></i><span class="in">${name}</span></button>`
    )
    .join('\n');
  return (
    `      <section class="icat" data-cat="${cat.id}">\n` +
    `        <div class="icat-h"><h3>${esc(cat.name)}</h3><span class="icount">${cat.icons.length}</span></div>\n` +
    `        <p class="icat-n">${esc(cat.note)}</p>\n` +
    `        <div class="igrid">\n${cells}\n        </div>\n` +
    `      </section>`
  );
}).join('\n');

const aliasRows = Object.entries(ALIASES)
  .map(
    ([from, to]) =>
      `        <div class="arow" data-terms="${from} ${to}"><i class="ic ic-${from}"></i><code>ic-${from}</code><span class="ar">use</span><code>ic-${to}</code></div>`
  )
  .join('\n');

splice(
  'pages/iconography.html',
  '<!-- ICONS',
  grid + '\n      <section class="icat" data-cat="alias">\n' +
    '        <div class="icat-h"><h3>Aliases</h3><span class="icount">' + Object.keys(ALIASES).length + '</span></div>\n' +
    '        <p class="icat-n">Older names kept alive so nothing breaks. They render the canonical glyph. Use the name on the right in new work.</p>\n' +
    '        <div class="alist">\n' + aliasRows + '\n        </div>\n      </section>'
);

/* ---- 3 · the name list AGENTS.md hands to page authors ------------- */

const names = CATEGORIES.map(
  (c) => `**${c.name}** — ` + c.icons.map(([n]) => n).join(' ')
).join('\n\n');
splice(
  'shared/AGENTS.md',
  '<!-- ICONNAMES',
  names +
    '\n\nAliases (older names, still render): ' +
    Object.entries(ALIASES).map(([f, t]) => `${f}→${t}`).join(' ')
);

console.log(
  `icons: ${ICONS.length} glyphs in ${CATEGORIES.length} groups, ${Object.keys(ALIASES).length} aliases, stroke ${STROKE}`
);
