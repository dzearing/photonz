# Do the words now turn in space?

## What this is about

A title's words can come in one at a time by turning in depth: **Swing In**
(each word hangs from an edge and swings up into place), **Flip Up** (each word
flips up about its middle), **Fly In From Depth** (each word flies forward from
far back, turning to face you) and **Tilt Settle** (each word arrives tipped
back and a little turned, and settles). You pick them in a title part's In menu,
by word or by letter.

On 2026-10-11 you said of these, looking at the depth mock: *"that has no
perspective, those are just 2d animations"*. You were right on both counts.

- **In the app**, each word was seen through the frame's own camera, about
  1300 pixels away at 1080p. A word a hundred pixels tall barely changes shape
  at that distance (its near edge measured 1.04 times its far edge half way
  in), and words away from the middle of the line leaned like italic type.
  The curve also had them nearly home by half time.
- **In the mock**, the Ghoztty viewer pane draws pages with WebKit, and WebKit
  drew every 3D stage on that page flat: the card flip, the cube and the
  turned layers were plain slanted rectangles. Chrome drew them correctly.

## What changed

Each turning word or letter now has its own close camera, centred on it, the
way animated type works in browsers and motion tools. Half way in, a turning
word's near edge is 1.3 to 1.6 times its far edge, by word and by letter, and
every word keeps the same shape wherever it sits on the line. The moves are
also half turned at half time now, and Flip Up starts edge on.

The mock page now draws in real perspective in WebKit as well as Chrome, and
its card flip is seen from closer.

## What to look at

- Contact sheet, clip Flip on top for comparison:
  `queue/audits/2026-10-11-text-depth-contact.png`
- One clip per entrance, by word and by letter:
  `queue/audits/2026-10-11-text-depth-entrance-*.mp4` (and `.gif`)
- The first word of each entrance, full size, half way in:
  `queue/audits/2026-10-11-text-depth-midpoints.png`
- The mock in WebKit, before (top) and after (bottom):
  `queue/audits/2026-10-11-text-depth-mock-webkit-before-after.png`
- The mock itself: http://127.0.0.1:8791/index.html#video-depth ("How it feels")

## The options

- **Keep this strength** (recommended): what the reel shows.
- **Stronger**: an even closer camera, near edge about twice the far one half
  way in. More dramatic, words reach further past their box.
- **Softer**: a further camera, near edge about 1.15 times the far one. Calmer,
  but heads back toward the flat look.
