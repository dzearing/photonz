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

**Groups do not rotate, and they scale only when you drag them.** Sitting still,
a group adds an offset to its children and nothing else, so a layer's canvas
position is the sum of the origins from it up to the canvas, plain addition.
Grouping something never changes a number inside it: a measured gap of 12 px is
still 12 px the instant it is grouped. Nothing rotates, at any level.

### Resizing places the pieces (landed 2026-09-03)

A container says how its contents line up, and any one piece inside may say
something different for itself. That is the whole rule. Each axis has four real
answers plus the one everything starts on:

| Across | Down | What it keeps |
| --- | --- | --- |
| Left | Top | its distance from that edge, and its own size |
| Right | Bottom | its distance from that edge, and its own size |
| Center | Middle | its offset from the middle, and its own size |
| Stretch | Stretch | BOTH distances, so it grows and shrinks with the container |
| Scale | Scale | nothing: position and size are both multiplied |

**Scale is what nothing-set means**, which is the proportional multiply this app
did before any of this existed, so every document saved before it resizes
exactly as it did. A container's default lives on the group
(`GroupContent.contentPlacement`), a piece's override lives on the layer
(`Layer.placement`), and each is optional PER AXIS: a divider can say "stretch
across" and leave "down" to the bar it sits in. Neither writes a key when it is
unset, so an untouched document is byte for byte what it was.

**This replaces the earlier rule that resizing a group scaled the layout
proportionally.** That rule is still what an unset piece does, but it was the
wrong DEFAULT for a container: a label centred in a button lands off centre at
any new width, because the label's position scaled while its type did not. The
five Library components therefore arrive with placements set — a button centres
its contents and stretches its fill, a nav bar pins its hairline to the bottom
and stretches it across — so dragging one wider needs no manual fixing.

**What holds its size, always.** Anything measured in points: text point size,
stroke width, corner radius, shadow and blur, a caliper's ticks and its label.
14 pt type is 14 pt type on a real screen, and a card that got wider did not
change what its label should read at.

**Text is the one box that is not simply multiplied.** Its width is — that is
its wrap width — but its height is however tall the words are once they have
re-wrapped to it, because the type never changed size. See "A label grows to fit
what it says" below. The one exception is a label told to fill the height, which
is the whole point of that choice: the box takes the height it was handed and
Align says where the words sit in it, so a label in a 36 pt row is centred in the
row rather than stuck against its top edge with a hole underneath. See "Where the
words sit in their box".

**A screen is a container too, with one substitution.** Dragging a frame's edge
moves where it clips rather than magnifying what is on it, so on a screen
nothing ever scales: a piece nobody gave a rule to holds still, which in a
frame's own space is pinning to the top left. Scale is therefore not offered for
anything on a screen, and a screen's Contents rows read Left and Top rather than
Scale, because that is what they honour. A bar set to Stretch runs the full
width of a screen dragged wider; a button set to bottom right stays in the
corner. A frame nested inside a group being scaled still scales, contents and
all, because there the intent was plainly "make all of this bigger".

**A piece that is both stretched and rotated** is stretched by its BOX, not by
what you see. Rotation is applied at render time around the frame's centre, and
placement is worked out on the unrotated frame, so a rotated child set to
Stretch gets a wider box and keeps spinning about that box's new centre. Its
visible corners will therefore poke past the inset you pinned, because the
inset was measured on the box. This is deliberate: the alternative is solving
for a rotated bounding box, which has no answer at 45 degrees that anybody can
predict. Rotate the container instead of the piece when you want the edges to
stay honest.

**What a measurement says afterwards.** A caliper's feet move with everything
else, so a caliper inside a group that doubled now spans twice as far and reads
twice the number. That is not the number drifting, it is the caliper still
telling the truth about what is on screen. The promise is precise: **grouping
never changes a number; resizing a container changes what is measured, and the
number says so.**

**A container names the pieces that are not following it.** Under the Contents
rows, a group or screen lists every piece directly inside it that carries a rule
of its own, with what that rule says beside the name ("Stretch across"), and
clicking a name goes to that piece. Without it the only way to find an override
was to click through every piece in turn, so a group whose contents refuse to
move was a mystery until you did. A container where everybody follows says
nothing at all, and the list stops at six with a count of the rest, since a
Layout section taller than the panel helps nobody. A piece that set the same
answer the container happens to say is still on the list: it stops matching the
moment the container's answer changes, which is exactly when you want to have
known. Only DIRECT children are listed — an argument further down belongs to the
container having it.

**Nested containers place their own contents.** A group inside a group gets its
new box from its parent's rule, then lays its own contents out by its own rules,
all the way down. A piece that keeps its size renumbers nothing inside it.

**The anchor moves with the box.** A group's origin is still not its box (see
below); it simply moves with the box so no sibling gets renumbered against an
origin that wandered. A frame's stored size IS its box, so it takes the new box
exactly rather than a multiply that rounds.

**Two things deliberately do not resize.** A **copy of a component** takes its
size from its original, because a copy's contents are refilled from the original
after every edit and a stretched copy would snap straight back; resize the
original and every copy follows. A container with **no width or no height** does
not stretch in that direction, because there is nothing there to divide by.

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

**Where it lives.** `LayerPlacement` and the resolution rule are in
`Sources/PhotonzCore/LayerPlacement.swift`; the maths is one function per axis
in `LayerScaling`; the inspector's Layout section is
`Sources/Photonz/PlacementInspector.swift`, behind `next-placement`. The RULE is
unflagged, because a layer with nothing set behaves exactly as it always did.

**On disk**, a document saved before any of this decodes unchanged, because a
flat list is a tree of depth one and an unset placement writes nothing.

### Where the words sit in their box (landed 2026-09-03)

**The decision: a label told to stretch fills the box and centres its words, and
text gains an Align of its own.** The alternative was to stop offering Stretch
for text at all, and it was rejected: a wrapped paragraph already re-wraps when
its box widens, which is exactly what a card body wants, so hiding the choice
would take away the one thing that worked to tidy up the one that did not.

Text has always been drawn from the top left of its box. That is invisible while
the box hugs the words and wrong the moment the box is bigger than they are, so
the missing half was never stretch, it was **where the words sit in the room
they have**. `TextContent` now carries an `alignment` (left, center, right) and
a `verticalAlignment` (top, middle, bottom), and the Text section of the
inspector has an Align row with the two of them, behind `next-placement`.

- **Nothing set is the top left**, which is what every document written before
  this drew, and no key is written for it. Left carries no paragraph style at
  all, so the render is byte for byte what it was.
- **Telling text to stretch centres it on that axis**, but only while it has
  never been given a place of its own: horizontal Stretch sets Align to Center,
  vertical Stretch sets it to Middle, in the same one edit, one undo. That is
  what makes the choice do something you can see instead of widening an
  invisible box. The Layout section says so in a line under the rows.
- **After that the Align row belongs to the user.** Coming off Stretch never
  rewrites it, and neither does stretching again.
- **Alignment never moves the box.** It says where the words sit in the room the
  box already has, so a stretched label stays stretched and a paragraph keeps
  its wrap width.
- **Stretching down actually makes that room** (landed 2026-09-04). A text box
  normally throws away a height handed to it, so for a while vertical Stretch
  did nothing at all and read as Top: the words moved to Middle of a box that
  never grew. Now the height is kept whenever the container is the one that
  decided it — a row hands every item the height of the row, a grid the height
  of its cell, and a resized group or screen the height its rule worked out —
  and it is never less than the words need, so a room too small for them still
  shows every line. Down a COLUMN there is nothing to fill: a column hands each
  row the height it already had, so Stretch there leaves the box hugging its
  words, and the inspector's Height tip still says the words decide it. Nothing
  re-measures when a file is opened, so a document saved with the choice already
  set is exactly what it was until its container is next resized.
- **A box too small for its words keeps every line.** CoreText fills a frame
  from the top down and drops what does not fit, so text that needs at least the
  box it has is drawn exactly as it always was rather than centred into losing
  its last line.
- **A box bigger than its words keeps that room when it is re-worded.** Typing
  in it happens at that width with the draft aligned the way the committed words
  will be, so a centred label does not spring to the left edge for the length of
  the edit and back on Return.

**Where it lives.** `TextAlign`, `TextVerticalAlign` and the stretch rule are in
`Sources/PhotonzCore/TextAlign.swift`; the drawing is `TextRasterizer`
(a paragraph style across, a shortened lay-out box down); the Align row is in
`TextInspector` and the caption in `PlacementInspector`.

**What this is not.** It is not auto layout: nothing re-flows the type size, and
a label whose words outgrow a shrinking button still overhangs it. That stays
`ui-layout`'s job.

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
| 3 The Library panel | View | Show Library (a checkmark while it is up) | none | a document is open |
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
  competing with the selection outline inside it. A **screen never draws it**
  (2026-09-03): the box means "you stepped in here", and you never step into a
  screen, so it would be on almost all the time and say nothing. A screen shows
  where it is already, with its surface and the name above it.
- **A click picks the outermost thing you are not already inside**, and the
  group you are inside is remembered only while you are in it: nothing about it
  is stored in the document. Clicking anything outside that group drops you back
  to the top level, so there is always a second way out besides Escape. Clicking
  a sibling of the piece you have selected keeps you at that level rather than
  throwing you to the top.
- **A screen is the exception: it is see-through for what sits on it**
  (2026-09-03). One click on a button you dropped on a screen picks the button,
  and you can drag it back off in the same gesture, because a screen is the
  surface you are building on rather than a package you opened. One level only,
  so a group on a screen is still one object and a screen inside a screen is
  still picked whole; a double click is what reaches into either. A click on the
  screen's own empty surface still picks the screen. The cost, taken knowingly:
  a screen covered edge to edge by a layer has no empty surface left to click,
  so it is picked from its name above it or from its row in the Layers list.
- **Where you are follows what you are holding** (2026-09-03). Dragging a layer
  off a screen takes you out of that screen with it, so Escape never jumps back
  to a screen the layer has already left.
- **⇧-click adds what you clicked to the selection**, or drops it when it is
  already in (2026-09-03). Before this the only way to pick two things on the
  canvas was to sweep a marquee around them, which takes in whatever else is
  nearby, so reaching ⌘G meant tidying up first. The gesture is the Layers
  list's, on the picture: it resolves through the same walk a plain click does,
  so at the top level you add whole groups and inside a group you add its own
  pieces. It extends the selection at the level you are on and only there: a
  ⇧-click out on the canvas while you are inside a group does nothing, because
  the alternative is a selection made of layers from two different lists and a
  silent step back out of the group you were working in. What sits on a screen
  is reached the same way a plain click reaches it, so picking two buttons on a
  screen is a click and a ⇧-click. And it never starts a drag — the press is
  about what is selected.
- **A sweep picks at the level you are on** (2026-09-05). Once you have stepped
  inside a group, a rubber band takes in that group's own pieces and nothing
  above them, so a band round two of the three things in a button picks those
  two instead of the button whole, or nothing at all. A nested group inside it
  still comes whole, a screen that cuts off what leaves it never hands over
  what it is hiding, and a copy of a component has no level to sweep inside at
  all. ⇧ adds within the same level, the way a ⇧-click does, so a selection can
  never end up made of one piece and one whole layer from the top. Out on the
  canvas nothing changes: the same band picks whole groups and loose layers.
  The level is read at the PRESS, because a press on bare canvas lets go of the
  selection and letting go is what puts you back at the top. A click on bare
  canvas that lets go still steps you back out, whether one piece was picked or
  five (2026-09-05: it used to step out only for one).

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
| picker | `next-color-picker` | the color rows open the picker the app shipped with, and shadow, backdrop and the measurement rows open the system color panel |

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

## A label grows to fit what it says

A box around words has to be the size the words are, or the last line is cut
off and the label hangs over the shape behind it. So a text box re-measures
itself whenever the two things that decide its shape change:

- **Its width.** Width IS the wrap width. Drag the right edge in, type a number
  into W, or let a stack stretch it across a fixed-width container, and the
  words re-wrap and the box becomes as tall as they now need. The top edge stays
  put and it grows downward. Dragging the bottom edge does nothing, which is
  what the inspector's Height field already says.
- **Its words.** A copy of a component answering a wording knob re-measures too.
  A box nobody has narrowed hugs its words, so it stays on one line and simply
  gets wider, growing from whichever edge its group lines contents up on; a box
  somebody HAS dragged narrower is a paragraph, so it keeps that wrap width and
  grows downward.

- **The room its container has for it.** A label in a group with a width of its
  own — one somebody typed, or one a ceiling is holding in — is as wide as its
  words until they outgrow that room, and then it wraps inside it and the group
  grows downward. This is the same answer a max width and a label give
  everywhere else, and it replaces the old one, where the words simply ran out
  past the far edge.

  Two rules keep it honest. It never narrows a label past the widest single
  WORD in it: below that there is nothing left to break and the letters come
  apart in the middle of a word, so a word too long for the room hangs out of
  it exactly as it did before. And the flow remembers that IT narrowed the
  label (`Layer.wrappedByItsContainer`), undoes that at the top of every pass
  and works the width out again, so raising the ceiling gives the words their
  line back instead of leaving them stuck on two.

  A paragraph somebody dragged narrower by hand is not touched. That width is
  an answer, not a derivation.

Nothing else re-measures. Moving a layer, restyling it, or changing anything
that is not its width, its words or the room around it leaves the box exactly
as it was, so a document that was laid out by hand is never quietly re-flowed
under its author.

Two rules make it hold together:

- **It happens inside the same undo step as the edit.** The measurement is
  injected into the pure model (`TextMeasurement.use`, wired to
  `TextRasterizer.naturalSize` at launch, an estimate everywhere else), so
  `Layer.resized(to:)` can re-measure without `PhotonzCore` importing CoreText.
