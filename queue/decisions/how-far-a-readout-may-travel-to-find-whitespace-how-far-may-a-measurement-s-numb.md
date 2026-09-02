# How far may a measurement's number travel sideways to find whitespace?

## The feature in one paragraph

The Measure tool draws a caliper between two edges and hangs a red pill with the number on it. A caliper knows which elements its feet landed on, and when the pill would sit on one of them it steps sideways into whitespace, tied back to the caliper by a thin connector in the same red ink. The question here is the leash: how far that sideways step may be before the number stops reading as the caliper's number. Today the leash is three pill lengths. Because the pill is wider than it is tall, that is about 130 px for a horizontal caliper and about 280 px for a vertical one.

## Where to see it

- Photonz Dev, Experiments window, release Next. Press M, choose Gap mode, and hover the gaps below on the settings pane used by the measure audits.
- The audit that raised it: `queue/audits/2026-09-02-caliper-subjects.json`, evaluate item 2 and rough item 2.
- The same limit was flagged for one-click Size readouts in `queue/audits/2026-08-23-size-readout-placement.json`, rough item 2.

## The three gaps the pictures use

1. **Field to buttons.** The 17 px space between the last settings row and the buttons, measured above the right end of Save Changes. The number goes to the right of Save Changes, a hop of about 100 px.
2. **Above Save Changes.** The same space, measured above the middle of Save Changes. Today the number goes right of the button, about 190 px away. A shorter leash sends it left instead, where it lands on the top corner of Reset.
3. **Under a row label.** An 8 px space between a text field and the divider under it, measured mid-row. Today the number travels about 250 px to the right edge of the picture. A shorter leash puts it above the gap, between two text fields, with the connector running up through one of them.

## What each option looks like

### Keep the long leash (today)

![Field to buttons: the number right of Save Changes on a 100 px connector](2026-09-02-readout-travel-field-today.png)

![Under a row label: the number at the right edge of the picture on a 250 px connector](2026-09-02-readout-travel-under-label-today.png)

![Above Save Changes: the number right of the button on a 190 px connector](2026-09-02-readout-travel-above-save-today.png)

Every number lands on empty space and the connector says which caliper it belongs to. The cost is the distance: under the row label the eye has to travel the whole width of the field to find the number, and a vertical caliper's leash is over twice a horizontal one's.

### One leash both ways, about 130 px

![Under a row label: the number between two fields, connector through the upper one](2026-09-02-readout-travel-under-label-shorter.png)

![Above Save Changes: the number on the top corner of Reset](2026-09-02-readout-travel-above-save-shorter.png)

The number stays close, and horizontal and vertical calipers get the same leash. When nothing within 130 px is clear, the number takes the nearest spot along the caliper's own line, and on this capture those spots are worse than the far ones: between two text fields with a connector through one, or on the corner of the Reset button. The field-to-buttons picture is unchanged because 100 px is inside the leash.

### The leash grows with the caliper

A tiny gap keeps its number within about one pill of itself; a long span may send its number up to three pill lengths. Every gap on the audit capture is small, so this looks exactly like the 130 px leash in the pictures above. The difference shows on a long caliper, say a 300 px column, which keeps today's freedom. Two calipers close together can behave differently, which makes the rule harder to predict.

## Why the recommendation is to keep the long leash

A far number on clean whitespace, with a connector, is easier to read than a near number on a button corner or wedged between two fields. Both shorter leashes buy closeness with those worse spots, and neither changes the 100 px field-to-buttons hop the audit actually asked about. If the 250 px hop under a row label bothers you in practice, the 130 px leash is the next best, and the fix for its bad fallback spots is the separate decision about boxed-in calipers.

## Rejected without a card

An unlimited leash was tried too. On this capture it sends the number between the two settings cards 1200 px across the picture to the far margin. No one would read that as the same measurement.

## Worth knowing

The pictures come from the real render pipeline on the audit capture, with the planner replayed under each rule. The sweep of every gap on the capture (931 of them) found 31 where the rules disagree; all are the vertical gaps described above or the small horizontal gaps at the left page margin, where the shorter leashes move the number from below the gap to above it with no change in legibility.
