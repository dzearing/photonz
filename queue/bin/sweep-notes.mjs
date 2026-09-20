import { cutShortBecause } from './sweep-parse.mjs';

// The notes on the standing "walks that fail in the full sweep" task, split
// into the part a sweep owns and the part a person owns.
//
// Until 2026-09-13 a sweep rewrote the whole notes field. That field is the
// only place anyone writes down what each failing walk MEANS: a manager pass
// spent a slot working out that six of twelve failing walks already had their
// own task with their own diagnosis, wrote it into the notes, and the sweep
// four hours later replaced every word of it with a fresh list. The log kept
// the history, but nobody reads thirty log lines to find a triage.
//
// So the machine's part lives between two markers and a sweep only ever
// replaces what is between them. Everything below the end marker is a person's
// and is carried across untouched.
export const MACHINE_BEGIN = '>>> SWEEP RESULT (rewritten by every sweep; anything you write in here is lost)';
export const MACHINE_END = '<<< END SWEEP RESULT. Write below this line and a sweep will keep it.';

// The text a person owns: whatever sits below the end marker.
//
// Notes written before the markers existed still have to survive their first
// sweep, and there the machine's block is recognisable by how it was built: it
// opens with "Last sweep " and closes with the "Sweep asked for by:" paragraph.
// Anything after that paragraph was written by hand.
export function humanPart(notes) {
  const text = String(notes || '');
  const end = text.indexOf(MACHINE_END);
  if (end !== -1) return text.slice(end + MACHINE_END.length).replace(/^\n+/, '').trimEnd();
  if (!text.startsWith('Last sweep ')) return text.trim();   // nothing machine-made here
  const asked = text.lastIndexOf('\nSweep asked for by:');
  if (asked === -1) return '';
  const gap = text.indexOf('\n\n', asked + 1);
  return gap === -1 ? '' : text.slice(gap + 2).trimEnd();
}

// The walks the last sweep reported, read back out of the machine block, so
// this sweep can say which of them stopped failing instead of letting them
// vanish from a list nobody diffed.
export function previousFailures(notes) {
  const text = String(notes || '');
  const end = text.indexOf(MACHINE_END);
  const machine = end === -1 ? text : text.slice(0, end);
  const names = [];
  // Both lists a sweep can leave: what failed in the run, and what a locked
  // screen never let run and was failing before it. The second one exists so a
  // string of partial sweeps cannot quietly lose the list.
  for (const re of [/^Failing walks \(\d+\): (.+)$/m, /^Not run this time and still failing from the last check \(\d+\): (.+)$/m]) {
    const m = machine.match(re);
    if (m) names.push(...m[1].split(',').map((s) => s.trim()).filter(Boolean));
  }
  return [...new Set(names)];
}

