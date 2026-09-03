# Building UI in Photonz — the IA, then the features

The focus epic `ui-building`: make Photonz the best tool for building UI, in the
same app people already use to capture and redline a screenshot. Written
2026-09-02 from the design study (`ui-entry-wt`, `ui-build-screen`, `ui-grid`,
`components`, `component-configure-wt`, `states`, `composites`, `dsys`,
`ds-build-wt`, `ds-switch`, `ds-modes`, `ui-prototype`) measured against what the
app actually does today.

Ships in the **Next** release behind flags. The mocks are proposals: where this
document disagrees with a mock, this document wins, and it says why.

## The two rules this work lives under

1. **It blends in or it does not ship.** Capture, measure, redline, annotate and
   export behave exactly as they do today. Someone who only takes screenshots
   never learns that any of this exists: no new window, no mode switch, no
   second shell. Every step below is additive to the one editor.
2. **It is useful the first time it opens.** A component library that starts
   empty is a chore. The app ships with a small set of built-in components, so
   the first thing a person does is drag one out, not author one.

## Where we are starting from

The document is a flat array of layers on one canvas
(`PhotonzCore/Document.swift`). A layer holds leaf content: an image, text, an
annotation, a callout, a measurement, a collage. Nothing nests, nothing
references another layer, and duplicating a layer produces an unrelated copy.
The editor is one canvas plus a right dock of contextual inspector sections, and
the Layers panel is a flat reorderable list.

So the vision needs four things the app has none of: containment, a second kind
of surface to put things on, a place to keep reusable pieces, and a link between
a definition and its uses.

## The IA, decided

These are the structural choices. They come before any feature, because every
feature below assumes them and changing one later means rewriting the rest.

### One tree, no second document kind

A layer may contain layers. That is the whole change. There is no separate
"design file" next to a "screenshot file": a capture with a measurement on it and
a screen made of components are the same document with the same tree.

A **group** is a layer whose content is other layers. A **frame** is a group with
a size that clips and can carry a layout. The mocks are right that "the starter
frame is an ordinary frame" (`ui-entry-wt`): a frame is not an artboard class of
its own, it is a group with two extra properties. Several frames sit side by side
on the one canvas, which is how a document holds more than one screen without the
model growing a pages concept.

**Why not artboards as a document-level list:** it would fork every operation
(select, move, restack, export, undo) into a per-page and a whole-document
version, and it would make a screenshot document structurally different from a UI
document. One tree keeps capture and redline on exactly the code they run today.

### The Library is a panel group, not a place you go

The Library joins Layers and the inspector sections in the existing right dock,
collapsible and resizable like everything else there. Four scopes on a segmented
control: Media, Components, Styles, Systems. Picking a library tile drives the
inspector exactly as picking a layer does, so there is one selection model in the
app and nothing new to learn.

**Why not a browser window or a mode:** rule 1. A second window is the thing that
turns "the app I screenshot with" into "the app that also has a design tool in
it".

### A component is a subtree with a name, an instance is a layer that points at it

Promoting a group makes it a **main**. An **instance** is a layer whose content
references a main by id and carries overrides for the properties the main chose
to expose. Editing the main updates every instance. Overriding an instance never
breaks the link. Detaching turns the instance back into ordinary layers.

Exposed properties come in three kinds, and no more for now: **text** (wording),
**boolean** (a layer is present or not), and **variant** (swap between shapes the
main already contains). A variant can only pick among what the main holds, so an
instance can never drift into something the main does not define.

**Deferred deliberately:** states, composites bound to data, prototyping
connections, modes, published and versioned systems. Every one of them is real
and in the mocks, and every one of them is worthless until a person can author a
component and reuse it. They come back after the scenario below works.

### Styles are named values layers point at

A **style** is a named paint, effect or text treatment. A layer either holds a raw
value or points at a style. Changing the style repaints everything pointing at
it. Tokens (the layer beneath styles, where `accent` resolves differently per
mode) are deferred: the built-in components bind to styles, and styles gain token
backing when modes arrive.

