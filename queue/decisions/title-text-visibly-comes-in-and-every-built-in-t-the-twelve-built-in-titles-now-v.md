# Do the rebuilt built-in titles look produced?

## What this is about

Photonz ships twelve built-in titles: nine full-frame **title pages** and three
**name cards** (lower thirds). You find them on the Library's Comps shelf under
Titles, and in Insert > Add Title Page / Add Name Card.

On 2026-10-11 you said the words "don't even move in". Measured, you were right
in effect: no headline was on screen at its first frame, but every one was fully
in about a third of a second later. Each in was half a second on a curve that is
nine tenths done a third of the way through, and the words moved twelve points.
The old contact sheet sampled its "in" frame after that, so the headline looked
already standing.

## What changed

- **Every headline now takes most of a second and is seen arriving.** A test
  measures it on the real renderer for all twelve: under a tenth of the headline
  on the first frame, between a fifth and four fifths of it half way through its
  in, never all there before 400 ms, and the same on the way off.
- **Each one comes in its own way:**

| Title | Headline entrance | Background |
| --- | --- | --- |
| Keynote Clean | words rise in one after another, motion blurred | drifting specks of light (Particles) |
| Soft Gradient Glass | words sharpen out of a deep blur | Liquid Gradient |
| Kinetic Bold | words slide up out of their own line with a little spring | Wind Streams on blue |
| Editorial Serif | words swing up on a hinge at their foot | Architectural Sketch on paper |
| Tech Terminal | typed a letter at a time, then the cursor | Grid Horizon |
| Behind Glass | words fly forward out of depth | your recording, frosted |
| Light Leak | letters close up from wide tracking | Light Leaks |
| Gradient Glow | falls into place from far larger out of a blur | Aurora, in cool colours |
| Stacked Stagger | lines flip up word by word | Energy Streams |
| Split Wipe | wiped on behind a sweeping edge | Light Rays inside the bar |
| Minimal Underline | letters rise one after another | none: the deliberately bare one |
| Pill Card | words settle flat from tipped back | Color Bubbles inside the pill |

- The line under each headline arrives on its own later beat.

## Look at it

- One five second film per title: `queue/audits/2026-10-12-title-set-<name>.mp4`
  (and `.gif`), for example `2026-10-12-title-set-kinetic.mp4`.
- The contact sheet `queue/audits/2026-10-12-title-set-contact.png`: every title
  at 0, 100, 200, 300, 400, 600 and 800 ms and once it holds, over a dark and a
  light recording.

## The options

- **Keep all twelve** (recommended): the reel is the set.
- **Calm two backgrounds**: Keynote Clean's specks and Tech Terminal's grid are
  the busiest; they would be made fainter.
- **A third quicker by default**: what Energy Punchy does today becomes the
  default. Quicker, but the arrival is seen less.
- **Rework Light Leak and Gradient Glow**: the two most assertive backgrounds go
  back for another pass.

A separate card already asks which of the ten moving backgrounds to keep; this
one is only about whether the titles, as built, feel produced.
