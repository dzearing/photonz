# Your Mac locks at night, and while it is locked the app cannot be tested

## Why you are being asked this twice

You were asked a version of this on 15 September and it is still waiting. That
card offered three answers, and one of them, "tell me when it has gone blind",
was built on 17 September as a piece of work in its own right. It ships. The
dashboard already says how long it has been since the app was really tested.

So that card was offering you something you already have, and picking it would
have closed the question without changing anything. It has been taken down and
this one replaces it. The question underneath is unchanged and still open.

## What this is about

The loop checks its own work by driving the app. There are about 527 short
scripted runs ("walks"): each one opens a real window, presses real keys, drags
real things, and then reads what happened. They are the only thing that tells
the loop whether the change it just made broke something.

Reading the window is the part that matters here. It only works if the window is
really drawn on the screen.

## What a locked screen does

When your Mac locks, the login window covers everything else. macOS then stops
doing work for windows nobody can see: it stops laying them out, stops advancing
animations, never finishes attaching the names that let a test find a button,
and refuses to take a screenshot at all.

The app is completely fine. The test is not.

## What it has cost, twice now

**14 September.** Your Mac locked at 8:46pm. At 4:19pm, unlocked, 391 of 396
runs passed. At 12:09am, locked, 115 of 400 were "broken", including all 31
tutorial runs, on exactly the same code. Four separate times the loop sent an
agent off to fix a bug that did not exist.

**15 to 18 September.** The screen was locked for three days. In that window the
loop built and audited four separate pieces of the video cutting feature and
shipped all four on unit tests alone. Every one of those four audits said so in
its own words: "NOTHING HERE WAS PHOTOGRAPHED", "nobody has felt this", "that is
now three video tasks in a row nobody has looked at". Then you opened the app,
trimmed a recording, pressed Save, and Save was greyed out. That is now the only
critical item in the queue.

The false failures from the first story are fixed and stay fixed whichever way
you answer. The second story is what this card is about, and nothing in the
queue fixes it.

## The three answers

### Keep it awake while the loop works (recommended)

While the loop is running, your Mac stops going to sleep and stops locking
itself. Testing carries on all night. Stopping the loop gives your Mac its
normal behaviour back at once.

Worth knowing: this only ever holds while the loop is actually running. It is a
power request, the same kind a video player makes while a film is playing, and
it can neither wake nor unlock a Mac that is already asleep or locked.

### Keep it awake only while the tests are running

Your Mac locks and sleeps exactly as it does today. The single exception is the
full test run itself, which takes about an hour and a half for the whole set: it
holds the Mac awake for its own length and then lets go.

The catch is that a run can only start if the Mac happens to be unlocked when
the loop comes round to asking for one. So this buys you finished runs rather
than more of them.

### Leave my Mac alone

Nothing changes. Lock it and the testing stops, honestly and loudly, and catches
up the moment you unlock. A night with the Mac locked is a night where nothing
checks the app.

**Choosing this closes the question for good** rather than handing it back.

## Where to look

- The dashboard, Project section: <http://127.0.0.1:8791>
- What a locked screen does to a walk, in full, with the list of which step
  kinds survive it: `Sources/PhotonzCore/PlaytestLockSafety.swift` and
  `Sources/Photonz/Playtest/PlaytestScreenState.swift`
- How the test runs work: `docs/design/playtest-harness.md`