// owners: { "<walk-name>": { ids: ["<task id>", ...], declared: true|false } }
// for failing walks that another open task already owns. The sweep's own list
// and the task's acceptance stop disagreeing about which walks this task is
// meant to fix, because the list itself says which ones belong to somebody
// else, and whether that task said so or was guessed at.
export function machineBlock(result, { previous = [], owners = {} } = {}) {
  const failed = result.failed || [];
  const list = failed.join(', ');
  const asked = result.requests?.map((r) => `${r.by}: ${r.why}`).join('; ') || 'a scheduled sweep';
  const minutes = Math.round((result.seconds || 0) / 60);
  const lines = [
    MACHINE_BEGIN,
    ``,
    // Three shapes a run can come back in, and a list of failures means a
    // different thing under each. A PARTIAL ran only the walks a locked screen
    // cannot touch, so its list is the failures in the part that ran and says so
    // in the same breath: half a set read as a whole set is how a green sweep
    // would come to mean nothing.
    result.partial
      ? `Last sweep ${result.ended} ran only the part of the walk set a locked screen cannot touch: ${result.walks} of ${result.total} walks ran in ${minutes} minutes, of which ${result.passed} passed. The other ${result.couldNotRun} were refused because the screen is locked, and those are unknown, not passing.`
        + (failed.length ? ` This list is the failures in the part that ran, not the state of the walk set.` : ``)
      : result.complete === false
        ? `Last sweep ${result.ended} DID NOT FINISH${cutShortBecause(result)}: it reached ${result.walks}${result.total ? ` of ${result.total}` : ''} walks in ${minutes} minutes, of which ${result.passed} passed. The walks it never reached are unknown, not passing.`
        : `Last sweep ${result.ended}: ${result.passed} of ${result.walks} walks passed in ${minutes} minutes.`,
    ``,
    // Nothing failing is a RESULT and gets written down like one. Until
    // 2026-09-18 a clean sweep wrote nothing at all, so this block kept the last
    // broken sweep's list under a heading promising every sweep rewrites it: on
    // 2026-09-18 it named four walks as broken that the sweep fifteen minutes
    // earlier had watched pass. What "nothing failing" is worth still depends on
    // how much of the set ran, so the sentence says which of the three it is.
    failed.length
      ? `Failing walks (${failed.length}): ${list}`
      : result.partial
        ? `Failing walks: none. Nothing failed in the part that ran, and the ${result.couldNotRun} walks the locked screen refused are unknown, not passing. This is not the walk set passing.`
        : result.complete === false
          ? `Failing walks: none. Nothing failed in what this run reached, and the walks it never reached are unknown, not passing. This is not the walk set passing.`
          : `Failing walks: none. Every walk in the set passed.`,
  ];

  // A run that was cut short took the probe app down with it, so the walk in
  // flight and the ones around it fail for the stop rather than for the app. On
  // 2026-09-18 a killed sweep's one failure, measure-chip-snap-walk, passed on
  // its own in 14s the next day. So a cut-short run's list is a list of
  // SUSPECTS and says so, and the next sweep that covers the set is what turns
  // a suspect into a break.
  //
  // It is its OWN line and never appended to the list above: previousFailures()
  // reads that line back and splits it on commas, so a sentence on the end of
  // it would come back as half a dozen walks with names like "so a walk failing
  // in its last moments may be a casualty of the stop rather than a break".
  if (result.complete === false && failed.length) {
    lines.push(
      ``,
      `Those ${failed.length} are UNCONFIRMED. This run was cut short, and a stop takes the probe app down with it,`,
      `so a walk failing in its last moments may be a casualty of the stop rather than a break.`,
      `Re-run one on its own with Scripts/playtest.sh before believing it; the next sweep that covers the set decides.`,
    );
  }

  // The walk that was RUNNING when the stop landed never answered at all. It is
  // neither a pass nor a failure and would otherwise just be missing from every
  // list here, which reads as a pass.
  if (result.unfinished) {
    lines.push(
      ``,
      `Never finished: ${result.unfinished} was still running when the run was stopped. It is not a pass and not a failure; nobody asked it anything.`,
    );
  }

  // A crash is in that list like any other failure and means something else
  // entirely: the app was GONE, so the open document went with it and no walk
  // after it proves anything. Say which ones and what they died in, above
  // everything else this block has to say.
  const crashed = result.crashed || [];
  if (crashed.length) {
    lines.push(
      ``,
      `The app DIED in ${crashed.length} of those, which is not a walk running slowly. Fix these first:`,
      ...crashed.map((c) => `  ${c.name}: ${c.why}`),
      `Crash reports: ~/Library/Logs/DiagnosticReports. Read one with`,
      `node Scripts/crash-report.mjs --file "<report>.ips".`,
    );
  }

  // A run that did not cover the set replaces a list that may have come from one
  // that did. The walks it never ran are not fixed and not failing: they are
  // unread, and dropping them would read as the app having healed overnight. So
  // they are carried across by name, under their own heading, and read back as
  // previous failures by the sweep after this one.
  //
  // This used to apply only to a sweep a locked screen cut down. A sweep stopped
  // on the clock has exactly the same hole and is the more dangerous of the two
  // now that a clean run writes a block at all: it reaches a hundred walks, none
  // of them fails, and without this the other four hundred silently stop being
  // failures.
  if (result.complete === false) {
    const ran = new Set(result.ranWalks || []);
    const carried = previous.filter((w) => !failed.includes(w) && !ran.has(w));
    if (carried.length) {
      lines.push(
        ``,
        `Not run this time and still failing from the last check (${carried.length}): ${carried.join(', ')}`,
        result.partial
          ? `Those walks look a control up by name, so the locked screen turned them away. They are unread, not fixed.`
          : result.interrupted
            ? `This run was interrupted before reaching them. They are unread, not fixed.`
            : `This run stopped before reaching them. They are unread, not fixed.`,
      );
    }
  }

  const ownedHere = failed.filter((w) => !owners[w]?.ids?.length);
  const ownedElsewhere = failed.filter((w) => owners[w]?.ids?.length);
  if (ownedElsewhere.length) {
    // A task that SAID it owns a walk and a task that merely mentioned the name
    // are worth very different amounts, and a line that reads the same for both
    // is how a real failure gets handed to somebody who was never working on
    // it. So each line says which it is.
    const guessed = ownedElsewhere.filter((w) => !owners[w].declared);
    lines.push(
      ``,
      `Already named by another open task, so read that one before re-diagnosing (${ownedElsewhere.length}):`,
      ...ownedElsewhere.map((w) => `  ${w} -> ${owners[w].ids.join(', ')}`
        + (owners[w].declared ? ` (that task says it owns this walk)` : ` (guessed from its wording, so read it before believing it)`)),
      ...(guessed.length
        ? [``, `${guessed.length} of those are guesses. A task stops being guessed at by naming its walks:`,
           `  node queue/bin/queue.mjs walks <task id> <walk> [<walk> ...]`,
           `  node queue/bin/queue.mjs walks <task id> --none      (it only mentions them in passing)`]
        : []),
      ``,
      ownedHere.length
        ? `This task owns the other ${ownedHere.length}: ${ownedHere.join(', ')}`
        : `That is every failing walk, so this task owns none of them right now.`,
    );
  }

  // A walk that passes this time has to be SAID to have stopped failing. Left
  // to just drop out of the list it reads as forgotten, and the next person to
  // open the task cannot tell a fix from an oversight. A sweep that was cut
  // short never reached some walks at all, so it is in no position to say.
  if (result.complete !== false) {
    const stopped = previous.filter((w) => !failed.includes(w));
    if (stopped.length) {
      lines.push(``, `Stopped failing since the last sweep (${stopped.length}): ${stopped.join(', ')}`);
    }
  }

  lines.push(
    ``,
    `Full output: ${result.log}. Re-run one of them on its own with`,
    `Scripts/playtest.sh Scripts/playtest/<name>.json --no-build, which takes about ten seconds.`,
    `Do NOT run Scripts/playtest-all.sh yourself; ask for a sweep with`,
    `queue/bin/sweep.sh request "<why>" and finish your task.`,
    ``,
    `Sweep asked for by: ${asked}`,
    ``,
    MACHINE_END,
  );
  return lines.join('\n');
}