## The order of work

Each step is a slice someone can try. Nothing below starts until the step above
it is real in the app, because each one is load-bearing for the next.

**A. Containment.**
1. Layers nest. Group and ungroup with the Photoshop keys, a real tree in the
   model, an outline with disclosure in the Layers panel, hit-testing and
   restacking that descend. Old flat documents decode unchanged.
2. Frames. A group that clips to a size, several of them on one canvas, a size
   preset menu, and export scoped to one frame.

**B. The shelf.**
3. The Library panel group, with its four scopes, its search, and its selection
   behaviour. It can be empty at this point; what matters is that it exists in
   the dock and behaves like every other panel.

**C. Reuse.**
4. Make component: promote a group to a main, which appears in the Library.
5. Insert an instance from the Library, and have a main edit update every
   instance at once.
6. Exposed properties and instance overrides, plus detach.

**D. Useful on arrival.**
7. The built-in components: a small starter set (button, input, card, nav bar,
   badge) that is in the Library on first launch, drawn from styles rather than
   raw values.
8. Styles: save a fill as a named style, bind a component to it, repaint
   everything by editing the style once.

**E. The bar.**
9. The complete scenario, audited end to end: draw a control, make it a
   component, drop three instances, expose a label, override one, edit the main,
   watch them all follow. Plus proof that capture, measure and redline are
   untouched.

## Landed: typed position and size (Next, `next-geometry-fields`, 2026-09-03)

Nothing above can be built to a spec while size and position are drag only, so
the inspector grew a **Position & Size** section before step 1: X, Y, W and H
for the selected layer, as numbers you can type.

- The numbers are document points, shown whole, with the same `px` word the
  measure readouts use, so a number measured with the caliper types straight
  back in.
- Typing lands on Return, on Tab and on clicking away. Up or down arrow steps
  a field by 1 and Shift by 10, the same amounts the canvas nudges by. Each
  landing is one undo step; tabbing through without editing records nothing.
- Taking a field selects its whole number, so clicking W and typing replaces
  the width instead of appending to it.
- The fields follow a canvas drag live rather than jumping on mouse-up.
- A field is typeable exactly where the canvas already lets you drag the same
  thing. Every layer moves, so X and Y are open unless the layer is locked.
  Size is not: an arrow's frame is padding around a shaft rather than the shape
  you drew, and a measurement is edited by its feet, so both show a dimmed W and
  H that say why on hover. Text takes a width (its wrap width) and not a height.
- Model and rules are `LayerGeometry` / `LayerGeometryEditing` in `PhotonzCore`;
  the section is `GeometryInspector.swift`; the write goes through
  `EditorState.setLayerGeometry`, which reuses the canvas drag's
  `commitLayerFrame` so annotation endpoints and caption placement stay correct.

Not in this slice: several layers selected at once (the section shows the
primary selection only), a proportional lock, and a rotation field.

## Questions the user decides, not the loop

Each of these becomes a decision card when the step that needs it is claimed.
None of them blocks the step before it.

- Does a frame clip its contents by default, or only when asked? Clipping is what
  makes a frame a screen; not clipping is what makes it a group people can see
  out of.
- Does dropping an instance default to the main's own configuration, or to the
  last variant that person used? (`components` raises this and leaves it open.)
- Do the built-in components look like macOS controls, or like a neutral kit that
  is obviously a starting point to edit? A convincing macOS button invites people
  to expect real macOS behaviour.
- Auto-layout: the mocks put it on frames from the start. It is the largest
  single piece of work in the vision and it is not required for authoring and
  reusing a component, so it is sequenced after step 9 unless the user wants it
  sooner.

## Done when

A person opens Photonz, drags a button out of the Library onto a frame, changes
its label, draws a control of their own, makes it a component, drops three of
them, edits the original, and watches all three follow. Then they take a
screenshot, measure it, and notice nothing about their editor has changed.
