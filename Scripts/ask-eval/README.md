# The Ask and skill eval

A fixed set of requests, run through Ask (the app's own, on the local model)
or through the Photonz skill (a fresh agent session with only the skill and the
Photonz MCP server). Each result is read back and photographed, then scored. A
change to Ask's prompt, the skill or the tools is kept when the score goes up
and thrown away when it goes down.

```bash
Scripts/ask-eval.sh run --engine ask --tag "what changed"     # about 11 minutes
Scripts/ask-eval.sh run --engine skill --tag "what changed"   # about 24 minutes
Scripts/ask-eval.sh run --engine ask --cases dog,smiley-icon --tag "..."   # just these
Scripts/ask-eval.sh compare                  # the last run against the best before it
Scripts/ask-eval.sh compare <run> --with <run>
Scripts/ask-eval.sh history
Scripts/ask-eval.sh run --engine ask --set held-out --tag "..."   # the held-out set, totals only, about 20 minutes
Scripts/ask-eval.sh report                   # the latest climb and held-out totals, and the lookup line
Scripts/ask-eval.sh feedback                 # thumbs down from the apps become held-out cases
Scripts/ask-eval.sh calibrate                # the judge against the user's own verdicts
Scripts/ask-eval.sh rescore <run> [--cases a,b]   # score saved results again
Scripts/ask-eval.sh sheet <run>              # draw a run's contact sheet again
Scripts/ask-eval.sh lines <run> [--with <run>]   # a run's judge lines in total: clean, designed, didWhatWasAsked, crafted
Scripts/ask-eval.sh run --engine ask --on next-ask-paints-drawings --tag "..."   # with a switch on that Next has off
```

`--on <switch>,<switch>` turns on switches that are off at Next defaults for
every case of the run (a try measured before it is anybody's default, such as
"Ask paints its drawings" before it was on at Next defaults). The run says so when it
starts and the history records them as `switched`, so it never reads as the
default app. `lines` prints the judge's lines as means over a run's drawing
cases and over all its cases, with the median seconds a drawing request took;
it is a total, so it works on held-out runs too, and every run records it.
`time <run> [<run> ...]` prints, per group, how many cases ran out of their time
limit or stopped part way and the median seconds and steps of a plan, also a total: a case still
planning at its limit has made nothing and scores 0, so read this before reading
a group's swing as Ask getting better or worse.

`--minutes N` stops starting new cases after N minutes and prints the
`--resume <run>` line that carries on. That is how a go loop runner, whose
commands stop at ten minutes, gets a whole run done in pieces. A run goes into
the history only when every case in it has run. Until then its total counts
each case not run as 0, so the run prints UNFINISHED and how many are left
above that total: it is not the run's score (Qwen3.5 9B read 19.8 with three
cases put off for a person at the Mac, and 21.2 once they ran).

`--models <id>,<id>` lends the probe only those built-in models and no picture
model, to measure one model as a smaller Mac would hold it. `--mac <GB>` plans
as a Mac of that size (its window and what it holds): a 16 GB Mac reads a 32k
window where this Mac reads 64k, so a model offered to small Macs is rated with
`--models <id> --mac 16`. Both are kept with the run, so `--resume` keeps them.

## What a run does, per case, one case at a time

1. A walk opens the case's starting document on the probe (never the dev app),
   at Next defaults, with every setting forgotten.
2. The engine works on it.
   * `ask`: the walk presses Ask, types the request, sends it and waits for Ask
     to finish (`askPhase` ran or stopped, 300 s at most). Ask's own time from
     send to done is the case's `seconds`.
   * `skill`: `claude -p` in an empty folder with `--plugin-dir plugin`, only
     the Photonz server (`--strict-mcp-config`, pointed at the probe), no
     settings, no shell, no web, no file writing. The prompt is the request
     word for word plus one line saying what is open in Photonz (Ask knows that
     from the app; an agent would otherwise have to guess). 360 s at most, 480 s
     for the sheet and pricing cases. The session's wall time is `seconds`.
3. The result is read over the MCP bridge (`read_document`, and `render_picture`
   for the picture). An agent that opened a new document (an icon canvas) is
   scored on the newest one it made.
4. The probe is quit.
5. Rules and the judge score it (below). Everything lands in
   `.ask-eval/runs/<run>/<case>/`: `result.png`, `read.json`, `score.json`, the
   walk, and for the skill the session's `transcript.jsonl`
   (`Scripts/agent-transcript.mjs` turns it into markdown). Runs are not
   committed; their scores are, in `queue/evals/ask-eval-history.jsonl`.

The screen must be unlocked: Ask is found by name, which a locked screen takes
away. A run that meets a locked screen stops and says so, and `--resume` picks
it up.

