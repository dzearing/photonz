# Does a picked recording show resize handles when it is not zoomed?

## What this is about

When you click a screen recording on the canvas it is **picked**: the canvas draws something round it so you know what your next drag or key will act on.

The zoom walkthrough mock ([video zoom walkthrough](http://127.0.0.1:8791/pages/video-zoom-wt.html)) draws a picked recording as a single **ring on the edge of the frame**, with **no handles**, at every step: before the zoom, during it and after.

## What the app does today

- **Zoomed in** (for example Scale at 220%): the app now draws the ring on the frame and no handles, as the mock does. Before this change it outlined the whole magnified picture, so a dashed edge and a handle hung out on the empty canvas.
- **At its own size** (Scale 100%, the wide shot): it shows the blue box on the frame plus the eight square handles that every picture has.

Pictures: the wide shot with handles is `queue/audits/2026-10-12-zoom-frame-ring-4-wide-sc.png`, and the zoomed ring is `queue/audits/2026-10-12-zoom-frame-ring-3-framed-sc.png`.

## The options

**A. Handles at its own size, a ring when zoomed (what ships).** You can still drag a corner to shrink a full-frame recording into a picture-in-picture. The eight squares appear and disappear as you scrub into and out of a push.

**B. Always a ring, never handles.** A recording that fills the frame always looks the same when picked, exactly like the mock. To shrink it you use the Scale row or drag the picture, not a corner. A recording already smaller than the frame keeps its handles.

## Worth knowing

Premiere and Final Cut show a picked clip's box with handles in the viewer only once you ask for the transform controls (Motion in Premiere, the Transform button in Final Cut); otherwise they draw nothing on the picture. Option B is closer to that calm default.
