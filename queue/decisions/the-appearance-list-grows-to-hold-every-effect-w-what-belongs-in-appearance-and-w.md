# What belongs in Appearance, and what belongs in Effects?

## What you are looking at

Pick a rectangle in Photonz Next and the right hand panel shows two sections,
one under the other.

**Appearance** is the newer of the two. It holds one row per thing the layer
paints: Fill, Outline, and now any shadows you have added. A row that is
switched on shows its own settings on the lines directly below it.

**Effects** is older. It holds three sliders that apply to the whole finished
layer: Opacity, Blur and Corner Radius.

The two read as if they overlap, and that is the report. Add a shadow and
Appearance grows a Blur, a Size and an Opacity, none of which say they are the
shadow's; Effects underneath has a Blur and an Opacity of its own. Four sliders,
two names, no way to tell which is which except by counting rows. There is also
nowhere to put a second border: a border round a layer is one row and one width,
so an inner and an outer one cannot both exist.

## What changed this week, so the pictures are current

On 2026-09-07 the Appearance list became a list you add to, from your answer
*one list you add to*. A shape can now carry two shadows, or a shadow cast into
it instead of behind it, added from a plus on the Appearance header and removed
with a cross. That work is in main and is what the "Today" strip shows.

This decision is the next question: where the line between the two panels
should fall now that one of them can grow.

## The strips

Each option is drawn as the panel for the SAME rectangle: a red fill, an
outline, a border sitting inside the edge, a border sitting outside it, and a
drop shadow. They are mocks, not screenshots, because two borders cannot be made
in the app yet.

### Today

What you reported. Appearance carries the shadow's own Blur, Size, Distance,
Direction and Opacity with nothing to say whose they are. Effects underneath
carries the layer's Opacity, Blur and Corner Radius.

### A. Appearance is what it IS, Effects is what you ADD

The split you proposed, drawn out.

- **Appearance** holds what every shape simply has, in the same order every
  time: Opacity, Fill, Outline, and Corner Radius only on shapes with corners.
  Nothing is ever added to it and nothing is ever removed from it.
- **Effects** starts empty and grows. A plus on its header offers Border,
  Shadow, Glow, Blur. You can add the same kind more than once, so the two
  Border rows in the strip are one inside the edge and one outside it, told
  apart by an Offset setting rather than by being two different effects.
- A part's settings sit behind a line of their own, so a shadow's Blur is
  visibly the shadow's.

The one thing to weigh: Blur and Corner Radius change homes, and blur becomes
something you add rather than a slider that is always there.

### B. One panel, no line to learn

The same content with no second section. What the layer always has sits at the
top in a fixed order, what you added sits under it, and the same plus is on the
one header.

Worth considering because the whole problem is a line people cannot state.
Delete the line and there is nothing to get wrong. The cost is a single long
list, and losing the ability to shut Effects and keep Appearance open.

### C. Change nothing but the ownership

The two panels stay as they are; the only change is the line down the left of a
part's settings. This is the smallest change that fixes the thing you actually
reported, and it leaves the rest of the split for another day. It does not give
you a second border.

## Where to look in the app

The panel is `Appearance` and `Effects` in the right hand dock of any editor
window in the Next release. A live screenshot of the current build, with a
shadow and an inner shadow added, is in the audit for this feature:
`queue/audits/2026-09-07-appearance-list.json`.

## One thing this decision does not settle

An outline that sits OUTSIDE a layer's edge is not built yet, in any option.
Every line Photonz draws today sits just inside the edge, and a line past the
edge has nowhere to be drawn: a shape is rasterized into a bitmap exactly the
size of its own box. That work is filed on its own
(`a-border-can-sit-outside-the-edge-not-only-insid`) and none of the answers
above depend on it; the Offset setting in the strips is what it will hang on.
