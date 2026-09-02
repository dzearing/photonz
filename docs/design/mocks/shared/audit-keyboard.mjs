/* Everything a mouse can click, a keyboard can reach.
   Run:  node shared/audit-keyboard.mjs [pageId ...] [--walk] [--verbose]
         (from docs/design/mocks, with the dev server up on :8791)

   A menu row in the study is a <div>. A card that links one page to another
   is a <div>. A bold word in a sentence that jumps you somewhere is a <b>.
   core.js binds click to every [data-target], popover.js to every
   [data-menu], and a mouse reaches all of them, so the pages LOOK finished.
   Tab reaches none of them, and a screen reader does not know they exist,
   because a div with a click listener is still just a div.

   core.js now upgrades those at load (role, tab stop, Enter/Space, arrow keys
   inside a menu). That is runtime behaviour, so no grep of the source can
   tell whether it holds; this runs the pages in a real browser and asks:

     · can every cross-link and every menu trigger take focus?
     · does every menu row have a keyboard path (its own tab stop, or one
       stop for the menu plus arrow keys)?
     · does Enter on a focused cross-link actually navigate (the shell
       receives the same photonzNav message a click sends)?
     · does a menu opened from the keyboard receive focus, move on
       ArrowDown, and close on Escape with focus back on its trigger?

   It also lists, for information only, anything else that shows a pointer
   cursor without being one of the shared vocabularies: those are page-private
   click handlers, and a page that binds its own is on its own for keys.

   --walk additionally presses Tab across each page and checks that every
   visible cross-link and trigger was actually landed on, which catches an
   element that is focusable on paper but unreachable in practice.

   Needs Playwright (the global @playwright/mcp install is enough) and a
   Chrome to drive; PZ_CHROME overrides the executable, PZ_BASE the server. */
import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const BASE = process.env.PZ_BASE || 'http://127.0.0.1:8791';
const argv = process.argv.slice(2);
const WALK = argv.includes('--walk');
const VERBOSE = argv.includes('--verbose');
const only = argv.filter((a) => !a.startsWith('--'));

function loadPlaywright() {
  const req = createRequire(import.meta.url);
  try { return req('playwright'); } catch (_) { /* not local */ }
  const g = execSync('npm root -g', { encoding: 'utf8' }).trim();
  for (const p of ['playwright', '@playwright/mcp/node_modules/playwright', '@playwright/test']) {
    if (existsSync(join(g, p, 'package.json'))) return req(join(g, p));
  }
  throw new Error('Playwright not found: npm i -g playwright (or @playwright/mcp)');
}

function chrome() {
  if (process.env.PZ_CHROME) return process.env.PZ_CHROME;
  const mac = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  return existsSync(mac) ? mac : undefined;
}

const pages = only.length
  ? only
  : readdirSync(join(ROOT, 'pages')).filter((f) => f.endsWith('.html')).map((f) => f.slice(0, -5)).sort();

