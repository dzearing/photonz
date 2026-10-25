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
| Airbrush | gaussian spray of fine particles whose flow accumulates while the pointer dwells | Flow, Spread, Droplet Size, Build-up |
| Oil | carries colour: picks up what is under the brush and smears it along; bristle streaks in a height map, lit so ridges show | Load, Smear |
| Watercolour | transparent glaze; pigment pools darker at the wet edge; wet-on-wet blooms; granulates into the grain; overlapping strokes layer | Wetness, Bleed, Granulation |

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
  shorter list. Built 2026-10-25 as `PaintRasterCache` (PhotonzRender): keyed
  by bitmap size and scale, it keeps the bitmap and the washes still wet after
  the last stroke, so the result is byte for byte a full replay; 128 MB, least
  recently used let go first, emptied under memory pressure. Two requests for
  the same layer at once wait on each other rather than both simulating it.
- **A press reads the paint it needs ready-drawn.** A smudge, a wash and oil
  read the layer under them. The canvas reads it at the scale the renderer
  bakes the layer at (`DocumentRenderer.bakeScale`), so it is the raster the
  last render kept, and with the Brush in hand it draws that into the view's
  pixels in the background as soon as a stroke lands (`warmBrushPaint`).
  Before this a smudge press re-simulated every stroke on the main thread:
  420 ms with ten strokes on a 12 megapixel canvas; after, 0.1 ms
  (`smudge-after-paint-keeps-up-walk`).
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

## What the marker and airbrush settled (2026-10-25)

- **A marker keeps the most, never the sum.** `MarkerStroke` (PhotonzRender,
  `MarkerAirbrush.swift`) lays each dab's nib into a coverage field by max, so
  a stroke that doubles back on itself is one even colour edge to edge. The
  edge is crisp with a hair of give (a pixel, or 0.4 pt at high zoom), never a
  soft brush.
- **Flow is the ink's strength**: 0.2 to 0.95 of the light taken at full
  coverage, never fully opaque, times Opacity. A marker ignores pressure and
  speed for now (decision 6 gives tilt a side; that is the dynamics slice).
- **It lands multiplied over the paint before it** on the same layer: the
  stroke is laid as `a·C·(1 − Da + D)` source-over, which is exactly multiply.
  The same formula makes the live overlay honest: the canvas hands the live
  marker the picked paint layer as it stands (the `working` copy the smudge
  already used), the overlay holds what the stroke lays over that paint, and
  it is shown at full strength (`LiveMarker.showsAtFullStrength`). Laid over
  the canvas it is the landed picture (the walk: 0.05% apart on a crossing).
  Over the picture under the paint layer the marker is a normal layer; the
  layer's own blend mode is the place to multiply it over a screenshot.
