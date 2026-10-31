# Markup: arrows, chips and measurements

The marks a redliner draws on a picture are **one system**. An arrow and every
measurement (size, distance, gap, alignment) carry the same **chip**, take
**one colour**, and are set from the same **Appearance**. Approved by the user
on 2026-10-31 from the prototype in
`queue/audits/2026-10-31-chip-styles-proto.html`.

| Where | What |
| --- | --- |
| Design system component | `mocks/shared/components/markup.css` + `markup.js` (`window.PZ.markup`) |
| Specimen page | `mocks/pages/markup.html` (Design system ▸ Markup) |
| App | `ChipStyle.swift` (`ChipStyle`, `ChipMarker`, `InkPlate` = `plateFor` and `glassFor`, `ChipLook`), `ChipRasterizer`, `ChipStyleTiles` (Chip and Marker rows); `ArrowStyle`, `HandMadeArrow`, `PillRasterizer` (the pill from before styles), `MeasureRasterizer` (measurements: not styled yet) |

The design system component and the app follow the same rules below. When one
changes, the other changes in the same piece of work, and this page with them.

## 1. The parts of a mark

- **Line**: the arrow's stroke and head, or a measurement's caliper or guide.
- **Chip**: the label plate and its words (an arrow's caption, a measurement's
  readout).
- **Marker**: an optional icon or accent at the start of the chip.

## 2. One colour

A mark has one colour, its **ink**. Picking a colour tints the line, the head
and the chip together, each the way the chip style uses ink. Nobody has to set
a chip's fill, edge and text one by one; those live under Advanced.

## 3. The plate is derived so the words always read

The line keeps the ink exactly as picked. The plate behind the words is derived
from it:

- A mid or dark ink is **darkened just enough** for white words to reach
  **4.8:1** (4.5 plus margin for the lit gradients).
- A light ink, whose darkening would pass **22 percent**, **keeps its colour and
  takes dark words** (`#1d1d1f`).
- Words in the ink on a white plate (Hairline) use the ink darkened to 4.6:1
  against white, so rounding the colour to a whole byte never takes them
  under 4.5:1 (at 4.5 exactly, 3 of the 5,472 sweep colours rounded to 4.48).

Measured with the palette (WCAG contrast, `PZ.markup.plateFor`):

| Ink | Plate | Words | Contrast |
| --- | --- | --- | --- |
| `#ff375f` red | `#d62e50` | white | 4.8:1 |
| `#0a84ff` blue | `#0970d9` | white | 4.8:1 |
| `#bf5af2` purple | `#9f4bc9` | white | 4.9:1 |
| `#ff9f0a` orange | ink | dark | 8.2:1 |
| `#30d158` green | ink | dark | 8.3:1 |
| `#ffd60a` yellow | ink | dark | 11.9:1 |
| `#ffffff` white | ink | dark | 16.8:1 |
| `#1d1d1f` black | ink | white | 16.8:1 |

**Any colour, not just the palette.** The Color row has the palette swatches
plus a custom colour well, and a custom colour gets exactly the same treatment.
Checked over 5,472 colours (every 5 degrees of hue, four saturations, nineteen
lightnesses): the worst words-on-plate contrast is **4.80:1**, and no colour is
darkened past 35 percent. Nobody has to open Advanced to keep a chip legible;
only a part overridden by hand under Advanced can break the rule, and the
inspector warns when it does.

**Glass is judged over the worst picture.** Its plate lets the picture through,
so its tint is derived separately: at 82 percent opacity its words must reach
4.8:1 over a pure white AND a pure black picture. White words take a darkened
tint, dark words a lightened one, whichever moves the colour less (worst over
the same 5,472 colours: 4.80:1). Before this, a light ink on glass over a white
screenshot fell to 1.4:1.

The other mixed styles hold for every colour without their own rule: Today's
dark plate (worst 5.95:1) and the Highlighter swipe (worst 5.6:1).

The app computes all of this in PhotonzCore (pure, tested) and must agree with
this table, and with the sweep, to the hex digit. The sweep's answers are
written by the design system itself (`Scripts/markup-plate-fixture.cjs` into
`docs/design/markup-plate-sweep.tsv`) and `ChipStyleTests` holds the app to
every line of it; regenerate the file in the same commit as any rule change.

**Glass in the app is drawn at 95 to 97 percent, not 82.** The tint and its
words are the rule's above, to the hex digit. But the app blends a layer over
the picture in linear light, where 82 percent lets far more of a white
screenshot through than a browser's blend does (red Glass measured 3.2:1 over
white at 80 percent). 95 percent is the least that keeps all 5,472 colours at
4.5:1 that way, so Glass in the app reads as frosted through its lit rim and
inner highlight more than through what shows behind it.

