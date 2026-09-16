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
rows read the shape's own settings. What those rows are CALLED, and what else
sits under them, is "What its colours are called" and "What kind of line it is"
below.

Everything in the Effects list — shadow, glow, blur, opacity, blend mode —
reaches a path unchanged, because those are applied to the layer's rendered
picture and know nothing about what drew it.

### What its colours are called

A path is a shape like any other, so its parts are named for what they paint
(`docs/design/shape-parts.md`). It showed one row simply called **Color** until
2026-09-15, which is what the user hit on their first real session with the Pen:
"there is a color but it's not clear its the stroke color".

| The path | The rows in Appearance |
| --- | --- |
| Closed | **Fill**, with a switch, and **Outline**, with a switch |
| Open | **Line**, with no switch |

The word follows what the row can honestly promise. A closed path has an inside
to paint and a line round it, and it can be without either — so both are PARTS,
with a switch each, and `LayerPart.outline` is a case of its own. An OPEN path
IS its line: take that away and there is nothing on the canvas at all, which is
a delete rather than a setting, so it keeps the switchless ink row a line and an
arrow already use and wears their word.

The switch is a WIDTH rather than a missing paint (`PathLineStyle.swift`):
switching off sets `strokeWidth` to nought and leaves the colour where it is,
and switching on hands back the weight a freshly drawn shape wears. That is
exactly how a switched-off fill behaves — it comes back at its starting colour
rather than the one it had — so the two rows keep one promise between them.

The one colour that does NOT stay put is one that would be invisible. A closed
path arrives as its fill and nothing else, so the first outline it is ever asked
for would land in the fill's own colour and draw nothing anybody can see. It
takes graphite or white instead, whichever stands further off the fill, exactly
as a box's first border does (`BorderInk.swift`). Only an ink that is LOST
against the fill is repainted, so a line switched off and switched back on comes
back in the colour it had, and an open path — which has no fill to be lost
against — is never repainted at all.

The row's settings go with the switch. A path with no outline used to keep a
Thickness reading 0 px under a colour well that painted nothing, which is the
dead control the switch exists to replace: off has to LOOK off.

A path picked ALONGSIDE a line falls back to the plain word Color and loses the
switch, because Outline is the wrong word over a line and a switch that reached
one would promise to delete it.

### What kind of line it is

`PathLineStyle.swift`, and three pickers under the Outline row:

| Row | Answers |
| --- | --- |
| **Pattern** | Solid, Dashed, Dotted |
| **Ends** | Flat, Round, Square |
| **Corners** | Sharp, Round, Flat |

Named as shapes rather than as drawing-engine words: nobody choosing between
"butt" and "square" is choosing between two English words that mean the same
thing. `svgName` is the one place the two vocabularies meet.

**Dashes are measured in LINE WIDTHS, not in points.** Dashed is three widths of
mark and two of gap, dotted is one and two. Turn a dashed line from 2 up to 8 and
the dashes grow with it instead of turning into a smear, which is what makes a
dashed icon look the same at every weight. A dash pattern you type numbers into
is a power tool with nowhere to live in this panel, and it is not what an icon
needs.

**Ends and dashes COMPOSE rather than override.** A dot is one width of mark, so
with round ends it is a dot, with flat ends a small square, and with square ends
a slightly bigger one. That is why the Ends row is offered as soon as dashes are
on, even on a closed shape that has no ends of its own: every dash has two
(`PathContent.showsLineEnds`). A closed SOLID shape is not asked, because there
it is a control that cannot act.

**A square end reaches further than a round one**, so `strokeOutset` grows for
it: the far corner of a square cap sits width/√2 from the last point rather than
width/2, and without the extra room the corners would be sliced off by the edge
of the shape's own bitmap.

**How far a sharp corner may be carried is stated out loud** (`pathMiterLimit`,
10). Core Graphics' default is 10 and SVG's is 4, so a file that stayed quiet
would come back a different shape in a browser than it is on the canvas.

**A sharp corner also needs room, and it is not the room a straight run needs.**
Where two runs meet, the outer edge is thrown out along the bisector by the
line's offset divided by the sine of half the angle: a right angle reaches 1.41
offsets, a thirty degree one 3.9. `strokeOutset` therefore asks every join where
its point would land and takes the furthest one PAST the outline's own box
(`PathContent.sharpCornerOutset`). Measuring it per axis rather than as the
length of the point is what keeps an ordinary shape costing nothing: the corner
of a plain rectangle reaches 1.41 offsets diagonally and still only one offset
along each axis. Before this a chevron drawn with a 12 point line lost 1.7
points off its point to the edge of its own bitmap.

