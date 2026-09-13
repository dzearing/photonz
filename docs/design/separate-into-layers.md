# Separate into Layers

Take a screenshot, right click the picture, choose **Separate into Layers**, and
every run of text in it becomes its own layer you can pick up and move. Where a
word came from, the background is filled with what was around it, so dragging a
label off a dark button leaves the button looking untouched rather than punching
a hole in it. Anything the app cannot read confidently is left in the picture and
not mentioned.

This document is the source of truth for the whole Separate set. This first slice
does text runs only. The later slices (boxes, hierarchy, shadows, real words)
extend the three seams described at the end.

## What you get

Exactly **two things**, never three:

1. Each run of text on its own layer, in reading order, stacked directly above
   the picture it came from.
2. The picture itself, with the space each run came from filled in.

There is no separate "repair" layer stacked over an untouched original. The
picture's own pixels are repaired. That is a bake, and it is deliberate: see
*Why the repair is destructive* below.

## Where it lives

- Right click a layer row in the layers panel → **Separate into Layers**.
- **Layer ▸ Separate into Layers**, with the same name.

It is offered on any picture layer that is drawn the way its box says it is,
**including the locked Background**, because the background picture is the case
a person actually starts from. Locking a layer stops a click on the canvas from
dragging it; it does not stop a command aimed at it by name.

It is behind `next-separate-into-layers`, on by default in Next.

## The three rules the user set

1. **No holes.** Taking a piece out and moving it must never reveal a gap.
2. **Hierarchy.** Text inside a box comes out as a child of that box. *(Not this
   slice. The seam for it is below.)*
3. **Ignore what you cannot read.** A part the app cannot interpret is left in
   the background picture, untouched and unmentioned in the layer tree. Guessing
   badly is worse than skipping.

## The sweep

`PhotonzCore/TextRunSweep.swift`. One pass over the brightness field
(`LumaField`, already computed and cached beside the edge map for the measure
tool), no OCR, no Vision, no new dependency.

The measure tool's `TextLineBounds` already reads a line of text, but it reads
the line **under a probe point**: it votes a local background, seeds on the ink
nearest the pointer and grows a band. Calling that at every point of a 12
megapixel capture is hundreds of thousands of probes. So the sweep is the same
idea turned inside out — find all the ink at once, then band it — and it keeps
`TextLineBounds`' thresholds so the two agree about what text is:

1. **Local background.** A separable box mean of the brightness over a
   `2·gap+1` window, computed with a sliding sum, so the whole picture costs two
   linear passes rather than a histogram per probe.
2. **Ink** is any pixel whose brightness sits `TextLineBounds.inkFloor` (15%)
   or further from that local mean. On a flat panel the mean equals the pixel and
   nothing is ink; on letters, the glyphs are.
3. **Rows into segments.** Each row's ink runs are merged when the clean stretch
   between them is under `gap` (`TextLineBounds.defaultGap`, 16 px on a 2x
   capture — a word space is well under it, two side-by-side items well over).
   A segment whose ink is one unbroken stretch across 90% of itself is a **rule**
   (an underline, a divider, the top edge of a card) and is dropped before
   anything is joined to it, the same test `TextLineBounds` uses to stop a band.
4. **Segments into runs.** Segments in rows within `max(2, gap/8)` of each other
   that overlap horizontally are unioned. What comes out is a line-of-text shaped
   component; its bounding box is the run.
5. **Does it look like words?** Same questions `TextLineBounds` asks: wide
   enough to be an element, no taller than eight gaps, at least as wide as it is
   tall, ink covering no more than 85% of the box (not a filled block), at least
   one clean column inside it (daylight between two letters), and no rule row.
   Anything else is quiet.
6. Overlapping runs are not both kept: a run that intersects one already
   accepted is dropped, so no two pieces can ever claim the same pixel.

Runs come back in **reading order** — banded by row, then left to right.

Cost is linear in pixels. Measured on the fixture and on a 12 megapixel capture
in the commit note.

## The patch

`PhotonzCore/PatchFill.swift` decides, `PhotonzRender/LayerSeparator.swift`
samples and paints.

Each run is grown by a **halo** of `max(1, gap/8)` px before anything is sampled
or painted. Without it the antialiased rim of the glyphs sits just outside the
box: it would poison the ring reading (a pixel 10% into a letter is not ink by
the 15% floor, but it is 25 levels off the panel colour) and it would be left
behind in the picture as a faint ghost of the word.

The **ring** is the band just outside the halo, up to 3 px wide, keeping only
samples that are not ink — so a button's border, or a neighbouring word, never
votes on what the background is.

Then, in this order:

1. **Solid.** If every ring sample is within 2 levels of the ring's median, the
   space is filled with that median. This is the overwhelmingly common case in
   real UI: words on a solid button, a bar, a card. It is **exact**: white words
   on a solid dark bar leave that bar one flat colour, byte for byte.
