#!/usr/bin/env node
// Decision drill: prove that answering a decision card with "do not build this"
// really ends the work.
//
//   node queue/bin/decision-drill.mjs
//
// On 2026-09-02 the user answered the colour-sampling card with "Not now, ask
// again after the measure tools have been tried" at 15:10. At 19:45 the loop
// claimed that same task and started building it, because resolving a decision
// returned its task to the queue whatever the answer was. The guards below have
// to hold:
//
//   1. an option marked as a decline retires its task instead of re-queueing it
//   2. a retired task is not claimable, so no runner can pick it up later
//   3. the task history names the answer that retired it, in plain language
//   4. an approving answer re-queues the task exactly as it always did
//   5. a decline retires the task even when another decision is still open on it
//   6. a late answer never reopens or rewrites a task that already finished
//
// Runs against a throwaway queue; never touches the real one.
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const sandbox = mkdtempSync(join(tmpdir(), 'photonz-decision-'));
process.env.PHOTONZ_QUEUE_DIR = join(sandbox, 'queue');
const q = await import('./queue-lib.mjs');

let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (detail ? '\n          ' + detail : ''));
  if (!ok) failed++;
};
const notes = (t) => q.findTask(t).log.map((e) => e.note);
// The two shapes a card carries: one option that builds the thing, one that does not.
const BUILD = { id: 'build', label: 'Add a Color mode to Measure', summary: 'Sample colours off the picture.' };
const DECLINE = { id: 'later', label: 'Not now, ask again after the measure tools have been tried', summary: 'Leave it out.', declines: true };

try {
  // --- 1 + 2 + 3: the answer that means no -------------------------------
  const declined = q.addTask({ title: 'Point at a colour and its value joins the spec', priority: 'p1-high', notes: 'drill' });
  const dNo = q.addDecision({
    taskId: declined.id,
    question: 'Should the Measure tool read colours off the picture for the spec?',
    options: [BUILD, DECLINE],
    recommended: 'later',
  });
  q.setStatus(declined.id, 'blocked', 'waiting on the decision');
  q.resolveDecision(dNo.id, 'later', 'try the measure tools first');

  const after = q.findTask(declined.id);
  check('a declined answer retires its task', after.status === 'dropped', 'status is ' + after.status);
  check('a retired task is not ready to claim',
    !q.readyTasks().some((t) => t.id === declined.id),
    q.readyTasks().map((t) => t.id).join(', ') || 'nothing ready');
  const claimed = q.claimNext();
  check('nothing can claim it, even with the queue otherwise empty',
    !claimed || claimed.id !== declined.id, claimed ? 'claimed ' + claimed.id : 'nothing claimable');
  const said = notes(declined.id).find((n) => n.startsWith('retired by that answer'));
  check('the history says which answer retired it, in plain language',
    !!said && said.includes(DECLINE.label), said || notes(declined.id).join(' | '));
  check('the decline is recorded as a real event, not a silent edit',
    q.readHistory().some((e) => e.ev === 'task_dropped' && e.id === declined.id && e.decision === dNo.id));
  check('a retired task is never announced as unblocked',
    !q.readHistory().some((e) => e.ev === 'task_unblocked' && e.id === declined.id));

  // --- 4: the answer that means yes, unchanged ----------------------------
  const approved = q.addTask({ title: 'Two point measure', priority: 'p1-high', notes: 'drill' });
  const dYes = q.addDecision({
    taskId: approved.id,
    question: 'Should Measure read colours off the picture for the spec?',
    options: [BUILD, DECLINE],
    recommended: 'build',
  });
  q.setStatus(approved.id, 'blocked', 'waiting on the decision');
  q.resolveDecision(dYes.id, 'build');
  const back = q.findTask(approved.id);
  check('an approving answer puts the task back in the queue', back.status === 'pending', 'status is ' + back.status);
  check('and the answer is written into its history',
    notes(approved.id).some((n) => n.includes(BUILD.label)), notes(approved.id).join(' | '));
  check('and it is claimable again', q.readyTasks().some((t) => t.id === approved.id));
  check('an approved task is still announced as unblocked',
    q.readHistory().some((e) => e.ev === 'task_unblocked' && e.id === approved.id));

  // --- 5: a decline outranks any other blocker ----------------------------
  const twoWays = q.addTask({ title: 'Alignment checks', priority: 'p1-high', notes: 'drill' });
  const dA = q.addDecision({ taskId: twoWays.id, question: 'How should alignment checks work?', options: [BUILD, DECLINE], recommended: 'build' });
  const dB = q.addDecision({ taskId: twoWays.id, question: 'Should alignment checks be built at all?', options: [BUILD, DECLINE], recommended: 'later' });
  const held = q.findTask(twoWays.id);
  held.blockedBy = [dA.id, dB.id];
  held.status = 'blocked';
  q.saveTask(held);
  q.resolveDecision(dB.id, 'later');
  check('a decline retires the task even with another question still open',
    q.findTask(twoWays.id).status === 'dropped', 'status is ' + q.findTask(twoWays.id).status);

  // --- 6: a late answer leaves finished work alone ------------------------
  const finished = q.addTask({ title: 'Readout slide', priority: 'p1-high', notes: 'drill' });
  const dLate = q.addDecision({ taskId: finished.id, question: 'Should the readout slide?', options: [BUILD, DECLINE], recommended: 'build' });
  q.setStatus(finished.id, 'done', 'shipped');
  q.resolveDecision(dLate.id, 'later');
  check('a late decline does not retire work that already shipped',
    q.findTask(finished.id).status === 'done', 'status is ' + q.findTask(finished.id).status);

  const reopened = q.addTask({ title: 'Something already dropped', priority: 'p1-high', notes: 'drill' });
  const dDropped = q.addDecision({ taskId: reopened.id, question: 'Build this?', options: [BUILD, DECLINE], recommended: 'build' });
  q.setStatus(reopened.id, 'dropped', 'not worth doing');
  q.resolveDecision(dDropped.id, 'build');
  check('a late approval does not resurrect a task someone dropped on purpose',
    q.findTask(reopened.id).status === 'dropped', 'status is ' + q.findTask(reopened.id).status);
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n[decision-drill] ${failed} check(s) failed` : '\n[decision-drill] all checks passed');
process.exit(failed ? 1 : 0);
