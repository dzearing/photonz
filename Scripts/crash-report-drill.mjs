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

// ---- 6b. the macOS fault that is not the app's ------------------------------
// The crash of 2026-09-25 23:22 ("Photonz Probe-2026-09-25-232258.ips") and
// three more like it: AppKit posting an accessibility notification to another
// app's observer (a window switcher watching every app) sent it to a port name
// that had died and been reused by a kernel object, and the kernel killed the
// app for it. Nothing of ours is on the stack but main(), so the old line read
// "EXC_GUARD in static PhotonzApp.$main()", which sends a person hunting in
// PhotonzApp.swift for a bug that is in macOS.
console.log('a macOS accessibility fault');
const axBody = {
  faultingThread: 0,
  exception: {
    type: 'EXC_GUARD', subtype: 'GUARD_TYPE_MACH_PORT', violations: ['INVALID_OPTIONS'],
    message: ' INVALID_OPTIONS on mach port 0 (guarded with 0x8001030400000011)',
  },
  threads: [{
    triggered: true,
    frames: [
      { symbol: 'mach_msg2_trap', imageIndex: 1 },
      { symbol: 'mach_msg', imageIndex: 1 },
      { symbol: '_XMIGPostNotification', imageIndex: 2 },
      { symbol: '_AXUIElementPostNotificationWithInfo', imageIndex: 2 },
      { symbol: '_NSAccessibilityNotify', imageIndex: 3 },
      { symbol: '-[NSApplication run]', imageIndex: 3 },
      { symbol: 'static PhotonzApp.$main()', sourceFile: 'PhotonzApp.swift', imageIndex: 0 },
      { symbol: 'Photonz_main', sourceFile: 'PhotonzApp.swift', imageIndex: 0 },
    ],
  }],
  usedImages: [
    { name: 'Photonz Probe', CFBundleIdentifier: PROBE },
    { name: 'libsystem_kernel.dylib' },
    { name: 'HIServices' },
    { name: 'AppKit' },
  ],
};
const DIR3 = fs.mkdtempSync(path.join(os.tmpdir(), 'photonz-crash-drill-ax-'));
fs.writeFileSync(path.join(DIR3, 'Photonz Probe-2026-09-25-232258.ips'),
  JSON.stringify(header('2026-09-25 23:22:53.00 -0700')) + '\n' + JSON.stringify(axBody));
r = readCrashReport(path.join(DIR3, 'Photonz Probe-2026-09-25-232258.ips'));
check('it is recognised as the known macOS fault', r && r.systemFault === 'macos-ax-notify', r && r.systemFault);
check('the line says it is macOS and not the app, and never blames main()',
  r && /macOS/.test(r.summary) && !/PhotonzApp/.test(r.summary), r && r.summary);
check('the detail carries the marker playtest.sh reruns on',
  crashLines(r).some((l) => l.startsWith('    Known macOS fault:')), crashLines(r));
const axRun = crashTimeMs('2026-09-25 23:22:51.00 -0700');
const staleAx = findCrashReportOrRecent({ dir: DIR3, bundleId: PROBE, sinceMs: axRun + 60000, fallbackSeconds: 600 });
check('a report that is not this crash\'s own never carries the rerun marker',
  staleAx && staleAx.stale && !crashLines(staleAx).some((l) => l.startsWith('    Known macOS fault:')), staleAx && crashLines(staleAx));
// The same guard anywhere else is not this fault: an app of ours sending to a
// bad port is our bug and must stay one.
const ownGuard = JSON.parse(JSON.stringify(axBody));
ownGuard.threads[0].frames.splice(2, 3, { symbol: 'MyPort.send()', sourceFile: 'MyPort.swift', sourceLine: 12, imageIndex: 0 });
fs.writeFileSync(path.join(DIR3, 'Photonz Probe-2026-09-25-232300.ips'),
  JSON.stringify(header('2026-09-25 23:23:00.00 -0700')) + '\n' + JSON.stringify(ownGuard));
r = readCrashReport(path.join(DIR3, 'Photonz Probe-2026-09-25-232300.ips'));
check('the same guard from our own code is not excused', r && !r.systemFault && /MyPort\.send/.test(r.summary), r && r.summary);
const segv = JSON.parse(JSON.stringify(axBody));
segv.exception = { type: 'EXC_CRASH', signal: 'SIGSEGV' };
fs.writeFileSync(path.join(DIR3, 'Photonz Probe-2026-09-25-232310.ips'),
  JSON.stringify(header('2026-09-25 23:23:10.00 -0700')) + '\n' + JSON.stringify(segv));
