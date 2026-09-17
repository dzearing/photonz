# SVG export — what goes out, and as what

An icon you draw in Photonz leaves as **an icon**, not as a picture of one:
Export offers SVG beside PNG, JPEG and HEIC, and what it writes is a real vector
file that any website, app or icon set can use. This is the other half of the
Pen (`vector-paths.md`): drawing a shape you cannot get out is half an answer.

Behind the Next flag `next-export-svg`, which needs `next-pen`.

## Where it lives

| Piece | Where | Why there |
| --- | --- | --- |
| The writer | `PhotonzCore/SVGExport.swift` | It is geometry and string building and nothing else: no Core Image, no AppKit, no type engine. It can be tested without a renderer, and it is. |
| The bridge | `PhotonzRender/SVGExporter.swift` | The only two things the writer cannot do for itself: a PICTURE of a layer with no vector answer (`DocumentRenderer`) and the OUTLINE of a text layer's letters (`TextRasterizer.outlinePath`, CoreText). Both are handed in as closures. |
| The way in | `Photonz/ExportDialog.swift`, `EditorState.exportSVG` | The format picker, the line that replaces the scale row, and the save panel. |

## The coordinate space: no flip

The document model counts y from the top. **So does SVG.** This is the one place
in the codebase where the two spaces already agree, so the flip
`DocumentRenderer` owns (`overview.md`) has no business here. A shape thirty
points down the canvas is thirty points down the file. Getting this wrong
produces a file that is upside down and reads as a rendering bug.

A layer is placed once, with a `transform="translate(x y)"` on its own element,
and everything inside it is written in the layer's own coordinates — the same
space the rasterizers draw in, so the numbers in the file are the numbers in the
model. A layer at the origin gets no transform at all.

## What each layer kind writes

**If you add a layer kind, you owe it a row here.** Anything not listed falls
through to a picture, which is safe and lossy, and the export says so.

| Layer | SVG | Notes |
| --- | --- | --- |
| Path | `<path d>` | A run with no handle on either end is written `L`, so a straight edge is straight; a run with handles is written `C`. Closed shapes close with `Z`. `fill-rule="evenodd"` where the shape has a hole. |
| Rectangle | `<rect>` | `rx` for even rounding. Corners rounded ONE AT A TIME become a `<path>` with arcs, which is the one rounding `<rect>` cannot say. |
| Ellipse | `<ellipse>` | |
| Line | `<line>` | Round cap, like the canvas. |
| Text | `<path>` of the letters' outlines, with a `<title>` | See "Why text is outlined" below. |
| Group | `<g transform="translate(…)">` | The nesting and the order the layers list shows. A frame's background is a `<rect>` under its children. A group that CUTS OFF what sticks out of it (a frame does by default, and so does any group with rounded corners) writes a `<clipPath>` of its box and holds its contents in one more `<g clip-path>`, so an icon drawn in a frame stays shapes. The ring round the box is written outside that cut, since a border is painted over the edge rather than cut by it. |
| Picture | `<image href="data:image/png;base64,…">` | An untouched photograph goes out as its OWN pixels — smallest file, sharpest picture. One that is cropped, turned, rounded off or wearing an effect is re-rendered through the real renderer at 2× so it looks the way it looks on the canvas. |
| Arrow | `<line>` shaft, a `<path>` or `<circle>` head, and its caption on a plate | Every number comes off `Geometry.arrowShaftEnd` / `arrowhead` / `arrowheadCircle`, the same helpers the canvas draws from. An arrow with a caption needs a type engine, because the caption is type; without one it keeps its picture and says so. |
| Highlight | `<rect style="mix-blend-mode:multiply">` | See "A highlighter paints through what is under it" below. |
| Measurement | `<path>` legs with the corner arced, a `<line>` leader, and its readout on a plate | The legs stop on the readout's outline exactly where the canvas stops them, because both read one plan (`MeasurePlan`). An alignment check writes its dashed guide, its ticks and the bracket round the offender instead. Needs a type engine for the readout. |
| Zoom callout, lens, collage | `<image>` | No vector answer yet. Each is reported. |
| A shape's softness and its shadows | `<filter>` on the shape itself | See "A shadow and a blur" below. Everything else about a halo — a glow, an inner shadow, a spread one — still falls back. |

### The plate a label sits on

