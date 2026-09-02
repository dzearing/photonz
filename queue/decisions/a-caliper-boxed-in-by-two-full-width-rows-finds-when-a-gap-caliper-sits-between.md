# Where does a caliper's number go when two full-width rows box it in?

## The feature in one paragraph

The Measure tool draws a caliper between two edges and hangs a red pill with the number on it. Since the last round of work, a caliper knows which elements its feet landed on and steps its number off them into whitespace: below a pair of buttons, beside a text field, wherever it finds room within about three pill heights. This question is about the one case where there is no room: a caliper standing in the space between two rows or cards that run the full width of the picture. Every direction the number could step is on one of the rows, so today it stays put on the caliper and its pill overhangs both rows by a few pixels.

## Where to see it

- Photonz Dev, Experiments window, release Next. Press M, choose Gap mode, and hover the space between the two settings cards on the audit capture (the settings pane used by the measure audits). Every example below is that space, measured mid-row.
- The earlier audit that raised it: `queue/audits/2026-09-02-caliper-subjects.json`, rough item 1.
- The same limit shows up for a Size readout on a full-width row (`queue/audits/2026-08-23-size-readout-placement.json`, rough item 1). Whatever is chosen here is the rule for that case too where it can apply.

## What each option looks like

### Stay on the line, straddling both rows (today)

![The number centred on the caliper, overhanging both cards](2026-09-02-boxed-in-a-straddle.png)

The number is at the gap, where you look for it, and every number in the spec is the same size. The cost is the overhang: the pill covers the two card edges just beside the caliper feet. At the picture's own scale that is a few pixels per side.

### Shrink the number to fit inside the gap

![A smaller pill sitting inside the gap](2026-09-02-boxed-in-c-shrink.png)

When the gap is narrower than the pill, the pill scales down until it fits with a little breathing room, never below about two thirds of its usual size. The number touches nothing and sits exactly on the space it describes. The cost is mixed pill sizes across one spec, a small pill that is harder to read on a dense capture, and a label size slider that no longer means what it says at tight spots.

### Step past the foot onto the blank part of the next row

![The number just below the lower foot, inside the next row](2026-09-02-boxed-in-b-past-foot.png)

The number slides along the caliper past its lower foot onto the empty stretch of the row below, touching the foot. Both measured edges stay visible and the number stays full size. The cost is that the number now sits inside a row and can read as that row's measurement. It also depends on the row having blank space right there; where the foot lands beside a label it is no better than straddling.

### Send it out to the page margin on a long connector

![The number at the left edge of the picture on a long connector](2026-09-02-boxed-in-d-margin.png)

The number travels sideways past the end of the rows into the page margin, tied back by a thin connector. It only works when the margin is wider than the pill. On this capture it is not, so the pill lands on the end of the card anyway and the connector runs most of the picture width. A number that far from its caliper stops reading as that caliper's number.

## Why the recommendation is to stay on the line

Each alternative buys a few uncovered pixels with something worse: a number that changes size, a number that looks like it belongs to a row, or a number far away on a leash. Straddling is the one answer that is always in the same place, always the same size, and always readable, and the feet stay visible past the pill. If the overhang bothers you in practice, the shrink option is the next best: it is the only one that keeps the number unmistakably at the gap.

## Worth knowing

While rendering these, a second problem showed up: when the caliper stands under a row's label text, the row above is sometimes not recognised, and the number is nudged up onto the label. That is a detection bug, not part of this decision, and it is filed as its own task.
