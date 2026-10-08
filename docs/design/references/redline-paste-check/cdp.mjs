// node cdp.mjs <port> <pageUrl> : pastes into #plain then #rich, prints records
const [port, url] = process.argv.slice(2);
const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50; i++) { try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); break; } catch { await sleep(200); } }
let page = targets.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let id = 0; const pending = new Map();
ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } };
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await send('Page.enable');
await send('Page.navigate', { url });
await sleep(1500);
await send('Page.bringToFront');
await send('Emulation.setFocusEmulationEnabled', { enabled: true });
for (const box of ['plain', 'rich']) {
  await send('Runtime.evaluate', { expression: `document.getElementById('${box}').focus()` });
  await sleep(200);
  const r = await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'v', code: 'KeyV', windowsVirtualKeyCode: 86, modifiers: 4, commands: ['paste'] });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'v', code: 'KeyV', windowsVirtualKeyCode: 86, modifiers: 4 });
  if (r.error) console.error('key error', r.error);
  await sleep(800);
}
const out = await send('Runtime.evaluate', { expression: 'JSON.stringify(window.records, null, 2)', returnByValue: true });
console.log(out.result.result.value);
const shot = await send('Page.captureScreenshot', { format: 'png' });
if (shot.result) (await import('fs')).writeFileSync(process.env.SHOT || 'paste-check.png', Buffer.from(shot.result.data, 'base64'));
ws.close();
