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
  const m = machine.match(/^Failing walks \(\d+\): (.+)$/m);
  if (!m) return [];
  return m[1].split(',').map((s) => s.trim()).filter(Boolean);
}

// owners: { "<walk-name>": ["<task id>", ...] } for failing walks that another
// open task already owns. The sweep's own list and the task's acceptance stop
// disagreeing about which walks this task is meant to fix, because the list
// itself says which ones belong to somebody else.
export function machineBlock(result, { previous = [], owners = {} } = {}) {
  const failed = result.failed || [];
  const list = failed.join(', ');
  const asked = result.requests?.map((r) => `${r.by}: ${r.why}`).join('; ') || 'a scheduled sweep';
  const minutes = Math.round((result.seconds || 0) / 60);
  const lines = [
    MACHINE_BEGIN,
    ``,
    result.complete === false
      ? `Last sweep ${result.ended} DID NOT FINISH${result.timedOut ? ' (stopped on the clock)' : ''}: it reached ${result.walks} walks in ${minutes} minutes, of which ${result.passed} passed. The walks it never reached are unknown, not passing.`
      : `Last sweep ${result.ended}: ${result.passed} of ${result.walks} walks passed in ${minutes} minutes.`,
    ``,
    `Failing walks (${failed.length}): ${list}`,
  ];

  const ownedHere = failed.filter((w) => !owners[w]?.length);
  const ownedElsewhere = failed.filter((w) => owners[w]?.length);
  if (ownedElsewhere.length) {
    lines.push(
      ``,
      `Already named by another open task, so read that one before re-diagnosing (${ownedElsewhere.length}):`,
      ...ownedElsewhere.map((w) => `  ${w} -> ${owners[w].join(', ')}`),
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

// Which open tasks already name each failing walk. A walk name is long and
// specific enough ("border-effect-walk") that a task mentioning it anywhere is
// about it; the standing task itself is skipped, and so is anything finished.
export function ownersOfWalks(failed, tasks, standingId) {
  const owners = {};
  for (const walk of failed) {
    const hits = tasks
      .filter((t) => t.id !== standingId && !['done', 'dropped'].includes(t.status))
      .filter((t) => [t.title, t.goal, t.notes].concat(t.acceptance || []).filter(Boolean).join('\n').includes(walk))
      .map((t) => t.id);
    if (hits.length) owners[walk] = hits;
  }
  return owners;
}
