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
   text in reading order — stacked directly above the picture it came from, and
   ARRANGED the way the screen was: a label that sat in a button comes out
   inside that button.
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
2. **Hierarchy.** Text inside a box comes out as a child of that box. Dragging
   the button carries its label. See *Which piece sits in which* below.
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
background.** A screenshot is painted the way UI is painted — flat colour behind
everything — and whatever interrupts one of those colours is a thing. A page has
one such colour and a window has several, which is the same rule and not a
special case.

1. **Patches of one colour.** Neighbouring pixels within 3 levels of each other
   are the same region, union-found in one pass. Chaining down a slow ramp is
   deliberate: a page with a gentle gradient is still one page. The step across
   an antialiased edge is tens of levels, so a box never leaks into its page.
2. **The background** is every patch holding at least a tenth of the picture's
   outer border. A flat page holds the whole border by itself and is the only
   one, which is the case this started as. A window is not like that: a dark
   canvas, a toolbar and a panel down each side each hold a corner of the border
   and not one of them holds half. Demanding a single page gave up on captures
   like that entirely — three of six real screenshots, including one of this
   app's own window, came back with their words and NOT ONE of their buttons.
   Each of those paints is a background in its own right, and whatever
   interrupts any of them is a thing.

   If no patch holds even a tenth of the border there is nothing for anything to
   be sitting on — a photograph, a collage — and nothing is claimed at all.
3. **The islands** are the connected pieces of everything that is not
   background. One touching the edge of the picture is dropped: the frame cut it
   in half, so its real shape is not in the picture and the app does not guess
   it. Dropping it is about not OFFERING it, and it happens last, after step 5
   has had its look inside.
4. **Two levels.** The boxes on the page, and then the boxes on THOSE. This is
   the question the feature lives or dies on — WHICH of the nested rungs are
   worth becoming layers — and it was answered with "one" until the layers list
   could nest. A settings pane has a rung for the window, one for the pane, one
   for every group and one for every row, and taking all of them as a flat pile
   is a tree nobody wants; taking them as a TREE, where a card closes up into
   one row, is shorter than the flat list was.

   So the same question is asked again inside every box that was taken: the
   parent's own paint plays the part the page plays outside it, and whatever
   interrupts it is a thing on the parent. On the fixture that turns four boxes
   into ten — the two cards and two buttons, plus four switches and two text
   fields nested under the cards, with the fields now real rounded rectangles
   because they are finally read against the card rather than against a page
   they cannot see.

   It stops at two (`BoxSweep.maxBoxDepth`), which is where the answers stop
   being things a person points at: three is the knob inside the switch and the
   chevron inside the row. Nothing is lost by stopping, because a box is cut
   whole — the knob still comes out, inside its switch.

   Three things keep the tree honest, and all three earn their place:

   - A box that read as ONE FLAT COLOUR is never looked inside. That reading
     already says every pixel three clear of its edge is the same paint, so
     there is nothing in there, and on a screen full of buttons that is most of
     the boxes.
   - The band two pixels in from the parent's own outline is the parent's
     antialiasing, not a thing on it (`bodyMargin`). Without taking it off, a
     header painted edge to edge joins the rim running all the way round the
     card and the pair reads as one piece the size of the card.
   - A child needs a clean ring of its parent to be read against, same as
     anything else. That is what refuses the knob inside a switch when the
     switch IS taken on its own: the knob nearly fills the track, so the band
     round it catches the track's own rounded ends and agrees with nothing.
     Something that nearly fills its holder stays in it.

   A child is cut out of its PARENT: its edge is read against the card, the
   space it leaves is filled with the card's own colour, and only what was
   sitting on the PAGE leaves a space in the page. So a card comes out whole
   rather than with a switch-shaped hole in it, and the switch is not in the
   picture twice. If a card is left behind, everything on it is left behind too
   — unless the card turned out to be SCENERY rather than a piece, which is step
   5. A card the frame cut in half used to take the row on it down with it, on
   the grounds that lifting the row would leave a hole nobody could fill. Once
   the card is read as background that stops being true: the row's space repairs
   to the card's own colour, so the row comes out and the cut card stays exactly
   as it looked.
5. **Scenery is looked through, not handed back.** Two things are scenery:
   something the size of the picture, and something big and full of holes.
   Rather than hand either back, whatever it is mostly painted becomes
   background too and the sweep looks at what sits on THAT. Three steps at most,
   and it stops early when nothing covers a twentieth of the piece, which is
   what a photograph looks like from here.

   - **The size of the picture.** A screenshot of one window offers one island
     the size of the frame.
   - **Big and full of holes.** A window's chrome with the canvas and the panels
     cut out of it is a comb: far too sparse to be a box and far too big to be
     nothing. It used to be dropped for having no shape, and every button on it
     went with it.

   This pass sees the pieces the frame CUT as well as the ones it did not, which
   nothing else does. A capture of a whole screen is one window on a desktop
   picture, and the window and the desktop around it are a single connected
   piece running off every side of the frame. Thrown away for being cut, it took
   the entire window with it. Looking inside a cut piece is not the same as
   claiming it: its real shape is still not in the picture, so it is still never
   offered as a box.
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

### Stepping off the box's own edge

