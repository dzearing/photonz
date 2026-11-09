#!/usr/bin/env node
// Tries the pages Preview as Web Page writes in real browser engines, WebKit
// (Safari's) and Chromium (Chrome's), and says whether each way of playing
// does what the Export sheet says it does.
//
//   Scripts/svg-preview-check.mjs [folder]
//
// The folder is where `Scripts/playtest/svg-preview-web-page-walk.json` writes
// its pages (the default): always.html, hover.html (On hover, Follow the
// page), once.html, default.html. The icon in them is a shape keyed to turn
// 0 -> 90 degrees over the first second of a two second lap, beside a red
// badge that is the accent.
//
// Needs Playwright's own engines, which `npx playwright install webkit
// chromium` puts under ~/Library/Caches/ms-playwright. It finds the newest
// copy of playwright-core npx has cached; set PLAYWRIGHT_CORE to a
// playwright-core folder to choose one.
//
// Exit 0: every check passed in both engines. 1: a check failed. 2: no
// engine could be started (nothing was checked).

import { createRequire } from 'module';
import fs from 'fs';
import os from 'os';
import path from 'path';

const require = createRequire(import.meta.url);
const folder = process.argv[2] || '/tmp/photonz-playtest/svg-preview-web-page-walk';

function findPlaywright() {
  if (process.env.PLAYWRIGHT_CORE) return require(process.env.PLAYWRIGHT_CORE);
  const npx = path.join(os.homedir(), '.npm', '_npx');
  const found = (fs.existsSync(npx) ? fs.readdirSync(npx) : [])
    .map((d) => path.join(npx, d, 'node_modules', 'playwright-core'))
    .filter((d) => fs.existsSync(path.join(d, 'package.json')))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (!found.length) return null;
  return require(found[0]);
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

// The turn of the icon inside `selector`, in degrees, as the engine is
// drawing it right now.
const turn = (page, selector) => page.evaluate((selector) => {
  const g = document.querySelector(selector + ' g[transform^="rotate"]');
  return g ? Math.round(g.transform.animVal.getItem(0).angle * 10) / 10 : null;
}, selector);
const fillOf = (page, selector) => page.evaluate((s) => getComputedStyle(document.querySelector(s)).fill, selector);
const box = (page, selector) => page.evaluate((s) => {
  const r = document.querySelector(s).getBoundingClientRect();
  return { x: r.x, y: r.y, w: r.width, h: r.height };
}, selector);

const results = [];
let started = 0;
function check(engine, page, what, ok, saw) {
  results.push({ engine, page, what, ok });
  console.log(`${ok ? '  ok  ' : '  FAIL'} ${engine.padEnd(8)} ${page.padEnd(12)} ${what}${saw === undefined ? '' : `  (saw ${JSON.stringify(saw)})`}`);
}

for (const [name, kind, exe] of engines()) {
  let browser;
  try {
    browser = await pw[kind].launch({ executablePath: exe, headless: true });
  } catch (e) {
    console.log(`!! ${name} would not start: ${String(e).split('\n')[0]}`);
    continue;
  }
  started += 1;
  const open = async (file) => {
    const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
    await page.goto('file://' + path.join(folder, file));
    return page;
  };
  try {
    // Always: it goes round with nobody pointing at it.
    {
      const page = await open('always.html');
      await page.waitForTimeout(600);
      const t = await turn(page, '.strip.light .try-button');
      check(name, 'always', 'plays with no hover', t > 5, t);
      await page.close();
    }
    // On hover, Follow the page.
    {
      const page = await open('hover.html');
      await page.waitForTimeout(700);
      const rest = await turn(page, '.strip.light .try-button');
      check(name, 'on hover', 'rests on its first frame until hovered', rest === 0, rest);
      const label = await box(page, '.strip.light .try-button span');
      await page.mouse.move(label.x + label.w / 2, label.y + label.h / 2);
      await page.waitForTimeout(600);
      const playing = await turn(page, '.strip.light .try-button');
      check(name, 'on hover', 'plays while the BUTTON is hovered (pointer on its words)', playing > 5, playing);
      await page.mouse.move(5, 5);
      await page.waitForTimeout(150);
      const left = await turn(page, '.strip.light .try-button');
      check(name, 'on hover', 'back to its first frame when the pointer leaves', left === 0, left);
      await page.mouse.move(label.x + label.w / 2, label.y + label.h / 2);
      await page.waitForTimeout(300);
      const again = await turn(page, '.strip.light .try-button');
      check(name, 'on hover', 'plays again from the top on the next hover', again > 0 && again < playing + 5, again);
      await page.mouse.move(5, 5);
      const others = await turn(page, '.strip.dark .try-button');
      check(name, 'on hover', 'hovering one copy leaves the others still', others === 0, others);
      const icon = await box(page, '.strip.dark [data-size="48"] .box');
      await page.mouse.move(icon.x + 2, icon.y + 2);
      await page.waitForTimeout(500);
      const sized = await turn(page, '.strip.dark [data-size="48"]');
      check(name, 'on hover', 'an icon on its own plays when pointed at, even at an empty corner', sized > 5, sized);
      await page.mouse.move(5, 5);
      const looping = await turn(page, '[data-plays="always"]');
      check(name, 'on hover', 'the Going round copy plays with no hover', looping > 5, looping);
      const inkLight = await fillOf(page, '.strip.light .try-button rect');
      const inkDark = await fillOf(page, '.strip.dark .try-button rect');
      check(name, 'on hover', 'the ink is the light strip\'s text colour', inkLight === 'rgb(29, 29, 31)', inkLight);
      check(name, 'on hover', 'the ink is the dark strip\'s text colour', inkDark === 'rgb(245, 245, 247)', inkDark);
      const accent = await fillOf(page, '.strip.dark .try-button ellipse');
      check(name, 'on hover', 'the red accent keeps its colour on dark', accent === 'rgb(255, 59, 48)', accent);
      await page.close();
    }
    // Once: one lap, then held on the last frame.
    {
      const page = await open('once.html');
      await page.waitForTimeout(600);
      const going = await turn(page, '.strip.light .try-button');
      check(name, 'once', 'plays with no hover', going > 5, going);
      await page.waitForTimeout(2200);
      const held = await turn(page, '.strip.light .try-button');
      await page.waitForTimeout(1500);
      const still = await turn(page, '.strip.light .try-button');
      check(name, 'once', 'holds its last frame after one lap', held === 90 && still === 90, [held, still]);
      await page.close();
    }
    // The drawing's own choice, untouched: Always, As drawn.
    {
      const page = await open('default.html');
      const chips = await page.evaluate(() => [...document.querySelectorAll('.chip b')].map((b) => b.textContent));
      check(name, 'default', 'says Always and As drawn', chips.join('/') === 'Always/As drawn', chips);
      const ink = await fillOf(page, '.strip.dark .try-button rect');
      check(name, 'default', 'as drawn keeps the drawn ink, even on dark', ink === 'rgb(29, 29, 31)', ink);
      await page.close();
    }
  } finally {
    await browser.close();
  }
}

if (!started) {
  console.log('!! Neither engine started: nothing was checked.');
  process.exit(2);
}
const failed = results.filter((r) => !r.ok);
console.log(`==> ${results.length - failed.length} of ${results.length} checks passed in ${started} engine(s).`);
process.exit(failed.length ? 1 : 0);
