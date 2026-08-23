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
// history.jsonl is append-only and the dashboard parses ALL of it on every poll
// (aggregateState reads it whole to build the charts). A loop stuck in a
// claim/reset cycle writes two events every few seconds, and on 2026-08-23 that
// left 7,949 churn events buried under 165 real ones in a 1.3MB file. So the
// file self-compacts: churn beyond the retention window collapses to one
// counted entry per task per day, while anything that describes a real change
// to the queue is kept forever and the charts stay exact.
export const HISTORY_MAX_BYTES = 512 * 1024;
export const HISTORY_GROW_BYTES = 64 * 1024;  // re-compact only after this much new growth
export const CHURN_EVENTS = new Set(['task_started', 'task_reset', 'runner_failed']);
// Churn stays entry-per-attempt while it is recent AND recent-enough to matter.
// The age window keeps yesterday debuggable; the count keeps a storm that
// happened an hour ago from filling the file on its own.
const CHURN_KEEP_MS = 48 * 3600 * 1000;
const CHURN_KEEP_MAX = 200;

export function appendEvent(ev, data = {}) {
  ensureDirs();
  appendFileSync(HISTORY, JSON.stringify({ t: now(), ev, ...data }) + '\n');
  maybeCompactHistory();
}

// Collapse runs of churn events (same day, same event, same task) into a single
// entry carrying `repeats` and `until`. Order is preserved: a rolled-up entry sits
// where its first occurrence was. Everything else passes through untouched.
export function compactHistory() {
  const events = readHistory();
  const cutoff = new Date(Date.now() - CHURN_KEEP_MS).toISOString();
  const churnTotal = events.filter((e) => CHURN_EVENTS.has(e.ev)).length;
  let churnSeen = 0;
  const out = [];
  const rolled = new Map();
  for (const e of events) {
    if (!CHURN_EVENTS.has(e.ev)) { out.push(e); continue; }
    churnSeen++;
    const verbatim = (e.t || '') >= cutoff && churnSeen > churnTotal - CHURN_KEEP_MAX;
    if (verbatim) { out.push(e); continue; }
    const key = `${day(e.t)}|${e.ev}|${e.id || '-'}`;
    const seen = rolled.get(key);
    if (seen) { seen.repeats += (e.repeats || 1); seen.until = e.until || e.t; continue; }
    // `repeats`, not `count`: some real events (objectives_updated) already
    // carry a `count` that means something else entirely.
    const entry = { ...e, repeats: e.repeats || 1, until: e.until || e.t, rolledUp: true };
    rolled.set(key, entry);
    out.push(entry);
  }
  const changed = out.length !== events.length;
  if (changed) writeFileSync(HISTORY, out.map((o) => JSON.stringify(o)).join('\n') + '\n');
  return { before: events.length, after: out.length, changed };
}

// Compact when the file is over budget, but only once per HISTORY_GROW_BYTES of
// new growth: a file that is legitimately large (all real events) must not
// re-scan itself on every single append.
function maybeCompactHistory() {
  let size = 0;
  try { size = statSync(HISTORY).size; } catch { return; }
  if (size <= HISTORY_MAX_BYTES) return;
  const last = readStatus().historyCompact;
  if (last && typeof last.size === 'number' && size < last.size + HISTORY_GROW_BYTES) return;
  compactHistory();
  try { writeStatus({ historyCompact: { at: now(), size: statSync(HISTORY).size } }); } catch { /* status is advisory */ }
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
  if (Array.isArray(body.log)) body.log = trimLog(body.log);
  writeJSON(file, body);
  return { ...body, file };
}

// ---- task logs --------------------------------------------------------------
// A task log is a story a human reads on the dashboard, so it has to stay
// readable no matter how badly the loop misbehaves. On 2026-08-23 one task was
// claimed and reset 2,757 times and its log grew to 5,515 entries / 556KB,
// which the dashboard then had to fetch and render on every poll. Two guards:
// identical consecutive notes collapse into one counted entry, and the array is
// capped with the middle elided (the opening entries and the recent ones are
// the parts anyone actually reads).
export const LOG_MAX = 120;       // entries kept in a task's log
export const LOG_KEEP_HEAD = 20;  // oldest entries kept when the middle is elided

export function trimLog(log) {
  if (!Array.isArray(log) || log.length <= LOG_MAX) return log;
  const tailCount = LOG_MAX - LOG_KEEP_HEAD - 1;
  const head = log.slice(0, LOG_KEEP_HEAD);
  const tail = log.slice(log.length - tailCount);
  // Count a previous elision marker as the entries it stood for, so the number
  // stays truthful across repeated trims instead of resetting each time.
  const dropped = log.slice(LOG_KEEP_HEAD, log.length - tailCount)
    .reduce((n, e) => n + (e && e.elided ? e.elided : 1), 0);
  return [...head, { t: now(), note: `... ${dropped} earlier entries elided`, elided: dropped }, ...tail];
}

// Append a note, coalescing an immediate repeat into `count` + `since` rather
// than a new line. Every writer in this file goes through here.
export function appendLog(task, note) {
  const log = [...(task.log || [])];
  const last = log[log.length - 1];
  if (last && last.note === note) {
    log[log.length - 1] = { ...last, t: now(), since: last.since || last.t, count: (last.count || 1) + 1 };
  } else {
    log.push({ t: now(), note });
  }
  task.log = trimLog(log);
  return task;
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 48).replace(/^-+|-+$/g, '') || 'task';

