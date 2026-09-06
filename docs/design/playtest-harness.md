# Scripted playtest harness

A way for an unmanned run to drive the real editor: open a file in the probe
build, press keys, click and drag on the canvas, render the window offscreen
at the moments you care about, and read back what the editor thinks happened.
It exists so an audit starts from a working walk instead of rebuilding one by
hand. Three audits in a row did that before this landed.

The harness lives in `Sources/Photonz/Playtest/PlaytestHarness.swift`. The
script format lives in `PhotonzCore` (`PlaytestScript.swift`, tested) so a
malformed script fails with a readable error before anything runs.

## Who can run it

- **Only the probe bundle** (`dist/Photonz Probe.app`, `com.dzearing.photonz.probe`)
  ever acts on a script. The dev app a person works in never does, and the
  shipping build does not contain the code: `Scripts/build-app.sh` defines
  `PHOTONZ_PLAYTEST` for the dev and probe variants only. Dev carries the code
  so dev and probe share one compiled product and flipping between them never
  triggers a rebuild.
- The probe is launched with `--playtest <script.json>` (via `open --args`).
  Nothing is read from a fixed location, so a stale request can never fire.
- The probe never becomes the active app, and macOS would not let it if we
  tried. The window it opens is kept at zero alpha for the whole run, so a
  person at the machine sees nothing and keeps their keyboard focus. That one
  fact decides which keyboard shortcuts a walk can press: see "Which shortcuts
  a walk can press" below.

## Run one

```bash
Scripts/playtest.sh Scripts/playtest/redline-walk.json           # build, run, wait, quit
Scripts/playtest-all.sh                                          # every walk, one line each
Scripts/playtest.sh path/to/walk.json --no-build                 # reuse the built probe
Scripts/playtest.sh path/to/walk.json --keep                     # leave the probe running
PHOTONZ_PLAYTEST_TIMEOUT=300 Scripts/playtest.sh path/to/walk.json
```

The wrapper builds and launches the probe with the script, waits for
`done.json` in the output folder, prints it plus the last log lines, lists the
renders, and quits the probe. Exit status is 0 only when `done.json` says
`ok`. `Scripts/probe-app.sh --playtest <script>` does the launch alone.

The example walk, `Scripts/playtest/redline-walk.json`, opens the settings
fixture and walks the whole redline flow: Distance, Size, Gap, Alignment, a
captioned arrow, Copy as Spec List and Copy Image. Copy it and change the
points to write a new one.

## What you get back

Everything lands in the script's `out` folder (default: `out` beside the
script; a relative path is relative to the script). A script that does not
parse lands there too, with `done.json` naming the step and the field, so a
typo comes back in a second rather than as a timeout on an empty folder:

- `<name>.png` for every `snapshot` (the editor window at 2x, exactly what a
  person would see) and every `render` (the composited document). A `-sc.png`
  beside it takes in anything hanging off that window as well, which is how a
  tooltip — a window of its own, hung on the one it labels — is in the picture
  at all; the picture then covers the rectangle the family fills rather than
  the window alone.
- `log.json`: one entry per step with the elapsed time, what the step did,
  and, after anything that changes the editor, its state: tool, Measure mode,
  hint text, copy confirmation, layer count, whether Undo and Redo have
  anything to do (`canUndo`, `canRedo`), whether this process has focus at all
  (`appActive`, always false in a walk), every measurement (name, value,
  role, feet, frame), every annotation (shape, caption, frame), legend
  entries, whether the edge map is ready, who has the keyboard, and the
  pointer's shape (`cursor`: `arrow`, `openHand`, `closedHand`, `crosshair`,
  `resize-up-down`, `rotate`, …) alongside what the canvas DECIDED was under
  the pointer (`cue`: `none`, `grab`, `rotate`, `resize-<axis>`), the canvas grid as the layers
  themselves are drawing it (`grid`: the zoom, a strength per rung, and which
  side of the picture it is on, or "nothing drawn"). A `drag` line
  also reports the cursor WHILE the button was down, the only moment a
  closed-hand grab exists. The real OS pointer is not where a synthesized click
  is, so read the cursor from a `move` step's `describe`, not from the state
  line right after a drag.

  **Assert on `cue` and read `cursor` as corroboration.** `cue` is the app's own
  answer for the point the walk moved to, so it is exact and repeatable.
  `cursor` is the real OS pointer, and a walk's pointer is synthesized while
  the real one is somewhere else on the screen entirely: any redraw that
  re-reads the real pointer position hands the cue back, so one stage in a long
  walk can come back `arrow` while the other thirty agree. That is the harness,
  not the app. `Scripts/playtest/grab-cue.json` walks every handle on the canvas
  this way.
- `menus-<stage>.json` and `menus-<stage>.txt` for every `menus` step: the menu
  bar as a tree for a program, and the same reading as indented text you can
  `cat` when you want to quote a menu item.
