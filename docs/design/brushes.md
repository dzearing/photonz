# Brushes and painting

The Brush tool lets a person (and the agent) paint, not only build vector
shapes. Asked for by the user on 2026-10-24: a realistic set of media
(charcoal, chalk, oil paint, watercolour, marker, crayon, airbrush), each with
the settings that medium needs, reachable from MCP. Epic `image-paint`; the
umbrella task is `a-brush-tool-paints-with-realistic-charcoal-chal`, and the
slices below are its dependencies in the queue.

The floor is the mocks: `image.html` and `img-retouch-wt.html` put
**Brush (B)** on the tool bar, and the retouch walkthrough shows a brush's
settings as panel rows (Size, Hardness, Flow, a mode dropdown) with every
stroke landing on its own layer so the picture underneath is never written to.
`PRODUCT-MODEL.md` §"Vector strokes are brushes" says a path's line can be
painted with a brush and stay editable.

## Decisions

### 1. A stroke is data, not pixels

A painted layer is a new layer kind, `LayerContent.paint(PaintContent)`, holding
an ordered list of `BrushStroke`s. A stroke is:

- its samples, in the layer's own top-left points: position, pressure (nil for
  a mouse), tilt (nil when the device has none), and milliseconds since the
  stroke began;
- the brush it was painted with: the medium plus that medium's setting values
  (`BrushSettings`), copied into the stroke, so changing the armed brush later
  never repaints old strokes;
- its colour (hex, the foreground colour at the time);
- a seed, so every random choice the engine makes (jitter, bristles, spray) is
  the same on every render.

Why: the architecture invariant (pixels never live in the document model), and
three things that fall out of it for free. Undo stays a snapshot of a small
value. The agent's stroke and a person's stroke are the same value and render
through the same code, so they are identical by construction. And a vector
path's brushed line is just samples taken along the path fed to the same
engine.

The cost is replay: the renderer must paint every stroke of a layer in order.
That is handled by caching (decision 5), and a layer with thousands of strokes
can later be flattened to a picture by an explicit command, never silently.

### 2. Where a stroke lands

Never into a picture's pixels. With a paint layer picked, the stroke is added
to it. Otherwise the first stroke makes a new paint layer, named **Paint**,
sized to the frame (or canvas) the stroke starts on, placed just above the
picked layer (or on top when nothing is picked), and picks it, so the strokes
that follow go to the same layer. This is the retouch mock's "every stroke
lands on the layer named in the Layers group".

A Photoshop user expects the brush to paint "on the current layer". Painting on
a screenshot here lands on a Paint layer just above it, which looks the same,
and keeps the screenshot intact. That is the one departure, and it is the
house's non-destructive rule.

Each stroke is one `History.perform`, so one Command Z takes one stroke off.

### 3. The brush stays in hand

Every other tool that makes something hands back Select when it lands
(`ArrowCaptionEntry.toolAfterLanding`). The Brush does not: painting is dozens
of strokes in a row, and every paint app keeps the brush. V or Escape puts it
down.

### 4. One engine, eight media

The engine is in two halves.

**Placement, in PhotonzCore (pure, tested).** From the samples and the
settings it works out the dabs: where each one goes along the stroke (spacing
as a fraction of the tip size), how big, how opaque, at what angle, with what
jitter, after the dynamics (decision 6) have had their say. Deterministic from
the seed.

**Marking, in PhotonzRender.** Each medium turns dabs into paint its own way.
A round dab with a texture on it is explicitly NOT good enough (the umbrella's
blind test fails it):