/* Runs inside the page: one record per clickable thing. */
function collect() {
  const NATIVE = 'button,input,select,textarea,summary';
  const vis = (el) => el.offsetParent !== null || getComputedStyle(el).position === 'fixed';
  const sig = (el) => {
    const cls = typeof el.className === 'string' ? el.className.trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.') : '';
    const t = el.getAttribute('data-target');
    return el.tagName.toLowerCase() + (cls ? '.' + cls : '') + (t ? '[→' + t + ']' : '');
  };
  const focusable = (el) => {
    if (el.matches(NATIVE)) return !el.disabled;
    if (el.tagName === 'A') return el.hasAttribute('href') || el.tabIndex >= 0;
    return el.tabIndex >= 0;
  };
  const menuOf = (el) => el.closest('.menu,[role="menu"],.popover');
  const seen = new Set();
  const items = [];
  const add = (el, kind) => {
    if (seen.has(el)) return;
    seen.add(el);
    // a disabled control is unreachable on purpose
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') return;
    const m = kind === 'menuitem' ? menuOf(el) : null;
    const its = m ? [].slice.call(m.querySelectorAll('.menuitem')) : [];
    const pop = el.closest('.popover.pop');
    items.push({
      kind,
      sig: sig(el),
      native: el.matches(NATIVE) || (el.tagName === 'A' && el.hasAttribute('href')),
      focusable: focusable(el),
      role: el.getAttribute('role'),
      visible: vis(el),
      closedPop: !!pop && !pop.classList.contains('on'),
      roving: !!m && its.some((i) => i.tabIndex === 0) && its.every((i) => i.tabIndex >= -1 && i.hasAttribute('tabindex')),
      text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 28),
    });
  };
  document.querySelectorAll('.menuitem').forEach((el) => add(el, 'menuitem'));
  document.querySelectorAll('[data-target]').forEach((el) => add(el, 'link'));
  document.querySelectorAll('[data-menu]').forEach((el) => add(el, 'trigger'));
  const VOCAB = 'button,a[href],input,select,textarea,label,summary,[data-target],[data-menu],.menuitem,[tabindex],[role]';
  document.querySelectorAll('body *').forEach((el) => {
    if (seen.has(el) || !vis(el)) return;
    if (getComputedStyle(el).cursor !== 'pointer') return;
    if (el.closest(VOCAB) || el.querySelector(VOCAB)) return;
    // the outermost pointer element only: cursor inherits, so a card's every
    // child would otherwise be counted as its own target
    if (el.parentElement && getComputedStyle(el.parentElement).cursor === 'pointer') return;
    // `__clk` is stamped by the init script on any element that had a click
    // listener added; without one the pointer cursor is decoration
    add(el, el.__clk || el.hasAttribute('onclick') ? 'pointer' : 'cursor');
  });
  return items;
}

