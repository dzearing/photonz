# A layer is made of parts

One model for every switchable thing a layer paints: fill, outline, shadow, and
anything added later such as an inner shadow or a glow. Written down before any
of it was built, because it changes the shape of every inspector and a model
half-applied is worse than the mess it replaced.

Status: **built in Next**, behind `next-shape-parts` (on by default there).
The layout was the user's call and they took it on 2026-09-06: *one list,
settings unfold*. Later the same day they asked for the fold to go: a part that
is switched on shows its settings straight away. Current is untouched.

## Why

Reproduced on the probe on 2026-09-06, one rectangle picked, Next release:

| Section | Rows |
| --- | --- |
| Color | Fill (checkbox, swatch, saved-colors menu) · Outline (swatch, menu, **no checkbox**) |
| Effects | Opacity · Blur · Corner Radius |
| Rectangle | Thickness |
| Shadow | Enable Shadow (switch) |

Three faults, each verified rather than assumed:

1. **The outline cannot be removed.** There is no switch on the Outline row, and
   `AnnotationStyles.strokeWidthRange` is `1...40`, so the thinnest a rectangle
   can be is a one point ring. A person who wants a plain filled box has no move
   to make. This is the thing the user hit.
2. **One part is spread over three sections.** The outline's colour is in Color,
   its thickness is in Rectangle, and the corner it turns is in Effects.
3. **Three different idioms for "is this on?"** — a checkbox in a shared section
   (Fill), nothing at all (Outline), and a switch inside a section of its own
   (Shadow). Learning one teaches you nothing about the next.

The user's original report also said a rectangle carries a *Border* under
Effects as well as a *Thickness*, which was true when they hit it but is no
longer: "One width for the line round a shape" (2026-09-03,
`Sources/PhotonzCore/OutlineWidth.swift`) took the Border row away from any
layer that draws its own outline. The two-edges confusion is therefore already
resolved for shapes; a picture, a frame, a label or a group still has a Border,
and this document renames it so that the word matches what the shape has.

## The model

> **A part is something a layer paints that can be absent.**
> It has one switch, one colour, and settings that only exist while it is on.
>
> **A property is something the layer always has.**
> It has no switch: position, size, opacity, blur, corner radius, an arrow's
> head size.

That single test is the whole model, and it is what makes the panel teachable:
learn to add an outline and you already know how to add a glow, because a glow
will arrive as one more row with a switch, a colour and its own settings.

### The parts a layer has