The defaults are exactly what the rasterizer always drew — round ends, sharp
corners, a solid line — and a file written before any of this existed decodes
to them, so nothing anybody has already drawn changes.

### The same question, asked of a line and an arrow

A line and an arrow are asked **Ends** and nothing else, in the same spot under
Outline beside their Thickness, reading the same `PathLineEnd`
(`AnnotationContent.lineEnd`, behind `next-line-ends`). Round is what they have
always drawn and what an older file opens as, the choice is one undo step, and
it is written into an exported SVG as `stroke-linecap`.

They are asked one question rather than three because they ARE one straight run:
there is no second run for a corner to happen at, and a Pattern picker is a
separate feature rather than part of this one. A box, an oval and a highlighter
wash are closed or are not a line at all, so they are not asked either — the
panel's own rule about a control that cannot act.

**A Border in the Effects list is deliberately NOT asked.** A ring round a box
is not stroked at all: `DocumentRenderer.ringed` draws it as one rounded rect
with a smaller one cut out of it, so there is no join to set. Giving it one
would mean rewriting that geometry for a result nobody could tell from Corner
Radius, which rounds the path itself so the fill and the ring round together.
The corner control for a box is its Corner Radius, and there is one of those.

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
the Pen is in hand and its line changes as the path grows; once the path can be
closed it reads "Click the first point to close the shape. Return finishes it
open, Esc discards it." Return and Escape do OPPOSITE things and that is the
only place a person is told so. Clicking the last anchor again also finishes,
for anyone who never thinks to press Return — which also means a double click
ends a path, for free, since the second click of one lands on the anchor the
first just placed.

### Two points are enough, when they make a shape

**Closing is not a head count.** The Pen used to refuse to join a path up until
it had three anchors, on the grounds that two points cannot enclose anything.
That is true of two points joined by straight runs and false the moment either
run bends: a leaf, a petal, an eye and a lens are all two points and two curves,
and they were unbuildable (reported 2026-09-14, first real drawing session).

So the question the Pen asks is the real one: **would joining this path up leave
a shape with an inside?** `PathContent.enclosedArea` answers it exactly rather
than by sampling, integrating ½∮(x dy − y dx) along each cubic run, so an
outline that doubles back along its own line works out to a clean zero. Two
points with a curve on them enclose a leaf and close; two points on a straight
line enclose nothing and do not, and neither do three or twenty in a row.

**The aim and the answer are separate.** The ring under the pointer appears on
the first anchor from the SECOND point on, exactly as it does at three, because
a press there is aimed at closing however it turns out. Whether it makes a shape
is settled when the button comes up, and the press itself can decide it: pulling
off the first anchor bows the run home, which is what turns a flat pair into a
half moon. A press that cannot make a shape is refused and changes nothing, down
to the handle the refused drag would have left behind.

**The refusal explains itself before it happens.** Standing on the first anchor
of a flat path, the chip stops offering the close and says instead: "These
points are in a line, so joining them up has no inside. Drag off this point to
curve the shape closed, or click a point off the line." It arrives before the
click that would be refused rather than after it, and it names the way out.
Before this the click silently dropped a third anchor exactly on top of the
first, which left junk in the path and never closed anything.

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

**The Pen ends like every other tool that makes something.** A finished path is
added, picked, and the pointer comes back, so the arrow keys nudge the shape and
the panels describe it without a trip to the tool bar. That is the rule for all
eleven creating tools (`Tool.createsLayers`, `ArrowCaptionEntry.toolAfterLanding`)
and the Pen has no exemption from it.

It did have one, for two days. "The Pen stays in your hand for the next shape"
was built on the reasoning that an icon is five or six shapes in a row, which is
true, and the answer to it is the app's own: P puts the Pen straight back, the
way R does for rectangles. Five shapes cost five presses of P, one per shape, and
in exchange the Pen ends the way the other ten tools end. The user hit the
inconsistency twice, the second time as "after i create a shape, it doesn't
select it and switch to V tool" (2026-09-15), which is what retired it. Escape
with nothing being drawn still puts the Pen down, for the Pen picked up and not
used and for a path abandoned mid-draw, and V or any other tool button still
puts it down as it always did.
`Scripts/playtest/pen-hands-back-walk.json` is the walk that holds all of it.

What the sticky Pen landed alongside stays: a picked path shows its points under
the Pen as well as under Select, so pressing P over a finished shape reaches its
anchors.

