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

Each presses the Ask button, types, sends, waits for `ran`, then undoes and
redoes the request, turns its row off and on with the switch, deletes it, and
undoes the delete, checking the document each time. They need Ollama with a model, so on a Mac without one
they stop with Ask's own sentence.

## Not in this slice

* The composer's `/` command list (the mock's `.cplist`): typing `/` to run an
  ordinary command by name.
* Pictures: the default model reads text only, so Ask plans from the
  structured read and the element boxes, never from a rendered picture.