## The score, 0 to 100

* **Rules** (0 to 10), read from the document, never the picture
  (`rules.mjs`, tests in `rules.test.mjs`, `node --test Scripts/ask-eval/rules.test.mjs`):
  * on the canvas: each thing off it costs 3;
  * words that overlap other words, a control, or half of a shape: each costs
    2.5 (words wholly inside a shape are on a backdrop, which is fine);
  * one type scale: more than four sizes costs 2.5 a size, more than four
    weights or two fonts 2 each;
  * alignment: how many cells share an edge or a centre with another across and
    down, and how even the gaps (or the steps) are along each row and column
    of three or more;
  * a drawing is centred and a sensible size (a backdrop over the whole canvas
    is not counted as the drawing);
  * what was asked: the case's own checks (`expect` in its file): a title that
    is the largest words and sits above, state headers, labelled rows, enough
    cells, prices, the parts of a face inside the face, ears and legs touching
    the body, an icon that is square, no words on a drawing that needed none,
    how many measurements.
  The rule score is the mean of the rules that apply.
* **The judge** (0 to 10): `rubric.md`, five lines (clean, typography, aligned,
  designed, did what was asked), each 1 to 10, typography left out for a
  wordless drawing. Nine looks at once (`JUDGE_LOOKS`), each line the mean of
  them, then the mean of the lines. Until 2026-11-09 it was three looks and each
  line's median; see "How steady a reading is" below for why that changed.
  The judge is `claude-opus-5-5` in a fresh `claude -p` session that can only
  read the picture: it never sees the request's transcript, the read document or
  who made it.
