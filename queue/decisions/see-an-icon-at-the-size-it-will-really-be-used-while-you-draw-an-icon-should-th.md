# Showing an icon small while you draw it

## What this is about

You asked this morning for a Pen that draws polygons with hard edges and bezier
curves, so you can build elaborate SVG icons, and for a way to get an icon back
out as clean SVG. Both of those are queued and the Pen itself has already
landed.

While planning the rest of the icon work, the loop came up with something you
did not ask for: a live preview that shows the icon you are drawing at the
small sizes it will really be used at. This card asks about that idea before
anyone builds it, rather than after.

## What is already settled and not part of this question

New Frame is getting icon sizes either way: 16, 24, 32, 48, 64 and 512. Today
the preset list is Desktop, Laptop, Tablet, Phone and Square, and the smallest
of them is a thousand pixels across, so there is currently nowhere in the app to
draw an icon at all. That half is plainly needed and is filed on its own.

This card is only about whether the app also shows you the icon small.

## Why anyone would want it

An icon is the only thing in this app that is drawn at one size and looked at
at another. A hairline that reads beautifully on a 512 pixel canvas vanishes at
16. A shape with a two pixel gap in it turns into a smudge. Every icon tool
worth using shows the small sizes while you work, because finding out after
export means drawing it again.

## What you would see

**A row of small previews.** Pick an icon frame and a small row appears at the
edge of the canvas: the same drawing at 16, 24, 32, 48 and 64 pixels, redrawn
as you draw. Pick anything else and it goes away. This is the recommendation.

**A preview section in the right hand panel.** The same previews, but in the
panel you already open for a picked layer, so nothing floats over the picture.
The cost is that it is hidden exactly when people tend to hide the panel, which
is while drawing.

**Do not build this.** Icon frames at the right sizes and nothing else. You
judge the small sizes by zooming out or by exporting and looking, and the queue
spends the slot on the Pen and on SVG export instead. Picking this retires the
task for good.

## Worth knowing either way

If it is built, the small sizes have to be drawn the way the system would
actually draw them. A smooth shrink looks fine and hides the exact problem the
preview exists to show, so it would be checked against the app's own render at
that size rather than judged by eye.

## Where to look

The icon drawing mock is at
`docs/design/mocks/pages/icon-draw-wt.html`, and the shared vocabulary any new
surface has to follow is in `docs/design/mocks/shared/UX-PATTERNS.md`.
