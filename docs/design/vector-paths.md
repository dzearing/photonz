# A shape can be any path

Straight edges and curves in one outline, with as many points as you like. The
foundation under the Pen, under boolean operations, and under SVG export: none
of those can start until a path exists as a thing the document can hold and the
canvas can draw.

Status: **built in Next** (2026-09-13). The model, the drawing, the geometry,
the way it takes colour, the **Pen** that lays one down (`next-pen`), and
**reshaping one afterwards** (`next-reshape-a-path`): moving points, pulling
their levers, turning a corner into a bend, adding a point on a run and taking
one out. See "Reshaping one" below.

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

### On the grid

An icon is drawn on graph paper, so a Pen point lands on the graph paper. With
the grid showing and Snap to grid on, a click puts its anchor on the nearest
crossing of the lines the canvas is DRAWING — the same lines a drag pulls to,
read from `CanvasNSView.canvasNudgeGrid`, so a box dragged with the Rectangle
tool and a box clicked out with the Pen sit on the same lines. Holding Command
puts the point exactly under the pointer, which is the one escape from the
magnets everywhere else on the canvas. Grid off, or Snap to grid off, and the
Pen places points exactly where it always did.

Three consequences worth knowing:

* **The preview is the promise.** The run to the pointer already reaches the
  crossing the click will land on, so you see where the point goes before you
  commit it.
* **Closing gets easier, not harder.** A click lands on the first anchor when
  the point it would PLACE is that anchor, rather than when the pointer is
  within eight points of it. Half a cell is wider than eight points, so without
  that a circle back to the start drops a second anchor exactly on top of the
  first and the shape never closes.
* **Shift still owns the angle.** A constrained run takes the grid only on the
  axis the angle left free: a level run from a point already on a line ends on
  a crossing, and a 45 degree run keeps its 45 degrees rather than being bent
  onto the paper.

The handles pulled out of a point are NOT quantized. A handle end is not a point
on the outline, it is how hard the curve bends there, and on a 32pt grid every
curve would have to bend in whole cells; a handle shorter than half a cell would
collapse to nothing and throw away the curve you just pulled. It is measured
from the anchor's snapped home, though, so the curve hangs off the right place.
`Scripts/playtest/pen-on-the-grid-walk.json` is the walk.

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

**The Pen stays in your hand.** Every other drawing tool hands back to Select
the moment it has drawn its one thing, which is right for a tool that draws one
thing per errand. An icon is five or six shapes in a row, so the Pen keeps
itself: a finished path is added, and picked, and the Pen is still the tool in
hand for the next shape. Escape with nothing being drawn is the way out — it
puts the Pen down and hands back to Select with the shape just drawn still
picked, so the old ending is one press away — and V, or any other tool button,
puts it down as it always did. The chip's opening line carries that way out,
because it is the line on screen between one shape and the next.
`Scripts/playtest/pen-stays-in-hand-walk.json` is the walk that holds all of it.

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

## Reshaping one

`Sources/PhotonzCore/PathEditing.swift` and `Sources/Photonz/CanvasPathEdit.swift`,
split the same way the Pen is: every decision about what the new shape IS lives
in the first and is tested there, and the second converts between the view and
the layer's own space, draws the chrome and hands each change to the editor.

### A path shows its points when it is picked

No mode, no second tool, no letter to learn. Pick a path with Select and its
points are on it; click one and its levers appear.

That is the bargain a line and an arrow already make in this app: what you edit
a shape BY is what its selection offers, and neither of them shows the eight
frame handles either (`Layer.hasEndpointHandles`). A path follows, for a reason
the probe made obvious: eight blue squares round the box and a dot on every
point are the same colour in the same places, and on a triangle three of the
points land exactly under three of the handles and vanish into them. So a path
showing its points wears no frame handles, its box still draws as the dashed
outline, and **the Position and Size fields still resize it** —
`allowsFrameResize` stays true, only the chrome and the press stand down.

A path inside a copy offers nothing, like every other layer that offers no
handles. Neither does one on a SLANT: reshaping moves the box the shape sits in
and a turn is measured about the middle of that box, so a point dragged on a
turned path would swing the whole shape round under the hand. Straightening it
in the A field brings the points back.

