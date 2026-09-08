# Taking Outline out of Appearance

## What you are looking at today

Pick a rectangle and the right hand panel shows two sections one under the other.

**Appearance** is what the shape simply has. It lists Opacity, Fill, **Outline**
(with a colour, a Width and a Position), and Corner Radius.

**Effects** is a list you add to. It starts empty, and the plus on its header
offers Shadow, **Border** and Blur. A Border also has a colour, a Width and a
Position.

So a rectangle can end up with an Outline set to 4pt Inside in one section and a
Border set to 2pt Outside in the other, both drawing a line round the same box,
neither saying which is which. That is what you reported, and asking for Outline
to come out is the right call: one line round a shape should be one control.

## What only you can settle

Outline is not just a row. It is what a shape tool gives you when you draw. Press
**R** today and you get a filled box **with a line round it**, in the outline
colour the tool bar is holding. Take the row away and something has to happen to
that line.

That is the whole question, and it is one you would notice every time you draw.

### If shapes arrive with their edge already listed

Drawing is exactly what it is today: press R, drag, and you get a filled box with
a line round it. The line is listed in Effects as **Border**, with its colour,
its Position and its Width right there. You can widen it, push it outside the
edge, drag a second one under it, or take it off with the cross.

The cost is a rule bending. The Effects list has been "the things you added",
and a fresh shape would now arrive with one row already in it.

### If shapes arrive bare

Press R, drag, and you get a plain filled box. No line. When you want one you
press the plus on the Effects header and choose Border, and it arrives already
looking like something.

The cost is a move. Most shapes you draw in a redline or a mock have an edge, so
this is one extra click most of the time. It also leaves the tool bar's outline
colour swatch with nothing to paint until a border exists, which makes setting a
colour before you draw stop meaning anything.

### If Outline stays

Nothing changes and the two controls go on sitting one above the other. This is
the option that ends the task rather than handing it back, so pick it only if you
would rather live with the duplication than change what drawing gives you.

## What has already shipped from this task

The other half of what you asked for is done and is in the build now: **an
effect's colour is a setting of that effect.** The Border row's header carries
only its name, its tick, its grip and its cross; the first row under the rule is
**Color**, with the same well and the same saved colours menu every other colour
in the app has. A shadow's colour reads exactly the same way, so the list reads
one way. See the audit `2026-09-08-effect-colour.json`.

## One thing to fix first, whichever you pick

A Border today draws a **rounded rectangle round the layer's box**, never the
shape's own path. Add one to an ellipse and you get a black square round a red
oval. So "a shape's edge is drawn only by a Border" cannot be true until a Border
can follow a shape. That is queued as its own task, *"A border you add to an
ellipse follows the ellipse"*, with the reproduction in its notes.

A line and an arrow are deliberately outside all of this. Their stroke IS the
layer, so it is a colour they always have rather than a line you can take off,
and it already reads as a Color row rather than an Outline row.

## Where to look

- The app: draw a rectangle with **R**, then add a Border from the plus on the
  Effects header, and read the two sections against each other.
- The written model: `docs/design/shape-parts.md`, sections "Appearance and
  Effects" and "Outline in Appearance, Border in Effects".
