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
```

`--minutes N` stops starting new cases after N minutes and prints the
`--resume <run>` line that carries on. That is how a go loop runner, whose
commands stop at ten minutes, gets a whole run done in pieces. A run goes into
the history only when every case in it has run.

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
  wordless drawing. Three looks at once, each line's median, then their mean.
  The judge is `claude-opus-5-5` in a fresh `claude -p` session that can only
  read the picture: it never sees the request's transcript, the read document or
  who made it. Repeat judging of the same picture moved by 0.2 at most
  (2026-10-20).
* **Named blind** (drawings only, 0 to 10): `naming.md`, three looks with no hint
  of the request; each look that names it as one of the case's `names` is a
  third. A drawing whose own words spell its name gets no credit for naming
  (the user's dog had "Dog" written over it).

A drawing's score is 3 x rules + 4 x judge + 3 x named; anything else is
4 x rules + 6 x judge (and a drawing with no `names` to check, one saved from
a vote, too). **Then, when the judge's didWhatWasAsked is under 7, the whole
score is scaled by didWhatWasAsked / 7** (`scoring.mjs`): the stock cat drawn
for "a cat curled up sleeping" is clean, aligned and named "cat" blind, and
without this scored about 85 while doing nothing the request asked. Nothing
made scores 0. The run's total is the mean of
its cases. One blind look is ten points on a drawing case, so read a change of
two or three points on the total as noise.

The rubric, the naming prompt and the judge model together have an id
(`rubric` in the history). Runs are only compared with runs of the same engine
on the same id; change the rubric and the old runs stop being the bar.

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

## The held-out set

`held-out/` is 45 requests a runner never climbs on (2026-10-20, after Ask
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
