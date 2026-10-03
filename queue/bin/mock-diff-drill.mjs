#!/usr/bin/env node
// Mock difference drill: prove an app task cannot be marked done while an
// audit it wrote lists a difference from the user's mock that names nothing
// that settles it, and that it can once the line names a card.
//
//   node queue/bin/mock-diff-drill.mjs
//
// On 2026-10-02 and 10-03 four audits in a row wrote differences from the mock
// into `rough` with a reason and no card or task, so the mocks were undercut
// quietly. The guards below have to hold:
//
//   1. `queue.mjs status <id> done` is refused when the audit the task wrote
//      lists a difference from a mock that names no card, task, dated answer
//      or written rule; the refusal names the audit line and what to add
//   2. the refusal leaves the task in progress and says why in its history
//   3. naming an open decision card in the line lets the same task through
//   4. an answered card, another task's id, the user's dated answer and a
//      written rule settle a line too; a withdrawn card and the task's own id
//      do not
//   5. lines that are not differences are not judged: no mock covers it, the
//      app goes further than the mock, it matches the mock, a long mock line
//      moved behind the question mark, a line that never mentions a mock
//   6. a line that matches in one sentence and departs in the next is judged
//   7. an audit named only in a task's notes (quoted as evidence) is not that
//      task's audit; one named in the closing note is
//   8. a task that is not app work is not judged, and the dashboard's own
//      status path is not gated
//
// Runs against a throwaway queue; MockDifferenceGateTests runs it as part of
// Scripts/test.sh.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, utimesSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const sandbox = mkdtempSync(join(tmpdir(), 'photonz-mockdiff-'));
process.env.PHOTONZ_QUEUE_DIR = join(sandbox, 'queue');
const q = await import('./queue-lib.mjs');
const md = await import('./mock-differences.mjs');

const audits = join(sandbox, 'queue', 'audits');
mkdirSync(audits, { recursive: true });
const audit = (name, rough, { old = false } = {}) => {
  const file = join(audits, name);
  writeFileSync(file, JSON.stringify({ feature: name, summary: 's', try: [{ do: 'a' }], evaluate: ['q'], rough }));
  // an audit from before the task was claimed
  if (old) { const then = new Date('2026-01-01T00:00:00Z'); utimesSync(file, then, then); }
};

let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (!ok && detail ? '\n          ' + detail : ''));
  if (!ok) failed++;
};
const cli = (...args) => {
  try {
    return { ok: true, out: execFileSync('node', [join(HERE, 'queue.mjs'), ...args], { env: process.env, encoding: 'utf8', stdio: 'pipe' }) };
  } catch (e) {
    return { ok: false, out: String(e.stderr || '') + String(e.stdout || '') };
  }
};
const task = (title, extra = {}) => {
  const t = q.addTask({ title, notes: 'drill', ...extra });
  q.setStatus(t.id, 'in_progress', 'claimed by drill');
  const claimed = q.findTask(t.id);
  claimed.started = new Date(Date.now() - 1000).toISOString();
  q.saveTask(claimed);
  return t.id;
};
const DIFF = "The mock's menu rows carry icons; these do not.";

