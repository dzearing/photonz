# How wide is the column of layer names on the icon timing strip?

## What this is

When you animate an icon (a bell that swings, a knob that lags it), a strip
opens across the bottom of the window. Down its left edge is a column of layer
names, each with a small mark for its kind (a square for a rectangle, a circle
for an ellipse). To the right of that column, each moving property has a bar
that says when it happens.

The mock is the **Make a bell swing** page:
http://127.0.0.1:8791/index.html#icon-animate-wt (the timing dock at the bottom).

## What differs

The mock draws the name column narrower than the app does. In the mock, "Bell
body" wraps onto two lines. In the app the column is wider, so names up to about
13 letters fit on one line and longer ones (Notification bell, Settings window)
now wrap onto two.

Picture, mock on top and the app below:
`queue/audits/2026-10-05-timing-strip-wrapped-names-vs-mock.png`

## Option a: keep the wider column (recommended)

Nothing moves. Fewer names wrap, rows stay shorter, and the bars start at the
same point on the icon strip as on the video timeline.

## Option b: narrow it to the mock's width

The names, ruler, bars and playhead all start further left, giving the bars a
little more room. Most two-word names then wrap onto two lines, each of those
rows grows taller, and the icon strip's bars no longer line up with the video
timeline's.
