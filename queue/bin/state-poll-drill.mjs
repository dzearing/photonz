#!/usr/bin/env node
// Drill for the dashboard's four-second poll (queue-lib aggregateState).
//
// The dashboard asks for state every four seconds, forever, on the same machine
// that runs the loop and the app. It used to answer with every task's whole
// history, which was three megabytes a poll and got worse with every task ever
// filed. This drill holds the poll to what a LIST needs, and holds the two
// endpoints that make that possible honest: one task's own record, and search.
// Run it after touching aggregateState, taskRow, readTaskDetail, searchTasks,
// searchTaskRows or noteTask. The last three are also what the follow-up bar
// stands on (queue/bin/follow-up-bar.md): a runner that cannot find the task
// already covering its finding files a near-twin instead.
//
//   node queue/bin/state-poll-drill.mjs
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-state-poll-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
for (const p of ['p0-critical', 'p1-high', 'p2-normal', 'p3-low']) mkdirSync(join(dir, 'tasks', p), { recursive: true });
const put = (prio, t) => writeFileSync(join(dir, 'tasks', prio, t.id + '.json'), JSON.stringify(t));

const fatLog = (n) => Array.from({ length: n }, (_, i) => ({ t: '2026-09-0' + ((i % 8) + 1) + 'T10:00:00.000Z', note: 'log line ' + i + ' ' + 'x'.repeat(400) }));

put('p1-high', {
  id: 'a-real-task', title: 'A real task', status: 'in_progress', release: 'next', area: 'app',
  seq: 3, created: '2026-09-01T10:00:00.000Z', updated: '2026-09-07T10:00:00.000Z', started: '2026-09-02T10:00:00.000Z',
  goal: 'Plain language goal.', notes: 'working detail mentions parsnips',
  acceptance: ['first thing', 'second thing'], epic: 'unmanned-loop', deps: [], blockedBy: [],
  log: fatLog(12),
});
put('p2-normal', {
  id: 'a-done-task', title: 'A done task', status: 'done',
  created: '2026-09-01T10:00:00.000Z', updated: '2026-09-06T10:00:00.000Z',
  completed: new Date().toISOString(), goal: 'g', notes: 'n', acceptance: [], log: fatLog(3),
});
put('p3-low', { id: 'a-parked-task', title: 'A parked task', status: 'pending', parked: true, parkReason: 'waiting', created: '2026-09-01T10:00:00.000Z', log: [] });
// enough weight to notice a regression that puts the logs back on the poll
for (let i = 0; i < 200; i++) {
  put('p2-normal', { id: 'bulk-' + i, title: 'Bulk task ' + i, status: 'done', created: '2026-08-01T10:00:00.000Z', updated: '2026-08-02T10:00:00.000Z', completed: '2026-08-02T10:00:00.000Z', goal: 'g'.repeat(300), notes: 'n'.repeat(900), acceptance: ['a'.repeat(200)], log: fatLog(8) });
}

const lib = await import('../bin/queue-lib.mjs');
let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

console.log('the poll payload');
const withTasks = lib.aggregateState();
const withoutTasks = lib.aggregateState({ tasks: false });
const bigBytes = JSON.stringify(withTasks).length;
const smallBytes = JSON.stringify(withoutTasks).length;
check('203 tasks with fat logs still poll under 300KB with the list', bigBytes < 300000, bigBytes);
check('without the list the poll is a fraction of that', smallBytes < bigBytes / 3, { smallBytes, bigBytes });
check('leaving the list out drops the key entirely', !('tasks' in withoutTasks), Object.keys(withoutTasks));
check('the list is on by default, so the CLI still prints everything', withTasks.tasks.length === 203, withTasks.tasks.length);

console.log('what a row carries');
const row = withTasks.tasks.find((t) => t.id === 'a-real-task');
check('the row draws itself: title, status, priority, seq, dates, release',
  row.title === 'A real task' && row.status === 'in_progress' && row.priority === 'p1-high' &&
  row.seq === 3 && row.created && row.updated && row.release === 'next', row);
check('the heavy fields stay off the poll',
  !('log' in row) && !('notes' in row) && !('goal' in row) && !('acceptance' in row), Object.keys(row));
check('the row carries the last line of the log, not the log', row.lastNote.startsWith('log line 11'), row.lastNote.slice(0, 20));
check('a runner who wrote a paragraph does not put one on every row', row.lastNote.length <= 120, row.lastNote.length);
check('a parked task says so', withTasks.tasks.find((t) => t.id === 'a-parked-task').parked === true);
check('nothing leaks the file path', withTasks.tasks.every((t) => !('file' in t)));
check('counts still count every task', withTasks.counts.total === 203 && withTasks.counts.byStatus.done === 201, withTasks.counts);

