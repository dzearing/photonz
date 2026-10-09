# Should Measure stay in your hand after a Size or Gap click?

## What this is about

The measure-redline goal promises that someone who uses Shottr or CleanShot X
gets from a screenshot to a redline they can paste into a chat in no more steps
than there. Nobody had counted, so we counted. The job: capture a region, then
measure one button's size and one gap, then copy the picture.

| | Steps |
| --- | --- |
| Photonz, Next as it ships today | **10** |
| Shottr | **9** |
| CleanShot X | can't do it on its own: it has no measuring tool. Its sister app PixelSnap 2 measures the live screen, and its documentation doesn't show whether a size and a gap can go into one picture |

The full table, with each app's documentation quoted, is section 13 of the
measure design notes (`docs/design/next-measure.md`).

## Where the extra step is

Photonz's ten steps: ⇧⌘4, drag, ⇧⌘6 to open it, I for Measure, I for Size,
click the button, **I to pick Measure up again**, I for Gap, click the gap,
⇧⌘C.

The step in bold happens because a measurement, like everything you draw,
hands you the thing it made with the pointer tool in hand. That was your rule
on 2026-08-22 and 2026-09-15 ("after i create a shape, it doesn't select it and
switch to V tool"). So the second measurement starts by picking the tool up
again. Shottr made the opposite choice on purpose: its release notes say
"Shottr keeps selected tool after the object is created (it's quicker now to
add multiple arrows, counters, etc.)". Photonz wins a step back elsewhere: one
Size click gives width and height together, where Shottr's ruler takes two
imprints.

Here is the capture just after the Size click: the width and height are
placed and picked, and the tool bar shows the pointer tool, not Measure.

![Size landed, the pointer tool in hand](2026-10-09-capture-to-redline-size-landed.png)

And after the gap, which is what ⇧⌘C copies:

![A size and a gap on the capture](2026-10-09-capture-to-redline-size-and-gap.png)

## The options

**A. Measure stays in hand after Size and Gap (recommended).** Click a button
in Size and its width and height land. The outline keeps following the pointer,
and the next click measures the next thing. What you just placed isn't picked,
so the panel shows the tool's settings, and the arrow keys don't nudge it until
you press V and click it. Distance, the three-click caliper you place by hand,
still hands you what you drew, because that's the one you're likely to adjust.
Photonz becomes 9 steps, level with Shottr, and every extra thing measured in
a redline saves another step.

**B. Keep it as it is.** Every tool ends the same way and the measurement you
just placed is ready to nudge or rename. Photonz stays one step behind Shottr,
and this success item stays unmet. Picking this retires the task.

**C. A region capture opens straight in the editor.** This saves the open step
(⇧⌘6) instead, the way Shottr's default does. But every screenshot you only
meant to paste would open a window you then have to close, and it replaces the
corner toast. Not recommended. If it were a setting that's off by default, the
default count would still be 10.

## How it gets checked

The count comes from a scripted walk
(`Scripts/playtest/capture-to-redline-steps-walk.json`) that goes from the
capture shortcut to the picture on the clipboard at Next defaults. Before it
presses I again, it waits for the tool to read Select. Whichever option you
pick, the walk changes to match and the table gets recounted.
