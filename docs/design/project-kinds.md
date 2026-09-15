# Does the app need project types?

Written 2026-09-15, from the queue task "Work out whether the app needs project
types at all". The user's own words for the question: *"we might need different
project types to isolate/hide some of the scenarios."*

The page this summarises is the study, and it is worth reading first because
the argument is mostly pictures: <http://127.0.0.1:8791/index.html#project-kinds>.

## The answer in one paragraph

**No to the gate, yes to the front door.** The app should ask what you are
making, because that question can set up the canvas, the zoom, the grid and the
export in one click, and today's New Canvas sheet asks "how big" instead, which
is a question you can only answer if you already know the answer. What it must
not do is remember that choice as a **kind** and use it to decide what you are
allowed to see afterwards. The reason is not a preference, it is a document the
app already lets you make: a 24 point icon frame beside a 1440 point screen, in
one window, both of them real work. Ask that document what kind it is and there
is no true answer, and every false one is wrong about half the canvas.

## What exists today

- A document is a canvas with a size. `AppCoordinator.newBlankCanvasWindow(size:)`
  makes one, File ▸ New Blank Canvas asks how big, and that is the whole of it.
  There is no kind, no template, nothing stored, nothing hidden.
- `FramePreset.all` is **screens plus icons in one list** (`Frames.swift`), and a
  frame is an ordinary layer. Nothing stops one document holding both.
- Context already follows the **frame**, in two shipped places:
  `IconPreviews.isIconSize` puts the size row up inside an icon frame, and
  `IconStrokeWeight.startingWidth` starts a fresh line at whole pixels there
  (2 points inside a 24, the tool's own 4 on a screen).
- Video is a **separate editor** with its own window and state
  (`VideoEditorState`, `VideoEditorView`). It is not a lens on the layer
  document, so it is not showing icon tools now and does not need a kind to stop.

## The honest case for kinds, counted rather than guessed

Counted off the real bar (`ToolBarLayout.bar` with every Next flag on, thirteen
slots), and generously: anything "rare" counted as keep.

| Kind | Slots it could hide |
| --- | --- |
| Icon | 5 (measure, arrow, highlight, zoom callout, lens) |
| Screen | 2 (highlight, lens) |
| Capture | **0** |
| Recording | 7 |

Five slots off an icon's bar is a real gain and this study does not pretend
otherwise. Two things take the shine off it:

- **Capture removes nothing**, and capture-and-redline is the app's main
  real-world job. For the primary user the whole feature is invisible.
- **The recording column describes a window that already exists**, so the only
  column where hiding is both real and unsolved is Icon.

And the crowding is not in the tool strip anyway. The pane study measured the
side pane asking **1052 points of the 968** a large window can give, with three
layers and one piece of text selected. A project type does nothing about that,
because the pane already follows what you picked rather than what you declared.

## The fact that decides it

One document, an icon frame and a screen frame, at the same moment:

```swift
#expect(document.isIconFrame(id: icon.id))     // the 24
#expect(!document.isIconFrame(id: screen.id))  // the 1440
#expect(document.iconFrameID(containing: glyph.id) == icon.id)
#expect(document.iconFrameID(containing: callout.id) == nil)
```

`Tests/PhotonzCoreTests/DocumentHasNoKindTests.swift`, three tests, in the suite.
Drawing an icon beside the screen it appears in is the point of having frames,
and it is how anybody checks that a 24 point mark reads where it will really be
seen. A document-level kind has two escapes from it and both cost more than they
save: forbid the mixed document, which removes the reason frames exist, or add a
fifth kind called Mixed that hides nothing, which is the typeless app with a
label on it.

## What solves the same problem instead

The problem is real: a surface that carries every tool forever gets worse every
time something ships. The answer is that **context follows the work, not a
declaration**. Three legs, two of them already running:

1. **The frame you are in.** An icon frame brings the size row and whole-pixel
   strokes; a screen frame brings layout and the grid.
2. **What you have picked.** The pane shows the sections that layer has, which is
   how it works today.
3. **What the document contains.** Something with a duration gets a transport,
   something with a repeating motion gets a cycle strip. That is where the
   animation study landed (`docs/design/animation-vs-video.md`).

The difference this produces between two moments in ONE document is larger than
the difference between two kinds, and nobody was asked a question to get it. It
is also re-answered every time the selection moves, rather than once at the
moment the person knew least about what they were making.

**One leg is genuinely missing.** A picture opened from a file becomes the canvas
itself with no frame around it (`EditorState.openImage`), so a capture has
nothing for the context to hang off. That is the one real piece of work this
answer creates, and it is smaller than a project type.

## Documents that already exist

Under the gate answer, old files force the feature to defeat itself. They carry
no kind, so on open the app can ask (a dialog in front of a file somebody just
double-clicked), guess from the contents (in which case the guess is doing the
work and the front-door question was never needed), or give them a no-kind state
that hides nothing — which then has to be a good place to work, because it is
where every old file lives, which makes the four kinds a decoration on an app
that must be complete without them.

Under the recommended answer nothing happens to them at all. There is no kind to
be missing. An old document gets every improvement made since it was written,
and a document written today opens in a build from last year. **A kind stored in
a file is a compatibility promise forever**, and the kinds we would invent now
are the kinds we understand now.

## The cost of being wrong, both ways

| | Kinds, and they were wrong | No kinds, and that was wrong |
| --- | --- | --- |
| What it feels like | The app looks broken, not focused. A real tool is missing and nothing says why. | The app feels busy. Every surface carries every tool. |
| How we find out | **Mostly we do not.** Nobody reports a tool they never knew existed. | **Immediately.** "There is too much in here" is the easiest complaint to make. |
| Cost to undo | High: stored in the file, so a format, a migration and a promise. | Low: nothing stored, so it is a rule about when something shows, testable behind a flag. |

The two are not symmetrical, and that asymmetry is the argument. Given two risks
of similar likelihood, take the one you will hear about.

## Recommendation

1. **New asks what you are making, and sets it up.** Icon, Screen, Capture,
   Recording. A starting point, not a mode: nothing hidden, nothing stored.
2. **A picture you open arrives in a frame**, so capture context has something to
   follow and a capture can sit beside a design in one document.
3. **The pane earns its room by relevance**, not by permission: sections appear
   because the frame, the selection or the document has something to say.

## The case that could still change this

The day video moves into the layer document, one document could hold a fourteen
second recording and a 24 point glyph at once, and the pane would have to carry a
transport and an icon size row together. That is an argument for the context rule
getting sharper, not for a kind, because a kind would have to call that document
one thing and it is two. If it ever becomes unbearable, the thing to reach for is
a **workspace**: a saved arrangement of panels you switch between and can always
switch back from. That is a view setting, not a property of the file, and it can
be added later without undoing any of the above.