A box on a DARK panel breaks an assumption a light one never does, and it broke
this feature on the surface the user looks at most.

A field on the inspector is painted about eight levels off the panel behind it,
and somewhere down its rounded corner the step between the two is under
`BoxSweep.colorTolerance`. Colour regions chain, on purpose — that is what lets
a page with a gentle gradient on it still be one page — so the field's edge
chains into the PANEL's own patch of colour and counts as background. The
field's island then stops INSIDE its own edge, and the band read just outside
the field is one row of that edge: a colour that is not the page, in a ring that
is otherwise flat. Rule 1 refuses it, rule 2 refuses it, and rule 3 leaves the
field in the picture.

Measured on a 602 x 704 crop of this app's own inspector: three of the four
X/Y/W/H fields were refused for exactly this, on rings that were 85% one flat
colour. The whole crop gave back three boxes.

So when the band right against a box will not agree, the ring **steps off it**
and reads again a little further out, up to `BoxSweep.maxBorderWidth`. Nothing
is loosened: the reading still has to be one flat colour or one even ramp, and
every sample still has to be background. Only WHICH background pixels are asked
changes, and a neighbouring control was never in the band to begin with — it is
an island, and the ring keeps only what the sweep called background.

Two things the step has to get right:

- **Whatever it steps over comes out with the box.** That band is what it just
  decided the box's own edge is, so the repair covers it. Without that the four
  fields came out and left a hairline rectangle where each of them had been.
- **A box sitting on another box never steps.** The mistake being undone is a
  page-level one, and inside a box the surround is not a patch of colour at all,
  it is the parent's own pixels. Stepping there would step over the one thing
  that keeps a knob inside its switch: something that nearly fills its holder has
  no clean ring of the holder to be read against, and that is how the app knows
  it is a part rather than a thing.

On the inspector crop this takes the boxes from three to six — all four fields,
as real rounded rectangles — and the refusals from ten to seven. Every refusal
left is a word with a red redline annotation drawn through the band around it,
and those are right to refuse: lifting the word would erase part of the line
somebody drew. Pinned by `Fixtures/dark-fields-2x.png` and
`SeparatedDarkFieldsTests`.

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

## How much one command takes

A whole screen is not a settings pane, and the limit is set from measurement
rather than taste. Run over real captures, what the sweep finds:

| capture | pieces it can read |
| --- | --- |
| the settings pane fixture, 1.4 MP at 2x | 11 |
| a dark inspector panel, 0.4 MP at 2x | 17 |
| this app's whole window, 7.7 MP at 2x | 119 |
| a dense web dashboard, 5.1 MP at 1x | 724 |
| an encyclopedia article, 5.1 MP at 1x | 225 |
| a photograph of a mountain, 1.7 MP | 437, none of them readable |

The first three are a layers list. The fourth is a wall of identical names you
scroll rather than read, and a command that hands you one has not helped you.
So `PhotonzCore/SeparateBudget.swift` sets the ceiling:

- **150 runs of text**, which sits above the whole-window case on purpose:
  taking a whole screen apart in ONE command is the entire point, so the limit
  must not bite on the ordinary picture. It bites on the web page.
- **30 boxes**, far fewer, because a box is a container and thirty groups to
  open is already more than a list wants.
- **4 levels deep** (`LayerNesting`), which is past anything a detector finds
  today and is where a row's name would start further in than the twist that
  opens it. Nothing is thrown away to keep it: a piece deeper than four levels
  joins the deepest group that holds it, so it still travels with the thing a
  person would drag.

**Past the limit the biggest pieces come out.** On a dense page the small ones
are the hundredth body-text run, which is exactly the piece nobody was going to
reach for; the big ones are the headings, the cards and the buttons. The rest
stay in the picture untouched and are COUNTED.

**And running it again takes the next hundred and fifty.** The pieces that came
out are no longer in the picture, so the next sweep reaches the ones behind
them. Measured on the dashboard capture: 142 out, 361 left; run again, 142 more
out, 219 left. That is what the pill means by *run it again for more*, and the
second run's names carry on where the first stopped (`LayerNaming.numberAfter`)
so no list ever holds two rows called Text 57.

Nothing found is ever dropped silently, which is what makes the count in the
pill checkable: `TextRunSweep` stops at 400 candidates but hands back how many
it stopped short of (`Sweep.beyondLimit`), and every one of those is added to
the tally. Before that it truncated quietly, and the pill on the dashboard
capture said 256 left when 580 were.

### How long it takes

Linear in pixels, 12 to 30 ms per megapixel in a release build, and it runs off
the main thread with the document touched only when it comes back. Measured end
to end, reading the picture plus separating it:

| capture | reading | separating |
| --- | --- | --- |
| 1.4 MP settings pane | 37 ms | 155 ms |
| 5.1 MP web dashboard | 73 ms | 73 ms † |
| 7.7 MP whole screen at 2x | 138 ms | 98 ms † |
| 12.2 MP tiled fixture | 110 ms | 959 ms |

† measured before the shadow slice and not re-measured since; both will have
gone up in the same way the other two rows did.

