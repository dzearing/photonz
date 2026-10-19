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
~/Library/Application Support/Photonz/Agent/<bundle id>.sock
```

so `com.dzearing.photonz.sock`, `com.dzearing.photonz.dev.sock` and
`com.dzearing.photonz.probe.sock` sit side by side and the three apps never
answer for each other (`AgentChannelAddress`, PhotonzCore). The socket is
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
  a grid of evenly spaced frames, each labelled with its time.

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
| `list_commands` | Every command with its name, menu title, area, arguments, and whether it can run right now on the named document | a command table in PhotonzCore that the menu bar, the timeline right-click rows and the layer right-click rows read |
| `run_command` | Run one by name with checked arguments; one run is one undo step | the same action the menu row calls, through `EditorState.perform` |

A coverage test lists every menu and right-click row and fails for any with no
command name, apart from a written left-out list.

### Slice 3 (`an-agent-can-draw-a-picture-with-shapes-paths-te`): pictures

`new_picture`, `add_shape` (rectangle, ellipse, line, arrow, highlight),
`add_path` (anchors, corner or smooth), `add_text`, `set_layer` (frame, fill,
stroke, corner radius, shadow, opacity, name, order, visibility), `group` /
`ungroup`, `delete_layers`, `add_measurement` and `add_annotation` (the app's
own redline marks, editable afterwards), `find_elements` (the element detector
the Measure tool snaps to), `export` (PNG, SVG). Each maps onto the
`EditorState` call the tool or panel already makes, inside `perform`, so it
undoes like a click. Scenarios 2 (a box in a cloud, as SVG) and 3 (measurements
on an open screenshot) are its try paths.

### Slice 4 (`an-agent-can-cut-a-video-from-history-clips-with`): video

`new_video`, `add_clip` (from History or a file, onto a track at a time),
`cut` (blade at a time), `trim`, `move_clip`, `set_transition` (the picker's
kinds and lengths), `add_title` (the built-in title styles), `recommended_zooms`
and `apply_zooms` (the zoom lane's own suggestions), `set_playhead`, `export`
(MP4). Scenario 1 (the Case 1 to 5 montage) is its try path.

### After the slices (`claude-can-make-and-edit-pictures-and-videos-in`)

The skill that teaches an agent the house look and the look-then-fix loop,
Library components from outside (scenario 4), the four scenarios rerun from a
fresh session, and the coverage count.

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

* Driving the menus (slice 2), drawing and video edits (slices 3 and 4).
* Notifications when the person changes the document while the agent works:
  the agent reads again when it needs to.
* Shipping the bridge inside the app bundle so a release user needs no repo.
  Until then the install command is a developer's.
