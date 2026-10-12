# Which moving title backgrounds stay, and which do new titles start on?

## What this is about

A title page in a video (the full screen card with a headline, before or between
clips) has a background. Until now that background was a flat colour, a still
gradient, or "Mesh", a faint drift you described as static noise.

There are now ten backgrounds that move by themselves, drawn fresh every frame
by the app (no video files). You pick one from the **Background** row in the
**Title** section of the right hand panel: it opens a grid of tiles, and every
tile plays its look in your title's own colours. Under the row, four sliders
tune the picked look: **Speed**, **Strength**, **Scale** and one that is the
look's own (Height, Trail, Softness, Angle, Warmth, Line Weight, Depth, Gloss or
Horizon).

## The ten looks

Each one has a four second movie and a GIF in `queue/audits/`, filmed behind
the Midnight title page with its Night colours:

| Look | Movie | What it does |
| --- | --- | --- |
| Aurora | `2026-10-12-live-backdrops-aurora.mp4` | Curtains of light rippling and changing colour |
| Energy Streams | `2026-10-12-live-backdrops-energyStreams.mp4` | Glowing lines with bright packets racing along them |
| Color Bubbles | `2026-10-12-live-backdrops-colorBubbles.mp4` | Big soft circles drifting, swelling and fading |
| Light Rays | `2026-10-12-live-backdrops-lightRays.mp4` | Beams falling through haze, sweeping slowly |
| Light Leaks | `2026-10-12-live-backdrops-lightLeaks.mp4` | Warm film washes sliding across |
| Wind Streams | `2026-10-12-live-backdrops-windStreams.mp4` | Fine lines following a flowing wind, with streaks running along |
| Architectural Sketch | `2026-10-12-live-backdrops-sketch.mp4` | A building drawn line by line, then held with a slow drift |
| Particles | `2026-10-12-live-backdrops-particles.mp4` | Dust and sparks at three depths |
| Liquid Gradient | `2026-10-12-live-backdrops-liquidGradient.mp4` | Your colours folding and flowing like liquid, with a sheen |
| Grid Horizon | `2026-10-12-live-backdrops-gridHorizon.mp4` | A glowing grid racing toward you under a horizon glow |

All ten side by side, six frames across two seconds:
`queue/audits/2026-10-12-live-backdrops-contact.png`.

## One thing to know before choosing

Words always have to read. So no look is allowed to get brighter than a set
limit behind white words (or darker than a limit behind dark ones), and words
in a lighter second colour get a soft shade where they need it. That limit is
why **Light Leaks** reads brownish rather than blazing: real light leaks are
very bright, and white words would vanish into them. Option D is the way to
make it bright and lean harder on the shade instead.

## The options

- **A. Keep all ten, titles start on Aurora** (recommended): nothing is taken
  away, and the most obviously alive look is what a new title page shows first.
- **B. Keep all ten, titles start on Liquid Gradient**: the calmest look as the
  starting point.
- **C. Drop Light Leaks and Wind Streams, start on Aurora**: a shorter list of
  the strongest eight.
- **D. Keep all ten, rework Light Leaks to be brighter**: start on Aurora, and
  make Light Leaks truly bright with a heavier shade on the words.

Building did not wait on this. The answer goes to the task that rebuilds every
built-in title on these backgrounds, which applies it.
