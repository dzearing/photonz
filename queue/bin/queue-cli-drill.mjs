#!/usr/bin/env node
// Queue CLI drill: prove two slips at the queue command can no longer quietly
// change the queue.
//
//   node queue/bin/queue-cli-drill.mjs
//
// Between 2026-09-23 and 09-26 nine stray tasks titled "x" were filed by
// runners trying out `addjson` (one of them with `--dry-run`, which was
// ignored), and on 2026-09-23 `status <id>` with no status word wrote
// `undefined` into a finished task, which then vanished from the dashboard.
// This drill runs the real CLI, the way a runner does, against a throwaway
// queue; it never touches the real one.
import { mkdtempSync, rmSync, readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const CLI = join(dirname(fileURLToPath(import.meta.url)), 'queue.mjs');
const sandbox = mkdtempSync(join(tmpdir(), 'photonz-queue-cli-'));
const QUEUE = join(sandbox, 'queue');
const env = { ...process.env, PHOTONZ_QUEUE_DIR: QUEUE };
delete env.GO_LOOP_PID;

const run = (...args) => {
  const r = spawnSync(process.execPath, [CLI, ...args], { env, encoding: 'utf8' });
  return { code: r.status, out: r.stdout, err: r.stderr };
};
const taskFiles = () => {
  const dir = join(QUEUE, 'tasks');
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((p) => readdirSync(join(dir, p)).filter((f) => f.endsWith('.json')).map((f) => join(dir, p, f)));
};
const readTask = (id) => JSON.parse(readFileSync(taskFiles().find((f) => f.endsWith(`/${id}.json`)), 'utf8'));
const history = () => existsSync(join(QUEUE, 'history.jsonl'))
  ? readFileSync(join(QUEUE, 'history.jsonl'), 'utf8').trim().split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];

let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (!ok && detail ? '\n          ' + detail : ''));
  if (!ok) failed++;
};

try {
  // --- filing ------------------------------------------------------------
  let r = run('addjson', JSON.stringify({ title: 'A dry run files nothing at all', goal: 'g', acceptance: ['a'] }), '--dry-run');
  check('addjson --dry-run exits 0', r.code === 0, r.err);
  check('addjson --dry-run writes no task', taskFiles().length === 0, taskFiles().join(', '));
  check('addjson --dry-run says it filed nothing', /dry run/i.test(r.out) && /nothing (was )?filed|not filed/i.test(r.out), r.out);
  check('addjson --dry-run shows the title it would file', r.out.includes('A dry run files nothing at all'), r.out);
  check('addjson --dry-run leaves no history event', history().length === 0, JSON.stringify(history()));

  r = run('add', 'A dry run files nothing here either', 'p2-normal', '--dry-run');
  check('add --dry-run writes no task', r.code === 0 && taskFiles().length === 0, r.out + r.err);

  r = run('addjson', JSON.stringify({ title: 'x' }));
  check('a one-word title is refused', r.code !== 0 && taskFiles().length === 0, r.out + r.err);
  check('the refusal says why', /three words/i.test(r.err), r.err);

  r = run('add', 'two words');
  check('add refuses a two-word title too', r.code !== 0 && taskFiles().length === 0, r.out + r.err);

  r = run('addjson', JSON.stringify({ title: 'A title long enough' }), '--dyr-run');
  check('an unknown flag is refused rather than ignored', r.code !== 0 && taskFiles().length === 0, r.out + r.err);

  r = run('addjson', JSON.stringify({ title: 'A real task to check' }));
  const id = r.out.trim();
  check('a real filing still works', r.code === 0 && id === 'a-real-task-to-check' && taskFiles().length === 1, r.out + r.err);

  // --- status --------------------------------------------------------------
  run('status', id, 'done', 'finished it');
  const before = readTask(id);
  const eventsBefore = history().length;

  r = run('status', id);
  const after = readTask(id);
  check('status <id> alone exits 0', r.code === 0, r.err);
  check('status <id> alone prints the task', r.out.includes(id) && r.out.includes('done') && r.out.includes('A real task to check'), r.out);
  check('status <id> alone leaves its status as it was', after.status === 'done', JSON.stringify(after.status));
  check('status <id> alone leaves the task file untouched', JSON.stringify(after) === JSON.stringify(before));
  check('status <id> alone adds no history event', history().length === eventsBefore, JSON.stringify(history().slice(eventsBefore)));

  r = run('status', id, 'finshed');
  check('an unknown status word is refused', r.code !== 0 && readTask(id).status === 'done', r.out + r.err);
  check('the refusal lists the allowed words', /pending.*in_progress.*blocked.*done.*dropped/.test(r.err), r.err);
  check('a refused status adds no history event', history().length === eventsBefore, JSON.stringify(history().slice(eventsBefore)));

  r = run('status', id, 'done');
  check('re-marking the same status with no note changes nothing', r.code === 0
    && JSON.stringify(readTask(id)) === JSON.stringify(before) && history().length === eventsBefore,
  JSON.stringify(history().slice(eventsBefore)));

  r = run('status', 'no-such-task');
  check('status on a missing task fails', r.code !== 0, r.out);

  // The library is the last line: the dashboard calls it directly.
  process.env.PHOTONZ_QUEUE_DIR = QUEUE;
  const q = await import('./queue-lib.mjs');
  let threw = false;
  try { q.setStatus(id, undefined); } catch { threw = true; }
  check('setStatus refuses a missing status', threw && readTask(id).status === 'done');
  check('no task ever carries no status', taskFiles().every((f) => typeof JSON.parse(readFileSync(f, 'utf8')).status === 'string'));
  check('no history event is ever named task_undefined', !history().some((e) => e.ev === 'task_undefined'));
} finally {
  rmSync(sandbox, { recursive: true, force: true });
}

console.log(failed ? `\n${failed} check(s) failed` : '\nall checks passed');
process.exit(failed ? 1 : 0);