An arrow's caption and a measurement's readout are the same plate: a rounded
`<rect>`, a ring round it in the same `<rect>` again, and the words as the
outline of their letters with a `<title>` carrying the string. It is sized from
the words, which is why the writer is handed a `TypeSetter` — PhotonzCore owns
no fonts, so how big "16 px" comes out at 14pt is a question only the app layer
can answer (`SVGExporter.typeSetter`).

**No plate in a file carries the soft shadow the canvas draws behind a
caption.** The lift is a filter, and Apple's SVG reader moves any filtered shape
one more step along for every transform standing above it. A label is always
inside the group that places the arrow it belongs to, so the halo would land
somewhere else entirely in Preview, Quick Look and Xcode while a browser drew it
where it belongs. Leaving it out is the one answer that looks the same in every
reader, and it costs nothing that matters: the legibility was never in the
shadow, it is in the opaque plate (`LabelPlate`), which the file carries in
full. Measured on the render-back check, the missing halo is about a quarter of
one part in 255 over the canvas.

### A highlighter paints through what is under it

A highlight is a rectangle that MULTIPLIES with the picture below it, and the
one word for that is CSS's `mix-blend-mode: multiply`. Browsers honour it.
**Apple's own SVG reader honours no blend mode at all** — not as a `style`, not
as a presentation attribute, not inside an isolated group; all three were tried
— so Preview, Quick Look and Xcode draw a flat bar of colour over the picture
where a browser draws a highlighter.

It is written anyway, because the alternative was worse in every reader. Until
this landed a highlight went out as an embedded picture, and a picture of a
highlight is its own pixels laid flat over the backdrop: it did not multiply in
a browser either. The render-back check therefore measures a highlight over
white, where multiplying and painting flat agree, and a separate test reads the
file for the blend word.

### Paint

A flat colour writes `fill="#RRGGBB"`, with `fill-opacity` on its own where the
colour has alpha in it — the same for `stroke`. A gradient writes a definition
in `<defs>` and points at it:

* **Linear** → `<linearGradient gradientUnits="userSpaceOnUse">` with the ends
  from `Paint.linearEnds(in:)`, so the ramp is aimed exactly where the canvas
  aims it.
* **Radial** → `<radialGradient>` with `Paint.centerPoint(in:)` and
  `Paint.radialRadius(in:)`.
* **Angular** → nothing. SVG has no conic ramp, so a swept shape falls back to a
  picture and says why.

### The line's position

A centred line is a plain `stroke`. Inside and outside are not things SVG can
say, so the file does exactly what `PathRasterizer` does: it draws the line
DOUBLE width and cuts off the half that should not be there — a `<clipPath>` of
the shape for an inside line, a `<mask>` for an outside one. On a rectangle or
an oval it is plain geometry instead: the box is inset by half the width, which
needs no cutting at all.

A drawn box's edge is a **Border in the Effects list**
(`OutlineRetirement.swift`), not a stroke on the shape, so the ring is written
from the effects: the band from the outer edge inwards by its own width, which
is a stroke riding half a width in from there. Several borders write in the
order the list paints them, foot first.

## Why text is outlined

A `<text>` element renders in whatever face the machine opening the file happens
to have. An icon handed to somebody without that font comes out wrong, and an
icon is exactly the thing that gets handed to somebody else. So the letters are
written as their outlines, laid out through the same framesetter the canvas
draws with, and the words themselves ride along in a `<title>` so the file can
still be searched and read aloud.

The cost is real and deliberate: **you cannot retype the words in the exported
file.** That is the right trade for a file whose job is to look the same
everywhere. A text layer wearing a halo round its letters (`BorderFollows`)
falls back to a picture instead, because that halo is painted into the words.

## What "clean" means here

* No `<defs>` block unless something needed one.
* No transform that does nothing: a layer at the origin gets none.
* No group that holds nothing, and no wrapper round a layer that turned out to
  be one shape.
* Two-space indentation, so a person can open it in an editor and recognise
  their own drawing.
* The only generated names are gradient and clip ids, one number each.

## When the drawing moves

A document whose layers are told to change over time can go out as a file that
**plays it itself** (`Sources/PhotonzCore/SVGMotionExport.swift`). Nothing about
the still file changes: a drawing with nothing moving in it writes the same
bytes it always did, and an animated one is the same shapes with animation
elements threaded through them.

