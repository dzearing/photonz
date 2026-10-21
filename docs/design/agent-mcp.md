# Agent MCP: an agent drives the Photonz you have open

An agent (Claude Code, or any MCP client) talks to the Photonz that is running
on this Mac, works in the document open in front of you, and can see what it
made. It never edits files behind the app's back: every step lands in the open
window, in the same undo history a click lands in, so you watch it happen and
one Command Z takes a step back.

This page is the design for the whole MCP ask
(`claude-can-make-and-edit-pictures-and-videos-in`) and the record of the first
slice (`an-agent-can-reach-the-running-app-read-the-open`).

## Install

One command, from the repo:

```
Scripts/install-mcp.sh            # registers "photonz" with Claude Code for this user
Scripts/install-mcp.sh --probe    # registers "photonz-probe", which drives the loop's probe app
```

It runs `claude mcp add --scope user photonz -- <repo>/Scripts/photonz-mcp.sh`.
`Scripts/photonz-mcp.sh` builds the small bridge program (`photonz-mcp`, in its
own build folder `.build-mcp` so it never waits on the app's build) the first
time and whenever its source changed, then runs it. Remove with
`claude mcp remove photonz`.

## How it reaches the app

```
Claude Code ──stdio (MCP JSON-RPC)──> photonz-mcp ──Unix socket──> Photonz.app
```

**The channel lives in the app.** Every build of Photonz (release, Dev and
Probe) listens on a Unix domain socket of its own:

```
~/Library/Application Support/Photonz/Agent/<name>.sock
```

so `release.sock`, `dev.sock` and `probe.sock` sit side by side and the three
apps never answer for each other (`AgentChannelAddress`, PhotonzAgentLink; a
short name because a socket's whole path must fit in 103 bytes, and any other
bundle id is used whole). The socket is
created `0600`, inside the user's own Library: only programs running as you can
connect, which is the same trust a script driving the app through the menu bar
already has. The app speaks MCP itself, one JSON-RPC message per line, so the
tool list, the argument checks and the answers all come from the app that
holds the documents.

**Why a socket, and why the app speaks MCP.** The alternatives were weighed:

| Channel | Why not |
| --- | --- |
| The playtest harness | Compiled out of release, reads one script at launch, and finds controls by name, which a locked screen takes away. A reference for reaching app state, not a transport. |
| HTTP on localhost inside the app | Any web page in a browser can reach a localhost port; a socket file in your Library cannot be reached by one. And an HTTP server cannot launch the app when it is not running. |
| AppleScript / Apple Events | Needs an Automation grant per calling app (a prompt for every terminal), cannot carry a picture back cheaply, and has no schema. |
| A headless copy that edits files | The user ruled it out: the work must happen in the open document and be undoable. |

The socket needs no permission, works the same on a locked screen, and costs
nothing while nobody is connected.

**The bridge** (`Sources/PhotonzMCP`) is deliberately dumb. It finds the app,
launches it if it is not running, and copies lines both ways. If the app quits
mid-session the bridge answers any question still waiting with an error saying
so, and launches and reconnects on the next one, so an agent session outlives
an app restart.

Which app it reaches: `PHOTONZ_APP` = `release`, `dev`, `probe`, or a bundle
id. Unset, it takes the first one running of Dev, release, Probe; with none
running it launches the release app if one is installed, else the Dev build in
`dist/`. **A go loop runner always gets the probe**: the loop exports
`GO_LOOP_PID` to every runner, an MCP server inherits its session's
environment, and a session with `GO_LOOP_PID` that named no app is sent to
the probe (`AgentChannelAddress.choice`). The server a person installs for
themselves is in every runner's session too, and an unmanned runner must never
drive the Dev app a person is working in.

**Opening a session does not start the app.** Claude Code starts every MCP
server when a session opens and asks it for its tool list. The app leaves its
handshake and tool list beside its socket (`<name>.json`,
`AgentMCP.handshake`), and while the app is closed the bridge answers those
two from it, so Photonz starts only when a tool is called. (The very first
session on a machine, before the app has ever run with the channel, starts it
to learn them.) Launching uses `open -g`, so the app starts in the background rather
than taking your keyboard; opening a document from the agent then brings its
window forward the way opening one from Finder does, because you asked to watch.

**The switch.** The channel is a Next feature, `next-agent-channel` in the
Experiments window, on by default in Next and absent from Current. Off, the app
opens no socket at all and the bridge says Photonz is not listening. It is read
at launch.

## Which document

Every tool that works on a document takes an optional `document` id. Ids are
short (`d1`, `d2`, ...), handed out the first time the app sees a window's
editor (when the window is seeded, and again when its canvas joins the window,
which is the only moment a file handed to the app as it starts is seen), and
stay the same for as long as that window is open.
`list_documents` lists them with their titles, files and which one is in front.
With no `document` given, a tool uses the one in front: the editor window
highest in the app's window order (not the key window, which a walk or another
app may be holding).