### The gestures

| What you do | What happens |
| --- | --- |
| Drag a point | It moves; the curves either side travel with it, because handles are offsets. |
| Click a point | It is picked, and only IT shows its levers. |
| ⇧ click | Gathers more points; arrow keys nudge every one of them, ⇧ by ten. |
| Drag a lever | Bends that side. On a smooth point the far lever swings round to match, keeping its own length. |
| ⌥ drag a lever | The same, with the two sides freed from each other: the far one holds still. |
| ⌥ click a lever | Pulls that lever in, so that side runs straight. A point curved on one side and straight on the other, which is what a rounded corner is made of. |
| Double click a point | Hard corner becomes a smooth bend, and again turns it back. It is also how a broken point is JOINED: both sides come back in line. |
| Double click the outline | Adds a point exactly where you clicked. |
| Delete | Takes the picked points out, the curve closing over the gap. With no point picked it still deletes the layer. |
| Escape | Lets the points go, before it lets the layer go. |

A square dot is a hard corner and a round one is a smooth bend, so what a point
IS can be read off the canvas. A picked one is filled in the accent instead of
hollow. The chip under the canvas carries the three gestures nobody guesses,
one line at a time as what is picked changes.

### The two that are real geometry

**Adding a point does not change the shape.** Splitting a cubic at a parameter
has an exact answer — de Casteljau — and the two halves are the same curve
written twice, to the last decimal place. `PathEditingTests` compares the halves
against the original cubic at 65 places rather than against a flattened outline,
because flattening has an error thousands of times larger than the one that test
exists to catch. A handle that was ABSENT stays absent, so splitting a straight
run gives two straight runs; and a straight run is split along the LINE rather
than along its degenerate cubic, which travels unevenly (a quarter of the way
along that cubic is 15.6% of the way along the edge).

**Taking a point out undoes the split.** Where a point came from a split, the
parameter is written in its own two levers: the point sits exactly that far
along the line between them, so `t = |handleIn| / (|handleIn| + |handleOut|)`
recovers it and stretching the outer handles by `1/t` and `1/(1-t)` puts the
original curve back to within 1e-14. Where the point was placed by hand, the
lengths of the runs either side stand in, which is close enough to look right.

### One undo step each

A drag previews through `EditorState.previewPath` (no history, the picture just
follows the pointer) and lands through `commitPath`, which is one
`History.perform`. It is the same live-then-commit pair a corner radius pull
uses. Every commit refits the layer's box round the new shape
(`PathBuilder.refit`), so a point dragged past the old edge moves the corner as
well as the point.

## Turning a shape into one

A rectangle is a fixed thing: you can resize it, but you cannot take one corner
and pull it somewhere else. **Turn Into Path** is the one step that stops it
being a rectangle and makes it an outline, keeping exactly the look it had. It
is in the layer's own row menu and in the Layer menu, beside "Turn Into
Picture", which is the other one-way turn the app offers, and it goes ABOVE it,
because it is the gentler of the two: this one keeps the shape editable.

`PhotonzCore/ShapeToPath.swift` is all of it, and it is pure geometry.

### What each shape becomes

| Shape | Path |
| --- | --- |
| Rectangle | four corner anchors, no handles |
| Rounded rectangle | eight, the four arcs half smooth — a straight edge arrives, a curve leaves |
| Per-corner rounded | one anchor per square corner, two per round one |
| Ellipse | four smooth anchors on its compass points |
| Line | an open path of two anchors |

An **arrow** does not convert, and it is the one worth saying out loud. Its head
is part of how it is DRAWN rather than part of its outline: the shaft is a
stroke and the tip is a solid triangle sized off that stroke, so a path of it
would either arrive with no head at all or be one closed silhouette of the whole
arrow whose points sit on the outside of a shape nobody thinks of as an outline.
A **highlight** is a wash rather than a shape: its colour IS the fill and it
always mixes with what is under it. Both keep "Turn Into Picture", which is the
honest answer for a mark whose look is how it is painted.

### The constant, and why it is exact rather than close

