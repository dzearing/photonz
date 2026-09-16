#!/usr/bin/env node
// What the loop does about a working tree a runner left dirty.
//
// A task that runs out of its turn stops without putting its work away, and
// the files it changed stay in the repository for whoever starts next. That is
// not theoretical: on 2026-09-16 the runner on
// separate-finds-the-boxes-in-a-dark-window-too-no ran out of turn at 05:18
// and left seven files changed (four modified, three new). Nothing in the loop
// mentioned them, so the next task would have begun on top of somebody else's
// half-built code and committed it under its own name.
//
// So the loop takes a picture of what was already dirty BEFORE it starts a
// runner, and when that runner ends it compares. Anything that became dirty
// during the runner's turn belongs to that runner:
//
//   * it is named in loop.log and on the dashboard, with the task that owns it
//   * it is put aside in a git stash whose message says whose it is
//   * the record is handed back to the owning task the next time that task is
//     claimed, as a log line saying how to restore it
//
// Two things are deliberately left alone:
//
//   queue/   the loop's own bookkeeping (status, history, task files, digests).
//            No task owns it, every runner writes it, and stashing it would
//            throw away queue state the loop is mid-way through writing.
//   anything already dirty when the runner started. That is either the user
//            editing their own repo or an earlier leftover somebody decided to
//            keep, and neither is this runner's to move.
//
// Usage:
//   node queue/bin/leftovers.mjs snapshot <file>
//   node queue/bin/leftovers.mjs settle <file> <kind> <taskId|-> <outcome> [label]
//   node queue/bin/leftovers.mjs list [--all]
//   node queue/bin/leftovers.mjs clear <recordId> <why>
import { execFileSync } from 'node:child_process';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import * as q from './queue-lib.mjs';

const REPO = q.REPO;

const git = (args) => execFileSync('git', args, {
  cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'],
});
const gitQuiet = (args) => { try { return git(args).trim(); } catch { return ''; } };

const isRepo = () => gitQuiet(['rev-parse', '--is-inside-work-tree']) === 'true';

// Every path git calls dirty right now, tracked or not. -z so a filename with a
// space or a newline in it survives; a rename entry carries BOTH paths and both
// are dirty, so both are read. --untracked-files=all names the FILES inside a
// brand new directory rather than collapsing them into the directory: a log
// line saying `Tests/Fixtures` tells a person nothing, and the before-picture
// has to be file-grained too, or a new file dropped into a directory the user
// was already working in reads as already-dirty and is left behind.
function dirtyPaths() {
  const raw = git(['status', '--porcelain=v1', '-z', '--untracked-files=all']);
  const parts = raw.split('\0');
  const paths = [];
  for (let i = 0; i < parts.length; i++) {
    const entry = parts[i];
    if (!entry || entry.length < 4) continue;
    const xy = entry.slice(0, 2);
    paths.push(entry.slice(3));
    if (xy[0] === 'R' || xy[0] === 'C') { i++; if (parts[i]) paths.push(parts[i]); }
  }
  return paths.map((p) => p.replace(/\/+$/, '')).filter(Boolean);
}

// The loop's own bookkeeping, which no task owns. A path is inside it if it is
// the directory itself or anything under it.
const OURS = ['queue'];
const isOurs = (p) => OURS.some((d) => p === d || p.startsWith(d + '/'));

const readSet = (file) => {
  if (!file || !existsSync(file)) return new Set();
  try { return new Set(JSON.parse(readFileSync(file, 'utf8'))); } catch { return new Set(); }
};

function cmdSnapshot(file) {
  if (!isRepo()) { writeFileSync(file, '[]\n'); return 0; }
  writeFileSync(file, JSON.stringify(dirtyPaths(), null, 0) + '\n');
  return 0;
}

function cmdSettle(file, kind, taskId, outcome, label) {
  if (!isRepo()) return 0;
  const before = readSet(file);
  const left = dirtyPaths().filter((p) => !isOurs(p) && !before.has(p));
  if (!left.length) return 0;

  const owner = taskId && taskId !== '-' ? taskId : null;
  const task = owner ? q.findTask(owner) : null;
  const who = label || (task ? task.title : null) || (owner || `the ${kind} pass`);
  const stamp = new Date().toISOString();
  const message = `photonz leftovers: ${owner || kind} (${outcome}) ${stamp}`;

  // Stash only what this runner dirtied. Exclude-only pathspecs mean "all files
  // except these", so the user's own edits and the queue's bookkeeping stay
  // exactly where they are.
  const keep = [...OURS, ...before];
  const args = ['stash', 'push', '--include-untracked', '-m', message, '--',
    ...keep.map((p) => `:(exclude,literal)${p}`)];

  const stashBefore = gitQuiet(['rev-parse', '--verify', '--quiet', 'refs/stash']);
  let sha = '';
  let why = '';
  try {
    git(args);
    const stashAfter = gitQuiet(['rev-parse', '--verify', '--quiet', 'refs/stash']);
    if (stashAfter && stashAfter !== stashBefore) sha = stashAfter;
    else why = 'git stash reported nothing to save';
  } catch (e) {
    why = String((e && (e.stderr || e.message)) || 'git stash failed').trim().split('\n').slice(-1)[0];
  }

  const rec = q.recordLeftovers({
    task: owner, kind, label: who, title: task ? task.title : '', outcome,
    files: left, stash: sha, why,
  });

  const n = left.length;
  const head = `${n} file${n === 1 ? '' : 's'} left changed by ${who}`;
  if (sha) {
    console.log(`${head}; set aside as git stash ${sha.slice(0, 12)} (restore: git stash apply ${sha}). Files: ${left.join(', ')}`);
  } else {
    console.log(`${head} and they could NOT be put aside (${why}). They are still in the working tree and the next task would commit them. Files: ${left.join(', ')}`);
  }
  return rec ? 0 : 0;
}

const [cmd, ...args] = process.argv.slice(2);
try {
  switch (cmd) {
    case 'snapshot':
      process.exit(cmdSnapshot(args[0]));
      break;
    case 'settle':
      process.exit(cmdSettle(args[0], args[1] || 'task', args[2] || '-', args[3] || 'unknown', args[4] || ''));
      break;
    case 'list': {
      const all = args.includes('--all');
      const rows = q.readLeftovers().filter((r) => all || !r.handed);
      if (!rows.length) { console.log('no leftovers'); break; }
      for (const r of rows) {
        console.log(`${r.id}\t${r.state}\t${r.task || r.kind}\t${r.files.length} file(s)\t${r.handed ? 'handed ' + r.handed : 'open'}`);
        console.log(`  ${r.restore || r.why}`);
      }
      break;
    }
    case 'clear': {
      if (!args[0] || !args[1]) throw new Error('usage: leftovers.mjs clear <recordId> <why>');
      const r = q.clearLeftovers(args[0], args[1]);
      console.log(r ? `cleared ${r.id}` : `no such leftovers record: ${args[0]}`);
      break;
    }
    default:
      console.error(readFileSync(new URL(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).join('\n'));
      process.exit(2);
  }
} catch (e) {
  console.error(`leftovers: ${e.message}`);
  process.exit(1);
}
