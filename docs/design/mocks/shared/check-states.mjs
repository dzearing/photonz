// Are the interaction states actually VISIBLE?
//
//   node shared/check-states.mjs
//
// The hover on a work-card row used to be `--glass-thin`, a near-opaque panel
// colour. On a light panel it read fine; on the dark card it was a 1% change
// and the row looked inert. The fix was to make the states overlays (a % of
// --ink, or of --accent when selected) so the delta comes from the token rather
// than from luck — and this script is the part that keeps them honest, because
// "looks fine on my screen" is how the first version passed review.
//
// It composites each state token over every surface a row is allowed to sit on,
// in both themes, and measures the change in relative luminance. Anything under
// FLOOR is reported and the process exits non-zero.
//
// Luminance, not hue distance, on purpose: these overlays are neutral or nearly
// so, and what a user perceives when a row lights up under the pointer is a
// brightness step. A hue-aware metric (CIEDE2000) would score the accent states
// generously for a difference the eye reads mostly as "bluer", not "brighter".

import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SHARED = dirname(fileURLToPath(import.meta.url));

// Minimum change in relative luminance, absolute, 0..1. 0.02 is about where a
// state stops being deniable on a 60Hz panel in a bright room — measured by
// dropping the ladder until people on the team stopped noticing hover at all.
const FLOOR = 0.02;
// Consecutive rungs (rest → hover → pressed) need to differ from EACH OTHER too,
// or pressed is just a slightly stickier hover.
const STEP_FLOOR = 0.015;

/* ---- colour ---- */
const hex = (h) => {
  const s = h.replace('#', '');
  const n = s.length === 3 ? s.split('').map((c) => c + c).join('') : s;
  return [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16));
};
// sRGB relative luminance, WCAG definition
const lum = ([r, g, b]) => {
  const f = (v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};
// `color-mix(in srgb, X p%, transparent)` composited over a backdrop is just
// alpha compositing at alpha = p.
const over = (fg, bg, alpha) => fg.map((c, i) => c * alpha + bg[i] * (1 - alpha));

/* ---- read BOTH the palette and the state ladder out of tokens.css, so this
        script cannot drift from the values that actually ship ---- */
async function themes() {
  const css = await readFile(join(SHARED, 'components', 'tokens.css'), 'utf8');
  // the light values are the first :root; the dark ones live under the
  // prefers-color-scheme block
  const darkStart = css.indexOf('prefers-color-scheme:dark');
  const blocks = { light: css.slice(0, darkStart), dark: css.slice(darkStart) };

  const grab = (block, name) => {
    const m = block.match(new RegExp(`--${name}\\s*:\\s*(#[0-9a-fA-F]{3,6})`));
    return m ? hex(m[1]) : null;
  };
  // --state-hover: color-mix(in srgb, var(--ink) 13%, transparent)
  const ladderOf = (block) => {
    const out = [];
    const re = /--state-([a-z-]+)\s*:\s*color-mix\(in srgb,\s*var\(--([a-z]+)\)\s*([\d.]+)%/g;
    let m;
    // the dark values appear twice — once under prefers-color-scheme and once
    // under :root[data-theme="dark"] — so keep the first of each name
    const seen = new Set();
    while ((m = re.exec(block))) {
      if (seen.has(m[1])) continue;
      seen.add(m[1]);
      out.push([m[1], m[2], parseFloat(m[3]) / 100]);
    }
    return out;
  };

  const build = (name) => {
    const b = blocks[name];
    return {
      ink: grab(b, 'ink'), accent: grab(b, 'accent'),
      ladder: ladderOf(b),
      // the surfaces a ROW is allowed to sit on. Not --stage: that is the page
      // behind the windows, and nothing row-shaped ever lands there.
      surfaces: {
        panel: grab(b, 'panel'), 'panel-2': grab(b, 'panel-2'),
        chrome: grab(b, 'chrome-solid'),
      },
    };
  };
  return { light: build('light'), dark: build('dark') };
}

const t = await themes();
const problems = [];

for (const [themeName, theme] of Object.entries(t)) {
  for (const [surfName, surf] of Object.entries(theme.surfaces)) {
    if (!surf) continue;
    const base = lum(surf);
    const rungs = [];
    for (const [name, tint, alpha] of theme.ladder) {
      const l = lum(over(theme[tint], surf, alpha));
      rungs.push([name, l]);
      const d = Math.abs(l - base);
      if (d < FLOOR) {
        problems.push(
          `${themeName}/${surfName}: --state-${name} is ${d.toFixed(3)} from rest (floor ${FLOOR})`
        );
      }
    }
    // rest → hover → press, and sel → sel-hover → sel-press, must each separate
    const pairs = [[0, 1], [2, 3], [3, 4]];
    for (const [a, b] of pairs) {
      const d = Math.abs(rungs[a][1] - rungs[b][1]);
      if (d < STEP_FLOOR) {
        problems.push(
          `${themeName}/${surfName}: --state-${rungs[a][0]} → --state-${rungs[b][0]} ` +
          `differ by only ${d.toFixed(3)} (floor ${STEP_FLOOR})`
        );
      }
    }
  }
}

const surfaces = Object.keys(t.light.surfaces).length * 2;
if (problems.length) {
  console.error(`✗ interaction states: ${problems.length} problem(s) across ${surfaces} surfaces\n`);
  problems.forEach((p) => console.error('  ' + p));
  process.exit(1);
}
console.log(`✓ interaction states: ${t.dark.ladder.length} rungs legible on all ${surfaces} surface/theme pairs`);