| Layer | Parts |
| --- | --- |
| Rectangle, ellipse | Fill · Outline · Shadow |
| Line, arrow | Colour (no switch: the line IS the shape) · Shadow |
| Highlight, text | Colour (no switch) · Outline · Shadow |
| Picture, frame, group, callout | Fill (a frame's surface) · Outline · Shadow |
| Later | Inner shadow · Glow, on any of them |

A shape that is all one colour keeps the single row it has today, labelled
Colour, because calling a line's one colour an outline is a small lie
(`ShapeSettingsNaming.swift` already draws this distinction and it stands).

### What each part holds

| Part | Switch | Colour | Its own settings |
| --- | --- | --- | --- |
| Fill | on/off | the fill colour | none yet (a gradient is a kind of colour, not a setting) |
| Outline | on/off | the outline colour | Thickness |
| Shadow | on/off | the shadow colour | Blur, Size, Distance, Direction, Opacity |

**Off means off, everywhere.** A part that is switched off shows its switch and
its name and nothing else: no colour, no settings. Switching it back on brings
back the colour and settings it had, so switching off is never destructive and
never loses what you had set.

**Every switch means the same thing underneath.** A colour that can be absent is
stored as an absent colour (`setAnnotationFill(nil)`); an outline that is off is
a width of zero, which is a real document state that saves, reopens, undoes and
copies like any other, and which the rasterizer has always drawn as no line at
all. Nothing about how an existing document draws changes: a rectangle with a
4pt outline today has its Outline part on at 4pt.

The one thing "off" does NOT keep is the width it took away: that is remembered
by the window rather than the document, so switching straight back on restores
it, and reopening the file tomorrow brings the outline back at the width a fresh
one wears. Undo restores it exactly, either way.

### The tool learns from the switch

**Switching a part off is remembered for the next shape you draw**, the same way
picking a colour, pulling Width or pulling Corner Radius already is. Take a
box's outline off and the next box comes out with no outline; put it back and
the next box has one, at the width you left it. The user reported the missing
half of this on 2026-09-06: the Fill switch taught the tool and the Outline
switch did not, so the outline came straight back on the next box.

The memory is per kind of shape, so taking a rectangle's outline off leaves the
ellipse and the arrow alone, and it lives with the other tool defaults, so it
survives quitting the app.

Over several layers picked at once, the switch teaches only what they agree on
(`PhotonzCore/ToolArming.swift`). Whether the part is there is never in doubt,
because the press just set it. Its thickness can be: switch two boxes of 2pt
and 10pt off and back on and they come back different, so the tool learns that
boxes have an outline and keeps the thickness it already had rather than being
handed one of theirs.

A ring round a picture, a label or a highlight is styling laid over the layer
rather than part of the shape, so it is remembered with the rest of that layer's
look, the way pulling its width under Effects already is.

### What is NOT a part

- **Opacity and Blur** are laid over the whole finished layer, whatever parts it
  has. They stay under Effects.
- **Corner Radius** rounds the fill and the outline together, and a rectangle
  with no outline at all still has rounded corners. So it is a property of the
  shape, not a setting of the outline, and it belongs with the shape's other
  properties rather than inside a part.
- **An arrow's head size** is the shape of the arrow, not a part of it.

The original complaint asked for the outline's colour, thickness and corner
radius to sit in one place. This model puts colour and thickness in one place
and leaves radius out, for the reason above: it is not the outline's. It stays
where every layer can reach it, under Effects, beside the other two things that
are laid over whatever the layer is made of.

### Naming

- Nothing that sets the width of a line is called **Thickness** any more. Inside
  the Outline part the row is **Width**, and its meaning comes from the part it
  sits in.
- **Border** disappears as a word. A picture's ring and a rectangle's ring are
  both the **Outline** part. They still differ underneath (a shape strokes its
  own path, a picture gets a ring drawn round its box) but nothing a person does
  differs, so nothing on screen should.
- A section named after the content kind (**Annotation**) is already gone; a
  section named after nothing in particular (**Effects**) keeps its name, since
  what is left in it really is laid over the top.

### Several layers picked

The parts list speaks for the whole selection, exactly as the Color section does
today, and for the same reason: a control that jumps to a different section when
you shift-click a second layer is a control you have to find again. A part
appears if **any** picked layer has one, its switch reads on only when every
picked layer that can have it does, and a row that reaches fewer layers than are
picked says so underneath, the way Fill already does.

This is why the parts do not become sections named after the shape: the heading
has to hold still when the selection changes.

## The panel

One section, headed **Appearance**, in the slot the Color section used to hold.
Inside it one row per part: the part's name, a tick, and the colour it paints.
A part that is switched ON also shows its own settings on the lines directly
below its row, at the same left edge as the row, and every switched on part
shows them at once. Ticking a part is already the person saying they want it, so
there is nothing more to press: no chevron, no remembering which part is open,
no indent.

It shipped on 2026-09-06 with the settings folded behind a chevron and one part
open at a time, which kept the section a fixed height; the user asked for the
fold to go the same day. The section is therefore as tall as what is switched on
(a shadow adds five rows), and the dock scrolls. Parts are told apart from their
settings by the tick column, which only a part row has, and by the gap: a part
sits 16 pt from the one above it and its settings sit 6 pt under its own row.
Anything a row says below itself, including the sentence about how many of the
picked layers it reaches, shares that one left edge.

A rectangle's whole panel goes from four sections to three:

| Before | After |
| --- | --- |
| Color: Fill (tick) · Outline (no tick) | Appearance: Fill · Outline · Shadow |
| Effects: Opacity · Blur · Corner Radius | Effects: Opacity · Blur · Corner Radius |
| Rectangle: Thickness | *(gone: Thickness is the Outline part's Width)* |
| Shadow: Enable Shadow · five sliders | *(gone: the Shadow row)* |

Two things did not go where the original report asked, and both are deliberate:

- **Corner Radius stays under Effects.** It is a property, not a setting of the
  outline (a box with no outline still has rounded corners), and it is ONE row
  that also rounds a screenshot, a frame and a group. Moving it into the shape's
  own section would leave every layer that is not a shape with nowhere to round
  its corners, or bring back the second Corner Radius slider that
  `CornerRadiusRow` exists to have ended.
- **A shape and a picture picked together show ONE Outline row** (settled
  2026-09-07). They used to show two, one for each kind of ring, because the
  colour underneath is stored in two different slots. A row now carries the
  colours it paints AND which of the picked layers takes each one
  (`PartColor`), so one switch, one well and one Width reach both: the shape
  gets its stroke, the picture gets its ring, in one step one undo puts back.
  A highlight keeps its own Colour row for its wash, because that stroke colour
  is the wash the highlight is made of rather than a line round anything.
- **The Outline row sits above Text, always.** It used to sit below whenever it
  was the ring kind, so picking a box beside a caption reordered the panel. One
  fixed place, so adding to the selection widens what a row answers for and
  never moves it.

### Where the code is

- `PhotonzCore/LayerParts.swift` — the model: what a part is, which parts a
  selection has, and switching the outline on and off. Tested in
  `Tests/PhotonzCoreTests/LayerPartsTests.swift`.
- `Photonz/PartsInspector.swift` — the list, the rows and their settings.
- The old `SelectionColorInspector` and `ShadowInspector` are still what Current
  draws, unchanged.

## How the list grows

Status: **built in Next** (2026-09-07), from the user's answer *one list you add
to*. Shadows are countable, an inner shadow is a Kind rather than an effect of
its own, and the plus that adds one rides the Appearance header. What is NOT
built is the Outline's Position, for the reason in "What existing documents must
keep drawing" below. Three parts fit in a fixed list. The ones people ask for next do not: an inner and an outer border, an
inner and an outer shadow, a glow, a bevel. Adding six more fixed rows is how a
panel turns into a wall. This section writes down how the list scales instead,
so that the next effect costs one entry and no new idea.

### The two ideas the whole thing turns on

**One. Inner and outer are a SETTING, not a different effect.** A border that
sits inside the edge and one that sits outside it are the same idea drawn in a
different place, so they are one part with a Position, exactly as a stroke is in
Figma and Sketch. A shadow thrown behind and one cast into the shape are one
part with a Kind. Four names people ask for collapse to two rows and two
popups, and the list stays short.

**Two. Some effects are COUNTABLE.** A second shadow is the common want: one
tight and dark for contact, one wide and soft for lift. A fixed row cannot hold
two. So the list has to accept more than one of a kind, which turns a fixed set
of rows into a list you add to and remove from. Once it is a list, the order is
visible, and anything visible has to be editable, so rows drag the way layers
do.

A bevel or an inner glow then costs one new kind and no new interaction.

### What a kind is

Every entry in Appearance is one **kind**, and a kind is described by four
things and nothing else:

| | |
| --- | --- |
| **Name** | What the row is called, and the word the add menu offers |
| **Count** | `one` — the layer has it or does not — or `many` |
| **Colour** | The one colour it paints, or none |
| **Settings** | The rows that appear under it while it is on |

That is the extension point. A kind is added by writing those four things down;
nothing about the panel, the switch, the add menu, the remove, the drag or the
document format changes to accept it.

### The kinds

| Kind | Count | Colour | Settings |
| --- | --- | --- | --- |
| Fill | one | the fill colour | none (a gradient is a kind of colour, not a setting) |
| Outline | one for now | the outline colour | Width · *(Position: not built, see below)* |
| Shadow | **many** | the shadow colour | **Kind** (Drop · Inner) · Blur · Size · Distance · Direction · Opacity |
| *Glow (next)* | many | the glow colour | Kind (Outer · Inner) · Blur · Size · Opacity |
| *Bevel (next)* | one | two colours, light and dark | Depth · Softness · Direction · Opacity |

Fill and Outline are `one` because nobody has asked for two and the row is the
same either way if they do: promoting a kind from `one` to `many` is a one word
change, not a redesign. Shadow is `many` on day one because that is the ask.

**A shadow's Kind and a border's Position are popups on the row, but the add
menu still names them in full.** The menu offers *Shadow* and *Inner shadow* as
two entries, because that is what a person is looking for and scanning a popup
they have not opened yet is not looking. Picking either adds one Shadow row with
its Kind already set. One row type, two doors into it.

### What order means

The list paints **bottom of the list first**, the same way the layer list does,
so the entry at the top of Appearance is the one nearest the eye. Drag a row and
the picture changes.

Where it is visible:

- Two drop shadows of different colours, where they overlap.
- An inner shadow above or below the fill: below, the fill covers it.
- An outline above or below an inner shadow, which decides whether the shadow
  darkens the line.

Where it is not: a single shadow and a single fill can only go one way round
that makes sense, which is why order has been invisible until now and why it
only becomes editable when a layer can hold two of something.

Today's fixed order — shadow behind, fill, then outline over the top
(`DocumentRenderer`) — is what a freshly converted layer gets, so a document
opened tomorrow paints exactly as it painted yesterday.

### Off is not remove

A row carries both, and they mean different things:

- **The tick** switches the effect off and keeps everything about it. This is
  the one that is used constantly: compare with and without.
- **The remove** takes the entry out of the list. Only entries of a `many` kind
  have one, because taking away the Fill row would leave a shape with no way to
  get its fill back except the add menu, and every rectangle would start life
  needing one.

Two ways to make something go away is the real hazard in this model. The answer
is that only countable things can be removed, so on a plain rectangle there is
exactly one gesture, the tick, and remove appears only once you have added a
second of something.

### What existing documents must keep drawing, and why Position is not built

Two facts, read out of the renderer rather than assumed. The second corrects
what this document said on 2026-09-07 before the code was read closely:

- **A picture, frame, label or group's ring is already an INSIDE border.**
  `bordered(_:box:radius:style:)` insets the box by the full width and cuts the
  middle out, so the ring sits wholly within the layer's edge.
- **A shape's own stroke is already inside its frame too.**
  `AnnotationRasterizer` insets the box by half the stroke width and then
  strokes it, so the stroke straddles that inset path and its OUTER edge lands
  exactly on the frame. Centred on the path, inside the frame.

So Inside is not one default among three: it is the only position anything in
the app has ever drawn, and it is what every existing document is wearing.

Outside is the one people ask for, and it is what makes Position expensive
rather than a popup. A shape is rasterized into a bitmap exactly the size of its
frame, and the ring round everything else is cropped to the layer's own extent,
so an outline that sits past the edge has nowhere to be drawn: the rasterizer
would need padding, the layer's reach (`renderBounds`, `previewPadding`) would
need to grow with it, and selection and hit testing follow from those. That is a
piece of work of its own and it would have swamped the list this task is about,
so Position is written down here and filed rather than half-built. Nothing about
the list has to change to accept it: it is one more setting under the Outline
row.

### More than one layer picked

The list still speaks for the whole selection, and one rule extends it: **rows
line up by position in the list, not by kind.** Two boxes that each have one
shadow show one Shadow row whose settings read Mixed where they differ. A box
with two shadows picked beside a box with one shows the first shadow as a normal
row and the second saying it reaches one of the two layers, the same sentence
Fill already says. Adding an effect adds it to every picked layer, so the lists
stay the same length as each other from then on.

### Where the code is

- `PhotonzCore/LayerParts.swift` — `LayerPart.isCountable`, `AppearanceKind`
  (what the plus offers), the shadow rows, and the four list edits: add,
  remove, move, switch. Tested in `Tests/PhotonzCoreTests/AppearanceListTests.swift`.
- `PhotonzCore/Layer.swift` — `LayerStyle.shadows` is the list, nearest the eye
  first; `shadow` still reads and writes the first one, so every caller written
  before this goes on working. `ShadowStyle` gains `kind` and `isOn`. A file
  with one shadow saves exactly the bytes it always did, and one with two writes
  the first where it has always been written so an older build still draws it.
- `PhotonzRender/DocumentRenderer.swift` — `shadowed(_:shadows:)` walks the
  list: inner shadows are cast into the layer and clipped to its silhouette,
  drop shadows go behind it nearest the eye first. Tested in
  `Tests/PhotonzRenderTests/ShadowListRenderTests.swift`.
- `Photonz/PartsInspector.swift` — the plus (on the section header, since the
  dock caps a section's height and scrolls the rest inside it), the Kind popup,
  the cross, the grip, and the row menu that does the same three things in
  words.

### What is rough, as built

- **Two shadows do not fit.** A shadow costs seven rows, so the second one's
  own row is already below the fold of the Appearance section and has to be
  scrolled to. This is the density the decision's option B was about; the user
  chose A, and the cost is now real rather than predicted.
- **A part's settings have no visible owner.** Blur, Size and Opacity under a
  Shadow row read like a second copy of the layer's own Blur and Opacity in
  Effects underneath. Reported by the user on 2026-09-07 from this very build.
- **The grip's drag is not scripted.** A synthesized press cannot start a
  SwiftUI drag, so the walk cannot carry out the reorder; the row's own menu
  (Move Up, Move Down, Remove) does the same thing and what both call is
  covered by tests.
