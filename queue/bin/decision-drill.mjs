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
//   7. an answer that lands while the runner is still working is kept, and the
//      task is never left waiting on a question that is already settled
//   8. a task with a question genuinely still open is still blocked
//   9. the guard sweep repairs anything already stranded that way
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

  // --- 7: the answer that arrived while the runner was still working ------
  // The live incident of 2026-09-02: answered at 15:24:11, the runner wrote
  // `blocked` at 15:24:36, and the task sat waiting on a settled question with
  // nothing that could ever hand it back.
  const raced = q.addTask({ title: 'The tool bar groups its tools', priority: 'p1-high', notes: 'drill' });
  const dRace = q.addDecision({ taskId: raced.id, question: 'Which order should the families take?', options: [BUILD, DECLINE], recommended: 'build' });
  q.setStatus(raced.id, 'in_progress', 'claimed by go loop');
  q.resolveDecision(dRace.id, 'build');           // the user answers first
  q.setStatus(raced.id, 'blocked', 'waiting on the decision');  // the runner catches up
  const settled = q.findTask(raced.id);
  check('an answer that lands first is kept, and the task is not left waiting',
    settled.status === 'pending', 'status is ' + settled.status);
  check('and the task is claimable again', q.readyTasks().some((t) => t.id === raced.id));
  check('and its history names the answer, not just the block',
    notes(raced.id).some((n) => n.includes(BUILD.label) && n.includes('back in the queue')),
    notes(raced.id).join(' | '));

  const racedNo = q.addTask({ title: 'Colour sampling', priority: 'p1-high', notes: 'drill' });
  const dRaceNo = q.addDecision({ taskId: racedNo.id, question: 'Build colour sampling?', options: [BUILD, DECLINE], recommended: 'later' });
  q.setStatus(racedNo.id, 'in_progress', 'claimed by go loop');
  q.resolveDecision(dRaceNo.id, 'later');
  q.setStatus(racedNo.id, 'blocked', 'waiting on the decision');
  check('a no that lands first stays a no, and the block does not revive it',
    q.findTask(racedNo.id).status === 'dropped', 'status is ' + q.findTask(racedNo.id).status);
  check('and nothing can claim it', !q.readyTasks().some((t) => t.id === racedNo.id));

  // --- 8: a real open question still blocks, exactly as before ------------
  const waiting = q.addTask({ title: 'Alignment checks order', priority: 'p1-high', notes: 'drill' });
  const dOpen = q.addDecision({ taskId: waiting.id, question: 'Which alignment order?', options: [BUILD, DECLINE], recommended: 'build' });
  q.setStatus(waiting.id, 'blocked', 'waiting on the decision');
  check('a task with a question still open is still blocked',
    q.findTask(waiting.id).status === 'blocked', 'status is ' + q.findTask(waiting.id).status);
  check('and nothing sweeps it back while the question is open',
    (q.guardStuck().unblocked || []).indexOf(waiting.id) === -1);
  q.resolveDecision(dOpen.id, 'build');
  check('and answering it normally still returns it to the queue',
    q.findTask(waiting.id).status === 'pending', 'status is ' + q.findTask(waiting.id).status);

  // --- 9: the sweep repairs anything already stranded ---------------------
  // Written straight to disk, the way a task stranded by an older build looks.
  const strandedYes = q.addTask({ title: 'Stranded by an older build', priority: 'p1-high', notes: 'drill' });
  const dOld = q.addDecision({ taskId: strandedYes.id, question: 'Build it?', options: [BUILD, DECLINE], recommended: 'build' });
  q.resolveDecision(dOld.id, 'build');
  const strandedYesT = q.findTask(strandedYes.id);
  strandedYesT.status = 'blocked';
  q.saveTask(strandedYesT);

  const strandedNo = q.addTask({ title: 'Stranded after a no', priority: 'p1-high', notes: 'drill' });
  const dOldNo = q.addDecision({ taskId: strandedNo.id, question: 'Build it?', options: [BUILD, DECLINE], recommended: 'later' });
  q.resolveDecision(dOldNo.id, 'later');
  const strandedNoT = q.findTask(strandedNo.id);
  strandedNoT.status = 'blocked';
  q.saveTask(strandedNoT);

  const swept = q.guardStuck();
  check('the sweep returns a stranded task to the queue',
    q.findTask(strandedYes.id).status === 'pending' && swept.unblocked.includes(strandedYes.id),
    'status is ' + q.findTask(strandedYes.id).status);
  check('the sweep retires a stranded task whose answer was no',
    q.findTask(strandedNo.id).status === 'dropped' && swept.retired.includes(strandedNo.id),
    'status is ' + q.findTask(strandedNo.id).status);

  // Two questions, both answered: the history quotes the answer that came last.
  const twoAnswers = q.addTask({ title: 'Asked twice', priority: 'p1-high', notes: 'drill' });
  const dFirst = q.addDecision({ taskId: twoAnswers.id, question: 'Which order?', options: [BUILD, { ...BUILD, id: 'other', label: 'The other order' }], recommended: 'build' });
  const dSecond = q.addDecision({ taskId: twoAnswers.id, question: 'And the recent slot?', options: [BUILD, { ...BUILD, id: 'other', label: 'The other order' }], recommended: 'build' });
  q.setStatus(twoAnswers.id, 'in_progress', 'claimed by go loop');
  q.resolveDecision(dFirst.id, 'other');
  q.resolveDecision(dSecond.id, 'build');
  q.setStatus(twoAnswers.id, 'blocked', 'waiting on the decisions');
  check('with two answers in, the history quotes the one that came last',
    notes(twoAnswers.id).some((n) => n.includes('back in the queue') && n.includes(BUILD.label)),
    notes(twoAnswers.id).filter((n) => n.includes('back in the queue')).join(' | ') || 'no reconcile note');

  // A parked task is blocked for a different reason and is not the sweep's business.
  const parked = q.addTask({ title: 'Parked, and also once asked about', priority: 'p1-high', notes: 'drill' });
  const dParked = q.addDecision({ taskId: parked.id, question: 'Build it?', options: [BUILD, DECLINE], recommended: 'build' });
  q.resolveDecision(dParked.id, 'build');
  const parkedT = q.findTask(parked.id);
  parkedT.status = 'blocked'; parkedT.parked = true; parkedT.parkReason = 'runners keep failing on it';
  q.saveTask(parkedT);
  check('the sweep leaves a parked task parked',
    !(q.guardStuck().unblocked || []).includes(parked.id) && q.findTask(parked.id).parked === true,
    'status is ' + q.findTask(parked.id).status);

  // --- 10: blocking with no card at all is still blocked, and says so -----
  const noCard = q.addTask({ title: 'Blocked on nothing', priority: 'p1-high', notes: 'drill' });
  q.setStatus(noCard.id, 'blocked', 'waiting on something');
  check('blocking a task with no decision card still blocks it',
    q.findTask(noCard.id).status === 'blocked', 'status is ' + q.findTask(noCard.id).status);
  check('and the history warns that nothing will ever return it',
    notes(noCard.id).some((n) => n.includes('no decision card was opened')), notes(noCard.id).join(' | '));
  check('and the sweep leaves it alone rather than guessing',
    !(q.guardStuck().unblocked || []).includes(noCard.id));
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n[decision-drill] ${failed} check(s) failed` : '\n[decision-drill] all checks passed');
process.exit(failed ? 1 : 0);