- `done.json`: `status` (`ok` or `failed`), how many steps completed, and the
  error when one failed. The run stops at the first failing step; the log
  keeps everything before it.

## Script format

```json
{
  "out": "/tmp/photonz-playtest/my-walk",
  "setup": { "forget": ["text"], "captures": ["fixtures/probe.png"] },
  "steps": [
    { "do": "open", "file": "../../Tests/PhotonzRenderTests/Fixtures/settings-pane-2x.png", "width": 1280, "height": 840 },
    { "do": "measureMode", "mode": "size" },
    { "do": "move", "at": [356, 786] },
    { "do": "snapshot", "name": "size-hover" },
    { "do": "click", "at": [356, 786] },
    { "do": "describe", "stage": "size", "note": "Save Changes measured" }
  ]
}
```

Points are in **document units** (what the `open` log line reports, for a 2x
capture that is device pixels) unless a step says `"space": "view"` (the canvas
view's own points) or `"space": "window"` (the whole window, measured down from
its top-left corner). Window space is the only way to name a spot that is NOT on
the picture, like the right hand panel or the chrome beside it; the `blank` and
`open` log lines report the window size and the canvas size, so you can work out
where the panel starts. The `open` entry also states the document size and pixel
scale so you can read coordinates straight off the fixture.

### What a walk needs set up, in the walk

The probe keeps its settings between runs on purpose: that is what a person's
app does. The cost is that a walk which changes one of them passes the first
time and fails the next, having gone looking for a value it moved itself. Two
walks were doing exactly that on 2026-09-04 — one changed the remembered text
size from 24 to 48 and then could not find the 24, and one needed a picture
copied into the Screenshots folder by hand and said so only in a note.

So a walk SAYS what it needs, in an optional `setup` block above `steps`, and
the harness performs it before step one and undoes it when the run ends, pass
or fail. The `setup` line is logged as step 0, so the log says what was done.

| In `setup` | what it takes | what happens |
| --- | --- | --- |
| `forget` | a list of memories (below) | Those settings go back to the values a machine that had never run Photonz would have, before the first step. |
| `captures` | picture files, relative to the script or absolute | Each is copied into the capture folder (`~/Pictures/Screenshots`) so the Library's Media shelf has it, and taken away again at the end. A name already taken there fails the walk rather than writing over someone's screenshot. |

The memories a walk can forget, by the word it uses:

| Word | What goes back to new |
| --- | --- |
| `text` | The font, size, weight and colour a new text block is made in. |
| `color` | The recent colours, and the foreground and background fills. |
| `shapes` | The look a new shape, arrow or callout is drawn in: paint, stroke, corner radius, and whether it has a fill at all. |
| `measure` | The Measure mode and the saved measure looks. |
| `tools` | Which tool each family in the toolbar stands for, and the wand's reach. |
| `groups` | Which groups in the layers list are open. |
| `panel` | Whether the dock and the Library are showing, how wide the dock is, which shelf the Library is on, and the order and collapsed state of the dock's sections. |
| `grid` | Whether the canvas grid is on, how far apart its lines are, how often one is stronger, and whether it draws rows as well as columns. |

A walk that reads a setting it never set is the one to think about here. Drawing
a rectangle and then opening its Fill colour needs `"forget": ["shapes"]`,
because the shape tool remembers the look it was last left holding, and a
rectangle left with no fill at all has no Fill colour to open.

`Scripts/playtest-all.sh` runs every walk in the folder and prints a line each.
Run it twice in a row: the same answers both times is what says the set can be
trusted. `PlaytestWalkSetupTests` holds the rest of the line — no walk may hide
setup in prose, every borrowed picture has to exist, and no walk may name a menu
by a value an earlier step of the same walk chose.