A path arrives wearing what a new box wears, which since 2026-09-15 means **no
edge until you ask for one**. A CLOSED path is its fill and nothing else: no
line round it, so its edges land exactly on the points that were clicked. It
used to come out filled AND outlined in the one armed ink, so the outline was
invisible and the painted shape reached half a line width past every point —
two points all round, which on a 24 point icon grid is a sixth of the drawing.
An OPEN path is untouched and keeps the weight the canvas set, because a line IS
its stroke and a line of no width is not a shape with no edge, it is nothing at
all. It carries no fill either. The Pen carries no colour capsule on the tool bar: the Appearance
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
| Double click a point | Hard corner becomes a smooth bend, and again turns it back. It is also how a broken point is JOINED: both sides come back in line, and a point curved on ONE side gets its other side back. |
| Double click a lever | Pulls that lever in, so that side runs straight. The same thing ⌥ click does, in the app's own idiom: two clicks change what the thing under them is. |
| Double click the outline | Adds a point exactly where you clicked. |
| Delete | Takes the picked points out, the curve closing over the gap. With no point picked it still deletes the layer. |
| Escape | Lets the points go, before it lets the layer go. |

A square dot is a hard corner, a round one is a smooth bend, and a rounded
square is a point curved on ONE side only — half way between the two, which is
what it is. So what a point IS can be read off the canvas. The dot says
whether, not which side: the outline itself already shows which run is
straight, and a glyph turned to face the straight side read as a diamond at
eight points across rather than as anything anybody could name. A picked point
is filled in the accent instead of hollow.

The chip under the canvas carries the gestures nobody guesses, and it names the
point you have picked: a hard corner is told how to curve it rather than told to
drag a lever it has not got, a bend is told about its levers, and a point curved
on one side says so and gives the way back in both directions.

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
| Highlighter wash | four corner anchors, filled in the wash's colour, no line |

A **highlight** was left out at first, for a reason that turned out not to hold.
A wash is a filled box, and the thing that makes it a highlighter rather than a
coloured slab is that it MIXES with what is under it. That mixing is not lost by
becoming a path: a highlight mark multiplies because `Layer.mixingIsFixed` says
it must, and the turn carries that into the layer's own `style.blendMode`, where
the picture is identical and it is a setting rather than a rule. Proved on
pixels, over a backdrop, in `TurnIntoPathRenderTests`. What it buys is a wash
that is no longer stuck being a rectangle: a run of words that wraps onto two
lines, or a panel with a notch out of it, can be highlighted in one mark.

An **arrow** does not convert, and it is the one worth saying out loud. Its head
is part of how it is DRAWN rather than part of its outline: the shaft is a
stroke and the tip is a solid triangle sized off that stroke, so a path of it
would either arrive with no head at all or be one closed silhouette of the whole
arrow whose points sit on the outside of a shape nobody thinks of as an outline.
Three of its four heads — the open chevron and the two dots — are separate
contours, and `PathContent` holds ONE, so for those the picture could not
survive the turn at all. It keeps "Turn Into Picture", which is the honest
answer for a mark whose look is how it is painted. What somebody actually wants
from an arrow they cannot reshape is a curved shaft, which is a change to the
arrow rather than a conversion away from it.

### And it stops calling itself a rectangle

A layer nobody has named by hand says what it IS, so a row reading `Rectangle`
reads `Path` the moment it stops being one; a second one turned after it is
`Path 2`, so the list still tells them apart. A layer somebody called `Card` is
called `Card` whatever it is made of (`LayerNaming.isAutoName`). The new name is
written inside the SAME mutation as the shape change, so one undo puts the
outline and the name back together — a step that restored the rectangle and left
the row saying `Path` would be the app disagreeing with itself.

### What it says afterwards

The question asked beforehand says what the command will do, and it carries a
"Don't ask again". The second time somebody uses it there is no question at all,
so the row in the layers list would quietly stop being the kind of thing it was
with nothing said. So the chip under the canvas leads with one line naming what
just happened — `PathEditHint.justTurned`, held in `EditorState`
`turnedIntoPathNotice` — and steps aside for the ordinary reshaping lines the
moment a point is picked, or the selection changes, or an undo takes the shape
back.

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

## Several shapes into one path

Three lines drawn end to end are a triangle, not three lines in a bag. Pick all
three, ask for a path, and you get ONE path: the runs welded where their ends
meet, closed because the last end came back to the first, and fillable from that
moment on. `PhotonzCore/PathJoining.swift` is the geometry;
`PhotonzDocument.turningLayersIntoPath(ids:)` carries it to the document in one
mutation, so the whole thing is one undo step.

