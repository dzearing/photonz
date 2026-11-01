# The one-surface pass did not lift Ask's painting. What now?

## What this is about

When you ask Ask to "paint a small landscape with oil paint", it sketches the
scene and paints it stroke by stroke with the Brush's oil paint, on its own
Paint layer, every stroke editable. The brush epic has one item left: two
model judges score that painting from 1 to 10 on whether it **looks painted**
and whether it **reads as the subject**.

On 1 November you chose option b on the last card: one more pass, lighting
each paint layer as one surface (paint building up where strokes overlap,
each new stroke lit against the paint under it), shipping only if the try
path painting reached **5 and 6** on looks painted, a skilled person's
digital painting's score.

## What this pass found

It was built properly, not as a sketch: the layer remembers how thick its oil
stands, and the stroke under your hand shows exactly what lands. Then it was
measured:

| Version | Looks painted | Reads as a landscape |
| --- | --- | --- |
| Before this pass, try path (judged again today) | 4, 5 | 7, 8 |
| One surface, seven variants on a test sketch (softer ridges, more colour variety, thick build-up, a canvas weave) | 4, 5 every time | 6 to 7 |
| One surface, the try path itself | **4, 5** | **8, 8** |
| A skilled person's digital painting (Krita) | 5, 6 | 9, 9 |

The judges also move about a point between runs: the last pass's best
picture, which scored 5 and 6, scored 5 and 5 when judged again today.

So the gate was not met, and nothing shipped. The code is saved as a patch
(`queue/audits/2026-11-01-brush-epic-one-surface.patch.txt`) in case it is
wanted later.

What the judges name, in every version: "even, repeated streaks", "uniform
digital stroke texture", "crude keyhole-shaped trees". That is about how Ask
paints (the same stroke at the same size everywhere, simple shapes), not how
the paint is lit. Six passes have now tried lighting, relief, colour, stroke
ends and a canvas weave.

## The options

- **A. Close the epic as it stands.** Ask paints a recognisable picture with
  real strokes; it looks a point more digital than a person's digital work.
- **B. Close it, and file "Ask's paintings look less digital" as its own,
  lower priority task** (recommended). That task works on what the judges
  name: varied strokes across one painting (dabs, long sweeps, thin scrubbed
  passages, thick highlights) and better shapes, with the same 5 and 6 bar.
  The epic stops holding the top of the queue.
- **C. Keep this task open and try the stroke variety here,** at the top of
  the queue, until the try path painting reaches 5 and 6.

## Where to look

- The picture on the card: `queue/audits/2026-11-01-brush-epic-one-surface-try-path.png`
  (before, after, and the person's painting, side by side).
- The try path painting at full size: `queue/audits/2026-11-01-brush-epic-one-surface-try-path-crop.png`
- Every number and the judges' words: `queue/audits/2026-10-31-brush-epic-measures.txt`, SIXTH PASS.
