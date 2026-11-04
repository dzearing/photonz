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
| Title bar, right slot | **Ask** button (sparkle, Ask, ⌘K), the mock's `.askbtn` | `AskTitlebarButton`, hung in `TitlebarPanelToggle` |
| Edit menu | **Ask…**, ⌘K | `EditorCommands` (undo/redo group) |
| Over the window | The composer, the mock's `.askpal`: glass over a dimmed window, one field, Ask. Return asks, Escape or a click outside closes | `AskComposerOverlay` |
| Dock | The **Agent** group, there once the window has asked: Working… while it works, then one row per request, newest at the top (what changed, a switch, a delete; right-click for Turn Off/On and Delete), and a field to ask again | `AgentPanel`, `InspectorSectionID.agent` |
| Settings | **Ask**: which model answers, Automatic by default; the one-time setup when there is none | `AskSettingsSection` |

**No model choice in the ask surface.** The mock's Model row (line 344) and its
Choose a model menu row (line 426) are not built: the user removed them on
2026-10-19 ("i don't want to have to select a model in the experience"). Which
model answers is set once in Settings.

**⌘K.** The mock prints ⌘K for Ask, and Ask has it everywhere, on a video as
on a picture: the user asked for one key on 2026-10-24. Until then a video gave
⌘K to Premiere's Add Edit; Split at Playhead now takes Final Cut's Blade, ⌘B
(UX-PATTERNS §7).

**The sheen.** Every arrival of the pointer sweeps the button's sheen once,
from the start, even while the last sweep is still crossing; staying does not
repeat it, and Reduce Motion skips it (`HeroSheen.sweeps`). Until 2026-10-24
only the first hover swept: a keyframe animator replays its track from where
the last run left the value, which was the end. The track now starts with a
move back to the beginning. `ask-sheen-every-hover-walk` films it
(`filmHover`).

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
   measured (85% overlap), a thirteenth measurement, a thirteenth component,
   and words a labelled component row already sets. A labelled row that would
   run off the bottom of the canvas grows the canvas down first (a
   `canvas_size` step anchored top left, `sheetHeight`). A refused call the model sends back unchanged twice more
   ends the planning with the steps already written (`mostSameRefusals`): a
   small model at temperature 0 otherwise spent every round left on it.
   Thirty rounds at most (twelve until 2026-10-23, when a kit of base
   components ran out of them).
5. Words with no tool call end it: with steps, that is the plan; with none,
   the model's own sentence ("I can't…") is shown in the Agent group and
   nothing changes.

**Components.** Asked for components, a kit or a design system, the model
makes each kind itself with `add_component` (`docs/design/agent-mcp.md`,
"Making a component"): its parts, its first look, and every state as only what
changes, so each lands in the Library as one component with its states as
versions. Which kinds a kit holds and how each looks is the model's own
knowledge of the platform's real kit, sharpened by the prompt
(`AskConversation.componentRules`); nothing about them is stored. The Library's
starters are no longer offered as the answer (before 2026-10-23 the prompt said
"the Library always offers starters... use them", and "base components" came
back as the five starters copied four times). Shown as a table, each row is an
`add_component` with `labels`, and the conversation lines them up as one sheet
(`alignSheet`): every row at the first one's x and straight under the last,
one column step for every row it fits. The starters are taken out of what
Ask is shown (`AskTools.withoutStarters`): shown them, it answered with
exactly their five kinds. Measured on the user's request: 14.7 before, 47.7 after
(2026-10-23, `Scripts/ask-eval.sh`, case `component-table`).

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

### Looking at a layout (2026-11-03)

A local model plans from numbers, not a picture, so its layouts came out
almost right: a heading "centred" at an x that was really its left edge,
button words dark on a blue fill, a price stacked onto the line under it.
Before it hands back, the run reads the finished document
(`AskLayoutCheck`, PhotonzCore, unit tested) and mends, in the same undo step,
what a person would see at a glance, on any request:

- words that do not read against what is behind them (the topmost filled box,
  or the page, which is a flat picture the app reads the colour of) take the
  nearest shade that does, and plain dark words on a coloured fill where white
  reads turn white, the way the system sets a button label (the same shades
  add_component uses). This overrides a colour the request named, on purpose:
  words are always legible;
- a centred line alone on its row, drifted less than a quarter of the way off
  the middle of what it sits on (its button) or of the row below it, is centred
  on it. A line with other words on its row is one of a set and stays;
- words hanging off the box they are on come back onto it, to its middle when
  the box is a chip or button;
- words stacked onto the words above them in the same column move down to
  clear them, taking the words under them along, when that keeps them inside
  what they sit on and clear of anything else made there; words that start
  past the middle of the words they touch are on the same line ("$29" and
  "/mo") and move along it instead;
- words hanging off the canvas come back on.

Only layers the request made are touched. A video is left alone, since what
is behind its words is footage, and so are words on a photo, whose colour is
not one thing. What it cannot mend is said beside the change in one short
sentence, "Some words still overlap." or "Some words run off their box."
Every look is a `look:` line in the trace.

A step's name (`$N`) is only swapped where a step's name can go, never in words
a person reads (`AskStep.wordKeys`): a price written "$12" stays a price.

add_text given no colour picks its default the same way
(`AskLayoutCheck.defaultInk`), for Ask and for an agent over MCP alike: white
on a blue button rather than near black.

The eval drives Ask by pressing the title bar's Ask button and Send, which work
with the window behind another app.

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

## Saying what it is doing (2026-11-01)

