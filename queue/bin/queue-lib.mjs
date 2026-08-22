// Photonz task queue - shared library.
// Used by the queue CLI (queue.mjs), the go loop, and the mock dev server's
// /api endpoints. Pure node stdlib, no deps. The queue is plain files so it
// survives reboots, is git-diffable, and every writer (loop, server, human,
// agent) goes through these helpers.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, appendFileSync, renameSync, statSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

export const QUEUE = dirname(dirname(fileURLToPath(import.meta.url))); // queue/
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

// A runner that exits without finalizing leaves the task in_progress forever.
// Reset it to pending so the loop retries, and record what happened.
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
    loop: { ...status, alive, stale: !alive && status.state === 'running' },
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