// The whole notes field: this sweep's block, then whatever a person wrote.
export function mergeNotes(oldNotes, result, owners = {}) {
  const human = humanPart(oldNotes);
  const block = machineBlock(result, { previous: previousFailures(oldNotes), owners });
  return human ? `${block}\n\n${human}\n` : block;
}

// The name of a walk as the sweep knows it: "border-effect-walk", never
// "Scripts/playtest/border-effect-walk.json". Somebody declaring a walk reaches
// for the path they just ran, so both spellings are read as the same walk.
export function walkName(s) {
  return String(s || '').trim().replace(/^.*\//, '').replace(/\.json$/i, '').trim();
}

// The walks a task SAYS it owns, or null when it has not said anything.
//
// An empty list is a statement too, and an important one: a task ABOUT the walk
// machinery quotes walk names as examples, and without a way to say "I own none
// of these" it claims every walk it talks about. That is how this very task came
// out owning dock-picked-first-walk on 2026-09-14.
export function declaredWalks(task) {
  const raw = task && task.walks;
  if (raw == null) return null;
  const list = (Array.isArray(raw) ? raw : String(raw).split(',')).map(walkName).filter(Boolean);
  return [...new Set(list)];
}

// Which open tasks own each failing walk, asking the task first and reading its
// prose only as a fallback.
//
// Two rules, and they are the whole of it:
//   A task that declares its walks is TAKEN AT ITS WORD. Its prose is not read
//   at all, so naming a walk as an example no longer claims it.
//   For a walk somebody declared, the tasks that only mention it are dropped.
//   The guess is what you get when nobody has said, not a second opinion.
// A walk name is long and specific enough ("border-effect-walk") that a task
// mentioning it is usually about it, which is why the guess is worth keeping;
// it was also wrong often enough to be worth labelling. The standing task
// itself is skipped, and so is anything finished.
export function ownersOfWalks(failed, tasks, standingId) {
  const open = (tasks || []).filter((t) => t.id !== standingId && !['done', 'dropped'].includes(t.status));
  const said = open.map((t) => [t, declaredWalks(t)]);
  const owners = {};
  for (const name of failed) {
    const walk = walkName(name);
    const declared = said.filter(([, w]) => w && w.includes(walk)).map(([t]) => t.id);
    if (declared.length) { owners[name] = { ids: declared, declared: true }; continue; }
    const guessed = said
      .filter(([, w]) => w === null)
      .filter(([t]) => [t.title, t.goal, t.notes].concat(t.acceptance || []).filter(Boolean).join('\n').includes(walk))
      .map(([t]) => t.id);
    if (guessed.length) owners[name] = { ids: guessed, declared: false };
  }
  return owners;
}
