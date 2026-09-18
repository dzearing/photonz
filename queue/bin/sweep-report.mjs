#!/usr/bin/env node
// Writes what a walk sweep found onto ONE standing task, whatever it found.
//
// EVERY sweep is written down, not only a failing one. Until 2026-09-18 a clean
// sweep printed "nothing failing" and stopped, so the standing task kept the
// last broken sweep's list under a heading promising every sweep rewrites it:
// on 2026-09-18 it named four walks as broken that the sweep fifteen minutes
// earlier had watched pass, and every runner and the dashboard read that.
// A clean sweep now updates the block with its own numbers and its own date,
// names the walks that stopped failing, and when it covered the WHOLE set it
// closes the standing task. It never opens one.
//
// The sweep runs whenever a runner asks for it, and the same walks tend to
// fail several sweeps in a row. Filing a fresh task each time would bury the
// queue in near-duplicates (queue-lib's addTask does not dedupe; it appends
// -2, -3 to the id), so the first failing sweep files the task and every
// later one appends its result to that task's log and refreshes its notes for
// as long as the task is still open.
//
// "Refreshes" and not "rewrites": the notes are also where a person writes
// down what each failing walk MEANS, and until 2026-09-13 a sweep replaced all
// of that with a fresh list. The sweep now owns only the block between the two
// markers in sweep-notes.mjs and carries everything below them across.
//
//   queue/bin/sweep-report.mjs queue/sweep/latest.json
import { readFileSync } from 'node:fs';
import * as q from './queue-lib.mjs';
import { mergeNotes, previousFailures, ownersOfWalks } from './sweep-notes.mjs';

const TITLE = 'Walks that fail in the full sweep';

// The standing task is found by a MARK it carries, not by its title.
//
// It used to be found by title, and the daily triage pass renames tasks so a
// title names an outcome: on 2026-09-17 it renamed this one to "Every walk in
// the sweep either passes or is corrected". The sweep three hours later could
// not see it, filed a second standing task beside it, and the triage of four
// failing walks stayed on a task no sweep was writing to any more. A mark
// survives a rename; a title does not.
const STANDING = 'walk-sweep';

const result = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const failed = result.failed || [];

// A run that got through no walks at all is not news, it is a run that did not
// happen: the screen was locked and every walk in the set was refused. Writing
// its row of zeroes over the block would throw away the last real answer.
if (!result.walks) {
  console.log('==> No walk ran, so there is nothing to write down.');
  process.exit(0);
}

const list = failed.join(', ');
const all = q.readAllTasks();
const live = all.filter((t) => !['done', 'dropped'].includes(t.status));
// The oldest marked task wins: it is the one carrying the triage history, and
// with two open at once the newer is the duplicate a rename already caused.
const byAge = (a, b) => String(a.created || '').localeCompare(String(b.created || ''));
const open = live.filter((t) => t.standing === STANDING).sort(byAge)[0]
  // Nothing marked yet: adopt the task the old title-matching sweep would have
  // found, and mark it below so the next rename cannot orphan it either.
  || live.filter((t) => t.title === TITLE).sort(byAge)[0];

// A clean sweep says so on the standing task; it never OPENS one. Filing a task
// to announce that nothing is wrong is how a green queue grows a red row.
if (!open && !failed.length) {
  console.log('==> Nothing failing, and no standing task is open, so there is nothing to update.');
  process.exit(0);
}

// Which failures already belong to another open task, so the list itself says
// which walks this task is actually meant to fix.
const owners = ownersOfWalks(failed, all, open?.id);

if (open) {
  const stopped = result.complete === false
    ? []
    : previousFailures(open.notes).filter((w) => !failed.includes(w));
  const tail = stopped.length ? `; stopped failing: ${stopped.join(', ')}` : '';
  // "249 of 249 walks passed" is true and reads as the whole set, so a run that
  // did not cover the set counts itself against the set instead.
  const cleanly = result.partial
    ? `nothing failing in the ${result.walks} of ${result.total} walks that ran`
    : result.complete === false
      ? `nothing failing in the ${result.walks} walks it reached before it stopped`
      : `nothing failing, all ${result.passed} walks passed`;
  q.appendLog(open, failed.length
    ? `sweep ${result.ended}: ${failed.length} failing (${list})${tail}`
    : `sweep ${result.ended}: ${cleanly}${tail}`);
  q.saveTask({ ...open, standing: STANDING, notes: mergeNotes(open.notes, result, owners) });
  if (failed.length) {
    console.log(`==> Updated the standing task ${open.id} with ${failed.length} failing walk(s).`);
  } else if (result.complete === false) {
    // Nothing failed, but most of the set never ran. The block says so and the
    // task stays open: a part of the set coming back clean is not the set
    // coming back clean, and the walks nobody ran are still unread.
    console.log(`==> Updated the standing task ${open.id}: nothing failing in the part that ran. Left open; the set was not covered.`);
  } else if (open.status !== 'pending') {
    // Somebody is on it, or it is waiting on a question. Closing a task out
    // from under whoever holds it would have them finishing work on a task that
    // is already done, and would strand any card opened against it. The block
    // says nothing is failing; they can close it themselves.
    console.log(`==> Nothing failing across the whole set, but the standing task ${open.id} is ${open.status}, so it is left alone.`);
  } else {
    // The whole set ran and every walk passed, so the task's own acceptance is
    // met and there is nothing on it to do. Left open it would cost a runner a
    // cycle of the focus to claim it, find nothing, and close it by hand; and a
    // pending task whose notes say nothing is failing is a dashboard row that
    // contradicts itself. A later failing sweep files a fresh standing task.
    q.setStatus(open.id, 'done',
      `the sweep that covered the whole set on ${result.ended} found nothing failing: ${result.passed} of ${result.walks} walks passed. `
      + `Closing this; the next sweep that finds a failure files a standing task again.`);
    console.log(`==> Nothing failing across the whole set. Closed the standing task ${open.id}.`);
  }
} else {
  const task = q.addTask({
    title: TITLE,
    goal:
      'The scripted walks are the app driving itself, and some of them no longer reach what they were written to check. ' +
      'Find out what each failing walk is looking for, then either fix the app if the walk is right or update the walk if the app moved on. ' +
      'This serves the focus because the sweep is the only thing that tells a focus runner whether the change it just made broke anything: ' +
      'a sweep with failures nobody has named cannot say that, so every focus feature ships on a weaker claim than it should.',
    epic: 'unmanned-loop',
    priority: 'p2-normal',
    area: 'queue',
    acceptance: [
      'Every walk the sweep block names as this task\'s own either passes or is rewritten to match what the app does now',
      'Each one is run on its own and passes twice in a row',
      'Any walk that was wrong rather than broken says so in this task log',
    ],
    notes: mergeNotes('', result, owners),
    source: 'sweep',
  });
  q.saveTask({ ...task, standing: STANDING });
  console.log(`==> Filed ${task.id} for ${failed.length} failing walk(s).`);
}
