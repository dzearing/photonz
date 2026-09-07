# A tool setting that is on screen twice

## What this is about

Some tools in Photonz have settings: how far a colour may drift before the
Magic Wand stops selecting it, whether the next Zoom Callout comes out a box or
a circle, what Measure snaps to and which measurements it shows.

Those settings used to live only in the right hand panel. That meant hiding the
panel, a normal thing to do while you look at a picture, took them away with it.
So in September a small capsule was added just above the floating tool bar,
carrying the settings for whatever tool is in your hand.

It works. But nothing was taken out of the panel when the capsule arrived, so
with the panel open the same rows are now on screen in two places at once.

## What it looks like today

Pick up the Zoom Callout with the panel open, and this is at the top of the
panel:

![The Zoom Callout's settings in the panel](2026-09-07-tool-twice-in-the-panel.png)

...while this is floating over the bottom of your picture at the same time:

![The same two settings in the capsule](2026-09-07-tool-twice-in-the-capsule.png)

Same two words, same order, same controls. Moving either one moves the other,
because they are one value, not two.

Here it is in the whole window:

![The Zoom Callout, panel open](2026-09-07-tool-twice-callout.png)

The Magic Wand is nearly the same story, except the panel has the longer slider
and a sentence saying what tolerance means, which the capsule does not:

![Tolerance in both places](2026-09-07-tool-twice-wand.png)

Measure is the awkward one. Snap and Show are in both places, but Mode is only
in the panel:

![Measure, panel open](2026-09-07-tool-twice-measure.png)

And Crop is the reverse. It has a panel section and no capsule at all, so
whatever rule we pick has to leave Crop working:

![Crop's Aspect, panel only](2026-09-07-tool-twice-crop-has-no-capsule.png)

For contrast, this is the capsule doing the job it was built for, with the panel
hidden. Nothing in this decision takes that away:

![Panel hidden, capsule carrying the settings](2026-09-07-tool-twice-panel-hidden.png)

## What you are choosing

Not whether both places keep working. They do, under every option. You are
choosing where your eye should go when you have a tool in your hand and the
panel is open.

### A. The panel holds them while it is open

The capsule stops appearing while the panel is open. Pick up the wand and its
Magic Wand section opens at the top of the panel and scrolls itself into view;
the bottom of your picture stays clear. Press Option Command L to hide the
panel and the capsule is back, exactly as it is today.

You would notice: the picture is less covered, and the settings are always in
the fuller form, with the long slider and the sentence. You would also notice
that they move from bottom to right when you show the panel.

### B. The capsule holds them whenever it is up

The opposite. The capsule is the home for the tool in your hand at all times,
and the panel stops showing the tool's section while the capsule has it.
Measure's Mode would move into the capsule so it is not stranded, and Crop,
which has no capsule, would keep its panel section.

You would notice: the setting never moves, it is always in the same spot just
above the tool you clicked. You would also notice the capsule sitting on your
picture the whole time, a wider one for Measure, and the wand's explaining
sentence becoming a tooltip instead of a line you can read.

### C. Leave it in both places

Nothing changes. Choosing this retires the task rather than sending it back to
be built.

## Worth knowing

- The capsule is small. Measured on a 1280 by 840 window it is at most 340 by
  36 points against a 1015 by 808 point picture, about 1.5% of it, in a band 76
  to 112 points up from the bottom edge.
- The panel is usually roomy here. With nothing selected it holds Layers and the
  tool section and then a lot of empty space, as every picture above shows.
- Modes are not part of this. Which shape Crop keeps and what a Measure click
  does both live inside their tool button as well, reachable by pressing and
  holding it, whichever option wins.