Looking inside the boxes added about a tenth on both re-measured rows (137 to
155 ms and 864 to 959 ms, measured back to back on the same machine). That is
one more pass over each box that was taken, and it is only paid on the boxes
that could hold something: a box that read as one flat colour is skipped
outright, and the parent's own paint is counted on a one-in-nine grid rather
than pixel by pixel, which together cost about a third of the first attempt.

The two rows that were re-measured went up because the CARDS now come out. Most
of that is work the command could not do before: cutting two 1312 x 264 cards to
their own outlines, and painting a repair over their space and their shadows.
The shadow reading itself is bounded by design — each edge is read at most 256
pixels along and 48 out, and the search for the four numbers is separable, so
one whole card costs about forty milliseconds in a DEBUG build and the search is
eighteen times cheaper than the obvious three-deep grid it started as.

Single cold passes, except the last row, which is the faster of two. No real
capture on the machine this was measured on reaches 12 megapixels: the
screen is 3456 x 2234, which is 7.7. The 12 megapixel row is the fixture tiled
out to 4032 x 3024 with twelve times as much text in it as any real screenshot
would have, which is the honest worst case rather than a real one.

Nothing is shown while it works, and the walk that runs it over a whole
screenshot prints what the main thread was doing while it did: the app settles
0.1 s after the command and records no stall at all. A spinner that flashes for
a tenth of a second is worse than no spinner.

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

There is a THIRD sentence, for the picture that offered more than one command
takes: "142 runs of text. 361 left in the picture, run it again for more". The
count is everything still in the picture for either reason, because that is the
number a person can check by looking at it; what changes is what to do about it,
and a piece the limit crowded out comes out on the next run while one that could
not be read never does. The line is only offered when something actually came
out — with nothing to show for the first run, sending somebody round again would
be a loop.

**A photograph is told it is a photograph.** Measured on one of a mountain: 437
pieces found in the grass and the rock face, none of them readable, none of them
anything a person would point at. "437 pieces left in the picture" is a true
sentence about texture and a useless one about the photograph, and it reads as
the app having failed at something. So past a handful
(`CopyConfirmation.unreadableWorthNaming`), with nothing taken, the pill says
the plain thing: "Nothing here reads as text or a box". Under a handful it still
counts them, because that is the case the count is FOR — a caption burnt into a
photograph is one or two things you are looking straight at, wondering why they
are still there.

The FIRST run is left picked — one outline on the canvas, at the top of the page
where reading starts, and the layers list scrolled to the new rows. Deliberately
not all of them: a person's first move is to grab a run and drag it, and a drag
with every piece picked would carry the whole page off the picture in one go.

## And what it goes on saying

The pill fades after three seconds and the number goes with it. On the project
dashboard capture that number is 365 still in the picture, and it is the whole
reason a person would run the command again — so a count you are expected to act
on later cannot live in a confirmation that leaves on a timer. Four audits in one
day each asked a version of "is the pill enough". It is not.

So two places keep it, behind `next-what-a-separation-left-behind`
(`SeparationLeftover`). **Neither writes anything into the document**: the value
is held against the picture's patched BITMAP, so undo puts the original pixels
back and the note goes with them rather than leaving a count over a picture that
holds everything again.

**The picture's own row**, on the second line under its name, the same slot a
component row uses to say whether it is the original or a copy
(`ComponentRowNote`). It is where the eye already is the instant after, and it is
printed on the thing that is still holding the 365. Four answers, and each is cut
to **eighteen characters**, which is measured rather than chosen: the line shares
a narrow row with a thumbnail, a padlock and an eye, which leaves it about 95
points on the dock's own width, and "Nothing left to separate" came out of the app
reading "Nothing left to sep…".

| The picture | The row says |
| --- | --- |
| More in it than one command takes | `365 left` |
| Leftovers it simply could not read | `26 left, unclear` |
| It gave up everything it had | `Nothing left` |
| Not a screenshot at all | `Nothing readable` |

The whole sentence is one hover away, because eighteen characters cannot carry
it: "365 pieces are still in this picture. Separating it again takes the next
batch."

The row is a READOUT and not a control, for the same measured reason. "365 left"
with a **Separate again** beside it came out of the app reading "Separate agai…".
So the press lives under the list, where there is a whole row's width for it, and
the row does the one job the list foot cannot: it stays with THIS picture,
whatever gets separated next. The row's own right click menu still carries the
command.

**A line under the whole list**, which is the half that matters on a dense page.
A picture tells you why: separating the dashboard leaves the layers list 173 rows
long, scrolled to the pieces, with the picture's own row about thirty screens
below the bottom of the panel. The count was kept and nobody could see it. So the
offer also sits under the list, where nothing can scroll it away, reading "365
left in the picture · Separate again".

It speaks for the LAST picture separated, and only while another run would reach
something. A picture that came apart completely, or one whose leftovers are
simply unreadable, has nothing to offer — and by then the list is short enough
that its row is in plain sight anyway. So the line appears when there is a batch
to take and goes quiet the moment there is not, rather than sitting under the
list forever reading zero.

The pill is unchanged and still says "run it again for more". That is how a
person learns the offer exists at all; the line under the list is where they act
on it a minute later.

## Names

