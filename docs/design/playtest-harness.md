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
script; a relative path is relative to the script):

- `<name>.png` for every `snapshot` (the editor window at 2x, exactly what a
  person would see) and every `render` (the composited document).
- `log.json`: one entry per step with the elapsed time, what the step did,
  and, after anything that changes the editor, its state: tool, Measure mode,
  hint text, copy confirmation, layer count, whether Undo and Redo have
  anything to do (`canUndo`, `canRedo`), whether this process has focus at all
  (`appActive`, always false in a walk), every measurement (name, value,
  role, feet, frame), every annotation (shape, caption, frame), legend
  entries, whether the edge map is ready, who has the keyboard, and the
  pointer's shape (`cursor`: `arrow`, `openHand`, `closedHand`, `crosshair`,
  …), which is how a walk proves a hover cue appeared. A `drag` line also
  reports the cursor WHILE the button was down, the only moment a closed-hand
  grab exists. The real OS pointer is not where a synthesized click is, so read
  the cursor from a `move` step's `describe`, not from the state line right
  after a drag.
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
capture that is device pixels) unless a step says `"space": "view"`. The
`open` entry in the log states the document size and pixel scale so you can
read coordinates straight off the fixture.

| `do` | fields | what happens |
| --- | --- | --- |
| `blank` | optional `canvasWidth` `canvasHeight`, optional `width` `height`, optional `card` | Opens a NEW EMPTY WINDOW and hands it a blank white canvas, the way the empty window's Blank canvas row does once a size is chosen. Defaults to the offered size (`BlankCanvas.defaultPreset`). `width`/`height` set the window frame, as in `open`. `card` names a snapshot taken of the empty window first, which is the only way to photograph the onboarding card — it stops existing the moment a document arrives. This is how a walk starts from nothing instead of from a screenshot. |
| `open` | `file`, optional `width` `height` | Opens the file in an editor window (path relative to the script or absolute), waits until it can be driven, hides it, sizes it. Every later step targets this editor. |
| `wait` | `seconds` | Sleeps. Prefer `waitFor`. |
| `key` | `key`, optional `modifiers` | Presses and releases a key. `key` is one character or `return`, `escape`, `tab`, `space`, `delete`, `left`, `right`, `up`, `down`. Modifiers: `command`, `shift`, `option`, `control`. Plain keys go to the window like typing; chords are offered to the window, then the menu bar, and then, if neither claimed them as a shortcut, sent to the window as an ordinary press (which is what ⇧↑ in a number field is). The log says who took them: `window`, `menu` or `responder chain`. |
| `shortcut` | `key`, optional `modifiers` `menuItem` | Presses a chord and REQUIRES it to reach a menu item that actually runs. Fails, loudly and with the reason, when no menu item carries the chord, when the item is not the one `menuItem` names, when something else takes the press, or when the item has nothing behind it. Use it for app-level shortcuts (Capture, New Window, Open); a window-scoped one fails by design and tells you to use `action` instead. See "Which shortcuts a walk can press" below. |
| `move` | `at` | Moves the pointer over the canvas (hover previews, snap dots). |
| `hover` | `label` or `at` | Rests the pointer on a control until its tooltip shows: `label` is the text the tooltip starts with ("Arrow", "Measure"); `at` is a point, and one over no control leaves the tooltip behind. The log line says what showed and where, and a `snapshot` taken now includes it. |
| `click` | `at`, optional `count`, `modifiers` | Mouse down and up on the canvas. |
| `drag` | `from`, `to`, optional `steps`, `modifiers`, `hold` | Mouse down, a run of drags, mouse up. `modifiers` are held for the whole gesture (Command drags free of every magnet). `hold` names a snapshot taken with the button still down, just before the release: the only way to photograph something that exists only mid-drag, like the yellow snap guide. |
| `focus` | `field` | Gives the keyboard to a named text field in the inspector, by the label the field shows ("W", "H", "X"). Everything after it — `type`, `key` tab, an arrow key — then goes to that field, the way it would for a person who clicked it. Fails with the list of fields that ARE on screen, which is usually the fastest way to learn why a section is not showing. Needed because `click` goes to the canvas view and can never reach the inspector. |
| `type` | `text` | Inserts text into whatever field has the keyboard. Fails when nothing does. Note this bypasses the keyboard entirely; to prove a field still takes ordinary typing, press the characters with `key`. |
| `tool` | `tool` | Picks a tool directly (`select`, `arrow`, `measure`, and so on), for when its key was not honoured. |
| `measureMode` | `mode` | Presses I until the Measure tool is in `distance`, `size`, `gap` or `alignment`, and logs how many presses it took. |
| `waitFor` | `condition`, optional `value`, `timeout` | Polls until `edgeMap` (element detection done), `captionField` (a caption field has the keyboard), `tool` = `value`, or `measureMode` = `value`. Times out as a failure. |
| `dragComponent` | `at` | Holds the component picked on the Library shelf over a point WITHOUT letting go, so a `snapshot` taken next photographs the landing box and the dashed frame it would join. The log line says what the canvas answered: whether it would place a copy or refuse, how big the box is, and whether it is joining a frame. A synthesized mouse drag cannot start a real drag session, so this is the only way to see a component drag in flight. |
| `dropComponent` | `at` | Lets go of the component picked on the Library shelf at a point, the way dropping its tile on the canvas does, through the same pasteboard the real drag writes. |
| `dropImage` | `file`, `at` | Lets go of a file over the canvas at a point, the way one arrives from the Finder (path relative to the script or absolute). A drop on a frame joins that frame; a drop on bare canvas lands the image centred on the canvas. |
| `snapshot` | `name` | Renders the window's content offscreen to `<name>.png`. While a sheet is up the SHEET is what gets photographed, since that is what a person is looking at. When the probe holds Screen Recording it also writes `<name>-sc.png`, the window as the screen shows it; read that one for anything judged by color or weight (see below). |
| `render` | `name` | Composites the document itself to `<name>.png`. |
| `describe` | `stage`, optional `note` | Logs the editor's state under `stage`. |
| `clearClipboard` | | Empties the clipboard. |
| `readClipboard` | `stage` | Logs the clipboard's types and text. |
| `menus` | `stage`, optional `menu` | Writes the app's own menu bar to the log and to `menus-<stage>.json` (plus a `.txt` you can read): every menu, item, shortcut, submenu and enabled state, plus the windows that are open. `menu` narrows it to one top-level menu by title ("Capture"). This is how a runner names a real menu item instead of one guessed from the source, and it needs no privacy grant of any kind. See below for what the dimming is worth. |
| `action` | `action` | Calls the editor directly: `copySpecList`, `copyImage`, `hideAllMeasurements`, `showAllMeasurements`, `hideInspector`, `showInspector`, `zoomIn`, `zoomOut`, `zoomToFit`, `undo`, `redo`, `newCanvasDialog`, `selectCanvas`, and more (`PlaytestAction` is the full list). The inspector toggle is a button, the zoom commands are menu chords, and the Canvas row is in the dock where a walk cannot click, so this is how a walk gets a wide canvas or a big picture. |

## Things to know

- **The probe remembers its settings between runs** (the last Measure mode,
  the style popover, flags). Say what you want (`measureMode`) instead of
  assuming a fresh state, or the walk changes with whoever ran last.
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
  different matter, and so is any title that renames itself with the document
  ("Show History" becoming "Hide History"): the probe's menu bar is frozen at
  its launch state for the whole walk, for the reason above, so both read as
  they did before any document existed. So the log says the bar is frozen and
  stops marking things dimmed. Reading ANOTHER app's menus is the
  thing that needs an Accessibility grant; nothing in a walk does.
- **The capture overlay has its own check, not a walk.** ⇧⌘4's overlay covers
  every display and owns the pointer, so no walk can reach it.
  `Scripts/probe-app.sh --no-build` then
  `open -a "dist/Photonz Probe.app" --args --capture-diag` runs it once and
  writes `/tmp/photonz-capture-diag.txt`: how long from starting a capture to
  the screen being dim, whether the frozen picture underneath is the true
  screen or a photograph of our own dim, and a real screenshot of a drag in
  flight at `/tmp/photonz-capture-diag-drag.png`. It quits the probe when it is
  done. **A locked screen invalidates the whole run** — every capture comes back
  as the desktop picture — and the first line of the report says so.
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