## What works on a locked screen

Everything in this slice. Nothing in the channel looks a control up by name or
needs a window on screen: reads come from the document, pictures are drawn
offscreen by the same renderer the canvas and the exporter use, and opening a
file opens its window whether or not anybody can see it. So the loop can drive
the agent tools overnight on a locked Mac. (Later slices that run menu
commands go through the command table, not through the menu bar, for the same
reason.)

## Seeing the work

An agent checks what it made by looking. Two kinds of answer:

* **A structured read** (`read_document`): the canvas, the layers as a tree
  with their frames, kinds, text, colours and styles, and on a video the tracks
  top to bottom with each clip's in and out, its cuts and the transitions on
  them, the markers and the playhead. Small enough to read in one go: defaults
  are left out, long text is cut at 200 characters, and past 400 layers the
  rest are counted instead of listed (`AgentDocumentRead`, PhotonzCore).
* **A picture** (`render_picture`, `video_frame`, `contact_sheet`): PNGs drawn
  by `DocumentRenderer`, returned as MCP image content so the model sees them.
  Each is scaled to fit `maxSize` (1024 by default, 2048 at most) so a 12
  megapixel screenshot does not eat the model's context. A video frame is
  drawn by `DocumentFrames`, the code the video exporter writes frames with, so
  the frame the agent sees is the frame the file would hold. A contact sheet is
  a grid of evenly spaced frames, each labelled with its time. Video frames
  come back on black, as the MP4 holds them: a movie has no see-through, and
  a frame handed back with its see-through in (a page fading in over the end
  of a clip) read as a white flash in a picture viewer that the film does
  not have.

## Tools

The tool list lives in PhotonzCore (`AgentTools`), with its JSON schemas, and
is unit tested: every tool has a schema of type object, every required argument
is a declared property, and every call is checked against the schema before
the app sees it, so a wrong argument comes back as a plain error rather than a
guess.

### Slice 1 (this task): reach, read, see, undo

| Tool | What it does | What the app already runs |
| --- | --- | --- |
| `list_documents` | Open documents: id, title, file, picture or video, size, length, in front, can undo/redo | the editors registered at seed (`EditorState.seed`) |
| `list_history` | Captures in History, newest first: index, file, picture or video, when | `CaptureStore.entries` (the History strip) |
| `open_document` | Open a file by path, or a History item by index; answers with its id once it is open | `AppCoordinator.openFileWindow`, `openRecording` (File > Open, History) |
| `read_document` | The structured read above | `PhotonzDocument`, `timelineTracks`, `clipCuts` |
| `render_picture` | PNG of the canvas as it is now (a video at its playhead), or of one layer, or of one region | `DocumentRenderer.render`, `render(only:)` (Copy, Export) |
| `video_frame` | PNG of a video at a time in seconds | `DocumentFrames.frame(atMS:)` (Export Frame, video export) |
| `contact_sheet` | A grid of frames across a range, each labelled with its time | `DocumentFrames` per frame |
| `undo` / `redo` | Step back or forward, one step or several | `EditorState.undo()` / `redo()` (Edit > Undo, Redo) |

### Slice 2 (`every-command-in-the-app-s-menus-can-be-run-by-n`): every command

| Tool | What it does | Maps onto |
| --- | --- | --- |
| `list_commands` | Every command with its name, menu, area, what it needs, its arguments, whether it can run right now on the named document, and a toggle's state. `area` and `readyOnly` narrow it | `AppCommandTable` (PhotonzCore) |
| `run_command` | Run one by name with checked arguments; one run is one undo step | `EditorState.run(_:)` (`Agent/AppCommandRunner.swift`), the switch the menu rows call |

