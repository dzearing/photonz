# A shape can be any path

Straight edges and curves in one outline, with as many points as you like. The
foundation under the Pen, under boolean operations, and under SVG export: none
of those can start until a path exists as a thing the document can hold and the
canvas can draw.

Status: **built in Next** (2026-09-13). The model, the drawing, the geometry and
the way it takes colour. There is NO Pen tool and no anchor editing yet: those
are the two slices after this one, and this document says where they attach.

## The words

Fixed here so the app, the mocks and the code all say the same thing. They are
the words `docs/design/mocks/pages/vector-wt.html` already uses.

| Word | What it means |
| --- | --- |
| **path** | The whole shape: a run of anchors, open or closed. |
| **anchor** | One point the outline passes through. |
| **handle** | The lever that bends the outline on one side of an anchor. |
| **corner** | An anchor whose two sides are independent. A hard turn. |
| **smooth** | An anchor whose two handles are kept in line, so the outline runs through it without a kink. |
| **run** / **segment** | The stretch of outline between two anchors. |

## The model

`Sources/PhotonzCore/VectorPath.swift`, pure and Codable like everything else in
the model. A path is a new kind of layer CONTENT — `LayerContent.path` — beside
image, text, annotation, measure and group. It is deliberately NOT a sixth
`AnnotationShape`: an annotation is a two-point mark built from a `start` and an
`end`, and everything that touches one assumes those two points exist. A path
has as many points as it likes.

```swift
PathAnchor { point, handleIn: CGPoint?, handleOut: CGPoint?, kind: .corner | .smooth }
PathContent { anchors, isClosed, paint, strokeWidth, strokePosition, fill, fillRule }
```

### The decision that matters: how an anchor holds its handles

Three choices, each made on purpose, because the editing slice has to break and
rejoin these relationships and a model that cannot say something now has to be
rewritten later.

**Handles are stored RELATIVE to their anchor**, as an offset from `point`
rather than as an absolute position. Moving an anchor then drags its curve with
it for nothing; mirroring one handle onto the other is a negation rather than a
reflection about a moving origin; and scaling a path multiplies points and
handles by exactly the same two numbers.

**Either handle may be absent, independently.** That is what makes a
**half-smooth** anchor expressible: `handleIn` nil with `handleOut` set is a
point that a straight edge arrives at and a curve leaves from. It is the
commonest thing in a real icon — a rounded-off rectangle, a teardrop, a shield —
and a model that forced both handles to exist would have to fake it with a
zero-length handle and then work out, every time, whether a zero meant "straight"
or "dragged all the way in".

**`kind` is intent, not geometry.** `smooth` is the PROMISE that the two handles
stay in line; `corner` is the promise that they are independent. Nothing that
DRAWS a path ever reads it — the drawing reads the handles — so a smooth anchor
can carry two handles of different lengths, exactly as it does in every drawing
app. `PathAnchor.alignHandles(keeping:)` is the one place the promise is kept,
and the Pen and the anchor editor call it when a handle is dragged.

A run with no handle at either end is a STRAIGHT line and says so
(`PathSegment.isStraight`), so `PathRasterizer` emits `addLine` rather than a
cubic that happens to look flat.

## How it fits the app

### Appearance and Effects

A path arrives with the two paints a shape has and needs no new colour
machinery: `ColorSlot.fill` and `ColorSlot.stroke`, the same two slots a
rectangle and a line already use. So a saved colour, a gradient and a colour
style all reach a path by the route they already take, and the Appearance panel
draws its rows without being taught anything.

The fill slot is only offered once the path CLOSES, because an open path has no
inside to paint. The fill is stored either way, so closing a path you had
painted brings its colour back rather than handing you a blank row.

**A path's edge is its OWN stroke, not a Border in the Effects list.** Every
other filled shape had its edge retired into Effects
(`OutlineRetirement.swift`), and a path cannot follow: a Border is a ring hugging
the layer's BOX, and a box round an arbitrary outline is a rectangle round a
shape that is not one — the exact bug an ellipse hit on 2026-09-08
(`RingShape.swift`). So a path joins the line and the arrow as a shape that IS
its stroke, `drawsItsOwnOutline` is true for it, and the Thickness and Colour
rows read the shape's own settings.

Everything in the Effects list — shadow, glow, blur, opacity, blend mode —
reaches a path unchanged, because those are applied to the layer's rendered
picture and know nothing about what drew it.

