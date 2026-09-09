# Floating one piece out of a row that arranges itself

## What happens today

A group in Photonz can arrange its own contents: a row, a column or a grid,
with a gap between the pieces and room around them. Everything inside is in the
line, in order, and moving one piece moves everything after it.

There is exactly one exception. One piece can be made the **surface**, the thing
behind everything else, and it steps out of the line and is drawn behind the
rest. That is how a button's coloured pill and a bar's background work.

There is no way to step out and land in **front**. So the ordinary UI pieces that
sit on top of something else, a notification dot on the corner of an icon, a
"New" ribbon over a card, a small avatar overlapping a header, cannot be placed
where you want them. Drop one into a row and it joins the row and pushes
everything along.

The workaround, and it does work: wrap the card in a second group that arranges
nothing, and put the dot in there beside it. The cost is three steps instead of
one, plus a group in the layers list that is invisible on the canvas, so the
tree stops matching what you see.

## Why it is worth deciding rather than just building

Photonz has been burned by building a feature from competitor parity without
asking first. Nobody has asked for this. It is a real limit and other tools do
have the switch, but that is not the same as somebody wanting it, and the
workaround exists. So this is a question, not a task.

The build itself is small if the answer is yes. The code that decides whether a
piece is in the line already has a hook for pieces that are not, and the surface
is its only member today. Adding a second member is a smaller change than it
sounds.

## The three answers

**A piece can step out and float in front.** The placement control gains one
more answer, sitting next to the one that makes a piece the surface. Pick it and
that piece leaves the line, is drawn in front, and stays where you drag it. The
row arranges itself as though the piece were not there. The thing to watch is
what happens when the container is resized: a piece placed by hand can end up
somewhere odd, which is why the recommendation is to hold it against the corner
of its container the way the placement rules already hold a piece against an
edge.

**Leave it to nesting.** Nothing changes. Wrap the card in a group that arranges
nothing and put the badge beside it. Choosing this retires the task for good.

**Let a drag decide it.** No control. Hold a key and drag a piece out of the
line and it stays where you drop it; drag it back and it rejoins. The panel
reports which it is but never asks. Direct, but an invisible key is a feature
nobody finds.

## The recommendation

The first one. It is one idea with two directions, behind and in front, rather
than two unrelated features, and it says what a piece is doing in a place a
person can read.
