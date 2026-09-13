# Separate into Layers

Take a screenshot, right click the picture, choose **Separate into Layers**, and
every run of text and every box in it becomes its own layer you can pick up and
move. Where a piece came from, the background is filled with what was around it,
so dragging a label off a dark button leaves the button looking untouched rather
than punching a hole in it. A box that is really one flat colour comes out as a
real rounded rectangle you can resize and repaint, not a picture that stretches.
Anything the app cannot read confidently is left in the picture and not
mentioned.

This document is the source of truth for the whole Separate set. It covers the
first two slices: text runs, and boxes. The later slices (hierarchy, shadows,
real words) extend the three seams described at the end.

## What you get

Exactly **two things**, never three:

1. Each piece on its own layer — the boxes down the page first, then the runs of
   text in reading order — stacked directly above the picture it came from.
2. The picture itself, with the space each piece came from filled in.

The stacking order is not a preference. A label sits ON the button it came off,
so the boxes go underneath: a button laid over its own label would hide it the
instant the command finished.

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
2. **Hierarchy.** Text inside a box comes out as a child of that box. *(Not yet.
   The box and its label come out as two layers side by side, so dragging a card
   leaves its labels where they were. The seam for fixing it is below, and it is
   the next task in the set.)*
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

## The boxes

`PhotonzCore/BoxSweep.swift`, on `PixelField` (colour, not brightness: a red
button and a blue one of the same weight are not the same box).

The rule, in one sentence: **a box is something sitting on the picture's own
background.** A screenshot is painted the way UI is painted — one flat colour
behind everything — and whatever interrupts that colour is a thing.

1. **Patches of one colour.** Neighbouring pixels within 3 levels of each other
   are the same region, union-found in one pass. Chaining down a slow ramp is
   deliberate: a page with a gentle gradient is still one page. The step across
   an antialiased edge is tens of levels, so a box never leaks into its page.
2. **The page** is the region holding most of the picture's outer border. If no
   one region holds half of it there is no page to read anything against — a
   photograph, a collage — and nothing is claimed at all.
3. **The islands** are the connected pieces of everything that is not the page.
   One touching the edge of the picture is dropped: the frame cut it in half, so
   its real shape is not in the picture and the app does not guess it.
4. **One level.** What sits on a box travels with it. That is the whole answer to
   the question this feature lives or dies on — WHICH of the nested rungs are
   worth becoming layers. A settings pane has a rung for the window, one for the
   pane, one for every group and one for every row; taking all of them produces
   a tree nobody wants. Taking one level produces the cards and the buttons,
   which is what a person points at.
5. **Something that fills the picture IS the picture.** A screenshot of one
   window offers one island the size of the frame. Rather than hand back the
   whole window, whatever that island is mostly painted becomes background too
   and the sweep looks at what sits on THAT. Three steps at most.
6. An island is offered when it is at least `minElement` on both sides, covers
   no more than 60% of the picture, and fills at least 75% of its own bounding
   box. That last one is what keeps a letter the text sweep could not read from
   coming back round as a box.

### Two things that were tried first, and measured

Both are written down so nobody spends the afternoon again.

- **`ElementBounds.candidates`**, the measure tool's ladder, looks like the
  answer and is named as such in the task. Probed on a 16 px grid over the
  1440x960 fixture it costs 7.0 ms a probe, **37.6 seconds** for the picture, and
  returns **320 distinct overlapping rungs** — every pair of agreeing horizontal
  boundaries, so two rows, three rows, a card, a card group. It is built to
  answer "what is under the pointer", where being generous is right. Sweeping a
  whole picture is the opposite job.
- **`TextRunSweep`'s own ink components** already know a box when they see one
  (`isBox`). But ink is measured against a 33 px box mean, so a box's edges read
  several pixels inside where they really are, and only boxes with more than 15%
  contrast are found at all — on the fixture, 4 of them, all mis-sized. Good
  enough to keep a switch out of the text layers, nowhere near good enough to
  cut one out.

## A box that is really a shape

A flat rectangle with a known rounding and a known fill can stop being a picture
and become a real one: it resizes without going to mush, and it takes a colour.
Anything less certain stays a picture, because a shape that is nearly right is
worse than pixels that are exactly right.

**Reading the edge to better than a pixel.** A pixel the box's edge only clips is
still a pixel of the box, and near a rounded corner those reach a long way
diagonally — read the mask as it is and a corner rounded by 12 px comes back as
7. So each pixel's coverage is worked out from how far its colour sits from the
page, measured against the paint RIGHT BESIDE it rather than against one reading
for the whole box. (One reading fails on the case that matters: a white field
inside a grey edge reads as uncovered, because white is nearer the page than grey
is.)