- **The flow runs until nothing moves.** A stack works out where its rows go
  from the sizes they had going in, so a label that re-wrapped while being
  placed is taller than the row under it was told about. `reflowLayouts` repeats
  until a pass changes nothing, capped, and it runs again after copies are
  refilled because that is the moment a copy's own wording lands.

A copy of a component arranges itself the way its original does: the stack or
grid on the original travels to every copy, along with how it lines its contents
up. Without that, a copy of a stack is a heap that happens to look right until
something inside it changes size.

## What the first version deliberately does not do

So later work is not measured against a promise nobody made. Each of these is a
real limit of the slices above, not an oversight.

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
- **Five kinds of exposed property**: wording, whether a part shows, a choice
  among shapes the main already contains, a COLOUR (one slot of one layer: its
  fill, outline, ink or border), and a NUMBER (one of four numbers on one layer:
  its corner radius, the thickness of the line round it, the gap a stack holds
  its contents apart by, or the room it keeps inside its edges). No images as
  properties, and no numbers beyond those four. A colour answer may be a raw
  paint or a saved colour, so a copy can be "the danger one" and follow every
  later edit to that name.
- **Detach is one way.** There is no re-attach; undo is the way back.
- **A main cannot be made from a group that already contains a main.** An
  instance inside a main is fine and updates correctly; promoting a group that
  holds a main is out, and the command is disabled with the reason on hover.
- Composites bound to data, prototyping connections, modes and published systems
  stay deferred as set out above. **States are no longer deferred**: a component
  holds versions of itself, see "Landed: a component holds more than one
  version" below.


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
- **The section speaks for the whole selection** (2026-09-03). Pick four
  buttons and one typed width makes all four that width; one typed X lines all
  four left edges up. Where the picked layers already agree the field shows
  their number, and where they do not it says **Mixed**, because a number that
  stands for one layer out of four is how you set three layers to something you
  never meant to type. Every edit is ONE undo step.
  - An arrow key on a Mixed field steps each layer from its OWN number, so a
    row that is spread out moves together and stays spread out. A number typed
    into the box and then stepped lands on all of them.
  - A field acts only on the layers that accept it. Select three rectangles and
    an arrow and W still reads and sets the three rectangles; the hover tip
    says "Applies to 3 of the 4 selected layers." A field no picked layer
    accepts is dimmed with the reason, as before.
  - A layer inside a picked group takes no place of its own, the same rule
    Arrange uses: the group already carries it, and setting both would move it
    twice. Locked layers stay in the count and accept nothing.
- **A typed size stops where the drag stops** (2026-09-04). Every layer floors
  at one point except text, which floors at 80: below that a caption is an
  unreadable sliver of a column many lines tall, so the canvas refuses to drag
  one narrower and the W field refuses to type one. Type 12 and the box lands
  on 80, and the field then reads 80 rather than the 12 nothing took. An arrow
  key stops at the same place instead of counting on down a box that is not
  moving, and the W hover tip says "Will not go below 80 px." before you find
  out by typing. The floor is one number,
  `TextMeasurement.minimumWidth` (`TextRasterizer.minimumTextWidth` is it), read
  per layer through `LayerGeometryEditing.minimum(for:)`.
- Model and rules are `LayerGeometry` / `LayerGeometryEditing` /
  `LayerGeometrySelection` in `PhotonzCore`; the section is
  `GeometryInspector.swift`; the write goes through
  `EditorState.setLayerGeometry(field:to:)` and `stepLayerGeometry`, which fold
  the whole selection into one `History.perform` and reuse the canvas drag's
  frame commit so annotation endpoints and caption placement stay correct.
  Walked end to end by `Scripts/playtest/multi-geometry-walk.json`.

Not in this slice: a proportional lock, a rotation field, and treating the
selection as one box (typing X moves every layer onto that edge, it does not
slide the group of them as a unit).

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
never rotates what it holds, so a transform or a crop on a group is ignored
rather than applied. (Resizing landed later — see "Resizing places the
pieces".)

### The layers list shows what is inside a group (landed 2026-09-03)

Step 1's fourth task, and the first one anybody can see. A group stopped being a
row with something hidden behind it.

- **A group row opens.** A chevron before the thumbnail twists the group open,
  and its contents draw indented 14 pt under it, one level per group. The
  column the chevron sits in appears only once the document HOLDS a group, so a
  screenshot with three annotations on it is the list it always was.
- **A shut group says how much it is hiding**, as a quiet count on the right of
  its row, in the same weight the Canvas row uses for its dimensions.
- **Open is interface state, not document state.** Opening a group is not an
  edit: it costs no undo step and never touches the file. It survives selection,
  undo and redo.
- **It also survives quitting.** Which groups a picture had open is filed under
  that file's path in the app's own settings (`OpenGroupMemory` in PhotonzCore),
  beside the other things the app remembers about how you were looking at
  something, so a picture opens looking the way you left it without a byte of
  interface state living in the document. A group deleted since last time is
  dropped from the record on the way in and on the way out; a picture with every
  group shut has no record at all; a picture that has never been saved or opened
  from anywhere has nowhere to file one, so it is not remembered.
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
  of. The same switch is on ANY container with a box of its own: a group given
  a width, a height or a largest size gets a **Clip contents** checkbox under
  those numbers in the Layout section. It starts OFF there, because a group has
  always let its contents hang out and no picture already drawn should change,
  while a screen has always cut them off and still does. A group that closes
  around its contents is not offered it, because nothing hangs out of it.
- **A container says when it is hiding something you drew.** Cutting a layer off
  hides it completely: it is not drawn, not clickable, and until now its row in
  the Layers list looked like every other row, so a label dragged a little too
  far was lost with undo as the only way back. A layer that ends up COMPLETELY
  outside the box around it now carries an orange scissors on its row, and the
  hover tip names the box and says how to get the layer back. A SHUT container
  carries the same mark and says how many layers inside it have gone, because a
  mark you have to open a group to find is a mark nobody sees. A layer half out
  is not marked: half of it is still on screen, and marking it would cry wolf on
  every card whose title runs a little wide.
- **What you draw on a frame lands on it.** A shape, a text block or a callout
  whose CENTRE falls inside a frame becomes a child of that frame, with its
  position rewritten so it does not move. Without this a frame would be a
  picture of a boundary: the only way in would be dragging rows in the layers
  list. **Measurements deliberately do not join a frame** — a caliper measures
  across things and must not be clipped by one, so redlining is untouched.
- **What you paste or drop on a frame lands on it too.** ⌘V puts the layer back
  where it was copied from, sixteen points along, and it joins whichever screen
  that spot is on. A file dragged in from the Finder joins the screen it was let
  go over: it is sized to fit that screen rather than arriving four times too
  big and clipped to its middle, and it is nudged just far enough to sit wholly
  inside rather than half over the edge. A copied SCREEN is the exception that
  never gets swallowed: pasting one makes a second screen beside the first, not
  a screen hidden sixteen points inside it. On bare canvas, and in a document
  with no frames at all, every one of these lands exactly where it always did.
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
auto layout, no constraints); and the frame's box has no rounded-corner preset
of its own beyond the Effects section every layer has. (Pasted and dropped
layers, and renaming on the canvas, both landed later the same day; see below.)

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
  Frame section turns that off for the group you can see out of. A group with a
  size of its own carries the same switch in the Layout section, off by
  default (2026-09-05).
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
which is worse than the gap; **lifted the same day, see "a copy follows the
original's look" below**); renaming an original does not rename copies
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
  nothing: every text layer in the app is called "Text" and every group the
  Group command makes is called "Group", so a knob on either takes what it DOES
  ("Wording", "Show", "Shape"). It is never named after what the layer says, for
  the reason under "a knob is named for what it controls" below. A starting
  point either way; the name is a field in the list.
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

## Landed: two shapes become a choice in one step (Next, `next-components`, 2026-09-03)

The rung the C6 audit called out: the choice knob worked, but the path to it was
unguided. A knob reaches a GROUP, so offering a choice meant already knowing the
shape of the answer — group the alternatives by hand, then find that group again
in the original's Add menu. What a person actually has is two shapes side by
side.

- **Layer ▸ Make Alternatives** takes the selected shapes, wraps them in a group
  of alternatives, settles the original on one of them and adds the knob every
  copy uses to pick between them. One command, one undo.
- **It takes the selection ⌘G would take**, so nobody learns a second rule about
  what "these layers" means. Select one group that already holds alternatives
  and it exposes that group where it stands rather than wrapping a group in a
  group, so grouping by hand first is no longer a dead end.
- **The row is ABSENT, not dimmed, when the selection cannot become a choice.**
  Every other row in that menu reads as something you might want on any
  selection; this one only means anything on two shapes inside an original, and
  a dead row on every other selection is a row people hunt the reason for. It
  appears the moment it would work. (The cost is discoverability: you cannot
  find it before you need it. Raised in the audit.)
- **The group is called "Choice" and its knob "Shape"**, because the knob is met
  beside a chip that already says "choice" and a row reading "Choice · choice"
  says the same word twice. A group somebody named themselves keeps its name and
  the knob borrows it.
- **A pill says what happened**, because settling the choice HIDES all but one of
  the shapes that were just selected: without a word on screen the command reads
  as having deleted one. It names the knob as well, since the knob itself appears
  on the ORIGINAL's Adjustable list, which is not the panel you are looking at
  while you work inside the component.
- **Nothing happens outside an original.** Two shapes on the bare canvas have
  nowhere to hang a knob, and inside a copy the layers belong to ITS original and
  would be rewritten by the next sync.

Deliberately left: the alternatives are still named "Rectangle" and
"Rectangle 2" unless somebody names them, so the copy's menu reads as two
identical rows numbered apart; the command does not make a component for you
when the shapes are loose on the canvas; and the new group's box still spans the
hidden alternative, so the selection can extend past what is drawn.

## Landed: a color can be saved as a named style and reused (Next, `next-styles`, 2026-09-03)

Step D8, built before step 7 for the reason recorded there: the starter
components are specified as painted from styles, and that cannot happen until
styles exist.

- **A style is a paint with a name, and it lives in the document.** Since
  2026-09-04 that paint can be a gradient (see the section below); no text or
  effect styles yet, and no token layer underneath, so a name still resolves to
  one paint rather than one per mode.
- **The color stays ON the layer.** A layer wearing a style is painted exactly
  as a layer somebody colored by hand, and the binding is the extra fact that
  says where the color came from. So the renderer, export, thumbnails and the
  package writer learn nothing about styles, and a copy of a component keeps
  drawing correctly whatever happens to the shelf.
- **Five colors can wear one**: a box's interior, a box or line's ink, a text
  block's ink, a frame's surface, and the border a layer's own styling draws
  around it. Each is a `ColorSlot` on the layer, so adding another later is a
  case in two switches.
- **A border's color is a color like the rest.** The Effects section sets how
  THICK a border is; what it is painted lives in the Color section with
  everything else, so it can be set on a whole selection at once and can wear a
  saved color. The Border row turns up only once a border is actually drawn: a
  color nobody can see is a dead control, and the way to a border is its width
  rather than a checkbox on the row. A border pointed at a saved color keeps its
  row while the width sits at zero, so taking a border off for a moment does not
  quietly lose the name.
- **One Color section, whatever is picked.** The mock hangs "Save as style" off
  a Fill section of its own. The app has a Color section that holds every color
  the picked layers have, and the styles button sits on each of its rows. It was
  briefly a section that appeared only over a multi-selection, with a single
  layer's colors living inside its Rectangle, Text or Frame section: that moved
  the color you were editing into a different section the moment you
  shift-clicked a second layer, so the section is now always there and it is the
  only place a color is.
- **A row is named by its slot, not by what is picked**: Outline, Fill, Text,
  Border. A
  label that read "Color" over a lone arrow and "Outline" the moment a box
  joined the selection would move house the same way the section used to.
- **A color that can be absent carries a checkbox**: a box's inside, a frame's
  surface. It speaks for the whole selection, so it is on only when every layer
  that could have that color has one, and one click fills the rest. It is what
  used to be the Fill toggle in a shape's settings and the "No background"
  button in a frame's.
- **Saving asks for the name first, in the dock.** A field opens under the color
  row, on a name nobody is using, with the text selected: naming it is typing
  and Return is enough, Escape leaves nothing behind. The alternative — make a
  style called "Color" and hope the person finds where to rename it — is how a
  shelf fills with "Color 2", "Color 3".
- **A row wearing a style shows its color and its NAME, and the well goes
  away.** A shared color is not edited from one of the places it is used, so the
  only way to change it is to change the style. Unlink is in the same menu and
  says what it does, so the way back to a one-off color is one click and never a
  surprise. (The name took the ROW LABEL's place at first, which is what made a
  rectangle's settings unreadable; see "the shape settings say what they are"
  below.)
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

## Landed: a row wearing a style says so, and still answers (Next, `next-styles`, 2026-09-05)

Reported by the user against the two sections above: a Fill row wearing a style
named Error showed a chip the same size, the same shape and in the same column
as the live wells on Outline and Border, and clicking it did nothing. Two rows
side by side looked identical and only one of them was live.

- **A color from a style is drawn HELD.** The chip sits inside a filled holder
  instead of covering its square, so a linked row and a plain one read
  differently straight down the column without reading the name beside them.
  Same 18pt footprint and the same column, so nothing moves when a row takes a
  style on or lets one go.
- **The chip is a control again.** It opens the same picker every other color
  row opens, because a person who clicks a color wants to change it and a
  control that ignores them is worse than one that asks. Picking a color there
  takes the row off the style — which is what `setColorHex`/`setPaint` have
  always done for a hand-picked color, and what the toolbar swatch has always
  done for a tool holding a saved one.
