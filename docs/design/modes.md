# Modes you can swap, rather than project types you are stuck in

Status: prototype delivered, decision open.
Pages: <http://127.0.0.1:8791/index.html#modes> and
<http://127.0.0.1:8791/index.html#shelves>.
Evidence: `Tests/PhotonzCoreTests/ModeIsAPresetTests.swift`,
`Tests/PhotonzCoreTests/DocumentHasNoKindTests.swift`.

This file replaces `project-kinds.md`. The question it asked (should a document
know what kind of thing it is?) was answered no, and the user then redirected it
to the thing worth building instead: **not types, modes.**

> "ideally you can just swap between modes without changing a document type... if
> you start at a certain project mode, it's like a preset of which things are
> available, and easy to swap between them."

A **type** is something a document IS and cannot easily stop being. A **mode** is
something the WINDOW is in, and swapping costs nothing. The document model never
learns about modes, so nothing here needs a migration.

---

## 1. The claim being tested, and why the chain comes first

The user sharpened it twice, and the second sharpening is the whole design
constraint:

> "there is a lot of overlap between the modes so i don't want 4 separate apps
> with 4 different ia. I want 1 app that can do 4 jobs pretty seamlessly. You can
> create a component, and then show that on a video timeline"
>
> "you can make an icon and use it in your component"

So the acid test is a three-link chain: **draw an icon, use that icon in a
component, put that component on a video timeline, in one document, with nothing
converted at any step.** It is drawn first on the prototype page, before any
panel arrangement, because if the chain is impossible then the arrangement is
decoration.

**It works, and the reason is one sentence: the icon, the component and the clip
are all layers in the same document, and the timeline is a view of the layers
that have a start and an end.** There is nothing to convert into. The bell placed
in the button is a component instance, the button placed over the video is an
instance of that, and editing the original redraws all three, which is what
`ComponentInstances` / `ComponentVersions` already do for a button used on four
screens.

### The bill

Video today is a separate editor (`VideoEditorState`, `VideoEditorView`) with no
layer list and no knowledge of the document model, so **nothing can be dragged
onto its timeline**. For the chain to be real, a recording has to become a layer
with a duration and the timeline has to become a view over layers. That re-aims
the queued video work (cutting and arranging) onto the new footing rather than
the old one, which is cheaper than building it twice but is a real re-aim, and
30fps playback of a composite is a harder bar than a still canvas.

**Modes are worth building either way.** The chain is the reason to pay the bill,
and that is a separate yes.

### One wrinkle, not hidden

A 24 point mark blown up to ~190 on a 1080p frame is a 24 point drawing at eight
times scale: the stroke scales with it and reads chunkier than the icon does.
Correct for a vector, still not what you wanted. The answer is a component with a
variant per size band, which belongs to the icon epic, not to modes.

---

## 2. What a mode is

A mode is a **named preset of choices the app already stores**, plus a small set
of defaults. Nothing about it is a new subsystem:

| Part of a mode | What it sets | Where it already exists |
| --- | --- | --- |
| Panel sections folded | per-section yes/no | `PanelSectionVisibility.Choices` |
| Tool groups in front | which groups sit in the bar | `ToolBarLayout` groups + the bar's overflow |
| New document size / zoom | a starting canvas | the New Frame size list |
| What the canvas shows | grid, magnification rule | `CanvasGridStore`, `magnifyNearest` |
| What new work starts as | tool defaults | the pen already starts at 2pt inside a 24pt frame |

`PanelSectionVisibility` says this in its own header already: "an override is
exactly the shape a MODE will want later: a mode is a named preset of these
choices, not a second mechanism."

### Where the switcher lives

A quiet chip in the window's **status**, beside the document name, opening a
popup list; also `⌃1 … ⌃5` and View ▸ Mode. **Not** a segmented control in the
title bar: three tabs up there read as navigating between three applications,
which is the exact impression this direction exists to avoid, and the study ruled
that shape out (`PRODUCT-MODEL.md` §4f). A popup reads as state.

### Exactly what a mode may fold

| Part | May fold? | Rule |
| --- | --- | --- |
| Panel sections | Yes, nine of them | only `PanelSectionVisibility.optionalSections` |
| The layers list | Never | not optional; the code refuses to write a choice for it |
| The picked layer's own section | Never | you could be left holding something with no way to change it |
| Appearance, Effects | Never | every layer has them, every job wants them |
| Tool groups | Yes, into the overflow | by group, never one tool out of a group |
| Shortcuts | Never | every tool keeps its key in every mode |
| The native menu bar | Never | **this is the safety net the whole idea rests on** |
| The timeline | Folded, not removed | it appears because the document has time, never because of a mode |
| The document | Never, in any sense | nothing hidden, nothing changed, nothing written |

One honest consequence: the tool bar's overflow button is `display:none` today
until the bar runs out of room. A mode that folds tool groups has to make it
permanent, because there is now always something in it.

---

## 3. The way back, which is the point

