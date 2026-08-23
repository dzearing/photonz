// Photonz task queue - shared library.
// Used by the queue CLI (queue.mjs), the go loop, and the mock dev server's
// /api endpoints. Pure node stdlib, no deps. The queue is plain files so it
// survives reboots, is git-diffable, and every writer (loop, server, human,
// agent) goes through these helpers.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, appendFileSync, renameSync, statSync } from 'node:fs';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// The queue lives at <repo>/queue. PHOTONZ_QUEUE_DIR points every writer at a
// throwaway copy instead, which is how the runner-failure drill
// (queue/bin/failure-drill.sh) exercises the real loop without touching the
// real queue.
export const QUEUE = process.env.PHOTONZ_QUEUE_DIR
  ? resolve(process.env.PHOTONZ_QUEUE_DIR)
  : dirname(dirname(fileURLToPath(import.meta.url))); // queue/
export const REPO = dirname(QUEUE);
export const PRIORITIES = ['p0-critical', 'p1-high', 'p2-normal', 'p3-low'];
const TASKS = join(QUEUE, 'tasks');
const DECISIONS = join(QUEUE, 'decisions');
const DIGESTS = join(QUEUE, 'digests');
const HISTORY = join(QUEUE, 'history.jsonl');
const STATUS = join(QUEUE, 'status.json');

const now = () => new Date().toISOString();
const day = (iso) => (iso || now()).slice(0, 10);

function ensureDirs() {
  for (const p of PRIORITIES) mkdirSync(join(TASKS, p), { recursive: true });
  mkdirSync(DECISIONS, { recursive: true });
  mkdirSync(DIGESTS, { recursive: true });
}

