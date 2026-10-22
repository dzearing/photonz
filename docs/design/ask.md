# Ask: a request in plain words, made at once on this Mac

Ask is the Agent in the editor (the mock: `docs/design/mocks/pages/agent-generate-wt.html`,
http://127.0.0.1:8791/#agent-generate-wt). You type what you want; a model
running on this Mac turns it into a plan of the same commands the MCP server
offers (`docs/design/agent-mcp.md`), and the moment it is done the change is
made. The Agent group keeps one row per request saying what changed, with a
switch to turn it off and on and a delete; one Command Z takes the latest
request back whole. There is no Run Plan and no list of steps on screen (the
user, 2026-10-20: "I don't need to see all the actions taken, i just need a
row that explains the change and a way to toggle it or delete it"). Nothing about the request or the
document leaves the Mac.

Switch: `next-ask`, on by default in Next, absent from Current.

## Where it is

| Place | What | Code |
| --- | --- | --- |
| Title bar, right slot | **Ask** button (sparkle, Ask, ⌘K on a picture), the mock's `.askbtn` | `AskTitlebarButton`, hung in `TitlebarPanelToggle` |
| Edit menu | **Ask…**, ⌘K on a picture | `EditorCommands` (undo/redo group) |
| Over the window | The composer, the mock's `.askpal`: glass over a dimmed window, one field, Ask. Return asks, Escape or a click outside closes | `AskComposerOverlay` |
| Dock | The **Agent** group, there once the window has asked: Working… while it works, then one row per request, newest at the top (what changed, a switch, a delete; right-click for Turn Off/On and Delete), and a field to ask again | `AgentPanel`, `InspectorSectionID.agent` |
| Settings | **Ask**: which model answers, Automatic by default; the one-time setup when there is none | `AskSettingsSection` |

**No model choice in the ask surface.** The mock's Model row (line 344) and its
Choose a model menu row (line 426) are not built: the user removed them on
2026-10-19 ("i don't want to have to select a model in the experience"). Which
model answers is set once in Settings.

**⌘K.** The mock prints ⌘K for Ask. On a video ⌘K is Premiere's Add Edit
(Split at Playhead), so there the key stays with Split and Ask is the button
and the menu row (UX-PATTERNS §7). On a picture Photonz gives ⌘K to nothing
else, so Ask has it.

## How a request becomes a plan

`AskConversation` (PhotonzCore, pure, tested in `AskPlanningTests`):

1. The model gets a system prompt, the document as `read_document` reads it,
   the request, and the tools Ask offers (`AskTools`): seven LOOKING tools
   (`read_document`, `find_elements`, `list_components`, `list_styles`,
   `list_titles`, `recommended_zooms`, `list_commands`) and sixteen DOING tools
   (drawing, text, measurements, components, styles, layout, `run_command`,
   titles, cuts, trims, moves, transitions, zooms). Nothing offered opens a
   window, writes a file or steps the history, so the plan lands in the asking
   document's own undo history.
2. A looking call is run at once and its answer handed back.
3. A doing call is **not run yet**. It is checked against its tool's schema
   (`AgentTools.request`, the same check every MCP call gets) and written into
   the plan, answered "Planned as step N". A step names what an earlier step
   makes as `$N`; the run swaps in the real id from that step's answer.
4. Refused while planning: a call that fails its schema, a tool Ask does not
   offer, a repeat of a planned step, a size measurement of a box already
   measured (85% overlap), and a thirteenth measurement.
5. Words with no tool call end it: with steps, that is the plan; with none,
   the model's own sentence ("I can't…") is shown in the Agent group and
   nothing changes.

`find_elements` answers are sorted before the model reads them
(`AskElements`): each box is labelled `control`, `card`, `row` or `strip` by its
shape, controls first, and a box two readers found is kept once. A small model
reads a list top down; unsorted, it measured the page's full-width rows twice
and missed every switch.

## Running a plan

As soon as planning ends, `AskSession` runs each step through `AgentWork.run`, the code the MCP
channel runs, inside `EditorState.asOneUndoStepAwaiting`, so the whole run is
one step in the history.

A step the app refuses changed nothing (every tool is atomic). It is passed
over (its reason kept for a walk in `skipped`), and the rest run, unless a later step names what it would have made (`AskPlan.isNamedLater`):
then the run stops and what already landed is undone, so a plan that goes
wrong half way leaves nothing half done. Stop does the same.

## One row per request: off, on, delete

`AskChanges.swift` (PhotonzCore, tested in `AskChangesTests`). Each request
that changed something is recorded as the document just before it ran and
just after (`AskRecordedChange`). Turning it **off** applies the difference
after→before onto the document as it is now; **on** applies before→after.
Both are a three-way merge over the document's saved form (`DocumentMerge`):
objects merge key by key, lists of things with ids (layers, group children,
styles, tracks, clips) merge thing by thing, in the current document's order,
with what the change added put back after the entry it followed. So later
edits to other things stay. When something done since changed the very thing
the request made (moved the layer it drew, say), the merge refuses, nothing
moves, and the row says "A later change builds on this."

Each switch or delete lands as one ordinary undo step. After an undo or redo
each row reads its state off the document (`AskChangeList.follow`), so ⌘Z on
the request shows its row off, and undoing a delete brings the row back.

The row's words come from the steps that landed (`AskChangeWords`): "Added 12
measurements", "Added the title “Case 1”", "Added 5 texts and placed a
component", 40 characters at most, wrapping to two lines in the panel. The
tooltip is what was asked. Clicking the words picks on the canvas what the
change made (the layers it added, else the ones it edited), the mock's Last
change click.

Rows last for the window's session, beside the undo history they lean on:
they hold whole document snapshots, which have no place in the saved file.

### Thumbs up and down

Each row carries a quiet thumbs up and thumbs down between its words and its
switch (faint until picked; also Good Result and Bad Result in its right-click
menu; the same thumbs again takes the vote back). No mock covers them; they
sit in the row because the row is what they judge. A vote saves the request,
the document before, the document after and a picture of it under
`~/Library/Application Support/<bundle id>/Ask feedback/<time-request>/`
(`AskFeedbackFolder`, `AskFeedbackCase` in PhotonzCore), with where each
drawing came from. `Scripts/ask-eval.sh feedback` turns each thumbs down into
a case of the eval's held-out set, started from that very document
(`Scripts/ask-eval/README.md`, "The held-out set"), so the set grows from real
use. Every add_drawing answer says where the drawing came from (`from`:
painted or your svg; built-in and illustration until 2026-10-22, still
counted); Ask keeps it per run (`AskDrawingSource`),
the walk state shows it as `ask.sources`, and the eval counts it, so a score
climbed by looking things up shows as a share of lookups.

## Requests sent while Ask works

A request sent while one is at work waits its turn (the user, 2026-10-20).
`AskSession.ask` puts it in `line` (`AskRequestLine`, PhotonzCore) when
`isBusy`, which is true from the send until the work Task has wound down, a
stopped one included. When that Task ends, `finished` starts the next in
line, so a waiting request reads the document as the one before it left it.

- Waiting rows sit above the working row, newest at the top like the change
  rows, so a request moves down the list as it goes and never jumps. Each has
  a cancel (X, and Cancel on right-click); a cancelled request never runs.
- The working row names its request; Stop ends only that one and the next
  waiting one starts. A stop while planning leaves `idle`; a stop while the
  steps land, or while Ask looks at a drawing it made, takes back what ran.
- Each window has its own line. Closing the window (`EditorView.onDisappear`)
  clears it and stops the request at work.
- Walks wait on `askSettled` (nothing at work, nothing waiting), since `ran`
  lasts an instant when the next request starts straight after. Walks:
  `ask-queues-a-request-walk`, `ask-cancels-a-waiting-request-walk`,
  `ask-stops-a-running-request-walk`.

## Finding the misalignments

"Find the misalignments", "check the spacing", "what is inconsistent here": the
model calls `find_misalignments` (a looking tool) and then `mark_misalignments`
once with the ids worth showing. Detection is code, never the model
(`LayoutRead` and `MisalignmentScan` in PhotonzCore):

* **Reading the picture** (`LayoutRead`). The page colour is the one round the
  rim; whatever differs from it is ink, and ink that touches is one piece. A
  piece that is mostly one flat colour, or a thin ring round flat space, is a
  box (card, button, field, switch) and is read again inside against its own
  fill; a piece with no one fill is a picture. Other ink joins into lines of
  words by how close the letters sit (each line's baseline is read off its
  busiest rows), and icon pieces within 3.5 points join into one mark.
* **What should agree.** The children of one box, or of twin boxes (siblings of
  one width for left and right, one height for top and bottom), compared by
  their inset from their own box; words with words, shapes with shapes. A
  member 1 to 8 points off what most share is marked, unless it agrees on its
  centre (a narrow icon among wide ones). Words agree within a point (an A sits
  further left in its box than an L) and are marked from 1.5 points.
* **Gaps.** Runs of three or more like things in a row or column, the runs of
  one box pooled. Two gaps off by opposite amounts round one thing mean the
  thing moved, and that thing is marked instead.
* **Padding and borders.** A box whose members are all off by one amount has
  different padding; chips and buttons of one height compare their insets;
  twin boxes of one fill compare border widths.
* **Words and what they belong to.** A caption under a picture, a label beside
  its control: each pair should sit the same way.

Each finding is one measurement layer in the Measure tool's look
(`MisalignmentMark`): an edge is an alignment guide down the line the others
share, ticked where they agree with a bracket round the miss; a gap, padding or
border is a caliper. The readout is the finding (`MeasureContent.finding`,
"Gap 2 pt wider: 18 vs 16", 30 characters at most), the layer is named for it,
and the readout keeps off what it points at. The row reads "Found 3
misalignments". On a picture with nothing off the model says so in one sentence
and nothing changes.

Scored by `MisalignmentCorpusTests` on 62 screenshots of web UIs rendered at 2x
with planted faults (`Scripts/misalign-corpus/make-corpus.mjs`): a climb set and
a held-out set written after the detector was tuned. Walks:
`ask-finds-the-misalignments-walk`, `ask-finds-nothing-off-walk`.

## Drawing a thing

"Draw a dog", "create a smiley face icon", "a lighthouse on a cliff at dusk":
one `add_drawing` call, never a pile of `add_shape` and `add_path` calls placed
blind (that is what drew the user's dog as brown shards on 2026-10-20, and the
smiley with its eyes above its head).

**Nothing is looked up and no subject has code of its own** (the user,
2026-10-20: "I want to be able to say make x without having to have a bunch of
static cat examples ... i don't want a hardcoded anything"). Until 2026-10-22
Ask had a stored set of about a thousand emoji drawings found by name and an
illustrator with code for particular scenes (mountains, a forest, a lighthouse,
a skyline, a fox); both are gone (see "What was taken out" below). A drawing is
made for the request, one of two ways:

* **Painted** by the picture model on this Mac and traced into layers, whenever
  it is running ("Painting a drawing", below). This is the route that measured
  best on the held-out set.
* **The model's own SVG** otherwise. With no picture model the call goes back
  to the model while it is still planning and it writes ONE whole SVG (a model
  writes a picture far better at once than as twenty separate shapes), told to
  give each big form a lit and a shadow side.

Either way:

* **As layers, never a picture.** `SVGArtwork` reads the SVG (paths with every
  command and arcs, circles, ellipses, rects, polygons, groups, transforms,
  fill rules, gradients): circles and ellipses become oval layers, boxes
  rectangles, the rest Pen paths with their curves and holes. The parts go in
  one group named for the thing; a face's parts are named Face, Left eye,
  Right eye, Mouth from where they sit (`FaceParts`). One Command Z takes the
  lot.
* **The look the person named** reaches the call (`AgentDrawingWords.lookWords`:
  line art, silhouette, watercolor, flat... words for a look, never a subject);
  a look the model guessed that the person never said is taken off.
* **Placed.** Centred, 60 per cent of the canvas's shorter side, or in the box
  asked for, kept on the canvas. An icon is a 512 point icon frame with the
  drawing on its live area (the keylines); on a blank picture (nothing but its
  flat background) the picture becomes that frame.
* **Looked at before it hands back** (`AskDrawingCheck`), every drawing, scenes
  included. The drawing is rendered and shown, with no hint of the request, to
  a model on this Mac that can see: the planning model itself when it can
  (Ollama's capabilities say `vision`), else the first of
  `AskModels.preferredVision` on the Mac (`AskModels.eyes`). If what it names
  shares a word with what was asked, it reads; if not, the planning model says
  yes or no. A miss is taken back and drawn again, told what was seen (painted
  again when painting, a new svg otherwise), at most twice; then Ask says "I
  couldn't make a clear drawing of that. Nothing was changed." No model that
  can see: Ask hands back without looking.

Both models are asked with their window size pinned (32k planning, 4k
looking; the planning model looking for itself keeps its 32k and does not
think, so it is answered from the copy already loaded): left out, Ollama loads them at its own default (128k), which swaps
the planning model out on every look.

The eval counts where every drawing came from on every run, climb and
held-out (`Scripts/ask-eval/lookups.mjs`, `AskDrawingSource`): stored,
template, or drawn for the request. Both lookup counts are 0 now; a drawing
that came back from a stored set or a coded scene would show there.

## A pose or a scene is planned, then checked

"A cat playing a guitar", "a black cat seen from behind", "a fox asleep under a
tree": until 2026-10-22 the look only asked a blind model to NAME the drawing,
so a standing cat for "a cat curled up asleep" read as "cat" and passed (queue
task `a-scene-of-things-doing-something-together-is-dr`). Now:

* **One add_drawing for the whole picture.** Two or more things, or one thing
  in a pose, an action or a view, is one call, never one per noun. A second
  add_drawing that would land on top of one already planned (both centred, or
  their frames mostly the same place) is refused with the step it would cover
  (`AskConversation.stacked`): a model resending a scene with its plan
  reworded painted two whole pictures one over the other.
* **A plan.** When the request names more than the thing, the planning model
  gives add_drawing `plan`: one to four statements someone looking can answer
  yes or no, one for each pose, action, view, mood and relationship the
  request names, and, when two things act together, which parts touch and
  what is in front. A view is said as the eye sees it ("we see the back of its
  head and both ears; no face shows"), which a picture model paints far more
  readily than the word "behind". Nothing the request did not ask for: plans
  padded with "it is centred" and "the branch spans the canvas" made the check
  paint good drawings again three times over.
* **Painted from the plan.** The statements follow the subject and the
  person's words in what the picture model is asked (`PictureModelRequest`).
* **Checked against the plan.** After the drawing reads as the thing, the
  model that sees is shown it on white (a lone layer renders with nothing
  behind it) and answers yes or no for each statement, numbered
  (`AskDrawingCheck.planBody`, `unmet`). A no is painted again, told what did
  not show; an answer it cannot read is no miss. When the last try still misses
  part of the plan, the drawing stays (it reads as the thing; it is the
  closest Ask came) rather than being thrown away.
* **Kept on the picture.** The tracer measures how much of the picture's edge
  is drawing rather than backdrop (`layers.py`, `clipped`); a thing (not a
  scene) running off the edge is painted once more from another seed, so a
  tree is not cut flat along the top.
* **Checked from the picture, not the layers.** A painted drawing's layers are
  colour regions ("Dark brown 3"), not parts, so "the paws touch the keys" is
  read from the rendered drawing rather than from which layers touch.

* **Named with a label.** A drawing's group is named from its subject cut to
  the first clause and to whole words within 40 characters
  (`AgentDrawingCall.layerName`): a subject written out at length on a
  redraw had named the layer with a paragraph.

Measured on the eleven pose and scene cases of the climb set (2026-10-22):
83.9 before, 87.1 and 86.7 after. Before, a black cat seen from behind was a
front-facing silhouette (45); after, a rear view (87, 91). Held-out, 45
cases at Next defaults: 60.3 (run `20261022-094634-ask-held-out`) against
57.5 and 57.1; on drawings didWhatWasAsked 5.6 to 6.1, crafted 4 to 6, clean
6.1 to 5.7; a drawing request 41 s against 31 s, the cost of painting again.
Still open: a scene's thin lines (a kite's string) are lost in tracing, where
the blur and mode filter that smooth a sky wipe them out.

## Painting a drawing

"Ask paints its drawings" (`next-ask-paints-drawings`, on in Next) sends
every `add_drawing` to a picture model on this Mac instead of the model's
own SVG, whenever the picture model answers. Measured on the held-out set on 2026-10-22 (queue task
`try-drawing-with-a-local-picture-model-then-turn`, audit
`queue/audits/2026-10-22-try-drawing-with-a-local-picture-model-then-turn.json`,
run `20261022-043200-ask-held-out`): total 57.5 against 35.9; on drawings
didWhatWasAsked 5.6 against 3.3, clean 6.2 against 5.9, designed 6.0 against
4.7, crafted 6.0 against 5.0; 31 s a drawing request against 30 s; nothing
looked up. A first run before scenes were painted edge to edge scored 56.8
with crafted 3.0: a scene on plain white loses its sky.
* **A scene** (the planning model's `scene`, or the general scene and
  time-of-day words in `AgentDrawingWords.sceneWords`: landscape, scenery,
  sunset, night... never a subject) is painted 4:3 edge to edge with its own sky and ground;
  the tracer keeps the backdrop, blurs the picture lightly so a gradient sky
  bands smoothly, and uses fourteen colours.
* **Recolouring a drawing.** A fill set on a group recolours its parts
  (`AgentGroupRecolour`): the colour covering the most becomes the one asked
  for, the rest keep their shade in the new hue, and a detail that would sink
  into the main colour is pushed the other way, so "make the cat black" keeps
  its eyes.

* **The picture model.** Z-Image Turbo (Tongyi-MAI, Apache 2.0), 8-bit MLX
  weights (`mflux-community/z-image-turbo-mflux-q8`, about 11 GB) run by
  mflux (MIT) behind `127.0.0.1:8793` (`Scripts/picture-model/serve.sh`). A
  768 point picture takes about 22 to 28 s on an M4 Max and holds 7.5 GB at
  its peak in mflux's own count (the server process rests at 5 GB and
  peaks at 13 GB with MLX's cache capped), beside the 29 GB the planning
  model holds. Ollama 0.40.7
  refuses image models ("image generation models are not currently
  supported"), which is why it is not the runner.
* **The prompt** is the subject the planning model wrote, the person's own
  words when they say more (`PictureModelRequest`: "cat, from the request:
  draw a cat curled up sleeping"), the look they named, and a general flat,
  traceable look (few flat colours, no text, plain backdrop). Nothing in it
  knows any subject.
* **Traced into layers** (`Scripts/picture-model/layers.py`, vtracer, MIT):
  the backdrop joined to the edge is cleared (white parts inside the drawing
  stay), the drawing's own pixels are reduced by k-means to at most ten
  colours, a mode filter folds anti-aliased blends into one side, the picture
  is traced at twice its size so curves are smooth, specks and the backdrop
  path are dropped, and every fill is snapped back to the palette. Each region
  is a filled Pen path named by its colour ("Dark brown 3"), 10 to 40 of them
  for a single subject (300 at most), in one group named for the subject.
* **When the server is not there**, the model writes its own SVG: the switch
  only takes effect when `/health` answers at the start of a request.

## What was taken out (2026-10-22)

Queue task `ask-draws-any-subject-well-with-nothing-stored-o`. Taken out, with
everything that routed to them:

* **The stored drawing set**: `Resources/Drawings/drawings.json` (992 Twemoji
  drawings named from Unicode's CLDR plus a hand list of everyday words),
  `DrawingLibrary`, the app's `DrawingSet` loader, its licence notice, and
  `Scripts/make-drawings.mjs` that built it. add_drawing's `builtIn` argument
  went with it.
* **The illustrator**: `Illustrator`, `IllustrationBrief` (a list of the
  subjects it knew: mountains, hills, forest, lake, sea, sun, moon, stars,
  birds, clouds, lighthouse, cliff, city, fox), `IllustrationPieces` (a
  function per subject: a ridge, a pine and treeline, clouds, stars, birds, a
  skyline, a lighthouse, a cottage, a sitting fox), `IllustrationPasses`, and
  its geometry and palette helpers. Its eight passes and its critique all
  worked on those subject planes (ridges, treelines, water, cliffs), so none of
  it ran on a shape it had not drawn itself.

What stays is what works on any subject, because nothing in it names one:

* **Painting from the person's words** and the general flat, traceable look the
  picture model is asked for (`PictureModelRequest`, `server.py`).
* **Palette reduction and tracing** (`layers.py`): k-means to a few colours, a
  mode filter, vtracer's spline fitting (the path smoothing and simplifying),
  specks dropped, fills snapped to the palette.
* **Gradients** read from any SVG into the app's own linear and radial paints
  (`SVGArtwork`), and **boolean shape operations** (`PathCombining`).
* **Recolouring a group** by its colours' shares (`AgentGroupRecolour`).
* **The look and revise loop** (`AskDrawingCheck`): a blind look by a model
  that can see, judged against the words of the request, drawn again on a miss.

## The model

**Runtime: built into Photonz** (since 2026-10-22; the user: "we should not
have a dependency on opening ollama", "is there a way to not have the user
micromanage apps running"). Photonz ships llama.cpp's `llama-server` inside
its own bundle (`Contents/Helpers/AskModel/`, pinned in
`Vendor/llama-server/VERSION`, fetched by `Scripts/vendor-llama-server.sh`,
signed with the app by `Scripts/build-app.sh`). `AskModelServer` starts it on a
loopback port it picks (18100 to 18899, never Ollama's) the first time Ask needs
it, or as soon as a person opens Ask or types, and stops it after five idle
minutes (`AskBuiltInServerPlan.idleSeconds`) and when Photonz quits. It runs
under a small shell watch that stops it the moment Photonz's pid is gone, so a
crash leaves nothing behind either, and a pid file catches anything older.
Ask speaks Ollama's chat shape internally; `AskServerChat` translates both ways
to the server's OpenAI-style `/v1/chat/completions`.

Default model: **Qwen3.6 35B** (`ggml-org/Qwen3.6-35B-A3B-GGUF`, a mixture of
experts with about 3B parameters at work per word, Q4_K_M plus its Q8_0 picture
reader, 21.0 GB download, 21.7 GB held, measured as the server's resident
size). It can see, so it also does Ask's look at a drawing. Qwen3.6 27B (the
same weights as Ollama's `qwen3.6:27b`) is second: offered in Settings when
downloaded, but not the default, because llama.cpp reads a prompt with it at a
sixth of the speed (below). Smaller Macs are offered Gemma 4 26B or Gemma 4 E4B
by the same three-fifths memory rule (`AskBuiltInModels.recommended`; their
memory is estimated, not measured). Files go in `~/Library/Application
Support/Photonz/Models`, shared by every build on the Mac, each downloaded from
a pinned revision and kept only once its size is exact.

### The runtime comparison, 2026-10-22

M4 Max, 64 GB. The climb set (41 cases), no picture model running, every case
from a cold start (the eval quits the probe after each case, so the built-in
server loads the model every time):

| Runtime and model | Climb | drawing, sheet, layout, redline, video | s / request (median) | GB held |
| --- | --- | --- | --- | --- |
| Built in, Qwen3.6 35B (default) | **55.3** | 61.5, 17.7, 19, 46.6, 39.5 | 22.7 | 21.7 |
| Ollama 0.40.7, `qwen3.6:27b` (default before) | 53.1 | 56.7, 21.2, 11.2, 47.4, 52.1 | 23.7 | 29.1 |
| Built in, Qwen3.6 27B | stopped after 10 cases | 10 cases: 62 average | 88 to 146 | 22.8 |

The three requests the task named: screenshot measurements 46.6 built in
against 47.4 (10 s against 50 s), the Case 1 title page 84.4 against 79.6
(10 s against 5 s), a pricing section on brand 19 against 11.2 (38 s against
83 s). Video is the built-in model's weak side: "a title page before each of
the three clips" scored 17.5 against 85.6.

Speeds (`llama-bench`, `--ctx-size 32768`): Qwen3.6 27B reads 217 tokens a
second (flash attention and bigger batches no faster) and writes 22; Qwen3.6
35B reads 930 to 1,330 and writes 27 or more. Ask's first prompt is about
10,400 tokens, so the 27B spends about 47 s reading before it writes a word
and the 35B about 8 s. The server loads either in 8 to 13 s; later turns of a
request reuse what was read. With its network denied (`sandbox-exec`, loopback
only) the server loads and answers tool calls and pictures the same.

Setup is Settings > Ask: the model, its size and where it goes, one Download
button, a progress bar with Stop. Ask with no model says "Ask needs its model.
Get it in Settings." with an Open Settings button (two clicks from Ask to a
download). A walk gets that Mac with `"askModelMissing": true`
(`ask-sets-itself-up-walk`).

**Ollama is optional, off by default**: "Use Ollama instead" in Settings > Ask
(`ask.runtime` = `ollama`). Kept rather than removed because the bake-off and
anyone with models there already can still use them; nothing reaches its port
otherwise (`AskBuiltInModelTests` checks that only `AskRuntime` names it).

One turn may write at most 8,192 tokens (`AskServerChat.mostTokensATurn`), so
an svg that never closes ends in a minute or two instead of filling the window.

### Before 2026-10-22: Ollama

Runtime: **Ollama**, on its loopback port, the only address Ask called.
Default: **`qwen3.6:27b`** (18 GB download, about 30 GB held while Ask uses
it), run with thinking off and a 32k window.

**Automatic** (`AskModels.automatic`) takes the first model in
`AskModels.ranked` that the Mac has and can hold. **The rule: a model may hold
at most three fifths of the Mac's memory** (`memoryShare`), leaving the rest
for macOS, Photonz and a browser. So, by memory:

| Mac | Automatic picks (and Settings offers to download) |
| --- | --- |
| 48 GB or more | `qwen3.6:27b` |
| 36 GB | `qwen3:30b` (cannot see; the look falls back to `llama3.2-vision` if present) |
| 32 GB | `gemma4:e4b` |
| 24 GB or less | none: Settings says Ask needs more memory than this Mac has |

A model chosen in Settings wins while it is on the Mac, whatever its size.

### The bake-off, 2026-10-21

M4 Max, 64 GB, Ollama 0.40.7 (brought up from 0.20.2 first). Every model ran
the eval's climb set (30 cases) through Ask; the ones that answer in under 30 s
ran the held-out set (45 cases) too. Seconds are Ask's own, send to done, the
median over the set. Memory is what Ollama said the model held at 32k. Broken
calls are tool calls with arguments the tool could not take, a tool it was not
given, or a call written as text (`AskConversation.brokenCalls`). The look used
`llama3.2-vision` for every row here, so the rows compare planners only.

| Model | Climb | Held-out | s / request (climb, held-out) | GB held | Broken calls (climb, held-out) |
| --- | --- | --- | --- | --- | --- |
| `qwen3.6:27b` | 74.1 | **35.9** | 3.6, 26.1 | 29.9 | 1 of 64, 18 of 128 |
| `qwen3.6:35b` | 72.4 | 31.5 | 1.3, 7.9 | 32.7 | 0 of 64, 27 of 156 |
| `gemma4:26b` | 71.6 | 26.4 | 7.9, 9.6 | 25.7 | 0 of 66, 19 of 129 |
| `qwen3:30b` (before) | 71.4 | 18.2 (on 0.20.2) | 10.8, - | 21.9 | 3 of 74, - |
| `gemma4:e4b` | 74.3 | 13.5 | 4.2, 4.6 | 18.6 | 0 of 42, 14 of 57 |
| `gemma4:12b` | 71.7 | - | 20.4 | 17.3 | 3 of 50 |
| `qwen3-vl:30b` | 74.7 | stopped: about 5 min a case | 28 | 22.5 | 0 of 51 |
| `gemma4:31b` | 75.3 | - (too slow) | 56.5 | 29.8 | 0 of 65 |
| `mistral-small3.2:24b` | 0 after 13 cases | - | 47 a turn | - | never called a tool |
| `qwen3-vl:8b` | stopped after 7 cases | - | 42 to 300 | - | - |

The `-mlx` tags scored the same as the plain ones (`qwen3.6:35b-mlx` 74.6,
`qwen3.6:27b-mlx` 75.5, `gemma4:26b-mlx` 73.7, `gemma4:31b-mlx` 57 s a
request): on Apple Silicon, Ollama 0.40 already runs the plain `qwen3.6` and
`gemma4` tags on its MLX engine (nvfp4, `ollama ps` says `mlx`), so the plain
tag is the default. The climb set barely separates models, because its
drawings came from the built-in set whatever the model (it was taken out on
2026-10-22); the held-out set does.

**One model looking, against two** (the held-out set, `qwen3.6:27b` planning):
looking with `llama3.2-vision` beside it, 35.9, median 26.1 s, about 41 GB held
by the two; looking with itself, 35.9 (drawings 36.0 against 35.1), median
31.1 s, 29.3 GB held. Same score, 11 GB and a second download fewer, about 5 s
slower in the middle of the held-out set (its harder requests; the climb set's
median is 3.6 s). One model is the default; `defaults write <bundle id>
ask.eyes <model>` makes a second model look, for measuring only.

Earlier, 2026-10-19, the screenshot request alone:

| Model | Result |
| --- | --- |
| Qwen3 30B A3B Instruct 2507 (a community build) | Wrote its tool call as text with a broken tag; Ask now reads those too, but the stock tag is the default |
| `gpt-oss:20b` | Its template cannot read a property given as a choice of types; with that flattened it ignored the no-thinking switch, thought for 122 s and gave up |
| Apple's on-device model (FoundationModels) | Not usable: its window is 4,096 tokens and the tool list plus the document read is about 5,800 before the request |

With no model: Settings says so and offers the download of the best model the
Mac can hold (`AskModels.recommended`, its size stated before you press it) through Ollama's own pull; with no Ollama, Settings
links its download. Ask itself says "Ask needs Ollama. See Settings." in the
Agent group.

## Try paths (walks)

* `Scripts/playtest/ask-annotates-a-screenshot-walk.json`: settings screenshot,
  "annotate the ux with measurements around the major ui elements".
* `Scripts/playtest/ask-adds-a-title-page-walk.json`: the sample recording,
  "add a title page that says Case 1 before this clip".
* `Scripts/playtest/ask-makes-a-pricing-section-walk.json`: a blank canvas,
  "Make a pricing section on brand".
* `Scripts/playtest/ask-draws-a-dog-walk.json`: a blank canvas, "draw a picture
  of a dog." (one Command Z takes it back), then "create a smiley face icon".

Each presses the Ask button, types, sends, waits for `ran`, then undoes and
redoes the request, turns its row off and on with the switch, deletes it, and
undoes the delete, checking the document each time. They need Ollama with a model, so on a Mac without one
they stop with Ask's own sentence.

## Not in this slice

* The composer's `/` command list (the mock's `.cplist`): typing `/` to run an
  ordinary command by name.
* Pictures while planning: the default model can see since 2026-10-21, but Ask
  still plans from the structured read and the element boxes; only the look at
  a drawing shows it a picture.