r = readCrashReport(path.join(DIR3, 'Photonz Probe-2026-09-25-232310.ips'));
check('nor is a different crash that happens to be in the same place', r && !r.systemFault, r && r.systemFault);
fs.rmSync(DIR3, { recursive: true, force: true });

// ---- 7. reading the stamp ---------------------------------------------------
console.log('the stamp on a report');
check('a zone behind UTC reads right', crashTimeMs('2026-09-18 01:22:38.00 -0700') === Date.parse('2026-09-18T08:22:38Z'));
check('a zone ahead of it does too', crashTimeMs('2026-09-18 10:22:38.00 +0200') === Date.parse('2026-09-18T08:22:38Z'));
check('nonsense is 0 rather than NaN', crashTimeMs('whenever') === 0);

// ---- 8. an AppKit exception the report lost the words of -------------------
// macOS 27 keeps the backtrace of an exception AppKit crashes the app over and
// drops its reason (the layout crashes of 2026-11-17 and 2026-11-19 both read
// "Messages:" and nothing else). The probe writes the reason down itself,
// keyed by pid (PlaytestExceptionRecorder), and the report picks it up here.
console.log('an AppKit exception the probe wrote down');
const DIR4 = fs.mkdtempSync(path.join(os.tmpdir(), 'photonz-crash-drill-exc-'));
const EXC = path.join(DIR4, 'exceptions.jsonl');
const layoutStamp = '2026-11-19 15:44:54.00 -0800';
const layoutBody = {
  pid: 4242,
  faultingThread: 0,
  exception: { type: 'EXC_BREAKPOINT', signal: 'SIGTRAP' },
  termination: { indicator: 'Trace/BPT trap: 5' },
  threads: [{ triggered: true, frames: [{ symbol: '+[NSApplication _crashOnException:]', imageIndex: 1 }] }],
  usedImages: [{ name: 'Photonz Probe', CFBundleIdentifier: PROBE }, { name: 'AppKit' }],
};
fs.writeFileSync(path.join(DIR4, 'layout.ips'),
  JSON.stringify(header(layoutStamp)) + '\n' + JSON.stringify(layoutBody));
const at = crashTimeMs(layoutStamp);
fs.writeFileSync(EXC, [
  // Same pid, a day earlier: a pid that came round again is not this crash.
  { pid: 4242, atMs: at - 86_400_000, name: 'NSRangeException', reason: 'an older crash', windows: [] },
  { pid: 9999, atMs: at, name: 'NSGenericException', reason: 'another process', windows: [] },
  'not json at all',
  { pid: 4242, atMs: at + 300, name: 'NSInternalInconsistencyException', reason: 'more Update Constraints passes than views',
    windows: [{ title: 'Noisy voice recording', frame: [40, 56, 100000, 1028], contentMinSize: [100288, 432], visible: true }] },
].map((l) => (typeof l === 'string' ? l : JSON.stringify(l))).join('\n') + '\n');
r = readCrashReport(path.join(DIR4, 'layout.ips'), { exceptionLog: EXC });
check('the reason the probe wrote down becomes the report\'s message',
  r && r.messages[0] === 'AppKit exception NSInternalInconsistencyException: more Update Constraints passes than views', r && r.messages);
check('with each window\'s size and minimum beside it',
  r && r.messages[1] === 'window "Noisy voice recording" 100000x1028 pt, minimum content 100288x432', r && r.messages);
check('and both reach the lines a walk prints',
  r && crashLines(r).some((l) => l.includes('more Update Constraints')), r && crashLines(r));
// The window that ran away, written when it happened, seconds before the crash.
fs.appendFileSync(EXC, JSON.stringify({
  kind: 'runawayWindow', pid: 4242, atMs: at - 4000, title: 'Noisy voice recording', frame: [100000, 1028],
  stack: [
    '0   Photonz Probe                       0x0000000102 closure #1 in static PlaytestExceptionRecorder.watchForARunawayWindow() + 120',
    '1   CoreFoundation                      0x000000018d __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__ + 148',
    '2   AppKit                              0x0000000191 -[NSWindow _setFrame:updateBorderViewSize:] + 1000',
    '3   AppKit                              0x0000000191 -[NSWindow setFrame:display:] + 40',
  ],
}) + '\n');
r = readCrashReport(path.join(DIR4, 'layout.ips'), { exceptionLog: EXC });
check('a window that ran away before the crash is named after the exception, with what resized it',
  r && r.messages[0].startsWith('AppKit exception') && r.messages[2] === 'window "Noisy voice recording" grew to 100000x1028 pt; the resize came from:'
    && r.messages[3] === '  AppKit -[NSWindow _setFrame:updateBorderViewSize:] + 1000' && r.messages.length === 5, r && r.messages);
