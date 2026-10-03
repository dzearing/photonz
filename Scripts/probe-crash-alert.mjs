#!/usr/bin/env node
// Closes the "Photonz (Probe) quit unexpectedly" alert a probe crash leaves on
// screen, and no other alert.
//
// When the probe dies, macOS puts that alert up over whatever the person is
// doing, and it stays in front until somebody clicks it: no app can take focus
// under it, so every walk after it fails for want of a key window. The crash
// itself is often not ours to stop (Scripts/crash-report.mjs, macos-ax-notify:
// macOS kills the app while it posts an accessibility notification to a window
// switcher), and a runner sometimes crashes the probe on purpose to prove a fix.
// Either way the alert is the harm, so it is closed as soon as the harness sees
// it.
//
// Which crashes put the alert up at all was found on 2026-10-03 by crashing the
// probe three ways with `kill -SEGV`: ReportCrash logs "crashed process ... was
// NOT user visible" and shows nothing while the probe is the menu-bar accessory
// it launches as (with an editor window open or not), and "WAS user visible"
// with the alert up once the probe has become a regular Dock app, which every
// video and tutorial walk makes it (AppCoordinator.openWindow).
//
// How it knows the alert is the probe's, without reading its title (that needs
// a grant the terminal does not have): window numbers only count up, so at each
// probe launch `mark` writes down the newest window number on the Mac. An alert
// is closed only when a probe crash report has been written since that launch,
// and exactly one alert is on screen that is numbered above the mark, i.e. went
// up while that probe was alive. An alert that was already up before the launch
// (somebody else's) is left alone, and so is a pair of new ones: a crash puts up
// one, so two means one of them is not the probe's.
//
// Every close that finds a crash spends it: the mark moves on to the newest
// window and to after that crash, alert or no alert. Without that, an alert
// somebody else put up AFTER the crash had been dealt with read exactly like
// the probe's (a drill alert was closed that way on 2026-10-03 before this was
// added). A crash while the probe is still an accessory puts no alert up at
// all, so `close --wait 3` gives the alert a moment to appear before the crash
// is spent.
//
// Closing it is `killall UserNotificationCenter`, which is what clicking Ignore
// does to it; launchd starts that process again on the next alert. The report
// is already written by then, so nothing is lost.
//
//   node Scripts/probe-crash-alert.mjs mark     at every probe launch, before it
//   node Scripts/probe-crash-alert.mjs close    after a crash, between tasks
//   node Scripts/probe-crash-alert.mjs close --wait 3   right after a crash
//
// PHOTONZ_KEEP_CRASH_ALERT=1 leaves the alert up, for a person who wants to see
// it. Drill: node Scripts/probe-crash-alert-drill.mjs
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { findCrashReport, PROBE_BUNDLE_ID, REPORTS_DIR } from './crash-report.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const MARK = process.env.PHOTONZ_PROBE_LAUNCH_MARK || path.join(ROOT, 'dist', 'probe-launch-mark.json');

// The whole decision, with nothing read from the machine, so the drill can put
// it through every case. `alerts` are window numbers on screen now; `crash` is
// the newest probe crash since the mark ({ whenMs }), or null.
export function decide({ mark, alerts, crash }) {
  if (!alerts.length) return { action: 'none' };
  if (!mark || !Number.isFinite(mark.maxWindowId)) return { action: 'leave', why: 'no-mark' };
  if (!crash) return { action: 'leave', why: 'no-probe-crash' };
  if (alerts.some((id) => id <= mark.maxWindowId)) return { action: 'leave', why: 'older-alert' };
  if (alerts.length > 1) return { action: 'leave', why: 'several' };
  return { action: 'close' };
}

// Crashes from this moment on count against the mark. A spent crash moves it
// past that crash; findCrashReport keeps a report up to a second before
// `sinceMs`, because a report's time is to the second.
export const crashesFrom = (mark) => mark.crashesFromMs ?? mark.launchedMs;
export const spent = (mark, crash, maxWindowId) => ({
  ...mark, maxWindowId, crashesFromMs: crash.whenMs + 1001,
});

// Each probe crash macOS saw, from its own log. A crash REPORT is not enough:
// macOS writes only so many a day for one app ("client log create type 309
// result FAILED: Log limit exceeded"), and past that the alert still goes up
// with no report behind it, which is how a crash on 2026-10-03 kept its alert.
// ReportCrash's "Formulating fatal 309 report for corpse[<pid>] Photonz Probe"
// is written for every crash, limit or not, and kept in the persisted log.
export function parseLoggedCrashes(text) {
  const out = [];
  for (const line of String(text).split('\n')) {
    const m = line.match(/^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3}).*Formulating fatal \d+ report for corpse\[(\d+)\] Photonz Probe\s*$/);
    if (!m) continue;
    const [, y, mo, d, h, mi, sec, ms, pid] = m;
    out.push({ whenMs: new Date(+y, +mo - 1, +d, +h, +mi, +sec, +ms).getTime(), pid: Number(pid) });
  }
  return out;
}