function readJSON(file, fallback = null) {
  try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJSON(file, obj) {
  writeFileSync(file, JSON.stringify(obj, null, 2) + '\n');
}

// ---- history ----------------------------------------------------------------
export function appendEvent(ev, data = {}) {
  ensureDirs();
  appendFileSync(HISTORY, JSON.stringify({ t: now(), ev, ...data }) + '\n');
}
export function readHistory() {
  try {
    return readFileSync(HISTORY, 'utf8').split('\n').filter(Boolean).map((l) => {
      try { return JSON.parse(l); } catch { return null; }
    }).filter(Boolean);
  } catch { return []; }
}

// ---- tasks ------------------------------------------------------------------
export function readAllTasks() {
  ensureDirs();
  const out = [];
  for (const p of PRIORITIES) {
    const dir = join(TASKS, p);
    for (const f of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
      const file = join(dir, f);
      const t = readJSON(file);
      if (t) out.push({ ...t, priority: p, file });
    }
  }
  return out;
}
export function findTask(id) {
  return readAllTasks().find((t) => t.id === id) || null;
}
export function saveTask(task) {
  const { file, ...body } = task;
  body.updated = now();
  writeJSON(file, body);
  return { ...body, file };
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 48).replace(/^-+|-+$/g, '') || 'task';

export function addTask({ title, priority = 'p2-normal', notes = '', release = 'next', area = 'app', acceptance = [], source = 'manual', seq = null }) {
  ensureDirs();
  if (!PRIORITIES.includes(priority)) priority = 'p2-normal';
  const all = readAllTasks();
  let id = slug(title);
  const existing = new Set(all.map((t) => t.id));
  let n = 2;
  while (existing.has(id)) id = `${slug(title)}-${n++}`;
  // seq is the sort order within a priority: decimal, stepped by 10 so a task
  // can be slotted between two others (15 goes between 10 and 20) without
  // touching every file. Triage renumbers back to clean steps.
  if (typeof seq !== 'number' || !isFinite(seq)) {
    const peers = all.filter((t) => t.priority === priority && typeof t.seq === 'number');
    seq = peers.length ? Math.max(...peers.map((t) => t.seq)) + 10 : 10;
  }
  const task = {
    id, title, priority, seq, status: 'pending', release, area,
    created: now(), updated: now(), deps: [], blockedBy: [],
    notes, acceptance, log: [{ t: now(), note: `created (${source})` }],
    file: join(TASKS, priority, `${id}.json`),
  };
  saveTask(task);
  appendEvent('task_created', { id, priority, title });
  return task;
}

// Move a task file when priority changes; folder is the source of truth.
export function setPriority(id, priority) {
  if (!PRIORITIES.includes(priority)) throw new Error(`bad priority ${priority}`);
  const t = findTask(id);
  if (!t) throw new Error(`no task ${id}`);
  if (t.priority === priority) return t;
  const dest = join(TASKS, priority, basename(t.file));
  renameSync(t.file, dest);
  const moved = { ...t, priority, file: dest };
  moved.log = [...(moved.log || []), { t: now(), note: `priority ${t.priority} -> ${priority}` }];
  saveTask(moved);
  appendEvent('task_reprioritized', { id, from: t.priority, to: priority });
  return moved;
}

export function setSeq(id, seq) {
  if (typeof seq !== 'number' || !isFinite(seq)) throw new Error(`bad seq ${seq}`);
  const t = findTask(id);
  if (!t) throw new Error(`no task ${id}`);
  const from = t.seq;
  t.seq = seq;
  t.log = [...(t.log || []), { t: now(), note: `seq ${from ?? 'none'} -> ${seq}` }];
  saveTask(t);
  appendEvent('task_resequenced', { id, from, to: seq });
  return t;
}

export function setStatus(id, status, note = '') {
  const t = findTask(id);
  if (!t) throw new Error(`no task ${id}`);
  const prev = t.status;
  t.status = status;
  // Moving a parked task anywhere else un-parks it and gives it a clean slate,
  // so the dashboard's "put it back in the queue" really is a fresh start.
  if (t.parked && status !== 'blocked') { t.parked = false; t.parkReason = ''; t.failures = 0; }
  if (note) t.log = [...(t.log || []), { t: now(), note }];
  if (status === 'done') t.completed = now();
  saveTask(t);
  appendEvent(`task_${status}`, { id, from: prev, ...(note ? { note } : {}) });
  return t;
}

// Pick the highest-priority pending task whose deps are all done and claim it.
export function claimNext(pid = null) {
  const tasks = readAllTasks();
  const doneIds = new Set(tasks.filter((t) => t.status === 'done').map((t) => t.id));
  const ready = tasks.filter((t) => t.status === 'pending' && (t.deps || []).every((d) => doneIds.has(d)));
  if (!ready.length) return null;
  ready.sort((a, b) => PRIORITIES.indexOf(a.priority) - PRIORITIES.indexOf(b.priority) || (a.seq ?? Infinity) - (b.seq ?? Infinity) || (a.created || '').localeCompare(b.created || ''));
  const t = ready[0];
  t.status = 'in_progress';
  t.started = now();
  t.log = [...(t.log || []), { t: now(), note: 'claimed by go loop' }];
  saveTask(t);
  appendEvent('task_started', { id: t.id, title: t.title, priority: t.priority });
  writeStatus({ state: 'running', task: { id: t.id, title: t.title, priority: t.priority, file: t.file }, note: 'working', pid });
  return t;
}

// ---- runner failures --------------------------------------------------------
// On 2026-08-23 the monthly spend limit killed every runner the instant it
// started. The loop treated "runner exited" as "task finished", reset the task
// to pending, re-claimed it, and did that 3,959 times in 13 hours while the
// dashboard read Running the whole way. The rules below make a dead runner a
// first-class failure: it gets recorded, retried more slowly each time, and
// eventually stops being retried at all.
export const MAX_TASK_FAILURES = 3;   // consecutive failures of ONE task before it is parked
export const UNHEALTHY_AT = 2;        // consecutive failures before the loop reports unhealthy
const DEFAULT_BACKOFF = [30, 120, 300, 900, 1800]; // seconds before the next claim, per failure
// Split first, drop blanks, THEN parse: an unset var splits to [''] and Number('')
// is 0, which would silently mean "no backoff at all" — the exact bug this file exists to fix.
const ENV_BACKOFF = (process.env.PHOTONZ_BACKOFF_STEPS || '')
  .split(',').map((n) => n.trim()).filter(Boolean)
  .map(Number).filter((n) => isFinite(n) && n >= 0);
export const BACKOFF_STEPS = ENV_BACKOFF.length ? ENV_BACKOFF : DEFAULT_BACKOFF;

const cleanError = (s) => String(s || '').replace(/\s+/g, ' ').trim().slice(0, 400);

// Park a task: it has failed on its own often enough that retrying it is just
// burning runners. Blocked keeps it out of claimNext; parked/parkReason say why
// so the dashboard and the next human can tell it from a decision block.
function parkTask(t, reason) {
  t.status = 'blocked';
  t.parked = true;
  t.parkReason = reason;
  t.log = [...(t.log || []), { t: now(), note: reason }];
  saveTask(t);
  appendEvent('task_parked', { id: t.id, reason });
}
function unparkTask(id, reason) {
  const t = findTask(id);
  if (!t || !t.parked) return false;
  t.status = 'pending';
  t.parked = false;
  t.parkReason = '';
  t.failures = 0;
  t.log = [...(t.log || []), { t: now(), note: reason }];
  saveTask(t);
  appendEvent('task_unparked', { id, reason });
  return true;
}

// Called by the go loop after every runner exits. Decides whether that run was
// a success or a failure, updates the task and the loop health, and returns how
// long the loop should wait before claiming again.
//
//   outcome  ok | failed | parked
//   backoff  seconds to sleep before the next claim
export function recordRunnerExit({ taskId = null, exit = 0, error = '', kind = 'task' } = {}) {
  const s = readStatus();
  const task = taskId ? findTask(taskId) : null;
  // What counts as failure: for a task run, the runner leaving its task
  // in_progress (it never finalized, whatever it exited with); for a digest run
  // there is no task to inspect, so the exit code is all we have. A runner that
  // finalized its task and then exited non-zero still did the work.
  const unfinalized = !!task && task.status === 'in_progress';
  const failed = task ? unfinalized : exit !== 0;
  if (!failed) {
    if (task && task.failures) { task.failures = 0; saveTask(task); }
    writeStatus({ health: 'ok', consecutiveFailures: 0, lastError: null, failureStreak: null });
    return { outcome: 'ok', backoff: 0, consecutiveFailures: 0, parked: false };
  }

  const message = cleanError(error) ||
    (unfinalized ? `runner exited ${exit} without finalizing the task` : `runner exited ${exit}`);
  const consecutive = (s.consecutiveFailures || 0) + 1;
  const prev = (s.failureStreak && typeof s.failureStreak === 'object') ? s.failureStreak : {};
  const streak = { taskIds: [...(prev.taskIds || [])], parked: [...(prev.parked || [])] };
  if (taskId && !streak.taskIds.includes(taskId)) streak.taskIds.push(taskId);

  // Failures that span more than one task are the environment's fault (spend
  // limit, no network, bad credentials), not any task's. Parking the whole
  // queue one task at a time would be the worst possible response, so back off
  // instead and hand back anything parked earlier in this same streak.
  const environment = streak.taskIds.length > 1;
  const unparked = [];
  if (environment && streak.parked.length) {
    for (const id of streak.parked) {
      if (unparkTask(id, 'unparked: runners are failing regardless of which task runs, so the earlier failures were not this task')) unparked.push(id);
    }
    streak.parked = [];
  }

  let outcome = 'failed';
  if (task && unfinalized) {
    task.failures = (task.failures || 0) + 1;
    task.lastError = { at: now(), exit, message };
    if (!environment && task.failures >= MAX_TASK_FAILURES) {
      parkTask(task, `parked after ${task.failures} runner failures in a row; last error: ${message}`);
      streak.parked.push(task.id);
      outcome = 'parked';
    } else {
      task.status = 'pending';
      task.log = [...(task.log || []), { t: now(), note: `runner failed (exit ${exit}, attempt ${task.failures}): ${message}` }];
      saveTask(task);
    }
  }

  const backoff = BACKOFF_STEPS[Math.min(consecutive - 1, BACKOFF_STEPS.length - 1)];
  writeStatus({
    health: consecutive >= UNHEALTHY_AT ? 'unhealthy' : 'ok',
    consecutiveFailures: consecutive,
    lastError: { at: now(), taskId: taskId || null, kind, exit, message, environment },
    failureStreak: streak,
    note: `runner failed (exit ${exit}); retrying in ${backoff}s`,
  });
  appendEvent('runner_failed', { id: taskId || null, kind, exit, consecutive, outcome, environment, error: message });
  return { outcome, backoff, consecutiveFailures: consecutive, parked: outcome === 'parked', unparked, environment };
}

// A runner that exits without finalizing leaves the task in_progress forever.
// Reset it to pending so the loop retries, and record what happened. Kept as a
// blunt safety net for anything recordRunnerExit did not cover (a task other
// than the claimed one left running, a loop restarted mid-task).
export function guardStuck() {
  const stuck = readAllTasks().filter((t) => t.status === 'in_progress');
  for (const t of stuck) {
    t.status = 'pending';
    t.log = [...(t.log || []), { t: now(), note: 'runner exited without finalizing; reset to pending' }];
    saveTask(t);
    appendEvent('task_reset', { id: t.id });
  }
  return stuck.map((t) => t.id);
}

// ---- decisions --------------------------------------------------------------
export function readDecisions() {
  ensureDirs();
  return readdirSync(DECISIONS).filter((f) => f.endsWith('.json'))
    .map((f) => readJSON(join(DECISIONS, f))).filter(Boolean)
    .map((d) => ({ ...d, hasBrief: existsSync(join(DECISIONS, `${d.id}.md`)) }))
    .sort((a, b) => (b.created || '').localeCompare(a.created || ''));
}
// The brief: a durable plain-language explainer next to the decision JSON
// (<id>.md). The dashboard's "Explain in more detail" renders it.
export function readDecisionBrief(id) {
  if (!/^[a-z0-9-]+$/.test(id)) return null;
  try { return readFileSync(join(DECISIONS, `${id}.md`), 'utf8'); } catch { return null; }
}

export function addDecision({ taskId, question, context = '', options = [], recommended = '' }) {
  ensureDirs();
  const qslug = slug(question).slice(0, 32).replace(/-+$/, '');
  let id = `${taskId}-${qslug}`;
  const existing = new Set(readDecisions().map((d) => d.id));
  let n = 2;
  while (existing.has(id)) id = `${taskId}-${qslug}-${n++}`;
  const d = { id, taskId, question, context, options, recommended, status: 'pending', created: now() };
  writeJSON(join(DECISIONS, `${id}.json`), d);
  appendEvent('decision_opened', { id, taskId, question });
  return d;
}

// Resolving a decision unblocks its task and puts it back in the queue.
export function resolveDecision(id, choice, note = '') {
  const file = join(DECISIONS, `${id}.json`);
  const d = readJSON(file);
  if (!d) throw new Error(`no decision ${id}`);
  d.status = 'resolved';
  d.answer = { choice, note, resolved: now() };
  writeJSON(file, d);
  appendEvent('decision_resolved', { id, taskId: d.taskId, choice });
  const t = d.taskId ? findTask(d.taskId) : null;
  if (t) {
    t.blockedBy = (t.blockedBy || []).filter((b) => b !== id);
    if (!t.blockedBy.length && t.status === 'blocked') t.status = 'pending';
    const chosen = (d.options || []).find((o) => o.id === choice);
    t.log = [...(t.log || []), { t: now(), note: `decision "${d.question}" resolved: ${chosen ? chosen.label : choice}${note ? ` (${note})` : ''}` }];
    saveTask(t);
    appendEvent('task_unblocked', { id: t.id, decision: id });
  }
  return d;
}

// ---- loop status ------------------------------------------------------------
export function readStatus() {
  return readJSON(STATUS, { state: 'stopped', task: null, note: '', updatedAt: null, pid: null });
}
export function writeStatus(patch) {
  const s = { ...readStatus(), ...patch, updatedAt: now() };
  writeJSON(STATUS, s);
  return s;
}
export function loopAlive(status = readStatus()) {
  if (!status.pid) return false;
  try { process.kill(status.pid, 0); return true; } catch { return false; }
}

// ---- objectives -------------------------------------------------------------
// The ordered epic tree that steers triage. Order IS priority; nesting is
// sub-epics. The dashboard's Objectives tab edits this wholesale.
const OBJECTIVES = join(QUEUE, 'objectives.json');
export function readObjectives() {
  return readJSON(OBJECTIVES, { updated: null, epics: [] });
}
export function writeObjectives(epics) {
  if (!Array.isArray(epics)) throw new Error('epics must be an array');
  const clean = (list) => list.map((e) => ({
    id: String(e.id || slug(e.title)),
    title: String(e.title || 'Untitled'),
    note: e.note ? String(e.note) : '',
    children: Array.isArray(e.children) ? clean(e.children) : [],
  }));
  const doc = { updated: now(), epics: clean(epics) };
  writeJSON(OBJECTIVES, doc);
  appendEvent('objectives_updated', { count: doc.epics.length });
  return doc;
}
// Queue a p0 triage pass against the current objectives (used by the dashboard's
// Retriage button). No-op if one is already waiting.
export function requestRetriage() {
  const existing = readAllTasks().find((t) => t.id.startsWith('retriage-queue-against-objectives') && ['pending', 'in_progress'].includes(t.status));
  if (existing) return { queued: false, id: existing.id };
  const t = addTask({
    title: 'Retriage queue against objectives',
    priority: 'p0-critical',
    seq: 1,
    area: 'queue',
    source: 'dashboard retriage button',
    notes: 'The user updated queue/objectives.json and asked for a retriage. Read the objectives tree (order is priority, nesting is sub-epics) and every open task, then make the queue reflect it: reprioritize (queue.mjs priority), resequence to clean steps of 10 per priority (queue.mjs seq), dedupe, and groom notes so each task names the objective it serves. Do NOT write a digest. Record one history event: queue.mjs event triage with a summary of what moved.',
    acceptance: ['Every open task priority/sequence is consistent with the objectives ordering', 'A triage history event summarizes the changes'],
  });
  return { queued: true, id: t.id };
}

// ---- digests ----------------------------------------------------------------
export function listDigests() {
  ensureDirs();
  return readdirSync(DIGESTS).filter((f) => f.endsWith('.md')).sort().reverse();
}
export function readDigest(name) {
  try { return readFileSync(join(DIGESTS, name), 'utf8'); } catch { return null; }
}

// ---- aggregate state for the dashboard --------------------------------------
export function aggregateState() {
  const tasks = readAllTasks().map(({ file, ...t }) => t);
  const decisions = readDecisions();
  const history = readHistory();
  const status = readStatus();
  const alive = loopAlive(status);
  const cutoff24 = new Date(Date.now() - 24 * 3600 * 1000).toISOString();

  // daily series for charts: per-day created/completed plus running totals
  const days = {};
  let totalCreated = 0, totalDone = 0;
  for (const e of history) {
    const d = day(e.t);
    days[d] = days[d] || { day: d, created: 0, completed: 0 };
    if (e.ev === 'task_created') { days[d].created++; totalCreated++; }
    if (e.ev === 'task_done') { days[d].completed++; totalDone++; }
  }
  const series = Object.values(days).sort((a, b) => a.day.localeCompare(b.day));
  let open = 0;
  for (const s of series) { open += s.created - s.completed; s.open = open; }

  const digestNames = listDigests();
  return {
    objectives: readObjectives(),
    generated: now(),
    loop: {
      ...status,
      alive,
      stale: !alive && status.state === 'running',
      health: status.health || 'ok',
      consecutiveFailures: status.consecutiveFailures || 0,
      lastError: status.lastError || null,
    },
    tasks,
    counts: {
      byPriority: Object.fromEntries(PRIORITIES.map((p) => [p, tasks.filter((t) => t.priority === p && t.status !== 'done' && t.status !== 'dropped').length])),
      byStatus: ['pending', 'in_progress', 'blocked', 'done', 'dropped'].reduce((m, s) => ({ ...m, [s]: tasks.filter((t) => t.status === s).length }), {}),
      total: tasks.length,
    },
    decisions: { pending: decisions.filter((d) => d.status === 'pending'), resolved: decisions.filter((d) => d.status === 'resolved').slice(0, 10) },
    completed24h: tasks.filter((t) => t.status === 'done' && (t.completed || '') >= cutoff24),
    next: tasks.filter((t) => t.status === 'pending').sort((a, b) => PRIORITIES.indexOf(a.priority) - PRIORITIES.indexOf(b.priority) || (a.seq ?? Infinity) - (b.seq ?? Infinity) || (a.created || '').localeCompare(b.created || '')).slice(0, 8),
    series,
    history: history.slice(-80).reverse(),
    digests: { list: digestNames, latest: digestNames[0] ? { name: digestNames[0], body: readDigest(digestNames[0]) } : null },
  };
}
