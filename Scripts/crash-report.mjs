#!/usr/bin/env node
// Reads what macOS wrote down when the app died, and says it in one line.
//
// When a scripted walk ends because the app ABORTED, the walk leaves no
// done.json, which for a year read exactly like a walk that was merely slow:
// "no done.json". Four sweeps in a row called twenty-one crashes seven slow
// walks (2026-09-17 night), and the crash that caused them was found by a
// person reading a stack trace instead. So a run that ends badly now looks for
// the crash report macOS drops into ~/Library/Logs/DiagnosticReports within a
// second or two of the abort, and says what it says.
//
//   node Scripts/crash-report.mjs --since <epoch-ms> [--wait 8]
//   node Scripts/crash-report.mjs --file <report.ips>
//
// Prints the ONE LINE summary first and the detail indented under it, so a
// caller can take `head -1` and print the rest as it stands. Exits 0 when it
// found a report, 1 when there is none (which is itself news: the app went
// away without crashing).
//
// Drill: node Scripts/crash-report-drill.mjs
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

export const REPORTS_DIR = path.join(os.homedir(), 'Library', 'Logs', 'DiagnosticReports');
export const PROBE_BUNDLE_ID = 'com.dzearing.photonz.probe';

// A report is two JSON documents in one file: a one-line header, then the body.
function parseIps(text) {
  const nl = String(text).indexOf('\n');
  if (nl < 0) return null;
  try {
    return { head: JSON.parse(text.slice(0, nl)), body: JSON.parse(text.slice(nl + 1)) };
  } catch {
    return null;
  }
}

// "2026-09-18 01:22:38.00 -0700" is not something Date parses the same way
// everywhere, so spell it out. Returns epoch ms, or 0 when it cannot be read.
export function crashTimeMs(stamp) {
  const m = String(stamp || '').match(
    /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)? ?([+-]\d{2}):?(\d{2})$/,
  );
  if (!m) return 0;
  const [, y, mo, d, h, mi, s, zh, zm] = m;
  const iso = `${y}-${mo}-${d}T${h}:${mi}:${s}${zh}:${zm}`;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? t : 0;
}

const GENERIC_ASI = /^(abort\(\) called|Abort trap.*)$/;

// A frame the app's own code is in, as opposed to the fifty frames of runtime
// above it. The image index is the app's own binary; compiler-generated inline
// frames are dropped because "EditorState.history.getter" at
// "/<compiler-generated>" names nothing a person can go and look at.
function appFrames(body, appImageIndexes) {
  const thread = body.threads?.[body.faultingThread ?? -1]
    || body.threads?.find((t) => t.triggered)
    || null;
  const out = [];
  for (const f of thread?.frames || []) {
    if (!appImageIndexes.has(f.imageIndex)) continue;
    const file = f.sourceFile && !f.sourceFile.startsWith('/<') ? f.sourceFile : '';
    if (!file && !out.length && !f.symbol) continue;
    if (!file) continue;
    const symbol = String(f.symbol || '(unnamed)');
    if (out.length && out[out.length - 1].symbol === symbol) continue;
    out.push({ symbol, file: path.basename(file), line: f.sourceLine || 0 });
    if (out.length >= 6) break;
  }
  return out;
}

const shorten = (s, n) => (s.length <= n ? s : `${s.slice(0, n - 1)}…`);

export function readCrashReport(file) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return null;
  }
  const parsed = parseIps(text);
  if (!parsed) return null;
  const { head, body } = parsed;
  const bundleId = head.bundleID || '';
  const appImageIndexes = new Set();
  (body.usedImages || []).forEach((img, i) => {
    if (img.CFBundleIdentifier && img.CFBundleIdentifier === bundleId) appImageIndexes.add(i);
    else if (!img.CFBundleIdentifier && img.name && head.app_name && img.name === head.app_name) appImageIndexes.add(i);
  });
  const frames = appFrames(body, appImageIndexes);
  const exception = body.exception?.type || 'crash';
  const signal = body.exception?.signal || body.termination?.indicator || '';
  const asi = Object.values(body.asi || {})
    .flat()
    .map(String)
    .filter((m) => m && !GENERIC_ASI.test(m));
  const what = signal ? `${exception} (${signal})` : exception;
  const where = frames.slice(0, 3).map((f) => shorten(f.symbol, 60)).join(' < ');
  return {
    file,
    app: head.app_name || '',
    bundleId,
    when: head.timestamp || '',
    whenMs: crashTimeMs(head.timestamp),
    exception,
    signal,
    indicator: body.termination?.indicator || '',
    messages: asi,
    frames,
    topFrame: frames[0]?.symbol || '',
    // The one line a sweep prints on the walk's own line. It names the top
    // frame of the app's own code and the two under it, because the top frame
    // of a Swift abort is usually a getter and the frame that names the thing
    // the user did is the third one down.
    summary: where ? `${what} in ${where}` : `${what}, no frame in the app's own code`,
  };
}

