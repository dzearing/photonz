# Your Mac locks at night, and while it is locked the app cannot be tested

## What this is about

The loop checks its own work by driving the app. There are about 425 short
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

The app is completely fine. The test is not. It reads a half-finished window and
reports what it found as though the app had produced it.

## What that cost, once

Your Mac locked at 8:46:47pm on 14 September. What happened next:

| When | What the test run said |
| --- | --- |
| 4:19pm, unlocked | 391 of 396 passed, all 31 tutorial runs passed |
| 8:42pm, locked four minutes in | Collapsed. Runs that take five seconds took a quarter of an hour |
| 12:09am, locked throughout | 115 of 400 "broken", including all 31 tutorial runs |

Nothing had changed in the app. The same code that passed in the afternoon was
checked out again and "failed" at night. Four separate times, the loop sent an
agent off to fix a bug that did not exist.

## What is already fixed, whichever way you answer

A run on a locked screen now says **"could not run"** instead of calling the app
broken. It is not a pass and it is not a failure. The full test sweep files
nothing from it, keeps its request, and does the real thing as soon as you
unlock. Launching the app for a look prints `screen locked` and says plainly
that nothing you see is a fact about the app.

So the false failures are gone regardless. **This decision is only about whether
any testing happens while you are asleep.**

## The three answers

### Keep it awake while the loop works (recommended)

While the loop is running, your Mac stops going to sleep and stops locking
itself. Testing carries on all night. The screen stays lit, and your Mac does
not lock itself during that time. Stopping the loop gives your Mac its normal
behaviour back at once.

Worth knowing: this only ever holds while the loop is actually running. It is a
power request, the same kind a video player makes while a film is playing, and
it can neither wake nor unlock a Mac that is already asleep or locked.

### Leave it alone, tests wait for you

Nothing about your Mac changes. Lock it and the testing stops, honestly and
loudly, and catches up the moment you unlock. A night with the Mac locked is a
night where nothing checks the app.

**Choosing this closes the question for good** rather than handing it back.

### Leave it alone, but tell me when it has gone blind

The same as leaving it alone, with one line on the dashboard saying how long it
has been since the app was last really tested. A quiet night becomes something
you can see rather than something you discover later.

## Where to look

- The dashboard, Project section: <http://127.0.0.1:8791>
- The reasoning in full, and what the one unnoticed night cost:
  `Sources/Photonz/Playtest/PlaytestScreenState.swift`
- How the test runs work: `docs/design/playtest-harness.md`