**The rounding** is then the radius that disagrees with the fewest pixels, tried
one at a time out to 64 image px, per corner — so a card rounded only at the top
reads that way.

**The shape** is offered only when all of this holds:

- the box agrees with that rounded rectangle over 97% of its own bounding box
  (an oval, a blob or a chart does not);
- everything inside it, three pixels clear of the edge, is one colour to within
  2 levels out of 255;
- everything between that clean reading and the edge is the same paint part way
  through a blend, so nothing is hiding in the ring.

**The edge** is read the same way, one width at a time from 1 to 4 image px:
a flat band round the outside whose colour differs from the fill. It is read
along the box's straight runs only — a band that hugs a curve is read against a
rounding that is right to about a pixel, so at the corners it strays outside the
paint it is trying to read and comes back with the page in it.

The bands are tight on purpose. Read loosely, a box with a two pixel edge answers
"one pixel", because a band that starts deep enough to clear the edge's own
antialiasing also clears the edge.

**The order matters more than any of it.** The text comes out FIRST and its holes
are filled before a single box is looked at. That is why the blue Save Changes
button on the fixture comes out as a real `#0A84FF` rounded rectangle: by the
time the box pass reads it, its white label has been lifted off and the space
filled with the button's own blue. Read the other way round it is a picture of a
button with words baked into it, forever.

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

## Cutting a box out

A box is not unmixed the way a run of text is. The sweep already said which
pixels are the box, so there is nothing to guess about the inside: it comes out
whole, switch knobs and dividers and all, cut to its own rounded outline with the
page it was sitting on left behind. Only the rim the renderer antialiased is
worked out, and each of those pixels is measured against the paint right beside
it — so a card that is barely lighter than its page keeps its edge instead of
dissolving into it.

A box that came out as a shape needs no bitmap at all.

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

## Nothing is separated twice, and no space is filled twice

A box may HOLD something already spoken for: a card holds the labels the same
command just took out of it, and the hole each one left has already been filled.
What it may not do is BE one, or clip one, because then the same pixels would
come out twice. So a run of text is either clear of every box or wholly inside
one, and a box that swallows the holes its own labels left carries them: those
pixels are painted once, by the box, not twice. `Result.patched` is the list of
spaces filled in, and no two of them overlap — which is a thing a test can check
rather than a thing a comment can claim.

## Running it twice

The second run finds nothing: after the first, the picture's text pixels are the
patch and its boxes are gone. Nothing is separated again and no second repair is
stacked. The command still answers — the notice pill says nothing was found —
rather than looking broken.

## What it says

A notice pill (`CopyConfirmation.Subject.separatedIntoLayers`) because the canvas
looks identical the instant after: nothing moves, so without a word on screen the
command reads as having done nothing at all. It says how many runs came out and,
when there were any, how many were left in the picture because they could not be
read confidently.

There are two different nothings and the pill says the right one. Running the
command a second time finds nothing at all, because the first run took it:
"Nothing here reads as text or a box". A photograph with a caption on it finds
something and cannot read it: "1 piece left in the picture, too unclear to read".

With boxes it counts both: "9 runs of text and 2 boxes. 2 left in the picture,
too unclear to read".

The FIRST run is left picked — one outline on the canvas, at the top of the page
where reading starts, and the layers list scrolled to the new rows. Deliberately
not all of them: a person's first move is to grab a run and drag it, and a drag
with every piece picked would carry the whole page off the picture in one go.

## Names

`Text 1`, `Text 2`, … in reading order, and `Box 1`, `Box 2`, … down the page.
Without OCR the app does not know the words, and numbering down the page at
least matches the order an eye scans the picture; it knows a box is a box and
does not know it is a button, so it says the thing it knows. When the later
slice reads the actual characters, the name becomes the words, and nothing else
about this changes.

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

Shadows are not modelled at all yet, and on the fixture that is exactly what
stops the two cards coming out. Both are found — they are two of the four things
sitting on that page — and both are put back, because what is around them is not
one colour and not a straight ramp: it is a soft shadow, darkest against the card
(223 out of 255 against a 242 page) and gone six pixels out. Filling that space
with any one colour would leave the shadow behind as a grey halo of a card that
is no longer there, so rule three applies and the card stays in the picture. The
shadow slice is what changes that: a shadow read as a shadow comes off WITH its
box, as a real shadow effect, and then the space under it is plain page again.