// The newest report for this app whose crash is not older than `sinceMs`.
// Deliberately NOT by file mtime: macOS rewrites these files when it
// symbolicates them, so a report from last night can carry this minute's mtime
// and would be read as the crash that just happened.
export function findCrashReport({ dir = REPORTS_DIR, bundleId = PROBE_BUNDLE_ID, sinceMs = 0 } = {}) {
  let names = [];
  try {
    names = fs.readdirSync(dir).filter((n) => n.endsWith('.ips'));
  } catch {
    return null;
  }
  let best = null;
  for (const name of names) {
    const r = readCrashReport(path.join(dir, name));
    if (!r) continue;
    if (bundleId && r.bundleId !== bundleId) continue;
    if (r.whenMs && sinceMs && r.whenMs + 1000 < sinceMs) continue;
    if (!best || r.whenMs > best.whenMs) best = r;
  }
  return best;
}

// How long ago, in the roughest terms that are still true.
export function ago(seconds) {
  if (seconds < 90) return `${Math.max(1, Math.round(seconds))}s`;
  if (seconds < 5400) return `${Math.round(seconds / 60)}m`;
  return `${Math.round(seconds / 3600)}h`;
}

// The one line a sweep prints on the walk's own line. A report that is not this
// crash's own says so IN THAT LINE and never borrows its authority: describing
// a crash as something it might not be is the whole mistake this exists to end.
export function walkLine(r) {
  if (!r.stale) return r.summary;
  return `no report of its own; the crash ${ago(r.agoSeconds || 0)} earlier was ${r.summary}`;
}

// This run's own crash report, or failing that the last one macOS wrote for
// this app within `fallbackSeconds` before the run, marked as not this crash's
// own. The fallback exists because macOS writes ONE report per crash signature
// and then skips repeats: two runs of the same crashing walk 18 seconds apart
// produced one report between them (2026-09-18 02:49). A sweep of seven walks
// all dying the same way would otherwise say nothing about six of them.
export function findCrashReportOrRecent({ dir, bundleId, sinceMs, fallbackSeconds = 1800 } = {}) {
  const own = findCrashReport({ dir, bundleId, sinceMs });
  if (own) return own;
  if (!fallbackSeconds || !sinceMs) return null;
  const prev = findCrashReport({ dir, bundleId, sinceMs: sinceMs - fallbackSeconds * 1000 });
  if (!prev) return null;
  return { ...prev, stale: true, agoSeconds: Math.max(0, (sinceMs - prev.whenMs) / 1000) };
}

export function crashLines(r) {
  const lines = [walkLine(r)];
  if (r.stale) {
    lines.push(
      `    macOS wrote no crash report for THIS one. It writes one per crash signature and`,
      `    then skips repeats for a while, so what follows is the last report it did write,`,
      `    from ${ago(r.agoSeconds || 0)} before this walk. Treat it as the likely shape of the crash, not as proof.`,
    );
  }
  if (r.indicator) lines.push(`    ${r.indicator}`);
  for (const m of r.messages) lines.push(`    ${m}`);
  for (const f of r.frames) lines.push(`    ${f.symbol}  ${f.file}${f.line ? `:${f.line}` : ''}`);
  lines.push(`    Crash report: ${r.file}`);
  return lines;
}

// --- command line -----------------------------------------------------------
const isMain = process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(new URL(import.meta.url).pathname);
if (isMain) {
  const argv = process.argv.slice(2);
  const opt = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : fallback;
  };
  const file = opt('--file', '');
  const dir = opt('--dir', REPORTS_DIR);
  const bundleId = opt('--bundle', PROBE_BUNDLE_ID);
  const sinceMs = Number(opt('--since', 0)) || 0;
  const waitS = Number(opt('--wait', 0)) || 0;
  // How far back to fall back when this crash left no report of its own,
  // because macOS skips a repeat of a crash it has already written down. Found
  // the hard way: two runs of the same crashing walk 18 seconds apart produced
  // exactly one report between them.
  const fallbackS = Number(opt('--fallback', 1800)) || 0;
  let found = null;
  if (file) {
    found = readCrashReport(file);
  } else {
    // macOS takes a second or two to write the report, so a caller that
    // noticed the app vanish gets to wait a moment for the reason.
    const deadline = Date.now() + waitS * 1000;
    do {
      found = findCrashReport({ dir, bundleId, sinceMs });
      if (found || Date.now() >= deadline) break;
      // Synchronous sleep: this is a one-shot CLI with nothing else to do.
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 500);
    } while (Date.now() < deadline);
    if (!found) found = findCrashReportOrRecent({ dir, bundleId, sinceMs, fallbackSeconds: fallbackS });
  }
  if (!found) {
    console.error('no crash report');
    process.exit(1);
  }
  console.log(crashLines(found).join('\n'));
}
