# Motion: a layer told to change one of its properties over time

Landed 2026-09-15, Next only, behind `next-motion`. Slices 1 and 2 of the
`icon-animate` set. Model: `Sources/PhotonzCore/LayerMotion.swift` (the pivot
is answered by `Layer.turnPivot`, in `TransformDrag.swift`). Panel:
`Sources/Photonz/MotionListInspector.swift`. Gestures:
`Sources/Photonz/EditorState+Motion.swift`. The crosshair on the canvas:
`Sources/Photonz/CanvasMotionPivot.swift`.

## The idea in one paragraph

Motion is a **property of a layer**, not a mode and not a preset. The panel
grows a **Motion** section directly under Effects, wearing the same header, the
same plus and the same kind of rows, because it is the same shape of thing: a
list you add to. The only difference is what a row means. An Effects row is
something the layer **paints**. A Motion row is something about the layer that
**changes**.

## There is no list of named motions

The first version of the mock offered Pulse, Wiggle, Bounce and Spin. The user
rejected it on 2026-09-15 as a closed vocabulary pretending to be a model, and
they were right: a bell does not pulse, it **swings**. So the plus is built out
of the layer in front of you. Every item names something that layer actually
has and carries the value it is wearing right now, because that is what you
would be animating away from. A preset is a combination of these, and
combinations are what you make.

Today that is Position, Scale, Rotation, Opacity, Color and Stroke width, and a
property is offered only where the layer has it: a photograph gets no colour
and no stroke, a box gets no stroke because a box's edge is a Border in the
Effects list. One property is one answer, so a layer already turning is not
offered a second rotation.

## What one entry says

**From**, **To**, **Around** and **At** (a turn only), **Start**, **Over**,
**Curve**, **Repeat**. Start and Over
are one type (`MotionTiming`) because the timing strip in slice 3 draws a bar
whose left edge is the start and whose width is the duration: they are the same
two numbers and moving either has to move both.

## The ruler is ONE CYCLE, in milliseconds

Not a document timeline. An icon repeats and a video finishes, and the two
cannot share a ruler (`docs/design/animation-vs-video.md`). One cycle is as
long as the last thing to finish, across the whole picture, so a delay on one
part of an icon is a distance you can see against the rest.

## What a turn turns AROUND

A bell that swings hangs from its **mount**, not from its middle. Put the pivot
in the middle and the top of the bell swings one way while the bottom swings
the other, which reads as a bobblehead: nothing about the two angles is wrong,
the pivot is. So a Rotation carries a `MotionPivot` from the moment it exists,
and it is a **handle on the picture** rather than a field somebody has to know
to go looking for. Adding a turn puts a crosshair on the middle of the layer,
which is deliberately the wrong answer, and one drag to the mount repairs it.

It is kept as a **fraction of the layer's own box**, not as a place on the
canvas. Move the bell and its mount comes with it; resize it and the mount
stays where it was on the shape; and the three spots worth a name are ordinary
values rather than a second kind of thing — the middle IS `(0.5, 0.5)`, the top
edge IS `(0.5, 0)`. Nothing clamps it into `0...1`, because a mount is very
often above the shape that swings, and that is the case the feature exists for.

`Layer.turnPivot` is the ONE question the renderer, the selection outline, the
turn knob, the handles and the hit test all ask, so the pivot is answered there:
the drawn pixels, the box round them and the place a click lands can never
disagree. A layer with no turn, or one still on its middle, answers exactly what
it answered before pivots existed.

Three ways in, one value:

| | |
| --- | --- |
| The crosshair on the canvas | the one that matters. The right pivot is a point on YOUR drawing and nobody else knows where it is |
| The **Around** menu | Its centre, Top centre, Bottom centre |
| The **At** pair | two numbers on the canvas, for when a number is what you want |

