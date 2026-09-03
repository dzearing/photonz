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

### A layer's position is stored against its parent

A layer's X and Y are measured from the top left of whatever contains it. For a
layer sitting loose on the canvas, that container is the canvas, which is the
rule the app already follows: every document that exists today is a tree one
level deep, and nothing about it changes.

**Why parent relative and not canvas coordinates.** A main component is placed
in many spots at once. If its children each carried canvas coordinates, every
instance would have to rewrite every number inside it, and the same subtree
could never appear in two places. Parent relative also makes moving a group one
number changing rather than one per child, and it makes dragging a whole screen
across the canvas free.

**Groups translate, they do not scale or rotate.** In the first version a group
adds an offset to its children and nothing else. So a layer's canvas position is
the sum of the origins from it up to the canvas, plain addition, and text sizes,
stroke widths, corner radii and measurement numbers inside a group are exactly
what they were outside it. That is worth the constraint on its own: a measured
gap of 12 px stays 12 px when the thing it measures gets grouped.

**A group's origin is set once and then holds still.** Grouping puts the origin
at the top left of the union of what was selected, and rewrites the selected
layers' positions relative to it once. After that the origin does not float:
drawing a new child that sticks out to the left of the group does NOT move the
group, it gives that child a negative X. The union of the children is a derived
value, used for the selection handles and for what the group draws into, and it
is never the anchor. If the origin chased the union, every sibling's stored
numbers would silently change each time you drew something.

**Moving a layer between containers rewrites its position** so it does not jump
on screen: dragging a layer into a group in the layers list keeps it exactly
where it was.

**The Position & Size fields show parent space.** Selecting a child inside a
group and typing Y = 0 puts it at the top of its group, not the top of the
canvas, which is what the numbers stored on that layer say and what every other
design tool does. For a top level layer, parent space IS canvas space, so a
person who redlines a screenshot and never makes a group sees no difference.
Watch this one in the frames audit: someone measuring against the whole picture
may expect canvas numbers, and if that turns out to bite, the answer is a
readout that shows both, not a change to what is stored.

**On disk**, a document saved before groups existed decodes unchanged, because a
flat list is a tree of depth one.

### The Library is a panel group, not a place you go

The Library joins Layers and the inspector sections in the existing right dock,
collapsible and resizable like everything else there. Four scopes on a segmented
control: Media, Components, Styles, Systems. Picking a library tile drives the
inspector exactly as picking a layer does, so there is one selection model in the
app and nothing new to learn.

**Why not a browser window or a mode:** rule 1. A second window is the thing that
turns "the app I screenshot with" into "the app that also has a design tool in
it".

**Built 2026-09-02, and two things changed from this plan.** First, the Library
is **off until asked for**: View ▸ Show Library puts it in the dock and the
answer sticks. Step 3 said the panel could ship empty, and a dock that grows an
empty section on its own is a change nobody asked for, least of all the person
who only redlines. Second, Media is **not** empty: it shows the captures the
app already keeps in the capture folder, so the shelf is useful the first time
it opens (rule 2) and its search and selection are things you can actually try.
Components, Styles and Systems are empty and each says in one line what will
fill it. Picking a media tile opens its own section in the same dock, with the
capture's size and age and two buttons (Place in Picture, Reveal); a double
click or a drag onto the canvas places it too. Cut from the mock as decorative
at this step: the slide-down browse overlay, the plus/Add to Library menu, the
category chip row inside a scope, the dock rail tab, and the "N uses" counts.

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

   **8 is built before 7.** The step numbers stay as they are, because the
   queue tasks quote them, but styles land first: step 7 says the starter
   components are drawn from styles rather than raw values, and that cannot
   happen until styles exist. Building 7 first would mean shipping the starter
   set in raw colors and redoing it.

**E. The bar.**
9. The complete scenario, audited end to end: draw a control, make it a
   component, drop three instances, expose a label, override one, edit the main,
   watch them all follow. Plus proof that capture, measure and redline are
   untouched.

## The menu items and keys each step adds

Three house rules, so nobody has to re-decide them per step:

- **Photoshop first.** Where Photoshop has the same command, take its key.
  Where it has no equivalent command, take the one a design tool user already
  knows, and say so here. Anything else gets no key at all: an invented
  shortcut is worse than none.
- **A flagged command is absent, not greyed.** With its flag off the menu row
  does not exist, the way the Measure menu already works. Nobody hunts for why
  a row is dead.
- **Enablement follows the selection**, and every row below says what enables
  it.

The numbers are the steps in **The order of work** above. Step 1 bundles four
queue tasks (the model, the renderer, the keys, the layers list); the keys land
with the third of them.

