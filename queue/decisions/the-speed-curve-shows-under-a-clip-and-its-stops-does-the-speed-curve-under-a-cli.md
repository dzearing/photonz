# How the speed curve under a clip looks

## What it is

When a clip's speed changes across it (speed stops, from the clip's right-click menu under Speed), the timeline now shows a **Speed curve** lane under the clip. It plots how fast the clip plays at each moment on the clip's own clock, with the mock's scale in the gutter (3x, 1x, 0). Each stop is a diamond you drag up, down and along. A stop can be a **Freeze**: the line drops to nought, stays there for the hold, and a second diamond marks where the hold ends.

The design is the timeline dock of the speed mock: http://127.0.0.1:8791/pages/video-speed.html (the "Speed curve" plot under the Retimed clip).

## What to look at

- The reel of a stop being dragged down and back up: `queue/audits/2026-10-17-speed-curve-reel.gif` (also `.mp4`), and the frames side by side in `2026-10-17-speed-curve-reel-contact.png`.
- The app beside the mock in one picture: `2026-10-17-speed-curve-beside-the-mock.png`.

## The question

The mock draws one faint cyan wash under the line and puts the band colours (Slow-mo, Normal, Fast, Freeze) on the clip bar above. The app tints the curve itself by speed: a light wash in each band's colour under the line and a solid strip of the legend colours along the floor.

- **Keep it (recommended):** fast, slow and frozen stretches read at a glance on the curve itself.
- **Quieter:** only the floor strip carries the colours, and the wash goes back to the mock's single faint cyan.
- **Bolder:** no wash; the line itself changes colour along its length.

Whichever you pick, the clip bar above gets the mock's band colours and legend in its own task (`a-ramped-clip-s-bar-is-tinted-by-its-speed-bands`).
