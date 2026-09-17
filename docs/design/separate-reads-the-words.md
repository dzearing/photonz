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

**Landed 2026-09-17** behind `next-read-every-label`, on by default in Next. See
`docs/design/separate-into-layers.md`, "The line offers to read every label at
once".

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
  and five of eighty-two on the dense page.

  **Landed 2026-09-17** behind the queue task
  `a-label-read-back-into-text-keeps-the-face-the-r`, and it turned out Turn into
  Text can have it too. The vote does not need the whole page READ — it needs a
  dozen runs asked what family they are, which is a tenth of a second spread over
  the cores, paid once per separation. So one label turned into text on its own
  now comes back in the face the rest of its page is in, and where there is no
  page to ask it decides for itself exactly as it did. See
  `docs/design/separate-into-layers.md`, "The page it came from settles the
  family".

### The rows say their words, even though the canvas does not

**Landed 2026-09-16** behind `next-a-separated-row-says-its-words`, on by
default in Next. See `docs/design/separate-into-layers.md`, "A separated row
says the words in its picture".

Saying no to automatic reading is about what goes ON THE CANVAS: a guess set in
the wrong face is evidence nobody can tell is a guess. A NAME is not that. It
costs no undo step, it is never saved, a wrong word in a list is a wrong word in
a list, and the half of the reading this study found unreliable — the face — is
not asked for at all. So the rows read, the canvas does not, and the two answers
agree with each other rather than contradicting.

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

### One page, one weight per kind of label

**Landed 2026-09-17** behind the queue task
`a-label-read-back-into-text-comes-back-in-the-we`. No flag: it is part of how
the reader answers.

The family vote settles half of the face. The other half wobbled for the same
reason, and it was MORE visible once the whole page came back at once: two
weights of one family are a few percent apart at label size, so a run deciding
alone comes back Medium beside an identical label that came back Regular. On
`settings-pane-2x` two of the six row labels did, and they did it confidently:
"Launch at login" scored Medium 0.795 against Regular 0.720, a lead wider than
`distinctMargin`, so no bar and no provenance filter could tell it from a label
that really is heavier.

**The vote could not be the page's**, though, and that is the whole design. A
page is one family; a page is not one weight. A page-wide vote would have
dragged "General" down to the weight of the rows under it, which is a worse
answer than the wobble, because somebody hands a redline over and acts on it.

So the vote is per KIND of label, and the two things the app already measured
that say what kind a label is are **how big it is** and **what colour its ink
is**:

- The size is taken at the family's LIGHTEST weight, so the size a run is
  grouped by does not depend on which weight happened to win it.
- Labels join a cohort smallest first, each needing a member within 3 per cent
  of its size and 2/255 of its ink, and no cohort may span more than 8 per cent
  of size. The span cap is what stops a page whose labels step up a little at a
  time — a row, a subhead, a head, a title — chaining into one cohort.
- A cohort settles on the weight with the highest TOTAL agreement across it,
  not the most hands. Two runs picking Medium by a thousandth and one picking
  Regular by a fifth are three runs that agree on Regular.

Colour is what carries the case the audits named. In this app's own Effects
panel, "Corner Radius", "Border 1" and "Border 2" are #EAEAEB and the "Style",
"Color", "Position", "Width" and "Offset" rows under them are #7C7C7C, at the
same size. A person can see at a glance which labels are meant to match, and so
can the reader: the sections settle on one weight, the rows settle on a lighter
one, and neither is flattened into the other.

**The weight is never a reason to lose a reading.** Where the cohort's weight
cannot account for a run's ink at all, the run is settled on its family alone,
the way it was before there was a weight vote. That escape is not a
compromise — it is the case it exists for: the bold key cap in this app's own
hint line scores 0.72 bold against 0.52 semibold, and it keeps its bold while
the two runs beside it settle together. Measured on all three study captures,
the reading counts are unchanged: 9 of 9, 30 of 40, 74 of 142.