## 4. Chip styles (ten)

Each style ends at its edge its own way, so they read as different even small.

| # | Id | Name | Plate and edge | Words |
| --- | --- | --- | --- | --- |
| 1 | `today` | Today | Dark plate in the ink, bright 2 pt ink outline, pill | white |
| 2 | `solid` | Solid pill | Lit fill (lighter top), top inner highlight, no edge | on-plate |
| 3 | `squircle` | Flat squircle | Flat plate, continuous corners, no edge, no shadow | on-plate |
| 4 | `hairline` | Hairline plate | White plate, 1 pt ink outline, flat | ink, darkened |
| 5 | `glass` | Glass | Frosted, translucent plate; gradient rim bright top-left and bottom-right | white with a soft shadow |
| 6 | `paper` | Paper | Light card on a layered soft shadow; ink stripe accent | dark |
| 7 | `spec` | Spec badge | Graphite plate with its own top-lit rim and a dark outer line; ink dot accent; monospaced | light |
| 8 | `tag` | Lit tag | Lit fill, small square corners | on-plate |
| 9 | `twotone` | Two-tone badge | Ink tab on the left holding the accent or marker; white body | dark |
| 10 | `highlight` | Highlighter | White plate with an ink highlighter swipe behind the words | dark |

No chip has a beak or pointer: the arrow or caliper already says what the chip
is about.

## 5. Arrow styles (ten)

How the line is **painted**, never part of the drawing: an arrow keeps its two
ends, colour, thickness and head size whichever style it wears.

| # | Id | Name | Look |
| --- | --- | --- | --- |
| 1 | `clean` | Clean | Geometric line, solid head |
| 2 | `handDrawn` | Hand-drawn | Thin pen line, gentle wobble, hooked open head |
| 3 | `marker` | Marker | Bold rounded stroke, loose two-stroke head |
| 4 | `brush` | Brush | Tapers from a point, swells, swept calligraphic head |
| 5 | `sketch` | Sketch | Rough outline arrow drawn twice, broken where the ink ran dry |
| 6 | `dashed` | Dashed | Dashed line, solid head |
| 7 | `block` | Block | Bold filled arrow whose shaft widens into a big head |
| 8 | `neon` | Neon | Glowing line with a bright core, open head |
| 9 | `dotted` | Dotted | Round dots, a dot at the tail, chevron head |
| 10 | `elbow` | Elbow | Right-angle connector with a rounded corner, dot at the tail, solid head |

1 to 5 exist in the app today (`ArrowStyle.swift`, from the user's hand-drawn
references). 6 to 10 are new. Ending (arrow, dot, none) applies only to Clean,
since the others draw their own heads.

## 6. Markers

| Marker | What shows |
| --- | --- |
| Accent (default) | The style's own detail: Paper's stripe, Spec's dot, Two-tone's dot |
| None | Nothing |
| Error | ✕ in a circle, red `#ff3b30` |
| Warning | ! in a triangle, yellow `#ffcc00` |
| Done | ✓ in a circle, green `#34c759` |
| Info | i in a circle, blue `#0a84ff` |

Status colours keep their meaning on any ink. On an **ink-filled** plate
(Today, Solid, Squircle, Glass, Lit tag, Two-tone's tab) the icon sits on a
white disc with its colour in the glyph (orange `#ff9500` for warning). On a
**light or graphite** plate it is the coloured disc with a white glyph (dark on
yellow). Any marker but Accent takes the stripe or dot away.

## 7. Size

S, M and L set the chip's type size (10.5, 12, 14 pt in the specimen) and its
padding, and may scale the line's weight. Thickness and Head Size, set by hand
under Advanced, override Size.

## 8. Appearance

The same controls sit on a picked mark (what this one is) and in the tool's
options (what the next one is), for the Arrow tool and every Measure mode.

```
APPEARANCE
  Arrow    10 tiles            arrows only
  Chip     10 tiles
  Color    one row of swatches
  Marker   None · Accent · ✕ · ! · ✓ · i
  Size     S · M · L
  ▸ Advanced (collapsed)
      Line, Head              from Color
      Chip Fill, Edge, Text   from style
      Thickness, Head Size    override Size
      Ending                  Clean arrows only
```

Under Advanced each part reads "from Color" or "from style" until it is set by
hand, and a part set by hand stays overridden until it is reset.

## 9. Every mark must

- Read over a light screenshot, a dark one and a busy photo (the specimen page
  shows all three for every chip).
- Never cover what it labels: chips sit beside their line, never on a handle.
- Export exactly as drawn: the chip style, marker and size are data on the
  layer, applied at render time.
- Use no em dashes in any words it shows.
