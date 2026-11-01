# Is "looks painted 8 of 10" the right bar for Ask's paintings?

## What this is about

When you ask Ask to "paint a small landscape with oil paint", it sketches the
scene and then paints it stroke by stroke with the Brush's oil paint, the same
strokes you would paint by hand. The painting lands on its own Paint layer, and
every stroke stays editable.

The brush epic has one item left open. It asks two model judges to score Ask's
painting on two questions, each from 1 to 10:

- **Reads as the subject**: would anyone name it at a glance? The bar is 7.
  Ask's painting scores **8 and 8**. Met.
- **Looks painted**: the judges are told that 10 means "it could be a photo of
  a real painted canvas or paper" and 5 means "brushy, but plainly made by a
  computer". The bar is 8. Ask's painting scores **4 and 5**. Not met.

A runner set that bar on 2026-10-31. Five passes since have changed the oil
stroke, where strokes are placed, colour, relief, a canvas weave and a
different way of painting. None moved the score past 5.

## What the test found

To see whether 8 can be reached at all, this pass scored pictures nobody here
made, with the same judges and the same question:

| Picture | Looks painted | Reads as a landscape |
| --- | --- | --- |
| A real oil seascape, photographed (Royal Museums Greenwich) | 10, 9 | 8, 8 |
| Van Gogh, Wheatfield with Crows | 10, 10 | 10, 9 |
| A skilled person's digital painting made in Krita | **5, 6** | 9, 9 |
| Ask's oil painting today | **4, 5** | 8, 8 |

So the question the judges answer is really "is this a photo of a physical
canvas?". A person painting on a computer does not pass it either. Judge A on
the Krita painting: "smooth, uniform digital brush strokes have no canvas
texture, paint build-up or bristle marks, so it plainly looks made on a
computer."

The picture on the card shows the three side by side, Ask's in the red box.

## The options

- **A. Close it.** The painting shows what you asked for, and it looks as
  painted as digital work does, a point under a skilled person's. The bar of 8
  is set aside and the epic closes. Anything you dislike in a painting, you say
  so on the audit and it becomes its own task.
- **B. One more pass, aiming for the person's score (5 and 6).** This pass
  tried lighting each paint layer as one surface, so paint builds up where
  strokes overlap instead of each stroke being lit alone. On one test picture
  that reached 5 and 6. It changes how every paint layer is drawn, so it
  needs its own speed checks, and on one picture the gain may be noise.
- **C. Keep 8.** The loop keeps working on it. Nothing in this test, a
  person's work included, reached it.

## Where to look

- The comparison picture: `queue/audits/2026-11-01-brush-epic-painted-bar-calibration.png`
- Every number and the judges' own words:
  `queue/audits/2026-10-31-brush-epic-measures.txt` (the last section is this pass)
- The epic's audit, with the try path, the stroke sheets and the reel:
  `queue/audits/2026-10-31-a-brush-tool-paints-with-realistic-charcoal-chal.json`
