# A shape can be any path

Straight edges and curves in one outline, with as many points as you like. The
foundation under the Pen, under boolean operations, and under SVG export: none
of those can start until a path exists as a thing the document can hold and the
canvas can draw.

Status: **built in Next** (2026-09-13). The model, the drawing, the geometry,
the way it takes colour, and the **Pen** that lays one down (`next-pen`). There
is no anchor EDITING yet — moving, converting and deleting the points of a path
that already exists — which is the slice after this one.

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

## The Pen

`Sources/PhotonzCore/PenDrawing.swift` (`PenSession`) and
`Sources/Photonz/CanvasPen.swift`. Every decision the gesture makes is in the
first, tested; the second converts between the view and the document, draws the
chrome, and hands one finished `PathContent` to `EditorState.addPath`, which
commits ONE layer through `History.perform`. Nothing enters the document until
the path ends, which is why stepping back through anchors is the session's job
rather than undo's.

### The three that decide whether it feels right

**Four view points of travel is the line between a click and a drag**
(`PenSession.dragThreshold`), which is what the rest of the app already calls
that difference (`AnnotationDrag.isClick`). It is latched: a drag that wanders
back to where it started is still a drag, or the anchor would flicker between a
corner and a curve under the hand. It is measured on SCREEN, so it means the
same thing at 8× as at 25%.

**The run to the pointer is redrawn on every mouse move**, not on presses, and
it is drawn in the ink the finished shape will wear. When the pointer is over
the first anchor the preview shows the shape CLOSED and faintly filled, so what
the click would give you is on screen before you commit to it.

**Finishing is said out loud.** A chip under the canvas stays up the whole time
the Pen is in hand and its line changes as the path grows; at three anchors it
reads "Click the first point to close the shape. Return finishes it open, Esc
discards it." Return and Escape do OPPOSITE things and that is the only place a
person is told so. Clicking the last anchor again also finishes, for anyone who
never thinks to press Return — which also means a double click ends a path, for
free, since the second click of one lands on the anchor the first just placed.

### Option: the rule that makes an icon drawable

Option means one thing in both places it can land: **the two sides of this
anchor are not tied together.**

* Dragging a NEW anchor out with Option held sets only the handle that leaves,
  so the edge arriving stays straight.
* Pressing Option on the anchor just placed pulls that anchor's outgoing handle
  back in, so the next edge leaves straight.

Between them those two place the half-smooth anchors a rounded corner is made
of — line, quarter round, line — and they are what Option does in every other
pen, so nobody has to be told. Without them a path drawn with the Pen can only
be all corners or all curves, and a rounded rectangle comes out with four bowed
edges.

### The rest of it

Shift puts the next anchor on the nearest of the usual angles from the last one,
keeping the distance travelled, which is the rule every constrained drag in the
app follows. It is applied the moment Shift goes down rather than at the next
mouse move.

Command Z while drawing steps back ONE anchor. It is taken in the canvas's
`performKeyEquivalent`, because a key equivalent never reaches a view's
`keyDown`: the window offers it to the view hierarchy before the Edit menu. Once
there is nothing left to step back through the pen stops answering and Command Z
means what it always means.

A path arrives wearing what a new box wears — the redline red, 4pt of line,
filled when it closed and no fill at all when it did not, because an open path
is a line. The Pen carries no colour capsule on the tool bar: the Appearance
panel repaints the path it just made, and a second place to set the same two
colours with nothing behind it is noise.

**What the mock asked for and did not get.** `vector-wt.html` closes a path from
a Close path button in the Properties panel, on ⇧⌘J. Clicking the first anchor
is what a person actually does and what every other pen does, so that is what
this builds; the panel's Path section (anchor type, node coordinates, Close
path) belongs with the editing slice, because node coordinate fields with no way
to drag a node are decoration.

## What the next slices add

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
* **The Pen hands back to Select after one path**, the way every other drawing
  tool does. An icon is several shapes in a row, so this is the first thing to
  reconsider if drawing an icon feels like work.
* **There is no way to place a half-smooth anchor without Option**, and the
  chip does not mention Option. A pen user will try it; a newcomer will not need
  it. Whether it deserves a line on screen is a question for the audit.