- **The picker says so before the click, not after.** Its top line reads
  "Using Error" with a palette mark, an Unlink beside it, and one plain
  sentence: a color picked here takes this off the style, or all three of them
  off it when the row speaks for three. `ColorStyleSelection.styleReplacementNote`
  in `PhotonzCore` writes it, so the wording is tested rather than typed into a
  view. Nothing is added UNDER the row: a sentence that is true every time you
  look at the panel is a sentence nobody reads by the third time.
- **Unlink is in three places and means one thing**: the row's menu, the
  picker's banner, and the toolbar swatch's popover. The color stays exactly as
  it is and simply becomes the layer's own.
- **One undo puts a style back on**, color and binding together, because the
  unlink and the paint are the one step they always were.

Deliberately left: no mark on the chip itself. The menu button 6pt to its right
already wears a palette mark beside the style's name, and the same mark twice in
one row says nothing the first one did not.

## Landed: a saved style can be a gradient (Next, `next-styles`, 2026-09-04)

A color could be kept under a name from the day styles landed. A gradient could
not, so the one paint worth keeping most — the ramp somebody spent time aiming —
had to be rebuilt by hand on every shape that wanted it.

- **A style holds a whole `Paint`, not a hex.** The wire key is still
  `colorHex`, and a solid paint writes the same bare string it always wrote, so
  every document already on disk opens unchanged and a document with no ramp in
  it is byte-identical to what the old build wrote.
- **Everywhere a style is drawn, it draws the paint**: the shelf tile, the
  Style section's swatch, and the swatch on a color row wearing it. A shelf of
  flat squares is a shelf you cannot pick a gradient off.
- **Save style in the picker keeps the whole paint.** It used to keep
  `displayHex`, which while a gradient is open is the stop the square is pointed
  at — so saving a sunset kept one orange.
- **A ramp is offered only where a ramp can be drawn.** One blue really is both
  the fill of a button and the color of a link, so an ink style turns up on the
  Text row; a sunset listed there would paint one flat orange. The Style section
  says so in a line under "Use it for" rather than leaving somebody hunting.
- **A binding that already exists stays honest rather than breaking.** A flat-only
  slot wearing a gradient style takes the style's flat color and keeps following
  it, so turning an ink style into a ramp does not silently unlink the text.
- **Reconciliation is paint-deep.** Comparing hexes let a claim stand over a ramp
  nobody saved: move one stop on the layer and the flat color never changes. The
  comparison is `Paint.draws(sameAs:)`, which ignores the ramp a solid is no
  longer using — a paint keeps its stops while it is solid, so `==` would call
  two flat oranges different because one of them used to be a sunset.

Deliberately left: text and borders still take one flat color, so a gradient
cannot be poured into a letter; and the Style section edits the ramp through the
same picker every color row uses rather than a shelf-sized gradient editor.

## Landed: the shape settings say what they are (Next, `next-styles`, 2026-09-03)

Reported by the user against the section above: a picked rectangle showed a
section headed **Annotation**, the word "Rectangle" beside one color and nothing
beside the other, the words "Border" and "Surface" where labels should be, and
every saved color in the document on every color menu. Four separate faults, one
unreadable panel.

- **A section that describes what you picked is named after IT.** "Annotation"
  is the name of a content kind in the model and nothing on screen is called
  one. The header now reads Rectangle, Ellipse, Arrow, Line or Highlight, and
  the Measure section reads Measurement. `AnnotationShape.title` lives in
  `PhotonzCore` (`ShapeSettingsNaming.swift`) so the header and the row labels
  cannot drift apart.
- **Every color says what part it paints, in a column of its own.** A box gets
  Outline and Fill; a line, arrow or highlight is all one color and just says
  Color, because the header already names the shape. The label is a fixed
  column and NEVER moves aside for anything — losing it exactly when a saved
  color was in use was the whole complaint.
- **The name of a saved color wears a palette mark.** The row label says what
  gets painted and the menu button says which saved color is doing the
  painting; without a mark those two read as a pair of labels and neither means
  anything. `ColorPartLayout` holds the columns: label, switch, color, menu.
  The switch column is present even when blank, so a rectangle's Outline
  swatch and its Fill swatch sit at the same left edge.
- **A saved color is offered only where it belongs.** There are two answers, not
  three: **ink** (outlines, lines, text) and **surface** (fills, frame
  backgrounds), which is the split the user described. `ColorStyleRole` on the
  style records it, saving from a row records it automatically, and each row's
  menu is titled "Saved outline colors" and so on, so a shorter list reads as
  scoped rather than as colors having gone missing. A row with no colors for its
  part says the others are for other parts and offers the way to widen one.
- **One color can serve both**, because one blue really is a button's fill and a
  link's ink. The picked style's own section grew a **Use it for** pair of
  checkboxes; unticking the last one does nothing rather than leaving a color no
  row will ever offer. Nothing is repainted by a change here.
- **A color saved before roles existed is never lost.** The document works one
  out: one of the app's own five keeps what the app made it for, anything else
  takes the parts it is already painting, and a color nothing uses stays offered
  everywhere. `effectiveColorStyleRoles` is pure, so nothing has to migrate on
  open, and a style with no roles writes no roles key.
- **Nothing about how a shape paints changed.** Only what the panel reads.

Deliberately left: the Measure section's own color row keeps its narrower label
column, having nothing to line up against.

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

## Landed: the whole scenario, walked end to end (Next, 2026-09-03)

Step E9, the acceptance bar for the epic. No feature in this one: two scripted
walks, an audit, and four follow-up tasks for what the sitting turned up.

- **`Scripts/playtest/component-end-to-end-walk.json`** drives the scenario the
  user named: draw a box, type a word in it, group, ⌥⌘K, name it, expose the
  wording, drop three copies off the shelf, override the middle one, then
  descend into the original and type a new width. It passes in about 19
  seconds and photographs every stage with the real screen capture, not the
  offscreen render. The log carries the proof the pictures cannot: the pill
  after the width edit reads "Updated · 3 copies of Save button", and one undo
  takes the width back off all four.
- **`Scripts/playtest/redline-with-components-walk.json`** is the other half:
  open a capture, measure a size and a gap, drag a component onto that same
  picture, measure again, copy the spec list and copy the image. The numbers
  are identical either side of the drop and the component is not in the spec
  list. The walk that predates all of this, `redline-walk.json`, also still
  passes step for step, which is the stronger statement: nothing about the
  redline flow changed, it was not adapted.
- **`dropComponent` in the playtest harness now reads a picked starter too.**
  It only knew about a component already in the document, so a walk could not
  do the first thing a person does, which is drag a built-in tile straight onto
  the canvas. The real drop path (`placeComponent`) always handled both.
- **A whole-screen capture cannot be scripted**, and this is stated in the
  audit rather than worked around: ⇧⌘4's overlay covers every display and owns
  the pointer. The redline walks open a capture that is already on disk. The
  standalone `--capture-diag` check that does exercise the overlay was run and
  reported the screen locked, which invalidates its own readings.

What the sitting found, each filed as its own task rather than fixed here:

- A number field never hands the keyboard back. After Return in W, a tool key
  types a letter into the number; Escape does not release it either, only a
  click on the picture. This bites in the middle of the scenario, between
  "type the new width" and "reach for Measure".
- A wording knob is named after the words it holds, so an overridden copy reads
  "Save → Cancel". The five starters dodge it by shipping the knob as "Label".
  (Fixed: "a knob is named for what it controls", below.)
- The Library opens below the fold. ⌥⌘K opens the shelf and picks the new
  component, and on a 900 pt window the shelf is off the bottom of the dock.
