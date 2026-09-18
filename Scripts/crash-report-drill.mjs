#!/usr/bin/env node
// Drill for reading what macOS wrote down when the app died.
//
// The words this produces are the words a sweep prints, and until 2026-09-18 a
// crash printed "no done.json", which is what a slow walk prints. So the
// things that matter here are: the line names the app's own code and not forty
// frames of Swift runtime, a report from LAST night is never read as the crash
// that just happened (macOS rewrites these files when it symbolicates them, so
// their mtime lies), and a file that makes no sense is skipped rather than
// taking the run down.
//
//   node Scripts/crash-report-drill.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  readCrashReport, findCrashReport, findCrashReportOrRecent, crashTimeMs, crashLines, walkLine, ago,
} from './crash-report.mjs';

let failures = 0;
const check = (label, ok, got) => {
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log('  FAIL ' + label + (got === undefined ? '' : '  got: ' + JSON.stringify(got)));
};

const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'photonz-crash-drill-'));
const write = (name, head, body) =>
  fs.writeFileSync(path.join(DIR, name), JSON.stringify(head) + '\n' + JSON.stringify(body));

const PROBE = 'com.dzearing.photonz.probe';
const header = (stamp, bundle = PROBE, app = 'Photonz Probe') => ({
  app_name: app, timestamp: stamp, bundleID: bundle, app_version: '0.15.0',
});
// The stack of the crash of 2026-09-17 night, trimmed from the real report
// ("Photonz Probe-2026-09-18-012238.ips"): renaming a layer read the document
// out of the same property the undo stack was being held exclusively for.
const renameBody = {
  faultingThread: 0,
  exception: { type: 'EXC_CRASH', signal: 'SIGABRT' },
  termination: { indicator: 'Abort trap: 6' },
  asi: { 'libsystem_c.dylib': ['abort() called'] },
  threads: [{
    triggered: true,
    frames: [
      { symbol: '__pthread_kill', imageIndex: 3 },
      { symbol: 'abort', imageIndex: 5 },
      { symbol: 'swift_beginAccess', imageIndex: 6 },
      { symbol: 'EditorState.history.getter', sourceFile: '/<compiler-generated>', imageIndex: 0, inline: true },
      { symbol: 'EditorState.document.getter', sourceFile: 'EditorState.swift', sourceLine: 913, imageIndex: 0 },
      { symbol: 'EditorState.readWordsForRows.getter', sourceFile: 'EditorState+RunWords.swift', sourceLine: 150, imageIndex: 0 },
      { symbol: 'closure #1 in EditorState.renameLayer(id:to:)', sourceFile: 'EditorState+LayersPanel.swift', sourceLine: 499, imageIndex: 0 },
      { symbol: 'History.perform(_:)', sourceFile: 'History.swift', sourceLine: 55, imageIndex: 0 },
    ],
  }],
  usedImages: [
    { name: 'Photonz Probe', CFBundleIdentifier: PROBE },
    { name: 'libobjc-trampolines.dylib' },
    { name: 'AGXMetalG16X' },
    { name: 'libsystem_kernel.dylib' },
    { name: 'libsystem_pthread.dylib' },
    { name: 'libsystem_c.dylib' },
    { name: 'libswiftCore.dylib' },
  ],
};

// ---- 1. what the line says --------------------------------------------------
console.log('the line a crashed walk prints');
write('Photonz Probe-2026-09-18-012238.ips', header('2026-09-18 01:22:38.00 -0700'), renameBody);
let r = readCrashReport(path.join(DIR, 'Photonz Probe-2026-09-18-012238.ips'));
check('it names what killed the app', r.summary.startsWith('EXC_CRASH (SIGABRT) in '), r.summary);
check('it names the app frame the crash was in', r.topFrame === 'EditorState.document.getter', r.topFrame);
check('and it reaches down to the thing the user did',
  r.summary.includes('EditorState.renameLayer(id:to:)'), r.summary);
check('a compiler-generated inline frame is not offered as a place to look',
  !r.frames.some((f) => f.symbol === 'EditorState.history.getter'), r.frames);
check('no runtime frame is mistaken for the app', !r.frames.some((f) => /pthread|abort|swift_/.test(f.symbol)), r.frames);
check('every frame says where to look', r.frames.every((f) => f.file && f.line), r.frames);
check('"abort() called" is not repeated as if it were news', r.messages.length === 0, r.messages);
check('the detail block ends with the report to open',
  crashLines(r).at(-1).endsWith('Photonz Probe-2026-09-18-012238.ips'), crashLines(r).at(-1));

// ---- 2. last night's crash is not this one ----------------------------------
// The trap this exists for: macOS rewrites a report when it symbolicates it, so
// an .ips from last night can carry this minute's mtime.
console.log('an older report is not read as the crash that just happened');
const OLD = 'Photonz Probe-2026-09-17-195842.ips';
write(OLD, header('2026-09-17 19:58:42.00 -0700'), renameBody);
fs.utimesSync(path.join(DIR, OLD), new Date(), new Date());
const runStarted = crashTimeMs('2026-09-18 01:22:00.00 -0700');
r = findCrashReport({ dir: DIR, bundleId: PROBE, sinceMs: runStarted });
check('the one from this run is the one found', r && r.when.startsWith('2026-09-18'), r && r.when);
const later = crashTimeMs('2026-09-18 02:00:00.00 -0700');
check('and a run that crashed nothing finds nothing, however fresh the files look',
  findCrashReport({ dir: DIR, bundleId: PROBE, sinceMs: later }) === null);

