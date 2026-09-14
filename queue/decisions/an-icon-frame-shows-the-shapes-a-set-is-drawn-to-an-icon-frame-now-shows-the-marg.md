# What else goes on an icon frame

## What is already there

Make a frame at an icon size (Layer ▸ New Frame, the Icons row, 24) and the
frame is no longer a blank square. Two things are drawn on it, in faint violet
dashes, before you draw anything:

- **The margin.** A 24 pixel frame shows a 20 by 20 square inside it. That is
  the space every glyph in a set keeps its drawing inside, and it is the single
  reason a set of icons looks like a set rather than like a pile of drawings.
- **The two center lines.** One down the middle, one across it.

Both are guides, not picture. They are drawn over your work and never into it,
so an export, a copy or an SVG of that frame comes back with your artwork alone.
View ▸ Show Icon Keylines turns them off, and they stay off until you turn them
back on.

This decision does not change any of that. It is only about **what else** the
frame should draw.

## The problem the extra shapes solve

Draw a square that exactly fills the 20 by 20 margin. Now draw a circle that
exactly fills the same margin. Put them side by side and the circle looks
**bigger**, even though both measure 20 across. That is not an illusion you can
argue with, it is how eyes work: a circle has less area than the square around
it, so to look the same size it has to be drawn a little larger than the square.

Every serious icon set handles this the same way: it publishes a set of shapes,
each a slightly different size, and you draw your glyph to whichever one matches
its shape. A boxy glyph fills the square. A round one fills the circle, which is
drawn a bit bigger. A tall thin one fills the tall rectangle. Do that and the
whole set reads at one size even though no two glyphs measure the same.

That set of shapes is the thing this decision is about.

## The three answers

### The classic four

A square, a circle, a wide rectangle and a tall one, all drawn at once, nested
inside the margin. This is the set Material Design publishes and the one most
icon libraries follow, so a glyph drawn here sits correctly beside glyphs drawn
anywhere else.

The cost is that a 24 pixel frame is a small place to put four outlines. While
you are drawing you are looking past four dashed shapes instead of one.

### Just the square and the circle

Two shapes rather than four. This is what the design study's own icon page
draws, and it is where nearly all of the effect lives, because square against
round is the pair that disagrees the most. Much quieter to work in.

What you give up is the two rectangles. A glyph that is long and thin, an arrow
or a bar, has no outline of its own to aim at, only the margin and the center
lines.

### Nothing more

Keep the frame exactly as it is today. Nothing extra gets built.

The margin and the center lines already carry most of the day-to-day value:
where the drawing may go, and where the middle is. The thing you lose is the
optical-size trick above, which stays something you would have to know about and
do by eye.

## Worth looking at

- The icon page in the design study, which draws the 24 unit artboard with its
  20 by 20 margin and names an 18 by 18 square and a 17.2 circle:
  <http://127.0.0.1:8791/index.html#icon-draw-wt>
- Material Design's own numbers inside a 24 unit box, for comparison: square
  18 by 18, circle 20 across, rectangles 20 by 16 and 16 by 20.

Whichever shapes you pick, they will be drawn in the same faint dashes as the
margin, scaled to whatever size the frame is, and taken away by the same one
switch.
