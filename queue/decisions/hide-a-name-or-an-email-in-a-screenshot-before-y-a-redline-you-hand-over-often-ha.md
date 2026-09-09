# Covering part of a picture before you send it

## What happens today

Photonz can take a screenshot, measure it, arrow it, caption it and write out a
spec list. It cannot hide anything in it.

There is a Blur effect, but it is an effect on a layer, so it softens the shape
you drew rather than the picture underneath it. Draw a rectangle over somebody's
email address, add Blur, and you get a soft-edged rectangle sitting on top of a
perfectly readable email address. The only way to hide something today is to
open the picture somewhere else and hide it there.

## Why it matters here

The main thing this app is for is redlining a real screen and handing the result
to somebody. Real screens have real names, real email addresses, real account
numbers and real customer logos in them. Hiding one or two of those is the
ordinary last step before the picture goes into a ticket, a pull request or a
chat. Right now that step happens in another app, which means the workflow this
app exists for leaks out of it at the very end.

CleanShot X ships two versions of this, a soft blur and a blocky pixelate, and
they are near the top of every review of it.

## Why it is cheap to build

The renderer already knows how to draw a layer against the picture beneath it.
That is how the zoom callout works: it magnifies a live region of everything
below it rather than a baked copy. A cover reads the same thing and blurs or
blocks it instead of magnifying it. It is an existing seam with a different
filter on the end of it.

## The four answers

**A cover you drag out, baked on export.** A tool in the bar. Drag a box over
what you want hidden and it goes soft or blocky. While you are working it is a
layer: move it, resize it, undo it. When the picture leaves Photonz, exported or
copied, the pixels underneath are gone from what leaves, so the person who
receives it cannot lift the box off and read what was there.

The catch worth knowing: the Photonz document you keep still holds the original
picture underneath the cover. The export is safe to hand over; the working file
is not, unless a later switch is added for that.

**A cover that is only ever a layer.** The same tool and the same drag, but the
cover never bakes. Simpler and always editable. An exported PNG looks fine, but
if you hand somebody the Photonz file they can drag the cover away and read what
was under it. The risk is that it looks like hiding when it is only covering.

**Redact by cutting instead of covering.** No new tool at all. Use the marquee
that already exists, plus a command that replaces everything inside it with a
solid block right there in the picture. The pixels are genuinely gone
immediately, in every copy of the file. The cost is that it is not adjustable:
if the box is slightly wrong it is undo and draw again, and it is destructive
editing in an app where nothing else is.

**Do not build this.** Photonz stays a capture, measure and redline tool and
hiding things stays somebody else's job. Choosing this retires the task for
good.

## The recommendation

The first one: a cover you drag out, baked on export. It is the only answer
where the thing you send is actually safe, it keeps the non-destructive
behaviour everything else in the app has, and it reuses machinery that is
already written and already tested by the zoom callout.
