# A locked row inside a stack

## What a stack is

A stack is a group that arranges its own contents. Put three rows in one and
they space themselves evenly along a column: add a row, delete a row, or drag
one past another, and the group puts everything back in order on its own. You
never nudge a row into place; you type a Gap and the stack does the rest.

Turn it on in the Experiments window (release Next, "Groups that arrange their
own contents", on by default), select a few layers and press Control Command G.

## What lock is

The padlock on a row in the Layers list means leave this alone. As of this
week a locked layer draws no resize handles, no rotate knob, and takes no typed
number in the Position and Size panel. It is how you protect the screenshot
underneath while you draw on top of it.

## The disagreement

Inside a stack, those two do not agree. You cannot move a locked row yourself,
but the stack still moves it: delete the row above it and the locked row slides
up with everything else. So the one row you said to leave alone is a row that
keeps moving.

Nothing here is broken; it is a question of what lock should mean once
something else already owns where a layer sits.

## What already changed today

Regardless of this answer, the panel now tells the truth. Select a locked row
inside a stack and the line under X, Y, W and H reads:

> This layer is locked, and the stack it is in decides where it sits. Unlocking
> it in the Layers list gives back its size, not its position.

It used to say "Unlock it in the Layers list to change its position or size",
which is a promise the stack takes straight back: unlock the row and its X and
Y still take no typing, because the stack owns them.

There is a picture of it, and of the locked row sliding up after a delete, in
the audit on the dashboard: **A locked row in a stack says who really owns its
position**.

## What each answer looks like on screen

### A. The stack keeps arranging it

Nothing changes from today. A locked row is protected from you and still
arranged by the stack. Stacks stay tidy: even spacing, no gaps, nothing
overlapping, ever. The panel explains the split so you are not left guessing.

This is the recommendation. It is also what other design tools do: locking a
layer in Figma does not take it out of an auto layout.

Choosing this retires the task.

### B. Locking pins the row where it is

A locked row stops moving at all. The rows around it flow past it instead of
through it.

Stack three rows and lock the middle one. Delete the top row and the middle row
stays exactly where it was, so the stack now has an empty band at the top where
the deleted row used to be. Make the top row much taller and it can no longer
fit above the locked one, so it lands below it instead. Unlock the row and it
drops back into the flow in one undo step.

The gain is that lock means one thing everywhere. The cost is that a stack can
now show a hole, or a row that visibly jumped past its neighbour, and a person
who does not remember locking that row will read both as a bug.

### C. A separate "Leave where it is" switch

Lock keeps meaning do not let me edit this. A new switch in the Layout section
takes one row out of the arrangement while it stays inside the group. It sits
with the Horizontal and Vertical rows that already say who owns each axis, and
it only appears for a layer inside a stack or a grid.

The visible result is the same as B, but you reach it on purpose and you can
still edit the row you pinned. It is the most work of the three, and it is the
answer that scales if pinning turns out to be something you actually want.

## The question

Should locking a row inside a stack stop the stack from moving it?