`Text 1`, `Text 2`, … in reading order, and `Box 1`, `Box 2`, … down the page.
Without OCR the app does not know the words, and numbering down the page at
least matches the order an eye scans the picture; it knows a box is a box and
does not know it is a button, so it says the thing it knows. When the later
slice reads the actual characters, the name becomes the words, and nothing else
about this changes.


## A run of text becomes words you can retype

`PhotonzCore/TextReading.swift` decides, `PhotonzRender/TextReader.swift` reads.

A separated run is a picture of a label. Right click it and choose **Turn into
Text** and it becomes the label: the words, in the face, size and colour the
screenshot was set in, sitting exactly where the old ones sat. Retyping it
changes the words on the button instead of covering them up.

It is a SEPARATE step you choose, not part of Separate into Layers. Separating a
screenshot is one thing a person asked for; reading the words is another, it
costs a recognition pass per run, and it is the one step here that can come back
and say no. Made automatic it would slow the command everybody uses in order to
sometimes surprise them. Offered as its own row in the same menu — right under
Separate into Layers, and in **Layer ▸ Turn into Text** — it is there the moment
they want it, on the row Separate just made.

It is offered on any picture Separate is offered on, INCLUDING the whole
screenshot, where it refuses with a signpost: *more than one run of text here,
separate it first*. A menu row that is not there teaches nothing.

That "separate step" was re-examined on 2026-09-16 against the obvious
alternative — Separate reading every run it is confident about, so nobody has to
find a second command — and the answer came back no, on measurement rather than
on taste. The short version: on this app's OWN window four of the thirty-one
runs that read come back in a family the window does not contain, and the app
calls all four `matched`, its confident verdict, so there is no bar and no
provenance filter that keeps the good ones and drops those. Folding it in would
also take the command from 155 ms to 298 ms on a settings pane and from 56 ms to
just under two seconds on a dense page. The numbers, the pictures and what to do
about the discovery problem instead are in
`docs/design/separate-reads-the-words.md`; the study that produced them is
`Tests/PhotonzRenderTests/SeparateAutoReadStudyTests.swift`.

### The words

`VNRecognizeTextRequest`, on device. This is the only place in the app that uses
Vision and the only place that needs to: every other part of this feature finds
things geometrically, and no geometric detector can hand back characters. On the
settings-pane fixture it reads all nine runs at confidence 1.00.

It is handed the run's COVERAGE, drawn black on white, rather than the picture.
The shape of the ink is the only thing that carries the characters, so handing
over a clean high-contrast version of it takes the colour question away: white
words on a blue button read exactly as well as black words on grey. Small ink is
scaled up first (a row label on a 1x capture is thirteen pixels tall, near the
floor of what recognition reads reliably) and given a white margin, because a
picture whose letters run into all four edges reads the edges as strokes.

More than one line is refused rather than joined: a run of text is one line, and
that is what makes this the step AFTER separating.

### The size and the colour, measured

The colour is the median of the pixels that are solidly inside a stroke — median
rather than mean so a cursor or a coloured bullet caught inside the run cannot
drag the whole label off its colour. On the fixture the eight dark runs come
back `#111111` and the white one on the blue button comes back `#FFFFFF`.

The size is not derived from the face's metrics, because the ink of a real
string is whatever that string happens to contain: a row label with no ascender
is x-height tall and a heading with a cap and a descender is far more. The words
are set once at a known size, measured, and scaled.

### The face, which has no API

There is no font identification API on any platform. So the app does the only
honest thing available: it SETS THE WORDS AGAIN in each of the few faces a Mac
screenshot actually contains — the system font at four weights, a monospace, and
the three the rest of the web still uses — lays each result over the original
ink, and keeps the best. `TextReading.agreement` is that number: the soft
Jaccard, the ink two masks share over the ink either of them has, laid ink box on
ink box and nudged two pixels either way to absorb a rounded point size.

A face whose word comes out the wrong LENGTH is dropped from the probe render
alone, before the nine sizes and the overlap search it would otherwise cost.

**And it is asked at the right size, which is not a detail.** The system font is
not one shape: it tracks its letters further apart at label size than at heading
size. A 2x capture's document is in the capture's own device pixels, so the same
label has to be SET at twice the point size it was captured at — and asking
whether a 13 point label is SF Pro by setting SF Pro at 27 points answers a
different question. Measured on the fixture: "Reset" agrees 0.92 with SF Pro read
at the size it was set and 0.76 read at twice it, and four of the six row labels
come back Helvetica Neue when the question is asked the wrong way round. So the
face is identified at the capture's own point size, and the SIZE is then matched
again in that face at the scale the layer will actually be drawn at.

That second pass is also the last check: whatever is about to land has to agree
with the picture too (`TextReading.landedBar`), or the run stays a picture. The
bar there is lower on purpose, because the coordinate space costs about a tenth
of a point of agreement for a reason no eye can find — a fraction of a pixel per
letter — and an overlap score punishes that hard.

### Where the words go

A text layer's box is not its letters: it holds the ascent above them, the
descent below, and the slack the rasterizer leaves so nothing clips. So the
words are set once, measured, and the box is placed by how far its own ink sits
inside it (`TextReader.frame(for:placingInkAt:)`). On the fixture every run
lands within half a pixel of where its ink was and comes out within two pixels
of the width it was.

### What it refuses, and why that is the point