**This is not the boolean operations.** Union, subtract and intersect combine
AREA, and three lines enclose no area at all, so a union of them produces
nothing useful. Joining ends and combining areas share the word "join" and are
different operations; conflating them is how one of them ends up unbuildable.

### The rules, all of them stated

* **The command acts on everything picked.** From the Layer menu that is the
  selection; from a layer row's menu it is `rowMenuTargets` — the whole
  selection when the row you right clicked is part of it, else that row alone.
* **Ends within 2 points of each other MEET** (`PathJoin.tolerance`). They are
  welded into one anchor sitting half way between, so ends that already touched
  do not move at all and a near miss moves each end by at most one point. Ends
  further apart than that are LEFT ALONE: they do not join, and the question
  says so. A tolerance nobody can predict is worse than no tolerance, which is
  why the number is in the question rather than only in this file.
* **An outline that comes back to its start closes**, unless closing it would
  enclose nothing — an outline doubling back along its own line sweeps no area,
  which is the same thing the Pen already refuses to close.
* **Order and direction do not matter.** The open runs are walked in a settled
  geometric order rather than the order they were picked, and a run whose far
  end is the one that meets is turned round before it is carried on.
* **The topmost survives.** It keeps its id, its slot, its effects and its look,
  so undo has one row to put back. It keeps its name too, unless that name was
  one the app wrote: "Line 3" is a poor name for a triangle, so an automatic
  name becomes "Path".
* **Welded corners are drawn round where the ends they replace were round.** A
  round cap on each of two lines meeting at a point paints the disc one round
  join paints, so the picture does not change at the joint.

### What does not join, and why that is the honest answer

A rectangle or an oval is CLOSED and has no free ends. A locked layer is never
swallowed. A rotated or flipped layer's outline is not where its anchors say it
is. And shapes that touch nothing simply do not meet.

All of those stay their own layer. The alternative — one layer holding several
separate runs — would mean a path that is more than one outline, and every part
of the app that reads a path (the renderer, the reshaping tools, the handles,
hit testing, SVG export, the inspector) assumes exactly one. That is a much
larger change than the thing anyone asked for, and it would be built for a case
nobody reported: the report was three lines that DO meet.

### What it says before it does it

One shape asks the question it always asked (`TurnIntoPathPrompt`). Several ask
the plural (`TurnIntoPathQuestion`), and it carries one thing the singular never
had to: the ANSWER. Four shapes can come out as one path or as three, they can
close or stay open, and two ends can be welded across a gap. None of that is
guessable from the canvas beforehand, so the question says which it will be:

> **Turn these 3 shapes into one path?**
> Every point on them becomes yours to move, curve or delete. Their ends meet,
> so they join into one outline. It comes back to where it started, so it
> closes and you can paint inside it. They stop being shapes, so the controls
> only a shape has go. Undo puts it back.

It is the same "Don't ask again" the one-shape question carries, because it is
the same command. Silenced, nothing is announced — which the app's own bar for
asking allows, since a join is VISIBLE the instant after: three rows became one.

## Two shapes become one

Most icons are not drawn point by point, they are built. A circle with a smaller
circle cut out of it is a ring; two rounded rectangles joined are a chat bubble;
the overlap of a square and a circle is a squircle. **Combine Shapes**, in the
Layer menu and on a layer row's own menu, is the four ways that happens:

| On the menu | What it keeps | What other apps call it |
| --- | --- | --- |
| Join | everything either shape covered | union |
| Cut Out | the bottom shape, less everything above it | subtract |
| Keep Overlap | only the part every shape covered | intersect |
| Drop Overlap | everything but the part they share | exclude |

It rides on the Pen's own flag, because the result of every one of these is a
path and a path you cannot reshape is a command with no payoff.

### A path holds several rings

The model had to change first. `PathContent` held exactly ONE outline, and the
two things an area operation hands back are not one outline: a ring is a rim and
a hole, and two shapes that never touch, joined, are two unconnected pieces.
Both are a single shape wearing a single fill, so both have to fit in one path.

They fit as ONE FLAT anchor list plus `ringStarts`, the indices where each ring
after the first begins — not as a list of lists. That is the decision the whole
change turns on: an anchor is still found by one number, so picking a point up,
dragging it, nudging it, gathering several and reading a press off the outline
all go on working on a hole exactly as they work on a rim, with no second index
threaded through the canvas. What had to learn about rings is short and all in
the geometry: `segments` and `flattenedRings` never join the last anchor of one
ring to the first of the next, `containsInside` counts every ring into one
tally (which is how the rim's winding and the hole's opposite winding cancel),
`neighbour` wraps within its own ring, and an edit that would leave a ring with
fewer than two points takes that ring out whole rather than leaving a stub.