**One table, one switch.** `AppCommandTable` names each command (`split_at_playhead`),
with the words of its menu row, where it lives ("Clip > Speed"), an area
(timeline, layers, edit, measure, view), when it can run in plain words, and its
arguments. `EditorState.run(_:)` and `canRun(_:)` are an exhaustive switch over
the names: each case calls exactly what its menu row used to call, and asks
exactly what its row's dimming asked. The menu bar rows now call
`editor?.run(.name)` and dim on `canRun(.name)`, so a row and an agent can never
disagree. The ⌫ row's "what does Delete take" rule moved into
`EditorState.deleteInHand` for the same reason.

**Picking first.** A menu row acts on what is in hand. An agent cannot click,
so a command declares what it can be told to pick first: `seconds` (moves the
playhead, as a click on the ruler does), `layers` (ids from read_document),
`piece` (one piece of a cut clip) and `track`. A toggle takes `on`; left out it
flips. Then the command's own arguments, checked against their choices
(`set_transition` `kind`, `set_speed` `percent`, `align` `edge`).

**One undo step.** `run_command` runs inside `EditorState.asOneUndoStep`, which
marks the history, runs, and folds whatever landed into one step
(`History.squash(since:)`). Picking a clip and cutting it is one Command Z. The
menu rows are not folded: they behave exactly as before.

**Coverage** (`EveryMenuCommandHasANameTests`): the test reads every `Button`,
`Toggle` and drawn row list in `EditorCommands.swift` and fails for any row whose
action does not go through `run(.name)` unless it is in `leftOut` (on purpose,
with the reason) or `notYet` (a list whose size is pinned, so it only shrinks).
The timeline right-click rows are placed by an exhaustive switch over
`TimelineMenuRow`; the layer right-click rows by title. Every other right-click
row is a menu bar row under the same or other words
(`EveryCommandIsInTheMenuBarTests`), so it is covered through that row. On
2026-10-19: 283 menu bar rows, 149 named, 56 left out, 77 not yet; 37 of 65
timeline right-click rows run a named command.

Right-click rows mostly act on the thing they were opened on through functions
that take it (`rollCutToPlayhead(at:)`, `duplicateLayer(id:)`). An agent reaches
the same edit by picking that thing and running the in-hand command. The rows
that were already "pick, then the in-hand call" now go through `run` too
(split, speed, detach and re-attach, speed stops, transition length and curve).

**The rest of the menu (`the-rest-of-the-menu-commands-can-be-run-by-name`).** The
not-yet list is empty: 284 menu bar rows, 215 named, 68 left out with a reason,
and 57 of 65 timeline right-click rows run a named command (214 commands). The
rules that got the last 77 rows there:

* *What a person is asked for, an agent says.* A row that opens a field, a
  sheet, a popover or a file panel (Rename…, Resize Image…, Canvas Size…, New
  Frame…, Freeze Frame…, Save as Preset…, Edit Word, Add Click…, Import Media…,
  Add Media at Playhead…, Export Sound…, Export Captions…) runs its command with
  the answer left out, and the command asks as it always did. The agent's schema
  makes the answer required, so `run_command` never opens anything
  (`AppCommandRunner+Asked.swift`).
* *A question is not put to an agent.* Turn into Picture and Turn into Path ask
  a person first; while an agent runs (`EditorState.agentIsRunning`) they do
  not, since the agent's one undo step is its way back. Save that would need a
  save box is refused with "export writes it to a path".
