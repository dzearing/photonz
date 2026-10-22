#!/usr/bin/env node
// Drill: a whole-set walk run that is STOPPED picks up where it stopped.
//
// On 2026-10-22 the daily whole-set run reached 989 of 1011 walks in 306
// minutes and was put down because the user came back to the Mac. The next
// whole-set run was going to start again at walk one. This holds the fix
// (queue/bin/sweep-resume.mjs) honest in three parts:
//
//   1. the rules, pure: what the remainder is, when carrying on is sound and
//      when it is not (code landed, a run stopped on its clock, a lock, a set
//      that moved), and how two parts merge into one record;
//   2. the schedule: the remainder runs as soon as the Mac is free, inside the
//      once-a-day floor, and when code has landed it says why it is not
//      carrying on;
//   3. end to end, on a scratch queue with a stand-in walk runner: the REAL
//      sweep.sh runs the whole set and is stopped part way, the next
//      `sweep.sh run` hands the runner only the remainder, the merged record
//      reads complete, and the standing walk task the first run opened is
//      closed by it.
//
//   node queue/bin/sweep-resume-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, existsSync, rmSync, chmodSync } from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { remainderOf, resumable, mergeRuns } from './sweep-resume.mjs';
import { decide, walkNames } from './sweep-schedule.mjs';
import { sweepSentences } from './sweep-parse.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

// ---- 1. the rules ------------------------------------------------------------
console.log('what a stopped run left unanswered');
const SET = Array.from({ length: 12 }, (_, i) => `walk-${String(i).padStart(2, '0')}`);
const stopped = {
  began: '2026-10-22T11:15:14Z', ended: '2026-10-22T16:21:27Z', seconds: 18373,
  walks: 9, passed: 7, failed: ['walk-02', 'walk-08'], crashed: [],
  ranWalks: SET.slice(0, 9), refusedWalks: [], couldNotRun: 0, total: 12,
  requests: [{ t: '2026-10-22T10:00:00Z', by: 'some-task', why: 'x' }],
  log: 'queue/sweep/a.log', complete: false, interrupted: true, timedOut: false,
  unfinished: 'walk-09', screenLocked: false, partial: false, head: 'abc',
};
let rest = remainderOf(stopped, SET);
check('the walks it never reached are the remainder, the one in flight included',
  rest.unreached.join() === 'walk-09,walk-10,walk-11', rest.unreached);
check('the walks it saw fail are run again, because a stop takes the probe down with it',
  rest.rerun.join() === 'walk-02,walk-08', rest.rerun);
check('in the order of the set', rest.walks.join() === 'walk-02,walk-08,walk-09,walk-10,walk-11', rest.walks);

console.log('when carrying on is sound');
const ok = (o) => resumable({ record: stopped, set: SET, head: 'abc', ...o });
check('same commit: carry on', ok({}).ok === true, ok({}));
check('a later commit that changed nothing a walk runs: carry on',
  ok({ head: 'def', codeSince: false }).ok === true);
check('code landed since: the whole set, and it says why',
  ok({ head: 'def', codeSince: true }).ok === false
  && ok({ head: 'def', codeSince: true }).because === 'code'
  && /code has landed/.test(ok({ head: 'def', codeSince: true }).why), ok({ head: 'def', codeSince: true }));
check('not knowing whether code landed is not the same code',
  ok({ head: 'def', codeSince: null }).ok === false);
check('a run stopped on its own clock is a wedge, not a person, and is not carried on from',
  resumable({ record: { ...stopped, interrupted: false, timedOut: true }, set: SET, head: 'abc' }).ok === false);
check('a run that covered the set leaves nothing to carry on from',
  resumable({ record: { ...stopped, complete: true }, set: SET, head: 'abc' }).ok === false);
check('a set that grew is not carried on from',
  resumable({ record: stopped, set: [...SET, 'walk-new'], head: 'abc' }).because === 'set');
check('a locked screen waits for the unlock rather than refusing most of the remainder',
  ok({ screenLocked: true }).because === 'locked');
check('a carrying-on run that went blind on this code is not tried again',
  ok({ blind: { began: '2026-10-22T17:00:00Z', head: 'abc' } }).because === 'blind');
check('a record from before runs wrote down what they reached is not guessed at',
  resumable({ record: { ...stopped, ranWalks: undefined }, set: SET, head: 'abc' }).ok === false);

