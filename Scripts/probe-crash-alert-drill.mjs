#!/usr/bin/env node
// Drill for closing the probe's "quit unexpectedly" alert, and only that one.
//
// Closing an alert is killing the process that draws every system alert, so the
// thing that matters here is what it must NOT close: an alert that was up before
// the probe launched, an alert when the probe did not crash, and anything at all
// when there is no launch mark to judge by.
//
//   node Scripts/probe-crash-alert-drill.mjs
import { decide, crashesFrom, spent, parseLoggedCrashes } from './probe-crash-alert.mjs';

let failures = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (ok) { console.log('  ok   ' + label); return; }
  failures++; console.log(`  FAIL ${label}  got: ${JSON.stringify(got)}  want: ${JSON.stringify(want)}`);
};

// The probe launched when the newest window on the Mac was 735000.
const mark = { launchedMs: Date.parse('2026-10-03T14:01:30Z'), maxWindowId: 735000 };
const crash = { whenMs: Date.parse('2026-10-03T14:01:48Z'), summary: 'EXC_CRASH (SIGSEGV)' };

check('no alert on screen: nothing to do', decide({ mark, alerts: [], crash: crash }), { action: 'none' });
check('the probe crashed and its alert went up after the launch: close it',
  decide({ mark, alerts: [735262], crash: crash }), { action: 'close' });
check('an alert was up before the probe launched: leave it, even after a probe crash',
  decide({ mark, alerts: [734900], crash: crash }), { action: 'leave', why: 'older-alert' });
check('an old alert and a new one together: leave both, closing one closes the other',
  decide({ mark, alerts: [734900, 735262], crash: crash }), { action: 'leave', why: 'older-alert' });
check('a new alert but no probe crash since the launch: not the probe\'s, leave it',
  decide({ mark, alerts: [735262], crash: null }), { action: 'leave', why: 'no-probe-crash' });
check('no launch mark: nothing to judge by, leave it',
  decide({ mark: null, alerts: [735262], crash: crash }), { action: 'leave', why: 'no-mark' });
check('a mark with no window number: leave it',
  decide({ mark: { launchedMs: mark.launchedMs }, alerts: [735262], crash: crash }), { action: 'leave', why: 'no-mark' });
check('an alert numbered exactly at the mark was already there: leave it',
  decide({ mark, alerts: [735000], crash: crash }), { action: 'leave', why: 'older-alert' });

check('two new alerts: one of them is not the probe\'s, leave both',
  decide({ mark, alerts: [735262, 735270], crash: crash }), { action: 'leave', why: 'several' });

// The case that closed a drill alert on 2026-10-03: the probe crashed, its
// alert was dealt with, and THEN somebody else's alert went up. Once spent, the
// crash no longer counts, and the newest window moves past what was on screen.
const after = spent(mark, crash, 735265);
check('a spent crash moves the mark past it', after.crashesFromMs > crash.whenMs + 1000, true);
check('...and past the windows on screen at the time', after.maxWindowId, 735265);
check('...and keeps the launch it was made at', after.launchedMs, mark.launchedMs);
check('a fresh mark counts crashes from its launch', crashesFrom(mark), mark.launchedMs);
check('a spent mark counts crashes from after the spent one', crashesFrom(after), crash.whenMs + 1001);

// What ReportCrash writes for every crash, even past macOS's daily cap on
// reports (2026-10-03: "Log limit exceeded", no report, the alert up anyway).
const logged = parseLoggedCrashes([
  '2026-10-03 07:07:58.990 Df ReportCrash[66261:19f0bdcd] Formulating fatal 309 report for corpse[60681] Photonz Probe',
  '2026-10-03 07:08:01.120 Df ReportCrash[66261:19f0bdce] Formulating fatal 309 report for corpse[23440] Photonz Dev',
  '2026-10-03 07:08:02.000 Df ReportCrash[66261:19f0bdcf] Something else about Photonz Probe',
].join('\n'));
check('the log names the probe\'s crash, with its pid', logged.map((c) => c.pid), [60681]);
check('...at the time it was logged', logged[0]?.whenMs, new Date(2026, 9, 3, 7, 7, 58, 990).getTime());

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