async function auditPage(page, id) {
  await page.setContent('<iframe id="f" style="width:1280px;height:900px;border:0"></iframe>');
  await page.evaluate((id) => {
    window.__nav = [];
    addEventListener('message', (e) => { if (e.data && e.data.photonzNav) window.__nav.push(e.data.photonzNav); });
    document.getElementById('f').src = '/pages/' + id + '.html';
  }, id);
  await page.waitForFunction(() => {
    const d = document.getElementById('f').contentDocument;
    return d && d.readyState === 'complete' && d.body && d.body.children.length > 0;
  }, null, { timeout: 15000 });
  await page.waitForTimeout(400);
  const frame = page.frames().find((f) => f !== page.mainFrame());
  const items = await frame.evaluate(collect);

  const r = { id, links: 0, linksBad: [], rows: 0, rowsBad: [], triggers: 0, triggersBad: [], pointer: [], nav: 0, navBad: [], menus: 0, menusBad: [], walkMissed: [] };
  for (const it of items) {
    if (it.kind === 'link') { r.links++; if (!it.focusable) r.linksBad.push(it); }
    else if (it.kind === 'trigger') { r.triggers++; if (!it.focusable) r.triggersBad.push(it); }
    else if (it.kind === 'menuitem') { r.rows++; if (!it.focusable && !it.roving) r.rowsBad.push(it); }
    else if (it.kind === 'pointer') r.pointer.push(it);
  }

  /* Enter on a cross-link must navigate. Links inside a closed popover are
     opened first, since that is the only way a person reaches them. */
  const links = await frame.$$('[data-target]');
  for (const h of links) {
    const st = await h.evaluate((el) => {
      const pop = el.closest('.popover.pop');
      const opened = pop && !pop.classList.contains('on');
      if (opened) pop.classList.add('on');
      const vis = el.offsetParent !== null || getComputedStyle(el).position === 'fixed';
      if (!vis) { if (opened) pop.classList.remove('on'); return null; }
      return { opened: !!opened, native: el.matches('button,a[href]') };
    });
    if (!st) continue;
    const before = await page.evaluate(() => window.__nav.length);
    await h.evaluate((el) => el.focus());
    const focused = await h.evaluate((el) => document.activeElement === el);
    if (focused) await page.keyboard.press('Enter');
    /* postMessage is a task, not a call: give it a moment to land. */
    await page.waitForFunction((n) => window.__nav.length > n, before, { timeout: 400 }).catch(() => {});
    const after = await page.evaluate(() => window.__nav.length);
    r.nav++;
    if (after === before) r.navBad.push({ sig: await h.evaluate((el) => el.tagName.toLowerCase() + '[→' + el.getAttribute('data-target') + ']'), focused });
    await h.evaluate((el, st) => { if (st.opened) { const pop = el.closest('.popover.pop'); if (pop) pop.classList.remove('on'); } }, st);
    await frame.evaluate(() => document.querySelectorAll('.popover.pop.on').forEach((p) => p.classList.remove('on')));
  }

  /* A menu opened from its trigger: Enter opens and focuses a row, ArrowDown
     moves, Escape closes and hands focus back. */
  const triggers = await frame.$$('[data-menu]');
  for (const t of triggers) {
    const ok = await t.evaluate((el) => {
      const m = document.querySelector(el.getAttribute('data-menu') || '#_');
      const vis = el.offsetParent !== null || getComputedStyle(el).position === 'fixed';
      return !!m && vis && !!m.querySelector('.menuitem');
    });
    if (!ok) continue;
    r.menus++;
    // a walkthrough step may have left this very menu open; Enter would then
    // (correctly) close it, so start every trigger from a closed menu
    await frame.evaluate(() => document.querySelectorAll('.popover.pop.on').forEach((p) => p.classList.remove('on')));
    await t.evaluate((el) => el.focus());
    const focused = await t.evaluate((el) => document.activeElement === el);
    const fail = [];
    if (!focused) fail.push('no focus');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(30);
    let s = await t.evaluate((el) => {
      const m = document.querySelector(el.getAttribute('data-menu'));
      return { open: m.classList.contains('on'), inside: m.contains(document.activeElement), item: document.activeElement && document.activeElement.classList.contains('menuitem') };
    });
    if (!s.open) fail.push('Enter did not open');
    else if (!s.inside || !s.item) fail.push('open but focus not on a row');
    if (s.open && s.inside) {
      const a = await t.evaluate(() => document.activeElement);
      await page.keyboard.press('ArrowDown');
      await page.waitForTimeout(10);
      const moved = await t.evaluate((el, a) => {
        const m = document.querySelector(el.getAttribute('data-menu'));
        const n = m.querySelectorAll('.menuitem:not(.disabled):not([disabled])').length;
        return n < 2 || document.activeElement !== a;
      }, a);
      if (!moved) fail.push('ArrowDown did not move');
    }
    await page.keyboard.press('Escape');
    await page.waitForTimeout(30);
    s = await t.evaluate((el) => {
      const m = document.querySelector(el.getAttribute('data-menu'));
      return { open: m.classList.contains('on'), back: document.activeElement === el };
    });
    if (s.open) fail.push('Escape did not close');
    else if (!s.back) fail.push('focus not returned to trigger');
    if (fail.length) r.menusBad.push({ sig: await t.evaluate((el) => el.tagName.toLowerCase() + '[' + el.getAttribute('data-menu') + ']'), fail });
    await frame.evaluate(() => document.querySelectorAll('.popover.pop.on').forEach((p) => p.classList.remove('on')));
  }

  if (WALK) {
    await frame.evaluate(() => { document.body.focus(); window.__hit = new Set(); });
    for (let i = 0; i < 400; i++) {
      await page.keyboard.press('Tab');
      const done = await page.evaluate(() => {
        const d = document.getElementById('f').contentDocument;
        const a = d.activeElement;
        if (!a || a === d.body) return false;
        const w = document.getElementById('f').contentWindow;
        if (w.__hit.has(a)) return true;
        w.__hit.add(a);
        return false;
      });
      if (done && i > 3) break;
    }
    r.walkMissed = await frame.evaluate(() => {
      const vis = (el) => el.offsetParent !== null || getComputedStyle(el).position === 'fixed';
      const out = [];
      document.querySelectorAll('[data-target],[data-menu]').forEach((el) => {
        if (!vis(el) || el.closest('.popover.pop:not(.on)')) return;
        if (!window.__hit.has(el)) out.push(el.tagName.toLowerCase() + '[' + (el.getAttribute('data-target') || el.getAttribute('data-menu')) + ']');
      });
      return out;
    });
  }
  return r;
}

const pw = loadPlaywright();
const browser = await pw.chromium.launch({ headless: true, executablePath: chrome() });
const page = await browser.newPage({ viewport: { width: 1300, height: 920 } });
/* Stamp every element that gets a click listener, in every frame, so the
   sweep can tell a page-private click target from a pointer cursor that is
   only decoration. */