console.log('the cards on Summary, which never get the list');
check('Up next rows are drawable on their own', withoutTasks.next.every((t) => t.title && t.priority && t.created), withoutTasks.next);
check('Completed rows carry their one line of history', withoutTasks.completed24h[0].lastNote !== undefined, withoutTasks.completed24h[0]);
check('audits is a count the page can compare, not a list of names', typeof withoutTasks.audits === 'number', withoutTasks.audits);
check('answered decisions are headers only', withoutTasks.decisions.resolved.every((d) => !('options' in d)));

console.log('one task, on demand');
const full = lib.readTaskDetail('a-real-task');
check('the record has everything the dialog draws', full.goal === 'Plain language goal.' && full.acceptance.length === 2 && full.log.length === 12 && full.notes.includes('parsnips'), Object.keys(full));
check('it knows its priority from the folder it was in', full.priority === 'p1-high', full.priority);
check('an unknown id is nothing, not a crash', lib.readTaskDetail('no-such-task') === null);
check('an id cannot walk out of the queue', lib.readTaskDetail('../../../etc/passwd') === null && lib.readTaskDetail('') === null);

console.log('search, which reads what the poll no longer carries');
check('a word that lives only in the working detail is found', lib.searchTasks('parsnips').join() === 'a-real-task', lib.searchTasks('parsnips'));
check('a word that lives only in the log is found', lib.searchTasks('log line 11').join() === 'a-real-task', lib.searchTasks('log line 11'));
check('a word in the checklist is found', lib.searchTasks('second thing').join() === 'a-real-task');
check('titles still match, and case does not matter', lib.searchTasks('A DONE TASK').join() === 'a-done-task');
check('an empty query matches nothing rather than everything', lib.searchTasks('   ').length === 0);
check('a word nobody wrote matches nothing', lib.searchTasks('zzzzz').length === 0);
// The words somebody would search are the words of the problem, which almost
// never sit next to each other in the record. Phrase first, then widen.
check('words in any order find the task when the phrase does not', lib.searchTasks('parsnips goal plain').join() === 'a-real-task', lib.searchTasks('parsnips goal plain'));
check('widening still needs every word', lib.searchTasks('parsnips zzzzz').length === 0);

console.log('search rows, and folding a finding into the task that already covers it');
const { rows: openRows } = lib.searchTaskRows('task');
check('the default is the OPEN queue only', openRows.every((r) => r.status !== 'done' && r.status !== 'dropped') && openRows.some((r) => r.id === 'a-real-task'), openRows.map((r) => r.id).slice(0, 5));
check('--all reads the finished ones too, for a regression', lib.searchTaskRows('A DONE TASK', { all: true }).rows.map((r) => r.id).join() === 'a-done-task');
check('an exact match says it is exact', lib.searchTaskRows('parsnips').mode === 'exact');
check('a widened match says so, so nobody reads coincidence as a hit', lib.searchTaskRows('parsnips plain goal').mode === 'widened', lib.searchTaskRows('parsnips plain goal').mode);
check('a row carries what decides whether it covers your finding', (() => { const r = openRows.find((x) => x.id === 'a-real-task'); return r && r.title === 'A real task' && r.priority === 'p1-high' && r.epic === 'unmanned-loop' && r.goal === 'Plain language goal.'; })());
check('rows come back in claim order, most urgent first', lib.PRIORITIES.indexOf(openRows[0].priority) <= lib.PRIORITIES.indexOf(openRows[openRows.length - 1].priority));
const noted = lib.noteTask('a-parked-task', 'also happens in the effects panel');
check('a folded finding lands in that task log and nothing else moves', noted.log[noted.log.length - 1].note === 'also happens in the effects panel' && noted.status === 'pending', noted.status);
check('the note is on disk, and search can read it back', lib.searchTasks('effects panel').join() === 'a-parked-task');
check('a near-twin with none of the same title words is still found', lib.similarTasks('parsnips in the plain language goal').some((r) => r.id === 'a-real-task'), lib.similarTasks('parsnips in the plain language goal'));
check('a title about something else is not a near-twin', lib.similarTasks('export an animated svg from the timeline').length === 0, lib.similarTasks('export an animated svg from the timeline'));
check('a near-twin check never offers a finished task to fold into', lib.similarTasks('a done task').every((r) => r.status !== 'done'));
let refused = false;
try { lib.noteTask('a-parked-task', '   '); } catch { refused = true; }
check('an empty note is refused rather than written', refused);
try { lib.noteTask('no-such-task', 'x'); refused = false; } catch { refused = true; }
check('a note to a task that does not exist is an error', refused);

rmSync(dir, { recursive: true, force: true });
console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
