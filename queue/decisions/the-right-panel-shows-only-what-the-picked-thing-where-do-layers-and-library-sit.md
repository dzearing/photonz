# Where do Layers and Library sit when something is picked?

## What this is about

The right hand panel in the editor is meant to answer one question: *what is
the thing I picked, and what can I set on it right now?* You called it
"clogged with useless non contextual crap" on 2026-10-13.

The panel holds two kinds of thing:

- **The pick's own sections.** Appearance, Effects, Motion for a rectangle;
  Measurement for a caliper; Text, Time, Reveal for a title.
- **Lists about the whole document.** Layers (everything in it), Measurements
  (every caliper), Library (what you can add), and on a video Captions and
  Transitions.

Today Layers sits at the top of the panel and the lists stay on screen
whatever you pick. So the panel always starts with something that is not
about the pick. That is the clog this card is about.

## What changed already, and needs no answer

- A tool's settings (Measure Tool, Magic Wand, Crop and so on) show only while
  that tool is in hand, straight under Layers and above the pick's sections.
  A walk now fails if one ever shows with another tool in hand. (The exact
  screenshot you sent, Measure Tool beside a rectangle picked with Select,
  could not be made to happen on today's build in any of 13 states tried.
  The rule now guards it anyway.)
- A picked caliper no longer shows Masked by. Key was already pictures only.
- The 3D section was already gone. Its values are on the small transform bar
  beside the layer.

## What the panel shows today, by pick

Taken by the walk `panel-shows-what-is-picked-walk`:

| What is picked, tool in hand | Sections, top to bottom |
| --- | --- |
| Nothing, Select | Layers, Library |
| Rectangle, Select | Layers, Appearance, Effects, Motion, Library |
| Rectangle, Measure | Layers, Measure Tool, Appearance, Effects, Motion, Library |
| Nothing, Measure | Layers, Measure Tool, Library |
| Caliper, Select | Layers, Measurement, Appearance, Effects, Motion, Measurements, Library |
| Text, Select | Layers, Text, Appearance, Effects, Motion, Measurements, Library |
| A video clip, Select | Properties, Time, Appearance, Effects, Audio (four sections), Captions, Transitions |
| A title, Select | Properties, Time, Text, Reveal, Appearance, Effects, Captions, Transitions |

Pictures: `queue/audits/2026-10-13-panel-picked-02-rectangle-select-sc.png`,
`...-06-measurement-select-sc.png`, `...-title-select-sc.png`.

## The options

### A. Pick on top, lists folded below

The pick's sections lead. The lists sit under them showing only their headers
until you open one. An opened list stays open.

The catch: if Layers is open and you pick a row in it, the new pick's sections
appear above the list, so the list (and the row you just clicked) moves down
under your pointer.

### B. Pick on top, lists in a pane at the bottom (recommended)

Photoshop's layout: Properties above, Layers below, each with its own height.
The pick's sections scroll in the top part. Layers, Measurements and Library
share a pane at the bottom that keeps its height whatever you pick, with a
grip between the two parts.

Nothing jumps when you pick from the list, and anyone who knows Photoshop
finds both where they expect them. It costs height on a laptop window and is
the bigger build.

### C. Lists on the left, the pick on the right

Layers, Measurements and Library move to a sidebar on the window's left edge,
the way Figma and Final Cut place them. The right panel holds only the pick
and the tool in hand. Each side has one job, but the canvas loses width on
both sides, and it moves something you have learned to find on the right.

### D. Keep the lists on top

Nothing moves. Only the rule already shipped applies.

## On a video

On a video the timeline already stands in for Layers, so the panel has no
Layers list there. Captions and Transitions are the lists. Under A or B they
join the others below the pick. Under C they join the left sidebar.
