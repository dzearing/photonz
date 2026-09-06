# A layer is made of parts

One model for every switchable thing a layer paints: fill, outline, shadow, and
anything added later such as an inner shadow or a glow. Written down before any
of it was built, because it changes the shape of every inspector and a model
half-applied is worse than the mess it replaced.

Status: **built in Next**, behind `next-shape-parts` (on by default there).
The layout was the user's call and they took it on 2026-09-06: *one list,
settings unfold*. Current is untouched.

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
Inside it one row per part: the part's name, a tick, the colour it paints, and a
chevron where the part has settings of its own. Click the chevron (or the name)
and that part's settings unfold underneath; open another and the first folds
away, so the section stays short whatever is switched on. The part you left open
stays open as you pick other layers, and across launches.

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
- **A shape and a picture picked together show two Outline rows**, one for each
  kind of ring, each saying which of the picked layers it reaches. They are one
  part, but the colour underneath is stored in two different slots and a single
  row cannot yet paint both. Followed up separately; it does not come up in a
  single selection, which is where the panel is used.

### Where the code is

- `PhotonzCore/LayerParts.swift` — the model: what a part is, which parts a
  selection has, and switching the outline on and off. Tested in
  `Tests/PhotonzCoreTests/LayerPartsTests.swift`.
- `Photonz/PartsInspector.swift` — the list, the rows and the unfolding.
- The old `SelectionColorInspector` and `ShadowInspector` are still what Current
  draws, unchanged.
