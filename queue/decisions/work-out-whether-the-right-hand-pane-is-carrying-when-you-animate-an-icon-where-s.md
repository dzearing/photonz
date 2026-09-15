# Where should the timing of an animation appear?

You said you were worried the side pane is overused real estate, right after saying
that animating a property "should be applied to a timeline that is bigger than the
property panel". This is that question, answered with numbers first.

**The study page is on the dashboard:**
[Is the right hand pane overloaded?](http://127.0.0.1:8791/index.html#pane-load)
It shows the same bell icon in the arrangement we have and the one proposed, side
by side, plus what the window looks like small, ordinary and large.

## What was measured, before anything was proposed

The right hand panel was measured in the running app, not estimated. A document
with three layers in it, one piece of text picked, one drop shadow on the text,
nothing unusual at all:

| | |
| --- | --- |
| What the panel wants | **1052 points** |
| What a 1680 by 1000 window gives it | 968 points |
| What a 1200 by 720 laptop window gives it | 688 points |
| What a 1000 by 640 window gives it | 608 points |

Where it goes: Layers 163 · Text 198 · Appearance 223 · Effects 332 · Position
and Size 130.

So **the panel does not fit at any window size, today, before animation exists**.
Position and Size, which is just X, Y, width and height, is below the bottom edge
in all three. One open drop shadow costs 332 points, more than Text and Position
and Size put together, and it cannot be shrunk because the panel has to draw the
effect you opened whole.

That is a separate problem from this decision, it is filed separately, and no
answer here fixes it. It matters to this question only because it says the
pressure on the panel is not coming from animation.

## What is actually the wrong shape for a narrow column

Of the twenty six sections the panel can show, exactly two:

- **The Library shelf.** It is a grid of thumbnails and a 265 point column fits
  two across. Not part of this decision.
- **Timing.** And this one is different in kind. Everywhere else in the panel you
  are reading a value. With timing you are reading a **gap**: does the knob start
  after the bell, and by how much. A gap between two bars is a thing with width.
  No amount of height in a column shows it.

That is the whole argument for moving timing out, and it is a narrow one. It is
not "the panel is full so put something somewhere else".

## What you would see, under each option

### A strip across the bottom (recommended)

You pick the bell, open Motion in the panel, and add Rotation. A band appears
across the bottom of the window with a ruler along it and one bar for the bell's
rotation. You pick the knob, add Rotation, and a second bar appears under the
first. You drag the knob's bar a little to the right and it now starts 90
milliseconds after the bell. The gap is drawn, labelled, and draggable.

The panel keeps what changes and by how much: Rotation, from minus 12 degrees to
12 degrees, pivot at the top, ease in out. That is a list you add to with a switch
on each entry, exactly like Effects sitting right above it.

Close it with the × in its own bar and it becomes one row that still reads
*Bell body and Knob · rotation · 900 ms loop*, so you always know what you are
still editing. There is no band at all in a document with no motion in it.

On a 1200 by 720 window the band takes the canvas from 688 to 516 points while it
is open, and back to 658 when collapsed. On a 1000 by 640 window it opens shorter,
110 points, because there is less to show.

### Keep it all in the right hand panel

Nothing new appears. The knob's entry says Start 90 ms and the bell's says Start
0 ms, in two boxes about 200 points apart vertically. You can set it, but you
cannot see it, and you find out whether it looks right by watching the preview
rather than by reading the timing.

### A timing window you open when you want it

Same bars, but floating over the drawing. Full width while it is up. The cost is
that it sits on top of the bell you are trying to watch swing, which is exactly
what you are looking at while you tune the lag.

### Not now

The panel keeps its current shape and no timing surface is built. Animated icons
wait. Picking this ends this piece of work rather than handing it back.

## What it would cost

Naming surfaces rather than guessing hours:

- **The editor window** has never had a band at the bottom. It grows one.
- **The push away rule** has to learn a new shape: today the side panel slides
  away completely, and a bottom band has to collapse to a row that says what you
  are editing.
- **The panel's section list** gets one new section, Motion, built the same way
  Effects is.
- **Keyboard and menus** get one more toggle beside the panel toggle.
- **The scripted walks** that read the panel's own measurements now measure a
  window with a band at the bottom of it.

## What does not move, whatever you pick

Motion itself stays in the panel. What changes and by how much is a list you add
to, entry by entry, with a switch on each, which is what Effects already is.
Splitting one idiom across two surfaces to save a bit of height would cost the
thing that makes it learnable.