`ringStarts` is left out of the file for a one-ring path, so nothing already on
disk changes the next time it is saved.

### The arithmetic is Core Graphics'

`CGPath` has had union, subtraction, intersection and symmetric difference since
macOS 13. They are exact and they keep curves as curves: a circle joined with
itself comes back as the same four cubics. Writing a bezier clipper by hand to
do the same thing worse is not the work.

The work is `PathContent.init?(CGPath)`, walking the answer back into the app's
own anchors. A `CGPath` is a flat list of "move here, curve to there" with no
notion of an anchor that has a handle on each side, and a naive walk turns every
curve into the straight line between its ends. So each curve's first control
point is written onto the anchor it LEAVES and its second onto the anchor it
ARRIVES at, the closing duplicate point is folded into the first anchor, a
quadratic is elevated exactly, loops that enclose nothing are dropped, and each
anchor is asked whether its two handles run in one line through it so a circle
that came through untouched still has four smooth points on it.

### The rules a person can hold in their head

* **The BOTTOM shape survives.** It keeps its id, its slot in the stack, its
  name, its effects and its look, and the result wears that look. One rule for
  all four, and it is what makes Cut Out predictable: everything above is cut
  out of it, so restacking changes the answer.
* **A shape has to have an inside.** An open path is a line and a line encloses
  nothing, so it takes no part and is left exactly where it is. Quietly closing
  it and filling it would change a picture nobody asked to change.
* **A turned shape combines where it LOOKS.** The turn is baked into the anchors
  on the way in, which is also why the result comes back unturned and its points
  are draggable again.
* **Nothing is a real answer.** Keep Overlap on two shapes that do not touch, a
  shape cut out of itself, a cut that swallows everything: the document is left
  exactly as it was and the pill under the canvas says why. Deleting both shapes
  and leaving a blank canvas is the one outcome nobody wants and the easiest to
  reach.
* **One undo step**, whatever the shapes were.

### And it stops calling itself a rectangle

A layer nobody has named by hand says what it IS, so a row reading `Rectangle`
reads `Path` the moment it stops being one; a second one turned after it is
`Path 2`, so the list still tells them apart. A layer somebody called `Card` is
called `Card` whatever it is made of (`LayerNaming.isAutoName`). The new name is
written inside the SAME mutation as the shape change, so one undo puts the
outline and the name back together — a step that restored the rectangle and left
the row saying `Path` would be the app disagreeing with itself.

### What it says afterwards

The pill under the canvas, not the path chip — because the sentence that matters
most is the one about a combination that came to nothing, and in that case the
shapes are still shapes and the chip is not up to say it. It carries the two
things the canvas cannot show: which shape's fill, outline and effects the
result is wearing, since two overlapping circles of the same colour say nothing
about which was underneath, and whether the result has a hole in it or came
apart into pieces.

### Where the mock was not followed

`docs/design/mocks/pages/draw-boolean.html` proposes a LIVE combine: both
sources kept underneath, a Union/Subtract/Intersect/Exclude row in the panel to
retune it, and a Release combine command. That contradicts the thing this is
for, because a live combine's result has no points of its own — reshaping it
means reshaping the hidden sources. This is the one-shot version: undo is the
release, and what you get has points you can pull. The mock's four words are
jargon the house style keeps out of user-facing copy, so they are said once in
the flag's description and nowhere else.

## What the next slices add

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
* **A GROUP cannot take part in Combine Shapes.** It is not a shape with an
  inside, so it is left alone with everything else that has none. Illustrator
  and Figma both allow it.
* **The Pen still needs ⌥ to place a half-smooth anchor as it draws**, and its
  own chip does not mention it. Reshaping no longer does — a double click on a
  lever is the way in there, and the chip says so — but the two tools now
  answer the same question differently.
* **Reaching a half-and-half point from a HARD corner takes two gestures**:
  double click the point to curve both sides, then double click one lever to
  straighten the side you did not want. The chip guides the first step but
  cannot name the second until there is a lever to name.
* **The Pen draws every anchor it has placed as the same round dot**, so while
  you are drawing you cannot see which points are corners, bends, or curved on
  one side. The reshaping chrome tells all three apart.
* **A path cannot be scaled by dragging any more once its points show.** The
  Position and Size fields do it, and a group round it does it, but there is no
  corner to pull. Whether that is missed is the question the reshape audit asks.
* **Points cannot be swept up with a marquee**, only gathered with ⇧ click. On a
  shape with thirty points that is thirty clicks.
* **A turned path shows no points at all.** Straightening it is the way in, and
  nothing on screen says so.