await page.addInitScript(() => {
  const add = EventTarget.prototype.addEventListener;
  EventTarget.prototype.addEventListener = function (type, ...rest) {
    if (type === 'click' && this instanceof Element) this.__clk = (this.__clk || 0) + 1;
    return add.call(this, type, ...rest);
  };
});
await page.goto(BASE + '/shared/components/order.json');

const tot = { pages: 0, links: 0, linksBad: 0, rows: 0, rowsBad: 0, triggers: 0, triggersBad: 0, nav: 0, navBad: 0, menus: 0, menusBad: 0, pointer: 0, walkMissed: 0 };
const pointerKinds = {};
let failed = 0;
for (const id of pages) {
  let r;
  try { r = await auditPage(page, id); } catch (e) { console.log(`${id.padEnd(26)} ERROR ${e.message.split('\n')[0]}`); failed++; continue; }
  tot.pages++;
  for (const k of ['links', 'rows', 'triggers', 'nav', 'menus']) tot[k] += r[k];
  for (const k of ['linksBad', 'rowsBad', 'triggersBad', 'navBad', 'menusBad', 'walkMissed']) tot[k] += r[k].length;
  tot.pointer += r.pointer.length;
  for (const p of r.pointer) pointerKinds[p.sig] = (pointerKinds[p.sig] || 0) + 1;
  const bad = r.linksBad.length + r.rowsBad.length + r.triggersBad.length + r.navBad.length + r.menusBad.length + r.walkMissed.length;
  if (bad) failed++;
  const cell = (n, b) => (b ? `${n - b}/${n}` : `${n}`).padStart(7);
  console.log(`${id.padEnd(26)} links${cell(r.links, r.linksBad.length)}  rows${cell(r.rows, r.rowsBad.length)}  triggers${cell(r.triggers, r.triggersBad.length)}  enter${cell(r.nav, r.navBad.length)}  menus${cell(r.menus, r.menusBad.length)}${WALK ? '  missed ' + r.walkMissed.length : ''}${r.pointer.length ? '  (+' + r.pointer.length + ' private)' : ''}${bad ? '  ✗' : ''}`);
  if (VERBOSE || bad) {
    const show = (label, list, f) => { if (list.length) console.log(`    ${label}: ` + list.slice(0, 8).map(f).join(', ') + (list.length > 8 ? ` … +${list.length - 8}` : '')); };
    show('cannot focus', r.linksBad.concat(r.triggersBad), (x) => x.sig + (x.closedPop ? '(in closed menu)' : ''));
    show('rows without a key path', r.rowsBad, (x) => x.sig + ' "' + x.text + '"');
    show('Enter does not navigate', r.navBad, (x) => x.sig + (x.focused ? '' : ' (never focused)'));
    show('menu keys', r.menusBad, (x) => x.sig + ' ' + x.fail.join('+'));
    show('Tab never landed on', r.walkMissed, (x) => x);
    if (VERBOSE) show('private click handlers', r.pointer, (x) => x.sig);
  }
}
await browser.close();

console.log('');
console.log(`${tot.pages} pages · cross-links ${tot.links - tot.linksBad}/${tot.links} focusable, Enter navigates ${tot.nav - tot.navBad}/${tot.nav} · menu rows ${tot.rows - tot.rowsBad}/${tot.rows} keyboard-reachable · triggers ${tot.triggers - tot.triggersBad}/${tot.triggers} focusable, ${tot.menus - tot.menusBad}/${tot.menus} open/move/close by key${WALK ? ` · Tab walk missed ${tot.walkMissed}` : ''}`);
const pk = Object.entries(pointerKinds).sort((a, b) => b[1] - a[1]).slice(0, 12);
if (pk.length) console.log(`private pointer targets outside the shared vocabulary (informational): ${tot.pointer} · ` + pk.map(([k, v]) => `${k}×${v}`).join(', '));
if (failed) { console.log(`\nkeyboard reach: ${failed} page(s) with a click target the keyboard cannot use ✗`); process.exit(1); }
console.log('keyboard reach: everything a mouse can click, a keyboard can reach ✓');