// ---- 3. somebody else's crash -----------------------------------------------
console.log('another app dying is not this app dying');
write('Xcode-2026-09-18-013000.ips', header('2026-09-18 01:30:00.00 -0700', 'com.apple.dt.Xcode', 'Xcode'), renameBody);
r = findCrashReport({ dir: DIR, bundleId: PROBE, sinceMs: runStarted });
check('the probe run does not claim Xcode\'s crash', r && r.bundleId === PROBE, r && r.bundleId);
check('and the dev app the user is playing in is never read either',
  findCrashReport({ dir: DIR, bundleId: 'com.dzearing.photonz.dev', sinceMs: runStarted }) === null);

// ---- 4. a crash with nothing of ours in it ----------------------------------
console.log('a crash with no app frame in it still says something');
write('Photonz Probe-2026-09-18-014000.ips', header('2026-09-18 01:40:00.00 -0700'), {
  ...renameBody,
  threads: [{ triggered: true, frames: [{ symbol: '__pthread_kill', imageIndex: 3 }] }],
});
r = readCrashReport(path.join(DIR, 'Photonz Probe-2026-09-18-014000.ips'));
check('it says the app crashed and that no frame was ours',
  r.summary === "EXC_CRASH (SIGABRT), no frame in the app's own code", r.summary);

// ---- 5. a file that makes no sense ------------------------------------------
console.log('a report that cannot be read takes nothing down');
fs.writeFileSync(path.join(DIR, 'Photonz Probe-2026-09-18-015000.ips'), 'not json at all\n{');
check('it is skipped', readCrashReport(path.join(DIR, 'Photonz Probe-2026-09-18-015000.ips')) === null);
r = findCrashReport({ dir: DIR, bundleId: PROBE, sinceMs: runStarted });
check('and the readable one beside it is still found', r && r.when.startsWith('2026-09-18'), r && r.when);
check('a folder with no reports in it is not an error',
  findCrashReport({ dir: path.join(DIR, 'nope'), bundleId: PROBE, sinceMs: 0 }) === null);

// ---- 6. the crash macOS did not write down ----------------------------------
// macOS writes ONE report per crash signature and skips repeats for a while:
// two runs of the same crashing walk 18 seconds apart left one report between
// them (2026-09-18 02:49). Saying nothing there would put us back where we
// started, and saying "this is your crash" would be the same lie in a new coat.
console.log('a repeat crash macOS did not write down');
// Its own folder: one report, from the run before this one.
const DIR2 = fs.mkdtempSync(path.join(os.tmpdir(), 'photonz-crash-drill-'));
fs.writeFileSync(
  path.join(DIR2, 'Photonz Probe-2026-09-18-012238.ips'),
  JSON.stringify(header('2026-09-18 01:22:38.00 -0700')) + '\n' + JSON.stringify(renameBody),
);
const secondRun = crashTimeMs('2026-09-18 01:23:00.00 -0700');
r = findCrashReportOrRecent({ dir: DIR2, bundleId: PROBE, sinceMs: secondRun, fallbackSeconds: 1800 });
check('the last report for this app is offered', r && r.when.startsWith('2026-09-18 01:22:38'), r && r.when);
check('and it is marked as not this crash\'s own', r.stale === true && Math.round(r.agoSeconds) === 22, r && r.agoSeconds);
check('the walk line says so before it says anything else',
  walkLine(r).startsWith('no report of its own; the crash 22s earlier was EXC_CRASH'), walkLine(r));
check('the detail says macOS skips a repeat, in so many words',
  crashLines(r).some((l) => /skips repeats/.test(l)), crashLines(r));
check('a report older than the window is not reached for',
  findCrashReportOrRecent({ dir: DIR2, bundleId: PROBE, sinceMs: secondRun, fallbackSeconds: 5 }) === null);
check('and a fresh report of its own is never called stale',
  findCrashReportOrRecent({ dir: DIR2, bundleId: PROBE, sinceMs: runStarted }).stale === undefined);
check('how long ago, roughly', [ago(3), ago(45), ago(600), ago(9000)].join() === '3s,45s,10m,3h');

// ---- 7. reading the stamp ---------------------------------------------------
console.log('the stamp on a report');
check('a zone behind UTC reads right', crashTimeMs('2026-09-18 01:22:38.00 -0700') === Date.parse('2026-09-18T08:22:38Z'));
check('a zone ahead of it does too', crashTimeMs('2026-09-18 10:22:38.00 +0200') === Date.parse('2026-09-18T08:22:38Z'));
check('nonsense is 0 rather than NaN', crashTimeMs('whenever') === 0);

fs.rmSync(DIR, { recursive: true, force: true });
fs.rmSync(DIR2, { recursive: true, force: true });
console.log(failures ? `\n${failures} FAILED` : '\nall ok');
process.exit(failures ? 1 : 0);
