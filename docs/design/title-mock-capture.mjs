#!/usr/bin/env node
// Photographs the title page mock (docs/design/mocks/pages/video-titles-apple.html)
// at exact moments, through headless Chrome's DevTools protocol, so the mock's
// frames can be laid beside the app's render of the same moments.
//
//   node docs/design/title-mock-capture.mjs --out <dir> [--ids a,b] [--frames] [--reel]
//
// --frames  per design: 0, 25%, 50%, 100% of the in, and the middle of the hold,
//           full size PNGs named <id>-<label>.png, plus contact-sheet.png
// --reel    every design played through at 30 fps, half size, into reel.mp4
//
// Needs the dashboard server on 127.0.0.1:8791 (it serves the mocks) and
// Google Chrome. Chrome is started with its own throwaway profile and is
// always killed before the script exits.
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const flag = n => args.includes(n);
const opt = n => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const OUT = opt('--out') || join(tmpdir(), 'tp-capture');
const BASE = opt('--base') || 'http://127.0.0.1:8791/pages/video-titles-apple.html';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
mkdirSync(OUT, { recursive: true });

const port = 9300 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), 'tp-chrome-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--window-size=1920,1080', '--hide-scrollbars', '--force-device-scale-factor=1',
  '--no-first-run', '--no-default-browser-check', 'about:blank',
], { stdio: 'ignore' });
const killChrome = () => { try { chrome.kill('SIGKILL'); } catch {} try { rmSync(profile, { recursive: true, force: true }); } catch {} };
process.on('exit', killChrome);
const watchdog = setTimeout(() => { console.error('capture: gave up after 9 minutes'); process.exit(2); }, 9 * 60 * 1000);

async function connect() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('Chrome did not open its debugging port');
}
const ws = new WebSocket(await connect());
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let seq = 0; const waiting = new Map(); const events = [];
ws.onmessage = m => {
  const msg = JSON.parse(m.data);
  if (msg.id && waiting.has(msg.id)) { const { res, rej } = waiting.get(msg.id); waiting.delete(msg.id); msg.error ? rej(new Error(msg.error.message)) : res(msg.result); }
  else if (msg.method) events.push(msg.method);
};
const send = (method, params = {}) => new Promise((res, rej) => { const id = ++seq; waiting.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
const evalJS = async expr => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result.value;

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: `${BASE}?shot=keynote-section&t=0` });
for (let i = 0; i < 100 && !events.includes('Page.loadEventFired'); i++) await new Promise(r => setTimeout(r, 100));
await evalJS('document.fonts.ready.then(() => true)');

const designs = await evalJS('window.tpDesigns.map(d => ({ id: d.id, name: d.name, inEnd: d.inEnd, outStart: d.outStart, outEnd: d.outEnd }))');
const only = opt('--ids') ? opt('--ids').split(',') : null;
const list = designs.filter(d => !only || only.includes(d.id));

async function shoot(id, t, file, scale = 1, format = 'png') {
  await evalJS(`window.tpSeek(${JSON.stringify(id)}, ${t}); new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))`);
  const shot = await send('Page.captureScreenshot', { format, quality: format === 'jpeg' ? 88 : undefined,
    clip: { x: 0, y: 0, width: 1920, height: 1080, scale } });
  writeFileSync(file, Buffer.from(shot.data, 'base64'));
}

if (flag('--frames')) {
  const sheet = join(OUT, 'sheet'); mkdirSync(sheet, { recursive: true });
  let n = 0;
  for (const d of list) {
    const moments = [['0', 0], ['25', d.inEnd * 0.25], ['50', d.inEnd * 0.5], ['100', d.inEnd], ['hold', d.inEnd + (d.outStart - d.inEnd) / 2]];
    for (const [label, t] of moments) {
      await shoot(d.id, t, join(OUT, `${d.id}-${label}.png`));
      await shoot(d.id, t, join(sheet, `f${String(n++).padStart(3, '0')}.png`), 0.2);
    }
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', join(sheet, 'f%03d.png'),
    '-vf', `pad=iw+8:ih+8:4:4:color=0x202022,tile=5x${list.length}`, '-frames:v', '1', join(OUT, 'contact-sheet.png')]);
  rmSync(sheet, { recursive: true, force: true });
  console.log(`frames: ${list.length * 5} in ${OUT}, contact-sheet.png`);
}

if (flag('--reel')) {
  const dir = join(OUT, 'reel'); mkdirSync(dir, { recursive: true });
  let n = 0;
  for (const d of list) {
    for (let t = 0; t <= d.outEnd + 300; t += 1000 / 30) await shoot(d.id, t, join(dir, `r${String(n++).padStart(5, '0')}.jpg`), 0.5, 'jpeg');
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', '30', '-i', join(dir, 'r%05d.jpg'),
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart', join(OUT, 'reel.mp4')]);
  rmSync(dir, { recursive: true, force: true });
  console.log(`reel: ${n} frames, ${(n / 30).toFixed(1)} s in ${join(OUT, 'reel.mp4')}`);
}

clearTimeout(watchdog);
ws.close();
killChrome();
process.exit(0);
