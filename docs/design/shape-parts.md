# A layer is made of parts

One model for every switchable thing a layer paints: fill, outline, shadow, and
anything added later such as an inner shadow or a glow. Written down before any
of it was built, because it changes the shape of every inspector and a model
half-applied is worse than the mess it replaced.

Status: **model agreed here, panel layout awaiting a decision** (see the decision
card for `one-way-to-add-colour-and-remove-any-part-of-a-s`). Nothing below is
built yet.

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
| Line, arrow, highlight | Colour · Shadow |
| Text | Colour · Shadow |
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
already stored as an absent colour (`setAnnotationFill(nil)`); the outline needs
the same, a stored width of zero or an absent stroke, so that "off" is a real
document state that saves, reopens, undoes and copies like any other. Nothing
about how an existing document draws changes: a rectangle with a 4pt outline
today has its Outline part on at 4pt.

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
and leaves radius out, for the reason above: it is not the outline's. Radius
moves out of Effects and into the shape's own section beside Head Size, so it
sits with the other things that describe the shape rather than under a heading
that means "laid over the top".

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

## What is still open

Where the parts sit on the panel — one list with settings that unfold, one list
with settings always showing, or a section per part — changes the shape of every
inspector in the app, so it is a decision for the user rather than a choice to
make here. The three layouts are drawn in the decision brief at
`queue/decisions/`. Everything above this heading is settled regardless of which
one wins.
