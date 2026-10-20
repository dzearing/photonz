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
4 x rules + 6 x judge. Nothing made scores 0. The run's total is the mean of
its cases. One blind look is ten points on a drawing case, so read a change of
two or three points on the total as noise.

The rubric, the naming prompt and the judge model together have an id
(`rubric` in the history). Runs are only compared with runs of the same engine
on the same id; change the rubric and the old runs stop being the bar.

## Calibration

`calibrate` judges the three pictures the user called a mess on 2026-10-20
(their canvases, cropped out of the screenshots in `queue/audits/`) and a clean
component sheet made by hand through the same tools
(`calibration/make-clean-sheet.mjs`, to the look of the design-kit mocks). The
mess must score 4 or under and the clean sheet 7 or over; if it does not, the
rubric is fixed before anything uses it. First calibration, 2026-10-20: dog
1.8, smiley 1.8, component sheet 1.4, clean sheet 7.6
(`calibration/last-calibration.json`).

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

`group` is `drawing`, `sheet`, `layout` or `redline`. `start` is
`{ "blank": [width, height] }` or `{ "open": "<repo-relative file>" }` (give it
a `context` line, "a screenshot of a settings screen", for the judge and the
agent). `timeout` and `skillTimeout` are in seconds. A new case changes the set,
so compare the next run with the next run, not with the old best.