* *Picks that were missing.* A caption word is the one being said at `seconds`
  (and `read_document` now lists caption lines with each word's start); a zoom
  is the one at `seconds` on the clip in `layers`; a gap is the one at
  `seconds` on `track`, closed by `delete`; a stretch of keys is the one under
  `seconds`; a value to animate or stop is named in its Animate row's words.
* *Rows built as lists* (Insert Title Page, Animate ▸, Picked in Range) run
  every row through the command (`insert_title`, `animate_property`,
  `section`); the coverage test checks the builder does.
* *Waiting.* Commands that read or write a file, or measure a sound, finish
  before the answer comes back (`runAwaiting`), inside the one undo step.

`Scripts/agent-commands-drill.mjs` drives the probe as an agent does and proves
each command an agent can run is one undo step: it runs it, checks the document
changed, undoes once and checks the document reads exactly as before (43 of 43
on 2026-10-19). It never touches the clipboard, which is the person's.

### Slice 3 (`an-agent-can-draw-a-picture-with-shapes-paths-te`): pictures

| Tool | What it does | Maps onto |
| --- | --- | --- |
| `new_picture` | A blank canvas in a window of its own; answers with its id | `AppCoordinator.newBlankCanvasWindow` (File > New Blank Canvas) |
| `add_shape` | Rectangle, ellipse or highlight in a frame; line or arrow between two points; fill, line, thickness, corners, opacity, shadow | `AnnotationBuilder.layer` (the shape tools), landed by `addDrawnLayer` |
| `add_drawing` | A thing by name (`subject`), optionally `icon`, a `frame`, or the agent's own `svg`: the built-in drawing when the set has one, else the SVG, read into layers. A scene, or any call with a `style` (line art, silhouette, badge, sunset, flat, illustration), is drawn by the illustrator | `DrawingLibrary`, `SVGArtwork`, `PhotonzDocument.addDrawing` (`docs/design/ask.md`, "Drawing a thing") |
| `add_path` | Points in order, corner or smooth (handles worked out Catmull-Rom style unless given), open or closed | `PathBuilder.layer` (the Pen), landed by `addDrawnLayer` |
| `add_text` | Words at a point, font, size, weight, colour, alignment, wrap width; `shadow: false` drops the Text tool's legibility shadow so an SVG keeps the words as text | `TextBuilder.layer` measured by `TextRasterizer.naturalSize` |
| `set_layer` | Frame, name, visibility, fill, line, thickness, corners, opacity, shadow, a text layer's words and size (its box re-measured) | `Layer.geometrySet` (the Position and Size fields), the Effects list's Border and Shadow |
| `find_elements` | The boxes the Measure tool sees in the picture plus every drawn layer, largest first | `ElementBounds.ladder` per probe (`AgentElementScan`) |
| `add_measurement` | `size` of a box or of the element at a point, `gap` between two boxes or around a point, `distance` between two points; answers with the names ("Size 220 × 26") and how many measured sides sit on a real edge | `addElementSize`, `addGapMeasure`, `addMeasure` (Size, Gap and Distance modes) |
| `list_components` / `place_component` | The Library's components (the document's, the shared shelf's, the starters) and a copy of one centred on a point | `componentEntries`, `placeComponent` (dragging a tile) |
| `export` | PNG (scale, background on or off) or SVG to a path | `ExportSizer.data`, `SVGExporter.data` (File > Export) |

Group, ungroup, delete, order, align and combine already run by name through `run_command` (slice 2), so they have no tools of their own. Each call is folded by `asOneUndoStep`, picks what it made, and lands exactly the layer the tool would have: a box's line is a Border in its Effects list, as one drawn by hand (`OutlineRetirement.swift`).

**The pure half** is `AgentDrawing.swift` (PhotonzCore): the typed specs, the builders, `AgentMeasurePlan` (the gap between two boxes, and the edge check) and `AgentElementScan`. The app half is `Sources/Photonz/Agent/AgentDrawingWork.swift`.

**Measuring puts the Measure tool in hand.** The readout planner keeps a number off the elements it measures only while the tool or a measurement is picked, so the measuring calls pick the tool up (and its mode) the way a person measuring has it, and the edge analysis the call ran is handed to the editor so the planner sees it.

**How find_elements reads a picture.** Probes run along the middle of every band between two of the picture's full-width horizontal edges, plus rows half a grid step apart (a switch's own edges are too short to show across the whole picture), with the straight-edged reader (a few milliseconds a probe). Each distinct thin or control-sized thing is read once more with the shape reader, which is the reader Size mode clicks with, so the box listed is the box a click would measure (a field's outer border, a switch's pill); a coarse grid with the shape reader then finds round cards and avatars. On the 1440 x 960 settings fixture it lists all ten controls exactly as Size reads them, 31 boxes in all, in about two seconds in the app (`AgentElementScanFixtureTests`). The edge check (`onEdges`) counts a side as on an edge within 3 px in the same edge map the tool snaps to.

The try paths: scenario 2 (a box in a cloud, as SVG) and scenario 3 (measurements on an open screenshot), run from fresh sessions on 2026-10-19: `queue/audits/2026-10-19-agent-drawing-transcript.md`.

### Slice 4 (`an-agent-can-cut-a-video-from-history-clips-with`): video