A retyped label in the wrong face is the kind of thing that makes a person
distrust the whole feature, so refusing has to be a real, common, unembarrassing
outcome. Every refusal is a sentence the pill says out loud, because a refusal
nobody can account for reads as the app being broken:

| what happened | what it says |
| --- | --- |
| more than one run | More than one run of text here. Separate into Layers first, then turn one run into words |
| no words read | No words could be read here |
| the ink barely differs from what it sits on | Too faint to tell the words from what they sit on |
| nothing agrees closely enough | No face here is close enough to the one in the picture, so it stays a picture |

### Matched, or a stated fallback

When one family beats every other by a clear margin the app says it IDENTIFIED
the face. When two are within a hair of each other — which happens at label size,
where two grotesques are genuinely hard to tell apart — it takes the SYSTEM FONT
among them and the pill says so: *set in SF Pro, the closest face to the
picture*. That keeps a page consistent as well as honest: six row labels that
each scored a hair differently all come back in one face rather than three in one
and three in another, which is the thing a person would actually notice.

### The page it came from settles the family

A run cannot tell, by looking at itself, that it is the odd one out. This app's
own window reads thirty-one of its forty runs, and four of those come back in
Helvetica Neue on a window with no Helvetica Neue in it: "Corner Radius",
"Border 1", "Offset" and "Width", each of them CONFIDENT, each scoring higher
than plenty of the correct readings. So "Border 1" came back visibly heavier
than the "Border 2" directly below it, which in the screenshot is the identical
label. There is no bar that separates those four from the right answers: their
scores sit in the upper half of the range, and the page's own family was 0.05 to
0.15 behind in each case.

What tells right from wrong is the rest of the page. Every screenshot anybody
takes apart is set in one family, so the runs vote: the family the most of them
came back in is the page's, each run is then set in its own best weight of THAT
family, and a run the family cannot account for closely enough stays a picture
instead (`TextReading.pageFamily`, `TextReader.read(preferring:)`).

Measured on the three study captures:

| capture | read before | read after | in a face the page does not contain |
| --- | --- | --- | --- |
| `settings-pane-2x` | 9 | 9 | 0 → 0 |
| `app-window-2x` | 31 | 30 | **4 → 0** |
| `dense-page-1x` | 82 | 77 | **13 → 0** |

The three strays on this app's window come back as SF Pro Semibold, SF Pro
Medium and SF Pro; the fourth, "Width", scores 0.58 in SF Pro and so stays a
picture. That is the trade and it is the right way round: a picture is honest
and a wrong face is not.

**Turn into Text still works on one label with no page read.** The vote is
counted from a dozen of the runs lying beside this one, spread across them, off
the main thread and across the cores — about a tenth of a second, paid once on
the first label anybody turns into text and remembered for the rest of that
separation. Where there is no page to ask — a picture somebody dragged in, a
whole screenshot, a run all on its own — nothing votes and the run decides for
itself exactly as it did before.

The pill says which happened. A run set in the page's family when its own ink
said something else is a stated fallback rather than an answer, for the same
reason two grotesques within a hair of each other are.

### And the labels like it settle its weight

The family vote settles half the face. The other half wobbled the same way and
was more visible once a whole page came back at once: at label size two weights
of one family are a few percent apart, so six row labels of one settings pane
came back four Regular and two Medium while being identical on screen, and
"Corner Radius", "Border 1" and "Border 2" came back Semibold, Medium and
Medium while being section labels of one style.

It cannot be settled the way the family is. A page is one family; a page is not
one weight, and a page-wide vote would drag a heading down to the weight of its
rows. So the weight is settled per KIND of label, and what says what kind a
label is, is what the app already measured about it: **how big it is and what
colour its ink is** (`TextReading.WeightBallot`, `TextReading.pageWeights`).
Labels of one size and one ink settle on the weight they agree on best; a
heading is a different size, and a white section label over grey rows is a
different colour, so neither is flattened into the rows under it.

Picking all six row labels of the settings pane now shows Weight: Regular in
the panel where it used to show Mixed, which is the app saying in one word that
two of those labels came back heavier than the four beside them.

Nothing is lost to it. Where the weight the page settled cannot account for a
run's ink at all, that run is set on its family alone exactly as before — which
is the case the escape exists for, because a run that scores far better heavier
than everything beside it usually IS heavier. Measured on the three study
captures the reading counts do not move: 9 of 9, 30 of 40, 74 of 142. Full
design: `docs/design/separate-reads-the-words.md`, "One page, one weight per
kind of label".

### The name becomes the words

`Text 9` becomes `Save Changes`, which is the whole visible reward for having
asked and what turns a list of Text 1…Text 9 into a list you can read. A name a
PERSON typed is theirs and is kept (`LayerNaming.isAutoName`).

Nothing is renamed to do it. A piece of text nobody has named by hand simply
wears its own words in the layers list, read off the layer each time the list is
built (`Layer.displayName`), shortened at a word boundary when it runs past
thirty two characters. That is why retyping the words on the canvas moves the row
with them, why this costs no undo step of its own, and why the rule holds for
every piece of text in the app rather than only the ones this command made. The
moment somebody types a name of their own the stored name stops being one the app
wrote, and from then on it is theirs and the words have no say.

