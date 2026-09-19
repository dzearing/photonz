#!/usr/bin/env node
// Drill for queue/bin/sweep-size.mjs: the walk sweep's size, worked out.
//
//   node queue/bin/sweep-size-drill.mjs
//
// The point of that file is that nobody types the number again, so the things
// worth drilling are the derivation (does it read what is really on disk, does
// one bad run move it), the cap arithmetic (does the stop still have room at
// this size and at twice it), and the check (does it actually go red when a
// document drifts, and does it go red when the sentence is deleted rather than
// quietly passing).
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  walkCount, perWalkSeconds, sweepSize, capSecondsFor, awakeSecondsFor,
  sizePhrase, multPhrase, checkQuotes, writeQuotes, QUOTERS, BUDGET_SECONDS_PER_WALK,
} from './sweep-size.mjs';

let bad = 0;
const check = (what, ok, detail) => {
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${what}`);
  if (!ok) { bad++; if (detail !== undefined) console.log('       ', JSON.stringify(detail)); }
};

// A repo with n walks on disk and the given sweep_pass events in its history.
function fakeRepo(n, runs, files = {}) {
  const root = mkdtempSync(join(tmpdir(), 'sweep-size-'));
  mkdirSync(join(root, 'Scripts', 'playtest', 'studies'), { recursive: true });
  mkdirSync(join(root, 'queue', 'bin'), { recursive: true });
  for (let i = 0; i < n; i++) writeFileSync(join(root, 'Scripts', 'playtest', `w${i}-walk.json`), '{}');
  // A study walk and a fixture must NOT be counted: playtest-all.sh globs the
  // top level only, so counting them would overstate every sweep.
  writeFileSync(join(root, 'Scripts', 'playtest', 'studies', 'a-study.json'), '{}');
  writeFileSync(join(root, 'Scripts', 'playtest', 'not-a-walk.txt'), 'x');
  writeFileSync(join(root, 'queue', 'history.jsonl'),
    runs.map((r) => JSON.stringify({ t: r.t || '2026-09-19T00:00:00Z', ev: 'sweep_pass', ...r })).join('\n') + '\n');
  for (const [rel, text] of Object.entries(files)) {
    mkdirSync(join(root, rel, '..'), { recursive: true });
    writeFileSync(join(root, rel), text);
  }
  return root;
}

// ---- 1. the count comes off disk -------------------------------------------
console.log('counting the walks');
let repo = fakeRepo(40, []);
check('it counts the walks playtest-all.sh would run', walkCount(repo) === 40, walkCount(repo));
check('a study walk is not one of them', walkCount(repo) !== 41);
rmSync(repo, { recursive: true, force: true });

console.log('the real repo');
check('the checked-in set is counted, and it is not the 322 the docs used to say',
  walkCount() > 400, walkCount());

// ---- 2. seconds a walk, from the recorded sweeps ----------------------------
console.log('what a walk costs');
// Ten honest runs at 12s a walk, with refusals priced in at 0.9s each.
const honest = (per, refused = 0, ran = 200) =>
  ({ walks: ran, seconds: Math.round(ran * per + refused * 0.9), couldNotRun: refused, total: ran + refused });
repo = fakeRepo(500, Array.from({ length: 10 }, () => honest(12)));
check('a set of even runs gives that cost back', Math.abs(perWalkSeconds(repo).seconds - 12) < 0.05, perWalkSeconds(repo));
rmSync(repo, { recursive: true, force: true });

// The refusals are subtracted. A partial sweep's raw seconds/walks would read
// far high, which is how a locked-screen run could have inflated the number
// everything else is written against.
repo = fakeRepo(500, Array.from({ length: 10 }, () => honest(12, 300)));
check('a locked run is not read as slow walks', Math.abs(perWalkSeconds(repo).seconds - 12) < 0.05, perWalkSeconds(repo));
rmSync(repo, { recursive: true, force: true });

// The one already in the real history: 519 walks in 361 seconds, which is the
// probe failing to build rather than a sweep.
repo = fakeRepo(500, [
  ...Array.from({ length: 9 }, () => honest(12)),
  { walks: 519, seconds: 361, couldNotRun: 11, total: 530 },
]);
check('a run that did not really run is thrown out', Math.abs(perWalkSeconds(repo).seconds - 12) < 0.05, perWalkSeconds(repo));
rmSync(repo, { recursive: true, force: true });

// One slow run must not drag the number: the median is why.
repo = fakeRepo(500, [...Array.from({ length: 9 }, () => honest(12)), honest(30)]);
check('one slow sweep does not move it', Math.abs(perWalkSeconds(repo).seconds - 12) < 0.05, perWalkSeconds(repo));
rmSync(repo, { recursive: true, force: true });

// A fresh checkout has no sweeps recorded. It must still answer.
repo = fakeRepo(500, []);
check('with no sweep ever recorded it still gives a number', perWalkSeconds(repo).seconds > 0, perWalkSeconds(repo));
check('...and says the number was not measured', perWalkSeconds(repo).measured === false);
rmSync(repo, { recursive: true, force: true });

// ---- 3. the cap has room ----------------------------------------------------
console.log('the wall-clock stop');
const size = sweepSize();
const good = size.walks * size.perWalkSeconds;
check('the cap is above a good full sweep of the set as it is today',
  size.capSeconds > good, { cap: size.capSeconds, good: Math.round(good) });
// The thing the task was filed for. 17 per cent was where the flat two hours
// had got to, and the next full sweep would have been cut off inside it.
check('...with at least half again in hand, not a rounding error',
  size.capSeconds / good >= 1.5, +(size.capSeconds / good).toFixed(2));
check('it still catches a probe that launches and never drives, well inside the run',
  size.capSeconds / 180 < size.walks / 4, { stoppedAfter: Math.round(size.capSeconds / 180), walks: size.walks });
check('it grows with the set, so 800 walks does not close it again',
  capSecondsFor(800) === 800 * BUDGET_SECONDS_PER_WALK, capSecondsFor(800));
check('a small checkout still gets two hours rather than two minutes',
  capSecondsFor(5) === 120 * 60, capSecondsFor(5));
check('the hold on the screen outlasts the cap, not just a good sweep',
  awakeSecondsFor(size.walks) > size.capSeconds, { awake: awakeSecondsFor(size.walks), cap: size.capSeconds });

// ---- 4. the check goes red when a document drifts ---------------------------
console.log('checking what the documents say');
const live = checkQuotes();
check('every place in the repo agrees right now', live.problems.length === 0, live.problems);
check('and there is more than one place, so this is really a cross-check', QUOTERS.length > 3, QUOTERS.length);

// A document stuck on the old number.
repo = fakeRepo(532, Array.from({ length: 10 }, () => honest(12)));
const fakeSize = sweepSize(repo);
check('the phrase reads as a person would write it',
  /^about \d+ walks and about \d+ minutes$/.test(sizePhrase(fakeSize)), sizePhrase(fakeSize));
check('the multiple against a runner ceiling is worked out too',
  multPhrase(fakeSize).endsWith('times the 600s ceiling'), multPhrase(fakeSize));
check('322 walks against a 532 set is outside the band', Math.abs(322 - fakeSize.walks) / fakeSize.walks * 100 > 10);
check('537 walks against a 532 set is inside it', Math.abs(537 - fakeSize.walks) / fakeSize.walks * 100 <= 10);
rmSync(repo, { recursive: true, force: true });

// Deleting the sentence must FAIL rather than pass quietly: that would be a
// silent way to switch the check off for a file.
console.log('a file that stops saying it');
const kept = readFileSync('CLAUDE.md', 'utf8');
try {
  writeFileSync('CLAUDE.md', kept.replace(/about \d+ walks and about \d+ minutes/, 'a while'));
  const gone = checkQuotes();
  check('a file that no longer says how big the sweep is fails the check',
    gone.problems.some((p) => p.file === 'CLAUDE.md' && /nothing in it says/.test(p.why)), gone.problems);
} finally {
  writeFileSync('CLAUDE.md', kept);
}
check('and the file is put back exactly as it was', readFileSync('CLAUDE.md', 'utf8') === kept);

// ---- 5. --write fixes it ----------------------------------------------------
console.log('putting it right');
const before = QUOTERS.map((f) => readFileSync(f, 'utf8'));
try {
  writeFileSync('queue/README.md', before[QUOTERS.indexOf('queue/README.md')]
    .replace(/about \d+ walks and about \d+ minutes/, 'about 322 walks and about 52 minutes'));
  check('the drift is seen', checkQuotes().problems.length === 1, checkQuotes().problems);
  writeQuotes();
  check('--write puts every place back in line', checkQuotes().problems.length === 0, checkQuotes().problems);
} finally {
  QUOTERS.forEach((f, i) => writeFileSync(f, before[i]));
}
check('nothing was left changed behind the drill',
  QUOTERS.every((f, i) => readFileSync(f, 'utf8') === before[i]));

console.log(bad ? `\n${bad} FAILED` : '\nall good');
process.exit(bad ? 1 : 0);
