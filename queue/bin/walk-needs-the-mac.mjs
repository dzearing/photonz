#!/usr/bin/env node
// Does this walk need the Mac to itself? Exit 0 (and name the steps) when it
// does, 1 when it does not.
//
// A walk runs without taking a person's keyboard, focus or screen since
// 2026-09-26 (queue/bin/focus-drill.sh): nothing it does activates the probe,
// its windows sit under every other app's, and a menu it only reads or picks
// from is never opened on screen. One thing cannot be done that way: a PICTURE
// of an open menu needs the menu really open, and an open menu takes every key
// press on the Mac until it closes. The same goes for a menu a walk opens with
// a real click on purpose. Those steps:
//
//   menuShot                          always a picture of an open menu
//   rightClick / panelMenu + "shot"   a picture of the menu it opened
//   panelMenu + "clicking"            opened by a real click, to prove the click opens it
//   panelMenu + "at"                  opened by a pointer click on its own face
//
// And one more that is not a menu: a REAL DRAG. SwiftUI starts a drag only in
// the active app, so `windowDrag` and `dragGrip` bring the probe to the front
// for the length of the drag and hand it straight back (PlaytestHarness,
// takeTheFrontForADrag). Measured 2026-09-26: with the probe in the back the
// ruler's scrub and a bar's end did nothing at all.
//
//   windowDrag / dragGrip / windowClick  the probe holds the front while the button is down
//   setup "front": true               the probe is the active app for the whole walk
//
//   queue/bin/walk-needs-the-mac.mjs <walk.json>
import fs from 'node:fs';

export function stepsThatNeedTheMac(walk) {
  const found = [];
  if (walk.setup && walk.setup.front === true) found.push('every step (setup front: the probe is the active app throughout)');
  (walk.steps || []).forEach((step, i) => {
    const n = i + 1;
    if (step.do === 'menuShot') found.push(`step ${n} (menuShot)`);
    else if (step.do === 'windowDrag' || step.do === 'dragGrip') found.push(`step ${n} (${step.do}, a real drag)`);
    else if (step.do === 'windowClick') found.push(`step ${n} (windowClick, a real click)`);
    else if ((step.do === 'rightClick' || step.do === 'panelMenu') && step.shot) found.push(`step ${n} (${step.do} with a picture)`);
    else if (step.do === 'panelMenu' && step.clicking) found.push(`step ${n} (panelMenu opened by a click)`);
    else if (step.do === 'panelMenu' && step.at) found.push(`step ${n} (panelMenu opened by a click on its face)`);
  });
  return found;
}

// Steps that run Ask's real model: a wait on Ask answering. Each loads the
// 23 GB chat model into a fresh probe and holds the GPU at 100% for a minute
// or more, which a person at the Mac feels (the user, 2026-10-25: "something
// is killing the cpu, the machine is kind of laggy"). They take no keys, so
// they are not a focus matter and the focus drill does not excuse them
// (`--focus-only`), but they wait for the person to step away like one, and
// inside a rotating check they are skipped and come round in the whole set.
export function stepsThatRunTheModel(walk) {
  const found = [];
  (walk.steps || []).forEach((step, i) => {
    if (step.do === 'waitFor' && (step.condition === 'askPhase' || step.condition === 'askSettled')) {
      found.push(`step ${i + 1} (waits on Ask's model, which loads 23 GB and holds the GPU)`);
    }
  });
  return found;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const focusOnly = process.argv.includes('--focus-only');
  const file = process.argv.slice(2).find((a) => !a.startsWith('--'));
  if (!file) { console.error('usage: walk-needs-the-mac.mjs [--focus-only] <walk.json>'); process.exit(2); }
  let walk;
  try { walk = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { process.exit(1); }
  const steps = stepsThatNeedTheMac(walk).concat(focusOnly ? [] : stepsThatRunTheModel(walk));
  if (!steps.length) process.exit(1);
  console.log(`needs the Mac to itself at ${steps.join(', ')}`);
  process.exit(0);
}