### Where the line sits

`strokePosition` is the same `BorderPosition` every other edge uses: inside,
centred or outside. **Centred is a path's default**, which is what every vector
tool draws and the only one of the three that means anything on an open path.
There is no such thing as an arbitrary outline inset by half a line width, so
inside and outside are drawn by stroking at DOUBLE width and clipping the half
that should not be there — the survivor is exactly a line of `width` on the
chosen side, and it follows every curve for free.

An open path reads `inside` and `outside` as `center`
(`effectiveStrokePosition`), because a line has no inside to be within.

### Its box, and the box you see round it

A path layer's `frame` is the box the OUTLINE actually fills — curve bulge
included, worked out from the cubics' turning points rather than from the
control points (`Bezier.extent`). A handle 40 long only bulges 30, so a box
drawn round the control points would sit well clear of the ink.

`PathBuilder.layer` re-states the anchors against that box on the way in, so a
path's numbers are always its own layer's numbers and moving the layer never
touches them.

The blue selection outline (`Layer.drawnBounds`) is that box plus however far
the line reaches past it, so a centred 10pt stroke shows 5 points of chrome on
every side and nothing the shape draws is left outside the outline.

### Clicking one

A path is hit where the SHAPE is, not where its box is (`PathContent.isHit`):
a filled shape takes a click anywhere inside it, and a shape with no fill — plus
every open path, which has no inside at all — takes a click near its line and
nowhere else, with the same six screen points of forgiveness a thin arrow gets.
Without this the empty corner of a squiggle's bounding box would swallow clicks
meant for whatever is behind it.

`fillRule` decides what "inside" means where an outline crosses itself, so an
icon can have a hole in it. Non-zero is the default, as everywhere.

### Moving, resizing, turning

`resized(to:)` routes a path through `PathBuilder.resized`, which multiplies
every anchor AND every handle by the box's two scale factors. Scaling a cubic's
control points is exactly the scaled cubic, so the curves scale rather than
distorting. The LINE WIDTH is left alone, which is the rule the whole app
follows: what is drawn from its box grows with the box, what is measured in
points holds still.

Moving touches nothing: the anchors are stored against the layer's own corner.
Turning is `LayerTransform` like every other layer, applied to the rendered
picture, and the hit test steps the click back through it.

All of this goes through `History.perform` like every other mutation, so every
change is undoable.

## Drawing it

`Sources/PhotonzRender/PathRasterizer.swift`, modelled on
`AnnotationRasterizer`: it draws in the layer's own top-left space, bakes at the
resolution the shape is about to be seen at, and pads the bitmap symmetrically
by the stroke's reach so a centred line has somewhere to go.

The inside is painted first and the edge over it, which is what makes an inside
line read as inset. A flat fill is filled outright; a gradient is poured through
the shape as a clip, honouring the fill rule, so a gradient icon keeps the hole
a flat one has.

Corners join with MITERS, because a corner anchor exists to be sharp and a round
join would quietly curve every one of them. Open ends get round caps, which is
what every other stroke in the app ends in. Neither is settable yet; see below.

## What the next slices add

* **The Pen** (`P`, already reserved). Placing anchors, dragging handles as you
  place them, closing a path, finishing an open one. This slice deliberately
  contains no gesture at all, so the model is not shaped by whichever
  interaction happened to be written first.
* **Anchor editing.** Dragging anchors and handles, switching an anchor between
  corner and smooth, breaking one side loose. `alignHandles(keeping:)` and the
  optional handles are the two hooks it needs.
* **Booleans** (`docs/design/mocks/pages/draw-boolean.html`) — union, subtract,
  intersect. `flattened()` and `containsInside` are the start of the geometry.
* **SVG export**, under `icon-export`. A path is already exactly the cubic data
  an SVG `d` attribute wants.

## Known rough edges

* **A Border added to a path from the Effects list still follows its BOX.** It
  is the ellipse bug in a new place, and the fix is the same one: the ring has
  to ask the layer for its silhouette. A path arrives with its own edge, so
  nobody has to add one, but the row is there and it will draw a rectangle.
* **Line cap and line join are not settable.** Icons want butt caps and a miter
  limit sooner or later.
* **Nothing creates a path in the app.** Until the Pen lands, the only path
  anybody can look at is `Scripts/playtest/fixtures/path-demo.photonz`, which
  the `path-demo` walk opens.
