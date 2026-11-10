#!/usr/bin/env node
// Drill for queue/bin/ci-main.mjs: a red main is said out loud.
//
//   node queue/bin/ci-main-drill.mjs
//
// Fixtures only, no GitHub: the runs below are the shape `gh run list` gives,
// modelled on main's week of 2026-11-03 to 11-10 (most runs cancelled by the
// next push, every finished one failing at one step of one job).
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readRuns, ciLine, ciBrief, failingWhere, refresh, readCiMain } from './ci-main.mjs';

let bad = 0;
const check = (what, ok, detail) => {
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${what}`);
  if (!ok) { bad++; if (detail !== undefined) console.log('       ', JSON.stringify(detail)); }
};

const at = Date.parse('2026-11-10T16:00:00Z');
const H = 3600000;
const iso = (hAgo) => new Date(at - hAgo * H).toISOString();
let n = 1000;
const run = (hAgo, conclusion, status = 'completed') => ({
  databaseId: n++, conclusion, status, headSha: `abc${n}def0123`, createdAt: iso(hAgo), updatedAt: iso(hAgo - 0.2),
  displayTitle: `commit ${n}`, url: `https://example.invalid/runs/${n}`,
});
const sizeStepFails = [
  { name: 'Test slice 1 of 3', conclusion: 'success', steps: [{ name: 'Run tests', conclusion: 'success' }] },
  { name: 'Build app bundle (arm64)', conclusion: 'failure', steps: [
    { name: 'Toolchain', conclusion: 'success' },
    { name: "The sweep's size is the size it really is", conclusion: 'failure' },
    { name: 'Build release app bundle', conclusion: 'skipped' },
  ] },
];

console.log('the week main was red');
// Newest first, as gh lists them: one still running, cancelled runs between,
// failures back to a green run a week ago.
const week = [
  run(0.1, '', 'in_progress'),
  run(0.5, 'cancelled'),
  run(2, 'failure'),
  run(3, 'cancelled'),
  run(30, 'failure'),
  run(100, 'failure'),
  run(170, 'success'),
  run(200, 'failure'),
];
let s = readRuns(week, sizeStepFails, at);
check('it is red', s.red === true);
check('a run still going is not the answer', s.run.id === week[2].databaseId, s.run);
check('nor is a run the next push cancelled', s.run.conclusion === 'failure');
check('it names the job and the step that failed, and only that step',
  failingWhere(s) === 'Build app bundle (arm64), at the step "The sweep\'s size is the size it really is"', failingWhere(s));
check('it counts the failed runs since the last green one, not before it', s.redRuns === 3, s.redRuns);
check('red since the first failure after green', s.redSince === week[5].createdAt, s.redSince);
check('and knows when it was last green', s.lastGreen && s.lastGreen.at === week[6].updatedAt, s.lastGreen);
const line = ciLine(s, at);
check('the line says main is failing and where', /^main's checks are failing: Build app bundle \(arm64\), at the step/.test(line), line);
check('...and for how long', /red for 4 days \(3 failed runs\)/.test(line), line);
const brief = ciBrief(s, at);
check('the runner brief leads with it', brief.startsWith('## Main is red right now'), brief.slice(0, 60));
check('...names the run and how to see why', brief.includes(week[2].url) && brief.includes(`gh run view ${week[2].databaseId} --log-failed`));
check('...and tells the runner what to do about it', /part of your task/.test(brief) && /queue\.mjs search/.test(brief));

console.log('no green run in reach');
s = readRuns(week.slice(0, 6), sizeStepFails, at);
check('it says "at least" rather than inventing a start', s.redSinceIsFloor === true && /red for at least/.test(ciLine(s, at)), ciLine(s, at));

console.log('green');
s = readRuns([run(0.2, 'cancelled'), run(1, 'success'), run(5, 'failure')], [], at);
check('a green last run is not red', s.red === false);
check('and has nothing to say on the dashboard, the banner or the runner', ciLine(s, at) === '' && ciBrief(s, at) === '');

console.log('nothing finished yet');
s = readRuns([run(0.1, '', 'in_progress'), run(1, 'cancelled')], [], at);
check('only cancelled and running runs: not red, nothing said', s.red === false && s.run === null && ciLine(s, at) === '');

console.log('timed out counts as red');
s = readRuns([run(1, 'timed_out')], [{ name: 'Test slice 2 of 3', conclusion: 'timed_out', steps: [{ name: 'Run tests', conclusion: 'timed_out' }] }], at);
check('a run that timed out is red and names its step', s.red && /Test slice 2 of 3, at the step "Run tests"/.test(ciLine(s, at)), ciLine(s, at));

console.log('reading GitHub, with a stand-in for gh');
const dir = mkdtempSync(join(tmpdir(), 'ci-main-'));
const file = join(dir, 'ci-main.json');
try {
  let calls = 0;
  const fake = (args) => { calls++; return JSON.stringify(args[1] === 'list' ? week : { jobs: sizeStepFails }); };
  s = refresh({ force: true, at, file, run: fake });
  check('refresh lists the runs and reads the failing run\'s jobs', calls === 2 && s.red, { calls });
  check('and writes what it read', readCiMain(file).run.id === week[2].databaseId);
  calls = 0;
  refresh({ at: at + 60000, file, run: fake });
  check('inside three minutes it does not ask GitHub again', calls === 0, { calls });
  calls = 0;
  refresh({ force: true, at: at + 60000, file, run: fake });
  check('the same failed run\'s jobs are not fetched twice', calls === 1, { calls });
  const down = () => { const e = new Error('HTTP 502: Server Error'); throw e; };
  s = refresh({ force: true, at: at + 120000, file, run: down });
  check('GitHub down: the last reading is kept, still red', s.red === true && s.run.id === week[2].databaseId);
  check('...and the error is written beside it', /502/.test(JSON.parse(readFileSync(file, 'utf8')).error || ''));
  rmSync(file);
  s = refresh({ force: true, at, file, run: down });
  check('GitHub down with nothing read before: never said to be red', s.red === false && ciLine(s, at) === '');
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log(bad ? `\n${bad} FAILED` : '\nall good');
process.exit(bad ? 1 : 0);