| Medium | What makes it read as itself | Its own settings (besides Size, Opacity) |
| --- | --- | --- |
| Pencil | graphite on the same paper: a thin line, wider and darker the softer the lead (grades 4H to 8B), the tooth showing more the lighter it is pressed; leaned, the side of the lead lays a broad grainy band; never black, piled passes go to a cool silver | Hardness (grade), Grain, Tilt Shading |
| Charcoal | dab mask multiplied by a paper grain fixed to the canvas, so strokes catch the same tooth; soft dusty edge; smudge drags the deposit | Grain, Smudge |
| Chalk | as charcoal, coarser grain, brighter and more opaque, broken edge | Grain, Smudge |
| Crayon | waxy: hard edge, grain catches only the high tooth, builds little on a second pass | Grain, Pressure (wax) |
| Marker | flat within a stroke (max coverage, not sum), translucent, darkens where separate strokes cross (multiply); chisel or round tip with an angle | Tip, Flow |
| Airbrush | gaussian spray of fine particles whose flow accumulates while the pointer dwells | Flow, Softness |
| Oil | carries colour: picks up what is under the brush and smears it along; bristle streaks in a height map, lit so ridges show | Load, Smear |
| Watercolour | transparent glaze; pigment pools darker at the wet edge; wet-on-wet blooms; granulates into the grain; overlapping strokes layer | Wetness, Bleed |

Watercolour follows the published simulation (Curtis et al., "Computer-Generated
Watercolor", SIGGRAPH 1997: a wet-area mask, pigment moved by a shallow-water
flow, edge darkening, backruns), simplified to what runs at interactive rate;
Rebelle and Fresco's live watercolour are the behaviour to match. Oil follows
the bristle-and-pickup approach of Baxter et al. ("IMPaSTo", 2004) in spirit:
colour picked up from the canvas, a height channel lit at render. Both are
expected to need Core Image or Metal kernels; the dry media and marker and
airbrush do not.

### 5. Staying smooth on a 12 megapixel picture

- **The live stroke paints itself.** While the pointer moves, the canvas draws
  the stroke in progress on its own overlay, adding only the new dabs to a
  bitmap the size of the stroke's bounds, with the same marking code. The
  document is not re-composited per mouse move.
- **A paint layer keeps its last raster.** The renderer remembers, per layer,
  the raster of strokes 0..n-1. When stroke n arrives (and the first n are
  unchanged), it paints only stroke n onto a copy. Undo hits the cache of the
  shorter list.
- Budget: input to pixel under one frame (16 ms) and commit under 50 ms on a
  12 MP canvas with a few hundred strokes, measured, written in the audit.

### 6. Pressure, tilt, speed, and the mouse

Samples carry the tablet's pressure and tilt (`NSEvent.pressure`,
`.tilt`; Apple Pencil through Sidecar arrives the same way). Each medium maps
them where the real medium would: pressure to size and opacity for charcoal,
to flow for airbrush, to load for oil; tilt broadens a charcoal or marker side;
speed thins a fast stroke. A mouse has no pressure, so the engine simulates a
taper: the stroke swells in over its first few points and thins out over its
last ones, and fast movement thins it.

### 7. Settings

Each medium declares its settings as a list (id, plain name, range, default),
so the panel, the tool options, MCP and the tests all read one list. The values
the brush is armed with are a preference per medium (like the other tools'
remembered colours), not part of the document.

Placement follows the placement contract: the medium (seven options, so a
dropdown) and its settings show in the **tool options capsule** over the tool
bar while the brush is in hand, and, with the panel open, in a Brush section of
the panel (the two doors the user allowed, UX-PATTERNS placement contract). The
capsule carries Medium, Size, Opacity and the medium's two own settings; the
panel carries the whole list.

Keys, by Photoshop: **B** picks the brush on a picture. On a document with time, B is already the Blade (`TimelineKeys.swift`, Edit ▸ Tools), and the video workspace's tools (PRODUCT-MODEL.md) carry no Brush, so the Brush is not on the bar there and B stays the Blade (UX-PATTERNS §7: Photoshop's key wins on a picture). **[** and **]** shrink and grow it,
**Shift**-click paints a straight line from the last stroke's end, **Option**
held samples a colour from the canvas. E (eraser), S and J stay free for the
eraser, stamp and heal.

Smudge: Photoshop and Procreate make smudge its own tool. Here it is a mode of
the brush (a Paint / Smudge choice in the options), using the picked medium's
tip, so "switch to charcoal and smudge" is one step. Charcoal and chalk also
smudge a little on their own by their Smudge setting.

### 8. The agent

