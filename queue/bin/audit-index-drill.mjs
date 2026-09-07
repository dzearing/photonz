#!/usr/bin/env node
// Drill for the Ready to try index (queue-lib auditIndex).
//
// The dashboard's Ready to try surface draws three hundred cards from ONE
// request, so the index it is built from has to be right about four things that
// are easy to get quietly wrong: the day comes from the file NAME, the order is
// newest first, a half-written report must not take the page down, and the
// cache has to notice a report arriving. Run this after touching audits in
// queue-lib.mjs.
//
//   node queue/bin/audit-index-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-audit-index-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
mkdirSync(join(dir, 'audits'), { recursive: true });
const write = (name, obj) => writeFileSync(join(dir, 'audits', name), typeof obj === 'string' ? obj : JSON.stringify(obj));

write('2026-08-01-old-thing.json', { feature: 'An old thing', epic: 'measure-redline', summary: 'It was old.', try: [{ do: 'a' }] });
write('2026-09-05-new-thing.json', { feature: 'A new thing', epic: 'ui-layout', summary: 'It is new.', try: [{ do: 'a' }, { do: 'b' }], evaluate: ['q'], rough: ['r'] });
write('2026-09-03-bare.json', {});                      // every field missing
write('2026-09-04-broken.json', '{ not json');          // half written
write('notes.txt', 'ignored');                          // not a report

const lib = await import('../bin/queue-lib.mjs');
let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

console.log('audit index');
let rows = lib.auditIndex();
check('the unreadable report is skipped, the rest survive it', rows.length === 3, rows.length);
check('newest first, by file name', rows.map((r) => r.name).join(),
  '2026-09-05-new-thing.json,2026-09-03-bare.json,2026-08-01-old-thing.json');
check('the day comes from the file name', rows[0].date === '2026-09-05', rows[0].date);
check('a card gets its feature, summary and epic', rows[0].feature === 'A new thing' && rows[0].summary === 'It is new.' && rows[0].epic === 'ui-layout', rows[0]);
check('counts are ready for the card meta', rows[0].steps === 2 && rows[0].questions === 1 && rows[0].rough === 1, rows[0]);
const bare = rows[1];
check('a report with no feature falls back to its slug, undated', bare.feature === 'bare', bare.feature);
check('a report with nothing in it still counts zero steps', bare.steps === 0 && bare.epic === '' && bare.summary === '', bare);

console.log('cache');
check('a second call returns the same rows object', lib.auditIndex() === rows);
write('2026-09-06-newest.json', { feature: 'Newest', epic: 'ui-building', summary: 's', try: [] });
rows = lib.auditIndex();
check('a report arriving invalidates the cache', rows.length === 4 && rows[0].name === '2026-09-06-newest.json', rows.map((r) => r.name));

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
