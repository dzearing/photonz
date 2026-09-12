# What should Corner Radius round when you have picked a group?

## The thing on screen

In the editor's right hand panel there is a section called **Appearance**, and
in it a row called **Corner Radius**: a name, a number on the right, and a
slider under it. Pull the slider and the thing you have picked gets rounder.

Over a plain box that is simple. The row reads the box's own curve, and pulling
it curves the box.

A **group** is different. A group is two or more things bundled together, the
way you bundle a red rectangle and the word "Save" to make a button. A group
draws nothing of its own. It has no edge, no fill, no outline. All you ever see
of it is the dashed marquee around it while it is picked.

So when the row is asked how round a group is, it has only one thing it can
truthfully answer about: the group's own **crop**, which is a box that clips
whatever is inside it. That box is invisible.

## What went wrong

Pick a button you made by grouping a rounded rectangle and a label, and the row
said **Corner Radius 0** with the knob at the far left, sitting directly above a
button that was visibly, obviously round.

Underneath there are two different cases, and they turned out to need different
answers.

### Case one: the contents fill the group

Group a rounded rectangle with a label sitting on top of it, and the group's box
is exactly the rectangle's box. The rectangle IS the group's edge.

Here the row really was just counting from the wrong place. A crop can take a
corner away and can never put a curve back, so the first stretch of the pull,
from 0 up to the rectangle's own 18, was cutting less than the rectangle already
curved and the canvas sat perfectly still. Past 18 the button did start rounding.

**This half is fixed and has shipped.** The row now reads 18, the knob starts at
18, and the first nudge rounds the button. Nothing about a plain rectangle or a
screenshot changed.

### Case two: there is room around the contents

Now give that same group 16 points of padding, so the button sits in from the
group's edges. This is the case the original report came from.

The group's corners are now empty. Nothing is painted there. So the row reads 0,
and that is honestly true of the group's box.

But the slider is now almost entirely useless. Its track runs to 76, and the
crop does not reach far enough in to touch the button until around 73. Pulling
it to 22 changes **nothing on the canvas except the dashed selection marquee**,
which disappears the moment you click away.

That was checked rather than reasoned about: a probe build was driven through
the pull and the button's pixels came out identical before and after. Only the
marquee changed.

This is the same complaint as the rule set on 2026-09-07, that a slider which
does nothing to the thing you have picked teaches you the panel is lying.

## What you are choosing between

### Round what is inside it (recommended)

Picking a group and pulling Corner Radius rounds the shape inside it, whatever
room is around it. Pick "Save button", pull the row, the button rounds.

The number on the row always describes something you can actually see.

What you give up: cropping a group by its own corners stops being a thing this
row does. It is a genuinely useful thing occasionally, mostly for clipping a
screenshot, but it is not what most people reach for this row to do, and it
would need another way in.

Where a group holds several different shapes, all of them round together. That
is not a new idea to learn: picking several shapes at once and pulling this row
already does exactly that.

### Keep it a crop, and show the crop

The row goes on meaning "round off this group's box". The fix is to stop the
pull being invisible: while the knob is held, the box being rounded is drawn on
the canvas, so you can see the crop closing in even while it is still cutting
empty space.

Honest, and it keeps the crop reachable. But the number still reads 0 next to a
round button, and you still cannot round the button from here.

### Leave it as it is

Groups whose contents fill them keep the fix that shipped. Groups with room
around their contents go on reading 0 and go on rounding only the marquee.

Choosing this retires the task.

## Where to look

- The editor itself: pick any group in the canvas and watch the Appearance
  section on the right.
- The pictures in the audit on the dashboard under **Corner Radius over a
  group** show both cases, the fixed one and the one still open.
