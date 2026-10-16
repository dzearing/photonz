# Words that travel into a title, whole or cut

## What this is about

Many built-in titles bring their words in one at a time: a word **rises** up
into place (Keynote Clean, Minimal Underline, Kinetic Bold's subtitle), letters
**track in** from either side, or letters **flip up** toward you. Every text
layer has a box, the one you see as the selection outline on the canvas.

Until now, the picture of the words was cut at that box. A word rising in from
below starts under its resting place, so on the bottom line it was sliced flat
along its feet until it landed. Measured on Keynote Clean, the headline's words
showed as little as 69% of themselves during the first frames of the rise, and
Minimal Underline's letters as little as half.

## What changed

Words in motion now draw in full, even where they pass outside their box. When
the entrance ends they are exactly where they always rested, inside the box.
The canvas, playback and an export all draw this the same way.

Mask Reveal and Wipe still hide words behind an edge, because that edge is the
whole look of those two entrances.

## What to look at

- `queue/audits/2026-10-16-words-whole-contact.png`: one row per entrance, each
  frame showing **Before** over **After**, with the text box dashed. The first
  columns are where the cut was worst.
- One MP4 and GIF per entrance beside it (`2026-10-16-words-whole-*.mp4`), and
  Keynote Clean as the app exports it (`...-keynote-exported.mp4`).
- The real app half a second into Keynote Clean:
  `2026-10-16-words-whole-walk-coming-in-sc.png`. The second word is drawn
  below the selection box while it rises.

## The options

- **a, Keep words whole** (recommended): what is built now.
- **b, Whole, but rising a shorter way**: same as a, and the built-in rises
  travel about half as far, so less of a word is ever outside its box.
- **c, Cut at the box, as before**: puts the slicing back.
