# What is the two-point measure question?

## The feature in one paragraph

The caliper is the measure tool you use by clicking two points: it draws a measurement between them and shows the distance. Today the shipped caliper is deliberately straight-only: your measurement reads horizontally or vertically, whichever way you are measuring, because UI redlines are almost always axis aligned. The mock, however, draws the caliper rotated to the exact angle between the two points, like a real pair of calipers.

## Where to see it

- The [Measure & redline mock](http://127.0.0.1:8791/index.html#redline) draws the rotated (free-angle) caliper.
- The current straight-only behavior is what shipped after the caliper redesign (phase 16.12), which removed free-angle mode on purpose after it made ordinary axis-aligned measuring fiddly.
- The measure spec: `docs/design/next-measure.md`, section 3.

## What each option feels like

- **Straight only.** Click two points, get the horizontal or vertical distance. You can never accidentally measure a sloppy diagonal when you meant a width. A true diagonal (an off-axis icon, a slanted decoration) cannot be measured directly, which in UI work is rare.
- **Straight by default, hold Shift for the diagonal.** The everyday behavior stays simple; the diagonal exists for the rare case. The cost is a hidden mode: modifier keys are easy to never discover and easy to hit by accident.
- **Free angle always.** Matches the mock drawing exactly, but every ordinary measurement now needs careful aim, which was precisely why the earlier free-angle caliper was redesigned away.

## Why the recommendation is straight only

The redesign already litigated this: axis-aligned measuring is the job, and the free-angle mode was removed because it taxed the common case to serve the rare one. The mock drawing is attractive but the shipped behavior is the one users measured faster with.
