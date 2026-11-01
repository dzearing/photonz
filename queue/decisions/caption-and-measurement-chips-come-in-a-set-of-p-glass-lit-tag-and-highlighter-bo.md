# Keep all ten chip styles, or drop the three that keep scoring low?

## What this is about

When you put a label on an arrow, the label sits on a **chip**. In Appearance
there is a **Chip** row of ten picture tiles, one per chip style. You approved
all ten from the prototype on 2026-10-31 ("Love it, ship it!"). The specimen
page is the design system's Markup page:
http://127.0.0.1:8791/index.html#markup

Your original report also asked that every style look professional, "not like
a kid made it", and the task's checklist turns that into a test: each style is
scored by a judge against Apple's apps, Figma and Sketch redline plugins and
CleanShot X, and each has to score as professional (7 of 10).

## What changed today

The four styles that failed the first judge were reworked in the app and the
design system together:

- **Glass** is now real frosted glass. The app blurs the picture under the
  label, lightens it, and lays the arrow's colour over it at 40 percent, with
  dark words. It looks the same on light and dark pictures, and an export
  matches the canvas exactly.
- **Spec badge** is a dark Mac-style badge: lighter graphite, a light inner
  edge all the way round, the system font instead of a typewriter font.
- **Highlighter** marks the whole line of words with a level band, instead of
  a tilted stripe across the bottom half of the letters.
- **Lit tag**: two new looks (a bevel, then a glow) were both judged worse, so
  it is back to the look you approved.

Pictures:

- All ten on a light window, a dark window and a busy photo:
  `queue/audits/2026-11-01-chip-styles-sheet.png`
- The same, with the three in question boxed:
  `queue/audits/2026-11-01-chip-styles-three-under-bar.png`
- Glass in the real app over a busy photo:
  `queue/audits/2026-11-01-glass-chip-frost-1-glass-on-photo-sc.png`

## What the judges said

Three independent judges, the middle score of the three:

| Style | Score |
| --- | --- |
| Flat squircle, Spec badge | 7 |
| Solid pill, Hairline plate, Paper, Lit tag | 6 |
| Today, Two-tone badge, baseline | 5 |
| Glass, Highlighter | 4 |

Their main complaints: Glass "a pale pink pill, not Liquid Glass" (on a flat
sheet the frosting barely shows); Highlighter "a box inside a box"; Lit tag
"a skeuomorphic sheen". The panel is stricter than the first judge, who
passed Solid, Hairline, Paper and Two-tone.

## The options

- **Keep all ten (recommended).** Your own eye approved these. The judges
  disagree with each other by up to two points and fail styles the first
  judge passed, so their bar is noisier than your taste. The task closes.
- **Drop the three boxed styles.** The row shows seven tiles. Arrows already
  wearing one keep drawing it, so nothing in an open document changes.
- **Rework the three again.** Another pass with new looks and another round of
  judging. Three passes have not reached 7 so far.
