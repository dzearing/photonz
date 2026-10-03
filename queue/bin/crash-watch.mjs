#!/usr/bin/env node
// Every Photonz crash is caught, read, and either filed or counted.
//
// The user, 2026-10-02, with a "Photonz (Probe) quit unexpectedly" dialog on
// screen: "make sure that you're catching these". Until then a crash was only
// noticed when it happened inside a walk, the person's own Dev app was never
// watched at all, and a crash the walk reader called a macOS fault was retried
// and forgotten. So after every task the loop runs this:
//
//   * every new crash report for the probe, the Dev app or the release app
//     (~/Library/Logs/DiagnosticReports, read by Scripts/crash-report.mjs)
//   * a crash in the app's own code: one p1 task per signature (the app, the
//     top three frames of its own code), with the report path and the stack;
//     a repeat of a signature already filed is logged on that task instead,
//     unless that task is closed: then the crash came back after its fix, and a
//     fresh p1 task says so and names the closed one (a line in a done task's
//     log is read by nobody)
//   * a crash in the Dev app is ALWAYS filed, even a known macOS fault: it
//     happened to the person
//   * a known macOS fault in the probe is listed and not filed: the walk is
//     run once more, and the "quit unexpectedly" alert it leaves is closed by
//     Scripts/probe-crash-alert.mjs (until 2026-10-03 three in a week filed a
//     task, which became that script)
//
//   node queue/bin/crash-watch.mjs          scan, file, print one line each
//   node queue/bin/crash-watch.mjs --dry    scan and print, file nothing
//   node queue/bin/crash-watch.mjs --since <ISO>   only reports after this
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readCrashReport, REPORTS_DIR } from '../../Scripts/crash-report.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const STATE = path.join(ROOT, 'queue', 'crash-watch.json');
const APPS = {
  'com.dzearing.photonz.probe': 'probe',
  'com.dzearing.photonz.dev': 'dev',
  'com.dzearing.photonz': 'release',
};
const argv = process.argv.slice(2);
const dry = argv.includes('--dry');
const sinceArg = argv.includes('--since') ? Date.parse(argv[argv.indexOf('--since') + 1]) : 0;

function load() {
  try { return JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch { return null; }
}
const state = load() || { seen: {}, signatures: {}, faults: {}, startedAt: new Date().toISOString() };
// First run: start from now, so a year of old reports is not filed in one go.
const floor = sinceArg || Date.parse(state.startedAt) - 1;

function queue(...args) {
  return execFileSync('node', [path.join(ROOT, 'queue', 'bin', 'queue.mjs'), ...args],
    { cwd: ROOT, encoding: 'utf8' }).trim();
}

// The status of a task by id, wherever its priority folder is; null if gone.
function taskStatus(id) {
  const dir = path.join(ROOT, 'queue', 'tasks');
  for (const folder of fs.readdirSync(dir)) {
    try { return JSON.parse(fs.readFileSync(path.join(dir, folder, `${id}.json`), 'utf8')).status; } catch {}
  }
  return null;
}

let names = [];
try { names = fs.readdirSync(REPORTS_DIR).filter((n) => n.endsWith('.ips') && /Photonz/i.test(n)); } catch {}
const lines = [];
for (const name of names.sort()) {
  if (state.seen[name]) continue;
  const r = readCrashReport(path.join(REPORTS_DIR, name));
  if (!r || !APPS[r.bundleId]) { state.seen[name] = 'not-photonz'; continue; }
  if (r.whenMs && r.whenMs < floor) { state.seen[name] = 'before-watch'; continue; }
  const app = APPS[r.bundleId];
  const own = r.frames.slice(0, 3).map((f) => f.symbol).join(' < ');
  const sig = `${app}|${r.systemFault || own || r.exception}`;
  state.seen[name] = sig;
  if (r.systemFault && app !== 'dev') {
    // Not counted toward a task any more. Its harm was never the crash (the
    // walk is run once more) but the "quit unexpectedly" alert it left over the
    // person's work, and since 2026-10-03 that alert is closed the moment the
    // harness sees the probe die (Scripts/probe-crash-alert.mjs). The fault
    // itself is macOS's and the window switcher's, and nothing here can stop it.
    lines.push(`crash ${app} ${r.when}: ${r.summary} (macOS fault: the walk reruns and its alert is closed, not filed)`);
    continue;
  }
  const known = state.signatures[sig];
  lines.push(`crash ${app} ${r.when}: ${r.summary}`);
  if (dry) continue;
  const cameBack = known && ['done', 'dropped', null].includes(taskStatus(known));
  if (known && !cameBack) {
    queue('log', known, `crash watch: it happened again in the ${app} app at ${r.when}: ${r.file}`);
    lines.push(`  logged on ${known}`);
    continue;
  }
  const stack = r.frames.slice(0, 8).map((f) => `${f.symbol}${f.file ? ` (${f.file}${f.line ? ':' + f.line : ''})` : ''}`).join('\n');
  const who = app === 'dev' ? 'the person\'s own Dev app' : app === 'probe' ? 'the loop\'s probe app' : 'the release app';
  const task = {
    title: `The app crashed in ${(r.frames[0]?.symbol || r.exception).replace(/\(.*$/, '').slice(0, 80)}`,
    goal: `Crash watch caught a crash in ${who} at ${r.when}: ${r.summary}.${cameBack ? ` It came back after ${known} was closed, so that fix did not hold or missed a route.` : ''} Read the report, reproduce it, fix the cause, and add a test that would have caught it.${r.systemFault ? ' macOS calls this a fault of its own, but it happened to the person, so find what in Photonz invites it.' : ''}`,
    epic: 'unmanned-loop', priority: 'p1-high', source: 'crash-watch',
    acceptance: ['Reproduced (or the exact conditions shown from the report) before the fix', 'The cause fixed in Photonz code, with a test or walk that fails before and passes after', 'crash-watch shows no new report with this signature for a week of walks'],
    notes: `${cameBack ? `Came back after: ${known}\n` : ''}Report: ${r.file}\nException: ${r.exception} ${r.signal}\nMessages: ${r.messages.join(' | ')}\nStack (app frames):\n${stack}`,
  };
  const id = queue('addjson', JSON.stringify(task)).split('\n').pop();
  state.signatures[sig] = id;
  lines.push(`  filed ${id}`);
}
if (!dry) fs.writeFileSync(STATE, JSON.stringify(state, null, 2) + '\n');
console.log(lines.length ? lines.join('\n') : 'crash watch: no new Photonz crash reports');
