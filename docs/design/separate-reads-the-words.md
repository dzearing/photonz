# Should separating a screenshot hand you text, or a picture of text?

**Recommendation: no. Separate into Layers should keep handing back pictures, and
the reading should keep being something a person asks for.** But asking for it
should stop being a menu item nobody finds, and the shape that fixes that is
better than automatic reading in one way automatic reading cannot match.

Written 2026-09-16 for the queue task
`find-out-whether-separating-should-hand-you-text`. The numbers below were
measured, not estimated; re-derive them any time with

```
PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter SeparateAutoReadStudyTests
```

which is `Tests/PhotonzRenderTests/SeparateAutoReadStudyTests.swift`. It is off
in a normal test run because it is a hundred and ninety Vision passes.

## The question

Taking a screenshot apart is two commands. Separate into Layers gives you a
picture of every label; Turn into Text on one of them gives you the words. A
person who wants to change a label has to know the second command exists, find
it in the same menu, and run it once per label. The app even teaches the
two-step ceremony in its own refusal copy (`TextReading.Refusal.moreThanOneRun`:
"More than one run of text here. Separate into Layers first, then turn one run
into words").

So: should the first command simply hand over real text wherever the app is sure
enough?

## What was measured

Three real captures, both shapes on each: **A**, separating as it works today,
and **B**, separating that reads every run it is confident about. Release build,
this machine.

| capture | runs | separate | + read every run, spread over the cores | read | in a face the page does not contain |
| --- | --- | --- | --- | --- | --- |
| `settings-pane-2x` (1440×960) | 9 | 155 ms | 143 ms → **298 ms** | 9 of 9 (100%) | 0 |
| `app-window-2x` (2549×1800, this app) | 40 | 262 ms | 477 ms → **739 ms** | 31 of 40 (78%) | **4** |
| `dense-page-1x` (1800×1400, the dashboard) | 142 | 56 ms | 1910 ms → **1966 ms** | 82 of 142 (58%) | **13** |

Read one after another rather than across the cores it is 494 ms, 943 ms and
3643 ms, so spreading the work is worth about half.

Every one of those three captures is set in ONE family. The last column is
therefore pure error.

## Why the answer is no

### 1. The app's sureness does not tell right from wrong

This is the finding that decides it, because the task's question was "wherever
the app is sure enough".

On `app-window-2x` the four labels that came back in Helvetica Neue on a page
that contains no Helvetica Neue are **Corner Radius (0.78), Border 1 (0.81),
Offset (0.72) and Width (0.74)** — and the app called all four `matched`, its
confident verdict, rather than `fallback`. Meanwhile correct readings go down to
0.56.

So the wrong ones sit in the UPPER half of the confidence range:

- Filtering to `matched` only keeps all four errors and throws away eight
  correct readings.
- Raising the agreement bar until all four drop means a bar of 0.82, which keeps
  **three** of the thirty-one.

There is no threshold, and no provenance filter, that separates the good from
the bad. "Wherever the app is sure enough" has no setting.

### 2. The error is invisible until it is expensive

`queue/audits/2026-09-16-separate-reads-text-shape-a.png` and `-shape-b.png` are
the same corner of the same window, separated both ways. In A, "Border 1" and
"Border 2" are the same weight, and so are "Width" and "Offset", because that is
what the screenshot says. In B, "Border 1" is visibly heavier than "Border 2",
and "Offset" is visibly heavier than the "Width" above it. Two labels of one
style in one panel, come back as two different faces.

At a hundred percent on a whole window it is a few percent of stroke and most
people would scroll past it. That is the problem, not the consolation: nothing
tells them, and the app's main job is redlining, where the screenshot is
EVIDENCE. Measuring type off a separated layer would be measuring the app's
guess at it.

### 3. Getting out of it costs the whole separation

Folded into the command the reading lands in the same single mutation the
separation does (`PhotonzDocument.separateIntoLayers`), so undo stays one press,
which is the promise. But that cuts both ways: one press is also the ONLY way
out, and it takes back all fifty pieces to be rid of four wrong labels. The
alternative is to find and fix each one by hand, which first requires noticing
it.

Asked for per run, as today, the guess lands on the one label a person is
looking straight at, and one press takes back exactly that.

### 4. It makes the command everybody uses several times slower

155 ms → 298 ms, 262 ms → 739 ms, 56 ms → 1966 ms. `EditorState.separateIntoLayers`
already notes that "the next thing that pushes this past a second owes the
command a progress indicator", and a dense page pushes it to two. A command that
one person in ten wanted the words from would get slower for the other nine.

## What would be given up by saying no

Honestly: on a well-behaved pane it is lovely. `settings-pane-2x` reads nine of
nine, all in one family, and the composed page
(`queue/audits/2026-09-16-separate-reads-text-settings.png`) is indistinguishable
from the capture. If every screenshot were that pane, this would be a yes.

## What to do instead

The complaint behind the task is real and it is about DISCOVERY, not about
automation. Two things fix it, and neither of them guesses on anybody's behalf.

### The pill offers to read the words, once you have seen what came out

The separation already raises a pill saying what it found. It should offer
reading as an action there: one press, for the whole picture, landing in one
undo step. That is the same single press automatic reading would have cost, with
three differences that all favour it:

- It happens AFTER the person has seen the pieces, so it is a choice about a
  result they are looking at rather than something that happened to their
  screenshot.
- The command everybody uses stays as fast as it is.
- **The page can vote.** Reading the whole picture at once is the only shape in
  which the runs can be compared with each other, and the study measured what
  that is worth: make every run take the family that won the page, and accept it
  where that family still clears the bar, and the strays go to zero by
  construction, at a cost of **one** reading of thirty-one on `app-window-2x`
  and eight of eighty-two on the dense page. Per-run Turn into Text can never do
  this, because it only ever sees one run.

### Double clicking a separated label reads it and opens it for typing

**Landed 2026-09-16** behind `next-double-click-reads-a-label`, on by default in
Next. See `docs/design/separate-into-layers.md`, "Double clicking the label reads
it and opens it for typing".

Double click already means "I want to change these words" for a text layer. On a
separated run it should read the run first and then put the caret in it. The
cost is one reading (25 to 56 ms) on the one label being touched, the guess
lands where the person is looking, one press takes it back, and a refusal says
why exactly as it does today. That task,
`find-out-whether-a-label-inside-a-group-can-be-d`, built it, and settled its own
question on the way: a label inside a group could always be double clicked into
typing, and the walk that said otherwise was clicking three times into a field
that had already opened.

## What was rejected, and why

| shape | why not |
| --- | --- |
| Read every confident run inside the command | 4 of 31 wrong on this app's own window, 13 of 82 on the dashboard, silently, and three to thirty-four times slower |
| Read only where the app says `matched` | Keeps every one of the four errors and drops eight correct readings; confidence does not correlate with correctness here |
| Raise the agreement bar until the errors drop | The bar would be 0.82, which keeps three readings of thirty-one |
| Let the page vote on one family, then read automatically | The vote is a real improvement and should happen, but it makes the reader better, not the automation safer. It does not touch the speed, and it does not fix the weight wobble (Border 1 reads Medium while Corner Radius reads Semibold, both section labels of one style) |
| Do nothing at all | The discovery problem is real: the second command is a menu row under the first and nothing on the row or the pill points at it |

## Rough edges the study turned up

- **The weight wobble is the remaining inconsistency even with the family
  settled.** Six row labels of one settings pane come back four Regular and two
  Medium; two section labels of one panel come back Medium and Semibold. At 13
  points that is a few percent of stroke, and the measurement is honest about
  what it sees, but it is the least consistent part of the answer. Already
  recorded in `queue/audits/2026-09-13-turn-into-text`.
- **Six runs of the app window hold no words at all** (`noWords`): the sweep
  found them as runs and they are icons. Under any automatic shape they would
  quietly stay pictures, which is the right outcome and needs no message.
- **The dense page refuses 60 of 142 outright** (`noFaceMatches`). That is the
  feature working: it is a web page in a family the app cannot set.

## See also

- `docs/design/separate-into-layers.md` — the feature this is about
- `Sources/PhotonzCore/TextReading.swift` — the bar, the margin, the fallback
- `queue/audits/2026-09-16-separate-reads-the-words.json` — the audit