Deliberately no auto-contrast shadow, which is what typing fresh text on a
picture gets. These words were already legible where they came from and they are
going back exactly where they were.

### How long it takes

Forty milliseconds for one run in a release build, reading and face matching
together, off the main thread. Nothing is shown while it works: a spinner that
flashes for a twentieth of a second is worse than no spinner.

### What it measures on the fixture

All nine runs, in one family:

| run | words | face | landed |
| --- | --- | --- | --- |
| General | General | SF Pro Bold | 0.88 |
| six row labels | all read exactly | SF Pro, two at Medium | 0.60 – 0.70 |
| Reset | Reset | SF Pro | 0.76 |
| Save Changes | Save Changes | SF Pro | 0.77 |

The serif and monospace candidates lose by more than the tie margin on every run
that was checked, which is what makes the bar mean something.

### Double clicking the label reads it and opens it for typing

Flag: `next-double-click-reads-a-label`, on by default in Next. Landed
2026-09-16.

Double click already means "I want to change these words" on a text layer, and
on a separated label it used to mean nothing at all: the gesture picked the
picture and stopped, and the only way to the words was knowing Turn into Text
sat in a menu. Now, with nothing left to step into, a double click on a run this
command lifted off reads that ONE run and puts the caret in it — the same
reading, the same refusal, one undo press for the reading and a second for what
was typed.

Two things make it safe to hang on a gesture rather than a menu row:

- **Only a run.** The layer remembers that the sweep read it as a run of text
  (`Layer.isARunOfText`, set by `PhotonzDocument.separateIntoLayers` and asked
  through `Layer.holdsWordsToRead`). Every other picture is left alone, which
  matters because reading REPLACES the picture with what was found in it: the
  same gesture offered on a photograph would turn a photograph into whatever
  word happened to be on a sign in it. The blue fill under a button is a picture
  too, and double clicking that reads nothing.
- **It lands on the one label you are looking at.** That is the whole argument
  for doing it here rather than inside Separate into Layers, where the app's
  confidence cannot tell a right reading from a wrong one and a bad guess costs
  the whole separation to undo. The study is
  `docs/design/separate-reads-the-words.md`.

The reading is off the main thread like every other, so the field opens when the
words land rather than on the click — `EditorState.readTheWordsThenType` asks,
`applyTextReading` answers with `askToTypeIn`, and the canvas opens its field
once per new token and not at all if the gesture became a drag in the meantime.
A reading that comes back with nothing opens no field and raises the same line
at the bottom of the canvas the menu row raises.

Walks: `Scripts/playtest/read-a-label-by-double-click-walk.json` for the reading,
`Scripts/playtest/double-click-a-label-walk.json` for the plain case of a label
that is already words and lives inside a group.

### The line offers to read every label at once

Flag: `next-read-every-label`, on by default in Next. Landed 2026-09-17.

Turn into Text was a menu row under a menu row, and nothing on screen pointed at
it. So the words in a screenshot were a feature you had to already know about,
and then run once per label. The line the separation raises now carries a
button, **Read the Words**, and one press turns every run it found into real
text in ONE undo step.

This is the half of the study `docs/design/separate-reads-the-words.md`
recommended and the reason it could say no to reading inside the command:

- It happens **after** the person has seen what came out, so it is a choice
  about a result they are looking at rather than something that happened to
  their screenshot.
- Separate into Layers stays exactly as fast as it was.
- **The page can vote.** Read together, the runs are compared with each other:
  they vote on the family the screenshot is set in, every run is held to the
  winner, and a run the winner cannot account for stays a picture instead of
  coming back a weight heavier than the identical label beside it. Measured,
  that takes the strays to nought, at a cost of one reading of thirty-one on
  this app's own window. Reading one label at a time can never do this, because
  it only ever sees one label.

The reading itself is `TextReader.readPage`, which is where the vote and the
second look at the strays live, spread over the cores for this caller and serial
for a test. `EditorState.turnIntoTextForLayers` is the command: it collects the
runs, raises a line saying how many it is reading, and lands every reading that
came back in a single `perform`.

**What the line says afterwards** is `TextReading.Batch`: how many labels are
words, the family they were all held to, named once for the page rather than
once per label, and how many stayed pictures. That last count is the half nobody
would otherwise find out about, since a label that could not be read looks
exactly like one that was.

**While it works it says so.** A dense page is about two seconds and pressing
the button takes the offer off screen, so the line becomes "Reading the words /
142 labels" until the answer lands. This is the progress indicator the command
has owed since it learnt to read boxes.

**Three doors, not one.** The pill's button is a shortcut, never the only way
in, so the same batch is on Layer ▸ Turn into Text and on a layer row's right
click menu, both acting on everything picked (`rowMenuTargets`, the rule
Duplicate, Delete, Group and Turn Into Picture already follow). Picking the
group a big separation arrives in and choosing Turn into Text reads the whole
screenshot. One target is never a batch: it falls through to the single reading,
so the pill still names the words and the face, and a refusal still says why.

Walk: `Scripts/playtest/read-every-label-walk.json`.

### A separated row says the words in its picture

Flag: `next-a-separated-row-says-its-words`, on by default in Next. Landed
2026-09-16.

