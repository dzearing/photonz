#!/usr/bin/env node
// Formats a claude stream-json event stream into a readable live feed for the
// go-loop window: one line per tool action, assistant prose as prose. The raw
// JSON is NOT preserved here; go-loop tees this formatted output to loop.log.
import { createInterface } from 'node:readline';

const dim = (s) => `\x1b[2m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;
const cyan = (s) => `\x1b[36m${s}\x1b[0m`;
const clip = (s, n = 110) => {
  s = String(s || '').replace(/\s+/g, ' ').trim();
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
};

// one-line summary of a tool call's most telling input
function toolLine(name, input = {}) {
  const pick = input.command || input.file_path || input.path || input.pattern || input.url
    || input.prompt || input.description || input.query || '';
  return `  ${cyan('▸ ' + name)}  ${dim(clip(pick))}`;
}

const rl = createInterface({ input: process.stdin, terminal: false });
rl.on('line', (line) => {
  let ev;
  try { ev = JSON.parse(line); } catch { return; }
  try {
    if (ev.type === 'assistant') {
      for (const c of ev.message?.content || []) {
        if (c.type === 'tool_use') console.log(toolLine(c.name, c.input));
        else if (c.type === 'text' && c.text?.trim()) console.log(clip(c.text, 400));
      }
    } else if (ev.type === 'result') {
      console.log(bold(`■ runner finished (${ev.subtype || 'ok'})`) + (ev.result ? '\n' + clip(ev.result, 600) : ''));
    } else if (ev.type === 'system' && ev.subtype === 'init') {
      console.log(dim(`session ${clip(ev.session_id, 12)} started`));
    }
  } catch { /* never let formatting kill the pipe */ }
});
