# A colour let go on a row in the layers list

## What this is about

The Library panel keeps saved colours as tiles. You can pick a tile up and
carry it to any colour well in the right hand panel: Fill, Border, the colour a
shadow is thrown in. That has always worked, and it is what makes a saved
colour feel like a thing rather than a menu entry.

As of a few days ago you can also pick up a saved **text style** and let it go
straight on a **row in the layers list** — no selecting first, no going to the
inspector. Aim it at a row, a line appears under the list saying what letting go
would do ("Sets this text in Heading 2"), and the row lights up. Aim it at a row
that cannot take one and the line says why ("Screenshot is not text, so it
cannot wear Heading 2").

A saved **colour** does not do that. Aim a colour tile at a row and you get the
no entry sign, no line, no explanation. This decision is about whether it should
work, and if so, what it paints.

## Why it is not obvious

A colour well is labelled. The Fill well paints the fill; that is the whole
question answered by where you dropped it.

A layer row is not labelled that way. It carries a thumbnail, a name and two
switches, and the layer behind it might have:

- **one colour** — a box has a Fill and nothing else; a text layer has its Text
  and nothing else. This is most layers.
- **several** — an arrow has its Line, plus a Head when it ends in one, plus a
  label pill's three when it carries a caption. A measurement has its Caliper
  plus the readout chip's three.
- **none** — a screenshot, a plain group. Unless it wears a Border, in which
  case the Border is its only colour, and that one lives in the Effects list
  rather than in Appearance.

So "drop a colour on a layer" has to answer *which* colour, and it has to answer
it for a layer that has none.

## What you would see, option by option

The line under the layers list is the whole safety net here. It is there in
every option, it appears the moment the tile crosses a row, and it says what
letting go would do before you let go.

### Its main colour, named before you let go (recommended)

The colour lands on the one part the Appearance section already leads with —
the thing the layer *is*.

| Row you aim at | What the line says |
| --- | --- |
| A box or an oval | Paints Fill with Brand. |
| A text layer | Paints Text with Brand. |
| An arrow or a line | Paints Line with Brand. |
| A measurement | Paints Caliper with Brand. |
| A screenshot wearing a ring | Paints Border with Brand. |
| A bare screenshot, a plain group | Screenshot has no colour to paint. |
| A locked row | Screenshot is locked, so it cannot be painted. |

Same voice as the text style refusals, same line, same row highlight. Dropping a
colour a layer is already wearing does nothing and says so, the way a colour
well already does.

The one place it can look half done: an arrow whose head is a different colour
from its shaft keeps that head. The line says "Paints Line with Brand" and only
the shaft changes, which is exactly what the Line well in the inspector does
today, so at least the two agree.

### Everything the layer paints

One drop, the whole layer one colour: "Paints all 3 colours of Save button with
Brand." Fast and unambiguous, and on anything with words it produces text you
cannot read against its own background. It also discards whatever colour work
was already on the other parts.

### The row opens so you can pick the part

Hold the colour over a row and the row unfolds into its parts, the way a group
row opens, and you let go on Fill or Border or Text. Nothing is ever chosen for
you. The cost is that the list rearranges itself underneath a moving pointer,
and that nearly every layer has exactly one part, so the common case gets a
second step for no gain.

### Leave colour off the layers list

Keep colours going only to the wells, where the well says what it paints. The
thing to weigh is that the list now takes a text style and refuses a colour, and
nothing on screen explains the difference.

## Where to look

- The layers list is the Layers section of the right hand panel in the app.
- The saved colours are the Library panel's colour tiles; drag one onto a Fill
  well today to see the line and the highlight the row version would copy.
- The text style version of this, already shipped, is the closest thing to a
  worked example: drag a saved text style from the Library onto a text row and
  watch the line under the list.