* **Named blind** (drawings only, 0 to 10): `naming.md`, nine looks with no hint
  of the request; each look that names it as one of the case's `names` is a
  ninth. A drawing whose own words spell its name gets no credit for naming
  (the user's dog had "Dog" written over it).

A drawing's score is 3 x rules + 4 x judge + 3 x named; anything else is
4 x rules + 6 x judge (and a drawing with no `names` to check, one saved from
a vote, too). **Then, when the judge's didWhatWasAsked is under 7, the whole
score is scaled by didWhatWasAsked / 7** (`scoring.mjs`): the stock cat drawn
for "a cat curled up sleeping" is clean, aligned and named "cat" blind, and
without this scored about 85 while doing nothing the request asked. Nothing
made scores 0. The run's total is the mean of
its cases. One case read twice can still differ by two or three points (below),
so read a change that size on one case as noise.

The rubric, the naming prompt, the judge model and the way looks are combined
(`JUDGING`) together have an id (`rubric` in the history). Runs are only
compared with runs of the same engine on the same id; change the rubric and the
old runs stop being the bar. Each run also records its `looks`: a run made with
`--judge-runs 3` to save time is on the same id but reads far less steadily.

### How steady a reading is

On 2026-11-09 the same balloon icon, the very same file, read 85.6, 84.0, 71.3,
72.0, 71.3 and 69.9 in six runs inside an hour, under the old judging (three
looks, each line's median). It looked like a drift downward through the hour.
It was not the time of day, the sheet or the judge changing. It was sampling,
made fourteen times bigger by two things in how the score was put together:

* **The picture sits between two whole numbers.** The judge gave its
  didWhatWasAsked 7 in about a third of its looks and 6 in the rest (20 of 66
  looks at 7 that evening, the same third at 16:56, at 17:35 and at 17:55). The
  median of three looks is then 6 three times in four and 7 one time in four,
  never anything in between.
* **didWhatWasAsked under 7 scales the whole score** (by 6/7 when it is 6). So
  one line moving one step took the case from 85.6 to about 72, a cliff of
  fourteen points, where every other line moving one step moves it by under
  one.

The first two runs simply drew 7 and the next four drew 6. Taking more looks
does not cure a median: simulated from 90 real looks at the balloon, six
readings landed within 5 points of their own mean only 11% of the time with the
median of three, 26% with the median of nine and 42% with the median of
fifteen, because a median still has to come out 6 or 7. A mean does not:
the mean of three gets 28%, of six 72%, of nine 90%, of twelve 97%. So the
judge takes nine looks and each line is their mean, and a picture read at 6.3
reads 6.3, scaled by 6.3/7, every time. Six readings of the balloon under the
new judging (17:59 to 18:03, one of them a whole `run` of the case end to end)
read 75.6, 73.9, 75.6, 73.9, 75.6 and 73.9: a mean of 74.8, none more than
0.9 from it. The nine looks run at once, so a case takes about ten seconds
more of judging, not a minute.

Two more things the evening showed:

* **A picture drawn again by another renderer is not the same picture to the
  judge.** A lab copy of the balloon, drawn from its SVG by a separate tool,
  differs from the eval's own sheet in about 200 edge pixels of 686,000. The
  judge gave the lab copy 7 in two looks of three (77 of 120) and the eval's
  copy 7 in one of three, judged side by side at the same minute. A picture
  that sits on a line's edge tips on detail that small. So a reading taken in a
  lab is a guide, and the number that decides is a reading of the eval's own
  sheet.
* **The best past run is a lucky one.** `compare` sets a run against the best
  before it, and under medians the best was the reading that drew the high
  side of a coin flip (the 85.6 above). That is one more reason the change of
  judging is a new rubric id: no old median reading is the bar for a mean.

## Video cases

A `video` case (since 2026-10-21) starts on the sample recording, eight
seconds of a folder being copied (quiet until 2 s, copying until 6 s, quiet
again), and is scored from what plays, never the document alone:

* `start` is `{ "sample": "recording" }`, with `"clicks": true` for the
  pointer and two clicks a recorder keeps (at 2 s and 2.6 s, what zooms are
  suggested from), and `"copies": n` to lay the sample n more times end to end
  (over the bridge, before Ask is asked). A case's `setup` goes into the walk's:
  `{ "history": 6 }` gives History six made-up captures, the newest recording
  being "Recording 0002", two pictures newer than it.
* After the run, a small frame every quarter second (`video_frame`, drawn the
  way export draws) is marked blank or not by `frame-stats.swift`, and kept in
  `read.json` as `playback`. `result.png` is a contact sheet of frames spread
  across the video and at the start, middle and end of every transition, each
  labelled with its time, the header listing the cuts and their transitions.
* **Rules** for a video: on the canvas; `plays`, no blank frame while it plays
  (each costs 3: a blank on a recording outside a transition, at a moment
  nothing plays, or a title bare for half a second; a title's bare background
  for a moment before its words come in is fine); and what was asked (`expect`):
  `recordings` (how many play), `titles` (title pages or cards with those
  words, in that order), `titlesBefore` (title i just before recording i),
  `sameLook` (the titles share every style but their words), `cut`
  (`near`, `within`, `transition`: a cut inside a recording), `zooms`,
  `after` (`clip` starts once `follows` ends), and `length` ([shortest,
  longest] in seconds).
* **The judge** reads the sheet against `rubric-video.md`: clean,
  typography, flow (in place of aligned), designed, didWhatWasAsked. There is
  no blind naming. The score is 4 x rules + 6 x judge, scaled by
  didWhatWasAsked like everything else.

## Icon cases

An `icon` case (since 2026-11-04) is a request for an icon. It is scored like a
drawing, with `expect.iconCraft` in place of `composed` (`rules.mjs`,
`iconCraft`): a square canvas of its own, vector parts only, 20 parts at most,
each named for what it is, one stroke weight, centred with even padding.
`ownPicture` is a case started on somebody's work: the icon must not be in that
document. Its `reference` names how SF Symbols, Lucide and Material Symbols draw
something comparable, and the judge reads a sheet (`icon-sheet.swift`), not the
bare picture: the icon large, at 64, 24 and 16 pixels on light and on dark, and
those references, with one more line, `readsAsIcon` (`rubric-icon.md`, kept out
of the rubric id so nothing else stops comparing). SF Symbols are drawn from the
Mac; the other two are fetched once into `.ask-eval/references/` and only ever
reach the judge. `lines <run>` prints the line's mean under `icon`.

## Animated icon cases

An `animated` case (since 2026-11-06) is a request for an icon that moves. It is
judged on the file that leaves the app, never the document: the run exports the
SVG and `svg-frames.swift` plays it in WebKit, photographing 16 moments across
one lap, so `result.png` is frames and `reel.gif` the reel. Rules: `iconCraft`,
plus `moves` (`rules.mjs`): keys in the document, motion in the file, no frames
all alike, nothing the file left still, no jump at the loop. The judge reads the
frames against `rubric-animated.md`, its own rubric kept out of the rubric id:
didWhatWasAsked is "the motion reads as what was asked" and `loops` is whether it
loops cleanly. `lines <run>` prints both under `animated`. There is no blind
naming: a word for a still does not name a motion. The score is 4 x rules +
6 x judge, scaled by didWhatWasAsked like everything else.

Tweaks are two-turn cases with `"motion": true` in `followups/`: both files are
filmed the same way and judged side by side with each lap's length, and a pass
also needs one Command Z to bring the first file back byte for byte.

## The held-out set

`held-out/` is 53 requests a runner never climbs on (2026-10-20, after Ask
reached 92 on the drawing cases mostly by looking nouns up in its built-in
set, while the user found it drew one cat for every cat request):

* the user's own failures to date ("draw a cat curled up sleeping", "draw a
  piano with a cartoon cat playing it");
* poses, scenes (things doing something together), styles named in the
  request;
* edits of an existing drawing, started from a document Ask made and saved by
  a thumbs vote (`held-out/starts/*.photonz`);
* icons, layouts and redlines on screenshots;
* video edits of the sample recording (2026-10-21);
* eight animated icon requests (`animated-h1` to `animated-h8`, 2026-11-08),
  written by an agent that never saw Ask's prompt or the climb set's animated
  cases, told only to vary the kind of motion and to keep off the twelve
  subjects the climb set animates;
* and every thumbs down a person gives one of Ask's rows: the app saves the
  request, the document before and what it made under
  `~/Library/Application Support/<bundle id>/Ask feedback/`, and `feedback`
  (run by itself at the start of every held-out run) copies each new one in as
  `held-out/use-<when>-<request>.json` started from that very document. The
  probe's own votes are walks, not people, and are left out. A thumbs up is
  counted, not added.

**The rule: a runner reads the held-out set in total only.** A held-out run
prints no case, its request or its score, draws no contact sheet, refuses
`--cases`, and goes into the history as a total, its groups and its lookup
line with no per-case scores. Its pictures are kept in
`.ask-eval/held-out-runs/<run>/` for a person to look at (`sheet <run>` draws
them); a runner never opens that folder or `held-out/`, and never moves a
held-out request into `cases/`. The one exception is an audit for the user:
after the last change is made and measured, the final run's sheet may be
drawn where it is and its path named in the audit (never copied into
`queue/audits/`, which every runner reads), and nothing is changed after
looking at it. Work on Ask reports both numbers
(`report`); a climb that does not move the held-out total did not make Ask
better.

## Where the drawings came from

Every run counts where each drawing came from, out of the app's own answer to
add_drawing (`lookups.mjs`, tests in `lookups.test.mjs`): **stored** (a
built-in drawing looked up by name), **template** (a coded illustration), or
**drawn** for the request (the model's own svg, shapes or paths). The run
prints and records it as one line, so climbing by lookup is a number:

```
drawings 31 stored, 6 template, 3 drawn for the request (93% looked up); 33 of 35 cases answered by lookup alone
```

The skill engine is counted the same way from its transcript.

## Calibration

`calibrate` judges the three pictures the user called a mess on 2026-10-20
(their canvases, cropped out of the screenshots in `queue/audits/`) and a clean
component sheet made by hand through the same tools
(`calibration/make-clean-sheet.mjs`, to the look of the design-kit mocks). The
mess must score 4 or under and the clean sheet 7 or over; if it does not, the
rubric is fixed before anything uses it. First calibration, 2026-10-20: dog
1.8, smiley 1.8, component sheet 1.4, clean sheet 7.6
(`calibration/last-calibration.json`).

Since 2026-10-20 it also judges the user's two cat pictures (the standing
built-in cat for "a cat curled up sleeping", and the same cat pasted over a
piano for "a piano with a cartoon cat playing it"): each must get
didWhatWasAsked 2 or lower and a case score under 40 even with every rule
met, however clean the drawing is.

Since 2026-10-20 it also judges the user's noisy redline of the settings
screenshot (twelve measurements, the switch measured four times, readouts
stacked): it must score 4 or under and 3 or lower on clean.

## Adding a case

One file in `cases/`, named for the case:

```json
{
  "request": "draw a picture of a dog.",
  "group": "drawing",
  "from": "where the request came from",
  "start": { "blank": [1440, 1024] },
  "names": ["dog", "puppy"],
  "expect": { "words": false, "touch": [["ear|leg|tail", "body|head"]] }
}
```

Put it in `cases/` to climb on it, or in `held-out/` to keep it unseen;
never both. `group` is `drawing`, `sheet`, `layout`, `redline` or `video`. `start` is
`{ "blank": [width, height] }`, `{ "open": "<repo-relative file>" }` (a
picture or a `.photonz` document) or `{ "sample": "recording" }` (above) (give it
a `context` line, "a screenshot of a settings screen", for the judge and the
agent). `timeout` and `skillTimeout` are in seconds. A new case changes the set,
so compare the next run with the next run, not with the old best.

A `change` case is about a layer that is already there, usually the one picked
(`picked-*`). Its blank `start` has `steps`, walk steps that draw the layers and
pick one, and its `expect.picked` is scored from the document, because a picture
cannot tell a judge that a second layer moved: `layer` is the one the request
should change, `changes` how (`wider` than a width, a `hue`, `rounder` than a
radius), and `others` every other layer as it stood, each of which must still
stand that way.
