# SVG export — what goes out, and as what

An icon you draw in Photonz leaves as **an icon**, not as a picture of one:
Export offers SVG beside PNG, JPEG and HEIC, and what it writes is a real vector
file that any website, app or icon set can use. This is the other half of the
Pen (`vector-paths.md`): drawing a shape you cannot get out is half an answer.

Behind the Next flag `next-export-svg`, which needs `next-pen`.

## Where it lives

| Piece | Where | Why there |
| --- | --- | --- |
| The writer | `PhotonzCore/SVGExport.swift` | It is geometry and string building and nothing else: no Core Image, no AppKit, no type engine. It can be tested without a renderer, and it is. |
| The bridge | `PhotonzRender/SVGExporter.swift` | The only two things the writer cannot do for itself: a PICTURE of a layer with no vector answer (`DocumentRenderer`) and the OUTLINE of a text layer's letters (`TextRasterizer.outlinePath`, CoreText). Both are handed in as closures. |
| The way in | `Photonz/ExportDialog.swift`, `EditorState.exportSVG` | The format picker, the line that replaces the scale row, and the save panel. |

## The coordinate space: no flip

The document model counts y from the top. **So does SVG.** This is the one place
in the codebase where the two spaces already agree, so the flip
`DocumentRenderer` owns (`overview.md`) has no business here. A shape thirty
points down the canvas is thirty points down the file. Getting this wrong
produces a file that is upside down and reads as a rendering bug.

A layer is placed once, with a `transform="translate(x y)"` on its own element,
and everything inside it is written in the layer's own coordinates — the same
space the rasterizers draw in, so the numbers in the file are the numbers in the
model. A layer at the origin gets no transform at all.

## What each layer kind writes

**If you add a layer kind, you owe it a row here.** Anything not listed falls
through to a picture, which is safe and lossy, and the export says so.

| Layer | SVG | Notes |
| --- | --- | --- |
| Path | `<path d>` | A run with no handle on either end is written `L`, so a straight edge is straight; a run with handles is written `C`. Closed shapes close with `Z`. `fill-rule="evenodd"` where the shape has a hole. |
| Rectangle | `<rect>` | `rx` for even rounding. Corners rounded ONE AT A TIME become a `<path>` with arcs, which is the one rounding `<rect>` cannot say. |
| Ellipse | `<ellipse>` | |
| Line | `<line>` | Round cap, like the canvas. |
| Text | `<path>` of the letters' outlines, with a `<title>` | See "Why text is outlined" below. |
| Group | `<g transform="translate(…)">` | The nesting and the order the layers list shows. A frame's background is a `<rect>` under its children. |
| Picture | `<image href="data:image/png;base64,…">` | An untouched photograph goes out as its OWN pixels — smallest file, sharpest picture. One that is cropped, turned, rounded off or wearing an effect is re-rendered through the real renderer at 2× so it looks the way it looks on the canvas. |
| Arrow, highlight, measurement, zoom callout, lens, collage | `<image>` | No vector answer yet. Each is reported. |

### Paint

A flat colour writes `fill="#RRGGBB"`, with `fill-opacity` on its own where the
colour has alpha in it — the same for `stroke`. A gradient writes a definition
in `<defs>` and points at it:

* **Linear** → `<linearGradient gradientUnits="userSpaceOnUse">` with the ends
  from `Paint.linearEnds(in:)`, so the ramp is aimed exactly where the canvas
  aims it.
* **Radial** → `<radialGradient>` with `Paint.centerPoint(in:)` and
  `Paint.radialRadius(in:)`.
* **Angular** → nothing. SVG has no conic ramp, so a swept shape falls back to a
  picture and says why.

### The line's position

A centred line is a plain `stroke`. Inside and outside are not things SVG can
say, so the file does exactly what `PathRasterizer` does: it draws the line
DOUBLE width and cuts off the half that should not be there — a `<clipPath>` of
the shape for an inside line, a `<mask>` for an outside one. On a rectangle or
an oval it is plain geometry instead: the box is inset by half the width, which
needs no cutting at all.

A drawn box's edge is a **Border in the Effects list**
(`OutlineRetirement.swift`), not a stroke on the shape, so the ring is written
from the effects: the band from the outer edge inwards by its own width, which
is a stroke riding half a width in from there. Several borders write in the
order the list paints them, foot first.

## Why text is outlined

A `<text>` element renders in whatever face the machine opening the file happens
to have. An icon handed to somebody without that font comes out wrong, and an
icon is exactly the thing that gets handed to somebody else. So the letters are
written as their outlines, laid out through the same framesetter the canvas
draws with, and the words themselves ride along in a `<title>` so the file can
still be searched and read aloud.

The cost is real and deliberate: **you cannot retype the words in the exported
file.** That is the right trade for a file whose job is to look the same
everywhere. A text layer wearing a halo round its letters (`BorderFollows`)
falls back to a picture instead, because that halo is painted into the words.

## What "clean" means here

* No `<defs>` block unless something needed one.
* No transform that does nothing: a layer at the origin gets none.
* No group that holds nothing, and no wrapper round a layer that turned out to
  be one shape.
* Two-space indentation, so a person can open it in an editor and recognise
  their own drawing.
* The only generated names are gradient and clip ids, one number each.

## Saying what it could not do

`SVGExport.fallbacks(in:)` answers the same question the writer answers, without
writing anything, so the **Export sheet says it before you save**: which layers
go out as pictures, and why, in plain words. Finding out afterwards, by opening
the file, is the failure this exists to prevent.

## How it is checked

By **rendering the file back**, never by reading the text
(`Tests/PhotonzRenderTests/SVGExportRenderTests.swift`). macOS can rasterize an
SVG through `NSImage`, so every case — a path, a rounded box, an oval, a line, a
group, an inside line, an outside line, a hole, a linear ramp, a radial ramp,
outlined words, a shadowed shape, a photograph — is drawn twice, once by the app
and once by the system's own SVG reader, and the two pictures must agree to
within one part in 255 averaged over the canvas. `Tests/PhotonzCoreTests/SVGExportTests.swift`
covers the writing itself.

## Known rough edges

* **An arrow, a highlight, a measurement, a zoom callout, a lens and a collage
  all fall back to pictures.** Arrows and measurements are the ones a redliner
  would miss.
* **A shadow, a blur or a glow costs a shape its vectors.** SVG has
  `feDropShadow` and `feGaussianBlur`; neither is wired up yet.
* **A sweeping gradient falls back.** A conic ramp can be approximated with
  wedges, at the cost of a big file.
* **A group that clips its contents falls back**, and so does a shape whose
  LAYER box is rounded off (as opposed to the shape's own corners).
* **Blend modes fall back.** `mix-blend-mode` exists in browsers but is not in
  SVG itself, and the render-back check could not verify it.
* **A fallback picture is rasterized at 2×.** It is the one part of the file
  that does not scale.