r = readCrashReport(path.join(DIR4, 'layout.ips'), { exceptionLog: path.join(DIR4, 'missing.jsonl') });
check('no log is no message, not a failure', r && r.messages.length === 0, r && r.messages);
fs.rmSync(DIR4, { recursive: true, force: true });

// ---- test helper: a crash of the process Scripts/test.sh runs ---------------
// On 2026-11-22 a GitHub slice died on signal 11 and nothing said where. The
// helper has no bundle id and its own code is the test bundle out of .build,
// with no line numbers on a runner, so it is found by name and read by image.
console.log('a test helper that died');
const DIR5 = fs.mkdtempSync(path.join(os.tmpdir(), 'photonz-crash-drill-helper-'));
const helperBody = {
  faultingThread: 1,
  exception: { type: 'EXC_BAD_ACCESS', signal: 'SIGSEGV' },
  termination: { indicator: 'Segmentation fault: 11' },
  threads: [{ frames: [{ symbol: 'mach_msg2_trap', imageIndex: 2 }] }, {
    triggered: true,
    frames: [
      { symbol: 'swift_retain', imageIndex: 3 },
      { symbol: 'BrushEngine.stamp(at:)', imageIndex: 1 },
      { symbol: 'BrushDynamicsRenderingTests.whatTheHandSeesIsWhatLands(_:)', imageIndex: 1 },
      { symbol: 'Testing.Test.run()', imageIndex: 4 },
    ],
  }],
  usedImages: [
    { name: 'swiftpm-testing-helper', path: '/Applications/Xcode.app/Contents/Developer/usr/libexec/swift/pm/swiftpm-testing-helper' },
    { name: 'PhotonzPackageTests', path: '/Users/runner/work/photonz/photonz/.build/arm64-apple-macosx/debug/PhotonzPackageTests.xctest/Contents/MacOS/PhotonzPackageTests' },
    { name: 'libsystem_kernel.dylib' },
    { name: 'libswiftCore.dylib' },
    { name: 'Testing', path: '/Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks/Testing.framework/Testing' },
  ],
};
const helperAt = Date.parse('2026-11-22T08:43:33-00:00');
fs.writeFileSync(path.join(DIR5, 'swiftpm-testing-helper-2026-11-22-084333.ips'),
  JSON.stringify({ app_name: 'swiftpm-testing-helper', timestamp: '2026-11-22 08:43:33.00 +0000', name: 'swiftpm-testing-helper' }) + '\n' + JSON.stringify(helperBody));
// A probe crash in the same folder, newer, is never read as the helper's.
fs.writeFileSync(path.join(DIR5, 'Photonz Probe-2026-11-22-084400.ips'),
  JSON.stringify(header('2026-11-22 08:44:00.00 +0000')) + '\n' + JSON.stringify(renameBody));
r = findCrashReport({ dir: DIR5, bundleId: '', sinceMs: helperAt - 60000, processName: 'swiftpm-testing-helper' });
check('found by its process name, not the probe beside it', r && r.app === 'swiftpm-testing-helper', r && r.file);
check('the frames are the test bundle\'s, named without line numbers',
  r && r.frames.length === 2 && r.frames[1].symbol.startsWith('BrushDynamicsRenderingTests.'), r && r.frames);
check('the line says the signal and the test it died in',
  r && r.summary === 'EXC_BAD_ACCESS (SIGSEGV) in BrushEngine.stamp(at:) < BrushDynamicsRenderingTests.whatTheHandSeesIsWhatLands(_:)', r && r.summary);
check('a crash before this run is not this run\'s',
  findCrashReport({ dir: DIR5, bundleId: '', sinceMs: helperAt + 60000, processName: 'swiftpm-testing-helper' }) === null);
check('the probe is still found by its bundle as before',
  findCrashReport({ dir: DIR5, sinceMs: helperAt })?.app === 'Photonz Probe');
fs.rmSync(DIR5, { recursive: true, force: true });

fs.rmSync(DIR, { recursive: true, force: true });
fs.rmSync(DIR2, { recursive: true, force: true });
console.log(failures ? `\n${failures} FAILED` : '\nall ok');
process.exit(failures ? 1 : 0);