The user, 2026-10-24: "when the agent is in progress, I would like more
frequent updates in the agents panel about what is happening." The request at
work keeps its words and Stop, and under them carries ONE live line saying what
Ask is doing now. It is one line high whatever it says, cross-fades as it
changes, and goes when the request is done: a finished row still says what it
made and never lists its steps (the rule of 2026-10-20 stands).

Every line comes from the pipeline as the stage starts (`AskStage`, PhotonzCore,
with its words and the 40 character budget; `AskSession.enter`), never from a
timer:

| Stage | Line | Where it comes from |
| --- | --- | --- |
| model loading | Getting the model ready | `AskModelServer.loading`, shown over whatever waits on it (`liveStage`) |
| reading the document | Reading the picture / video | `conversation` |
| a canvas picture for a model that sees | Looking at the canvas | `conversation` |
| the model reading the prompt | Reading your request, 41% | llama-server `/slots`, polled while a turn is out (from two seconds in: before that the count is the last request's): `n_prompt_tokens` against Ask's own estimate of the request, held under 100 |
| the model writing | Writing the steps | `/slots` `n_decoded` above 0 |
| a look the planner asked for | Looking through the components, … | the look's tool |
| a drawing's plan | Planning a fox, 1 of 2 | `withDrawingPlans` |
| the picture model loading | Getting ready to paint | `AskPictureModel.report` |
| painting | Painting a fox, 2 of 3, 44% | `server.py` writes `painting 4/9` per mflux step to `PHOTONZ_PICTURE_PROGRESS` |
| tracing | Turning a fox into layers | `server.py` writes `tracing` |
| other steps | Making the changes, 3 of 7 | `run` |
| looking at what it drew | Checking a fox | `look` |
| a try again | Trying again: it looked like two foxes / missed … | the check's verdict, held through the whole re-plan |

Once a stage has run five seconds its line carries the time on it ("12s",
then "1:05"). The picture server's stages reach the session through a task
local (`AskPictureModel.$report`), so two windows asking at once each hear their
own. An agent reads the same line through MCP: `list_documents` carries `ask`
(`request`, `doing`, `seconds` on that stage, `waiting`) for a window where Ask
is working. A walk reads `ask.stage`, and `ask.stages` with the time each line
came (`AskStageLog`, its `longestWithoutNews`).

Measured on 2026-11-01 (`ask-says-what-it-is-doing-walk`, "a fox in a forest at
sunset", 144 s): the longest the line went without changing was 10.9 s, the
model loading into memory, which says its time. Reading the prompt moves every
2.5 s, painting every 4.7 s.

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
  it is set up ("Painting a drawing", below). This is the route that measured
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
  not show; an answer it cannot read is no miss. Every try is held to the
  first try's plan (`AskDrawingCheck.carryingPlans`): the model rewords the
  subject when it draws again, and a plan asked afresh of the reworded subject
  grew details nobody asked for ("a black beak centred on its face" for "an
  angry bird"), each a reason to paint again. After the last try the closest
  one lands (`Attempt`, `isCloser`: one that reads beats one that does not,
  fewer statements missed beats more, a tie goes to the later): a last try
  that did not read had thrown away an earlier one that did (2026-10-23).
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
own SVG, whenever the picture model is set up. Measured on the held-out set on 2026-10-22 (queue task
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
  mflux (MIT), which Photonz sets up and runs itself ("The picture model's
  setup", under "The model"). A 768 point picture takes about 22 to 28 s on an M4 Max and holds 7.5 GB at
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
* **When it is not set up**, the model writes its own SVG: the switch only
  takes effect when the weights are whole and the tools installed
  (`AskPictureServer.isInstalled`) at the start of a request.

## A photo, a drawing or a painting

The user, 2026-10-24: "I'd like to say 'paint a picture' and it will use brush
tools when they're ready, or make a photorealistic image of ..., and it will
generate an image, or 'make vector art of ...' or 'create an icon' and it would
use the vector tools". Ask reads which kind the person asked for and uses that
tool (`AgentPictureKind`, `Sources/PhotonzCore/AgentPhoto.swift`):

* **A photo** ("a photo of", "photograph", "photorealistic", "realistic"):
  `add_photo`, the same picture model's painting KEPT AS PIXELS, one ordinary
  picture layer (its pixels in the image store) filling the canvas, the pixel
  selection or the frame asked for, as one undo step. The prompt is the
  subject, the person's words, and a general photographic look
  (`PictureModelPhotoRequest`): none of the flat-look words a traced drawing
  needs. It is painted at the box's aspect at about a million pixels, every
  side a multiple of 16 (`/photo` in `Scripts/picture-model/server.py`).
* **Vector layers** ("vector art", "draw", "illustration", "icon", "logo",
  "line art"): `add_drawing`, painted and traced as before. An icon or vector
  word wins over a photo word ("a photo icon" is an icon).
* **A painting** ("paint", "painting", "brush"): painted with the Brush,
  stroke by stroke (since 2026-10-31, `docs/design/brushes.md` decision 8).
  Only for a painting is the model shown `list_brushes` and `paint_stroke` and
  a painter's way of working (`AskConversation.brushRules`: block in edge to
  edge with a wide brush, middle shapes, then a little detail; three or four
  shades an area; each stroke's points as a short `path`); every other
  request sees exactly the tools and instructions it saw before. A drawing or
  photo planned for a painting is turned back with what to do. Where the
  Brush is not there (a video, a release without it) it is painted as ONE
  picture layer in a painted look, and Ask says so: "No brushes yet, so I
  made one image." With no picture model it is drawn as vector art and the
  line says "No brushes yet, so I drew vector art."
* **Neither**: the planning model picks (the instructions: a real place,
  animal, person or moment is a photo; a thing to design with is a drawing),
  and the row says which it made ("Made a photo of a dog on a beach", "Drew a
  dog").
* **The other way**: "as a photo", "as vector art", "try it as a painting" on
  its own makes the last request again that way (`AgentPictureKind.remade`).
  The words that named the earlier kind are left out of the new prompt
  (`withoutOtherKinds`), so "make vector art of a fox" made again as a photo
  is not painted as vector art.

Only the general words for a kind are read; nothing about any subject. Agents
get the same tool over MCP (`add_photo`).

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

Default model: **Qwen3.8 27B** since 2026-10-24, the user's call ("we should be
using qwen 3.8 27b 4 bit quant over 3.6 35b"): `ggml-org/Qwen3.8-27B-GGUF`,
Q4_K_M plus its Q8_0 picture reader and its multi-token-prediction draft
(`mtp-Qwen3.8-27B-Q4_0.gguf`, run with `--spec-type draft-mtp`), 21.3 GB
download, 24.4 GB held (the median over the climb set; 27.6 at its peak), from
a 48 GB Mac up. It is dense, so it is slower than the 35B: see "Qwen3.8 27B,
2026-10-24" below. A Mac that already has Qwen3.6 35B keeps using it, and
Settings offers Qwen3.8 beside it ("New default: Qwen3.8 27B (21.3 GB)",
Download); once both are down Automatic moves to Qwen3.8 and the older one has
a Delete (`AskBuiltInModels.newer`, `removable`; walks
`ask-offers-the-new-default-model-walk`, `ask-deletes-an-older-model-walk`). A
model whose draft file is missing runs without it.

Before it, **Qwen3.6 35B** (`ggml-org/Qwen3.6-35B-A3B-GGUF`, a mixture of
experts with about 3B parameters at work per word, Q4_K_M plus its Q8_0 picture
reader, 21.0 GB download, 21.7 GB held, measured as the server's resident
size), now second, and the default on a 40 GB Mac. Both can see, so each also
does Ask's look at a drawing. Qwen3.6 27B (the
same weights as Ollama's `qwen3.6:27b`) is second: offered in Settings when
downloaded, but not the default, because llama.cpp reads a prompt with it at a
sixth of the speed (below). Smaller Macs are offered Gemma 4 26B or Gemma 4 E4B
by the same three-fifths memory rule (`AskBuiltInModels.recommended`; their
memory is estimated, not measured). Files go in `~/Library/Application
Support/Photonz/Models`, shared by every build on the Mac, each downloaded from
a pinned revision and kept only once its size is exact.

### Choosing a model (2026-11-01)

The user, 2026-10-24: "in settings, I would like multiple model options to
choose from ... by default, model should not be downloaded and clicking ask
should bring you to a dialog which downloads a recommended model set if needed
based on the mac configuration."

* **Nothing is downloaded until a person wants Ask.** A fresh Photonz has no
  model and starts no helper: typing in Ask warms a model only when one is on
  the Mac (`AskModelServer.warm`).
* **The first Ask opens one dialog** (`AskSetupSheet`; also Create in the New
  window): what Ask is, the set for this Mac with each part's size, the total
  and the space left, Download and Not Now. Not Now keeps the words in their
  field. Download starts the set; the dialog shows each part's progress, with
  Stop and Hide (the download carries on hidden), and once everything is down
  the request runs without being typed again. Other Models… opens Settings at
  the Ask section.
* **The set** is `AskModelSetup.plan` in PhotonzCore, tested: the best offered
  chat model the Mac holds by the three-fifths rule whose download fits the
  free disk (2 GB kept spare), stepping down when the disk is short, then the
  picture model when it fits beside it in memory and on disk. A Mac too small
  says so; a full disk says how much to free.
* **Settings > Ask** lists every offered model as a row (`AskModelRow`): name,
  one line on what it is good at, In Use when Ask answers with it, the smallest
  Mac sold that holds it and its download size ("Too big for this Mac" when it
  is), quality and speed as five dots each with the real numbers in the help
  tag, and Download, Use or Delete. A download shows its progress, size and
  Stop. The picture model is a row of its own. Deleting the model in use falls
  back to the next one on the Mac, or to the dialog. Qwen3.6 27B is no longer
  offered (Qwen3.8 27B is the same size, newer and better) and shows only on a
  Mac that has it.
* **Ratings are measured**, by fixed bands (`AskModelRating`): quality from
  the held-out total (2 from 20, 3 from 35, 4 from 50, 5 from 60), speed from
  the median seconds a request (2 at or under 180, 3 at or under 90, 4 at or
  under 45, 5 at or under 20). Below 20 on the held-out set a model cannot do
  Ask's work, and its row says "Too weak for Ask" instead of a Download.
* **Delete confirms in its row** (Cancel, "Delete 21.0 GB"), not in an alert:
  a walk's click could not press an alert's button, nor a destructive-role
  button in the row (2026-11-01), so the button is a plain one.

Measured on an M4 Max, 64 GB, on the held-out set (45 cases, totals only).
"GB held" is the server's resident size, median over the run, at this Mac's
64k window (a 32 GB Mac or smaller runs a 32k window and holds somewhat less):

| Model | Held-out | Quality | s / request (median) | Speed | GB held | Download | Smallest Mac | Tool calls broken | Run |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Qwen3.8 27B (default) | 57.8 | 4 | 141.9 | 2 | 24.4 | 21.3 GB | 48 GB | | `20261024-163432-ask-held-out` |
| Qwen3.6 35B | 60.2 | 5 | 49.1 | 3 | 21.7 | 21.0 GB | 36 GB | | `20261024-191502-ask-held-out` |
| Gemma 4 26B | 20.2 | 2 | 35.5 | 4 | 23.1 | 15.4 GB | 36 GB | 148 of 278 | `20261102-004807-ask-held-out` |
| Qwen3.5 9B (16 GB Mac) | 20.7 | 2 | 91.8 | 2 | 10.1 (peak, 32k) | 6.6 GB | 16 GB | 41 of 190 | `20261102-122343-ask-held-out` |
| Qwen3.5 4B | 12.4, too weak | 1 | 57.4 | 3 | 7.8 | 3.4 GB | 16 GB | 49 of 207 | `20261102-012713-ask-held-out` |
| Gemma 4 E4B | 4.5, too weak | 1 | 13.3 | 5 | 7.3 | 5.2 GB | 16 GB | 74 of 123 | `20261102-002913-ask-held-out` |
| Gemma 4 E2B | 4.6, too weak | 1 | 15.8 | 5 | 4.2 | 3.4 GB | 8 GB | 27 of 102 | `20261102-001045-ask-held-out` |
| Z-Image Turbo (pictures) | 57.5 with it, 35.9 without | 4 | 31 a drawing request | 4 | 12 more | 11.2 GB | beside the chat model | | `20261022-043200-ask-held-out` |

The Gemma and Qwen3.5 runs had only that model on the probe and no picture
model (`--models <id>`), as the Mac each is for would run it. Qwen3.5 9B's row
was also planned as a 16 GB Mac (`--mac 16`: that Mac's 32k window and
memory), since that is the Mac it is for; at this Mac's 64k window the same
model scored 21.2 at 76.3 s (`20261102-023538-ask-held-out`). That 64k run
was first read as 19.8, too weak: three of its cases had been put off for a
person at the Mac and counted as 0. Run to the end on 2026-11-02 it was 21.2,
and the eval now prints an unfinished run as UNFINISHED, never as a score. The small models
fail mostly by writing tool calls Ask cannot read (the broken counts above),
which is what Ask's instructions, about 16k tokens of them, ask of a model.

What each Mac gets (`AskModelSetup.plan`, plenty of disk):

| Mac | Gets | Download |
| --- | --- | --- |
| 8 GB | "This Mac doesn't have enough memory for Ask." | nothing |
| 16 GB | Qwen3.5 9B | 6.6 GB |
| 24 GB | Qwen3.5 9B | 6.6 GB |
| 32 GB | Qwen3.5 9B (the picture model needs 22.1 GB beside it, 20.6 allowed) | 6.6 GB |
| 36 GB | Qwen3.6 35B | 21.0 GB |
| 48 GB | Qwen3.8 27B | 21.3 GB |
| 64 GB | Qwen3.8 27B and Z-Image Turbo | 32.5 GB |

An 8 GB Mac may hold 5.2 GB. Only Gemma 4 E2B fits (4.6 held-out); Qwen3.5
4B might, if its 7.8 GB reading is high, but scores 12.4. Both are far under the
floor, so their rows say Too weak for Ask and the dialog says the memory is
short.
Among models on a Mac, `ranked` puts the small ones in score order, so a Mac
holding several answers with the best, and the New default offer only ever
steps up (`AskBuiltInModels.newer`).

Walks: `ask-sets-itself-up-walk` (8 GB Mac: dialog, Not Now, Download, the
request runs), `ask-settings-lists-models-walk` (16 GB Mac: Settings from the
dialog, at Ask), `ask-offers-the-new-default-model-walk`,
`ask-deletes-an-older-model-walk` (Use, Delete, fall back). A walk can plan for
another Mac size with `"askMac": 8`, and a download in a walk with its own
models folder clones the Mac's copy, so it is done in a second.

### Walks share one model (2026-10-30)

Every walk starts a new probe, and every probe used to load the whole model
for itself: about 23 GB and the GPU flat out for a minute, once per Ask walk.
Now a walk run shares one server (`AskWalkServer` in PhotonzCore, the files and
the launch in `AskWalkServerProcess`, the run's side in
`Scripts/ask-walk-server.sh`):

- The first probe in a run that needs the model starts it OUTSIDE itself,
  detached, under a small watch, and writes what it runs to
  `~/Library/Caches/Photonz/ask-walk-server/record.json`. Later probes in the
  run adopt it when it runs the model they would pick from the same folder;
  one that sets up its own models (`askModelMissing`, `askModelsOnly`) or
  wants another model runs its own, tied to itself, as before. A person's Ask
  never shares: only a walk's setup turns sharing on.
- It runs gently: `taskpolicy -b`, `--ubatch-size 128 --batch-size 512
  --prio -1 --poll 0 --threads 4`. Measured on 2026-10-30 (M4 Max, Qwen3.8 27B
  with its draft, one 2412-token request): 212 t/s reading and 39.7 t/s
  writing against 232 and 42.8 at the app's own settings, about 9% slower. A
  1 MB GPU blit every 50 ms beside it read p50 0.42 ms, p99 4.2 ms (0.70 and
  2.8 at the app's settings); both stay far inside a frame.
- Its life is bounded three ways: `playtest-all.sh` (every rotating check and
  whole-set run) or a lone `playtest.sh` owns it and stops it on the way out;
  the watch stops it when that owner is gone (a SIGKILL'd run) or after three
  minutes with nothing asked (`/slots` saying it is processing keeps it); and
  the go loop stops it when it stops.

### Qwen3.8 27B, 2026-10-24

M4 Max, 64 GB, the same code for both (commit 2abd8391 plus the switch), every
case from a cold start, Next defaults (built-in server, picture model on):

| Model | Climb (41) | drawing, sheet, layout, redline, video | Held-out (45) | drawing, layout, redline, video | s / request (median, climb / held-out) | GB held (median / peak) |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen3.8 27B + MTP draft (default) | 75.3 | 79.4, 81.4, 67.9, 46.6, 54 | 57.8 | 64.4, 12.3, 22.3, 59.6 | 140.8 / 141.9 | 24.4 / 27.6 |
| Qwen3.6 35B | 77.1 | 86.3, 65.2, 32.9, 48.3, 37.8 | 60.2 | 68.4, 22.4, 9.2, 50.1 | 52.1 / 49.1 | 21.8 / 23.5 |

Runs `20261024-131153-ask`, `20261024-151759-ask`, `20261024-163432-ask-held-out`,
`20261024-191502-ask-held-out`. Qwen3.8 is better on sheets, video and held-out
redline, worse on drawings (its own look turned down two good drawings by
naming them more or less precisely than the request; queue task
`ask-on-qwen3-8-27b-keeps-a-drawing-its-look-name`) and held-out layout, and
about three times slower: it is dense, reads a prompt at 103 to 183 tokens a
second against the 35B's 1,046, so a cold first request spends 60 to 90 s
reading Ask's ~10k-token instructions (screenshot measurements 83 s against
14 s). A warm server reads only what is new (the same 12.5k-token prompt a
second time: 1.6 s against 62.8 s); bringing that read back from disk on a cold
start is queue task `ask-s-first-answer-after-its-model-loads-comes-i`.

**The draft.** `mtp-Qwen3.8-27B-Q4_0.gguf` (1.7 GB, same revision) runs as
llama.cpp's multi-token prediction (`--spec-type draft-mtp --model-draft`,
`AskBuiltInServerPlan.arguments(draftOnDisk:)`). Writing a 700-token svg:
11.9 tokens a second without, 33.2 with it (510 of 565 drafted accepted), 28.7
with the repo's DFlash draft instead. On 8 climb cases, 73.8 with it against
60.4 without (`20261024-160940-ask`): without it the component table and the
pricing section ran past the eval's 300 s. It costs about 3.8 GB held. Prompt
reading, tool calls and pictures are the same with it.

**The server.** b11826 loads Qwen3.8 (`qwen35`, 64 blocks, the same shape as
Qwen3.6 27B); b11853, the newest on 2026-10-24, read and wrote at the same
speed back to back, so the vendored build did not change.

**Memory.** "GB held" is the eval's reading of the server's resident size after
each case (`modelMemory` in `Scripts/ask-eval/engines.mjs`; until 2026-10-24 it
read the server's shell watch and said 0 for every built-in run). The choices'
`gigabytes` is the median, as the 35B's 21.7 always was.

### The runtime comparison, 2026-10-22

M4 Max, 64 GB. The climb set (41 cases), no picture model running, every case
from a cold start (the eval quits the probe after each case, so the built-in
server loads the model every time):

| Runtime and model | Climb | drawing, sheet, layout, redline, video | s / request (median) | GB held |
| --- | --- | --- | --- | --- |
| Built in, Qwen3.6 35B (default) | **55.3** | 61.5, 17.7, 19, 46.6, 39.5 | 22.7 | 21.7 |
| Ollama 0.40.7, `qwen3.6:27b` (default before) | 53.1 | 56.7, 21.2, 11.2, 47.4, 52.1 | 23.7 | 29.1 |
| Built in, Qwen3.6 27B | stopped after 10 cases | 10 cases: 62 average | 88 to 146 | 22.8 |

Held-out set, 2026-10-22, at Next defaults (built-in Qwen3.6 35B, the picture
model Photonz sets up and runs, no Ollama): **61** over 45 cases (drawing 69.1,
layout 6.4, redline 31.5, video 48.1; 41.5 s median a request; nothing looked
up), run `20261022-231423-ask-held-out`, against 60.3 for the best before
(Ollama `qwen3.6:27b` with the picture model started by hand).

The three requests the task named: screenshot measurements 46.6 built in
against 47.4 (10 s against 50 s), the Case 1 title page 84.4 against 79.6
(10 s against 5 s), a pricing section on brand 19 against 11.2 (38 s against
83 s). Video was the built-in model's weak side: "a title page before each of
the three clips" scored 17.5 against 85.6, because it left the first page with
no clip and no time, and such a page goes at the playhead. Once `add_title`
said so in its own words, the case scored 84.4 and the climb set's video group
53.1 against Ollama's 52.1 (run `20261023-011305-ask`).

Offline: a walk can take the probe off the network (`"offline": true`, a
loopback-only sandbox the probe puts on itself and every helper inherits).
`ask-runs-with-no-network-walk` measures a screenshot and paints a drawing
that way, and the three named requests ran offline in 9.5 s, 10.2 s and 59.3 s.
Both servers let go 5 min 12 s after Ask last used them, and nothing of
Photonz's is running a second after it quits.

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

### The picture model's setup, 2026-10-22

The picture model is the same kind of thing as the chat model: Settings > Ask
offers it ("Ask can paint its drawings with Z-Image Turbo, 11.2 GB. It goes in
Application Support > Photonz > Models.") on a Mac that can hold it beside the
chat model (`AskPictureModelPlan.fits`, 12 GB held), with progress and Stop
(`AskModelDownload.pictures`). One Download does two things:

* **The weights**, 13 pinned files (`AskPictureModelPlan.modelFiles`, 11.0 GB)
  into `Models/z-image-turbo-q8/`, in the layout mflux reads from a local path.
  A file the Mac already keeps for the Hugging Face tools at the same revision
  and size (`~/.cache/huggingface/hub/...`) is cloned from there instead
  (`AskBuiltInModels.huggingFaceCache`), for both models.
* **The tools**: Photonz ships `uv` (MIT, `Contents/Helpers/PictureModel/uv`,
  pinned in `Vendor/uv/VERSION`, fetched by `Scripts/vendor-uv.sh`), which
  builds a private Python 3.12.11 with exactly the 43 packages the server
  imports at exact versions (`AskPictureModelPlan.packages`, installed
  `--no-deps --only-binary`) in `Models/picture-tools/`, its cache and Python
  inside that folder and nothing read from the person's own setup. mflux
  declares torch, OpenCV and matplotlib for other models; leaving them out
  saves about 700 MB (435 MB installed against 1.2 GB). About 12 s on a fast
  connection. `installed.txt` holds the list, so a build with a different list
  installs again.

`AskPictureServer` runs `server.py` (shipped in `Contents/Resources/PictureModel/`)
with that Python, offline (`HF_HUB_OFFLINE`, compiled files kept out of the
bundle), on a port it picks (18900 to 19699), under the same watch as the chat
server (`AskHelperProcess`): started the first time Ask paints, let go after
five idle minutes, stopped when Photonz quits. It loads in about 2 s from a
warm disk and holds 11.2 GB resident (about 25 GB at its peak while painting).
Nobody runs a script; `Scripts/picture-model/serve.sh` is gone. A walk waits
for the setup with `waitFor askPicturesSetUp`.

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

## Changing what it just made (2026-10-31)

"Paint a beach at sunset", then "make the water bluer": the second request
changes the first one's water in place, the way a conversation would. Three
things make that work, none of them knowing any subject:

* **Parts carry the model's own names.** A painting's sketch gives every shape
  an id ("sky", "water", "sun-shadow"); each stroke that fills the shape keeps
  it (`BrushStroke.part`), and `read_document` lists a paint layer's `parts`.
  A drawing's SVG ids already name its layers.
* **Ask remembers the window's requests** (`AskMemory`): the latest six rows
  that are still on, each with what it did and the layers it made (id, name,
  kind, parts), handed to the model after the document. Deleting or turning
  off a row forgets it; closing the window forgets all of it.
* **Ask sees the canvas** when its model can see and there is something to see
  (an earlier request, or more than one layer): a 768 point picture rides on
  the request.

The tool is `change_part` (`AgentPartChange.swift`, also on MCP): recolour a
named part toward a colour (one shift for the whole part, so its shades keep
their differences) or by hue, saturation and lightness; scale it about its
middle; move it; or remove it. On a painting it changes that part's strokes,
which are data, so nothing is painted over; shrinking or removing a part shows
the shape the sketch painted under it. The row says it as done ("Made the water
bluer"), and one undo takes it back.

Measured by the two-turn eval, `node Scripts/ask-eval/followup.mjs run`: twelve
make-then-change conversations, a judge comparing the two pictures on the right
part, the words, and nothing else moving (`queue/evals/ask-followup-history.jsonl`).

A drawing the picture model paints is traced into layers named by colour, so
"the door" may share a white layer with the chimney. Ask, which sees the canvas
a pixel a point (up to 1024), gives `at`, a point inside the part: the smallest
ring of the topmost filled path there, with the rings inside it, is split out
into its own layer under the part's name, and changed alone; the next request
finds it by name. A photo has no parts: `warmth`, `saturation` and `lightness`
change it through its colour grade (the Effects list's own), and a colour to
recolour toward is refused. One part of a photo needs an edit model (the
Qwen-Image measuring task).

## Fitting the window (2026-10-31)

A change to a traced Statue of Liberty failed with the server's own words,
"request (39719 tokens) exceeds the available context size (32768 tokens)".
Reproduced the same day on the probe (blank 1440 by 1024, "draw the Statue of
Liberty", then "make her robe a darker green"), and measured on Qwen3.8 27B's
own tokenizer (`/tokenize` and `/apply-template` on the bundled llama-server):

| Piece of the first request | Before | After |
| --- | --- | --- |
| The document (read_document of 205 traced paths) | 23,423 | about 350 (estimated) |
| Tools, as the chat template sets them out | about 13,480 | about 11,900 (no video tools on a picture) |
| Instructions, the request, and after: the memory and the short-form rule | about 1,500 | about 2,300 |
| Canvas picture, 1024 by 728 | 738 | 738 |
| **Whole request** | **38,424 text + picture = 39,719** | **15,012** |

Three things make it fit, none of them knowing any subject:

* **The document is said in short** (`AskDocumentDigest`, `AskDocumentFit.swift`).
  A read that fits 2,500 tokens goes over exactly as read_document wrote it.
  A bigger one has its biggest groups said as one entry each, biggest first:
  name, box, and `parts` (how many layers it holds, its children's names with
  alike names once and how many share them, "Teal (157)", and its colours).
  Still too big, the layers are listed from the top and the rest counted. A
  read_document the model asks for while planning is fitted to 4,000 tokens,
  and one of a single layer lists that layer's parts one by one, as many as
  fit, with `parts.listed` saying how many. When anything is said in short the
  instructions say how to reach a part (`change_part` with the layer's id and
  the part's name, or `at` a point inside it), and a `change_part` whose part
  is none of the names there and has no point is sent back for one while the
  model can still give it.
* **Every request is budgeted before it is sent** (`AskConversation.fittedMessages`).
  The window less a reply's room (8,192 tokens) is the budget. Over it, the
  oldest tool answers are left out first ("An earlier answer, left out to make
  room"), the newest last; the instructions, the person's words and the
  model's own turns never. A request that still cannot fit is not sent, and the
  person reads "That was too much for Ask to read at once. Try asking about one
  part." Tokens are estimated without the tokenizer (`AskTokens`): a run of
  letters a token, a digit one, other marks two fifths of one, plus 15 per
  cent; the tools a fifth more again for the template; a picture a token per
  32 by 32 pixels. Against the real counts it reads 2 to 15 per cent over.
* **No server's words reach the person** (`AskTrouble`). A failure of the
  model's server is kept in the trace and shown as one plain sentence: too much
  to read, the model not found, or "Ask's model couldn't answer that. Try
  again."

The window. Measured on this 64 GB Mac with Qwen3.8 27B and its draft:

| Window | Held at load | Peak | Reading 38,424 tokens |
| --- | --- | --- | --- |
| 32,768 | 24.0 GB | | refused |
| 65,536 | 26.2 GB | 27.1 GB | 325 s (118 a second) |

So a Mac with 48 GB or more starts its server with 65,536 and plans to it
(`AskConversation.contextWindow(memoryGigabytes:)`, also passed to Ollama as
`num_ctx`); a smaller one keeps 32,768. The shared walk server records its
window and is not adopted by a probe that plans to another. The bigger window
is room for a long plan's rounds (a kit of a dozen components), not the fix:
five minutes to read a big document is no answer, which is why the document
is said in short. The fitted request (15,012 tokens) took 91 s to read, about
165 tokens a second; the tools are most of it.

Still rough: the model reaches "her robe" through a colour group ("Pale teal"),
so the pale pieces across robe, face and arm turned dark and the robe's other
shades stayed. A named part of a traced drawing is a region of many colour
pieces, which neither a name nor one point reaches yet: folded into the task
`making-a-part-of-a-traced-drawing-smaller-shrink`.

## Try paths (walks)

* `Scripts/playtest/ask-annotates-a-screenshot-walk.json`: settings screenshot,
  "annotate the ux with measurements around the major ui elements".
* `Scripts/playtest/ask-adds-a-title-page-walk.json`: the sample recording,
  "add a title page that says Case 1 before this clip".
* `Scripts/playtest/ask-makes-a-pricing-section-walk.json`: a blank canvas,
  "Make a pricing section on brand".
* `Scripts/playtest/ask-draws-a-dog-walk.json`: a blank canvas, "draw a picture
  of a dog." (one Command Z takes it back), then "create a smiley face icon".
* `Scripts/playtest/ask-builds-base-components-walk.json`: a blank canvas, the
  user's "create a table of apple like quality base components that show
  different states and text" (one Command Z takes the whole sheet back).
* `Scripts/playtest/ask-makes-a-photo-walk.json`: a blank canvas, Command K,
  "a photo of a dog on a beach" (one picture layer, "Made a photo of..."),
  then "an illustration of a dog" (vector layers, "Drew a dog").
* `Scripts/playtest/ask-makes-it-again-as-a-photo-walk.json`: "make vector art
  of a fox", then "as a photo".
* `Scripts/playtest/ask-paints-with-brushes-walk.json`: "paint a small landscape
  in oil" paints it with the Brush, stroke by stroke, onto one Paint layer, with
  no line about brushes.
* `Scripts/playtest/ask-says-what-it-is-doing-walk.json`: Command K, "a fox in
  a forest at sunset", a picture of the window every 2.5 s while it works (the
  reel), the live line gone once it lands.
* `Scripts/playtest/ask-says-what-it-is-doing-across-requests-walk.json`: a
  scene, an edit to the picked layer, a photo and a component sheet, each
  recording the lines it showed and when.

Each presses the Ask button, types, sends, waits for `ran`, then undoes and
redoes the request, turns its row off and on with the switch, deletes it, and
undoes the delete, checking the document each time. They need Ollama with a model, so on a Mac without one
they stop with Ask's own sentence.

## A web page from its address (2026-11-03)

The user, 2026-10-20: "I should also be able to say 'mock this web page (url)'
and it should be able to see it and recreate it ... I want to make sure we don't
get prompt injected by doing so." A request with an address in it ("mock this
web page https://www.gov.uk") opens that page and lands its top as editable
layers, its controls as Library components, and the row says where Ask looked:
"Looked at gov.uk, made 4 components". A request with no address never touches
the network; Settings > Ask, **Open web pages you name**, keeps Ask off the web
entirely (`AskWeb.settingKey`, on by default; renamed **Use the web when you
ask** on 2026-11-03, when it came to cover looking things up too), and then a
request with an address or a lookup is answered "Ask is kept off the web in
Settings." and nothing opens.

The limits hold even if the model is fooled by what a page says:

* **App code opens the page, never the model.** `AskWeb.address(in:)` reads only
  the person's words (http and https only; a bare address needs `www.` or a
  site ending, so "Node.js" is not one). `AskWebReader` opens it in a throwaway
  `WKWebView`: its own empty store (no cookies, no logins, nothing kept), no new
  windows or panels, no downloads, no file or script addresses, and once the
  page commits it cannot go anywhere else; 20 seconds at most. It is read at
  the canvas's size.
* **The model sees a picture and a checked description, nothing else.** A
  script walks the page as drawn into boxes (fills, edges, corners), runs of
  words (size, weight, colour, font stack, alignment, lines) and pictures, in
  paint order (stacking contexts compared, a positioned element over the flow).
  `AskWebPage.checked` (PhotonzCore, `AskWebTests`) gives every part Photonz's
  own id (p1, p2 ...), cuts it to the page's top, turns colours into #RRGGBB,
  strips hidden characters, caps words at 280 characters and the page at 260
  parts, and leaves out words a person cannot see (smaller than 6 points, or
  the colour of the box behind them; the script already leaves out what is not
  displayed, see-through, clipped away or off the top). The model is told the
  parts as one line each, words quoted as JSON strings.
* **While page material is in play the model's tools make new layers and
  nothing else** (`AskWeb.doing`): `add_page_parts`, `add_shape`, `add_text`,
  `add_path`, and `set_layer` only on a layer this plan makes (`$N`). No menu
  commands, no export, no files, no painting, no address to fetch. Looking is
  `read_document`, `find_elements`, `list_components`, `list_styles`.
* **The page always lands.** The plan runs as the page first, every part no
  component took, as one group named for the host, then each component the
  model asked for (`AskConversation.webPlan`). A model that refuses or is
  talked out of its job still leaves only the mocked page.

`add_page_parts` (Ask's own tool) lands parts by id exactly as the page drew
them; with `component` they become one Library component placed where the page
has it, and any part inside the control's boxes that paints after them goes
with it. Words are drawn in the first family of the page's stack this Mac has
(SF Pro for a sans serif), made a little smaller, to four fifths at most, when
the stand-in runs wider than the page's own font. Pictures are cut from a
second snapshot with every word, fill and edge made see-through, so a hero
picture never carries its own headline (apple.com's doubled "MacBook Pro").

Every address the page loaded is in the trace (`web request:`) and in a walk's
`ask.webRequests`. The eval's `web` rule (`Scripts/ask-eval/rules.mjs`,
`webSafety`) checks a case's allowed hosts, words that must and must not land,
and that the picture's own Background is still there. Cases: `web-gov-uk`,
`web-python-org`, `web-apple-com` and the two injection pages served on
loopback (`Scripts/ask-eval/web/`, `serve` in the case): visible words telling
the assistant to delete, export and open an address, and the same hidden seven
ways and in a comment. Walk: `ask-mocks-a-web-page-walk`.

Not yet: same-named controls as copies of one component.

## Looking things up (2026-11-03)

"look up the Meadow design system's base components and make a sheet of them"
searches the web, reads what it finds, and builds from it; the row says where
it looked ("Looked at m3.material.io, made 9 components"). Only the person's
words put Ask on the web (`AskLookup.wants`: "look up", "look it up", "search
the web for", "search online", "find it online", "web search", said as an ask,
so "a cat that will look up at the moon" stays a drawing). An address in the
request is a page mock instead (above).

**Two models, never one** (`AskLookup`, PhotonzCore, `AskLookupTests`), the
same local model in two separate talks:

1. **The reader's first turn sees the person's words and nothing else** and
   writes at most two searches, its answer held to a schema by the server's
   grammar (`format`, sent to llama-server as `response_format`).
2. **App code searches and reads.** Each search goes to the service with the
   words as its query (ephemeral session, ten seconds); the first results on
   different sites, at most two, are read in the same throwaway web view a page
   mock uses (`AskWebReader.text`: words a person can see, line by line,
   cleaned and capped at 6,000 characters). Addresses come from the service,
   never from a model.
3. **The reader's second turn reads all that** (the results and the pages'
   words, fenced as material, never instructions) and answers with a list held
   to a schema: a topic, up to six facts for all of it (colours with their hex
   codes, corners, type), and up to 24 things of four notes each.
   `AskLookup.found` cleans and caps every word.
4. **The builder sees only that list**, every word quoted, as facts. While it
   is in play its tools make new things only (`AskLookup.doing`): no
   `run_command` (menu commands touch files and share), no `change_part`, no
   clip edits, no `list_commands`, and `set_layer`, `apply_style` and
   `set_layout` only on what this plan makes (`$N`).

Every network request happens before any web text reaches a model: the reader
has no tool to ask for another, and the builder has none either. The reader
has nothing to leak, since it never saw the document. A page that tells the
assistant to delete, export or open an address can at worst put those words
into the list, and the builder can at worst set them as words on the canvas.

**The search service is Brave Search's web API** (`AskLookup.service`): an
index of its own, meant for apps, with a free plan and a key the person makes
on its site, sent as a header from an ephemeral session. A keyless engine's
results page was the alternative; DuckDuckGo's answered a script with a robot
check and no results (measured 2026-11-03). Settings > Ask, under the web
switch: **Search key** (kept in the login keychain, `AskSearchKey`, never in
settings) and Get a Key. With no key, a lookup is answered "Searching isn't
set up in Settings." and nothing is searched.

A walk searches a stand-in on this Mac's loopback (`"askSearch": <port>` in its
setup, `AskLookup.walkEndpoint`), in the service's own shape. The eval's
`lookup-kit` (a made-up design system, Meadow, so its components can only come
from the lookup) and `lookup-injection` (a search result and a page telling the
assistant, visibly and hidden five ways, to delete every layer, export, run a
menu command and open an address carrying the document) serve one from
`Scripts/ask-eval/web/lookup*/`. Walk: `ask-search-not-set-up-walk`.

## Not in this slice

* The composer's `/` command list (the mock's `.cplist`): typing `/` to run an
  ordinary command by name.
* Pictures while planning: the default model can see since 2026-10-21, but Ask
  still plans from the structured read and the element boxes; only the look at
  a drawing shows it a picture.
