# The Layers list says four selected and shows two rows

## What you would see

Paint a rectangle and save its fill as a style called Accent. Group that
rectangle with a second one, turn the group into a component, and drop one copy
of it on the canvas.

Now open the style and press Select What Uses This. It picks four layers: the
two rectangles inside the original, and the two pieces inside the copy. The
Layers list says **4 layers selected** and shows **two rows**, because a copy
has no twist open and its pieces have no rows of their own.

Everything the app then does is correct. Type a new X and the original moves
with the copy following it. Nothing else on screen says a different number.

## Why it happens

A copy of a component is one row in the list, on purpose: its insides are the
original's business, and opening every copy would bury the list. But a style is
worn by the pieces, not by the copy, so anything that asks "where is this style
used" honestly finds pieces inside copies.

So the count is counting a real selection and the list is showing a deliberate
view of it. They are both right and they do not match.

## What each answer means

**Say how many are inside copies.** Four stays four, and a short line under it
says two of them are pieces inside copies. Nothing about which layers get picked
changes, you just find out that the reach went further than the rows. This is
the recommendation because it is the only option where neither the number nor
the rows have to become less true.

**Count only the rows you can see.** The list says two. The pieces inside copies
are still picked and still change when you edit. It looks tidy and it means the
app is changing things it never mentioned, which is the kind of surprise that
makes people distrust undo.

**Only pick what has a row.** The button stops reaching into copies at all.
Selection and rows always agree, and the button stops doing the job it exists
for: repainting a colour everywhere it is used now means visiting each copy.
Worth knowing that editing the style itself still repaints everything, copies
included, so this is less limiting than it sounds.

**Leave it alone.** What happens today. It has never produced a wrong result,
only an unexplained number.

## Where to look

`Scripts/playtest/style-users-walk.json` walks exactly this, and the picture of
it is the fourth step.
