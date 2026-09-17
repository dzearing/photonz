# Pointing a copy at a different component

## What a copy is

The Library holds components: a Button, a Card, a Nav Bar. Drag one onto a
screen and what lands is a **copy** of it. The copy is not a snapshot. It keeps
following the original, so editing the original changes every copy of it
everywhere, which is the whole reason components exist.

A copy also has settings of its own, called knobs: the words on a button, its
corner radius, the room it holds inside its edges, whether a part shows at all.
Those are yours, per copy, and they survive edits to the original.

## What you cannot do today

You cannot change your mind about **which** component a copy follows.

Put a Primary Button on a screen, set its label, nudge its corner radius, give
it the room you want, and then decide it should have been a Secondary Button.
There is no way to say so. You delete it, drag the other tile out of the
Library, and set all of it up again from nothing. On a screen carrying twenty
copies, trying a different button means doing that twenty times, so in practice
nobody tries. That is the cost: it is not that the change is slow, it is that
the change does not get explored.

Every other tool of this kind has this. In Figma it is called swapping an
instance and it is a row in the right hand panel.

## What the options feel like

**A row in the panel.** Pick the copy. The Component section of the right hand
panel already tells you which component this copy follows. Under this option
that line becomes a control: click it, choose another component, and the copy
becomes one of those instead, standing in the same place, at the same size,
carrying over every setting the new component also offers.

**Drop the new one on top.** Nothing changes in the panel. You drag a tile out
of the Library the way you always do, but you let go directly on top of a copy
that is already on the canvas, and it takes that copy's place. Letting go
anywhere else places a new one, exactly as it does now.

**Both.** The row teaches you it is possible; the drop is what you use once you
know.

**Leave it.** Deleting and re-placing stays the way to change your mind.

## What carries over, whichever way you do it

Not everything can. The new component may not have the knobs the old one had.

- Where it sits on the canvas, and how big it is: kept.
- A knob the new component also has, matched by name: kept, with your value.
- A knob the new component does not have: dropped. The app says how many were
  dropped rather than losing them quietly.
- One undo puts the whole thing back, knobs included.

## Why you are being asked

This adds something to the screen that you have not asked for, and the shape of
it is a matter of taste rather than engineering. The loop built a capture loupe
straight off its own suggestion on 2026-09-02 and it was rejected on sight; this
is the question that would have avoided that.

It is also worth saying plainly that option D is a real answer. A first version
of a design tool where you delete and redo is defensible, and picking D retires
the task rather than parking it.

## Where to look

- The Component section of the right hand panel, on any copy you have placed.
- `docs/design/ui-building.md`, the section "What the first version deliberately
  does not do", which records the related limit: detach is one way and there is
  no re-attach.
