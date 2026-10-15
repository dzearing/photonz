# Which key lets a point inside an icon land exactly where you put it?

## What this is about

When you draw inside an icon frame (a 24 by 24 frame, say), every point you
put down is pulled onto something: a whole unit, one of the keylines, or a
corner, edge or centre of a shape you already drew. That is what keeps an icon
crisp and its exported file clean. You can see it working: a small ring sits
where the point will land, with a blue pill beside it naming the spot in the
icon's own units ("9, 10").

Sometimes you want to put a point somewhere none of those pulls would allow.
The question is which key you hold to do that.

## Where it comes from

- The icon mock, **Draw an icon on the grid**
  (`docs/design/mocks/pages/icon-draw-wt.html`, step 3), says:
  *"Nothing is forced: holding ⌃ suspends snapping for one drag."*
- Everywhere else on Photonz's canvas, **Command** has always meant "exactly
  where I put it": drawing a shape on a screenshot, measuring, moving a layer
  near the grid.

## What you would experience

**A. Command, as everywhere on the canvas (recommended).** Hold Command while
you click or drag and the point lands exactly under the pointer, inside an icon
or not. One key to learn. Control-click keeps meaning right-click, as it does
in every Mac app.

**B. Control inside icons, Command elsewhere.** Matches the mock. But on a Mac,
Control held while you press the button is a right-click, so pressing with
Control down opens a menu instead of starting a drag. It would only work if you
start the drag first and then hold Control.

**C. Both keys inside icons.** Either works inside an icon frame; Command only
elsewhere. Friendly to both habits, but two answers to one question, and the
same right-click catch as B.

## Already built, whatever you pick

- View ▸ Snap in Icons ▸ **Grid**, **Keylines**, **Geometry**: the mock's three
  Snap to choices, each turning its pull on or off for as long as you like.
- The ring and the pill naming the landing spot.
- Shapes' edges and centres as targets, as in the mock's step 6.
