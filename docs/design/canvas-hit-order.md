# What a press on the canvas takes hold of

A picked layer wears several marks at once. A rectangle with a turn on it
carries eight resize squares, four rounding dots, a turn knob floated off its
top edge, and a crosshair for the point it turns around — and under all of them
sits the shape itself, which a press picks up and moves. Most of the time they
are yards apart and nobody has to think about it. Where two of them land on the
same few points, something has to decide which one a press means.

Until this was written down, every overlap was settled by hand, by moving one
hit test above another in the long list `CanvasView.mouseDown` reads. Two of
those hand-rolled answers went wrong within two days of each other in September
2026:

- A pivot parked within about eleven points of a corner could not be picked up
  on the canvas at all. The corner square answered first, however near the
  crosshair was drawn, so somebody who put the point there on purpose could
  never get it back.
- The pointer over a path's own points was read *after* the canvas boundary
  handles while the press read it *before*, so the cursor promised one thing
  and the press did another.

Two hand-rolled answers to the same question is a sign the question needs an
answer rather than a third list. This is it.

## The rule

**A press is read in bands. Within a band, the nearest drawn mark takes it.**

Two halves, and both matter. The bands say what kind of thing wins outright:
they are the things a person cannot see coming, ordered so that the smaller,
more specific target is never buried under the larger one it sits on. Inside a
band nothing is buried, because everything there is a mark of about the same
size drawn at a known spot, so the honest answer is simply the one nearest the
pointer — which is what the eye reads too.

Three corollaries fall out of it, and they are the parts worth remembering:

1. **A mark only competes where it is in reach.** Chrome the press was going to
   miss anyway never takes a press away from chrome it would have hit. A press
   nine points off a corner is past that square's slack, so the square does not
   get to claim it and then drop it.
2. **A mark drawn ON the picture wins a tie against the box drawn round it.** A
   crosshair parked exactly on a corner is a crosshair somebody put there on
   purpose, and it is the one of the two with no other way in: a resize can be
   pulled from any of the other seven handles or typed into Position & Size.
3. **The cue and the press ask the same question, in one place.** The pointer
   shape is the only invitation any of this chrome has, so a cue that runs
   ahead of the press is worse than no cue at all.

## The bands

Read in this order. Everything within one band settles by nearest mark.

| # | Band | What is in it |
| --- | --- | --- |
| 1 | **The mode you are in** | Crop's own box. The Pen's next point. A measure in flight. A tool that owns the canvas owns the press. |
| 2 | **The picked object's own points** | A path's anchors and levers. They sit on the outline, where a press would otherwise pick the whole shape up or start the next one. |
| 3 | **The canvas itself** | The boundary handles, when the canvas is what is picked. |
| 4 | **The picked layer's content** | Either end of a line or arrow, an arrow's caption pill, a caliper's number, feet and head dot. These *are* the object: a caliper is its two feet. |
| 5 | **Marks on the picture** | The crosshair a turning layer carries. Drawn inside the shape, often dead in its middle, so it cannot wait behind the press that moves the shape. |
| 6 | **The box round the picture** | The turn knob, the four rounding dots, the eight resize squares, and the live stretch of each edge. |
| 7 | **The picture** | Picking the layer up and moving it. A band sweep on a screen's own surface. |
| 8 | **Nothing** | A marquee on empty canvas. |

Bands 5 and 6 are the pair that made this necessary, and they are the pair the
nearest-mark rule actually arbitrates today: `CanvasHitOrder.markTakesPress`
compares the crosshair against whatever the box would have taken the press
with, and hands it to whichever is nearer. So:

- A crosshair parked on a corner takes the press aimed at it, and the layer
  still resizes from its other seven handles.
- A crosshair parked ten points inside a corner leaves the corner alone: aim at
  the corner and you resize, aim at the crosshair and you move the pivot.
- A crosshair dragged to just above the top edge — the bell hanging from its
  mount, which is the case the feature exists for — does not swallow the turn
  knob floating eighteen points out from that same edge.

## Where it lives

- `Sources/PhotonzCore/CanvasHitOrder.swift` — the rule, pure and tested
  (`Tests/PhotonzCoreTests/CanvasHitOrderTests.swift`).
- `Handles.grab` and `CornerRadiusHandles.grab` — the same answers `hit` gives,
  with how near the press landed, which is what the comparison needs.
- `CanvasPointer.contentGrab` — band 4, split out so band 5 has a place to sit.
- `CanvasNSView.motionPivotTakesPress` — the crosshair asking the question, in
  the layer's own upright space. Both `mouseDown` and the pointer cue call it,
  which is corollary 3.

Distances are compared in the layer's own upright space, which is where its
handles are hit-tested, so a turned layer answers where its chrome draws.
Tolerances are screen points throughout: a handle is a screen-sized thing and
the same layer is roomy zoomed in and cramped zoomed out.

## Adding chrome

New chrome picks a band and stops there. If it needs to beat something in its
own band for a reason other than being nearer, that is the signal that the
bands are wrong, not that this one case is special — say so here and change the
table. What is not allowed any more is quietly inserting a hit test at the spot
in `mouseDown` that makes today's bug go away.