console.log('two parts, one run of the set');
const part2 = {
  began: '2026-10-22T18:00:00Z', ended: '2026-10-22T18:06:00Z', seconds: 360,
  walks: 5, passed: 4, failed: ['walk-02'], crashed: [],
  ranWalks: ['walk-02', 'walk-08', 'walk-09', 'walk-10', 'walk-11'], refusedWalks: [], couldNotRun: 0,
  requests: [{ t: '2026-10-22T10:00:00Z', by: 'some-task', why: 'x' }, { t: '2026-10-22T17:30:00Z', by: 'other', why: 'y' }],
  log: 'queue/sweep/b.log', complete: true, interrupted: false, timedOut: false, head: 'abc',
};
let m = mergeRuns(stopped, part2, SET);
check('every walk in the set has an answer, so it is complete', m.complete === true && m.walks === 12 && m.total === 12, m);
check('a failure it confirmed stays failing', m.failed.join() === 'walk-02', m.failed);
check('a failure that passed when run again is cleared', !m.failed.includes('walk-08'), m.failed);
check('the counts add up', m.passed === 11, m.passed);
check('it keeps the day\'s start, so finishing it is not a second run of the day', m.began === stopped.began, m.began);
check('and ends when the last part ended', m.ended === part2.ended);
check('it names the log of the part that finished it, which is how sweep.sh knows it was written',
  m.log === 'queue/sweep/b.log');
check('both parts are written down', m.parts.length === 2 && m.parts[0].walks === 9 && m.parts[1].walks === 5, m.parts);
check('the requests of both, once each', m.requests.length === 2, m.requests);
check('what this part did is kept apart for the loop\'s event',
  m.resumed.ran === 5 && m.resumed.seconds === 360 && m.resumed.reran === 2
  && m.resumed.cleared.join() === 'walk-08' && m.resumed.confirmed.join() === 'walk-02', m.resumed);
let said = sweepSentences({ ...m, ended: part2.ended }).join(' ');
check('its sentence says it came in parts, so five hours is not read as one sitting',
  /11\/12 walks passed/.test(said) && /over 2 parts/.test(said) && /stopped at 9 walks/.test(said), said);

// Stopped again, part way through the remainder: still one record, still not complete.
const part2Stopped = { ...part2, walks: 2, passed: 1, ranWalks: ['walk-02', 'walk-08'], failed: ['walk-02'],
  complete: false, interrupted: true, unfinished: 'walk-09' };
m = mergeRuns(stopped, part2Stopped, SET);
check('a carrying-on run that is itself stopped is NOT complete', m.complete === false && m.interrupted === true, m);
check('...and the walks still unanswered are still the remainder',
  remainderOf(m, SET).unreached.join() === 'walk-09,walk-10,walk-11', remainderOf(m, SET));
check('...and it can be carried on from again', resumable({ record: m, set: SET, head: 'abc' }).ok === true);
const m3 = mergeRuns(m, { ...part2, ranWalks: ['walk-02', 'walk-09', 'walk-10', 'walk-11'], walks: 4, passed: 4, failed: [] }, SET);
check('three parts make one complete run', m3.complete === true && m3.parts.length === 3 && m3.failed.length === 0, m3);

// A part whose list was finished but a walk in the set still has no answer
// anywhere (a walk that waited for the person and never ran) is not complete.
m = mergeRuns(stopped, { ...part2, ranWalks: ['walk-02', 'walk-08', 'walk-09', 'walk-10'], walks: 4 }, SET);
check('a walk with no answer anywhere keeps the merged run from reading complete',
  m.complete === false && m.walks === 11, m);

// ---- 2. the schedule ---------------------------------------------------------
console.log('the schedule');
const now = Date.parse('2026-10-22T17:00:00Z');   // 5.7h after the stopped run began
let d = decide({ now, latest: stopped, head: 'abc', codeSinceFull: false, set: SET });
check('inside the once-a-day floor, the rest of a stopped run is due straight away',
  d.run === 'full' && d.resume === true && d.walks === 5, d);
check('and it says what it is finishing', /stopped at 9 of 12/.test(d.why), d.why);
d = decide({ now, latest: stopped, head: 'def', codeSinceFull: true, codeSinceCheck: true,
  rotation: { lastHead: 'abc' }, set: SET });
check('with code landed, inside the floor: the rotating check, and the line says why the stopped run was not carried on',
  d.run === 'slice' && !d.resume && /code has landed since the last whole-set run was stopped/.test(d.why), d);
d = decide({ now: now + 24 * 3600e3, latest: stopped, head: 'def', codeSinceFull: true, set: SET });
check('with code landed, past the floor: the whole set, and it says why',
  d.run === 'full' && !d.resume && /stopped, so what it reached is about code that is gone/.test(d.why), d);
d = decide({ now, latest: m3, head: 'abc', codeSinceFull: false, set: SET });
check('once finished, nothing more runs on that code', d.run === 'nothing', d);
d = decide({ now, latest: stopped, head: 'abc', codeSinceFull: false });
check('a caller that does not give the set gets the old answer, never a guessed remainder', !d.resume, d);

