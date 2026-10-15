#!/usr/bin/env node
// Drill for where a newly filed task joins the line (queue-lib draftTask,
// focusSeq, servesFocus).
//
// Until 2026-10-15 every new task went to the very end of its priority, so a
// follow-up for the video work in focus waited behind every icon and redline
// task the last triage had lined up: overnight on 10-15 the loop built five of
// those while four video follow-ups filed the afternoon before sat at seq 4010
// to 4050. This proves the rule that replaced it: a task for the focus epic, or
// any epic under it, goes after the last open focus task (and the last of the
// user's own asks) at the head of its priority and before the first open task
// of any other epic, in the order it was filed; every other task still goes to
// the end. It runs against a throwaway queue and never touches the real one.
//
//   node queue/bin/focus-seq-drill.mjs
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dir = mkdtempSync(join(tmpdir(), 'photonz-focus-seq-'));
process.env.PHOTONZ_QUEUE_DIR = dir;
const q = await import('./queue-lib.mjs');

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

try {
  writeFileSync(join(dir, 'objectives.json'), JSON.stringify({
    focus: 'video',
    epics: [
      { id: 'video', title: 'Video', stage: 'now', children: [
        { id: 'video-cutting', title: 'Cutting', stage: 'now', children: [
          { id: 'video-blade', title: 'Blade', stage: 'now' },
        ] },
      ] },
      { id: 'icons', title: 'Icons', stage: 'now', children: [{ id: 'icon-grid', title: 'Grid', stage: 'now' }] },
      { id: 'loop', title: 'Loop', stage: 'now' },
    ],
  }));

  console.log('which epics serve the focus');
  check('the focus itself', q.servesFocus('video'));
  check('a child of the focus', q.servesFocus('video-cutting'));
  check('a grandchild of the focus', q.servesFocus('video-blade'));
  check('another epic does not', !q.servesFocus('icons') && !q.servesFocus('icon-grid'));
  check('no epic does not', !q.servesFocus('') && !q.servesFocus(undefined));

  console.log('a priority holding focus and icon tasks');
  const P = 'p2-normal';
  const add = (title, epic, extra = {}) => q.addTask({ title, epic, priority: P, ...extra });
  const v1 = add('First video follow-up here', 'video');
  const i1 = add('First icon task here', 'icon-grid');
  const i2 = add('Second icon task here', 'icons');
  const l1 = add('A loop task at the end', 'loop');
  check('the line starts as filed', [v1.seq, i1.seq, i2.seq, l1.seq].join() === '10,20,30,40', [v1.seq, i1.seq, i2.seq, l1.seq]);

  const v2 = add('Second video follow-up here', 'video-cutting');
  check('a focus task goes after the last focus task and before the first icon task', v2.seq > v1.seq && v2.seq < i1.seq, v2.seq);
  const v3 = add('Third video follow-up here', 'video-blade');
  check('the next focus task goes after it, in the order filed', v3.seq > v2.seq && v3.seq < i1.seq, v3.seq);
  const i3 = add('Third icon task here', 'icon-grid');
  check('a task for another epic still goes to the end', i3.seq > l1.seq, i3.seq);
  const none = add('A task naming no epic', '');
  check('a task naming no epic still goes to the end', none.seq > i3.seq, none.seq);

  const order = q.readAllTasks().filter((t) => t.priority === P).sort((a, b) => a.seq - b.seq).map((t) => t.id);
  check('the claim order is focus first, in filing order, then the rest as filed',
    order.join() === [v1, v2, v3, i1, i2, l1, i3, none].map((t) => t.id).join(), order);

  console.log('what the head of the line is made of');
  q.setStatus(v1.id, 'done', 'finished');
  q.setStatus(v2.id, 'done', 'finished');
  q.setStatus(v3.id, 'done', 'finished');
  const v4 = add('Fourth video follow-up here', 'video');
  check('with no open focus task it goes just ahead of the first other task', v4.seq < i1.seq && v4.seq > 0, v4.seq);

  const P1 = 'p1-high';
  const u1 = q.addTask({ title: 'The user asked for this icon fix', epic: 'icon-grid', priority: P1, source: 'user' });
  const r1 = q.addTask({ title: 'A runner icon follow-up', epic: 'icon-grid', priority: P1 });
  const v5 = q.addTask({ title: 'A video follow-up at p1', epic: 'video', priority: P1 });
  check("a focus task never jumps ahead of the user's own ask", v5.seq > u1.seq && v5.seq < r1.seq, [u1.seq, v5.seq, r1.seq]);

  const blocked = add('A blocked icon task waits', 'icons', { seq: 1 });
  q.setStatus(blocked.id, 'blocked', 'waiting on a card');
  const v6 = add('Fifth video follow-up here', 'video');
  check('a blocked task of another epic still counts as part of the line', v6.seq < blocked.seq, [blocked.seq, v6.seq]);

  const pinned = add('A focus task with a seq given', 'video', { seq: 999 });
  check('a seq given by hand is kept', pinned.seq === 999, pinned.seq);

  console.log('the pure rule');
  const t = (seq, focus, status = 'pending') => ({ seq, status, focus });
  const head = (x) => x.focus;
  check('an empty priority starts at 10', q.focusSeq([], head) === 10, q.focusSeq([], head));
  check('only focus tasks: the end', q.focusSeq([t(10, true), t(20, true)], head) === 30, q.focusSeq([t(10, true), t(20, true)], head));
  check('a done task of another epic is not in the line', q.focusSeq([t(10, true), t(20, false, 'done'), t(30, true)], head) === 40);
  check('halfway between the head and the rest', q.focusSeq([t(10, true), t(20, false)], head) === 15, q.focusSeq([t(10, true), t(20, false)], head));
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
