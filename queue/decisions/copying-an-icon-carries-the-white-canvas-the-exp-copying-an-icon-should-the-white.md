# Copying an icon: should the white canvas come with it?

## The short version

There are two ways to hand a drawing to something else, and they have stopped
agreeing with each other.

- **Save it.** File ▸ Export as PNG. The sheet now carries a checkbox,
  *Include the background*, and it starts unticked, so the file you save has
  nothing painted behind the drawing.
- **Copy it.** Shift Command C. There is no sheet, nothing to tick, and what
  lands on the clipboard still has the white canvas baked into it.

So the icon you save is see-through and the icon you paste is not. This card is
about which of those two is right for Copy.

## What it looks like

The same drawing, pasted onto a dark page.

**Copy today**

![A red arch on a big white rectangle, sitting on a dark page with a hard white box around it](copying-an-icon-carries-the-white-canvas-the-exp-copying-an-icon-should-the-white-today.png)

**Copy with the canvas left out**

![The same red arch on the dark page with nothing behind it](copying-an-icon-carries-the-white-canvas-the-exp-copying-an-icon-should-the-white-canvas-left-out.png)

The second one is what Export already gives you if you save the file instead.

## What a canvas is, exactly

When you start a blank drawing, the white you see is a real layer: a full-size
picture of white sitting under everything, so that a fill or an eraser has
something to work on. It shows up in the layers list like anything else.

That is why this is a question at all. Nothing anywhere says whether that white
is your *paper*, which you are working on top of, or your *page*, which is part
of what you are making. Sometimes it is one and sometimes it is the other, and
Photonz cannot tell the difference by looking:

- Drawing an **icon** on a blank canvas, the white is paper. You want the icon
  on its own.
- Drawing a **wireframe or a screen** on a blank canvas, the white is the page.
  Its light grey boxes and dark grey lines only read because the page is
  behind them. Paste that with no page into a dark chat and the lines land on
  the dark and disappear.

A **screenshot, a photograph or a screen capture never enters into it.** Its
bottom layer is a picture with detail in it, not one flat colour, so nothing
recognises it as a canvas and nothing is ever taken away from it. That is true
under every option below.

## What each option feels like

### A. Copy leaves the canvas out too

Shift Command C behaves like the saved file. One rule, no new commands, and the
report's complaint goes away completely.

The cost is that the white version stops existing on the clipboard. There would
be no key, no menu item and no modifier that gets it back: you would have to
save a PNG with the box ticked and hand the file over instead. For anyone
copying a wireframe into a dark surface, that is a step backwards from today.

And because Copy has no sheet, it is a change nobody is told about. Export can
afford its default because you see the unticked box and the colour swatch every
single time.

### B. Copy leaves it out, holding Option copies it with

The default is option A. Open the File menu holding Option and *Copy Image*
reads *Copy Image with Background* instead, on its own shortcut, and does
exactly what Copy does today.

This is how Mac apps have always offered a variant of a command, so it adds
nothing to the menu you have to look at, and nothing is lost. The honest cost is
that a variant behind Option is easy never to find. Against that, the Export
sheet is already teaching the same idea in plain sight, with the same words, so
somebody who has exported once knows the choice exists.

This is the recommendation.

### C. Copy keeps the canvas, a second command leaves it out

Shift Command C is untouched. A new item, *Copy Image Without Background*, sits
right under it in the File menu, always visible.

Nothing anybody does today changes, and both results are on screen rather than
hidden. But the thing that was reported stays true: save gives you see-through
by default, copy gives you white by default, and you have to remember which is
which.

### D. Leave copy alone

Copy keeps the white. Handing an icon over see-through stays an Export job.
Picking this retires the task for good.

## If you want to see it yourself

Open a new blank drawing, draw a shape on it, press Shift Command C, and paste
into anything with a dark background. Then File ▸ Export the same drawing as a
PNG and open that file over the same dark background. The two pictures above are
those two results.