- **The chisel nib** is a rounded box the stroke's Size wide and 0.3 of it
  thick, held at a fixed 45 degrees (long edge lower left to upper right, a
  right hand's hold): along that edge the stroke is a thin line, across it the
  full width. Tilt turning the nib waits for the dynamics slice.
- **The airbrush sprays by time.** `BrushPlacement.Walker` lays an airbrush
  dab every `dwellInterval` (40 ms at the default Build-up, see below) the pointer stays within a dab's spacing of
  where it settled, as well as its spaced dabs along the way, so a held spot
  builds up and a slow pass is darker than a fast one. The pointer sends no
  events while still, so the canvas's `brushDwellTimer` hands the stroke a
  sample where the pointer is after 25 ms without one; those samples are
  stored, so the landed stroke builds exactly what was seen.
- **A dab is a cloud plus droplets.** Superseded the same day by the
  airbrush's own slice: see "What the airbrush settled" below.
- **Bars** (`MarkerAirbrushRenderingTests`, `PaintMeasures`): `flatShare` of a
  marker stroke that doubles back at least 0.9 (marker 0.99, the round tip
  0.82); `meanAlpha` held a second over a pass at least 1.6 times (airbrush
  3.3, the round tip 1.0); `fringeGrain` of the spray at least three times the
  round tip's (0.040 against 0.005). The round tip is now the oil paint's,
  until its slice.

## What the airbrush settled (2026-10-25)

- **Four settings, one list.** Flow (how hard it sprays, 40), Spread (how wide
  the mist reaches from the line, 55), Droplet Size (fine mist to coarse
  spatter, 25) and Build-up (how fast a held spray piles up, 50), all in
  `BrushMedium.settings`. Softness became Spread: `BrushMedium.settingID` maps
  the old id, so a stroke saved with `softness` opens with that value as its
  Spread and a caller still saying softness sets Spread.
- **A dab is a bell of mist plus droplets.** `AirbrushStroke`
  (`MarkerAirbrush.swift`): a gaussian whose width is 0.15 to 0.36 of the
  radius by Spread, fading to nothing by the rim, so even a spot held until it
  saturates has no edge. Droplets from the stroke's seed: most ride the mist a
  little wider than it, three in ten are overspray anywhere over the cone (the
  halo along a real airbrush line). Droplet Size trades many specks of 0.1 pt
  for fewer of up to 1.4 pt, and moves paint from the mist into the drops.
- **Spatter at a heavy flow.** When Flow times the press passes a half, each
  dab throws a few big drops out past the mist that land thick, more with a
  bigger Droplet Size.
- **Pressure and speed.** The press sets the paint (0.2 to 1 of it, a pen's own
  reading or a mouse's simulated one). Each moving dab carries `BrushDab.spray`,
  the share of its paint it lays, from the pointer's eased speed
  (`BrushPlacement.spray(speed:)`: all of it slow, about half at 2 pt/ms,
  never under a quarter), so a fast pass is light. Held dabs spray all of it.
- **Build-up sets the dwell rate.** `BrushPlacement.dwellInterval(buildUp:)`:
  40 ms at 50, 20 ms at 100, none at 0 (a held spot then gets only what the
  pass laid).
- **Bars** (`AirbrushRenderingTests`, numbers in
  `queue/audits/2026-10-25-airbrush-measures.txt`): `featherShare` at least
  0.6 (airbrush 0.82, round tip 0.21); `edgeDroplets` at least 0.1 a square
  point (0.17, round tip 0); held a second over none at least 1.6 times (3.3,
  round tip 1.0, rising at every step of 0, 250, 500, 1000, 2000 ms); a slow
  pass over a fast one at least 1.4 times (2.0, round tip 1.0).

## What watercolour settled (2026-10-25)

- **No fluid is simulated; what Curtis's simulation produces is built from
  fields a dab can update alone** (`Watercolour.swift`, PhotonzRender). Each
  pixel keeps how deep it is inside the WET AREA (the most any dab gave it, so a
  stroke is one wash however often it doubles back) and inside the brush's own
  path. The wet area is the path crept out by Bleed along lobes and fingers of
  noise fixed to the layer and the stroke's seed. Pigment is a thin, mottled
  wash, a little thinner where the water carried it, POOLED darker in a band
  just inside the wet area's edge, settled into the paper's pits by
  Granulation (the same `PaperGrain` as the dry media, read twice as broad),
  and, at low Wetness, caught only on the tooth (a dry brush). Per-pixel noise
  is worked out once, the first time a dab comes near, and kept.
- **Wetness** is how wet the brush is: how long the stroke stays wet, how far
  Bleed can carry it, how hard the edge pools, and below about 40 a dry brush
  that skips. **Bleed** is how far it creeps past the brush; above 40 its front
  feathers instead of pooling. **Granulation** was added because some pigments
  settle into the paper and some do not, and a watercolourist picks for it.
  Edge darkening is not its own knob: a dry brush has no pooled edge and a wet
  wash does, so Wetness carries it.
- **A stroke records when it began** (`BrushStroke.startedAt`, seconds; the
  canvas stamps it at mouse-down). A watercolour stroke stays wet for
  `WatercolourDrying.seconds(wetness:)` after it ends (1.5 s dry to 8 s soaked,
  5.4 s at the default) and `wetness(when:)` says how wet it still is when a
  later stroke begins. Strokes saved before there was a time have none and
  read as long dry, so nothing painted earlier changes. Stored, so a replay
  blooms where the first render did.
- **Wet into wet**: where a stroke's dabs fall on a wash still wet, its water
  floods on through that wash, as far as three and a half radii, never onto
  dry paper. Into a soaking wash the front feathers (soft mixing); into one
  that has begun to dry it is crisp and pools hard and dark (a backrun). It
  works within one paint layer. The renderer keeps the washes still wet as it
  replays a layer (`WetWashes`); the live overlay rebuilds the same ones from
  the layer's strokes at mouse-down (`WetWashes.under(_:earlier:...)`, only the
  strokes that can still matter), so the bloom under the pointer is the bloom
  that lands.
- **Known departure**: a real bloom also LIFTS pigment out of the earlier
  wash's middle. Paint here is only laid, never lifted (as with the smudge), so
  the live overlay can be honest; the bloom is new paint spreading through the
  wet wash with a pale inside and a dark ragged front.
- **It lands multiplied** over the paint before it on the layer, exactly as the
  marker does (the same adjusted source-over), so dry strokes crossing deepen
  into a glaze and the live overlay, handed the layer's paint, matches.
- **Bars** (`WatercolourRenderingTests`, `PaintMeasures`): `edgeToCentre` (the
  darkest of the outer third of the covered width over the mean of its middle
  third, median over half-radius stretches) at least 1.3: watercolour 1.41, the
  round tip 1.00. `spreadPastPath` (how far a twentieth of the strongest
  coverage reaches past the radius, as a share of it) at least 0.15:
  watercolour 0.25, round tip -0.03. Bleed 0 to 100 moves the spread 0.03 to
  0.45. A box of 4.5 times half the Size holds a stroke (`BrushMedium.reach`).

## What oil paint settled (2026-10-25)

- **A row of bristles, each with its own reservoir** (`OilPaint.swift`,
  PhotonzRender). About one bristle a point across the brush, of uneven widths,
  clumped in their lift and press, the outermost two carrying less. Each holds
  a colour and how much paint it has left.
- **A flat brush, swept.** The footprint is square to the way the brush goes:
  the full Size across, 0.6 of half the Size either side along it, pressing
  hardest in its middle (a smooth bell, so however the dabs fall no seams cross
  the stroke). The heading is eased (0.15 of each new step) so a wobbling hand
  bends the streaks rather than scalloping them. The first dab waits until the
  brush has moved, so the stroke starts square; a click lays it four times
  (`LiveMarker.finish()`, called on mouse-up).
- **Load** is how far a full brush paints before it runs dry: `3 + 0.25·Load`
  brush widths (about 15 widths of full cover at the default 70, measured),
  each bristle lasting 0.55 to 1.45 of that, so the end of a long stroke
  breaks into a dry brush's streaks. A fuller brush also lays the paint
  thicker.
- **Smear** is pickup. Under each dab each bristle averages the layer's paint
  it passed over and moves its colour toward it by `0.3·Smear·coverage`, and
  is reloaded a little by it; where it lands on paint the two also mix in place
  (`0.4·Smear·coverage`). What it picked up wears off toward its own colour
  over `0.6 + 3.4·Smear` brush widths. Pickup reads only the paint layer the
  stroke lands on, as it stood before the stroke (a new layer has none), never
  the picture below: the house's non-destructive rule, and what lets the live
  overlay (handed the same layer as `working`) match.
- **Height, lit at landing.** Each pixel keeps a height in points: eased
  between neighbouring bristles' lifts with a shallow groove where each ran,
  and a low rim where the paint was pushed to the sides. It is lit from the
  upper left (diffuse plus a small gloss) when the stroke is laid down, so the
  light is baked into the stroke's pixels; a later stroke covers it like paint.
  Only laid, never scraped off, so live and landed agree (the walk: 0.14% and
  0.42% of the canvas apart).
- **Bars** (`OilRenderingTests`, `queue/audits/2026-10-25-oil-paint-measures.txt`):
  `ridgeContrast` (the spread of lightness across a stroke's core, averaged
  along it) at least 0.025: oil 0.041, the plain round 0.001. `carriedShare`
  of a red stroke's colour in a blue one over the two brush widths after it
  leaves the red, at least 0.1: oil 0.33 at the default, 0.015 at Smear 0,
  0.65 at 100; the plain round 0.001.
- **Known limit, not oil's own:** the renderer bakes a paint layer at most 16
  MP, and a paint layer is the whole canvas, so on a 12 MP canvas a landed
  stroke is about 1.15 pixels a point. Zoomed in past about 140% the bristles
  the live stroke drew go soft when the button comes up (the walk measured 1.3%
  of the canvas changing at 172%). Folded into the painting-speed slice.

## What the settings slice settled (2026-10-25)

- **The tool options carry six things** (`ToolSettingsBar`, brush): the brush
  (its tile chooser, not a dropdown: the user, 2026-10-24), Mode, Size,
  Opacity, and the brush's first two own settings
  (`BrushMedium.toolOptionSettings`): a pencil's Hardness and Grain, an
  airbrush's Flow and Spread, a watercolour's Wetness and Bleed. The panel's
  Brush section carries every setting (`BrushMedium.settings`), Name and Group
  above them and the mock's one line below. Both read and write the same armed
  brush, so moving either moves both.
- **A setting's control comes from its spec** (`BrushSettingSpec.control`): a
  number is a slider (a short track and its reading in the tool options, a
  track and a typed number box in the panel); two or three choices are a
  segmented control (the marker's Round | Chisel); more are the panel's
  dropdown (the pencil's grades). `BrushSettingSpec.reading` says each one the
  same way everywhere: "16 pt", "60%", "HB".
- **Each brush remembers its own.** `AnnotationStyles` keeps the armed brush
  and, beside it, what every other medium was last left at
  (`armBrush`, `brush(for:)`, saved under `brushes`). One never used starts at
  its own defaults, its own Size among them, so an airbrush picked after a thin
  marker sprays at 40 pt. Mode (Paint or Smudge) follows the brush across
  media. The tiles paint each brush as picking it would give you.
- **[ and ]** step Size in Photoshop's steps (`BrushSize.stepped`: by 1 under
  10, 5 to 50, 10 to 100, 25 to 200, 50 to 300, then 100, held to 1...500),
  from the tool options (the window's own shortcut, the way the tool bar's
  letters work) and Edit > Tools (Decrease Brush Size, Increase Brush Size).
  The ring under the pointer redraws at the new size at once.
- **Walk names**: the tool options' rows are "Tool <name>", the panel's
  "Brush <name>", apart from a picked layer's own Opacity and Size rows.
- **Every own setting visibly changes the stroke**, measured
  (`BrushSettingsVisibleTests`, `PaintMeasures.changedShare`): the same stroke
  at a setting's two ends, the share of it that differs, read per pixel and per
  four-point block, at least 0.2. A setting that acts only in its own situation
  is painted in it: Tilt Shading with a leaning pen, Smear across paint already
  there, Build-up held still. Charcoal's Smudge read 0.08 and was strengthened
  at its top end (`0.25·s² + 0.65·s⁴`, defaults within a tenth of before); it
  reads 0.47. Numbers: `queue/audits/2026-10-25-brush-settings-measures.txt`.

## What the dynamics settled (2026-10-25)

- **One response per medium, in PhotonzCore** (`BrushDynamics.response(for:)`):
  what a press does to the width and the weight, how much a fast pen thins
  the line, how deep a mouse stroke's taper goes, and what a lean lays down.
  Placement applies it, so every dab's `diameter` already carries the press
  and the new `BrushDab.weight` carries how heavily it marks; the renderers
  only read them. Charcoal: width 0.4 and weight 0.3 at no press (shares of a
  full press). Chalk 0.5 and 0.4, crayon 0.75 and 0.3 (wax reaches deeper
  into the paper as it is pressed), watercolour width 0.3 (a round brush's
  belly), oil 0.7 (its press is still its load), marker 0.8 and never darker.
  The airbrush's press stays its flow and the pencil's stays its own grades.
- **Size is the steady press.** Every response is 1 at the mouse's steady
  press (`BrushDynamics.steadyPress`, 0.64), so a mouse paints exactly what
  the ring under the pointer shows and the earlier slices' bars still hold. A
  hard press goes past the Size (charcoal about 1.28 times); `BrushMedium.reach`
  covers it and a full lean. Photoshop puts Size at a full press; chose this
  because a mouse never presses hard.
- **Speed.** A mouse's simulated press already lightens moving fast. A pen's
  press is left as the pen read it, and each dab is narrowed by the pen's
  eased speed instead (`penThinning`, up to 0.3 by 4 pt/ms).
- **The mouse taper.** A stroke whose first sample has no pressure swells in
  from `1 - taperDepth` of its width over `taperLength` (twice the Size, 10 to
  60 points) as it is drawn, and once the pointer lifts its last stretch thins
  the same way (`BrushPlacement.taperedOut`, applied by `dabs(for:)`). The
  live stroke cannot know where it ends, so the tail draws in as the stroke
  lands, the way a finger's taper does in other paint apps: chose that over
  replaying the whole stroke on the main thread at release (a hitch on a long
  stroke) and over holding the tail back while drawing (the line would trail
  the pointer by two tip widths). The walk measured 0.13% of the canvas
  changing between held and landed. A click is a light touch, as before. The
  airbrush does not taper (its spray already feathers) and a smudge is a
  finger: no press, no taper.
- **Tilt.** `BrushDynamics.lean(_:)` is the one reading (none under 0.12, all
  of it by 0.8). Charcoal and chalk lay the side of the stick, the pencil's
  patch generalised: 2.6 and 2.7 times longer along the lean, paler, a softer
  edge for charcoal. A chisel marker's long edge turns square to the lean
  (from its fixed 45 degrees upright); a round one broadens 1.6 times along it.
- **Bars** (`BrushDynamicsRenderingTests`, numbers in
  `queue/audits/2026-10-25-pen-pressure-measures.txt`): heavy over light at
  least 1.4 times the width and 1.6 times the paint for charcoal and chalk,
  crayon's paint 1.5 times, the airbrush's 1.8, watercolour and oil 1.15
  times the width; leaned charcoal 1.6 times as wide (chalk 1.3); a chisel
  leaned across 2.5 times as wide as along; a fast pen or mouse at most 0.88
  of a slow one; a mouse stroke within 5 points of either end under 0.7 of its
  middle width. Before this slice every medium but the pencil failed them all.

## Slices (queue tasks, in order)

1. Foundation: the tool on B, paint layers, strokes as data, placement engine,
   a first round tip, live overlay, one undo step per stroke.
2. Dry media: charcoal, chalk, crayon on a paper grain, with smudge.
3. Marker and airbrush.
4. Watercolour.
5. Oil paint.
6. Settings in the tool options and the panel; [ and ]; per-medium memory (the medium is picked from tiles).
7. Pressure, tilt and speed; the mouse taper.
8. MCP and the agent API; Ask paints.
9. Brushed vector strokes.
10. Painting speed on a 12 MP picture, measured.

The umbrella closes the epic: the blind test sheet (one unlabelled stroke per
medium, judged by the runner and a model, beside reference photos), the try
path, the reel, and the final audit.