It is also FASTER than what it replaced, because it forced the reader apart into
the half that costs (the recogniser, the ink, the thirteen faces scored) and the
half that does not (choosing among faces already scored, and fitting the winner
at the layer's size). The page is measured once and settled twice, where before
it was read once and the strays READ again. Spread over the cores on
`dense-page-1x`: **1812 ms against the 1966 ms** the family vote alone cost.

### One kind of label, one size

**Landed 2026-09-17** behind the queue task
`a-label-read-back-into-text-comes-back-at-the-si`. No flag, like the two votes
above it.

The weight vote left the last of the wobble showing. Picking the six row labels
of the settings pane made the Weight menu say Regular and the Size menu say
Mixed, because each run is fitted to its own ink and which glyphs a run happens
to contain moves that about: 27.6, 28.0, 28.5, 28.0, 28.5 and 28.4 points for
six labels that are 13 points on screen. Anybody who then set a size was tidying
up after the app.

The cohorts are the ones the weight settled on, so a heading is not one of its
rows and a white section label is not one of its grey ones. What is different is
the ANSWER a cohort gives, because a size is not one of four things to vote on:

- **The middle of what they fit**, not the average, so the one label whose ink
  was measured badly cannot drag the other five off the size they plainly are.
  It is also the size they agree with best, measured: on the settings pane's six
  rows the middle scores 4.571 total against the nearest whole point's 4.204,
  and on the Effects panel's rows 4.484 against 4.484. There is nothing to be
  gained by searching for a better one, and a search costs a render per label
  per candidate.
- **Settled in the size the layer is SET at**, not the size the face was
  identified at. Those two are not one number divided by the other: rendering
  the same words at a different scale moves the ink by an antialiased edge
  either side, which on this fixture is a 6 to 10 per cent difference, per run.
  A run drawn at its own scale is multiplied back up by that scale so it is
  still comparable with the labels beside it.
- **Not rounded to a whole point**, tempting as that is. Holding those six rows
  to 28 rather than 28.38 puts "Copy to clipboard" 3 pixels short of the ink it
  replaces and drops its agreement to 0.502, under `landedBar`, so the label
  meant to come back tidy comes back not at all. The Size menu says whole points
  anyway, so all six read "28 px": one number, which is what was asked for.
- **Never a reason to lose a reading**, exactly as the weight is not. A run
  whose ink the settled size cannot account for keeps the size it fitted itself
  at, and a run held to its own heavier face is neither counted nor answered,
  because a heavier face reaches the same ink height at a smaller size.

The Effects panel is the case that says this settles wobble rather than
flattening a page: its section labels come back at 23.03 and the rows under them
at 22.22, each group agreeing with itself.

**A box exactly as wide as its words was a hairsbreadth from being cut.** Found
landing this, and older than it: a label's box is measured for its own words, the
canvas states that box in output pixels and the rasterizer divides it back, and
`w * zoom / zoom` is not always `w` in binary floating point. One ulp short was
enough for `TextRasterizer.truncating` to cut "Show in menu bar" down to "Show in
menu b…" on the canvas at 151% while it read whole at 150%. It now allows a
hundredth of a point of shortfall, which is far more than any round trip can lose
and far less than anybody can see.

## What was rejected, and why

| shape | why not |
| --- | --- |
| Read every confident run inside the command | 4 of 31 wrong on this app's own window, 13 of 82 on the dashboard, silently, and three to thirty-four times slower |
| Read only where the app says `matched` | Keeps every one of the four errors and drops eight correct readings; confidence does not correlate with correctness here |
| Raise the agreement bar until the errors drop | The bar would be 0.82, which keeps three readings of thirty-one |
| Let the page vote on one family, then read automatically | The vote is a real improvement and HAS happened (2026-09-17), and so has the weight vote beside it, but both make the reader better rather than the automation safer. Neither touches the speed |
| Do nothing at all | The discovery problem is real: the second command is a menu row under the first and nothing on the row or the pill points at it |

## Rough edges the study turned up

- **The family is settled as of 2026-09-17.** The last column of the table above
  is no longer the state of the app: the runs of a capture vote on their family
  and every run is set in it, so `app-window-2x` reads 30 of 40 with none off the
  page's family and `dense-page-1x` reads 77 of 142 with none off it. The counts
  in this document are what reading each run ON ITS OWN gave, which is what the
  study was about.
- **The weight is settled as of 2026-09-17 too**, by a vote of its own. See
  "One page, one weight per kind of label" below. Before it, six row labels of
  one settings pane came back four Regular and two Medium, and the section
  labels of one panel came back Semibold, Medium and Medium.
- **And the size, later the same day.** See "One kind of label, one size". Before
  it, those same six row labels came back at six different sizes between 27.6
  and 28.5 points, and the Size menu read Mixed for them.
- **Six runs of the app window hold no words at all** (`noWords`): the sweep
  found them as runs and they are icons. Under any automatic shape they would
  quietly stay pictures, which is the right outcome and needs no message.
- **The dense page refuses 60 of 142 outright** (`noFaceMatches`). That is the
  feature working: it is a web page in a family the app cannot set.

## See also

- `docs/design/separate-into-layers.md` — the feature this is about
- `Sources/PhotonzCore/TextReading.swift` — the bar, the margin, the fallback
- `queue/audits/2026-09-16-separate-reads-the-words.json` — the audit