| `do` | fields | what happens |
| --- | --- | --- |
| `blank` | optional `canvasWidth` `canvasHeight`, optional `width` `height`, optional `card` | Opens a NEW EMPTY WINDOW and hands it a blank white canvas, the way the empty window's Blank canvas row does once a size is chosen. Defaults to the offered size (`BlankCanvas.defaultPreset`). `width`/`height` set the window frame, as in `open`. `card` names a snapshot taken of the empty window first, which is the only way to photograph the onboarding card — it stops existing the moment a document arrives. This is how a walk starts from nothing instead of from a screenshot. |
| `open` | `file`, optional `width` `height` | Opens the file in an editor window (path relative to the script or absolute), waits until it can be driven, hides it, sizes it. Every later step targets this editor. |
| `wait` | `seconds` | Sleeps. Prefer `waitFor`. |
| `key` | `key`, optional `modifiers` | Presses and releases a key. `key` is one character or `return`, `escape`, `tab`, `space`, `delete`, `left`, `right`, `up`, `down`. Modifiers: `command`, `shift`, `option`, `control`. Plain keys go to the window like typing; chords are offered to the window, then the menu bar, and then, if neither claimed them as a shortcut, sent to the window as an ordinary press (which is what ⇧↑ in a number field is). The log says who took them: `window`, `menu` or `responder chain`. |
| `appKey` | `key`, optional `modifiers` | Presses and releases a key by handing it to the APPLICATION instead of posting it into the window. `key` goes straight to the window, which is right for typing and for menu shortcuts but invisible to anything watching the app as a whole — and an application-wide event monitor is what takes the history overlay down on Esc and on a click outside it. Use this when the thing you are driving listens to the app rather than to a window; use `key` for everything else. |
| `shortcut` | `key`, optional `modifiers` `menuItem` `checked` | Presses a chord and REQUIRES it to reach a menu item that actually runs. Fails, loudly and with the reason, when no menu item carries the chord, when the item is not the one `menuItem` names, when something else takes the press, or when the item has nothing behind it. `checked` is for a SETTING's item: one that is simply on or off keeps ONE name and says its state with a checkmark, so `checked` names the tick the item must be wearing BEFORE the press and the walk fails when the checkmark lies. Use it for app-level shortcuts (Capture, New Window, Open); a window-scoped one fails by design and tells you to use `action` instead. See "Which shortcuts a walk can press" below. |
| `move` | `at` | Moves the pointer over the canvas (hover previews, snap dots). |
| `pinch` | `to`, optional `steps` | Pinches the zoom to `to` (1 is 100%), around the middle of the canvas, in `steps` even nudges through the very call two fingers on a trackpad make. Every nudge is checked and the log line says whether the grid was drawn at each one, with `gridDuringPinch` in the state carrying one reading per nudge. This is the only step that can see a fault which exists only WHILE the zoom is moving: a `zoomIn` steps straight over it, and so does a snapshot, since the redraw that takes the picture is the redraw that puts things back. `Scripts/playtest/grid-pinch-walk.json` is the walk that reads it. |
| `hover` | `label` or `at`, optional `window` | Rests the pointer on a control until its tooltip shows: `label` is the text the tooltip starts with ("Arrow", "Measure"); `at` is a point, and one over no control leaves the tooltip behind. The log line says what showed and where, and a `snapshot` taken now includes it. `window` names another of the app's windows to rest in, by its title, the way `snapshot` does: the capture history is a floating panel of its own, so it is the only way to reach its controls. A point inside a named window is in window space, since there is no canvas there to measure from. |
| `click` | `at`, optional `count`, `modifiers` | Mouse down and up on the canvas. The log line also says what the click cost: `handler` is the synchronous mouse-down and mouse-up time, and `mainBusy` is how long the main thread stayed busy afterwards, over how many run-loop passes, and the longest single pass (see "Reading the cost of a step" below). |
| `drag` | `from`, `to`, optional `steps`, `modifiers`, `hold`, `wobble` | Mouse down, a run of drags, mouse up. `modifiers` are held for the whole gesture (Command drags free of every magnet). `hold` names a snapshot taken with the button still down, just before the release: the only way to photograph something that exists only mid-drag, like the yellow snap guide. `wobble` shakes the pointer by that many points as it travels, mostly back and forth along the line it is walking and half as much sideways, which is what a hand actually does. Every drag line reports what the snap guides did across the run: `guides caught 1, let go 1, changed 2, went back on themselves 0`. The last number is the one to read — a walk over a dense screenshot honestly crosses dozens of lines, but a guide that RETURNS to one it just left is the flicker, and it should be zero however hard the hand shakes. `Scripts/playtest/snap-hold-walk.json` and `snap-hold-foot-walk.json` are the walks that measure it. |
| `focus` | `field` | Gives the keyboard to a named text field in the inspector, by the label the field shows ("W", "H", "X"). Everything after it — `type`, `key` tab, an arrow key — then goes to that field, the way it would for a person who clicked it. Fails with the list of fields that ARE on screen, which is usually the fastest way to learn why a section is not showing. Needed because `click` goes to the canvas view and can never reach the inspector. |
| `type` | `text` | Inserts text into whatever field has the keyboard. Fails when nothing does. Note this bypasses the keyboard entirely; to prove a field still takes ordinary typing, press the characters with `key`. |
| `tool` | `tool` | Picks a tool directly (`select`, `arrow`, `measure`, and so on), for when its key was not honoured. |
| `measureMode` | `mode` | Presses I until the Measure tool is in `distance`, `size`, `gap` or `alignment`, and logs how many presses it took. |
| `waitFor` | `condition`, optional `value`, `timeout` | Polls until `edgeMap` (element detection done), `captionField` (a caption field has the keyboard), `tool` = `value`, or `measureMode` = `value`. Times out as a failure. |
| `dragComponent` | `at` | Holds the component picked on the Library shelf over a point WITHOUT letting go, so a `snapshot` taken next photographs the landing box and the dashed frame it would join. The log line says what the canvas answered: whether it would place a copy or refuse, how big the box is, and whether it is joining a frame. A synthesized mouse drag cannot start a real drag session, so this is the only way to see a component drag in flight. |
| `dropComponent` | `at` | Lets go of the component picked on the Library shelf at a point, the way dropping its tile on the canvas does, through the same pasteboard the real drag writes. |
| `dragFile` | `file`, `at`, optional `space` `hold` `release` | Holds a file over a point WITHOUT letting go (path relative to the script or absolute). The log line says what answered: that it would place a copy, or that it refuses the file and the pointer shows the no-entry sign, which is the only way a walk can record a refusal, since letting go of a refused file does nothing to see. It names every destination the drag was offered to, innermost first, and the one that took it, so a walk can tell the picture's answer from the window's. With `"space": "window"` the point can be anywhere in the window, not just on the picture. `hold` names a picture taken while it is in the air. `release` lets go on the view that answered, so a step can prove a file the pointer promised actually lands rather than only that it was promised. |
| `dropImage` | `file`, `at`, `hold` | Lets go of a file over the canvas at a point, the way one arrives from the Finder (path relative to the script or absolute). The picture lands where you let go, fitted to the frame under the pointer or to the canvas. `hold` names a picture taken while the file is still in the air, which is the only moment the landing outline exists. |
| `snapshot` | `name`, optional `window` | Renders the window's content offscreen to `<name>.png`. While a sheet is up the SHEET is what gets photographed, since that is what a person is looking at. When the probe holds Screen Recording it also writes `<name>-sc.png`, the window as the screen shows it; read that one for anything judged by color or weight (see below). `window` names another of the app's windows to photograph instead, by its title ("Capture History"), which is the only way to picture a floating panel. |
| `render` | `name` | Composites the document itself to `<name>.png`. |
| `describe` | `stage`, optional `note` | Logs the editor's state under `stage`. |
| `clearClipboard` | | Empties the clipboard. |
| `readClipboard` | `stage` | Logs the clipboard's types and text. |
| `selectRow` | `row`, optional `modifiers` | Clicks a row in the layers list by the name it shows, the way a person picks a layer out of the list instead of off the picture. Modifiers read as they do under a pointer: shift ranges from the anchor row, command adds or removes. This is the only way to select a LOCKED layer, since a click on the picture falls straight through one. Fails with the list of rows that ARE there. |
| `panel` | `stage` | Writes what the RIGHT HAND PANEL, and any popover open on top of it, are showing to the log and to `panel-<stage>.json`: every tile on the Library shelf, every row in the layers list, every control a `press` can land on (with the row it is on and whether it is far enough up the dock to be reached where it is), and every menu in the dock, by the names the steps below use for them. The `menus` step for the panel, and the first step to write when a walk cannot find something. |
| `press` | `control`, optional `in` `count` `modifiers` | Presses something in the RIGHT HAND PANEL, or in a popover open on top of it, by the words on it: a button ("Clear Stretch"), one segment of a picker ("Row", "Fixed"), a row that goes somewhere. `in` names the row it sits on, for when the same word appears twice — the Layout section holds a Hug and a Fixed for Width and another pair for Height, so `{"control": "Fixed", "in": "Width"}`. The press is real mouse events posted to the app's queue, never the control's action called behind its back, so a control that is covered or wired to nothing fails the walk. Fails with the list of controls that ARE there; a `panel` step prints the same list. |
| `panelMenu` | `menu`, optional `shot` `choose` | Opens a menu INSIDE the window by the row it sits on ("Size", "Vertical") or, for a menu on no named row, by the words on its button ("Add"). Name it by its row wherever there is one: a menu wears its own value, so a walk that called it "24 pt" is naming something the very next field changes. A `panel` step reads them "Size (24 pt)": the name first, then what it is showing. writes its rows to the log, and closes it. `shot` names a real screen capture of the menu in place over the panel, written to `<shot>-sc.png` — the only kind of picture of a menu there is, since a menu is drawn outside this process and renders blank offscreen. `choose` picks one of its rows by title instead of closing with nothing chosen. Needs the Screen Recording grant for the picture; the rows reach the log either way. |
| `scrollPanel` | `by`, optional `row` | Scrolls the panel list `by` points, negative going DOWN the list. The log says how many rows were on screen before and after, which rows arrived, how many row bodies were built, and what it cost the main thread. Name a `row` to pick which list; leave it out for the layers list wherever it is sitting, which is what a walk crawling down a long list wants, since the row it started from scrolls away and stops being built. The layers list builds only the rows you can see, so this is the only way to reach the rest. A synthesised wheel is usually swallowed by a SwiftUI scroll area, so the step falls back to scrolling directly and SAYS which of the two happened. |
| `dragTile` | `tile`, `to`, optional `space` `hold` | Picks a tile up off the Library shelf by its name and lets it go on the picture, through the canvas's own drag destination — the same calls a drop from the Finder makes, carrying the very payload the tile's own drag hands over. A capture tile can be named by the caption it shows ("10 hours ago") or, better for a walk that has to keep working, by its file name. `hold` names a picture taken while it is still in the air, which is the only moment the landing outline exists. |
| `dragHandle` | `area`, optional `by` `expect` `hold` | Drags the grab bar under a resizable area of the right hand panel — `Layers`, `Library` — `by` points down, negative being up, and CHECKS what it did. The log line says how tall the area was, how tall it is now, how tall its content wants to be, and the ceiling that got remembered for the next launch. `expect` says what the walk is claiming: `moves` (the default) needs a bar that is there and an area that lands exactly where the drag left it, and `absent` needs no bar at all, which is the right answer for a list too short for any ceiling to change. `hold` names a picture taken with the bar still held. It drives the bar's own handlers rather than posting mouse events, the same wall `dragSection` hits. `Scripts/playtest/panel-grip-walk.json` is the walk that reads it. |
| `dragSection` | `section`, `past`, optional `stop` `hold` `cancel` | Picks a SECTION of the right hand panel up by its title and carries it up or down the column, then lets go. `past` names the section it is carried past; `stop` says how far — `middle` (the default), just beyond that section's middle, which is the line it moves aside on, or `touching`, only far enough to touch its near edge, where nothing should happen yet. `hold` names a picture taken with the section still in the air, the only moment there is anything lifted off the panel to photograph. `cancel` presses Escape instead of letting go. The log line says what is in hand, what the panel is promising while it is carried (a reorder is not a drop, so the honest answer is nothing), and the section order before and after. It drives the dock's own carry rather than posting mouse events, because SwiftUI gestures do not answer synthesized ones — the same wall `dragComponent` hits. |
| `dragRow` | `row`, `onto`, optional `zone` `hold` | Picks a row up in the layers list by its name and lets go of it on another row: `above` it (the default), `below` it, or `inside` it when that row is a group. `hold` names a picture taken before letting go, which is the only moment the line that says what will happen is on screen. |
| `menuShot` | `menu`, `name`, optional `ticked` `unticked` | Opens one of the app's OWN menu-bar menus over the probe window and photographs it, to `<name>-sc.png`. A `menus` step reads the words and the checkmarks exactly, but it is not a picture, and a menu draws outside this process so an offscreen render of it comes back blank: this is the only way an audit can SHOW what a menu looks like. `ticked` and `unticked` name the rows that must, and must not, be wearing a checkmark, so the step is a test and not only a picture. A row with nothing behind it is refused rather than asserted, because its state is the default it would wear with no document at all. To read window scoped rows live, open the Capture History first (`shortcut` on ⇧⌘H) and leave it up: it takes key, and that is enough for SwiftUI to fill in the focused window. Needs the Screen Recording grant for the picture; the rows reach the log either way. |
| `menus` | `stage`, optional `menu` | Writes the app's own menu bar to the log and to `menus-<stage>.json` (plus a `.txt` you can read): every menu, item, shortcut, submenu and enabled state, plus the windows that are open. `menu` narrows it to one top-level menu by title ("Capture"). This is how a runner names a real menu item instead of one guessed from the source, and it needs no privacy grant of any kind. See below for what the dimming is worth. |
| `action` | `action` | Calls the editor directly: `copySpecList`, `copyImage`, `hideAllMeasurements`, `showAllMeasurements`, `hideInspector`, `showInspector`, `showGrid`, `hideGrid` (which SET the grid rather than flipping it, so a walk's starting point does not depend on what the last walk left behind), `zoomIn`, `zoomOut`, `zoomToFit`, `undo`, `redo`, `newCanvasDialog`, `selectCanvas`, `saveLayers` (keeps the layers beside the picture the window was opened from, which is how a walk proves what comes back on the next open), and more (`PlaytestAction` is the full list). The inspector toggle is a button, the zoom commands are menu chords, and the Canvas row is in the dock where a walk cannot click, so this is how a walk gets a wide canvas or a big picture. An action always goes in the `action` field: `{ "do": "frameSelection" }` is refused, and the error says the line to write instead. |

## Reaching into the right hand panel

The canvas is one AppKit view, so a point in it means something and `click` and
`drag` work. The dock is not: it is SwiftUI, a walk has no way to say which tile
or which row it means, and AppKit will not start a real drag from a synthesized
press at all. That is why five audits written on one day in September 2026 each
had to admit the same hole — a menu in the dock covered by a test instead of a
picture, a drop line photographed from a one-off build, a tile drag taken on
trust.

Four steps close it, and one more makes them writable:

- `panel` lists what is there. Start here: it prints the tiles, the rows and the
  menus by the exact names the other three take, so a walk is written from what
  the app is actually showing rather than from the source.
  It lists what is BUILT, which since 2026-09-04 is what is on screen: the
  layers list makes a row the first time you scroll to it, so a row further
  down a long list is not in the inventory and cannot be named by `dragRow`
  until a `scrollPanel` has brought it into view. In a document short enough to
  fit the panel, which is most walks, nothing changes.
- `panelMenu` opens a menu and photographs it. A menu takes the app hostage
  while it is up — the click that opens one does not return until it closes, and
  nothing on the main queue runs meanwhile, which is why a walk that clicked one
  simply stopped. The driver arranges its way out first, from a thread that
  reaches the main one in the tracking run loop mode by hand.
- `press` presses a control. Both halves of the panel are covered: a button or
  a link drawn by SwiftUI says who it is through a marker behind it, and a
  segmented picker — Free / Stack / Grid, Row / Column, Hug / Fixed, which is
  most of the Layout section — is a real AppKit control underneath, so its
  segments name themselves and need no marker. A segment that is a PICTURE
  rather than words is named by what the system calls that picture: the text
  alignment rows come out as `align left`, `align center`, `align right`, and
  the vertical ones as `align vertical top` and so on. (A SwiftUI
  `.accessibilityLabel` on the Image does not reach the segment; the symbol's
  own name does.) A style slider takes a press too — it is called `Slider` and
  named by its row, so `{"control": "Slider", "in": "Corner Radius"}` puts the
  knob in the middle of that track, which is how a walk makes two layers differ
  in something only a slider can set. Either way the press is real
  mouse events POSTED to the app's queue. That last word is the whole trick:
  SwiftUI answers a press from inside its own tracking loop, which pulls the
  release out of that queue, so a walk that called `mouseDown` on the view
  directly left the release nowhere to be found and stopped for good.
- `dragTile` and `dragRow` carry out a real drop. They build the pasteboard from
  the very closure the view's own `onDrag` uses and hand it to the destination
  as a dragging info, so `draggingEntered`, `draggingUpdated` and
  `performDragOperation` run exactly as they do under a pointer. Everything
  drawn while the drag is in the air is real and can be photographed with
  `hold`.

What they do NOT do is synthesize the picture that follows the pointer during a
drag. That lives in the window server and belongs to a session only a real
device can start, so it is the one part of a panel drag a walk cannot see.

Tiles and rows say their own names: each hangs an invisible marker behind itself
(`PanelTarget.swift`) carrying the name a person reads and the same drag closure
the pointer uses, so a walk can never pick up something a person could not.

A control does the same with `playtestControl("Clear Stretch")`, and the row it
sits on is named with `playtestField("Width")` — put that on the whole row, word
and control together. A row is never pressed itself, since the middle of a row
is its empty space; it only lends its word to whatever it holds, so two rows
wearing the same answer can be told apart. Adding either to a new control is one
line and is how a feature that lives in the panel becomes playtestable rather
than merely photographable.

### A control's name holds still; what changes about it goes in its detail

An eye is called `Visibility` whether the layer is showing or hidden, and the
detail says which: `Visibility (Layers, Label, shown)`. That is the same
promise a picker segment already makes when it says `already on Fixed`, and it
is what lets a walk press the same thing twice to toggle it. A name that read
"Hide Layer" one moment and "Show Layer" the next would make the second press
a different step from the first.

The names, as of September 2026:

| In | Called | Told apart by |
| --- | --- | --- |
| A layer row | `Visibility`, `Lock`, `Twist` | `in: "<the row's name>"` |
| A color row | `Color`, `Switch`, `Save` | `in: "Fill"`, `in: "Background"`, … |
| A well anywhere else | `Color` | `in: "Shadow"`, `in: "Backdrop"`, … |
| Position & Size | `X`, `Y`, `W`, `H` | there is one of each |
| A copy's own look | `Revert Blur`, `Revert Shadow`, … | the name says which |
| Shadow | `Enable Shadow` | there is one |
| Frame | `Clip contents` | there is one |
| Layout | `Clear Stretch`, `Each side`, the pickers | `in: "Width"`, `in: "Height"` |
| The colour picker | see below | `in: "Paint type"`, `in: "Swatches"`, … |

`Twist` is the triangle that opens a group. It matters more than it looks: the
layers list builds a row only once it is on screen, so every row inside a shut
group is invisible to `panel`, `press` and `dragRow` until a walk has pressed
the twist on the group above it.

### The colour picker is a window of its own, and a walk can use it

A popover does not live inside the window it appears to grow out of: it is a
separate window sitting on top. So a search that started at the editor's
content view walked straight past the colour picker, and every audit that
touched colour had to hand back a picture of it. `panel` and `press` now read
the editor window AND anything attached to it, and a press is addressed to the
window the control is actually in.

Open it the way a person does — `{"do": "press", "control": "Color", "in":
"Fill"}` — and everything inside is then in the same list as the panel's own:

| In the picker | Called | Told apart by |
| --- | --- | --- |
| The type tiles | `Solid`, `Linear`, `Radial`, `Angular` | `in: "Paint type"` |
| The numbers switch | `HSL`, `RGB`, `HEX` | `in: "Color format"` |
| The HEX box | `Hex value` | it is not called HEX, which is the tab above it |
| The swatch rows | `Shades`, `Related`, `Document`, `Recent` | `in: "Swatches"` |
| One swatch | `Shades 1` … `Shades 9`, `Related 4`, … | the row and the place in it |
| A gradient's ramp | `Add a stop`, `Remove this stop`, `Reverse the ramp` | `in: "Stops"` |
| Keeping the colour | `Save style`, then `Style name` and `Save` | `in: "Style name"` |
| Shutting it | `Close` | `in: "the picker"` |

A swatch is named by its PLACE in the row, not by its colour: the shades are
worked out from whatever colour you opened on, so a walk that said `#7C4DFF`
would stop working the first time the colour before it changed. The hex it
holds today is in its detail, so the log still says which colour landed, and a
walk that genuinely knows the hex may name that instead as long as only one
thing on screen is wearing it.

Two things to know before writing one. The swatch row REMEMBERS which scope it
was left on between launches, so a walk that wants the shades presses `Shades`
first rather than assuming. And the eyedropper is deliberately unnamed: it
raises the system screen sampler, which would take the app hostage with nothing
left running to dismiss it.

What is still only photographable in the picker is the saturation square and
the channel sliders, for the same reason as the panel's sliders: a press is not
a drag.

The SLIDERS — Opacity, Blur, Corner Radius, Border and the five shadow rows —
are pressed, not dragged. Each is called `Slider` and named by its row, so
`{"control": "Slider", "in": "Corner Radius"}` puts the knob where the press
lands, which for the middle of the track is the middle of the range. That is a
real click on the real control, so it is the way to make two layers differ in
something only a slider can set. What a press still is not is a DRAG, so a walk
that needs the live preview frames between mouse-down and release uses the
`action` steps (`dragOpacity`, `dragCornerRadius`, `addShadow`, …) instead. The
Frame's Size menu is a menu, so it is opened with `panelMenu` rather than
pressed.

Two things a press cannot tell you. It cannot say whether a SwiftUI control is
DIMMED — `disabled` leaves no mark on the view tree — so a press on a dead
button reports a pass, and the walk has to judge it by what changed; a picker
segment is a real AppKit control and does know. And a control scrolled out of
the dock is still built and still listed, but a press refuses it and asks for a
`scrollPanel` first, rather than clicking a spot that is not on screen.

## Reading the cost of a step

A `click` resets a meter on the main run loop; the click's own log line and
every `wait` after it report `mainBusy <total>ms over <n> passes, longest
<ms>`: how long the main thread has been busy since the click, in how many
run-loop passes, and the longest single pass. The harness's own work
(describing the editor, rewriting the log) is subtracted, so the numbers are
the app's. The one to watch is **longest**: a pass over 16ms is a frame the
app did not draw, which is what "sluggish" means to a person clicking. Read
the `wait` line that follows the click, since the click line stops counting
50ms in. `Scripts/playtest/select-click-perf-walk.json` builds a scene with
nested groups and component copies and clicks through it; it is the guard on
selection latency (numbers from 2026-09-03 in its commit).

## Things to know

- **The probe remembers its settings between runs** (the last Measure mode,
  the style popover, flags). Say what you want (`measureMode`) instead of
  assuming a fresh state, or the walk changes with whoever ran last. When the
  walk itself CHANGES one of those settings, or reads one it never set, name it
  in the walk's `setup` block (above) so it starts from the same place every
  time.
- **The Library shelf remembers its tab, so a walk says which shelf it wants.**
  `showLibrary` opens the Library on whatever scope it was last left on, which
  is what a person wants and what a walk cannot rely on: the search box is
  labelled per scope ("Search media", "Search components"), so a walk that
  opens the Library and then focuses one of those passes or fails depending on
  what ran before it. Use `showMediaShelf` or `showComponentShelf` instead,
  which open the Library AND put it on that shelf. `PlaytestWalkShelfTests`
  reads every walk in this folder and fails the suite when one reaches for a
  scope's search box without asking for that shelf first, so this cannot come
  back. Keep `showLibrary` for walks that only care that the shelf is on
  screen, or that make a component or save a style first (both move the shelf
  to their own scope on their own).
- **Which shortcuts a walk can press, and why the rest cannot.** Two kinds,
  and the line between them is sharp:

  - **App-level shortcuts really work.** Capture, New Window, Open — anything
    that acts on the app rather than on a focused window. A `shortcut` step
    presses one for real and the walk can watch what it did: ⇧⌘N opens a
    second window and the next `menus` step lists it.
  - **Window-scoped shortcuts cannot be pressed at all.** ⌘Z, ⌘C, ⌘N, the
    align chords: everything in `EditorCommands` that targets the focused
    editor. A `shortcut` step FAILS on one and says so; use an `action` step
    for the outcome.

  The reason is one fact with a long shadow: **macOS will not let a
  script-launched background process take focus.**
  `NSApp.activate(ignoringOtherApps:)`, `makeKeyAndOrderFront` and
  `becomeKey()` were each tried on 2026-09-03, with the window visible and
  with it hidden, and every one left `isActive` and `keyWindow` untouched. No
  focus event ever arrives, so SwiftUI never re-evaluates the `Commands` body,
  so the menu bar stays frozen at the state it was built in at launch — when
  no editor existed. Every window-scoped item is dimmed for the whole walk
  with a **nil target and a nil action**, and forcing `isEnabled` back on does
  not help: there is nothing behind the item to run. (Proven by printing the
  live values into the Undo item's own title mid-walk, which came back reading
  the launch-time values.)

  So a `key` step's old "taken by menu" was never a pass. It now names the
  item and says outright when nothing was behind it. Use `shortcut` when you
  want that to be a failure rather than a log line.

  What this means for undo: a walk proves undo WORKS with `action` (draw, then
  `{ "do": "action", "action": "undo" }`, and watch `layers` and `canRedo` in
  the log). It cannot prove ⌘Z is wired to it. `Scripts/playtest/undo-shortcut-walk.json`
  walks the whole story end to end.
- **A `menus` step reads titles exactly and dimming only loosely.** Reading
  our OWN menu bar needs no permission, so titles, order, shortcuts and
  submenus are exact and an audit can quote them. What is greyed out is a
  different matter, and so is the checkmark on any window-scoped setting: the
  probe's menu bar is frozen at its launch state for the whole walk, for the
  reason above, so both read as they did before any document existed. So the
  log says the bar is frozen and stops marking things dimmed. App-level items
  ARE live, so a checkmark on one of those (Capture ▸ Show History) can be
  asserted with `checked` and is exact. Reading ANOTHER app's menus is the
  thing that needs an Accessibility grant; nothing in a walk does.
- **The capture overlay has its own check, not a walk.** ⇧⌘4's overlay covers
  every display and owns the pointer, so no walk can reach it.
  `Scripts/probe-app.sh --no-build` then
  `open -a "dist/Photonz Probe.app" --args --capture-diag` runs it once and
  writes `/tmp/photonz-capture-diag.txt`: how long from starting a capture to
  the screen being dim (in another tool's pixels and in the window server's own
  sharing state), whether the frozen picture underneath is the true screen or a
  photograph of our own dim, whether a window's drop shadow survives the capture
  API the freeze uses, and a real screenshot of a drag in flight at
  `/tmp/photonz-capture-diag-drag.png`. It quits the probe when it is done.
  **A locked screen invalidates the whole run** — every capture comes back as
  the desktop picture — and the first line of the report says so.

  The shadow line puts two windows of its own on screen (a grey backdrop with a
  white card floating over it) and reads the band of backdrop just under the
  card against a band far enough below to be clean, through the old capture path
  and the freeze's new one. It has to supply its own window because a shot of an
  empty screen cannot tell "the shadow is missing" from "there is nothing to
  cast one", which is how an earlier run left the question open. When the old
  path finds no shadow either the line says INCONCLUSIVE rather than guessing,
  which is what a locked screen produces.
- **Glass and vibrancy do not render offscreen**: a snapshot shows the
  window's content, not the system's translucency. Toasts and the capture
  overlay are not covered; the walk starts at the editor.
- **The offscreen render gets some colors wrong.** It resolves each layer's
  colors on its own, and a plain tool button has come out pure black on the
  dark bar while its neighbour came out pure white. Never judge brightness,
  weight or a disabled look from `<name>.png`; use `<name>-sc.png`, which is
  the real picture. It is only written when the probe holds Screen Recording
  (the harness preflights and never prompts), and the log's `capture` line
  says whether it was. You do not have to guess before a walk:
  `Scripts/probe-app.sh` prints a `Grants:` line on every launch saying whether
  the probe may record the screen, from the file the probe writes about itself
  at launch (`Sources/Photonz/Playtest/ProbeGrants.swift`).
- Keep the probe quit when you finish. `Scripts/playtest.sh` does that unless
  you pass `--keep`.
- Never point this at `dist/Photonz Dev.app`. It would not act on a script
  anyway, and rebuilding it ends someone's session.