A preset that hides a tool is indistinguishable from a broken app in the second
you reach for that tool. Five mechanisms, four of which already exist:

1. **The shortcut still works.** Press `I` and Measure is armed, with a quiet
   line saying it is in the overflow menu. The worst case is a tool you cannot
   see, never a tool you cannot use.
2. **Folded tools are in the overflow menu** a narrow window already uses.
3. **Folded sections are listed** by the dock's own **Panels** button (standard
   chrome on every window), and the list inside the panel says *"you turned this
   off"* rather than leaving a blank (`PanelSectionVisibility.Reason` already
   distinguishes that from *"nothing in this document needs it yet"*).
4. **A mode you bend stays bent.** The chip reads "Icon, edited"; Reset this mode
   is in the same popup.
5. **Show everything** unfolds the lot in one click, and swapping back to a mode
   restores exactly the arrangement you left.

`ModeIsAPresetTests` pins 3, 4 and 5 as facts rather than promises: a mode is a
set of per-section choices, swapping away and back lands on the identical set of
sections, and handing the lot back to automatic gives the window of somebody who
never touched a mode.

**Why this is not the escape hatch the kinds study rejected:** nothing a mode
does is a NEW place. The old objection was that a "show all tools" switch makes
two states of the app to learn. Here, folded things go to places that already
exist for other reasons, and the app already shipped the by-hand version of this
feature. A mode is a name for a set of choices you would otherwise make one at a
time.

---

## 4. Modes are data, and pixel art proves it

Four hardcoded modes would be four information architectures in a costume. The
user's example:

> "i could see the modes being extensible. some other scenarios might be 'i want
> to make pixel art' and we configure the setup with tools built around that"

Pixel art written out: 32 × 32 at 1600%, grid at one pixel, nearest-neighbour
magnification, pencil at 1px with hard edges and no antialiasing, Measurements /
Placement / Columns / Component / Shadow folded, Motion kept because sprites
animate. **Three of the five ingredients are already running in the app.**

### The line, and the case that tests it

A mode **may** fold what the window offers, set a default for the next thing you
make, and change what you are looking at (grid, magnification: view settings,
exactly like zoom). A mode **may not** change how existing work comes out, touch
anything in the file, or take a capability away.

The case: switch to Pixel art with a smooth curve already on the canvas and **the
curve stays smooth**. If it re-rendered hard-edged, the document would be in a
mode and swapping would no longer be free, which is the rejected idea wearing a
better name. Hard edges are a property of a LAYER (apply it, undo it, see it in
the panel); a mode can arm that for new work, it cannot reach backwards. That
leaves one small thing to build that this study does not propose: a hard-edge
switch on a raster layer, which belongs to the drawing work.

---

## 5. Old documents, new documents

- **Old documents:** nothing happens to them, because there is nothing in them to
  happen to. No mode is stored in a file, so there is no missing value to guess,
  no dialog in front of a file somebody just double-clicked, and no compatibility
  promise. This is the biggest practical difference from the project type this
  replaces.
- **New documents:** open in the mode the window was already in, unless what you
  did says otherwise. New ▸ Icon opens in Icon; a capture opened from History
  opens in Redline; a recording opens in Video. Nobody is asked a question at the
  front door.
- **Somebody who never finds modes** loses nothing: the default arrangement is
  the one the app has now.

---

## 6. The shelves (companion page)

The chain starts with a drag, so the app needs an answer to which shelf. Settled
by the user, by **scope, not by kind**:

- **History is the global shelf.** Everything you have made or captured, across
  documents, reachable from the menu bar with no window open.
- **The Library is the document's own shelf.** What this file contains and can
  place again.

Open questions inside that model, answered on `shelves.html`:

- **Copy or link?** *A copy that follows*, which is what `SharedComponents`
  already does (decided 2026-09-09, "one shelf the whole app shares"): the
  document keeps a complete original marked as following the shelf, so a file
  sent to somebody else still draws. **Do not invent a second linking rule.**
- **Captures beside components?** Yes, because the strip was never sorted by
  kind: it is what you recently had, in the order you had it. The filter gains
  Icons and Components. The risk is volume, and pinning is the existing answer.
- **Is the Library just the layers list?** No. **Layers is where things ARE, the
  Library is what there IS to place.** Three placements of one bell are three
  layer rows and one Library tile, and half the Library (colour and text styles)
  is not layers at all.
- **One bill:** the Library's Media scope shows the global capture folder today
  (`LibraryPanel`). Under this model those belong to History, and Media becomes
  the pictures this document uses.

---

## 7. Recommendation

1. **Build modes as named presets** of the choices that already exist, with the
   chip in the window's status.
2. **Ship the way back in the same slice**, not after it. Without it, a mode is a
   bug report.
3. **Modes are written down, not coded.** If the four we ship are the only four
   possible, they are four applications.

Video moving into the layer document is a **separate decision**: modes are worth
building either way, but the three-link chain is only real if it happens.