| Step | Menu | Item | Key | Enabled when |
| --- | --- | --- | --- | --- |
| 1 Containment: the model | none | none | none | nothing on screen |
| 1 Containment: the renderer | none | none | none | nothing on screen |
| 1 Containment: the keys | Layer | Group | ⌘G | two or more layers are selected, or one group's contents are |
| 1 | Layer | Ungroup | ⇧⌘G | the selection is a group |
| 1 Containment: the layers list | none | none | none | the twist open control is pointer driven |
| 2 Frames | Tools | Frame tool | F | always |
| 2 | Layer | New Frame… | none | a document is open |
| 2 | Layer | Frame Selection | none | one or more layers are selected |
| 2 | File | Export… (the existing row grows a frame scope) | ⇧⌘E | unchanged |
| 3 The Library panel | View | Show Library / Hide Library | none | a document is open |
| 4 Make component | Layer | Make Component | ⌥⌘K | the selection is a group that does not already contain a main |
| 5 Insert an instance | Layer | Insert Component | none | a component is selected in the Library |
| 6 Overrides and detach | Layer | Detach Instance | ⌥⌘B | the selection is an instance |
| 6 | Layer | Select Main Component | none | the selection is an instance |
| 7 Built-in components | none | none | none | they are ordinary components |
| 8 Styles | none | none | none | saving a style is a button in the fill inspector |
| 9 The bar | none | none | none | an audit, not a feature |

**Where the rows sit.** Group and Ungroup go in the Layer menu directly above
the divider that starts Bring to Front, so the structure commands are together.
Make Component, Insert Component, Detach Instance and Select Main Component form
their own group under that. Show Library sits directly under Show Layers in
View, because they are the same kind of thing.

**Why these keys.**

- **⌘G and ⇧⌘G** are Photoshop's Group Layers and Ungroup Layers, and the user
  asked for Photoshop parity. macOS reserves ⌘G for Find Again by convention;
  Photonz has no Find, so it is free.
- **F for the frame tool** is the design tool convention. Photoshop's F cycles
  screen modes, which Photonz does not have, and F collides with none of the
  tool keys already spent (V C A L R O H T Z I G W).
- **⌥⌘K for Make Component** and **⌥⌘B for Detach** are the keys a design tool
  user already has in their fingers. Photoshop has neither command and binds
  neither key, so there is nothing to be compatible with.
- **Frame Selection gets no key.** The design tool key for it is ⌥⌘G, which is
  Photoshop's Create Clipping Mask. Photonz may well want clipping masks later,
  so that key stays unspent.
- **The Library toggle gets no key.** Photoshop's Libraries panel has no default
  key either, and ⌥⌘L is already Show Layers.

**Keys this work spends, so nothing else takes them:** ⌘G, ⇧⌘G, ⌥⌘K, ⌥⌘B, F.

### The two canvas gestures, and what they collide with

Nesting needs a way in and a way out, and both keys are already busy.

- **Double click goes one level deeper.** Today a double click on a text layer
  opens it for typing and a double click on an arrow opens its caption. The rule
  that keeps all three consistent: a double click always descends. On a group it
  selects the child under the pointer; on a text layer, which has nothing inside
  it, descending means opening it to type. So double clicking a group that holds
  a label selects the label, and double clicking again starts typing.
- **Escape comes back out one level**, and it slots into the priority order the
  canvas already runs (cancel a drag, then clear the marching ants, then clear
  the layer selection, then return to the select tool). Stepping out of a group
  goes in ahead of clearing the layer selection: while you are inside a group,
  Escape leaves it with the group selected, and only once you are at the top
  does Escape clear the selection as it does today.