MCP and the agent API get: list the brushes and their settings, pick and set
the armed brush, and paint a stroke from a list of points with optional
pressure. A stroke from MCP goes through the same editor call as one from the
pointer, so it is the same value, the same render and one undo step. Ask can
use these to paint; nothing it paints comes from stored subjects (the house
rule): the model plans strokes, the engine makes them look like paint.

### 9. Brushed vector strokes

`PathContent` gains an optional brush. With one, the path's line is drawn by
sampling the curve into stroke samples (pressure from a taper, or later from a
per-anchor width) and feeding the same engine. The path stays editable: move
an anchor and the line re-paints.

## What slice 1 settled (2026-10-24)

- The Brush keeps the layer pick when you pick it up (`Tool.preservesLayerSelection`),
  because the picked layer is where the strokes go: that is what lets decision 2
  put a new Paint layer "just above the picked layer". Its handles hide while
  the brush is in hand, as they do for every non-Select tool.
- The armed brush lives in `AnnotationStyles` beside the Pen's ink: its own
  colour (black out of the box, Photoshop's foreground) and a `BrushSettings`
  starting on Charcoal. The Width behind the tool bar swatch is the brush's Size
  until the settings slice gives it its own controls.
- Placement walks a Catmull-Rom curve through the samples, one sample behind
  the pointer, and lays a last dab on the very end; `BrushPlacement.Walker` is
  shared by the live overlay and the renderer, so live and landed agree by
  construction (the walk measured 0.06% of the canvas different between the
  held and the landed picture).
- The live overlay is a view-sized bitmap over the composite, cut to the box
  the stroke will land in, shown at the stroke's opacity. It stays up until the
  composite holding the stroke arrives.

## What slice 2 settled (2026-10-24)

- **The paper is the layer's, in points.** `PaperGrain` (PhotonzRender) is one
  procedural tile, 128 points square, repeated: a cellular dimple pattern (pits
  with a network of ridges between them, the way pressed drawing paper is made)
  plus a little value noise and a faint fibre, evened out so a threshold of `t`
  leaves exactly `t` of the paper bare. It is read in the paint layer's own
  points, not the canvas's: moving a painted layer carries its paper with it,
  and every stroke on one layer catches the same tooth. Chose that over
  absolute canvas coordinates because a moved layer should keep its look.
- **Dry media work on pixels, not a stamped tip.** `DryStroke` lays each dab
  into a coverage field: a tip whose edge the paper breaks, streaked across its
  width by the stick's uneven face (so the marks run along the drag), pressed
  lighter and darker along its length, settling only on paper above a height
  the press reaches. Grain 0 paints the whole tip; the streaks scale with Grain
  too, since they are the stick's texture.
- **What tells the three apart** (settled by a blind test, 2026-10-24: model
  judges beside reference photos, order shuffled every round). Charcoal
  SHADES: a dense, velvety dark core that fades out softly over the outer half
  of its radius, the tooth caught to the same depth right across the tip and
  the fall-off shaded over it (a smoky edge, not a ring of specks), long faint
  streaks, fine dust beside it. Chalk is POWDER: a lighter film than
  charcoal's carbon (chalk is mostly white binder; every judge read the darker
  of the two as charcoal), there or bare, never half-tone, a fine grit of its
  own worked into the tooth so it lands as many small crisp flecks, dry streaks
  that break along the drag, a ragged edge that sheds crisp crumbs. Crayon is
  WAX: a hard edge that wavers with the hand, colour only on the high tooth,
  skips smeared along the drag, a worn flat tip with short squared ends. For
  chalk and crayon Grain says how far into the paper they reach; for charcoal
  it says how much of the pits stay shaded. Tests: `halfToneShare`,
  `streakAgreement`, `widthWaver` in `PaintMeasures`.
- **A smudge keeps the paper's tooth**: what the finger presses down sits more
  on the tooth than in the pits (`PaintMeasures.unevenness` in the smear).