**One lap, stated as fractions of itself.** Every motion in a document shares
the lap the canvas and the timing strip use, and each one is written as a list
of moments inside that lap, each moment a fraction of it. Milliseconds on
screen, fractions in the file. Two animations with two different durations would
drift apart on the first repeat, which would quietly destroy the one thing a lag
between two parts of one drawing is for.

**SMIL, not CSS keyframes.** A turn has to say the point it turns ABOUT, and
`<animateTransform type="rotate">` says it in plain user units in the value
itself. The CSS answer is `transform-origin`, whose meaning inside an SVG
depends on `transform-box` and on whether the transform arrived as an attribute
or as a property — and a bell hanging from the wrong point is the exact mistake
`MotionPivot` exists to prevent.

| What moves | What the file says |
| --- | --- |
| Position | `animateTransform type="translate"`, as a move from where it was drawn |
| Rotation | `animateTransform type="rotate"`, about the pivot, in canvas units |
| Scale | `animateTransform type="scale"`, between a step out to the middle and back |
| Opacity | `animate attributeName="opacity"` |
| Colour | `animate` on `fill` or `stroke`, on a group the shape INHERITS from |
| Line width | `animate attributeName="stroke-width"`, inherited the same way |

Curves SVG can state are stated — `keySplines` for the four standard eases and
for one you drew — and curves it cannot are drawn point by point instead: back
and elastic overshoot, and SMIL keeps both control points inside the unit
square. Steps become `calcMode="discrete"`. Every value is asked of the motion
ITSELF rather than worked out again, so the file and the canvas can never
disagree about what a curve or a there-and-back means.

**A host that strips it still gets the icon.** Every animated attribute is also
written as an ordinary attribute on the group that carries the animation, so a
reader that throws the animation away draws the drawing at the top of its lap
rather than a black square. That is checked by rendering the file back through
the system's own SVG reader and comparing it with the canvas
(`anAnimatedFileStillDrawsTheIconWhereTheLapStarts`).

## A shadow and a blur

A shape wearing a blur or a drop shadow goes out **as a shape**, with one
`<filter>` on it. A shadow is the commonest thing to put on an icon, so it was
also the commonest reason an icon left the app as a flat picture.

The filter says the same thing the canvas does, in the same order: the layer's
own softness first, then each shadow cast from that softened silhouette, then
the drawing laid over the lot. The foot of the Appearance list is furthest from
the eye, exactly as `DocumentRenderer.shadowed` stacks them.

```
<filter id="effect-1" filterUnits="userSpaceOnUse" x="-14" y="-14" width="148" height="158"
        color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="6" result="shadow-1-soft"/>
  <feOffset in="shadow-1-soft" dx="4" dy="8" result="shadow-1-cast"/>
  <feFlood flood-color="#102040" flood-opacity="0.5" result="shadow-1-ink"/>
  <feComposite in="shadow-1-ink" in2="shadow-1-cast" operator="in" result="shadow-1"/>
  <feComposite in="SourceGraphic" in2="shadow-1" operator="over"/>
</filter>
```

Four things in that are not the obvious way to write it, and each of them is
there because of what **Apple's own SVG reader** does with the obvious way. That
reader is CoreSVG: it is what `NSImage` uses, which makes it the thing the
render-back check measures against, and it is also Preview, Quick Look and
Xcode, which makes it the thing a person sees when they double-click the icon
this app just wrote. Every one of these was measured rather than assumed
(`queue/audits`, and the task log of "A shadow survives the trip out to SVG").

* **Never `feDropShadow`.** CoreSVG parses it and draws nothing for it: two
  shadows with nothing in common render byte for byte identical. The five
  primitives it is shorthand for all work, so the file says them.
* **Never `feMerge`.** Same story. `feComposite operator="over"` stacks the
  shadows instead, and is just as old and just as portable.
* **`color-interpolation-filters="sRGB"`.** SVG's default is to mix a filter in
  linear light, which comes back a different shade from the canvas.
* **The filter rides the shape, and the shape carries its own `transform`.**
  CoreSVG draws a filtered element one extra step along for every transform
  standing ABOVE it, so a shadowed shape inside a group that sits anywhere but
  the canvas corner lands in the wrong place. A transform on the element itself
  it gets right.

### A viewport where a transform would not do

Two shapes people draw all the time could not wear a shadow under those rules:
one with a **ring** round it, because a ring is a second element and a filter on
the `<g>` holding the two is ignored outright; and one drawn **inside a frame**,
because the frame's own `transform` is a transform standing above it.