| Tool | What it does | Maps onto |
| --- | --- | --- |
| `new_video` | A new video in its own window; with `clips` (History indexes or paths) they are laid end to end on V1, the frame takes the first clip's size, and the length follows what is on it | `AppCoordinator.newBlankVideoWindow` (File > New Video), then `placeTimelineFile` per clip: Premiere's New Sequence from Clip |
| `add_clip` | A recording on a picture track, straight after the last clip unless `seconds` says where, overwriting what is there | `EditorState.placeTimelineFile(_:atMS:onTrack:)`, the overwrite Add at Playhead runs |
| `cut` | The blade at a moment on a clip (or the clip under it on the highest picture track) | `splitClipAtPlayhead` (B, Split at Playhead) |
| `trim` | Keep `fromSeconds` to `toSeconds` of a clip's recording, on the recording's own clock; `ripple` closes or opens the gap on every track. On a title or shape (no recording behind it) the two say when it arrives and goes from its own first frame | `ClipTrimSession` + `applyTrim` (the trim handles); `rippleTrimClipEdge` (⌘ on an edge); `moveLayerStart`/`moveLayerEnd` (a title bar's ends) |
| `move_clip` | Slide a clip to a time, or onto another track; refused where it would land over a clip | `moveClip(_:toInMS:)`, `moveClip(_:toTrack:)` (dragging the bar) |
| `set_transition` | A kind (or `none`) and a length on the cut at `seconds`, from read_document's `cuts`; a kind the cut cannot pay for is refused with the kinds it can take | `setTransition(_:at:)` (the transition picker), `withLength` (Length) |
| `add_title`, `list_titles` | A title page or name card in one of the Insert menu's styles, with its words; with `clip`, a page in front of that clip, the clip and what follows moving along, the default transition on the join | `insertTitleBeforeClip`, `insertTitle` (Sequence > Insert Title Page), then `commitTextEdit` + `relayOutTitle` per line, as typing does |
| `recommended_zooms`, `apply_zooms` | The zooms the app recommends from each recording's kept clicks, on the video's clock; then put them on, one step for every clip | `addSuggestedZooms` on a copy; `suggestZooms(onClip:)` (Suggest Zooms) |
| `set_playhead` | Move the playhead | `moveDocumentPlayhead` |
| `export` | `format: mp4` with `size` (full, 1080p, 720p, 480p) and `quality` (high, standard, small), written straight to a path; answers once the file is there | `EditorState.writeVideo`, the write the Export sheet ends in |

**Times.** Every answer gives times exactly as read_document does
(milliseconds as seconds, never rounded), so a time handed back finds the cut
or clip it was read from (`agentCut(nearMS:)` allows 60 ms either way).

**The end of the video.** The playhead stops on the last frame, a millisecond
short of the end, so a clip added "at the playhead" at the end landed a
millisecond early, overwrote the last frame of the clip before it, and left
the two not quite meeting (no edit point, so no transition). `add_clip` lands
at a moment named outright instead (`placeTimelineFile(_:atMS:onTrack:)`).

**Words.** A title's lines are re-worded with the measure typing uses
(`TextBlockMetrics.roomyBox`): the centred line's box is four fifths of the
frame wide and stays that wide, so the words stay centred. A style's sample
second line the agent did not word is taken out rather than left reading "A
short line about it".

**Zooms come from clicks.** A recording made by Photonz keeps where the
pointer went beside it (`.photonzpointer`); the recommendations are built from
its clicks. A clip with none gets none, and `recommended_zooms` says so.

`Scripts/agent-video-drill.mjs` drives the probe as an agent does over two
short History recordings (copied, with their clicks, into a scratch folder)
and proves each edit is one undo step and the MP4 is written: 14 of 14 on
2026-10-19. Scenario 1, the Case 1 to 5 montage from a fresh session, is in
`queue/audits/2026-10-19-agent-video-transcript.md`.

### Design systems (`claude-can-make-and-edit-pictures-and-videos-in`)

Scenario 4 rebuilds a website's design system as a Library. Components were
already reachable (draw, `group`, `make_component`, `place_component`); what an
agent could not say was the system itself: named colours and type, and the
spacing a component keeps.

| Tool | What it does | Maps onto |
| --- | --- | --- |
| `list_styles` | The Styles shelf: colours (name, hex) and text styles (font, size, weight, colour), with ids | `colorStyles`, `textStyles` |
| `add_style` | A colour or a text style saved by name. Refused when the name is taken | the colour picker's Save style (`saveColorStyle(hex:name:)`); a text style straight onto the shelf (`addTextStyle`), since the Style row only saves from picked words |
| `apply_style` | A style put on layers by name: a text style re-sets the words and re-measures their boxes; a colour paints `fill`, `stroke` or `text` (the inside, else the ink, when unsaid) | dropping a text style's tile on words (`dropTextStyle`); choosing a colour style in a colour row (`bindColorStyle`) |
| `set_layout` | A group or frame as a `stack` (row or column), `grid` or `free`, with gap, row gap, columns, padding (one number or four sides), width and height (points or `hug`), spread and wrap | the inspector's Layout section: `setGroupLayout(id:kind:)` then `updateGroupLayout` |

A button is a group of a box and its words, made a padded row stack, with the
box made its surface (`run_command surface_behind`, Layer > Surface Behind the
Rest): painted to the group's edges, the words laid out on top. That is how the
starter Button is built, and `Scripts/agent-design-drill.mjs` builds one that
way through the bridge and proves each step is one undo step (16 of 16 on
2026-10-19). `read_document` shows a group's `layout`.

**Where a group is.** A group's stored size is unused; its box is
`localBounds`, which is already in its parent's space. `read_document` used to
hand an agent the stored 0 x 0 frame, and `set_layer` and every tool answer
shifted the box by the group's anchor a second time (a group at 100, 100
answered 200, 200). Both now go through `AgentDrawing.box(of:)`; the layers
inside a group are still measured from the group's top left, and the
`read_document` description says so.