// ---- 3. end to end -----------------------------------------------------------
console.log('end to end: the real sweep.sh, a stand-in walk runner, a scratch queue');
const locked = (() => {
  try { return /<true\/>/.test(execFileSync('sh', ['-c', 'ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked'], { encoding: 'utf8' })); }
  catch { return false; }
})();
const set = walkNames(REPO);
if (locked) {
  console.log('  skip end to end: the screen is locked, and a remainder waits for the unlock by design');
} else if (set.length < 50) {
  console.log('  skip end to end: fewer than fifty walks in this checkout');
} else {
  const box = mkdtempSync(join(tmpdir(), 'sweep-resume-'));
  const qdir = join(box, 'queue');
  for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(qdir, 'tasks', p), { recursive: true });
  mkdirSync(join(qdir, 'sweep'), { recursive: true });
  const sdir = join(qdir, 'sweep');
  writeFileSync(join(box, 'set.txt'), set.join('\n') + '\n');
  const HANG = set.length - Math.max(25, Math.floor(set.length / 10));
  const early = set[10];
  const casualty = set[HANG - 2];
  writeFileSync(join(box, 'fail-1.txt'), [early, casualty].join('\n') + '\n');
  writeFileSync(join(box, 'fail-2.txt'), '');

  // The stand-in: playtest-all.sh's lines and summary, in its exact shape, for
  // the list it is handed (or the whole set), with nothing launched. It writes
  // down what it was asked to run, and can be told to hang mid-walk the way a
  // real walk is in flight when the person comes back.
  const runner = join(box, 'stand-in.sh');
  writeFileSync(runner, `#!/bin/bash
LIST="$DRILL_SET"
[[ "\${1:-}" == "--only" ]] && LIST="$2"
echo "$*" > "$DRILL_BOX/args.$DRILL_PHASE"
grep -v '^$' "$LIST" > "$DRILL_BOX/ran.$DRILL_PHASE"
i=0; PASSED=0; FAILED=()
while IFS= read -r w; do
  [[ -z "$w" ]] && continue
  i=$((i+1))
  if [[ -n "\${DRILL_HANG_AT:-}" ]] && (( i == DRILL_HANG_AT )); then
    printf '%-40s' "$w"
    sleep 60 & SP=$!
    trap 'kill $SP 2>/dev/null; exit 143' TERM
    wait $SP; exit 0
  fi
  if grep -qxF "$w" "$DRILL_FAIL"; then printf '%-40s %3ds  FAILED  step 3 (expect): not there\\n' "$w" 1; FAILED+=("$w")
  else printf '%-40s %3ds  ok\\n' "$w" 0; PASSED=$((PASSED+1)); fi
done < "$LIST"
echo
echo "==> $PASSED passed, \${#FAILED[@]} failed"
(( \${#FAILED[@]} )) && printf '    %s\\n' "\${FAILED[@]}"
printf '==> %d walks in 0m 00s\\n' "$i"
(( \${#FAILED[@]} )) && exit 1
exit 0
`);
  chmodSync(runner, 0o755);
  const envFor = (phase, extra = {}) => ({
    ...process.env, PHOTONZ_QUEUE_DIR: qdir, PHOTONZ_SWEEP_RUNNER: runner,
    DRILL_BOX: box, DRILL_SET: join(box, 'set.txt'), DRILL_PHASE: phase,
    DRILL_FAIL: join(box, `fail-${phase}.txt`), ...extra,
  });
  const runSweep = (phase, extra, onLine) => new Promise((done) => {
    const child = spawn('queue/bin/sweep.sh', ['run'], { cwd: REPO, env: envFor(phase, extra) });
    let out = '';
    child.stdout.on('data', (b) => { out += b; if (onLine) onLine(child); });
    child.stderr.on('data', (b) => { out += b; });
    // A drill never outlives its own clock.
    const guard = setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 120000);
    child.on('exit', (code) => { clearTimeout(guard); done({ code, out }); });
  });
  const latest = () => JSON.parse(readFileSync(join(sdir, 'latest.json'), 'utf8'));
  const tasks = () => readdirSync(join(qdir, 'tasks')).flatMap((p) =>
    readdirSync(join(qdir, 'tasks', p)).filter((f) => f.endsWith('.json'))
      .map((f) => JSON.parse(readFileSync(join(qdir, 'tasks', p, f), 'utf8'))));
  const standing = () => tasks().filter((t) => t.standing === 'walk-sweep');

  // Part one: the whole set, stopped while walk HANG is in flight.
  const stopWhenStuck = () => {
    const iv = setInterval(() => {
      const logs = readdirSync(sdir).filter((f) => /^\d{4}-.*\.log$/.test(f));
      if (!logs.length) return;
      const text = readFileSync(join(sdir, logs.sort().pop()), 'utf8');
      if (text.split('\n').filter((l) => /\s(ok|FAILED)$|FAILED  /.test(l)).length >= HANG - 1) {
        clearInterval(iv);
        // A signal is the path a person coming back takes too: sweep.sh sets
        // INTERRUPTED and goes down the same stop.
        try { process.kill(sweepPid, 'SIGTERM'); } catch {}
      }
    }, 200);
    return iv;
  };
  let sweepPid = 0;
  const p1 = await new Promise((done) => {
    const child = spawn('queue/bin/sweep.sh', ['run'], { cwd: REPO, env: envFor('1', { DRILL_HANG_AT: String(HANG) }) });
    sweepPid = child.pid;
    const iv = stopWhenStuck();
    let out = '';
    child.stdout.on('data', (b) => { out += b; });
    child.stderr.on('data', (b) => { out += b; });
    const guard = setTimeout(() => { try { child.kill('SIGKILL'); } catch {} }, 120000);
    child.on('exit', (code) => { clearTimeout(guard); clearInterval(iv); done({ code, out }); });
  });
  check('part one: the whole set was handed to the runner', readFileSync(join(box, 'ran.1'), 'utf8').trim().split('\n').length === set.length);
  check('part one ends INTERRUPTED (exit 4)', p1.code === 4, { code: p1.code, tail: p1.out.slice(-600) });
  let L = latest();
  check(`part one is recorded as stopped at ${HANG - 1} of ${set.length}`,
    L.interrupted === true && L.complete === false && L.walks === HANG - 1 && L.total === set.length,
    { interrupted: L.interrupted, walks: L.walks, total: L.total });
  check('its two failures are written down, unconfirmed', L.failed.length === 2, L.failed);
  check('the standing walk task is opened with them', standing().length === 1
    && standing()[0].status === 'pending', standing().map((t) => t.status));
  const status1 = execFileSync('queue/bin/sweep.sh', ['why-not'], { cwd: REPO, env: envFor('x'), encoding: 'utf8' });
  check('the schedule now says the rest runs, and why', /^full: .*stopped at \d+ of \d+/.test(status1), status1);
  const what = execFileSync('queue/bin/sweep.sh', ['what'], { cwd: REPO, env: envFor('x'), encoding: 'utf8' }).trim();
  const want = set.length - (HANG - 1) + 2;
  check('and the loop\'s line names the remainder, not five hours', new RegExp(`rest of the stopped walk sweep \\(${want} of ${set.length}`).test(what), what);

  // Part two: the next run. Everything passes this time.
  const p2 = await runSweep('2', {});
  const ran2 = readFileSync(join(box, 'ran.2'), 'utf8').trim().split('\n');
  const args2 = readFileSync(join(box, 'args.2'), 'utf8').trim();
  check('part two hands the runner a list (--only), not the whole set', /^--only /.test(args2), args2);
  check(`part two runs only the remainder: ${want} walks`, ran2.length === want, ran2.length);
  check('...which is every walk part one never answered', set.slice(HANG - 1).every((w) => ran2.includes(w)));
  check('...plus the two it saw fail', ran2.includes(early) && ran2.includes(casualty));
  check('...and nothing part one already passed', !ran2.includes(set[0]) && !ran2.includes(set[HANG - 3]));
  check('part two exits 0', p2.code === 0, { code: p2.code, tail: p2.out.slice(-800) });
  L = latest();
  check('the merged record is ONE complete run of the set',
    L.complete === true && L.walks === set.length && L.passed === set.length && L.failed.length === 0 && L.parts.length === 2,
    { complete: L.complete, walks: L.walks, passed: L.passed, failed: L.failed, parts: (L.parts || []).length });
  check('...counted from the day\'s start, so the once-a-day floor is unchanged', L.began === L.parts[0].began);
  check('the run says it finished the set', /That is the whole set, on one code/.test(p2.out), p2.out.slice(-800));
  const t = standing()[0];
  check('the standing walk task reads the merged result and is closed by it',
    t && t.status === 'done' && /covered the whole set/.test((t.log || []).map((l) => l.note).join('\n')),
    t && { status: t.status, log: (t.log || []).slice(-2) });
  const summary = JSON.parse(execFileSync('queue/bin/sweep.sh', ['summary'], { cwd: REPO, env: envFor('x'), encoding: 'utf8' }));
  check('the loop\'s event carries this part\'s own walks, not the merged count',
    summary.walks === want && summary.resumed === true && summary.answered === set.length && summary.complete === true, summary);
  const after = execFileSync('queue/bin/sweep.sh', ['why-not'], { cwd: REPO, env: envFor('x'), encoding: 'utf8' });
  check('and with the set finished, nothing more is due on that code', /^nothing:/.test(after), after);
  check('no claim is left behind', !existsSync(join(sdir, '.claimed.json')));
  rmSync(box, { recursive: true, force: true });
}

console.log(failures ? `\n${failures} check(s) FAILED` : '\nall checks passed');
process.exit(failures ? 1 : 0);
