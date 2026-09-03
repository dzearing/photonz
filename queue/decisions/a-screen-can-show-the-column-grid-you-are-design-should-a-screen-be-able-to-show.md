# A column grid behind a screen

## What this is about

On 3 September Photonz learned to arrange the contents of a group: a **stack**
lays things along one axis with an even gap, a **grid** fills rows of equal
cells. Those are containers. They hold your pieces and decide where each one
sits.

Designers also use a second thing that is confusingly called a grid: a
**column overlay**. Twelve faint columns with a gutter between them and a
margin at the edges, drawn behind a whole screen. It holds nothing and moves
nothing. It is there so you can see whether the card you just dropped starts on
column 4 and ends on column 8.

Photonz has the first and not the second. This question is whether to build the
second, and if so, whether it should pull at your drag.

## Where it would live

On a screen (the thing the F tool draws), in the Layout section of the right
panel, under the rows that are already there. Three numbers: how many columns,
the gap between them, the margin at the outside edges. A switch to show or hide
it. Each screen keeps its own.

It would draw behind everything on that screen, at every zoom, and would never
appear in an export or a copied picture. It is chrome, like the selection
handles, not part of your document's pixels.

## What you would experience

**Columns you can see.** You set twelve columns on a screen. Faint vertical
bands appear behind your work. You drag a card and watch its left edge against
the band. If it is a hair off, you fix it with the position fields or the align
buttons, both of which are already in the panel. Nothing ever moves on its own.

**Columns you can see and stick to.** The same picture, except that while you
drag, the card pulls onto the nearest column edge when it gets close, with a
short line saying which one it caught. Holding Command drags free. This is the
same behaviour that dragging already has against other layers and against the
edges of the picture.

**Skip it.** Nothing changes. If you want a twelve column layout you build it
inside a grid container, which gives you twelve equal cells but only for the
pieces you put in that one container, not as a rule for the whole screen.

## Why this is a question and not a task

Two reasons.

First, nobody asked for it. It comes out of the design study rather than out of
using the app, and the rule here is that a new thing on screen gets your yes
before it gets built.

Second, on 2 July you turned down alignment guides that appeared while you were
dragging. Snapping to columns is a cousin of that, so the difference between the
first two options is worth your judgment rather than ours.

## What we would recommend

**Columns you can see**, without snapping. It matches how the design tools
people come from actually behave (their layout grids draw and do not grab), it
cannot surprise a drag, and it is a small enough slice that adding snapping
later is a change of one rule rather than a rewrite. If you find yourself
eyeballing and wishing it would catch, say so and snapping is a short follow-up.