try {
  // --- 1 + 2: an unsettled difference refuses done ------------------------
  const t1 = task('Audio effects on a picked sound');
  audit('2026-10-02-drill-effects.json', [DIFF, 'Every picture was taken with the Mac locked.']);
  const refused = cli('status', t1, 'done', 'shipped, audit queue/audits/2026-10-02-drill-effects.json');
  check('done is refused while the audit lists a difference from the mock naming nothing', !refused.ok, refused.out.trim());
  check('the refusal names the audit and the line', /2026-10-02-drill-effects\.json, rough line 1 \("The mock's menu rows carry icons; these do not\."\)/.test(refused.out), refused.out.trim());
  check('...and says what to add, in one sentence', /name the decision card or task that settles this difference in the line itself, or fix it and take the line out\./.test(refused.out), refused.out.trim());
  check('the line that is not about the mock is not named', !/rough line 2/.test(refused.out), refused.out.trim());
  check('the task stays in progress', q.findTask(t1).status === 'in_progress', q.findTask(t1).status);
  check('its history says why', q.findTask(t1).log.some((e) => /^not done yet: 2026-10-02-drill-effects\.json rough line 1/.test(e.note)));
  check('mock-check reads the same as the gate', /line 1  NAMES NOTHING/.test(cli('mock-check', t1).out));

  // --- 3: naming a card lets it through -------------------------------------
  const card = q.addDecision({ taskId: t1, question: 'Should the effects menu rows carry icons?', options: [{ id: 'a', label: 'Yes' }, { id: 'b', label: 'No' }], recommended: 'a' });
  audit('2026-10-02-drill-effects.json', [`${DIFF} Asked on ${card.id}.`, 'Every picture was taken with the Mac locked.']);
  check('mock-check now says the card settles it', new RegExp(`settled by card ${card.id}`).test(cli('mock-check', t1).out), cli('mock-check', t1).out);
  const accepted = cli('status', t1, 'done', 'shipped, audit queue/audits/2026-10-02-drill-effects.json');
  check('the same task is let through once the line names an open card', accepted.ok, accepted.out.trim());
  check('...and the task is done', q.findTask(t1).status === 'done');

  // --- 4: what settles a line, and what does not ----------------------------
  const other = q.addTask({ title: 'Menu rows carry icons', notes: 'drill' });
  const answered = q.addDecision({ taskId: other.id, question: 'Icons?', options: [{ id: 'a', label: 'Yes' }] });
  q.resolveDecision(answered.id, 'a');
  const gone = q.addDecision({ taskId: other.id, question: 'Icons again?', options: [{ id: 'a', label: 'Yes' }] });
  q.withdrawDecision(gone.id, 'a duplicate');
  const ctx = (ownId = '', userAsked = false) => ({
    card: (id) => { const d = q.readDecisions().find((x) => x.id === id); return !!d && d.status !== 'withdrawn'; },
    task: (id) => !!q.readTaskDetail(id),
    ownId, userAsked,
  });
  const settled = (line, c = ctx()) => md.settlementOf(line, c);
  check('an answered card settles a line', settled(`${DIFF} ${answered.id}`) === `card ${answered.id}`);
  check('another task settles a line', settled(`${DIFF} Filed as ${other.id}.`) === `task ${other.id}`);
  check("the user's dated answer settles a line", /2026-09-29/.test(settled(`${DIFF} Your call on 2026-09-29.`) || ''));
  check('a written rule settles a line', settled(`${DIFF} UX-PATTERNS §7 says the Mac's own rows win.`) === 'the rule in UX-PATTERNS §7');
  check('a withdrawn card does not', settled(`${DIFF} ${gone.id}`) === null);
  check("the task's own id does not", settled(`${DIFF} ${other.id}`, ctx(other.id)) === null);
  check('"filed as its own task" with no id does not', settled(`${DIFF} Filed as its own task.`) === null);
  check('"because you asked" settles a task the user filed', settled("The mock draws an x on the bar. It was replaced because you asked for the toggle.", ctx('', true)) !== null);
  check('...and not a task the loop filed', settled("The mock draws an x on the bar. It was replaced because you asked for the toggle.", ctx('', false)) === null);

  // --- 5 + 6: which lines are differences -----------------------------------
  const not = [
    'No mock covers scrubbing; this is behaviour only.',
    'There is no mock page for View mode; it was built from the task\'s words.',
    'The Strength buttons under the row go further than the mock, which draws rows with no settings under them.',
    'Our menu has a Custom row the mock does not draw, so Somewhere else comes after it.',
    'One curve covers both fades, as the mock draws it.',
    "The mock's line under the grid is longer than the panel's budget, so it moved, in the mock's words, behind the question mark beside Transitions.",
    'Every picture was taken with the Mac locked, so colours may read dimmed.',
  ];
  for (const line of not) check(`not a difference: ${line.slice(0, 60)}`, !md.isMockDifference(line));
  const are = [
    "The mock (pages/video-audio.html, #gEffects) draws Effects as its own dock group with a rail tab; here it is a section in the panel under Gain.",
    'This departs from video.html\'s timeline, which draws plain gradient bars at every zoom.',
    "Side by side with video.html PROPERTIES: names, size, colour and the 76pt column match. The mock's property rows show a number box alone; Appearance keeps a track beside the box.",
    "Menu rows are in macOS title case to match the menu beside them; the mock writes sentence case.",
  ];
  for (const line of are) check(`a difference: ${line.slice(0, 60)}`, md.isMockDifference(line));

  // --- 7: whose audit it is ---------------------------------------------------
  audit('2026-09-30-drill-quoted.json', [DIFF], { old: true });
  const quoting = task('A follow-up about an old audit', { notes: 'Evidence: queue/audits/2026-09-30-drill-quoted.json lists a difference.' });
  check('an old audit quoted in the notes is not judged', cli('status', quoting, 'done', 'shipped').ok);
  const claiming = task('A task closing with an old audit named');
  check('an audit named in the closing note is judged', !cli('status', claiming, 'done', 'shipped, audit queue/audits/2026-09-30-drill-quoted.json').ok);

  // --- 8: not app work, and the dashboard -----------------------------------
  const infra = task('A loop change');
  const it = q.findTask(infra); it.area = 'queue'; q.saveTask(it);
  check('a task that is not app work is not judged', cli('status', infra, 'done', 'shipped, audit 2026-09-30-drill-quoted.json').ok);
  const byHand = task('Marked done by the user');
  q.setStatus(byHand, 'done', 'set from dashboard, 2026-09-30-drill-quoted.json');
  check('the dashboard can still mark it done', q.findTask(byHand).status === 'done');
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
