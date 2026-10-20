#!/usr/bin/env node
// The gate on new decision cards (`decisionRefusal`, queue-lib.mjs): at most
// three wait on the user, and each one shows a marked picture of the thing it
// asks about. Run: node queue/bin/decision-gate-drill.mjs
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { decisionRefusal, MAX_OPEN_DECISIONS } from './queue-lib.mjs';

const dir = mkdtempSync(join(tmpdir(), 'decision-gate-'));
writeFileSync(join(dir, 'marked.png'), '');
let bad = 0;
const check = (what, refusal, wantRefused) => {
  const ok = wantRefused ? !!refusal : refusal === null;
  if (!ok) { bad++; console.log(`FAIL ${what}: ${refusal ?? 'allowed'}`); }
};
check('a card with a picture and room is allowed', decisionRefusal({ shot: 'marked.png', pending: 0, auditsDir: dir }), false);
check('no picture is refused', decisionRefusal({ shot: '', pending: 0, auditsDir: dir }), true);
check('a picture that is not there is refused', decisionRefusal({ shot: 'gone.png', pending: 0, auditsDir: dir }), true);
check('a path instead of a name is refused', decisionRefusal({ shot: '../x.png', pending: 0, auditsDir: dir }), true);
check('an option picture that is not there is refused',
  decisionRefusal({ shot: 'marked.png', options: [{ id: 'a', shot: 'nope.png' }], pending: 0, auditsDir: dir }), true);
check(`${MAX_OPEN_DECISIONS} waiting refuses the next`, decisionRefusal({ shot: 'marked.png', pending: MAX_OPEN_DECISIONS, auditsDir: dir }), true);
check(`${MAX_OPEN_DECISIONS - 1} waiting still allows one`, decisionRefusal({ shot: 'marked.png', pending: MAX_OPEN_DECISIONS - 1, auditsDir: dir }), false);
console.log(bad ? `${bad} failed` : 'all good');
process.exit(bad ? 1 : 0);