**Words inside a copy.** A copy's pieces are rebuilt from its original after
every edit, so `set_layer` writing words straight onto one answered "done"
and changed nothing (scenario 4's first run detached thirty list rows with
make_unique to get round it). Words now land where typing over the piece
lands (`ComponentPieceEditing`): on the copy's own answer to the original's
wording knob, after giving the original one when it has none, which is the
inspector's Make Adjustable that an agent cannot press
(`PhotonzDocument.agentWordCopyPiece`). Anything else set on a piece is refused
with the two ways forward (edit_original, make_unique).

**Reading one layer.** `read_document` lists 400 layers at most, top first; a
board with a page of thirty rows runs past that and the rows below stop being
listed. `layer` reads one group, frame or component and everything inside it
with the whole budget.

### The skill and the plugin

`plugin/` is a Claude Code plugin: the Photonz skill
(`plugin/skills/photonz/SKILL.md`) and the server (`plugin/.mcp.json`, which
runs `Scripts/photonz-mcp.sh`). The skill is the part an agent reads before it
starts: the do, look, fix loop (read, do one thing, render it, judge it against
the ask, fix), which tool serves which area, the facts that cost a wasted step
when missed (top-left points, a group's children measured from its corner,
the Text tool's legibility shadow, absolute export paths), the house look (one
8 point grid, one of each: accent, radius, stroke, family; the app's own title
styles and transitions, the same throughout; legible always) and a recipe for
each of the user's four scenarios.

`Scripts/install-mcp.sh` registers the server and links the skill into the
user's skills folder (`~/.claude/skills/photonz`, a link so it follows the
repo); `--remove` takes both out, and only a link it made. For one session
without installing anything: `claude --plugin-dir <repo>/plugin`. The scenario
runs use the plugin for the skill and `--strict-mcp-config` with the probe
server, so a session has exactly the skill and the server.

A website is seen through headless Chrome (the skill gives the command, with a
time budget so animated pages settle), opened in Photonz as a picture and read
with `render_picture` regions and `find_elements`.

## Answers and errors

A tool answer is MCP `content`: a short text part (JSON for reads, one line
for actions) and, for the picture tools, an image part. A tool that cannot do
what it was asked answers with `isError: true` and one plain sentence saying
why and what to do instead ("No document is open. Open one with
open_document."). A malformed request gets a JSON-RPC error. Nothing in an
answer is shown to the person, so the copy rules for the app's chrome do not
apply, but the answers still never name a vendor.

## Trying it

```
Scripts/install-mcp.sh --probe          # once
Scripts/probe-app.sh                    # or let the first tool call start it
claude                                  # a fresh session, then ask:
> what is open in Photonz, and show me the frame 10 seconds in
```

The first slice's run of exactly that is in
`queue/audits/2026-10-19-agent-mcp-transcript.md`.

## Not in this slice

* Notifications when the person changes the document while the agent works:
  the agent reads again when it needs to.
* Shipping the bridge inside the app bundle so a release user needs no repo.
  Until then the install command is a developer's.