Grabbing the crosshair **starts the loop** if it is not already running, because
a pivot cannot be judged on a still picture: with the layer sitting at nought
degrees, changing what it turns around changes nothing you can see. Adding a
motion already starts the preview, so it is the same habit rather than a new
one. The whole drag is one step for undo, and the crosshair is drawn from the
STORED layer, so while the bell swings it sits dead still underneath — which is
both what makes it catchable and what teaches what a pivot is.

Three more places this deliberately leaves the mock:

1. **No pivot TOOL.** The mock puts a "Move the pivot (Y)" button on the
   floating tool bar and gates every later step behind it, which makes moving a
   pivot a MODE. A first-timer who sees a crosshair on their bell tries to drag
   it; making them find a tool first is where they stop. It is directly
   draggable with Select.
2. **No separate move button on the Around row.** That is the tool again.
3. **A fraction of the box, not canvas numbers.** The mock reads the pivot as
   `12, 4.4`, which is a place on the canvas; stored that way, dragging the bell
   tears the swing loose from it. The row still READS canvas numbers.

## Three places the MOTION ITSELF leaves the mock

1. **A fresh motion already moves.** The mock seeds From and To at the value
   the layer has now, so its own row reads `0° → 0°`: add a motion and nothing
   whatsoever happens. A rotation arrives as `-12° → 12° over 0.9s`, measured
   from whatever angle the layer is already at, and the preview starts, so the
   answer to "did that do anything" is on screen before you read a field.
2. **Repeat answers what happens after it plays, including coming back.** The
   mock's panel offered Once, 3 times and Forever, and its own bell swung out
   and back inside one cycle, which none of those three can say. A one way
   repeat snaps the bell home every 900ms, which is a jump cut. So the menu is
   Once, 3 times, Forever, and **Forever, there and back**, which is the
   default. One menu, no seventh field.
3. **No drag handle on a row.** An Effects row is ordered because the order is
   what paints over what. Two motions are on two different properties and
   nothing about the picture changes if you swap them, and this codebase
   already names that failure: a grip that changes nothing is a grip that lies.

## Nothing is baked in

A motion is evaluated at the moment the canvas is drawn, exactly like a blur or
a shadow: `EditorState.displayDocument` hands the renderer
`document.moved(toMotionTimeMS:)` while the preview runs, and the stored
document never moves. Stop the preview and the picture is the picture you drew,
which is what you edit against. Every change to a motion goes through
`History.perform`, so each is one step for undo.

`render`, export and thumbnails all go to the stored document, so they show the
layer as drawn. Animated export is its own slice.

## Curves

One named set, settled here for the app side of
`one-set-of-easing-curves-named-the-same-way-ever`, with the shape drawn beside
every name because nobody can tell ease out back from ease out quint by
reading:

| Name | What it is |
| --- | --- |
| Linear | the identity |
| Ease in out | `cubic-bezier(.4, 0, .2, 1)`, the design language's `--ease-standard` |
| Ease in | `cubic-bezier(.4, 0, 1, 1)` |
| Ease out | `cubic-bezier(0, 0, .2, 1)`, the design language's `--ease-decel` |
| Ease in out sine | |
| Ease out back | overshoots and settles |
| Ease out elastic | overshoots several times |
| Steps, 4 | jumps rather than slides |
| Draw a curve | `cubic-bezier(a, b, c, d)`, two handles you drag |

Back and elastic are allowed past the end on purpose: clamping them would
quietly turn both into ease out.

## Performance

The preview redraws the composite at a deliberate ceiling of 30 frames a
second, through the same latest-wins `RenderScheduler` every other edit uses, so
a renderer that cannot keep up drops frames rather than queueing them. The
sharp-copy pass is skipped while the preview runs, because a sharp copy of a
moving picture is stale before it lands.

## What is NOT here, and where it goes

The **cycle timing strip** in the bottom dock is slice 3. The looping preview at real icon
sizes is slice 4, and animated SVG export is slice 5.
