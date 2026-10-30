# Brushes draw exactly what lands: what that costs, and what to do about it

## What this is about

On 2026-10-25 you asked that painting be what you see: earlier strokes never redraw or
flicker, the stroke you're drawing looks exactly as it will when you let go, and drawing
stays immediate.

The first part shipped on 2026-10-27 and has held up since. Nothing already on the canvas
changes while you draw, at any zoom. The stroke under the pointer is drawn in the
picture's own pixels, so nothing sharpens when you let go. A mouse stroke's end thins as
you draw it, so it doesn't snap thin on release. The red box in the pictures marks those
thinned ends.

## The catch

The task also asks that no brush be slower per pointer move than before that change. It
isn't, at small and medium sizes:

| p95 per move, ms | before | today | today, no thinned end |
| --- | --- | --- | --- |
| Oil 150 pt, 12 MP picture zoomed out | 1.4 | 7.8 | 4.2 |
| Pencil 150 pt, 12 MP picture zoomed out | 1.0 | 5.5 | 3.0 |
| Oil 150 pt, screenshot-size picture | 4.5 | 8.4 | 4.3 |
| Pencil 20 pt, screenshot-size picture | 0.7 | 1.9 | 1.5 |

One 120 Hz screen frame is 8.3 ms. Full tables:
`queue/audits/2026-10-30-paint-move-cost.txt`.

There are two reasons:

1. **The thinned end is drawn again on every move.** The end's shape depends on where the
   pointer is right now, so the last stretch is taken back and redrawn each time it moves.
   That's about half the cost at 150 pt.
2. **On a big picture zoomed out, the live stroke paints the picture's own pixels.** At
   fit on a 12 MP picture that's about 2.8 picture pixels per screen pixel. The old preview
   painted screen pixels and swapped to the sharp version when you let go, which is the
   swap you asked to get rid of.

Turning the thinned end off fixes reason 1 and brings a screenshot-size picture back to
the old numbers. Nothing fixes reason 2 except going back to the rough preview, or making
every brush dab itself several times cheaper. That second job is the open brush speed
task (`every-brush-follows-the-pointer-with-no-lag-even`).

## The options

- **A. Keep the thinned end, accept the cost (recommended).** Drawing stays exactly what
  lands. Small and medium brushes stay within about one frame. The big brush frame keeps
  being worked on in the brush speed task, and every gain there lowers these numbers too.
  This task closes against "no slower than one 120 Hz frame at 20 and 150 pt" rather than
  the old numbers.
- **B. Mouse strokes end at full width.** As in Photoshop with a mouse: the start still
  thins, the end stops where you let go. About half the cost per move. Watercolour and
  pencil lose their tapered tails (compare the two pictures). Pen strokes are unchanged.
- **C. Back to the rough preview.** The old speed everywhere, but the stroke changes when
  you let go.

## Pictures

- Today, the end thins as you draw: `queue/audits/2026-10-30-paint-ends-thinned.png`
- Option B, the end stays full width: `queue/audits/2026-10-30-paint-ends-full.png`

Both are real captures of the app: oil, pencil and watercolour, drawn left to right at
100%.