// A task carries THREE kinds of writing, and they are not interchangeable:
//   goal       one or two plain sentences a human reads first: what changes,
//              and for whom. No file names, no class names, no jargon.
//   acceptance the checklist that decides done. One verifiable item per line.
//   notes      the runner's working detail. May be as technical as it likes,
//              because it is read last and by an agent.
// The dashboard renders them in that order, so a task is legible before it is
// implementable.
export function addTask({ title, goal = '', epic = '', priority = 'p2-normal', notes = '', release = 'next', area = 'app', acceptance = [], source = 'manual', seq = null }) {
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
    // `epic` is the objective this serves. A task that cannot name one is work
    // for its own sake, which is the thing the objectives exist to prevent.
    id, title, goal, epic, priority, seq, status: 'pending', release, area,
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
  appendLog(moved, `priority ${t.priority} -> ${priority}`);
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
  appendLog(t, `seq ${from ?? 'none'} -> ${seq}`);
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
  if (note) appendLog(t, note);
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
  appendLog(t, 'claimed by go loop');
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
  appendLog(t, reason);
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
  appendLog(t, reason);
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
      appendLog(task, `runner failed (exit ${exit}, attempt ${task.failures}): ${message}`);
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
// A runner that exits without finalizing leaves the task in_progress forever.
// Reset it to pending so the loop retries, and record what happened. Kept as a
// blunt safety net for anything recordRunnerExit did not cover (a task other
// than the claimed one left running, a loop restarted mid-task).
//
// The reset is NOT a free retry: it counts against the same per-task failure
// budget recordRunnerExit uses, so a task nothing can finish gets parked here
// too rather than being handed back to the loop forever.
export function guardStuck() {
  const stuck = readAllTasks().filter((t) => t.status === 'in_progress');
  const parked = [];
  for (const t of stuck) {
    t.failures = (t.failures || 0) + 1;
    if (t.failures >= MAX_TASK_FAILURES) {
      parkTask(t, `parked after ${t.failures} runner failures in a row; last runner exited without finalizing the task`);
      parked.push(t.id);
      continue;
    }
    t.status = 'pending';
    appendLog(t, `runner exited without finalizing; reset to pending (attempt ${t.failures})`);
    saveTask(t);
    appendEvent('task_reset', { id: t.id, attempt: t.failures });
  }
  return { reset: stuck.filter((t) => !parked.includes(t.id)).map((t) => t.id), parked };
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
    appendLog(t, `decision "${d.question}" resolved: ${chosen ? chosen.label : choice}${note ? ` (${note})` : ''}`);
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
  return readJSON(OBJECTIVES, { updated: null, focus: null, principles: [], epics: [] });
}
export function writeObjectives(epics, meta = {}) {
  if (!Array.isArray(epics)) throw new Error('epics must be an array');
  const clean = (list) => list.map((e) => ({
    id: String(e.id || slug(e.title)),
    title: String(e.title || 'Untitled'),
    note: e.note ? String(e.note) : '',
    // now | next | later. Stage is what stops the queue from working on
    // everything at once: only `now` epics may hold open tasks.
    stage: ['now', 'next', 'later'].includes(e.stage) ? e.stage : 'later',
    children: Array.isArray(e.children) ? clean(e.children) : [],
  }));
  const prev = readObjectives();
  const doc = {
    updated: now(),
    // the ONE feature epic the loop is working toward right now
    focus: meta.focus !== undefined ? meta.focus : (prev.focus || null),
    principles: meta.principles !== undefined ? meta.principles : (prev.principles || []),
    epics: clean(epics),
  };
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

// ---- audits -----------------------------------------------------------------
// An audit is what makes a feature playtestable by a human: what it is, how to
// try it, and what to judge. Written by the runner that finishes a feature,
// read on the dashboard's Audit tab.
const AUDITS = join(QUEUE, 'audits');
// Audits are STRUCTURED, not prose. A free-form markdown report becomes a wall
// nobody reads, and worse, it cannot be reacted to line by line. This shape is
// short by construction and gives the dashboard something to hang a comment on:
//   { feature, epic, summary, try:[{do,shot}], evaluate:[..], rough:[..] }
export function listAudits() {
  try { return readdirSync(AUDITS).filter((f) => f.endsWith('.json')).sort().reverse(); } catch { return []; }
}
export function readAudit(name) {
  if (!/^[a-z0-9._-]+\.json$/i.test(name)) return null;
  return readJSON(join(AUDITS, name));
}

// Feedback is the point of the Audit tab: a reaction becomes a task, with the
// thing being reacted to quoted so a runner does not have to guess.
export function addFeedback({ audit, anchor = '', quote = '', text, epic = '' }) {
  if (!text || !text.trim()) throw new Error('feedback needs text');
  const t = addTask({
    title: 'Feedback: ' + text.trim().split(/[.!?\n]/)[0].slice(0, 70),
    goal: text.trim(),
    epic,
    priority: 'p1-high',
    area: 'app',
    source: 'audit feedback',
    acceptance: ['The thing the user described is changed, or a decision is opened explaining why not'],
    notes: `Filed from the audit ${audit}${anchor ? ` (${anchor})` : ''}.` +
      (quote ? `\n\nWhat they were reacting to:\n"${quote}"` : '') +
      `\n\nTheir words:\n"${text.trim()}"`,
  });
  appendEvent('feedback_filed', { id: t.id, audit, anchor });
  return t;
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
    // Names only. The body used to ride along on every poll, which put the
    // whole of today's digest (7KB of markdown) into a payload the dashboard
    // fetches every 4 seconds and re-parses. The page fetches the one digest it
    // is showing from /api/digest/<name> instead.
    digests: { list: digestNames, latest: digestNames[0] || null },
    audits: listAudits(),
  };
}