The rule above — a piece of text nobody has named by hand wears its own words —
could not reach the case it was written for, because a separated run holds no
words. It holds a PICTURE of words, so a dense page came apart into a hundred
and forty rows called Text 1 to Text 142 with nothing to tell them apart but a
thumbnail the size of a postage stamp, and typing "recommended" into the find
field, with the word plainly on the canvas, answered "No layer says that".

Now the app reads the words off each piece and the rows say them. Three things
decide the shape of it, and each one is a line somebody could disagree with:

- **The words only, never the face.** `TextReader.words` runs the recogniser and
  stops. It does not identify the family, the weight or the size, which is the
  half the study found unreliable: four of thirty one runs of this app's own
  window came back set in a face the window does not contain, and the app called
  all four its confident verdict. The words were right in every one of those. A
  name needs the reliable half and nothing else. It also answers where the whole
  reading gives up: sixty of the dense page's hundred and forty two runs are
  refused for having no matching face, and each of those is still a label
  somebody would search for.
- **After the command, never inside it.** Separate into Layers is untouched and
  exactly as fast as it was. The reading starts once the pieces have landed
  (`EditorState.readWordsOffRuns`), takes a dozen pieces at a time from the top
  of the list down, spreads each dozen over the cores at a priority that yields
  to whatever the person is doing, and fills the names in behind itself. The
  dense page's 142 runs read in 1650 ms one after another, which is a few
  hundred spread out, so the numbers become words about a second after the pill
  appears.
- **Nothing is written into the document.** The reading is held against the
  BITMAP, beside the document and not in it, the way the leftover counts already
  are (`EditorState.wordsReadOffPictures`). The row works its name out as it is
  drawn (`Layer.displayName(readWords:)`). So the separated picture is byte for
  byte what it was, no undo step is spent on it, undoing the separation and
  running it again finds the reading already there, and the moment somebody
  names a piece by hand or turns it into real text their answer takes over.
  Opening the rename field on a row that is saying read words and pressing
  Return changes nothing, the same promise a text layer's row already makes.

A piece with nothing readable in it — an icon, a switch, a patch of flat panel —
keeps the name the command gave it, and is asked once and never again. While the
pass is still working, a find that matches nothing says "Still reading the
words" rather than "No layer says that", which would be a wrong answer given a
second early.

Walk: `Scripts/playtest/separated-rows-say-their-words-walk.json`. The walks that
test the separation itself pin this flag OFF, so they keep testing against names
that do not move; `find-a-layer-walk` does the same and photographs the old
behaviour for comparison.

## Which piece sits in which

A pile is not what the screen looked like. A label that sits in a button is part
of that button, and the whole point of taking a screenshot apart is to be able to
pick the button up and have its label come with it.

`PhotonzCore/LayerNesting.swift`, and the rule is one sentence: **a piece belongs
to the smallest thing that holds it.**

- **Holds** means nine tenths of the piece's own area is inside the candidate,
  not all of it. The cut is deliberately generous — a run of text is grown by a
  halo before it is taken — so a label that filled its button edge to edge comes
  back a pixel or two proud of it, and a rule that demanded every pixel would
  orphan it by arithmetic rather than by anything a person can see.
- **Smallest** settles the piece that could go in two places: a label inside a
  row inside a card goes in the row. Nine tenths is far enough from a half that a
  piece straddling the seam between two cards is refused by both, so a piece is
  in exactly one place or in none — never in two.
- A candidate has to be strictly bigger than the piece, so two readings of the
  same rectangle can never swallow each other and the tree can never loop.
- **A piece that belongs to nothing stays at the top.** The heading on a settings
  pane is nobody's child and is not pushed into a group that does not fit it.
- Nothing in it stops at two levels. Where the screen is three deep the tree is
  three deep, and the rule takes rectangles rather than pieces, so whatever a
  later slice finds nests the same way.

This is the same judgement the measure tool already makes from the other end.
`ElementBounds.captionHeightRatio` says words centred in a rung not much taller
than they are belong to that rung rather than being an element of their own,
which is how pointing at a button's label means the button. Both questions get
the same answer: the label is the button's.

### What it looks like in the list

A box that holds something becomes a group, because only a group holds layers.
The group keeps the box's name and the box's own body goes inside it, named for
what it is:

```
▾ Box 2        the whole button: one click on the canvas picks this
    Text 9     the words that were sitting on it
    Fill       the button itself, a real rounded rectangle
```

`Fill` for a box that came out as a real shape, `Picture` for one that came out
as pixels. The number stays on the group so the list never says Box 2 twice and
leaves you to work out which one is the button. When the later slice reads the
actual characters the group's name becomes the words, and nothing else here
changes.

Every group the command makes is left OPEN. It has just invented these layers
and the pill says how many came out, so a list that hides most of them behind a
twist reads as having lost them; one click closes any of them.

Nesting happens where groups exist — that is, when `next-layer-groups` is on,
which it is by default in Next. With it off the layers panel draws no twist at
all, so a group's children would be in the document and out of every reach a
person has, and the command hands back the flat pile instead.

### What is NOT nested yet