- **The group you are inside draws a faint dotted box of its own** (added when
  step 1's keys shipped, 2026-09-03). Without it, descending is a mode with no
  sign of itself: the handles move to one piece and nothing else on the canvas
  changes. The box is the selection blue at a quarter strength, one point wide
  and finely dotted, so it reads as the room you are standing in rather than
  competing with the selection outline inside it.
- **A click picks the outermost thing you are not already inside**, and the
  group you are inside is remembered only while you are in it: nothing about it
  is stored in the document. Clicking anything outside that group drops you back
  to the top level, so there is always a second way out besides Escape. Clicking
  a sibling of the piece you have selected keeps you at that level rather than
  throwing you to the top.

## The flag each step ships behind

Six flags, all **Next only** and all **on by default in Next**, matching every
other Next flag in the catalog. Current never sees any of them.

| Step | Flag | Turning it off restores |
| --- | --- | --- |
| 1 (model and renderer) | none | nothing to restore: they are never flagged |
| 1 (keys and layers list) | `next-layer-groups` | no Group or Ungroup rows, a flat layers list, no descending on double click |
| 2 | `next-frames` | no frame tool, no New Frame, no per frame export scope |
| 3 | `next-library` | the right dock exactly as it is today |
| 4, 5, 6 | `next-components` | no Make Component, no instances, no Library components section |
| 7 | `next-starter-components` | the Library holds only components you authored |
| 8 | `next-styles` | fills are raw values only, no Library styles section |
| 9 | none | it is an audit of everything above |

Three rules that go with them:

- **The model and the renderer are never flagged.** The first two tasks inside
  step 1 ship unconditionally, because a switch that gates nothing a person can see is a
  switch with no effect, and because a document that already contains groups
  has to keep opening and drawing correctly whatever the flags say. Turning a
  flag off takes away a way in, never a document's contents.
- **A flag whose prerequisite is off behaves as off.** `next-frames`,
  `next-library` and `next-components` need `next-layer-groups`;
  `next-components` and `next-styles` need `next-library`;
  `next-starter-components` needs `next-components`. The Experiments row says
  what each one needs, so a switch that appears to do nothing explains itself.
- **They retire together.** When the whole ladder is the way Next works, all six
  come out of the catalog in one change rather than lingering as dead switches.

## What the first version deliberately does not do

So later work is not measured against a promise nobody made. Each of these is a
real limit of the slices above, not an oversight.

- **A group does not scale what is inside it.** A group's size follows its
  contents; there is no resize handle that stretches five children at once. A
  frame has a size, but resizing a frame moves where it clips, it does not
  resize the layers inside.
- **Nothing rotates.** No layer, group or frame has a rotation, which is what
  keeps the coordinate rule pure addition.
- **No auto layout and no constraints.** A child does not move or stretch when
  its frame changes size. This is the single largest piece of the vision left
  out, and it is sequenced after the whole ladder.
- **Components live in the document they were made in.** There is no shared
  library across documents, no publishing, no versioning and no update
  notifications. The starter set is the one exception: it is provided by the app
  and available everywhere, and dropping one copies it into your document.
- **Styles are per document too**, and have no token layer underneath, so there
  is no light and dark resolution of a named color yet.
- **Only three kinds of exposed property**: wording, whether a part shows, and a
  choice among shapes the main already contains. No numbers, no colors, no
  images as properties.
- **A text override does not resize its instance.** Without auto layout, a long
  label can overflow the button it sits in.
- **Detach is one way.** There is no re-attach; undo is the way back.
- **A main cannot be made from a group that already contains a main.** An
  instance inside a main is fine and updates correctly; promoting a group that
  holds a main is out, and the command is disabled with the reason on hover.
- **The Position & Size fields still show one layer at a time**, so a group and
  a child cannot be edited together.
- States, composites bound to data, prototyping connections, modes and published
  systems stay deferred as set out above.


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

## Landed: layers can hold layers (Next, unflagged, 2026-09-03)

Step 1's first task, the model half. Nothing appears on screen: no group can be
made from the interface yet, and no document that exists today looks or behaves
any different. What changed is that the picture can now hold a tree.

- **A group is a layer whose content is other layers** (`LayerContent.group`,
  carrying `GroupContent.children`). Not a second document kind, not a new
  top-level list.
- **A child's frame is measured from its parent's origin**, exactly as decided
  above. `PhotonzDocument.canvasFrame(of:)` adds the origins up the chain when
  something needs canvas space.
- **A group's box is derived, never stored.** Its `frame.origin` is the anchor
  its children hang from and its `frame.size` is unused: the box comes from
  `Layer.localBounds`, the union of what it holds. So drawing a child that
  sticks out to the left gives that child a negative X instead of silently
  rewriting every sibling's numbers.
- **Every document helper reaches inside**: find, add, move, remove, reorder,
  restack, duplicate, hit test, marquee, canvas crop and canvas resize. A
  selection that spans two levels restacks inside each list rather than pulling
  a child out of its group, and a marquee grabs a group whole or not at all.
- **Duplicating a group mints fresh ids all the way down**, so the same subtree
  can sit in two places and `layer(id:)` stays unambiguous.
- **Reparenting rewrites position**, so dragging a layer into or out of a group
  does not move it on screen (`moveLayer(id:toGroup:)`).
- **`groupLayers` / `ungroupLayer` exist in the model** and round-trip exactly.
  The keys that call them are the third task in step 1.
- **`flattenedLayers` is the bridge**: canvas-space leaves, bottom-up, carrying
  the visibility, lock and opacity of the groups above them. The renderer and
  the package writer run on it, so a document with groups draws and saves
  correctly today. A document with no groups gets its own array back untouched,
  so nothing about the existing path costs anything.
- **On disk nothing changed.** A flat document encodes byte for byte as it did,
  and a legacy payload decodes unchanged; groups are a new case, not a wrapper.

### A group draws as one thing (renderer, landed 2026-09-03)

Step 1's second task. Still nothing on screen: no group can be made from the
interface. What changed is that when one can be, it will look right.

- **A group with no styling of its own passes through.** Its children draw
  straight onto the canvas, exactly as if they sat loose, so grouping never
  changes a single pixel and a highlight inside a group still multiplies with
  the photo underneath it. This is the common case and it costs nothing.
- **A group that carries styling is one object.** Its children composite into a
  private buffer first, and then the group's blur, rounded corners, border,
  shadow and opacity apply once, to that one picture: a card with a shadow looks
  like a card instead of three overlapping shadows, and a half-faded group does
  not show its own pieces through each other.
- **Rounded corners follow the group's box** (`localBounds`) and clip what the
  group holds. The buffer itself is sized by `Layer.renderBounds` — the box
  grown by how far everything inside it reaches — so a child's own shadow or
  blur is never clipped by the edge of its group.
- **Blending is isolated inside a styled group.** A child that multiplies sees
  the group's contents below it, not the canvas. That is what being one object
  means, and it is why a plain group passes through instead. A zoom callout is
  the exception: it still magnifies the real canvas beneath its group.
- **Repainting stays cheap where it can.** An edit inside a plain group repaints
  only what moved; an edit inside a styled group repaints the whole group,
  because the group's fade and shadow are computed from all of it.
- **A group has a drag sprite** like any other layer, sized to the box its
  contents make.
- `flattenedLayers` stays as the bridge for the package writer, which wants
  leaves; the renderer now walks the tree itself.

Deliberately left: the Position & Size fields would show 0 for a group's W and
H, which no one can reach until the Layers list learns to show groups. A group
never scales or rotates what it holds, so a transform or a crop on a group is
ignored rather than applied.

### The layers list shows what is inside a group (landed 2026-09-03)

Step 1's fourth task, and the first one anybody can see. A group stopped being a
row with something hidden behind it.

- **A group row opens.** A chevron before the thumbnail twists the group open,
  and its contents draw indented 14 pt under it, one level per group. The
  column the chevron sits in appears only once the document HOLDS a group, so a
  screenshot with three annotations on it is the list it always was.
- **A shut group says how much it is hiding**, as a quiet count on the right of
  its row, in the same weight the Canvas row uses for its dimensions.
- **Open is interface state, not document state.** It lives on the window, so
  opening a group is not an edit, costs no undo step, and never touches the
  file. It survives selection, undo and redo, and it does not survive a
  relaunch.
- **The list follows the canvas.** Any change of selection opens the groups
  above the newly selected layer, so double clicking into a group on the canvas
  opens that group in the list with the piece inside it highlighted. The two
  never disagree about what is selected.
- **A drag says what it is about to do before you let go.** Each row has three
  zones: the top strip puts what you are carrying in front of that row, the
  bottom strip behind it, and the middle of a group row puts it inside. Above
  and below always mean *become that row's sibling*, and the line is drawn at
  that row's indent, so the line itself names the list you are joining. Dropping
  against a row that sits loose on the canvas is the whole of taking a layer out
  of a group.
- **An open group row has no "below".** The slot under it already belongs to its
  own topmost child, so aiming there would land the layer somewhere the eye
  never pointed. Its bottom strip means inside. To place a sibling after an open
  group, drop above the row that follows its contents.
- **Dropping into a group opens it**, and what you dragged becomes the
  selection, so the inspector talks about the layer you just acted on.
- **A drag carries the whole selection** when the row you grabbed is part of it,
  the way Delete and Duplicate already do, and the rows keep their relative
  stacking.
- **Locked layers stay put.** `restackLayers` and `groupLayers` already refuse to
  move one; the panel's drag used not to, so the locked Background could be
  shoved into a group. It now agrees with the Layer menu.
- **Nothing jumps.** Every dropped layer's position is rewritten into its new
  parent's space, and a drop that would change nothing is refused, so a wasted
  drag costs no undo step.
- The decision lives in `PhotonzCore` (`LayerPanelTree.swift`: `panelRows`,
  `LayerDropZone.forPointer`, `dropProposal`, `dropLayers`), so what a pointer
  over a row means is tested rather than buried in a view.

Deliberately left: no keyboard way to open a group, no open-all, and no
horizontal aiming inside a drop line to choose a level.

## Landed: a frame is a group with a size (Next, `next-frames`, 2026-09-03)

Step A2. The first thing in this ladder a person can build a screen on.

- **A frame is a group whose stored size is finally used.** An ordinary group's
  box follows its contents and its stored size is unused; setting
  `GroupContent.isFrame` turns that stored size into a real box the contents
  live in. So moving, restacking, grouping, undo, hit testing and saving are all
  the code that already existed, and there is no artboard list on the document.
- **It paints a surface, white by default.** A frame with no fill is invisible
  on a white canvas, which makes "draw a frame" feel like nothing happened. The
  Frame inspector section carries the surface, the size preset menu and a
  **Clip contents** switch; Position & Size types the exact numbers, which is
  where every layer's numbers already are.
- **It clips.** Anything past the edge is not drawn, not hit, and not exported.
  A frame that does not clip is one switch away, for the group you can see out
  of.
- **What you draw on a frame lands on it.** A shape, a text block or a callout
  whose CENTRE falls inside a frame becomes a child of that frame, with its
  position rewritten so it does not move. Without this a frame would be a
  picture of a boundary: the only way in would be dragging rows in the layers
  list. **Measurements deliberately do not join a frame** — a caliper measures
  across things and must not be clipped by one, so redlining is untouched.
- **The name and the edge are chrome, not content.** The canvas draws a frame's
  name above its top left corner and a hairline at its edge, in a neutral grey
  that reads on a white surface and a dark screenshot alike. Neither is in the
  document, so neither exports, and both stay one point wide at every zoom.
- **F draws one; a click drops one.** The frame tool joins the END of the
  drawing family in the tool bar, so no tool anybody already reaches for moves.
  A drag makes a frame the size you drew; a plain click drops one at the size
  you made last, which is how a second phone screen costs one click.
  Layer ▸ New Frame… opens the size list (Desktop, Laptop, Tablet, Phone,
  Square, Custom) and places the frame beside the frames already on the canvas,
  along their top edge, so a document reads as a row of screens. Layer ▸ Frame
  Selection puts a frame around what you have, fitted exactly and with no
  surface painted, because that is a boundary drawn around existing work.
- **Export takes a scope.** With frames in the document the Export sheet asks
  what to write: the whole canvas, or one frame. It opens on the frame the
  selection is in, the size line shows that frame's box, and the file is named
  after the frame. The picture is the frame's contents only: the canvas behind
  it and the layer overlapping it from outside are not in it.
- On disk an ordinary group writes none of the frame keys, so a document saved
  before frames existed is byte for byte what it was.

Deliberately left: a frame does not resize or lay out what is inside it (no
auto layout, no constraints); pasted and dropped layers do not land on a frame
yet, only drawn ones; the name is renamed in the Layers list rather than on the
canvas; and the frame's box has no rounded-corner preset of its own beyond the
Effects section every layer has.

## Landed: make a component, find it in the Library (Next, `next-components`, 2026-09-03)

Step C4. The payoff rung: something you drew becomes something you can fetch.

- **A main is a group with an id on it.** Promoting sets
  `GroupContent.componentID` and nothing else: the layer is not moved, not
  rewrapped, not re-parented, so nothing on the canvas shifts by a pixel when
  you press the key, and select, move, restack, hide, undo and save are all the
  code that already existed. The id is a fresh UUID rather than the layer's own,
  because a copy of a main is its own component and needs an identity that did
  not exist before: duplicating a main mints a new one rather than leaving two
  layers claiming to be the same thing.
- **Layer ▸ Make Component (⌥⌘K)** is live for one unlocked group that is not
  already a main, holds no main, and sits inside none. Components inside
  components are a nesting question this version has no answer for, so the row
  is dead rather than making one that later work would have to unpick.
- **It shows the Library on the Components shelf.** The Library is off until
  asked for, so without this you press a key and nothing changes anywhere you
  are looking. This is a departure from the mock, which draws the shelf already
  open. The tile carries a picture of the component, drawn from the same
  thumbnail cache the layers list uses, so a component looks like itself
  wherever it is listed.
- **Then it hands you the name.** The Component section's Name field takes focus
  with the name selected, so naming it is typing and ignoring it leaves a
  component called "Component". This is the New Folder idiom. It is the
  section's field rather than the layers row because that field visibly IS a
  field, and a row that silently became editable is a row nobody knows they can
  type in. The Component section sits directly under Position & Size, beside
  Frame, because both say what KIND of group you have selected.
- **One name, one place.** A component's name IS its layer's name, so the canvas
  mark, the layers row, the Name field and the Library tile cannot disagree.
  There is no second string to keep in step.
- **The mark is the design system's component glyph**, four diamonds, in violet
  rather than the selection accent. It sits above the main's top left corner on
  the canvas (chrome, so never in an export), next to the name in the layers
  list, and on the corner of the Library tile. A frame that has been promoted
  shows this INSTEAD of its frame label, so a box never wears two names.
- **Picking a tile opens the component's own section**, the way picking a layer
  opens its sections: the name, how many layers are inside, and Select on
  Canvas, which answers "where is this thing?".
- On disk an ordinary group writes no component key, so a document saved before
  components existed is byte for byte what it was.

Cut from the mock as later work, not oversight: exposed properties, the
control/variant pickers, the instance count and the override list all belong to
steps C5 and C6, and are absent rather than shown as controls that do nothing.
Deliberately left: nothing places a copy yet, so the shelf is browse only;
Ungroup on a main still works and quietly ends the component (undoable, and
there are no instances to break yet); and a main whose top edge is at the very
top of the canvas has its mark clipped, the same limit a frame's name already
has.

## Questions the user decides, not the loop

Each of these becomes a decision card when the step that needs it is claimed.
None of them blocks the step before it.

- ~~Does a frame clip its contents by default, or only when asked?~~ Answered by
  the task that built frames: it clips, and a **Clip contents** switch in the
  Frame section turns that off for the group you can see out of.
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

## Landed: a copy follows its original (Next, `next-components`, 2026-09-03)

Step C5. The other half of "create once, reuse everywhere": the shelf stops
being a list and starts handing you things.

- **A copy is a group that carries the id of the component it follows**
  (`GroupContent.instanceOf`). What is inside it is NOT its own: the document
  keeps every copy's contents equal to the original's. Because the contents are
  kept rather than referenced, the renderer, hit testing, export, thumbnails and
  the package writer all see an ordinary group and needed no change at all.
- **The sync runs inside `History.perform`**, so no command can forget it and
  editing an original plus every copy following is ONE undo step. It is skipped
  outright for a document with no copies in it (`holdsComponentInstance` stops
  at the first one it finds), so nothing about a screenshot costs anything.
- **The ids inside a copy are derived, not minted** (`ComponentIdentity.derived`,
  a stable mix of the copy's id and the piece's id). Fresh ids each sync would
  rewrite the document on every edit, and `History.perform` would record an undo
  step for an edit that changed nothing.
- **A copy is one object.** A click picks the whole copy, a double click does
  not descend into it, its layers row has no twist open, and nothing can be
  dropped inside it. A piece you could select inside a copy is a piece you could
  edit and lose the next time the original moved, and that silent loss is worse
  than the restriction. Overrides (C6) are the supported way in.
- **Four diamonds is the original, one diamond is a copy**, in violet, on the
  canvas, in the layers list and in the dock. The first cut drew a copy's mark
  as the four diamonds hollow; at nine to twelve points each diamond is under
  three points across and the outline read exactly like the fill, so it became a
  different SHAPE rather than a different weight. The original also carries its
  name on the canvas and a copy does not: a screen built from twelve buttons
  would otherwise wear twelve labels.
- **Three ways to place one**, all landing in `insertComponentInstance`: drag a
  tile onto the canvas (its own pasteboard type, so a dropped file and a dropped
  component can never be confused), double click a tile, or Layer ▸ Insert
  Component. Double click PLACES, which is what it already does on a Media tile;
  finding the original moved to a Select Original button. ⌘J on a copy makes
  another copy that is still linked.
- **A copy lands centred on where you let go**, and joins the frame it was
  dropped on, the same rule a drawn shape follows. Dropping a button on a phone
  screen has to put the button on that screen or moving the screen leaves it
  behind.
- **The pill says how far an edit reached**: "Updated, 2 copies of Setting". The
  things that moved are elsewhere on the canvas, often scrolled off it, so
  without it you change one thing and have no idea what else you changed.
  Placing, moving and duplicating a copy all report nothing, because none of
  them is an edit that reached anywhere — the count compares subtrees ignoring
  ids, since duplicating re-mints every id under a copy without one pixel
  moving.
- **A component may not hold a copy of itself**, directly or through anything it
  already holds; the model refuses rather than trusting the interface, and a
  drop onto the component's own original says "A component cannot hold a copy of
  itself" instead of quietly doing nothing.
- **Deleting an original does not delete the copies.** They keep exactly what
  they were drawing and become ordinary groups.
- On disk a group that is not a copy writes no copy key, so a document saved
  before this step is byte for byte what it was.

Deliberately left, and each one is a real limit rather than an oversight: a
copy's own opacity, blur, shadow and corner radius are its own and do not follow
the original (syncing them would make the Effects sliders snap back on a copy,
which is worse than the gap); renaming an original does not rename copies
already placed; the shelf tile shows a name and keeps the count of copies in its
tooltip and in the picked component's section; and Ungroup on a copy still
dissolves it, which is a detach by another name until Detach Instance arrives.

## Landed: a copy can be changed without leaving the family (Next, `next-components`, 2026-09-03)

Step C6, the last rung before the Library is worth shipping. A copy stopped
being a picture you can only move.

- **The original chooses what is adjustable.** Its section grew an
  **Adjustable** list and an **Add** menu: pick a piece of the component and the
  kind of knob it should be. A copy gets exactly those knobs and nothing else,
  which is the whole of "override safely". The decision lives on the original
  because it applies to every copy at once.
- **Three kinds, and they are the same shape as each other**: **wording** (what
  a text layer says), **show or hide** (whether a layer is drawn), and a
  **choice** (which ONE of a group's children is drawn). Every knob is one fact
  about one layer inside the original, so resolution is one code path rather
  than three.
- **A choice can only land on a shape the original holds**, so a copy can never
  show something the component does not define. Exposing one also settles the
  original on a single option: a group whose alternatives all draw at once is
  not a choice, and picking one on a copy would stack a second shape on the
  first rather than swapping it.
- **The Add menu is grouped by KIND, not by layer.** The mock lists every layer
  with every knob it could make; on a component of eight layers that is
  twenty-four rows, most of them meaningless. Here the three kinds are the
  headings and only the layers each knob makes sense for sit under them, with a
  layer already exposed that way dropping out.
- **A knob is named after the layer it exposes**, except where that name says
  nothing: every text layer in the app is called "Text", so a wording knob takes
  the WORDS ("Auto-enhance"), and every group the Group command makes is called
  "Group", so a knob on one takes what it does ("Shape", "Show"). Both are
  starting points; the name is a field in the list.
- **The answers live on the copy and are applied AFTER it is refilled from the
  original.** That order is the whole trick: an edit to the original reaches
  every copy, including one that has overridden something else, because each
  copy takes the original's picture whole and then the few facts it owns are
  written back over the top.
- **Every set knob has a way back.** A revert arrow appears on a row the moment
  it is overridden and puts it back to following the original. Without it a copy
  set ten edits ago could only be fixed by undoing ten edits.
- **A choice menu numbers repeated names for display** ("Rectangle",
  "Rectangle 2"), because two rectangles drawn in a row are both called
  "Rectangle" and a menu of identical rows is a menu nobody can choose from.
  Nothing is renamed in the document.
- **Detach** (Layer ▸ Detach Instance, ⌥⌘B, and a button on the copy's section)
  turns a copy into ordinary layers that no longer follow the original. It keeps
  exactly the picture it was drawing, and it says so in the pill, because
  nothing on screen changes when it runs and a command that looks like it did
  nothing is a command people press twice.
- **Layer ▸ Select Original** takes no key: it is a way to get somewhere, not an
  edit, and the copy's section has had a button for it since C5.
- **A knob whose layer is deleted out of the original goes with it**, and every
  copy's answer to it goes too, so nothing is left keyed to something no longer
  there.
- **Setting a knob does not raise the "copies followed" pill.** That pill
  reports what moved OUT OF SIGHT; this edit reached the one copy whose panel
  the person is typing into.
- On disk a group that exposes nothing and answers nothing writes neither key,
  so a document saved before this step is byte for byte what it was.

Cut from the mock deliberately: the "Custom property…" row (nothing behind it),
the stepper as a third built-in control shape, and the separate "Instance props"
section — a copy's knobs sit in the copy's own Component section, so there is
one place a component layer answers about itself.

Deliberately left: a knob cannot reach into a copy nested inside the original
(those contents belong to ITS original); there is no way to edit an original's
default from a copy's panel; knobs cannot be reordered; a long wording override
still overflows the copy, because there is no auto layout; and detach is still
one way, with undo as the way back.

## Landed: a color can be saved as a named style and reused (Next, `next-styles`, 2026-09-03)

Step D8, built before step 7 for the reason recorded there: the starter
components are specified as painted from styles, and that cannot happen until
styles exist.

- **A style is a color with a name, and it lives in the document.** No gradients
  (nothing in the app paints one), no text or effect styles yet, and no token
  layer underneath, so a name still resolves to one color rather than one per
  mode.
- **The color stays ON the layer.** A layer wearing a style is painted exactly
  as a layer somebody colored by hand, and the binding is the extra fact that
  says where the color came from. So the renderer, export, thumbnails and the
  package writer learn nothing about styles, and a copy of a component keeps
  drawing correctly whatever happens to the shelf.
- **Four colors can wear one**: a box's interior, a box or line's ink, a text
  block's ink, and a frame's surface. Each is a `ColorSlot` on the layer, so
  adding another later is a case in two switches.
- **The button sits on the rows that already exist.** The mock hangs "Save as
  style" off a Fill section of its own; the app already has a Fill row in
  Annotation, a Color row in Text and a Background row in Frame, so the styles
  button goes on those rather than making a fourth place to look for a color.
- **Saving asks for the name first, in the dock.** A field opens under the color
  row, on a name nobody is using, with the text selected: naming it is typing
  and Return is enough, Escape leaves nothing behind. The alternative — make a
  style called "Color" and hope the person finds where to rename it — is how a
  shelf fills with "Color 2", "Color 3".
- **A row wearing a style shows its color and its NAME, and the well goes
  away.** A shared color is not edited from one of the places it is used, so the
  only way to change it is to change the style. Unlink is in the same menu and
  says what it does, so the way back to a one-off color is one click and never a
  surprise.
- **The Library's Styles shelf is where a style is renamed, recolored and
  removed.** Picking a tile clears the layer selection by design, so applying a
  style could never be a shelf action; binding belongs on the row, where the
  layer is still selected. The picked style's section says how many colors it
  paints before you change it, has Select What Uses This, and Remove.
- **Editing a style repaints everything wearing it in one undo step**, because
  the repaint happens inside the same document mutation as the style's own
  change.
- **Removing a style repaints nothing.** Every layer keeps the color it is
  wearing and simply owns it again. Deleting a name must never delete work.
- **A safety net runs after every edit.** A binding is a claim, and anything
  that paints a layer some other way — the paint bucket, a paste, a tool default
  — would make that claim false. So a slot whose color has drifted from its
  style, or whose style is gone, quietly lets go and keeps what it is wearing. A
  row can never say "Accent" over a color that is not Accent. The check is one
  nil test per layer, on the walk the component sync already makes.
- On disk a document with no styles writes no styles key and a layer wearing
  none writes no bindings key, so a document saved before this step is byte for
  byte what it was.

Deliberately left: styles are per document, with no shared library across
documents and no publishing; there is no way to make a style without a layer to
save it from; a style cannot be applied to several selected layers at once; and
there are no text or effect styles, only color.

## Landed: the Library arrives stocked (Next, `next-starter-components`, 2026-09-03)

Step D7. The Components shelf now holds five components the first time it is
opened — **Button, Text Field, Card, Nav Bar, Badge** — so the first thing a
person does is drag one out rather than author one. `StarterComponents.swift`
in `PhotonzCore`, the shelf and its section in `LibraryPanel` / `ComponentPanel`.

- **They are data, not views.** Each is a plain subtree of the same boxes and
  text layers a person draws by hand, so once dropped nothing about one is
  special: it takes copies, its knobs turn, it detaches, it saves. Nothing
  downstream — renderer, export, package writer, layers list — learns a word.
- **A starter's id IS its component id**, fixed in the binary
  (`StarterComponents.fixedID`, built from bytes so there is no parse to fail).
  So the first drop brings the ORIGINAL into the document and every drop after
  that places a copy of it, one shelf tile covers both, and the tile's caption
  changes from "starter" to "main" / "2 copies placed" rather than the tile
  moving or vanishing.
- **They paint from five named styles** — Accent, Surface, Text, Muted, Border —
  which the drop brings into the document with them. So recoloring Accent once
  repaints every starter wearing it, which is step D8's argument made with
  something nobody had to build first. A style already in the document wins,
  matched by id and then by NAME, so somebody who keeps their own Accent gets
  theirs. A drop brings only the styles that starter actually paints from.
- **They are built at the document's `pixelScale`**, because a capture's canvas
  is measured in image pixels: a 36 point button drawn at one to one would land
  half size on a Retina screenshot.
- **`PhotonzCore` cannot measure text**, so `StarterComponents.layer` takes a
  measuring function and the app hands in `TextRasterizer.naturalSize`. Its own
  fallback is an estimate, good enough for a test and never what the app draws
  with. `StarterComponentRenderTests` draws the real thing and checks where the
  ink lands, because every number can be right and the label still off by ten
  points.
- **Starter text carries no contrast halo.** Every text layer normally gets one
  so a caption stays legible over a screenshot; on a button's label it reads as
  a defect.
- **A neutral kit, not a set of macOS controls.** A button that looks exactly
  like the system's invites people to expect the system's behaviour from it, and
  this is a drawing. Looking like a starting point is the honest thing for it to
  look like. It is one table of colors and sizes, so this is cheap to revisit.

Deliberately left: no **choice** knob anywhere in the set. A Filled/Outline
button needs its label inside each option, which would give the component two
wording knobs that each work half the time; the honest fix is per-option
wording, which the model does not have. Wording and show-or-hide only. Also
left: no way to add to the starter set, no starter frames or screens, and a
long override still overflows the control it sits in, because there is no auto
layout yet.