2. **Linear gradient.** Otherwise a least squares line is fitted through the ring
   down the box and across it. If either fit explains every sample to within 6
   levels, the space is filled with that gradient.
3. **Skip.** Otherwise the run is left in the picture and no layer is made.

There is deliberately **no content-aware inpainting and no edge extend**. On flat
UI neither is needed. On a photograph, inpainting invents detail that is not
there and an edge extend smears it sideways, and the user was explicit that a
visible guess is worse than leaving the thing alone. A run whose surroundings are
a photograph is a run we cannot read confidently, and rule 3 says skip it.

## Cutting the text out

A piece must be the **letters**, not a rectangle of button with letters on it —
otherwise dragging a label off a blue button drops a blue tile on whatever it
lands on.

There is no OCR here, so the cut is an unmix rather than a trace. For every pixel
in the run's halo box, with `bg` the patch colour that will go under it:

- `d` is how far the pixel sits from `bg`, `contrast` is how far the run's
  darkest-or-brightest tenth sits from it,
- `alpha = min(d / contrast, 1)` — full inside a stroke, partial on an
  antialiased rim, zero on the panel,
- the colour is `(pixel - (1-alpha)·bg) / alpha`, which is the original ink
  colour back out of the blend, so syntax-coloured or two-tone text keeps its
  own colours rather than being repainted one flat tone.

A run whose ink barely differs from its background (`contrast` under 10%) is not
confidently readable and is skipped.

## Why the repair is destructive

The picture's own bitmap is replaced by the patched one. That is a bake, and it
is the one place in the app that repairs a picture in place.

It is what the user asked for, in their own correction on 2026-09-12: *"I mean
that I WANT it to fill that space with the bg color so that the text is on one
layer the bg is on the other."* The alternative — an untouched original with a
repair layer stacked over it — is three things in the tree where they asked for
two, and the tree is the thing they are separating in order to read.

It is **fully undoable**, which is the requirement, not non-destructiveness:
undo is a whole-document snapshot (`History.perform`), the original bitmap stays
in `ImageStore` under its own ref, and one Command Z brings the untouched
screenshot back along with every layer the command made, in a single press.

The app already bakes pixels deliberately in exactly this way — Rasterize Layer
and Turn a Shape into a Picture — so this follows a precedent rather than
breaking the non-destructive rule in `CLAUDE.md`, which is about layer *styling*
(blur, shadow, border, radius, opacity) staying a render-time effect.

## Running it twice

The second run finds nothing: after the first, the picture's text pixels are the
patch. Nothing is separated again and no second repair is stacked. The command
still answers — the notice pill says nothing was found — rather than looking
broken.

## What it says

A notice pill (`CopyConfirmation.Subject.separatedIntoLayers`) because the canvas
looks identical the instant after: nothing moves, so without a word on screen the
command reads as having done nothing at all. It says how many runs came out and,
when there were any, how many were left in the picture because they could not be
read confidently.

There are two different nothings and the pill says the right one. Running the
command a second time finds no text at all, because the first run took it:
"Nothing here reads as a run of text". A photograph with a caption on it finds
text and cannot read it: "1 run of text left in the picture, too unclear to
read".

The FIRST run is left picked — one outline on the canvas, at the top of the page
where reading starts, and the layers list scrolled to the new rows. Deliberately
not all of them: a person's first move is to grab a run and drag it, and a drag
with every piece picked would carry the whole page off the picture in one go.

## Names

`Text 1`, `Text 2`, … in reading order. Without OCR the app does not know the
words, and numbering down the page at least matches the order an eye scans the
picture. When the later slice reads the actual characters, the name becomes the
words, and nothing else about this changes.

## The seams the later slices use

The three pieces this slice owes the rest of the set, designed so a detector and
a nesting pass can be added without reopening any of it:

- **The sweep returns pieces.** `TextRunSweep.sweep` returns rects in reading
  order plus the ink mask it built. A box detector is another producer of rects
  against the same mask; it does not touch the sweep.
- **The patch is a separate decision from the cut.** `PatchFill.decide(ring:)`
  takes ring samples and returns a fill, and knows nothing about text. A box
  piece patches through the identical call.
- **The builder takes a list.** `PhotonzDocument.separateIntoLayers(id:patched:
  pieces:)` swaps the source layer's bitmap and inserts N pieces above it in one
  mutation, therefore in one undo step, however many pieces there are. The
  hierarchy slice changes what that list looks like (a piece gains children); it
  does not change when the mutation happens or how undo sees it.

Shadows are not modelled at all yet. A shadow around a box reads as ink, so it is
part of what the box detector will have to decide about; nothing here assumes it
is absent.
