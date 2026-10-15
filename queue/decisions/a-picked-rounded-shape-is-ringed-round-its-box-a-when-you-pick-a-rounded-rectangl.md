# The ring round a picked rounded rectangle

## What this is about

When you pick a layer on the canvas, it wears a ring in the accent colour, with
eight small square handles you drag to resize it. For most layers the ring is
simply the layer's box. A rounded rectangle is the one case where two answers
are possible: the ring can stay a near-square frame round the box, or it can
bend round the shape's rounded corners.

## What the mocks say

The shared selection frame every mock page uses
(`docs/design/mocks/shared/components/selection.css`, the `.sel-ring` rule) is
explicit: the ring hugs the bounds with a 2 pixel corner softening, "a hairline
softening that reads as square at every size", and the notes at its foot say
never to trace the object's shape.

## What happened before

On 2026-09-08 the app was changed, on the loop's own judgement and with no card,
to curve the ring round a rounded rectangle, because four straight lines looked
like they cut across the corners. Back then the ring was a dotted blue line. It
is now one solid accent line (the mocks' look, built on 2026-10-14), and a
solid accent line that follows the curve reads as a blue border drawn on the
shape.

## Option A: square frame round the box (recommended, what Next shows now)

The ring is the same near-square frame for every layer. The eight handles sit
on it, at its corners and edge midpoints.

![A picked rounded rectangle wearing a near-square frame round its box](2026-10-14-ring-hugs-box-rounded-sc.png)

Zoomed in twice, the softening stays a hairline:

![The same, zoomed in](2026-10-14-ring-hugs-box-zoomed-sc.png)

## Option B: the ring curves with the shape

The ring traces the rounded corners. The handles still mark the square box a
resize grabs, so the four corner handles sit out in empty space, off the ring.

![A picked rounded rectangle whose ring follows its curve, corner handles floating off it](2026-10-14-ring-curves-rounded-sc.png)

![The same, zoomed in](2026-10-14-ring-curves-zoomed-sc.png)

## How these pictures were taken

Both are real window captures from the loop's own copy of the app, a rectangle
drawn on a white canvas with Corner Radius pulled to 72. The window was behind
another app while it was photographed, so the accent reads slightly paler than
it would in front. Option A is
`Scripts/playtest/a-picked-rounded-shape-hugs-its-box-walk.json`; option B is
`Scripts/playtest/selection-outline-rounds-walk.json` with the new switch off.
Either answer is one switch in Experiments: "The ring round a pick hugs its box".