`BoxSweep` takes ONE level of boxes: the things sitting on the picture's own
background. A box can therefore never contain another box today, so the deepest
tree a real capture produces is a box holding its words. Card ▸ row ▸ label needs
the sweep to descend INSIDE an accepted box — its own fill becomes the local
background and what interrupts THAT becomes its children — and needs a child's
space patched out of its parent's pixels rather than the page's. That is its own
slice. The rule above already carries it the day the detector does.

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
  hierarchy slice took that seam: a piece now carries `children`, and a piece
  that has any becomes a group in the same single mutation. When the mutation
  happens and how undo sees it did not change, and the whole tree is still one
  press of Command Z.

## A box brings its shadow with it

`PhotonzCore/ShadowRead.swift`.

A card sits on a soft shadow, and a shadow is the one thing around a box that
neither agrees with itself nor ramps evenly. Before this, that alone stopped
every shadowed card in every screenshot from coming out: on the fixture both
cards were found and both were put back, because what surrounds them is darkest
against the card (223 out of 255 against a 242 page) and gone six pixels out,
and filling that space with any one colour would have left a grey halo of a card
that is no longer there.

Read as a shadow, it comes off WITH the card as a real shadow effect, the space
underneath is plain page again, and moving the card moves its shadow.

### The model

A drop shadow is the box's own silhouette, blurred by a gaussian, moved by an
offset, painted in one colour at one opacity. Along the middle of a straight
edge, well away from the corners, the blur of a half plane is exactly the
gaussian's own integral, so how dark the picture is `t` pixels out from that
edge is

    alpha(t) = opacity · Phi((o - t) / sigma)

where `o` is how far the shadow reaches past that edge: `-dx` on the left, `+dx`
on the right, `-dy` on the top, `+dy` on the bottom. Four unknowns — opacity,
sigma, dx, dy — fitted against ALL FOUR edges at once with the same opacity and
the same sigma, coarse then fine, with the opacity falling out in closed form
because the model is linear in it.

Fitting all four edges together is what makes the answer checkable rather than
plausible. A real shadow explains four edges with one set of numbers. Almost
nothing else does.

### In linear light, which is not a detail

The fit is done on the light the pixels stand for, not on the bytes they are
stored as, because that is where the renderer lays a shadow down. Read straight
off the bytes, the fixture's card shadow measures ten percent black; laid back
down by the renderer, ten percent darkens that page by half as much as the
screenshot did. The numbers looked reasonable in the inspector and the card came
out visibly flat. Every tolerance here is still written in levels out of 255,
which is the unit a screenshot is stored in and the unit an error is visible in,
and each reading carries its own conversion between the two.

### What is refused, and why that is most of it

A wrong shadow makes a separated card look broken in a way a missing one does
not, so the reading hands back nil on any of:

- **An edge that disagrees with itself.** A shadow is the same all the way along
  a straight edge. A reflection, a page that shades sideways and a neighbour's
  own shadow are not.
- **A page that never comes back.** Each edge is read outward until the picture
  starts getting DARKER again — a shadow only ever fades, so anything that
  darkens further out is the next thing along — and the page has to have
  returned by the end of what is left. This is also what lets two stacked cards
  each keep their own shadow instead of finding the neighbour's darkness in
  their own tail.
- **Four edges that disagree about the page colour.** A page shading dark to
  light fails here.
- **Anything under three levels at its darkest**, which is rounding noise.
- **A falloff that is not a gaussian's.** Every reading on every edge has to sit
  within one and a half levels of the one fitted shadow. A soft darkening that
  falls off in a straight line misses by seven.
- **A glow, or a coloured cast.** Only darkening straight towards black is read.
- **A box too near the frame**, or one whose repair would paint over something
  that is not page. A shadow's reach can be seventeen pixels and painting that
  over a control sitting eight pixels below the card would erase it.

Deliberately NOT read: **spread** (a silhouette grown or shrunk before blurring,
which this model cannot tell apart from an offset — real UI shadows almost never
carry one) and **a tinted shadow** (the colour comes back as black at some
opacity). Both come back nil and the box stays in the picture.

### The repair

The space painted over is the box grown by the shadow's REACH: the distance at
which the fitted shadow stops darkening the page by even a third of a level. On
the fixture that is seven pixels, and what is left behind is one flat colour,
byte for byte, with no trace of the shadow.

The box's own antialiased rim is unmixed against the page ALREADY DARKENED by
the shadow rather than against the bare page. Read against the bare page a
card's edge comes out too faint and dissolves into whatever it is dragged onto.

### What it measures on the fixture

Both cards: `#000000` at 22.6%, blur 2.05 px, offset (0, 2) — the same shadow
for both, which is what the page was drawn with. Rebuilt through the app's own
renderer and compared against the screenshot it came from, the shadow bands
differ by at most 2 levels out of 255 and 0.03 on average
(`SeparatedShadowRoundTripTests`). That round trip is the only check that can
say the numbers are right rather than plausible, and it is also what pins their
meaning: `radius` is a gaussian sigma in image pixels, and a positive `offset`
height throws the shadow down the page.

### What it does to the fixture's tree

The two cards are now the biggest things that come out, so the capture goes from
eleven pieces in nine top-level rows to thirteen pieces in five: the heading,
the two cards each holding their three row labels, and the two buttons each
holding theirs.