Both are answered by the one element SVG already has for moving something
without a transform: a nested `<svg>` with an `x`, a `y`, a `width`, a `height`
and a `viewBox`. CoreSVG honours a filter on one of those, and a viewport is not
a transform, so nothing above the shape is one either.

* **A drawing in more than one piece** goes inside a viewport that carries the
  filter. Its `viewBox` is the SAME rectangle as its `x`/`y`/`width`/`height`,
  so the space inside it is the space it sits in, and one `<g transform>` below
  the filter puts the pieces in place. This matters: give a filtered viewport a
  `viewBox` shifted from where it is placed and CoreSVG draws the whole thing
  twice, once where it belongs and once a step along.
* **A group holding anything filtered** places what is in it with a viewport
  instead of a `<g transform>`. Here the `viewBox` IS shifted — by the group's
  frame origin — because that is what does the placing, and it is safe because
  this viewport carries no filter. It is bought only where there is a filter
  inside to save (`SVGExport.placesByViewport`), so an ordinary group is still
  the plain `<g transform>` the layers list reads as.
* **The viewport is the drawing's whole reach, `Layer.renderBounds`, never its
  frame.** CoreSVG clips a nested viewport whatever `overflow` says, and a
  shadow falls outside the box it is cast from. `overflow="visible"` is written
  anyway, for the readers that do honour it.
* **A turned group cannot do this**, since a turn is a transform and nothing
  else says one. What is inside it keeps its picture, and the sheet says why.

### The region, and whose units it is in

A filter clips whatever falls outside its region, and the region a file gets for
free is a tenth of the shape's box on each side, which cuts a long shadow off in
mid air. So the region is stated outright, from `Layer.renderBounds` — the same
reach a drag sprite and a dirty rect already use.

In whose user units, though, is a question the readers answer differently:
a browser reads them in the shape's own space, CoreSVG in the space the shape is
placed in. The two differ by exactly where the layer sits. Rather than pick one
and be wrong in the other, the region covers the reach in **both**: a rectangle
bigger than either needs, and right whichever is meant. A region larger than
necessary costs a bigger buffer and nothing else.

### What still keeps its picture, and why

| It wears | Why it cannot go out as a shape |
| --- | --- |
| A glow | A glow is a halo grown from the silhouette before it is blurred, which is `feMorphology`, and that is a square-cornered grow in a file and a round one on the canvas. |
| An inner shadow | Same shape of problem, cast the other way. |
| A shadow with spread | Same: spread is the grow. |
| A fade, with any filter at all | CoreSVG applies a fade twice to anything filtered, once to the drawing going in and once to what comes out, so a half-faded shape comes back a quarter of itself. |
| A turn | The canvas turns the shape and throws the shadow afterwards, so the shadow falls the same way whatever the angle. A filter turns with the thing it is on. |
| A turn standing over it | A group that is TURNED. A turn has to be a transform and no viewport says one, so what is inside keeps its picture. A group that only MOVES it is fine: see the viewport note above. |
| Motion standing over it, in the file that PLAYS | A layer's motion is written as groups that slide and turn it, so anything inside is under a transform. Only in the animated file: the still one has no such groups and the shadow survives. |

Each of these is named on the Export sheet in plain words before you save, the
same as every other fallback.

## Where it is going, asked before what format

`SVGHandoff` is the model behind the Export sheet's first question. The same
animated SVG plays on a web page, is thrown away by a design tool, and is
stripped out of a README, so a list of formats cannot tell you what will happen
to what you just made. The sheet asks the destination, moves the format to the
one that survives, and lists what makes the trip and what does not — including
the one line nothing carries: **a drawing in a page receives no clicks**.

## The canvas it was drawn on

A blank canvas is a REAL full-size bitmap of white (`SolidImage`), because a
marquee fill or an eraser stroke on the background has to redraw at full
resolution. That is right on the canvas and wrong in a file: an icon drawn on
one used to export with a white rectangle the size of the canvas behind it, so
handed to a developer it could not sit on a coloured page or a dark theme
without the box showing.

`SVGExport.backdrop(in:flatImages:)` names the layer that is only the canvas:
the **bottom-most layer anyone can see**, where it is one flat colour reaching
every edge, with no transform, no blend, and no effect on it. Everything else
is part of the drawing. That is what keeps the answer safe:

* a **screenshot** is a photograph rather than a flat colour, so it is never
  the canvas and its picture always goes out;
* a **screen exported as a frame** is scoped to the frame, whose own surface is
  inside it rather than under it, so it always keeps its background;
* a flat swatch **drawn on top** of the canvas is not the bottom layer, and a
  flat colour that does not reach the edges is not the canvas either.

`SVGExport.Background` says what to do about it, and `.drop` leaves that one
top-level layer out. The Export sheet asks with **Include the background**,
unticked, with a swatch of the colour that would go in and one line saying what
the file will be — and the row is **not there at all** when there is no canvas
to leave out, rather than sitting dimmed with nothing to say. The answer is not
remembered between exports: it is shown on the sheet every time instead, so it
can never be a setting somebody left on months ago quietly putting a white box
back.

Reading which bitmaps are flat walks their pixels (36 ms for a 12 megapixel
canvas), so the Export sheet asks **once when it opens and whenever the target
changes**, and hands the same answer to the background row, the fallback lines,
the photograph lines and the hand-off list.

## Saying what it could not do

`SVGExport.fallbacks(in:)` answers the same question the writer answers, without
writing anything, so the **Export sheet says it before you save**: which layers
go out as pictures, and why, in plain words. Finding out afterwards, by opening
the file, is the failure this exists to prevent.

## How it is checked

By **rendering the file back**, never by reading the text
(`Tests/PhotonzRenderTests/SVGExportRenderTests.swift`). macOS can rasterize an
SVG through `NSImage`, so every case — a path, a rounded box, an oval, a line, a
group, an inside line, an outside line, a hole, a linear ramp, a radial ramp,
outlined words, a shadowed shape, a ringed shadowed shape, a shadowed shape in a
group, one in a frame, one two groups deep, a photograph, an arrow, its endings,
its caption, a highlight, a caliper, a moved readout, an alignment check — is drawn
twice, once by the app
and once by the system's own SVG reader, and the two pictures must agree to
within one part in 255 averaged over the canvas. `Tests/PhotonzCoreTests/SVGExportTests.swift`
covers the writing itself.

## Known rough edges

* **A zoom callout, a lens and a collage still fall back to pictures.** An
  arrow, a highlight and a measurement no longer do.
* **A caption's plate loses its drop shadow**, and a highlight's blend is drawn
  only by browsers. Both are above: the reasons are Apple's SVG reader, and both
  are the least-bad answer rather than an oversight.
* **A glow, an inner shadow and a spread shadow still cost a shape its
  vectors**, and so does a shadow on a shape that is faded, turned, or held by
  a group that is turned. See "A shadow and a blur" above for the table and the
  reasons. A plain drop shadow and a blur go out as shapes, ring or no ring,
  frame or no frame.
* **A shadow comes back a different SHADE wherever it is see-through.** The
  canvas mixes a shadow into what is under it in linear light and every SVG
  reader mixes it in sRGB, so a 55% black shadow over a white frame comes back
  134 where the canvas draws 192, and a coloured shadow over nothing at all
  comes back its own colour where the canvas draws a washed-out one. Nothing in
  the file can ask a reader to mix in linear light. The placing is exact: the
  same shape over nothing is 0.002 off.
* **A sweeping gradient falls back.** A conic ramp can be approximated with
  wedges, at the cost of a big file.
* **A shape whose LAYER box is rounded off falls back** (as opposed to the
  shape's own corners). A GROUP that cuts off what sticks out of it does not:
  it writes a `<clipPath>`.
* **Anything moving inside a layer that goes out as a picture stops moving.**
  The picture holds one moment of it. Each piece is named in the result's
  `unmoved` list, by its own name, so the Export sheet says so before you save.
* **A blend mode on a LAYER still falls back to a picture.** Only a highlight,
  whose mixing is part of what it is, writes `mix-blend-mode`, and only because
  its picture was wrong everywhere.
* **A fallback picture is rasterized at 2×.** It is the one part of the file
  that does not scale.
* **A turn on a layer that is also flipped or skewed does not animate.** The two
  cannot be separated out of one matrix, so the turn is dropped and named in the
  result's `unmoved` list rather than turning about the wrong thing.
* **A colour or a line width on a shape the file draws in two halves** — an
  inside or an outside line — is dropped the same way, because the width a
  group hands down would reach the wrong one of the two.
