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

### 4. One engine, seven media

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