- Text typed by hand keeps the screenshot contrast halo inside a component, so
  a button label reads smudged. `StarterComponents` already strips it. (Fixed:
  "text inside a component is drawn clean", and again for screens in "text
  typed on a screen is drawn clean", below.)

## Landed: layers line up with each other (Next, `next-align-layers`, 2026-09-03)

Arranging by hand got the two halves of real help it was missing. Asked and
answered as a decision card first ("both", 2026-09-03), because guides while
dragging had been built once before and turned down; the card's own advice was
to build the commands first and the guides after, and that is the order this
landed in.

**Align and space, on a selection.** Two or more layers picked and an
**Arrange** section appears at the top of the inspector, above Position & Size:
six buttons that line the selection's left edges, centres, right edges, tops,
middles or bottoms up, and two that space it out evenly across or down. The
same rows are in the Layer menu under **Align** and **Space Evenly**.

- **Align lines the selection up with itself**, never with the picture: the
  reference is the box the whole selection occupies, so the layer already on
  that edge does not move. One layer has nothing to line up with, so the
  section is absent and the menu rows are dim.
- **Space evenly means equal gaps, not equal centres.** The outermost two hold
  still and everything between them slides, so pressing it tidies the inside of
  a row without moving the row. It needs three layers; with two the buttons are
  dimmed and say why on hover.
- Positions land on whole points, and every command is **one undo step** for
  the whole selection. A command that would change nothing costs no step.
- A layer inside a selected group takes no part of its own: the group carries
  it.
- Locked layers never move, which is what keeps a screenshot underneath still
  while the boxes on top of it are tidied.

**Guides while you drag.** A dragged layer now sticks to the edges and centres
of the other layers as well as the picture's, sits flush against them, and
shows a thin line saying what it just lined up with. Holding **⌘** drags free,
the same key that already frees a measure foot or a region corner.

- The line reaches only across the boxes it joins, with a little overhang, so a
  crowded canvas does not fill with full-height rules. A line to the picture's
  own edge or middle still spans the whole picture, because that is what it
  lines up with.
- Deliberately not offered: a box whose middle happens to sit on another box's
  edge. That is a coincidence, not a relationship anyone was aiming for.
- Hidden layers never attract (you cannot see what you stuck to), and neither
  does the group you are inside, whose box would chase you as you move.
- The peers are gathered once at mouse-down, since nothing but the dragged
  layer moves during a drag.

**Keys.** Photoshop binds none of these commands, so they take the design-tool
set: ⌥A ⌥H ⌥D for left, centre, right; ⌥W ⌥V ⌥S for top, middle, bottom; ⌃⌥H
and ⌃⌥V for spacing.

**Where it lives.** `LayerArrangement` (align and space maths) and `Snapping`
(peer candidates, guide spans, `snapPeers`) in `PhotonzCore`, both tested;
`ArrangeInspector.swift` and `EditorState.alignSelection` /
`distributeSelection` in the app; the drag itself in `CanvasView`. Walked by
`Scripts/playtest/align-layers-walk.json`.

Not in this slice: shift-clicking a second layer on the canvas to add it to the
selection (a rubber band around them, or shift-clicking rows in the layers
list, is the way in today) and equal-gap badges while dragging. Aligning one
layer to the frame it sits in landed next, below.

## Landed: one layer lines up inside its screen (Next, `next-align-layers`, 2026-09-03)

Align needed two layers, because a layer picked on its own had nothing to line
up with. A layer sitting **on a screen** does have something: the screen. So
one box on a screen now gets the Arrange row with its six align buttons live,
and one press puts it in the middle.

- **The reference is the screen the layer is directly on**, so Align Center
  means the middle of the screen and Align Right means the screen's right
  edge. The layer already there does not move, and each press is one undo step.
- **A plain group is not a reference.** A group's box is the union of what is
  inside it, so a group of one would hand back the layer's own box and leave
  six buttons that do nothing.
- **The search does not climb past a group.** A word inside a button on a
  screen answers to nobody, rather than flying to the middle of the screen and
  out of the button it belongs to. Pick the button and it lines up on the
  screen; how the word sits inside the button is what Layout is for.
- **Two or more layers still line up with each other**, on a screen or off it.
  One thing picked answers to what holds it, several answer to each other,
  which is what every other interface tool does.
- **The row says what it is lining up against.** The caption reads "This layer
  lines up inside Card" and every button's tip reads "Align Center in Card",
  because six live buttons with only one layer on screen would otherwise be a
  guess about what is about to move where.
- **Centring here is the same sum as centring under Layout** (`LayerScaling.span`),
  unrounded, down to the half point. If the two disagreed, centring a label and
  then dragging the card wider would nudge it sideways.

**Where it lives.** `LayerArrangement.aligned(_:to:within:)` takes an optional
container box and `canAlign(count:hasContainer:)` drops to one layer when there
is one, both tested; `EditorState.arrangeReference` finds the parent screen,
and `ArrangeInspector` carries the wording. Walked by
`Scripts/playtest/align-in-frame-walk.json`.

Not in this slice: spacing evenly against a screen's inner edges, and making an
align press also write a lasting Layout rule. Lining a piece up inside the plain
group it sits in landed next, below.

## Landed: a piece lines up inside the group that holds it (Next, `next-align-layers`, 2026-09-03)

Align answered to a screen, which is the size it was given. It said nothing
about the case people hit most while building UI: a word sitting on a button.
Pick the word now and the Arrange row is there, with the button as the thing it
lines up inside, so one press centres it.

- **The box a piece lines up inside a group is everything ELSE in the group.**
  For a word on a button that is the button's background, which is the answer
  anyone would expect. Taking the group's own box instead would mean lining a
  piece up against a box that piece helps define: a word hanging over the
  button's edge would centre itself, shrink the group under its own feet and be
  off centre again. Leaving the piece out keeps the reference still, so one
  press lands it and a second press does nothing.
- **A group of one offers nothing**, because there is nothing else in it to line
  its only child up inside. The row is absent rather than six dead buttons.
- **An axis with no room dims**, and says why. A word already as wide as the rest
  of its group cannot go left, centre or right, so those three grey out and the
  caption reads "It is already as wide as the group, so only up and down can
  move it." The other three stay live.
- **The group never resizes under the piece.** A piece already inside its group
  stays inside it after any of the six presses, so the group's box is exactly
  what it was. The one exception is honest: a piece that was hanging OUTSIDE the
  group comes inside, and the group tightens to the rest of its contents, which
  is the point of pressing the button.
- **A stack or a grid offers nothing.** A container that arranges its own
  contents puts them back after every edit, so an align press inside one would
  be undone before you saw it. Where those pieces sit is what the Layout section
  is for. That now holds for a screen that arranges itself too, which used to
  offer six buttons that did nothing.
- **The search still never climbs.** A word inside a button inside a screen
  answers to the button. Pick the button and it answers to the screen.

**Where it lives.** `ArrangeContainer` and `PhotonzDocument.arrangeContainer(of:)`
in PhotonzCore carry the whole rule, tested in `ArrangeContainerTests`;
`EditorState.arrangeReference` reads it and gates each kind of holder on its own
flag (`next-frames` for screens, `next-layer-groups` for groups);
`ArrangeInspector` and the Layer ▸ Align menu dim per axis. Walked by
`Scripts/playtest/align-in-group-walk.json`.

Not in this slice: making an align press write a lasting Layout rule, and
spacing several pieces evenly inside the group that holds them.

## Landed: a screen is renamed by clicking its name (Next, `next-frames`, 2026-09-03)

The name above a frame's top left corner used to be a caption: the only way to
change it was to find the frame's row in the Layers list and double click
there. It is now the frame's handle.

- **Click the name, pick the screen. Double click it, type a new one.** The
  field opens exactly where the name is drawn, with the whole name selected, so
  renaming a screen is a double click and a word. Return lands it as ONE undo
  step, Escape leaves the frame as it was, and a click anywhere else lands it
  the way a rename field does everywhere on the Mac. An empty name is no name:
  the frame keeps the one it had.
- **The letters are the target, not the box.** The name draws in a box up to
  240 points wide whatever the name is, and a click on the empty part of that
  box still means what it always meant on bare canvas — including the double
  click that zooms the window. Only the letters plus a few points of slop
  answer, which is `CanvasNameLabels` in `PhotonzCore` (tested): it owns where
  the name draws, what answers a click, and which name wins where two overlap
  at a zoomed-out size.
- **Hovering a name tints it to the accent.** Nothing else says a caption can
  be clicked, and this is the whole invitation. A selected screen's name is
  already tinted, so hover and selection read as one state: this name is live.
- **⇧-click on a name adds that screen to the selection**, the same gesture
  ⇧-click on the picture runs, so picking two screens to align is two clicks on
  their names.
- **Only the Select tool.** With a drawing tool in hand that strip is still
  canvas you can draw on. A locked frame's name answers nothing, the same way
  its picture does not.
- **One name in one place.** The canvas name and the Layers row are the same
  layer name through `renameLayer`, so they cannot disagree.

**Where it lives.** `CanvasNameLabels` and `CanvasNameLabel` in `PhotonzCore`
(geometry and hit testing, tested); `CanvasFrames.swift` in the app (the frame
chrome) and `CanvasNames.swift` (the hover tint, the field, the rename); the
press itself in `CanvasView.mouseDown`.
The field is an `NSTextView` rather than an `NSTextField` on purpose: a text
field borrows the window's field editor and AppKit takes it back the moment the
window is not key, which is every moment of an unmanned playtest, so the rename
could be neither driven nor photographed. Walked by
`Scripts/playtest/frame-name-rename-walk.json`.

Not in this slice: renaming any other layer by clicking it on the canvas — only
screens and components wear a name there. A component's name in that same spot
landed next, below.

## Landed: a component is renamed by clicking its name (Next, `next-components`, 2026-09-03)

A screen promoted to a component swaps its grey name for the component's name
in violet, behind the four-diamond mark. That name used to be a caption and
nothing else: clicking it did nothing, and the only way to change it was the
Component section in the dock. **A screen's name and a component's name are now
the same handle.**

- **Click the chip, pick the component. Double click it, type a new one.** The
  field opens exactly where the name is drawn, with the whole name selected.
  Return lands it as one undo step, Escape leaves it as it was, an empty name
  keeps the old one. Identical to a screen in every way a person can feel.
- **The mark is part of the chip, not a hole in it.** "◆ Card" reads as one
  small label, so the whole thing answers a click. A click that lands on the
  diamond and quietly does nothing is the kind of miss nobody forgives.
- **Violet at rest, the accent when live.** The name tints to the accent on
  hover and while the component is selected, exactly as a screen's does. It can
  afford to: the diamond in front of it goes on saying "component", so the name
  is free to say "live". The field that opens over it is outlined in the violet
  rather than the accent, so you can still see what kind of thing you are
  naming while you type it.
- **The rename is a COMPONENT rename**, not a layer rename, so the canvas, the
  Layers row, the Library tile and the Component section all move together.
  They read one name from one place, so they cannot disagree.
- Copies still wear the single diamond and no name. A screen built from twelve
  buttons would otherwise carry twelve labels, and a copy's name is already in
  the Layers list and the dock.

**Where it lives.** The behaviour is shared with screens and lives in
`CanvasNames.swift`; `CanvasComponents.swift` draws the mark and the violet
name; `CanvasNameLabels.leadingInset` (PhotonzCore, tested) is the few points
the mark takes at the left. The commit routes through `renameComponent` rather
than `renameLayer`. Walked by
`Scripts/playtest/component-name-rename-walk.json`.

Not in this slice: renaming a COPY by clicking it on the canvas (a copy has no
name there to click), and renaming a component from the Library tile itself.

## Landed: a copy follows the original's look (Next, `next-components`, 2026-09-03)

C5 kept a copy's CONTENTS equal to the original's and left its own fade, blur,
rounded corners, border and shadow alone, because writing the original's look
over a copy would snap an Effects slider back the moment it was let go. So
moving a piece inside a component reached every copy and rounding the component
itself reached none of them, which is a distinction nobody drawing a button
would think to make. The look follows now.

- **It follows part by part.** Fade one copy and it keeps that fade; give the
  original a shadow afterwards and the faded copy takes the shadow anyway. The
  alternative, where the first slider you touch takes the whole look off the
  original for good, is how a copy quietly stops being a copy.
- **The parts are the controls**: opacity, blur, corner radius, border width,
  border colour, shadow, blending. **A shadow is one part**, not six: its
  softness, size, distance, direction, opacity and colour are six controls for
  the one thing a person means by "the shadow".
- **Nothing has to announce that it styled a copy.** A copy remembers the
  original's look as of the last time the two were put in step
  (`GroupContent.followedStyle`), and anything its own look differs from that
  by is a part somebody set on it. The styling paths are many — sliders,
  steppers, colour wells, and whatever arrives next — and a model that needed
  each one to raise a flag is a model where the one that forgets snaps a
  person's work back.
- **It says so where you did it.** A revert arrow appears on the Effects or
  Shadow row itself, beside the label, exactly as it does on a knob's row. The
  copy's own section also grows an **Its own look** line naming the parts, with
  one way back to the whole of the original's look, because Effects is a
  different section and may be collapsed or scrolled away: without it, a copy
  you faded last week is a copy that mysteriously ignores the original.
- **The notice counts a look change like a change to the contents.** Rounding
  an original says "Updated, 2 copies of Setting"; fading it when one copy
  keeps its own fade says one copy, because that is how far the edit reached.
  Styling a copy itself announces nothing, the same rule setting a knob follows:
  the pill reports what moved out of sight.
- **A copy nested inside another component follows its own original's look**,
  resolved in the same pass, so which copy the sync reaches first never decides
  the answer.
- **A document saved before this opens looking exactly as it did.** A copy with
  no memory adopts the original's current look as its memory and repaints
  nothing, so anything it already differed by becomes its own. A copy that was
  meant to follow is one click on the way back from doing so.
- On disk only a copy writes the key, so a document saved before this step is
  byte for byte what it was.

Deliberately left: the original's section does not say which of its copies have
looks of their own, so finding the odd one out means clicking through them; the
shadow's way back sits on its Enable row rather than on the control you touched,
which is the price of treating a shadow as one thing; and a copy's size, place,
name and whether it is hidden are still its own, which is what lets copies sit
in different spots at all.

Walked end to end by `Scripts/playtest/component-look-walk.json`.

## Landed: a knob can be a number (Next, `next-components`, 2026-09-06)

The fifth kind of knob, and the last one the first version left out. A copy could
be given its own wording, its own visible pieces, its own shape and its own
colour, but not its own number: a card original could not produce a round copy
and a square one, or a roomy one and a tight one.

- **Four numbers, not every number.** A layer carries dozens (where it sits, how
  big it is, how faded, how far its shadow falls) and offering all of them would
  rebuild the twenty-four row Add menu that grouping the menu by kind exists to
  stop. The four are **Corner radius**, **Thickness**, **Gap** and **Padding**,
  and every one of them is a number a person already types into the inspector
  for an ordinary layer.
- **Those four because the others are already the copy's.** Where a copy sits
  and how big it is have always been its own; its fade, blur, rounding, border
  and shadow have been its own part by part since C5's look-following. These
  four sit on a layer INSIDE the original, which is the one place a copy has no
  other way to reach.
- **A number knob names WHICH number**, exactly as a colour knob names which
  colour: one box has both a rounding and a thickness, so a knob called "Box"
  would say nothing. It arrives named "Corner radius", and exposing one leaves
  the other on offer.
- **A layer is only offered the numbers it HAS.** A label has no corners to
  round and no line round it, so it offers none; a group that arranges nothing
  has no gap; and a group whose four sides of room disagree has no ONE number to
  show, so it is not offered room at all rather than offered a field that would
  print a number the group does not have.
- **Rounding writes whichever number actually rounds.** A rectangle curves the
  outline it draws and everything else has its corners masked off; the knob
  reads and writes the one that is really rounding that layer and puts the other
  to nought. It is the same one step the canvas's Corner Radius row takes
  (`ComponentNumberKnob.swift`), so the two can never disagree.
- **The field is the same field.** A knob's number field is the control the Gap
  and Padding rows on the canvas are, so the arrow keys stepping it, Return
  landing it and handing the keyboard back to the picture, the rounding, and the
  word Mixed over several copies are all decided in one place.

Deliberately left: a knob still cannot reach the original's OWN root, so a card
whose room inside sits on the component's outermost group cannot hand that room
to its copies yet (its rounding it already can, through the look-following). Room
that differs side to side cannot be a knob. And a copy's panel can show a knob
called "Corner radius" above the Effects section's own "Corner Radius" slider,
which round different things; renaming the knob is one field away.

## Landed: a knob is named for what it controls (Next, `next-components`, 2026-09-03)

The E9 sitting's second finding. A wording knob took the words of the layer it
exposed, so a button that said "Save" got a knob called "Save"; the first copy
to answer "Cancel" left a panel reading Save above Cancel, which reads as a bug
in the app rather than as a copy doing its job.

- **One naming rule for every kind now.** A knob takes the name of the layer it
  exposes, unless that name is one the APP wrote rather than a person ("Group",
  "Group 2", "Text", "Text 2"), in which case it takes what the knob does:
  "Wording", "Show", "Shape". `ComponentNaming.isPlaceholderLayerName` is the
  one place that judgement lives, and `defaultPropertyName` is now two lines.
  Show-or-hide on an unnamed text layer used to land as "Text · show", which
  said nothing either, and is caught by the same rule.
- **The words moved to the Add menu**, which is the one place they help: two
  unnamed text layers are two rows both reading "Text", so a row now reads
  Text “Save”. Read once while choosing, never kept as a name. Clipped at 24
  characters so a paragraph does not become a menu row.
- **A new knob lands with its name selected**, the New Folder idiom the
  component's own Name field already follows. "Wording" is honest but says
  nothing about WHICH wording, so the author types "Label" while they are still
  thinking about it, and ignoring the field leaves a name that is at least never
  wrong. `EditorState.componentPropertyAwaitingName` hands the focus over.
- **Nothing is renamed in documents that already exist.** The rule only decides
  the name a knob is BORN with, so a knob somebody has called "Save" stays
  "Save", saves, opens and renames exactly as before.
- The five starters were never affected: their text layers are named ("Label",
  "Title", "Body"), so their knobs always borrowed a real name.

Deliberately left: a component with two unnamed text layers still gets "Wording"
and "Wording 2" if the author skips both name fields, and nothing suggests a
better name from where the layer sits. Naming the layers, or the knobs, is the
answer, and both are one field away.

## Landed: text inside a component is drawn clean (Next, `next-components`, 2026-09-03)

The E9 sitting's third finding. Every text layer is born wearing a soft contrast
halo so a caption stays readable over a screenshot. Inside a component that halo
reads as a printing error: the word "Save" on a button you drew looked smudged,
on the original and on every copy, while the app's own five starters looked
crisp beside them.

- **The rule is per component, not per group.** Bundling an arrow with its
  caption is the everyday redline move, and that caption still needs its halo,
  so grouping cannot be the trigger. Promoting to a component is a statement
  that what is inside is a piece of UI, and a label on a control is not a
  caption over a screenshot. Copies count too: a copy is a group carrying
  `instanceOf`, so `Layer.isComponentRoot` covers the original and the copies.
- **It is read at draw time and erases nothing.** `Layer.drawnShadow(onDesignedSurface:)`
  is the whole rule, and `DocumentRenderer` carries an `onDesignedSurface` flag
  down the tree. Make Component never edits your text, so taking it back out draws the
  halo again with no undo history and no re-derived values. Nothing bakes into
  pixels.
- **A shadow somebody chose still draws.** Only the automatic halo steps aside,
  matched by value against `TextBuilder.autoContrastShadow` for the text's own
  color, so a title on a card can still cast a real shadow inside a component.
- **The Shadow switch tells the truth.** With a label inside a component picked,
  Enable Shadow reads off, because off is what is drawn; turning it on gives that
  label a real shadow. Drag previews and layers-list thumbnails follow the same
  rule, so a label never sprouts a halo in a thumbnail the canvas does not show.
- Nothing in Current changes: components only exist in Next.

Deliberately left: a halo somebody had already tuned by hand before promoting
keeps drawing inside the component, because by then it is a shadow they chose.
Text typed straight onto a screen was left out of this slice and picked up by
"text typed on a screen is drawn clean" below.

Walked by `Scripts/playtest/component-text-halo-walk.json`.

## Landed: dragging one out of the Library (Next, `next-components`, 2026-09-03)

Every Library tile carried an `.onDrag` and the canvas had a drag destination
ready for it, and yet dragging a component onto the canvas did nothing at all.
People fell back to double clicking a tile, which places one in the middle
rather than where they wanted it.

**The cause was a type identifier the system had never heard of.** A component
travels under its own pasteboard type, `com.photonz.component-id`, so a dropped
file and a dropped component can never be mistaken for each other. That type was
never DECLARED in the app's `Info.plist`. An undeclared identifier is not
rejected: the drag pasteboard accepts the type name and then carries ZERO BYTES
behind it, so the canvas saw a component arrive, read nothing out of it, and
refused the drop. Everything else about the plumbing was correct. The layers
list drags fine because it travels as plain text, which every Mac already knows.

- **`Scripts/build-app.sh` declares the type, in every variant including the
  probe**, conforming to `public.item` rather than `public.data` so a component
  claims no files and offers the Finder no file promise. The build FAILS if the
  finished `Info.plist` does not carry it, because the only symptom of losing it
  again is a feature that quietly stops working.
- **A picture of the component follows the pointer.** `onDrag(preview:)` on both
  the component tiles and the media tiles, so picking a tile up looks like
  picking anything up on a Mac.
- **The canvas says where it will land, before the button comes up.** A filled
  accent box the exact size of the copy, centred where the pointer is; over a
  screen, a dashed accent box around that whole screen as well, drawn just
  outside it so a component the size of the screen cannot hide the very cue that
  says it is joining one. A drop that would be refused (a copy landing inside
  its own original) answers with the ordinary no-entry pointer instead of
  accepting the drag and scolding afterwards.
- **One answer decides both the picture and the drop.**
  `PhotonzDocument.componentDropTarget(of:at:)` and `componentDropSize(of:)` in
  `PhotonzCore` (tested) are read by the canvas mid-drag and by the placing
  itself, so what was promised and what happens can never disagree.
- **Nothing in an `onDrag` closure touches app state any more.** A change made
  while the drag is being handed over redraws the tile and SwiftUI asks for the
  item all over again, which was producing two drags for one press.

**Where it lives.** `ComponentInstances.swift` in `PhotonzCore` (the two
answers); `ComponentPanel.swift` and `LibraryPanel.swift` (the tiles and their
previews); `CanvasView.swift` (`trackComponentDrag`, `refreshComponentLanding`);
`Scripts/build-app.sh` (the declaration and the guard). Walked by
`Scripts/playtest/library-drag-walk.json`, which uses the `dragComponent` step
to hold a component in the air and photograph what the canvas draws.

Not in this slice: style tiles, which do not drag at all — a named color has
nothing to land on, it paints what is already selected.

## Landed: text typed on a screen is drawn clean (Next, `next-frames`, 2026-09-03)

The halo rule, widened one level up. Text inside a component was already drawn
without the automatic contrast halo; a heading typed straight onto a screen you
are designing still wore it, and on any surface that is not white it read as a
smudge behind the words.

- **The trigger is a painted surface, not a frame.** A frame counts when it
  paints a background, which is what a screen made with the frame tool does.
  Frame Selection deliberately paints nothing — it draws a boundary around work
  that already exists — so a caption on a screenshot somebody wrapped in a
  frame keeps its halo, which is the whole reason the halo exists. Making the
  trigger "is a frame" would have taken the halo off exactly the captions that
  need it.
- **One predicate, one flag.** `Layer.paintsSurface` (a frame with a
  `backgroundHex`) joins `isComponentRoot` in `Layer.startsDesignedSurface`, and
  `PhotonzDocument.isOnDesignedSurface(_:)` answers for a layer anywhere in the
  tree. The renderer's flag and `Layer.drawnShadow(…)` were renamed from
  `insideComponent` to `onDesignedSurface` so the name still tells the truth.
- **Plain groups in between change nothing.** A group moves no pixels, so text
  in a row inside a screen is still on that screen.
- **Still read at draw time, still erases nothing.** Dragging text onto a screen
  drops the halo, dragging it back off puts it back, and clearing a screen's
  surface puts it back too, with no undo history and no baked pixels. A shadow
  somebody chose still draws, and the Shadow switch keeps reading what is
  actually drawn.

**Where it lives.** `Components.swift` in `PhotonzCore`;
`DocumentRenderer.swift`; `LayersPanel.swift` (the Shadow switch). Tested in
`TextHaloTests` and `TextHaloRenderTests`. Walked by
`Scripts/playtest/screen-text-halo-walk.json`, which paints a screen a strong
colour first — on a white screen a white halo behind dark text cannot be seen
at all, which is why the complaint only bites once a screen has a surface.

Deliberately left: a screenshot placed inside a painted screen with a caption
laid over it loses that caption's halo, because the rule reads the container,
not what is under each word. Turning the Shadow switch on gives that caption a
real shadow, which is the way back.

## Landed: when a link breaks, the app says so (Next, `next-components` and `next-styles`, 2026-09-03)

Four things follow something else, and all four could stop following without a
word: a color painted over stopped being the style it claimed, a slider dragged
on a copy took that part off the original, ungrouping a copy turned it into
loose layers, and deleting an original left its copies drawing what they always
drew. Each one is invisible at the moment it happens. You find out later, when
an edit to the original stops arriving and something on the canvas is left
behind. Now all four say so, in the same words, in the same place, while
Command Z is still one press away.

- **One sentence, four shapes.** The canvas pill says **Stopped following** and
  one line under it: "1 color no longer follows Accent", "Opacity on this copy
  no longer follows Setting", "The pieces of this copy no longer follow
  Setting", "2 copies no longer follow Setting". One frame, so the second time
  you see it you already know what it is telling you.
- **Found by looking, not by being told.** A break is a fact about the
  difference between the document before an edit and after it, so it is worked
  out in one place (`LinkBreakReport.between`, run from `History.perform`)
  rather than announced by four commands. Every route in gets it right —
  a menu item, a key, a walk in the playtest harness, a command written next
  year — and no command has to remember it exists.
- **An edit that breaks nothing says nothing.** Editing an original, moving a
  copy, putting a part back on the original, and picking a different style for
  a slot are all silent. Dragging one slider says it once, on the frame the
  part let go, not on every frame of the drag.
- **What you asked for is not a break.** Unlink takes a color off its style on
  purpose and Remove Style means those colors are their own now; saying so
  afterwards is the app repeating your own command back at you. Detach already
  has its own word. None of those raise this.
- **What is inside a copy belongs to the original.** A color inside an original
  that four copies follow counts once, in the original, rather than once per
  copy.
- **It stays up longer than a Copied notice** (3 seconds against 1.6): it is a
  whole sentence naming two things, and it is the only one of these pills you
  might want to act on. **Undo takes it off screen**, because a notice saying a
  link broke a second after undo put it back is a lie.

Deliberately left: deleting an original still says it as it happens rather than
asking first, because that puts a modal on the Delete key for something one
undo away; and the pill names what broke but does not offer a way to it, so a
copy stranded off screen is still found by hand.

Walked end to end by `Scripts/playtest/link-break-walk.json`.

## Landed: a group can arrange its own contents (Next, `next-auto-layout`, 2026-09-03)

Asked for by the user while answering the alignment decision: as well as lining
layers up by hand, a component should be able to hold a **grid** or a **stack**,
so the things inside it space and re-flow themselves.

**One control, three words.** Pick a group and the Layout section opens with an
**Arrangement** row: **Free**, **Stack**, **Grid**.

- **Free** is every group this app has ever made: things stay where you put
  them.
- **Stack** lays them along one axis with an even **Gap**, and a **Direction**
  of Row or Column.
- **Grid** fills rows of equal cells, with **Columns**, a **Column gap** and a
  **Row gap**.
- **Padding** is the space kept clear inside the edges, on a screen and on a
  group alike (see the sizing section below: a group that arranges itself has
  edges of its own).

Every number is typed, never dragged for, with the same keys as the other
number fields (Return lands it, Escape puts it back, up and down step by 1 and
Shift by 10).

**Turning what you already arranged into a stack moves nothing.** The direction
and the gap are READ off where the contents already are, so a row you spaced by
eye at 16 points becomes a row with a gap of 16 and not one thing shifts. Where
the spacing was uneven the average wins, which is the tidy-up you were about to
do by hand. The group's own anchor moves with its contents, so nothing on the
canvas jumps at the moment you press it.

**The gap is the space you can see.** A gap of 8 puts 8 points between two
shapes, and it puts 8 points between two lines of type as well. That is not
free: the box around a piece of text is measured a few points bigger than its
words, so that antialiased edges never clip, and a flow that counted that room
put 12 points on screen where the field said 8. The stack and the grid flow by
the words instead, and hand each text box its spare room back on the far side
where it sits inside the gap and nobody can see it. The same rule centres a
label on its words rather than on its box, stretches it so the words reach the
padding rather than stopping short of it, and reads a hand-spaced column back as
the gap you would have measured with a ruler.

**A text layer's box is its words.** The same spare room used to be visible in
every number a person reads off a label: the blue box hugged it at the top left
and floated four points clear at the bottom right, W said 104 where the words
were 100 wide, and a label dragged next to something lined itself up by an edge
that is not drawn. So the box a person sees is now the box every surface
speaks. The selection outline and its eight handles, the rotate knob, the W and
H fields, the magnets a drag lines itself up with, the band you sweep round
something and the Arrange row all read the words; the canvas and the panel put
the room back at the one door each of them commits through, so nothing about
how the words are drawn changes and no saved document moves. `Layer.withoutSlack`
and `Layer.withSlack` are the pair, `Layer.contentBounds` and
`PhotonzDocument.canvasContentBounds` are the boxes built on them, and
`LayerGeometrySelection.Member.slack` carries the room through a typed number.
The floor a text box stops at is stated on the words as well
(`TextMeasurement.minimumContentWidth`, 80), because 80 is the number the field
says out loud. Tested in `TextBoxIsItsWordsTests`, walked by
`Scripts/playtest/words-box-walk.json`, `words-gap-walk.json` and
`words-drag-walk.json`.

**The flow owns one axis; the placement rules own the other.** A column stack
decides every Y, and whether a row sits Left, Centre, Right or Stretch across is
the same Horizontal menu that was already in this section, which any one layer
can still answer differently for itself. A grid decides the cells, and the two
menus say where each thing sits inside its cell. The axis the flow owns says
"Set by the stack" rather than offering a menu that changes nothing, and
**Scale** disappears from the choices, because a container that places its
contents never magnifies them.

**Everything re-flows, and nobody had to be told.** The flow runs inside
`History.perform`, so adding a layer, deleting one, pasting one, hiding one or
undoing all put the contents back in order without any command knowing stacks
exist — and each of them stays exactly one undo step. Hiding a row closes the
space it held. **Dragging a row past its neighbour reorders the stack** rather
than snapping it back, because order comes from where things are, not from the
order they were drawn in. Since the stack decides where its contents sit, X and
Y in Position & Size stop taking typing for a layer inside one and say who owns
them on hover.

**Inside a component it works the way you would hope.** Make the stack a
component, drop a copy, add a row to the original, and the copy grows the same
row in the same place, in one step.

**Menus and keys.** Layer ▸ **Stack Selection** (⌃⌘G) and **Grid Selection**,
right under Group: several layers picked become one group that arranges them,
and a group already picked simply starts arranging itself. Stacking is one
modifier off grouping, and Photoshop binds neither the command nor the key.
Grid Selection takes no key.

**Cut from the mock on purpose** (`ui-autolayout` draws eight controls):

- **Distribute** (packed / centre / between / around). Three of its four
  options only mean anything in a container BIGGER than its contents, and a
  plain group is exactly as big as its contents.
- **Per-child hug / fill / fixed.** It would be a second control saying what
  the Horizontal and Vertical rows right below already say. The stack reuses
  those instead.
- The `ui-grid` mock's "layout grid" is a different thing again: a column
  overlay you eyeball against, not a container that positions what it holds.
  The ask was for a container, so that is what this is.

**Where it lives.** `GroupLayout` (the model and reading a layout off an
existing arrangement), `GroupFlow` (the maths) and `GroupLayoutEditing`
(`setGroupLayout`, `stackSelection`, `reflowLayouts`) in `PhotonzCore`, all
tested; `GroupContent.layout` is optional and writes no key when unset, so every
document saved before this decodes and draws unchanged.
`ArrangementInspector.swift` and `EditorState.setArrangement` /
`updateArrangement` / `stackSelection` in the app. Walked by
`Scripts/playtest/stack-and-grid-walk.json`.

Not in this slice: wrapping as a fourth direction and binding gaps to spacing
tokens. Per-side padding landed on 2026-09-04, below.

## Landed: a stack can be a size of its own (Next, `next-auto-layout`, 2026-09-03)

A stack used to be exactly as big as whatever was in it, so "this menu is 320
wide and every row fills it" could only be built on a screen. Now a group that
arranges itself can be told how big it is, one axis at a time.

**Two rows, Hug or Fixed.** Under the gaps, a group that arranges itself gains
**Width** and **Height**, each **Hug** or **Fixed**. Hug is what a stack has
always been: as big as its contents plus its padding. Fixed holds a number of
its own. Pressing Fixed starts from the size the group is at that moment, so
nothing moves when you press it. A screen keeps no such rows: a screen's box is
the box you made it.

**The number is W and H, not a fourth field.** The size itself is typed in
Position & Size, the same two boxes every other layer's size is typed in, and
dragging the group's handles sets it too. Typing one of them pins only that
side, so a menu can be 320 wide and still exactly as tall as its rows. Doing
either flips the row below to Fixed, which is how the two rows teach what they
mean.

**Being wide is not the same as filling.** A stack told it is 320 wide does not
widen its rows on its own: the Horizontal row still owns that axis, and setting
it to **Stretch** is what makes every row fill the 320. The section's caption
says so in words when a size is set, so nobody is left staring at a wide stack
of narrow rows. This is deliberate — one axis, one owner — and it is why there
is still no per-child hug/fill/fixed control.

**A resize sizes it, it never magnifies it.** Dragging a handle on a stack used
to scale everything inside it, and then the flow re-laid it out with the
original gap, so the result matched nothing. Now the drag hands the stack a box
and the flow fills it: the type stays the size it was. The same rule carries
down, so a stack set to stretch inside a screen takes the screen's width and
passes it on to its own rows.

**Where it lives.** `GroupLayout.width` / `.height` (nil means hug, and writes
no key, so every document saved before this is byte for byte what it was),
`Layer.localBounds` for the box a group with a layout makes, `GroupFlow.Bounds`
for the per-axis room the flow shares out, and `LayerScaling.rearranging` for a
resize that sizes rather than scales. `ArrangementInspector` holds the two rows.

Not in this slice: a minimum or maximum size, and a stack that spreads its
contents along the axis it flows on (distribution) when it is longer than they
are. Per-side padding landed on 2026-09-04, below.

## Landed: room on each of a stack's four sides (Next, `next-auto-layout`, 2026-09-04)

Padding was one number, so a card whose contents sit 16 in from the left, 12
down from the top and 24 up from the bottom could not be built: the only way to
get uneven room was to nudge a piece, which the stack then put back. Now the
room is four numbers, and one of them can still be typed once.

**One field, and a chevron beside it.** The Layout section still shows a single
**Padding** field, because the same room all round is what most things want:
type 16 and every side gets 16. The chevron next to the word opens **Top**,
**Right**, **Bottom** and **Left** underneath it, indented, each its own typed
number with the same keys as every other. Clockwise from the top, the order
anybody who has written a CSS shorthand already carries.

**Uneven room shows itself.** Arrive at a stack whose sides differ and the four
are already open, because the single field has no honest number to put in that
case: it goes empty and reads **Mixed**, with the four numbers in its tooltip,
and typing one number there evens them all out again. Closing the four by hand
is allowed and remembered until the selection moves on.

**The box grows to hold it.** A stack that is as big as its contents adds the
near edge's room where the contents start and the far edge's to the size, so
24 at the bottom makes the stack 8 taller than 16 did and nothing inside it
moves. A stack with a size of its own hands its rows what is left between its
sides instead, so a 320-wide stack with 16 left and 8 right stretches its rows
to 296. A grid does the same with its cells.

**Reading it off a screen.** Turning a screen's contents into a stack reads the
left and top margins the contents already sit at and mirrors them onto the
right and bottom. Only the near edges are real: the space below the last row is
just the rest of the screen, and reading that as room would leave a stack
claiming three hundred points of bottom padding.

**Where it lives.** `GroupPadding` in `PhotonzCore` (four sides, floored at
nought, and Codable as a single number for as long as they agree, so every
document written before this is byte for byte what it was),
`GroupLayout.padding`, `GroupFlow.stacked` / `.gridded` for the flow and
`Layer.localBounds` for the box. `ArrangementInspector` holds the field, the
chevron and the four rows. Tested in `GroupPaddingTests`, walked by
`Scripts/playtest/stack-padding-walk.json`.

Not in this slice: a paddings-are-tokens link to a spacing scale, and dragging
the room out on the canvas rather than typing it.

## Landed: a container closes around its contents (Next, `next-auto-layout`, 2026-09-04)

Give a button a longer label and the button stayed the width it was, so the
words hung out of the pill on both sides. Being as big as what is inside you
was something only a stack could do, and a button is not a stack: it is a word
with a fill behind it. Now every group can close around its contents, and the
fill behind them follows.

**Every group takes a size and room at its edges.** The Layout section's
**Width** and **Height** rows (Hug or Fixed) and its **Padding** field are no
longer a stack's alone: a group set to **Free** has them too. Free still means
what it always meant — things stay where you put them — and Hug adds the one
thing it was missing: the box is as big as the pieces plus the room at the
edges, so wording that grows makes the container grow. A group nobody has
touched shows Hug with the room its contents already have, so arriving at a
plain group and arriving at one somebody set up read the same, and pressing
nothing changes nothing.

**Stretch inside a hugging container means surface.** This is the rule the
whole thing rests on. A container that hugs has no spare room to share out, so
a piece told to Stretch inside one cannot be placed against anything and cannot
be measured — it is trying to be the size of the box, and the box is trying to
be the size of it. So:

- **A piece that stretches along an axis is not measured on that axis.** The
  pieces that are not stretching decide the size; the stretched one takes it.
- **A piece that stretches BOTH ways is the surface behind everything.** It
  steps out of the arrangement entirely: no turn in a stack, no gap, and it is
  painted to the container's own edges rather than to the room inside them,
  because padding is room INSIDE a button's fill, not around it.
- **Where every piece stretches** there is nothing else to go on, so they are
  measured after all and the group keeps the size it had.

**A hugging axis takes that axis over.** There is no spare room on it, so the
contents keep the arrangement they already have and move as one to the room at
the near edge; the group's own corner holds still, so a control grows to the
right and downward. Typed X and Y are closed on that axis, with the reason
pointing at Padding, the same way a stack closes the axis it flows along. An
axis with a size of its own is untouched: the placement rules still answer it,
which is why a button dragged wider keeps its label in the middle.

**Dragging a handle still sizes rather than scales**, and it pins only the axis
that changed: drag a hugging button wider and it holds that width while its
height still follows its label.

**The two controls that are a word with room around it now say so.** The
starter **Button** is 16 either side of its label and 36 tall, and the
**Badge** is 8 either side of its count. Re-word either one — by typing on the
canvas, or by answering a copy's knob — and the control gets wider on its own,
with the same room it had. The other three starters are boxes with a shape of
their own (a card is 260 wide because that is the card), so they hold the size
they were drawn at.

**Closing around the WORDS, not the measuring slack.** A measured text box
carries four points of slack for antialiased edges, and the glyphs are drawn
flush to its near corner, so the slack all sits on the far edges. A container
measures its text children without it, or every centred label sits two points
off the middle of the control it is in. The same reasoning made
`StarterComponents.estimatedTextSize` go through `TextMeasurement`: two
estimates that disagreed by a single point were enough to make a starter's
label look like a paragraph somebody had already narrowed, so a longer word
wrapped down the page instead of widening the button.

**Where it lives.** `GroupLayout.kind` is optional now (nil is Free, and writes
no key, so a document saved before this is byte for byte what it was);
`GroupFlow.closedAround` is the free flow, `GroupFlow.size` the one sum both
the flow and `Layer.localBounds` measure with, `ResolvedPlacement.isSurface`
the rule above, and `Layer.contentBounds` the words-not-slack measurement.
`LayerScaling.rearranging` pins the dragged axis. `StarterComponents.layout`
gives the button and the badge theirs. `ArrangementInspector` shows the rows
for Free. Tested in `GroupHugTests`, walked by
`Scripts/playtest/button-hug-walk.json`.

Not in this slice: hug for a SCREEN, which is deliberate — a screen's box is
the box you drew, and something hanging off its edge must never resize it. Nor
a minimum or maximum size, so a hugging button with one letter in it is as
narrow as one letter plus its room.

## Landed: a copy is not asked to decide what its original decides (Next, `next-auto-layout` + `next-components`, 2026-09-04)

Picking a copy showed the whole Layout section: Arrangement, Gap, Padding, and
the rows saying where its contents sit. Every one of those is refilled from the
original by `syncComponentInstances`, so 24 typed into a copy's Padding read
back as 24 until the next edit anywhere in the document, and then it was 0
again. The section was offering something it could not keep.

- **The model refuses it, not the panel.** `canSetGroupLayout` says no to a
  copy, and `setGroupLayout`, `updateGroupLayout` and `setContentPlacement` all
  guard on the new `ownsContentRules(id:)`. A rule the interface enforces is a
  rule a keystroke, a script or a menu can walk around, and this one is about
  data that is going to be overwritten.
- **A copy is SHOWN its arrangement and refused the typing of it**, which is the
  answer the W and H fields already give a copy. The numbers move into a
  sentence rather than into greyed-out fields, because a field you cannot type
  in still looks like a field and eight of them reads as broken rather than as
  owned by somebody else: "Everything in this copy lines up down, 30 apart. It
  keeps 16 clear inside its edges."
- **Who owns it is said once, at the foot of the section**, under the Horizontal
  and Vertical rows it hands over as well: "A copy arranges its contents the way
  its original does. Use Edit Original in the Component section to change it for
  every copy." That button is three rows below, in view in the same panel.
- **An axis the arrangement decides says so in the same words on both**: a copy
  reads "Set by the stack" where the original does, rather than reading back the
  answer underneath that the stack is overriding.
- Everything a copy really does own is untouched: where it sits, its knobs, its
  own placement rule inside whatever holds it, and (since 2026-09-04) its size.

`PhotonzDocument.instanceArrangementReason` is the one sentence, shared by the
rows' tooltips and the caption. Tested in `ComponentInstanceLayoutTests`, walked
by `Scripts/playtest/copy-layout-walk.json`.

Since then a copy HAS been given one of these for itself: its size, below.
Padding a copy may set for itself is still not in, and still for the same
reason it was refused here: nobody hits it daily, and refusing is honest.

## Landed: a copy can be given its own size (Next, `next-components`, 2026-09-04)

The same nav bar is 1200 points wide on a desktop screen and 375 on a phone.
Until now the only way to say that was Detach, which throws away every future
edit to the original: the W and H boxes on a copy were greyed, because a number
typed there was overwritten by the next sync.

A copy now takes a width and a height like any other layer, and keeps them.

- **The eight handles are back on a copy, and the boxes take typing.** Drag a
  copy's edge or type 1200 into W and it is 1200 wide. One undo puts it back.
- **Nothing inside the copy is scaled.** A copy told how big it is flows its
  contents into that box exactly as the original would at that size: a bar
  that stretches spreads across 1200, a title pinned left stays 16 in from the
  left, a control that hugs its label keeps the label the size it is. Scaling
  the contents would have been work the next sync threw away.
- **One axis at a time.** Widen a copy and its height still follows the
  original, which is the ordinary case rather than a special one: a nav bar
  owns its width and takes its height, its colour, its wording and its spacing
  from the original as before.
- **The Component section says so, and is the way back.** A copy that owns a
  side shows an "Its own size" row reading `1200 wide` (or `48 tall`, or both)
  with the same u-turn button "Its own look" carries. One press puts both sides
  back on the original. Without the row, a copy that quietly ignores the
  original's width is a copy nobody can explain, because the W box looks the
  same whether the number in it is the copy's answer or the original's.
- **A copy PLACED by the thing it sits in claims nothing.** A copy stretched
  across a stack or a screen goes through the same resize a handle drag does,
  so without a guard every stretched copy would silently and permanently stop
  following its original. The container's answer is passed through as such
  (`Layer.resized(to:placedByContainer:)`) and recorded nowhere.
- **The size is the ONE thing this hands over.** Arrangement, gap, columns,
  padding and where the contents sit are still the original's, still refused on
  a copy, and still say so at the foot of the Layout section.

The record is `GroupContent.instanceSize` (`InstanceSize`: a width and a height,
either of them nil for "follows the original"), written OVER the original's
layout by `syncComponentInstances` through `InstanceSizing`, and over the frame
box for a copy of a screen. It is dropped on detach, and saved only by a copy
that has one, so a document written before this is byte for byte what it was.
`LayerScaling.resizingCopy` is the resize. Tested in
`ComponentInstanceSizeTests`; the refusal it replaces is documented above.

## Landed: dragging onto a screen puts it in the screen (Next, `next-frames`, 2026-09-03)

Drawing a shape on a screen already put the shape on that screen, and dropping
a copy from the Library already put the copy on it. Dragging something that was
already on the canvas did not: it landed on top of the screen and stayed a
sibling, so moving the screen left it behind, and the layers list read as two
things side by side when the picture read as one thing on top of the other.

**One rule, whichever way it got there.** A layer joins the screen that holds
its **centre**, the same rule `addLayerOnFrame` has always used, so a shape
dropped mostly on a screen joins it and one dropped mostly off it does not.
Nothing moves on screen: the position is rewritten into the screen's space.

**Leaving matters as much as joining.** A layer dragged off a screen comes out
onto bare canvas. Without that, dragging something out of a clipping screen left
it a child and simply clipped it away, which looks exactly like the layer
vanishing.

**Only a drag.** A resize and an arrow-key nudge never change what holds a
layer, even though they share a commit path with the drag today. A layer
quietly changing hands one point at a time is a surprise nobody can see coming,
and there is no pointer over a screen to say it is about to happen. An ⌥-drag
does adopt: the copy joins the screen it was dropped on.

**The promise is on screen before you let go.** While the pointer is down the
screen a drop would join wears the same dashed box a component dragged off the
Library shelf draws, because it is the same promise. A drop that changed hands
opens that screen in the layers list, so the layer is not lost in a shut row.

**What never happens.** A screen is never swallowed by another screen (the rule
pasting a screen already follows); nothing goes inside a COPY of a component,
whose contents belong to its original; and nothing goes anywhere that would put
a component inside itself.

**Where it lives.** `FrameAdoption.swift` holds the rule (`frameAdoption`,
`frameAdoptionHost`, `adoptMovedLayers`) and `canMoveSubtree` in
`ComponentInstances.swift` holds the component half of it.
`EditorState.commitCanvasDrop` and `commitCanvasOrigins(_:joiningScreens:)` are
the drag-only commit paths; `CanvasNSView.adoptionHost` draws the promise.
Walked end to end in `Scripts/playtest/screen-adoption-walk.json`.

Not in this slice: a screen growing to fit something dropped half over its
edge, and a single click reaching a layer that sits directly on a screen (it
still picks the screen, which is the rule for every group).


## Landed: one color picker, everywhere a color is chosen (Next, `next-color-picker`, 2026-09-04)

Asked for on 2026-09-03 with a screenshot of the designed picker. The app had
three different answers to "pick a color": a bespoke popover on the shape and
tool rows, the system color panel on the shadow, backdrop and measurement rows,
and nothing at all in between. Which picker you met depended on which row you
clicked.

There is one now, drawn the way `docs/design/mocks/pages/color.html` draws it:
what you are painting and what it looked like before, a saturation and
brightness square, a switch between HSL, RGB and HEX with one slider and one
number per channel, one swatch row that answers "near this one" four ways,
a live contrast reading and Save style. Every color row in Next opens it:
a shape's inside, its outline, text, border, a drop shadow, a collage backdrop,
a measurement's stroke, chip and text, the tool colors, the foreground and
background fills, and a saved color's own row. No row raises the system panel
any more.

The arithmetic is in `PhotonzCore` and tested: `ColorPickerModel.swift` holds
the HSL and HSV views of a color, `PickerColor` (hue kept separately, so
dragging to black and back returns the color you started from rather than a
red), the channel and format tables, `ColorText.parse` for everything a pasted
color arrives as, the derived shade and relative ramps, and `ContrastReading`
on real WCAG luminance. `DocumentColors.swift` answers what a document is
actually painted with, most used first. The view is
`Sources/Photonz/DesignedColorPicker.swift`; `ColorPickerEntry.swift` holds the
ONE switch between it and the old picker, so no future row can open something
else.

Three deliberate departures from the mock, each in the audit
(`queue/audits/2026-09-04-one-color-picker.json`):

- **A fourth swatch scope, Recent.** The mock has three. Dropping recents would
  have been a regression for the commonest move, reusing the color you just
  used on something else.
- **The contrast reading is fixed on white**, where the mock reports whichever
  of white or black scores better. A readout that silently changes its own
  background cannot answer "can I put this on the page". Black is in the tip.
- **No Solid, Linear, Radial and Angular row.** Three of the four would have
  done nothing. Gradients are their own task and the row arrives with them.

Two things the picker is honest about and does not yet do: the color lands on
release rather than during the drag (one drag would otherwise be twenty undo
steps), and the eyedropper is the system sampler, whose own loupe is the live
preview. Both are queued.

Two pieces of harness came with it, because a popover in the dock is out of a
walk's pointer reach: the actions `openColorPicker`, `openShadowColorPicker`
and `closeColorPicker`, and an `appearance` step that puts the probe into light
or dark for the shots that follow without touching the machine's own setting.
Walk: `Scripts/playtest/one-color-picker-walk.json`.

## Landed: every starter says what it is the size of (Next, `next-auto-layout`, 2026-09-04)

The button and the badge closed around their words that morning; the card, the
nav bar and the text field still held the size they had been drawn at, so a
long card title ran past the edge of the card. Now all five answer the same
question, and none of them answers it the same way, because the honest answer
depends on what the thing IS:

| Starter | What it is the size of |
| --- | --- |
| Button | As wide as its label with the room either side, and 36 points tall. |
| Badge | As wide as its count with the room either side, and 20 points tall. |
| Text Field | 220 points wide, and as tall as its placeholder with the room above and below. |
| Card | 260 points wide, and as tall as everything on it with the room above and below. |
| Nav Bar | A box 320 points wide and 48 points tall. |

Those sentences are not typed out beside the drawings: `StarterComponent.sizing`
writes them FROM the layout each one is built with, so they cannot drift into
describing a card that no longer exists. The Layout section says the same thing
live for whatever is selected, which is where a person actually reads it.

**A field and a bar keep their width on purpose.** A field 74 points wide
because "Name" is short is not a place to type, and a bar is as wide as the
screen it sits on, never as wide as its title. So the width is a number, the
wording wraps inside it, and a nav bar title too long for its bar stays centred
and overhangs — which is what a person building that screen needs to see.

**The card is the one that ARRANGES.** It is a column stack, not a box that
closes around what is in it, and that is the whole reason it works: a title
long enough to wrap has to push the line under it DOWN. A free group leaves
every piece where it was put, so the second line of the title would have grown
straight through the first line of the body. It would have looked right on the
first title and broken on the second.

**Stretch across, not fill.** The card's picture well used to say "stretch both
ways", which the container rules now read as "I am the surface behind
everything" — so the well would have been painted to the card's own edges and
covered the card. It says stretch ACROSS now, and keeps its own height. The
title and the line under it say the same, which is what makes them wrap into
the card's room instead of running out of its right-hand side.

**Where it lives.** `StarterComponents.layout` gives each of the five its two
sides, `StarterComponents.sizing` writes the sentence from that layout, and the
drawings themselves carry the placement each piece needs. Tested in
`StarterSizingTests`, walked by `Scripts/playtest/starter-sizing-walk.json`.

Not in this slice, and both worth knowing: a starter already sitting in a
document keeps the shape it was dropped with, because a starter is a drawing
made at drop time and nothing rewrites one in place. And a text field with a
long placeholder WRAPS rather than truncating with an ellipsis, because a text
layer has nothing that clips; growing downward is the honest shape when nothing
can be hidden.

## Landed: a container can be told the smallest and largest it may get (Next, `next-auto-layout`, 2026-09-05)

The hug audit's own complaint: "There is no minimum width, so a button with one
letter in it is as narrow as one letter plus its room." Hugging is right until
it is not — a two letter button stops looking like a button, and a card with a
very long title runs off the screen. Every group can now be given a floor and a
ceiling on each axis, and neither one is anything but a typed number.

**Four numbers, empty by default.** Beside the **Width** and **Height** rows in
the Layout section sits the same twist-open **Padding** already uses. Open it
and there are two rows, **Smallest** and **Largest**, both showing None. A
group nobody has typed a number into is byte for byte the group it was: the
same layout, the same file, no extra work in the flow. The rows open themselves
whenever a limit is set, so a group that stopped growing never hides the reason,
and the section's sentence reads it back: "It never gets narrower than 200."

**The room a floor makes belongs to the contents.** This is the part the sketch
of the feature got wrong and the build fixed. A floor holding a group open makes
room nobody has put anything in yet, so the whole block of contents moves to
where its pieces agree it should go: a centred word centres in the room the
floor made rather than sitting jammed against the left padding. An axis the
group was GIVEN a size on is different — that size came from a handle somebody
dragged, and things staying where you put them is what Free means — so it is
only the limit case that places the block.

**Contents too big for the room start at the near edge.** A word wider than its
ceiling overhangs the far edge rather than centring and escaping off the near
one, where nothing else in the app would look for it. Overhanging is honest
until there is a way to wrap or shrink words; nothing is clipped and nothing is
lost.

**The rules that keep it small.** The smallest wins where the two cross, which
is what anybody who has written a stylesheet already carries, and typing 96 over
a 9 passes through that state anyway. A limit stops a dragged handle too, so the
number in the field and the box on the canvas can never disagree. A stack or a
grid held at a limit lays its rows out in the room it actually has, rather than
overflowing it quietly. A limit that does not bite costs nothing: the flow only
runs a second pass when the number it comes back with is not the one it started
with.

Not in this slice: wrapping or shrinking words that outgrow a ceiling, limits on
a screen (its box is its frame), per child limits, and limits as tokens on a
scale.

Model and maths in `GroupLayout` and `GroupFlow` (`limitsSize`, `heldWidth`,
`heldHeight`, `holding`), the rows in `ArrangementInspector`. Tested in
`GroupSizeLimitsTests`, walked by `Scripts/playtest/size-limits-walk.json`.

## Landed: a bar's hairline is chrome, not a row (Next, `next-auto-layout`, 2026-09-05)

A bar is not only the controls on it. It is a surface, a hairline along its
bottom edge, and then the controls. The surface already stepped out of the flow,
because stretching BOTH ways can only mean "be the size of the box" and
something that is the size of the box cannot decide how big the box is. A
hairline stretches ONE way and hugs an edge on the other, and a row counted it
as one more control and stood it in the line — 320 points of nothing, with the
real controls pushed off the end behind it. Which is why the one starter shaped
like a bar could not be built as a row at all, and was a Free box of pieces
pinned by hand instead.

**One rule, said about one axis instead of two.** A piece stretched along the
way a stack RUNS steps out of the flow and is painted to the group's own edges,
exactly as the surface is. Across a row, that is a hairline; down a column, a
rail. Its OTHER direction still says which edge it hugs, so Bottom puts the
hairline on the bottom of the bar whatever the bar's height becomes, and both of
its rows stay live in the Layout section — changing either one is how it stops
spanning and becomes a piece being arranged again. `Stretch` along the flow was
inert before this: the flow is what hands out the room along itself, so a row
asking for all of it was never a request the flow could honour. The way to say
"take what is left over" is Fill, and it is a different answer with a different
name.

**The starter Nav Bar is a row now.** Drop it, drag it wider, and it arranges
itself with nothing typed into the Layout section: the back label holds the
room at the left edge, the hairline spans the new width and stays a hairline,
the surface fills it, and the title stays in the middle of the whole bar rather
than in the room the back label leaves — a title is centred on the bar it is on,
which is what the render test has always asked of it. Three of its four pieces
are not things the row lines up at all, and its Layout section says so: Stack,
Row, and three pieces listed with a rule of their own. What is left in the row
is the leading end of the bar, so a second control dropped beside the back label
lines up with no numbers typed.

**The title is drawn UNDER the controls.** Its box is the whole bar, so on top
it would answer for every click meant for the back label — driving the built bar
on 2026-09-05 is how that was found, not reading the diff.

**Centred words line up in the width they were measured against.** A text box
carries a couple of points on each side for the antialiased glyph edges to round
into, sitting on the far edges because words drawn from the left never touch
them. Centred words are not drawn from the left: half that slack landed on their
left and put them two points right of the middle of the box they were centred
in. They now lay out in `naturalSize`'s own constraint, so a centred label is
centred on the box a person can see. Nothing changes for a label that has never
been given an alignment, which is every label written before alignment existed.

Rule in `ResolvedPlacement.stepsOutOfTheFlow(of:)`, applied by `GroupFlow.placed`
(which now spans each piece per axis rather than only filling the surface),
`GroupFlow.arranged` and `PlacementEditing`. Drawing in
`StarterComponents.navBar`, words in `TextRasterizer.alignedWidth`. Tested in
`GroupChromeTests`, walked by `Scripts/playtest/nav-bar-row-walk.json`.

## Landed: a row can push its contents to its two ends (Next, `next-auto-layout`, 2026-09-05)

A bar is a logo at one end and buttons at the other, and one gap cannot make
that shape. Until now the only way to build it was to nudge the pieces apart by
hand and watch the stack put them back, which is the whole complaint auto layout
exists to answer. A stack that has been given a size of its own can now share
the room it has LEFT OVER between its rows instead of holding a number.

**A switch beside the word, not a row of its own.** The Gap row grows a small
arrows-apart switch between its label and its field. Press it and the field
reads **Spread**: the first piece sits on the near edge, the last on the far
one, and everything between them shares the room equally. The Layout section
already spends seven rows on one group, and this is two states about the number
on the same line, so it is a switch rather than an eighth row.

**Two ways back to a number, because either is the one somebody reaches for.**
Press the switch again and the gap that was there comes back — the number is
KEPT while it spreads, never thrown away and never re-inferred — or type a
number straight over the word Spread, which turns spreading off and holds that
gap. The word is drawn at full strength, not the grey a Mixed value is drawn
at: it names a real state rather than standing in for a value that is not one
value.

**It is only offered where it could do something.** There is room to spread only
where the axis the stack FLOWS along is bigger than its contents: a size of its
own, a floor holding it open, or a screen, whose box is the box you drew. A
stack that hugs has nothing left over, so the switch is not there at all and the
section's sentence says why in one line — "There is nothing left over to spread
until Width is Fixed." A control that is present and changes nothing is worse
than no control. A grid is never offered it either: its columns already share
its width out, and a second way to say that is a second way to be wrong.

**The room is measured from the start, not added up gap by gap.** Each row is
pushed on by its own share of what is left over, rounded once, so the last one
lands exactly on the far edge however the rounding falls, and no gap is ever a
half point. Contents too big for the room share nought and sit tight against
each other rather than overlapping, which is the same answer a stylesheet gives.
The room at the edges is respected on both sides, so the two ends land inside
the padding, and the surface behind a bar still takes the whole box rather than
being spread with the pieces on it.

Not in this slice: sharing the room around the outside as well (the centred and
space-around shapes), spreading a grid's rows, and per-child growth — a piece
that eats the leftover room itself rather than the gaps doing it.

Model and maths in `GroupLayout` (`spreadsGap`, `spreadsContents`,
`couldSpread`) and `GroupFlow.spread`, the row in
`ArrangementInspector.gapRow`. `GroupLayout` writes its own JSON now, for one
reason: a stack that holds one gap writes nothing at all about spreading, so
every document saved before this is byte for byte the file it always was, and
`everyNumberRoundTrips` is the test that stops the next number added there from
being forgotten in that list. Tested in `GroupSpreadTests`, walked by
`Scripts/playtest/spread-gap-walk.json`.

## Landed: a piece can take the room a row has left over (Next, `next-auto-layout`, 2026-09-05)

The search field in the middle of a nav bar is not a width somebody chose. It is
whatever the logo and the buttons left, and it changes every time the bar does.
Until now every piece in a stack kept the size it was drawn at along the way the
stack runs, so the only way to build that was to drag the field to the right
width and drag it again the moment anything around it moved. One piece in a
stack can now be told to take what is left instead.

**Filling is about the FLOW, not about an axis.** The row that already said who
owns the direction the stack runs in ("Set by the row", "Set by the stack") is
now a menu with exactly two answers: that, or **Fill the row** / **Fill the
stack**. It says "take whatever this stack has left along the way it runs", so
flipping a row to a column goes on meaning the same thing rather than turning
into a rule about the wrong direction. It is named after the flow because the
panel already has a Fill three sections down — the colour inside a shape — and
two controls a thumb apart wearing the same word is how somebody paints a
rectangle when they meant to widen it.

**It is not the Stretch that makes a surface.** Stretched BOTH ways still means
"be the surface behind everything, painted to the box's own edges", which is
what a button's fill is. Something that is the size of the box cannot also be
one of the pieces sharing the box out, so a filler is its own thing and the two
never collide: a search field that fills a bar across and fills its height down
is still a piece being arranged.

**A filler takes the leftover instead of its own size, and two split it.** What
is left is the room inside the edges, less every other piece, less every gap.
Two fillers split it down the middle, measured from the start so the pair lands
exactly on the room there was and no piece is ever half a point wide. Nothing is
ever handed less than nothing: contents already too big for the stack leave a
filler with no room rather than a negative width, and a shape that had a size
keeps a point of it so it can still be grabbed.

**A filler beats a spreading gap.** Two things cannot both have the room left
over. Where a piece fills, the stack goes back to sitting the typed gap apart,
which is the answer anybody who has written a stylesheet already carries;
sharing nought between them would close every gap and read as broken.

**Setting it back gives the size back.** The flow writes the size it worked out
straight into the piece, so without this a button tried at Fill for a second
would be stuck at whatever the room made it with nobody left who remembers what
it was. The size before is kept on the piece and handed back on the way out, one
edit and one undo. Words are the exception down a column: their height is
however tall they came out, so they go back to their own measurement.

**It is only offered where it could do something,** on the same test spreading
uses: room exists where the axis the stack FLOWS along is bigger than its
contents. A hugging stack has none, so there is no menu at all and the caption
under the rows says why and names the number that would change it. And while a
piece is filling, the size field on that axis is a number to READ, not one to
type: the flow would put a typed number straight back on its next pass, so it
loses its box and its tip points at the two controls that do change it.

Not in this slice: a container default ("everything inside fills"), which is a
grid; growth weights, so one filler can take twice what another does; and a
minimum a filler will not shrink below.

Model in `FlowFill` and `Layer.flowFill`, the maths in `GroupFlow.alongTheFlow`,
the offer in `PlacementEditing.canFill` / `fillTitle` / `noRoomToFill` over
`GroupLayout.hasRoomAlongTheFlow` (which `couldSpread` now reads too, since both
ask one question), the edit in `PhotonzDocument.setFillsTheFlow`, and the row in
`PlacementInspector.ownedByTheFlow`. Tested in `GroupFillTests`, walked by
`Scripts/playtest/fill-the-flow-walk.json`.


## Landed: a component holds more than one version (Next, `next-components`, 2026-09-05)

A button has a normal look, a hover look and a disabled look. Until now those
were three components, and the three drifted apart the first time anybody edited
one. A component now holds more than one drawing of itself under one name, and
every copy picks which one it is showing.

**A version is a whole drawing, not a list of differences.** The user settled
this on 2026-09-05, with the cost stated: a version may differ in ANY way — a
different shape, an extra part, another arrangement — and in exchange a change
meant for every version has to be made in each one. The mitigation chosen with
it is that a new version is made by DUPLICATING one that already exists, so
versions start out identical and only differ where somebody made them differ.

**A version is an ordinary main on the canvas.** It selects, moves, restacks,
hides, saves and undoes like any group, and every tool already works on it. That
is the whole reason a version is a drawing rather than hidden data: a version
you cannot see is a version you cannot edit. A new one lands loose on the canvas
just to the right of the one it came from — not inside whatever holds that one,
or adding a version to a button that lives on a screen would drop a stray button
into the screen.

**The duplicate keeps the knob ids and points them at its own layers.** That is
what lets a copy keep the wording and the colours it chose when it is switched
between versions; a duplicate with fresh knob ids would reset every copy the
moment it switched. Each version carries its own knobs after that, so the
Adjustable list belongs to the drawing you have selected.

**A copy says which version it shows, in writing.** From the moment a component
gets its second version, every version has an id and every copy names one, so
restacking the drawings can never change what an already placed copy draws. A
copy left holding a version somebody deleted lands back on one the component
still has, and the canvas says so ("Version deleted · 1 copy moved to Default")
rather than leaving it drawing nothing.

**Where it is.** The Component section on the ORIGINAL grew a Versions block:
the drawing you are on wears an editable name and the word "showing", the others
are a press that selects them, and Add makes one. On a COPY the Version row sits
above the knobs, because a knob changes one fact and a version changes the whole
drawing; copies picked together that show different versions read Mixed, like
every other row there. The layers list prints the version name beside the
component mark, since every version carries the component's name. Edit Original
on a copy lands on the version that copy is showing.

Not in this slice: a version set drawn as one thing on the canvas, and
reordering versions. (One edit reaching every version, and placing a particular
version straight from the shelf, landed separately, below.)

Model in `ComponentVersions.swift` (`ComponentVersion`, `componentVersions`,
`addComponentVersion`, `setInstanceVersion`), the fields on `GroupContent`
(`versionID`, `versionName`, `instanceVersion`), the sync in
`PhotonzDocument.syncComponentInstances`, the panel in
`ComponentVersionList` / `ComponentInstanceProperties.versionRow`. Tested in
`ComponentVersionTests`, walked by
`Scripts/playtest/component-versions-walk.json`.


## Landed: one edit reaching every version (Next, `next-components`, 2026-09-06)

The cost accepted with the choice above was that a change meant for every
version has to be made in each one: a new corner radius on a button gets typed
three times, and the third time it gets typed wrong. This is that cost sanded
down, and it is deliberately the SMALL answer.

**What it is not.** Not a mode you enter to edit every version together: a mode
you have to enter is a mode you forget you are in, and it fights the whole point
of versions, which is that they may differ anywhere. Not "make the other
versions match this one" over the whole drawing either: that deletes exactly the
divergence versions exist to hold.

**What it is.** You edit ONE PIECE in the drawing you are looking at, the
ordinary way, with the ordinary controls. Then one press gives the same piece in
every other version this piece's LOOK and WORDING: its colours, rounding,
border, shadow, fade, the saved colours it points at, and the words themselves.
Where each piece sits, how big it is, and what is inside it never travel — so a
version that arranges its pieces differently, or has a part the others do not,
comes through untouched. Text is the one exception on size: a text layer's box
IS its wording, so the same words in the same type take the same room.

**It names what it would change, before it runs.** The row reads "Apply to
Hover and Disabled", not "Apply to Other Versions", because "what is this about
to touch" is the question somebody asks with their hand on the button. Once
there are more names than a row can carry it counts them instead. When every
other version already matches it says so and dims, rather than being a button
you press and watch do nothing, and a version with no matching piece is NAMED as
left out rather than quietly missed.

Standing on the DRAWING itself rather than on a piece inside it carries only
that drawing's own surface, and the sentence beside the button says so: claiming
"Button already matches" when only its surface does would be a lie about the
whole thing.

**Where it is.** A Component section on the piece itself, right above Color and
Effects: you have just moved the Corner Radius slider, and the answer to "do I
now have to do that twice more" belongs beside the slider you moved, not only in
a menu you would have to know to look in. The same row sits under the Versions
list on the original, and the same command is in the Layer menu and the layers
list's context menu.

**Matching the same piece across drawings**, strongest first: a knob (a
duplicate keeps the knob ids, so an adjustable piece has an exact handle in
every version), then its place inside the drawing WHEN the name there agrees,
then its name when exactly one piece over there wears it. Position alone was
tried and is wrong: a version that grew a glow at the front would have had the
glow repainted with the button's colour. When none of the three answers, the
version is skipped and said to be skipped.

One `History.perform`, so one undo step however many versions it reached, and
every copy of every version it touched follows inside that same step.

Model in `ComponentVersionMatching.swift` (`ComponentVersionApply`,
`componentVersionApply`, `applyToOtherComponentVersions`,
`Layer.wearingTheLookAndWording(of:)`), the pill in
`CopyConfirmation.componentVersionsMatched`, the panel in
`ComponentVersionApplyRow` / `ComponentVersionPieceInspector`, the menus in
`EditorCommands` and `LayersPanel`. Tested in `ComponentVersionMatchTests`,
walked by `Scripts/playtest/apply-to-versions-walk.json`.


## Landed: placing a particular version straight from the shelf (Next, `next-components`, 2026-09-06)

Every copy used to land showing the component's FIRST version, so a disabled
button was two steps: drop one, then find the Version row and switch it. On a
screen wanting four disabled buttons that is four corrections. The shelf can now
hand you the version you asked for, and the copy arrives already showing it.

**Where the choice is.** In the Component section under the shelf, the one that
opens when you pick a tile, directly above Place a Copy: a "Place" row naming
the version a copy off this tile will arrive as. It is there only while the
component holds more than one drawing, so a shelf of plain components is exactly
the shelf it always was.

**Not on the tile itself.** A tile is 68 points wide and already carries a
click, a double click and a drag; a fourth gesture on a nine point badge is a
gesture nobody lands, and a version called "Disabled, pressed" has nowhere to be
read there. What the tile DOES carry is the answer: it draws the chosen version's
picture and wears its name on a small badge, so the shelf shows what you are
about to get before you pick anything up.

**Every way of placing agrees.** Dragging the tile, double clicking it, Place a
Copy and Layer ▸ Insert Component all place the version the shelf is set to, and
the box drawn under the pointer mid-drag is that version's size — versions may
differ in size, so the outline in the air would otherwise promise the wrong box.

**It is a state of the tool, not a fact about the picture.** The choice is not
saved in the document: it is which version you are placing right now, like the
tool in your hand. A version deleted after it was chosen falls back to the
component's first rather than leaving the shelf pointing at a drawing that is
gone, and a copy already placed can still be switched afterwards, so choosing at
the shelf is a shortcut rather than a decision you are stuck with.

The version rides along on the drag pasteboard beside the component id
(`ComponentDrag.Payload`), so what the tile was set to when the drag started is
what lands. Model in `PhotonzDocument.insertComponentInstance(of:at:inside:version:)`
and `componentDropLanding(…version:)`, the shelf's own choice in
`EditorState.shelfComponentVersionChoice` / `shelfComponentVersion(of:)`, the row
in `LibraryComponentInspector.versionRow`. Tested in
`ComponentVersionPlacementTests`, walked by
`Scripts/playtest/place-a-version-walk.json`.

## Landed: a copy can have its own room inside (Next, `next-components`, 2026-09-06)

Number knobs (C6) reached every layer INSIDE an original and stopped there. So a
card built the way cards are actually built, as one stack with room kept clear
inside its own edges, had that room on the outermost group and nowhere else, and
every copy of it was stuck with the same roominess. Nothing said why: the Add
menu listed each piece of the card and not the card.

- **The original itself is on the Add menu**, first, offering the two numbers it
  holds its contents with: **Gap** and **Padding**. First because it is the
  outermost thing, and a menu that listed the pieces of a card and then the card
  would read inside out. The row reads "Card ▸ Padding", the component's own
  name and the number it turns.
- **Only those two.** The card's rounding, the line round it, its fade and its
  shadow are deliberately not offered: a copy already owns every one of those
  part by part the moment it is given one (`LayerStyle.following`), and two
  mechanisms writing one field is the two-sliders bug `CornerRadiusSelection`
  exists to end. The room and the gap have no such second way in, which is the
  whole reason they need this one.
- **The answer lives in the copy's own layout**, not in its contents, because
  that is where the room is. It is written on where that layout is built, after
  the size the copy owns, so a copy that owns its width and its room keeps both:
  they are different fields of one layout and neither writes over the other.
- **Nothing new appears on screen.** The Add row, the number field on the copy,
  the revert arrow and the Layout section's sentence ("It keeps 40 clear inside
  its edges") were all already there and all already generic.
- **The copy's contents move in the same edit.** The flow pass runs before the
  copies are refilled, so a copy whose own layout was the only thing to change
  would have stayed where the old room put it until the next edit. The sync now
  counts a changed layout as a changed copy, which is what runs the second flow
  pass.
- On disk nothing is new: a knob already carries the layer it names and the
  number it turns, and this one simply names the outermost layer. A document
  written before it decodes exactly as it did.

Deliberately left: **room that differs side to side is still not offered at
all**, on the component itself or on any layer inside it, because "the room" of
a group keeping 10 above and 16 beside is not one number. That rules out the
common case of making a button roomier, since every starter control except the
card is built with a taller-than-wide inset.

Where it lives: `ComponentNumberSlot.onTheComponentItself` and the `GroupLayout`
number accessors in `ComponentNumberKnob.swift`, the root row in
`PhotonzDocument.componentPropertyCandidates`, `applyRootOverrides` in
`ComponentProperties.swift`, called from `syncComponentInstances` and `rebound`
in `ComponentInstances.swift`. Tested in `ComponentRootNumberKnobTests`, walked
by `Scripts/playtest/component-own-room-walk.json`.
