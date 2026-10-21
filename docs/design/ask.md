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
built-in, illustration, your svg); Ask keeps it per run (`AskDrawingSource`),
the walk state shows it as `ask.sources`, and the eval counts it, so a score
climbed by looking things up shows as a share of lookups.

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

"Draw a dog", "create a smiley face icon": one `add_drawing` call, never a
pile of `add_shape` and `add_path` calls placed blind (that is what drew the
user's dog as brown shards on 2026-10-20, and the smiley with its eyes above its
head).

* **The built-in set first.** `Resources/Drawings/drawings.json` holds 992 clean
  flat drawings of everyday things: the Twemoji graphics (CC-BY 4.0, credited in
  Open Source Notices, licence beside the file), named and given the words
  people use from Unicode's CLDR, plus a hand list of everyday words where the
  name is not one ("car" is "automobile", a coffee cup is "hot beverage").
  `Scripts/make-drawings.mjs` builds it; `DrawingLibrary.match` finds in it.
* **The model's own SVG otherwise.** When the set has nothing, the call goes
  back to the model while it is still planning and it writes ONE whole SVG
  (a model writes a picture far better at once than as twenty separate shapes).
* **As layers, never a picture.** `SVGArtwork` reads the SVG (paths with every
  command and arcs, circles, ellipses, rects, polygons, groups, transforms,
  fill rules, a gradient's first colour): circles and ellipses become oval
  layers, boxes rectangles, the rest Pen paths with their curves and holes. The
  parts go in one group named for the thing; a face's parts are named Face,
  Left eye, Right eye, Mouth from where they sit (`FaceParts`). One Command Z
  takes the lot.
* **Placed.** Centred, 60 per cent of the canvas's shorter side, or in the box
  asked for, kept on the canvas. An icon is a 512 point icon frame with the
  drawing on its live area (the keylines); on a blank picture (nothing but its
  flat background) the picture becomes that frame.
* **Looked at before it hands back** (`AskDrawingCheck`). The drawing is
  rendered and shown, with no hint of the request, to a model on this Mac that
  can see (`llama3.2-vision`, first of `AskModels.preferredVision`). If what it
  names shares a word with the thing, it reads; if not, the planning model says
  yes or no. A miss is taken back and drawn again, told what was seen, at most
  twice; then Ask says "I couldn't make a clear drawing of that. Nothing was
  changed." No model that can see: Ask hands back without looking.

Both models are asked with their window size pinned (32k planning, 4k
looking): left out, Ollama loads them at its own default (128k), which swaps
the planning model out on every look.

Measured 2026-10-20 (M4 Max, 64 GB, `Scripts/ask-eval.sh`, the 13 drawing
cases): drawing score 35.4 before, 92 after; named right blind 1 of 13 before,
13 of 13 after; median 18.4 s from Ask to the finished drawing. Things the set
does not have are where it is still weak: a lighthouse and a windmill were
each drawn three times by the model and refused by the look.

## Drawing an illustration

"Draw an svg illustration of a sun over mountains" once gave three flat green
triangles and a yellow circle, one triangle poking past its own box (the user,
2026-10-20, `queue/audits/2026-10-20-user-ask-sun-over-mountains.png`). A
small model on this Mac cannot hold the light direction, the value order and a
broken ridgeline at once, so for a scene it makes only the narrow choices and
Photonz does the craft.

* **What counts.** `add_drawing` with a scene as its subject (mountains, hills,
  a forest, a lake, the sea, a cliff, a lighthouse, a city skyline) or with a
  `style`, or a lone animal asked for as an illustration (`IllustrationBrief`).
  A thing by itself (a dog, a tree, a cup) and any icon stay on the built-in
  set. Ask adds the look words the person typed ("as line art", "a badge") to
  the call's `style` when the model leaves them out.
* **Styles.** painted (light and shadow faces, depth haze), sunset (ridge bands
  stepping in value under a sunset sky), flat (two tones a form, no ramps), line
  art (ink lines, outline heaviest), silhouette (one ink, snow and ridge light
  cut out as paper), and badge (any of them in a circle with a frame line).
  With none named the illustrator picks one and the change row says which:
  "Drew a sunset illustration", "Drew a silhouette badge".
* **Eight passes, each checked** (`Illustrator`, `IllustrationWork`):
  1. brief (subject, style, time of day); 2. composition (frame, a focal point
  off centre, the horizon off the middle, planes blocked in as overlapping
  boxes); 3. values (three to five planes in grey, nearest darkest); 4. shape
  (lopsided peaks, broken ridgelines by midpoint displacement, one pine
  repeated at varied heights); 5. light (one light; every peak split along a
  broken crease into a lit side and a shadow face away from it, ridge light on
  the lit side, cast shadows away from it); 6. colour (one palette per time of
  day, every plane re-lit to its planned value, distance lighter and bluer, a
  sky gradient); 7. detail and finish (snow caps with a ragged edge, birds near
  the focus, reflections and glitter on water, windows, the lamp's beams, line
  weights, everything cut to the frame in its geometry, so no masks); 8.
  critique (values, the squint, light agreement, nothing past the frame, the
  focus big enough to read at 32 points). A failed check revises the tuning
  (more value contrast, another seed) and draws again, twice at most.
* **Pieces** (`IllustrationPieces`): a ridge, its shadow face, ridge light, a
  snow cap, a pine and a treeline, a ray burst, glitter, ripples, a reflection,
  rolling hills, a streak of cloud, stars, birds, a skyline, a lighthouse and
  cottage, a sitting fox. A scene is composed from them.
* **As layers.** The scene is written as one clean SVG (a `<g id>` per part of
  the picture, an id on every shape, gradients in defs) and read with
  `SVGArtwork.parse(keepingGroups: true)`: a group per part (Sky, Sun, Far
  range, Middle range...), each shape a layer named for what it is (Ridge,
  Shadow face, Snow, Ridge light), gradients as the app's own linear and radial
  paints. Fitted whole at four fifths of the canvas.
* **Not looked at.** Ask's blind look (below) skips an illustration: a miss
  would send it back to the model's own SVG, which is exactly what it replaces.

`Scripts/ask-eval.sh` has eight illustration cases (`"crafted": true`), judged
on the extra "crafted" line in `Scripts/ask-eval/rubric-crafted.md`; the
user's own picture scores crafted 1 in calibration.

## The model

Runtime: **Ollama**, on its loopback port (`127.0.0.1:11434`), the only address
Ask ever calls. Default: **`qwen3:30b`** (Qwen3 30B A3B, a mixture of experts
with 3B active, 18.6 GB), run with thinking off and a 32k window. Automatic
takes the first of `qwen3:30b`, `qwen3:32b`, `qwen3:14b`, `qwen3:8b` the Mac has
(`AskModels`).

Measured on 2026-10-19, M4 Max, 64 GB, the screenshot request:

| Model | Result |
| --- | --- |
| `qwen3:30b` (Ollama) | Plan in 22 s from a cold prompt, 25 measurements before the sorting and the cap; tool calls well formed |
| Qwen3 30B A3B Instruct 2507 (a community build) | Wrote its tool call as text with a broken tag; Ask now reads those too, but the stock tag is the default |
| `gpt-oss:20b` | Its template cannot read a property given as a choice of types; with that flattened it ignored the no-thinking switch, thought for 122 s and gave up |
| Apple's on-device model (FoundationModels) | Not usable: its window is 4,096 tokens and the tool list plus the document read is about 5,800 before the request |

With no model: Settings says so and offers the download of `qwen3:30b` (18.6 GB,
stated before you press it) through Ollama's own pull; with no Ollama, Settings
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
* Pictures: the default model reads text only, so Ask plans from the
  structured read and the element boxes, never from a rendered picture.
