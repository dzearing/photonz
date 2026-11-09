#!/usr/bin/env node
// Plays animated SVGs Photonz exported in real browser engines, WebKit
// (Safari's) and Chromium (Chrome's), and says whether every turn in them
// comes home where the lap starts over: the angle the engine draws a
// millisecond before each lap ends against the one it draws as the next
// begins, for three laps (task `a-looping-turn-comes-home-and-spins-evenly-
// witho`). With --film <folder> it also records each file playing for three
// laps, one video per engine, for an audit's reel.
//
//   Scripts/svg-lap-seam-check.mjs [--within 1] [--film <folder>] <file.svg> ...
//
// Needs Playwright's own engines, found the way `Scripts/svg-preview-check.mjs`
// finds them (`npx playwright install webkit chromium`).
//
// Exit 0: every turn in every file came home within the bar in both engines.
// 1: one did not. 2: no engine could be started (nothing was checked).

import { createRequire } from 'module';
import fs from 'fs';
import os from 'os';
import path from 'path';

const require = createRequire(import.meta.url);
const args = process.argv.slice(2);
let within = 1;
let film = null;
const files = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === '--within') within = Number(args[++i]);
  else if (args[i] === '--film') film = args[++i];
  else files.push(path.resolve(args[i]));
}
if (!files.length) {
  console.log('usage: Scripts/svg-lap-seam-check.mjs [--within 1] [--film <folder>] <file.svg> ...');
  process.exit(2);
}

function findPlaywright() {
  if (process.env.PLAYWRIGHT_CORE) return require(process.env.PLAYWRIGHT_CORE);
  const npx = path.join(os.homedir(), '.npm', '_npx');
  const found = (fs.existsSync(npx) ? fs.readdirSync(npx) : [])
    .map((d) => path.join(npx, d, 'node_modules', 'playwright-core'))
    .filter((d) => fs.existsSync(path.join(d, 'package.json')))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return found.length ? require(found[0]) : null;
}

function engines() {
  const cache = path.join(os.homedir(), 'Library', 'Caches', 'ms-playwright');
  const newest = (prefix, rel) => (fs.existsSync(cache) ? fs.readdirSync(cache) : [])
    .filter((d) => d.startsWith(prefix))
    .map((d) => path.join(cache, d, rel))
    .filter((p) => fs.existsSync(p))
    .sort()
    .pop();
  return [
    ['WebKit', 'webkit', newest('webkit-', 'pw_run.sh')],
    ['Chromium', 'chromium', newest('chromium-', 'chrome-mac/Chromium.app/Contents/MacOS/Chromium')],
  ];
}

const pw = findPlaywright();
if (!pw) {
  console.log('!! No playwright-core found. Run `npx playwright --version` once, or set PLAYWRIGHT_CORE.');
  process.exit(2);
}

// The page an SVG plays in: the file itself, large, on white.
const page = (svg) => `<!doctype html><html><body style="margin:0;background:#fff;display:grid;place-items:center;height:100vh">
<div style="width:480px;height:480px">${svg.replace(/<svg /, '<svg width="480" height="480" ')}</div></body></html>`;

// Every turn's angle, in degrees, at `seconds` into the file's clock: the
// animations are paused and set there, so the answer is the engine's own.
const anglesAt = (p, seconds) => p.evaluate((seconds) => {
  const svg = document.querySelector('svg');
  svg.pauseAnimations();
  svg.setCurrentTime(seconds);
  return [...document.querySelectorAll('animateTransform[type="rotate"]')].map((a) => {
    const item = a.parentElement.transform.animVal;
    for (let i = 0; i < item.numberOfItems; i += 1) {
      if (item.getItem(i).type === 4) return item.getItem(i).angle;
    }
    return null;
  });
}, seconds);

const lapOf = (svg) => {
  const m = svg.match(/animateTransform[^>]*type="rotate"[^>]*dur="(\d+)ms"/);
  return m ? Number(m[1]) / 1000 : null;
};

let failed = false;
let started = 0;
for (const [name, kind, exe] of engines()) {
  let browser;
  try {
    browser = await pw[kind].launch({ executablePath: exe, headless: true });
  } catch (e) {
    console.log(`!! ${name} would not start: ${String(e).split('\n')[0]}`);
    continue;
  }
  started += 1;
  try {
    for (const file of files) {
      const svg = fs.readFileSync(file, 'utf8');
      const lap = lapOf(svg);
      const label = path.basename(file);
      if (!lap) {
        console.log(`  FAIL ${name.padEnd(8)} ${label}: no turn in the file`);
        failed = true;
        continue;
      }
      const p = await browser.newPage({ viewport: { width: 480, height: 480 } });
      await p.setContent(page(svg));
      for (let n = 1; n <= 3; n += 1) {
        const before = await anglesAt(p, n * lap - 0.001);
        const after = await anglesAt(p, n * lap + 0.001);
        before.forEach((b, i) => {
          const a = after[i];
          const apart = Math.abs((((b - a) % 360) + 540) % 360 - 180);
          const ok = apart <= within;
          if (!ok) failed = true;
          console.log(`${ok ? '  ok  ' : '  FAIL'} ${name.padEnd(8)} ${label} lap ${n}: ${b.toFixed(2)}° then ${a.toFixed(2)}°, ${apart.toFixed(2)}° apart`);
        });
      }
      // A quarter of the way round, for a reader to see the turn is there.
      const quarter = await anglesAt(p, lap / 4);
      console.log(`       ${name.padEnd(8)} ${label} at a quarter lap: ${quarter.map((q) => q.toFixed(1) + '°').join(', ')}`);
      await p.close();

      if (film) {
        fs.mkdirSync(film, { recursive: true });
        const context = await browser.newContext({
          viewport: { width: 480, height: 480 },
          recordVideo: { dir: film, size: { width: 480, height: 480 } },
        });
        const playing = await context.newPage();
        await playing.setContent(page(svg));
        await playing.waitForTimeout(lap * 3000 + 300);
        const video = playing.video();
        await context.close();
        if (video) {
          const out = path.join(film, `${label.replace(/\.svg$/, '')}-${kind}.webm`);
          fs.renameSync(await video.path(), out);
          console.log(`       ${name.padEnd(8)} ${label} filmed for three laps: ${out}`);
        }
      }
    }
  } finally {
    await browser.close();
  }
}
if (!started) process.exit(2);
process.exit(failed ? 1 : 0);