A quarter circle cannot be written exactly as a cubic. Every drawing program
uses the same approximation: put each handle `4/3 × (√2 − 1)` ≈ 0.5523 of the
radius along the tangent. `ShapeToPath.circleHandle` is that number, and on an
ellipse it is applied to EACH AXIS separately — half the width across the top
and the foot, half the height at the two sides. Taking one number for both is
what turns a wide oval into a lozenge.

The number is not merely standard, it is what Core Graphics itself draws with:
`CGPath(roundedRect:)`, `CGPath(ellipseIn:)` and `addArc(tangent1End:…)` all
agree with it to the BIT, measured on rendered pixels at radius 8, 20 and 60 and
on a 180 × 120 oval. That is why a shape survives this turn pixel for pixel
rather than almost.

### What survives

The layer keeps its id, its name, its slot, its style, every effect and its own
transform. The only thing that changes is what it is MADE of, and it is one
`History.perform`, so one undo brings back a real rectangle with its Corner
Radius row.

The one thing it LOSES is that row, and that is the whole reason the command
stops and asks first (`TurnIntoPathPrompt`, and `SilencedQuestions` for the
"Don't ask again"). The instant after, the picture is identical, so nothing on
screen says the Corner Radius control has gone. A path has points rather than
corners: rounding it through the style would lay a rounded rectangle over it and
chop its outline off at the box, which is the very thing the one Corner Radius
row exists to stop a rectangle suffering, so `Layer.hasCorners` is false for a
path and the row is not offered.

### Three things that had to be fixed for the picture to survive

Each was reproduced on rendered pixels before it was fixed, and
`PhotonzRenderTests/TurnIntoPathRenderTests.swift` composites every shape twice
and compares the two bitmaps byte for byte.

1. **A ring round a path followed the layer's BOX**, so a rounded box turned
   into a path kept its curved fill inside a hard square frame. Since the
   Outline row left Appearance a box has no stroke of its own at all — its edge
   IS a Border effect (`OutlineRetirement.swift`) — so this was not an edge
   case, it was every shape in the app. `DocumentRenderer.pathSilhouette` now
   grows or shrinks the outline itself by sweeping it with a disc (a stroke of
   twice the reach IS that sweep), mitred so a square corner pushed outwards
   stays square.
2. **A path's stroke reach was half a point on an odd width**, which put its
   whole bitmap on a half pixel and let the compositor resample a hard edge
   soft. `PathContent.strokeOutset` rounds up now, the way a line's own overhang
   already did.
3. **`GradientPainter.stroke` never set the line cap for a FLAT paint**, only
   for a gradient, so every open path in the app ended in square butts while
   asking for round ones.

## What the next slices add

* **Booleans** (`docs/design/mocks/pages/draw-boolean.html`) — union, subtract,
  intersect. `flattened()` and `containsInside` are the start of the geometry.
* **SVG export** — done, under `icon-export`. A path is already exactly the
  cubic data an SVG `d` attribute wants, and Export writes it:
  `docs/design/svg-export.md` says what every layer kind writes, including the
  ones that have no vector answer yet.

## Known rough edges

* **An ellipse's OWN ring is still a bounding-box approximation.** A Border on a
  path follows the true outline now, and a Border on an ellipse annotation is
  still drawn as a second oval inset in its box, which is only the same thing as
  a line a fixed distance inside the curve when the oval is a circle. So turning
  a 2:1 oval into a path moves its ring by a fraction of a pixel along the
  flanks. The path's is the correct one; the oval's is the one to fix.
* **Line cap and line join are not settable.** Icons want butt caps and a miter
  limit sooner or later.
* **There is no way to place a half-smooth anchor without Option**, and the
  chip does not mention Option. A pen user will try it; a newcomer will not need
  it. Whether it deserves a line on screen is a question for the audit.
* **A path cannot be scaled by dragging any more once its points show.** The
  Position and Size fields do it, and a group round it does it, but there is no
  corner to pull. Whether that is missed is the question the reshape audit asks.
* **Points cannot be swept up with a marquee**, only gathered with ⇧ click. On a
  shape with thirty points that is thirty clicks.
* **A turned path shows no points at all.** Straightening it is the way in, and
  nothing on screen says so.