- **Smudge is a mode in the capsule, and it only adds.** The tool options capsule
  carries Medium (a dropdown, all seven) and Mode (Paint | Smudge, a segmented
  control). A smudge stroke is stored on the paint layer it drags
  (`PhotonzDocument.smudgeStroke`): the picked paint layer, or the topmost shown,
  unlocked paint layer under the pointer, and never a picture or a new layer,
  so a smudge on bare screenshot does nothing and adds no undo step. The finger
  carries a blurred patch of what it passed over and spreads it thinner into
  lighter places, more on the paper's tooth than in its pits; it never scrapes
  paint off. That is what lets the live overlay
  be honest: what it lays over the paint, laid over an empty overlay, shows the
  same thing as the landed stroke. Real smudging also lifts; that is a known
  departure, written here, not a bug.
- **Charcoal and chalk's Smudge setting** is the same finger pulling the
  stroke's own deposit along into the valleys as it goes.
- **Measured bar.** `PaintMeasures.interiorGapFraction`: the share of a straight
  stroke's core (within a third of its radius of the line) left under half its
  strongest coverage. The soft round tip scores 0; the bar is 0.12; charcoal,
  chalk and crayon at their defaults score about 0.14, 0.38 and 0.25 on the
  stroke sheet.
- **Live and landed share `LiveMarker`.** The canvas hands it the view's pixels
  as a transform from the landing layer's points, so the live stroke walks the
  same layer-local samples the renderer does.

## What the pencil settled (2026-10-24)

- **Pencil is a fourth dry medium**, not an engine of its own: a `DryLook`
  parameter set (thin crisp tip, fine striations, no dust, no smear) on the same
  paper. First in the Medium list, the sketching media leading. Size 3.
- **Every dab carries a press and a lean.** `BrushDab.pressure` (0...1) and
  `.tilt` come from the pen's samples, eased between them; a sample with no
  pressure (a mouse) gets `BrushDynamics.mousePressure`: a light touch-down
  settling to a steady middle press over its first few points, lighter moving
  fast. No taper out: the live stroke cannot know where it ends. Only the
  Pencil reads them so far; the dynamics slice gives the other media theirs.
- **Hardness is a choice of grades** (4H, 2H, HB, 2B, 4B, 6B, 8B, default HB):
  a softer lead is wider, darker and reaches deeper into the paper. Pressure
  widens the line a little and darkens it a lot, and a lighter press leaves
  more of the tooth bare and the film thinner.
- **Tilt Shading** says how far a lean lays the side of the lead down: the tip
  becomes a patch long the way the pen leans (up to seven times the radius),
  paler and catching only the high tooth. A stroke's box reaches that far
  (`BrushMedium.reach`).
- **No mouse modifier for tilt.** Shift (straight line), Option (colour pick),
  Command and Control-Option are all Photoshop's on a brush drag (UX-PATTERNS
  §7), so a mouse paints upright; walks hold a pen with the `pen` step.
- **Sheen**: graphite is never black. The colour is lifted toward a cool silver
  by how dark it is, a little more where the deposit is densest, so passes
  piled up converge on a silvery grey rather than black. Per stroke, so the
  live stroke shows exactly what lands.
- **Bars** (`PaintMeasures.lineProfile`, `PencilRenderingTests`): 8B at least
  1.4 times the width and 1.8 times the darkness of 2H; at pressure 0.2 at least
  0.3 of the core left to the tooth. The round tip fails all three.

## Slices (queue tasks, in order)

1. Foundation: the tool on B, paint layers, strokes as data, placement engine,
   a first round tip, live overlay, one undo step per stroke.
2. Dry media: charcoal, chalk, crayon on a paper grain, with smudge.
3. Marker and airbrush.
4. Watercolour.
5. Oil paint.
6. Settings in the tool options and the panel; [ and ]; medium dropdown.
7. Pressure, tilt and speed; the mouse taper.
8. MCP and the agent API; Ask paints.
9. Brushed vector strokes.
10. Painting speed on a 12 MP picture, measured.

The umbrella closes the epic: the blind test sheet (one unlabelled stroke per
medium, judged by the runner and a model, beside reference photos), the try
path, the reel, and the final audit.
