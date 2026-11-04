#!/usr/bin/env node
// A REAL paste into real Chrome: not a process reading the clipboard the way
// Chrome might, but Chrome's own paste command on a real page, through the
// DevTools protocol. A throwaway profile, killed at the end.
// Each time the clipboard moves it waits the next delay, pastes, and writes
// one JSON line saying what the page was handed.
// Usage: real-paste-chrome.mjs <seconds> <delaysMs,comma> <expectedWidth> <out.jsonl>
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync, appendFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import readline from 'node:readline'

const [seconds, delaysArg, widthArg, out] = process.argv.slice(2)
const delays = delaysArg.split(',').map(Number)
const expected = Number(widthArg)
const port = 9400 + (process.pid % 200)
const profile = mkdtempSync(join(tmpdir(), 'paste-chrome-'))
const page = join(profile, 'paste.html')
writeFileSync(page, `<!doctype html><title>paste</title><div id=box contenteditable style="min-height:200px"></div><script>
window.results=[];
box.addEventListener('paste', async e => {
  const d=e.clipboardData, r={types:[...d.types], items:[...d.items].map(i=>i.kind+':'+i.type), files:[...d.files].map(f=>({name:f.name,type:f.type,size:f.size}))};
  const f=d.files[0]; window.results.push(r);
  if(f){ try{ const b=await createImageBitmap(f); r.width=b.width; r.height=b.height }catch(err){ r.error=String(err) } }
  r.done=true;
});
box.focus();
</script>`)
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  [`--user-data-dir=${profile}`, `--remote-debugging-port=${port}`, '--no-first-run',
   '--no-default-browser-check', '--window-size=500,400', `file://${page}`], { stdio: 'ignore' })
const watch = spawn('/tmp/copy-timing/clipwatch', [seconds], { stdio: ['ignore', 'pipe', 'ignore'] })
const stop = () => { watch.kill(); chrome.kill(); setTimeout(() => { try { rmSync(profile, { recursive: true, force: true }) } catch {} process.exit(0) }, 800) }
setTimeout(stop, Number(seconds) * 1000 + 3000)
process.on('SIGTERM', stop)

const sleep = ms => new Promise(r => setTimeout(r, ms))
let target
for (let i = 0; i < 100 && !target; i++) {
  await sleep(200)
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === 'page') } catch {}
}
if (!target) { console.error('Chrome did not open its debug port'); stop() }
const ws = new WebSocket(target.webSocketDebuggerUrl)
await new Promise(r => ws.addEventListener('open', r))
let id = 0; const waiting = new Map()
ws.addEventListener('message', m => { const d = JSON.parse(m.data); if (waiting.has(d.id)) { waiting.get(d.id)(d.result ?? d); waiting.delete(d.id) } })
const send = (method, params = {}) => new Promise(r => { const n = ++id; waiting.set(n, r); ws.send(JSON.stringify({ id: n, method, params })) })
await send('Emulation.setFocusEmulationEnabled', { enabled: true })
const ev = async expression => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.value
const paste = async () => {
  const key = { key: 'v', code: 'KeyV', windowsVirtualKeyCode: 86, modifiers: 4 }
  await send('Input.dispatchKeyEvent', { type: 'keyDown', ...key, commands: ['paste'] })
  await send('Input.dispatchKeyEvent', { type: 'keyUp', ...key })
}
console.error('ready')
let n = 0, busy = false
readline.createInterface({ input: watch.stdout }).on('line', async line => {
  if (busy) return
  busy = true
  const seen = Number(line.split(' ')[1]); const delay = delays[n++ % delays.length]
  await sleep(delay)
  const before = await ev('window.results.length')
  const asked = Date.now()
  await ev('box.focus()'); await paste()
  let r
  for (let i = 0; i < 100; i++) { await sleep(50); r = await ev(`(()=>{const r=window.results[${before}];return r&&r.done?r:null})()`); if (r) break }
  const outcome = !r ? 'no paste event' : r.width === expected ? 'new' : r.files.length ? 'wrong or bad file' : r.items.length ? 'no picture' : 'empty'
  appendFileSync(out, JSON.stringify({ n, seen, delayMs: delay, waitedMs: Date.now() - asked, outcome, ...r }) + '\n')
  await ev('box.innerHTML=""')
  busy = false
})
