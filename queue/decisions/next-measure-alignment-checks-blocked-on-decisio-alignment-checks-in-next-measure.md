# What is alignment checking?

## The feature in one paragraph

When you redline a screenshot, one of the questions you ask most is "do these things actually line up?" A row of icons, the left edges of stacked cards, a label and its field. Alignment checking is the tool answer: the app tells you whether a set of elements share an edge, and if not, which one is off and by how many pixels.

## Where to see it

- In the [Measure & redline mock](http://127.0.0.1:8791/index.html#redline), look for the dashed vertical guide spanning four elements with a small "aligned" tag, and the panel row reading "Left edge alignment / 4 items".
- The measure spec: `docs/design/next-measure.md`, alignment section.

## History that matters here

An earlier version of this idea (draggable alignment guides, phase 16.6) was built and then rejected: it felt like busywork to place guides by hand for little payoff. That is why this decision exists instead of just building the mock as drawn. Whatever we choose has to be less work than eyeballing, not more.

## What each option feels like

- **Draw an alignment guide yourself.** You drag along an edge; everything the line crosses gets checked. Direct and precise, but it is a hand tool, and the last hand tool version got rejected. The difference this time: the guide answers a question (aligned or not, and who is off) instead of just being a visual ruler.
- **Let the app find alignment problems.** You select a region; the app lists everything misaligned inside it. No effort, but findings you did not ask about can be noise, and you cannot interrogate one specific edge.
- **Skip for v1.** Sizes and gaps ship first; alignment waits for real usage to teach us which of the above is right.

## Why the recommendation is the guide

It answers the exact question you have, at the exact edge you care about, and it only exists while you ask. But the earlier rejection is real evidence against hand tools, so if that history feels decisive, the automatic option or skipping are both defensible.