const stamp = (ms) => {
  const t = new Date(ms);
  const p = (n) => String(n).padStart(2, '0');
  return `${t.getFullYear()}-${p(t.getMonth() + 1)}-${p(t.getDate())} ${p(t.getHours())}:${p(t.getMinutes())}:${p(t.getSeconds())}`;
};

function loggedCrashes(sinceMs) {
  try {
    const text = execFileSync('/usr/bin/log', ['show', '--style', 'compact', '--start', stamp(sinceMs),
      '--predicate', 'process == "ReportCrash" AND eventMessage BEGINSWITH "Formulating fatal"'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 20000 });
    return parseLoggedCrashes(text).filter((c) => c.whenMs >= sinceMs);
  } catch {
    return [];
  }
}

// The newest probe crash since `sinceMs`, from the log or from a report.
function newestCrash(sinceMs) {
  const dir = process.env.PHOTONZ_CRASH_REPORTS_DIR || REPORTS_DIR;
  const report = findCrashReport({ dir, bundleId: PROBE_BUNDLE_ID, sinceMs });
  const found = [...loggedCrashes(sinceMs), ...(report?.whenMs ? [{ whenMs: report.whenMs }] : [])];
  return found.reduce((a, b) => (!a || b.whenMs > a.whenMs ? b : a), null);
}

function readAlerts() {
  const out = execFileSync('swift', [path.join(ROOT, 'Scripts', 'system-alerts.swift')], { encoding: 'utf8' });
  const maxWindowId = Number((out.match(/^maxWindowId=(\d+)$/m) || [])[1] || NaN);
  const alerts = [...out.matchAll(/^alert=(\d+)$/gm)].map((m) => Number(m[1]));
  return { maxWindowId, alerts };
}

function readMark() {
  try { return JSON.parse(fs.readFileSync(MARK, 'utf8')); } catch { return null; }
}

const clock = (ms) => new Date(ms).toTimeString().slice(0, 8);

function writeMark(m) {
  fs.mkdirSync(path.dirname(MARK), { recursive: true });
  fs.writeFileSync(MARK, `${JSON.stringify(m)}\n`);
}

function mark() {
  writeMark({ launchedMs: Date.now(), maxWindowId: readAlerts().maxWindowId });
}

function close(waitSeconds) {
  const m = readMark();
  if (!m) return 0;
  let { alerts, maxWindowId } = readAlerts();
  // Nothing on screen and nobody waiting: nothing to close, and no need to read
  // macOS's log (most of a second) on every launch to know it. Move the mark on
  // so a crash that put no alert up is not held against a later one, keeping
  // the last few seconds in case an alert is still on its way.
  if (!alerts.length && !waitSeconds) {
    writeMark({ ...m, maxWindowId, crashesFromMs: Math.max(crashesFrom(m), Date.now() - 5000) });
    return 0;
  }
  // Right after a death, macOS takes a second or so to log the crash and put
  // the alert up, so `--wait` keeps looking for both until it has them.
  const deadline = Date.now() + waitSeconds * 1000;
  let crash = newestCrash(crashesFrom(m));
  while ((!crash || !alerts.length) && Date.now() < deadline) {
    execFileSync('sleep', ['0.2']);
    if (!crash) crash = newestCrash(crashesFrom(m));
    ({ alerts } = readAlerts());
  }
  if (!crash) return 0;
  const verdict = decide({ mark: m, alerts, crash });
  const status = act(verdict, alerts, crash);
  writeMark(spent(m, crash, readAlerts().maxWindowId));
  return status;
}

function act(verdict, alerts, crash) {
  if (verdict.action === 'none') return 0;
  if (verdict.action === 'leave') {
    if (verdict.why === 'older-alert' || verdict.why === 'several') {
      console.log('==> The probe crashed, and a system alert that may not be its own is up, so every alert');
      console.log('    is left alone for whoever is at the Mac.');
    }
    return 0;
  }
  const when = ` at ${clock(crash.whenMs)}`;
  if (process.env.PHOTONZ_KEEP_CRASH_ALERT === '1') {
    console.log(`==> The probe's crash${when} left its "quit unexpectedly" alert up; PHOTONZ_KEEP_CRASH_ALERT=1 keeps it.`);
    return 0;
  }
  try { execFileSync('killall', ['UserNotificationCenter'], { stdio: 'ignore' }); } catch {}
  for (let i = 0; i < 30; i++) {
    const left = readAlerts().alerts.filter((id) => alerts.includes(id));
    if (!left.length) {
      console.log(`==> Closed the "Photonz (Probe) quit unexpectedly" alert the probe's crash${when} put up,`);
      console.log('    so it is not left over the person\'s work or holding the front from the next walk.');
      return 0;
    }
    execFileSync('sleep', ['0.1']);
  }
  console.log(`!! The probe's crash${when} put up a "quit unexpectedly" alert and it would not close.`);
  return 1;
}

const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
if (isMain) {
  const cmd = process.argv[2];
  if (cmd === 'mark') mark();
  else if (cmd === 'close') {
    const i = process.argv.indexOf('--wait');
    process.exitCode = close(i > 0 ? Number(process.argv[i + 1]) || 0 : 0);
  }
  else {
    console.error('usage: node Scripts/probe-crash-alert.mjs mark|close');
    process.exitCode = 2;
  }
}
