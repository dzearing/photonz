# Where a keyed value's curve opens

## What this is about

When a value on a layer is keyed (say a title's Scale goes from 100% to 160%
between one second and two), the value moves between the keys along a
**curve**: straight, easing in, easing out, or a shape you draw by dragging
**Bezier handles**. Seeing that curve is how you tell a move that eases gently
from one that snaps.

Under each track on the timeline there is now one lane per keyed value, with a
diamond per key. The question is where you look at, and reshape, the curve.

## Option A: in the lane (built now)

Click the small curve button beside a lane's name, or **Graph** on the
Animating header in Properties. That lane grows taller and draws the curve
right on the timeline, with the keys sitting on it and handles you can drag.

- It lines up with the ruler, the clip and the playhead, so "when" reads
  straight off the timeline.
- The timeline gets taller while a curve is open.

Picture: `queue/audits/2026-09-23-key-lanes-9-handle-dragged-sc.png`.

## Option B: a Graph panel on the right (what the mock draws)

The video mock (http://127.0.0.1:8791/index.html#video, the "Graph" group in
the right dock) keeps the curve in a collapsed **Graph** group at the bottom of
Properties. It plots the value you pick in Animating, across the clip's length,
with times written underneath.

- The timeline stays compact.
- The curve is small (the panel is about 210 points wide) and cannot line up
  with the timeline, so times are read off its own labels.

## Option C: both

The lane keeps its curve and the Graph panel is added as well. Both draw the
same curve, so they always agree, but there are two places to learn.

## Recommendation

**A.** A curve you shape is about timing, and it is easiest to judge where it
lines up with the clip and the playhead.
