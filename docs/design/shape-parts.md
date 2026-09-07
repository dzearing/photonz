# A layer is made of parts

One model for every switchable thing a layer paints: fill, outline, shadow, and
anything added later such as an inner shadow or a glow. Written down before any
of it was built, because it changes the shape of every inspector and a model
half-applied is worse than the mess it replaced.

Status: **built in Next**, behind `next-shape-parts` (on by default there).
The layout was the user's call and they took it on 2026-09-06: *one list,
settings unfold*. Later the same day they asked for the fold to go: a part that
is switched on shows its settings straight away. On 2026-09-07 they split the
one list in two: **Appearance is what it IS, Effects is what you ADD**. Read
"Appearance and Effects" below first; it supersedes anything above it that says
the shadow is a row in Appearance. Current is untouched.

## Why

Reproduced on the probe on 2026-09-06, one rectangle picked, Next release:

| Section | Rows |
| --- | --- |
| Color | Fill (checkbox, swatch, saved-colors menu) · Outline (swatch, menu, **no checkbox**) |
| Effects | Opacity · Blur · Corner Radius |
| Rectangle | Thickness |
| Shadow | Enable Shadow (switch) |

Three faults, each verified rather than assumed:

1. **The outline cannot be removed.** There is no switch on the Outline row, and
   `AnnotationStyles.strokeWidthRange` is `1...40`, so the thinnest a rectangle
   can be is a one point ring. A person who wants a plain filled box has no move
   to make. This is the thing the user hit.
2. **One part is spread over three sections.** The outline's colour is in Color,
   its thickness is in Rectangle, and the corner it turns is in Effects.
3. **Three different idioms for "is this on?"** — a checkbox in a shared section
   (Fill), nothing at all (Outline), and a switch inside a section of its own
   (Shadow). Learning one teaches you nothing about the next.

The user's original report also said a rectangle carries a *Border* under
Effects as well as a *Thickness*, which was true when they hit it but is no
longer: "One width for the line round a shape" (2026-09-03,
`Sources/PhotonzCore/OutlineWidth.swift`) took the Border row away from any
layer that draws its own outline. The two-edges confusion is therefore already
resolved for shapes; a picture, a frame, a label or a group still has a Border,
and this document renames it so that the word matches what the shape has.

## The model

> **A part is something a layer paints that can be absent.**
> It has one switch, one colour, and settings that only exist while it is on.
>
> **A property is something the layer always has.**
> It has no switch: position, size, opacity, blur, corner radius, an arrow's
> head size.

That single test is the whole model, and it is what makes the panel teachable:
learn to add an outline and you already know how to add a glow, because a glow
will arrive as one more row with a switch, a colour and its own settings.

### The parts a layer has

| Layer | Parts |
| --- | --- |
| Rectangle, ellipse | Fill · Outline · Shadow |
| Line, arrow | Colour (no switch: the line IS the shape) · Shadow |
| Highlight, text | Colour (no switch) · Outline · Shadow |
| Picture, frame, group, callout | Fill (a frame's surface) · Outline · Shadow |
| Later | Inner shadow · Glow, on any of them |

A shape that is all one colour keeps the single row it has today, labelled
Colour, because calling a line's one colour an outline is a small lie
(`ShapeSettingsNaming.swift` already draws this distinction and it stands).

### What each part holds

| Part | Switch | Colour | Its own settings |
| --- | --- | --- | --- |
| Fill | on/off | the fill colour | none yet (a gradient is a kind of colour, not a setting) |
| Outline | on/off | the outline colour | Thickness |
| Shadow | on/off | the shadow colour | Blur, Size, Distance, Direction, Opacity |

**Off means off, everywhere.** A part that is switched off shows its switch and
its name and nothing else: no colour, no settings. Switching it back on brings
back the colour and settings it had, so switching off is never destructive and
never loses what you had set.

**Every switch means the same thing underneath.** A colour that can be absent is
stored as an absent colour (`setAnnotationFill(nil)`); an outline that is off is
a width of zero, which is a real document state that saves, reopens, undoes and
copies like any other, and which the rasterizer has always drawn as no line at
all. Nothing about how an existing document draws changes: a rectangle with a
4pt outline today has its Outline part on at 4pt.

The one thing "off" does NOT keep is the width it took away: that is remembered
by the window rather than the document, so switching straight back on restores
it, and reopening the file tomorrow brings the outline back at the width a fresh
one wears. Undo restores it exactly, either way.

### The tool learns from the switch

**Switching a part off is remembered for the next shape you draw**, the same way
picking a colour, pulling Width or pulling Corner Radius already is. Take a
box's outline off and the next box comes out with no outline; put it back and
the next box has one, at the width you left it. The user reported the missing
half of this on 2026-09-06: the Fill switch taught the tool and the Outline
switch did not, so the outline came straight back on the next box.

The memory is per kind of shape, so taking a rectangle's outline off leaves the
ellipse and the arrow alone, and it lives with the other tool defaults, so it
survives quitting the app.

Over several layers picked at once, the switch teaches only what they agree on
(`PhotonzCore/ToolArming.swift`). Whether the part is there is never in doubt,
because the press just set it. Its thickness can be: switch two boxes of 2pt
and 10pt off and back on and they come back different, so the tool learns that
boxes have an outline and keeps the thickness it already had rather than being
handed one of theirs.

A ring round a picture, a label or a highlight is styling laid over the layer
rather than part of the shape, so it is remembered with the rest of that layer's
look, the way pulling its width under Effects already is.

### What is NOT a part

- **Opacity and Blur** are laid over the whole finished layer, whatever parts it
  has. They stay under Effects.
- **Corner Radius** rounds the fill and the outline together, and a rectangle
  with no outline at all still has rounded corners. So it is a property of the
  shape, not a setting of the outline, and it belongs with the shape's other
  properties rather than inside a part.
- **An arrow's head size** is the shape of the arrow, not a part of it.

The original complaint asked for the outline's colour, thickness and corner
radius to sit in one place. This model puts colour and thickness in one place
and leaves radius out, for the reason above: it is not the outline's. It stays
where every layer can reach it, under Effects, beside the other two things that
are laid over whatever the layer is made of.

### Naming

- Nothing that sets the width of a line is called **Thickness** any more. Inside
  the Outline part the row is **Width**, and its meaning comes from the part it
  sits in.
- **Border** stops being the name of the line a layer HAS. A picture's ring and
  a rectangle's ring are both the **Outline** part. They still differ underneath
  (a shape strokes its own path, a picture gets a ring drawn round its box) but
  nothing a person does differs, so nothing on screen should. The word came back
  on 2026-09-07 for the EXTRA rings you add in Effects, which is a different
  thing: see "Outline in Appearance, Border in Effects".
- A section named after the content kind (**Annotation**) is already gone; a
  section named after nothing in particular (**Effects**) keeps its name, since
  what is left in it really is laid over the top.

### Several layers picked

The parts list speaks for the whole selection, exactly as the Color section does
today, and for the same reason: a control that jumps to a different section when
you shift-click a second layer is a control you have to find again. A part
appears if **any** picked layer has one, its switch reads on only when every
picked layer that can have it does, and a row that reaches fewer layers than are
picked says so underneath, the way Fill already does.

This is why the parts do not become sections named after the shape: the heading
has to hold still when the selection changes.

## The panel

One section, headed **Appearance**, in the slot the Color section used to hold.
Inside it one row per part: the part's name, a tick, and the colour it paints.
A part that is switched ON also shows its own settings on the lines directly
below its row, at the same left edge as the row, and every switched on part
shows them at once. Ticking a part is already the person saying they want it, so
there is nothing more to press: no chevron, no remembering which part is open,
no indent.

It shipped on 2026-09-06 with the settings folded behind a chevron and one part
open at a time, which kept the section a fixed height; the user asked for the
fold to go the same day. The section is therefore as tall as what is switched on
(a shadow adds five rows), and the dock scrolls. Parts are told apart from their
settings by the tick column, which only a part row has, and by the gap: a part
sits 16 pt from the one above it and its settings sit 6 pt under its own row.
Anything a row says below itself, including the sentence about how many of the
picked layers it reaches, shares that one left edge.

A rectangle's whole panel goes from four sections to three:

| Before | After |
| --- | --- |
| Color: Fill (tick) · Outline (no tick) | Appearance: Fill · Outline · Shadow |
| Effects: Opacity · Blur · Corner Radius | Effects: Opacity · Blur · Corner Radius |
| Rectangle: Thickness | *(gone: Thickness is the Outline part's Width)* |
| Shadow: Enable Shadow · five sliders | *(gone: the Shadow row)* |

Two things did not go where the original report asked, and both are deliberate:

- **Corner Radius stays under Effects.** It is a property, not a setting of the
  outline (a box with no outline still has rounded corners), and it is ONE row
  that also rounds a screenshot, a frame and a group. Moving it into the shape's
  own section would leave every layer that is not a shape with nowhere to round
  its corners, or bring back the second Corner Radius slider that
  `CornerRadiusRow` exists to have ended.
- **A shape and a picture picked together show ONE Outline row** (settled
  2026-09-07). They used to show two, one for each kind of ring, because the
  colour underneath is stored in two different slots. A row now carries the
  colours it paints AND which of the picked layers takes each one
  (`PartColor`), so one switch, one well and one Width reach both: the shape
  gets its stroke, the picture gets its ring, in one step one undo puts back.
  A highlight keeps its own Colour row for its wash, because that stroke colour
  is the wash the highlight is made of rather than a line round anything.
- **The Outline row sits above Text, always.** It used to sit below whenever it
  was the ring kind, so picking a box beside a caption reordered the panel. One
  fixed place, so adding to the selection widens what a row answers for and
  never moves it.

### Where the code is

- `PhotonzCore/LayerParts.swift` — the model: what a part is, which parts a
  selection has, and switching the outline on and off. Tested in
  `Tests/PhotonzCoreTests/LayerPartsTests.swift`.
- `Photonz/PartsInspector.swift` — the list, the rows and their settings.
- The old `SelectionColorInspector` and `ShadowInspector` are still what Current
  draws, unchanged.

## How the list grows

Status: **built in Next** (2026-09-07), from the user's answer *one list you add
to*. Shadows are countable, an inner shadow is a Kind rather than an effect of
its own, and the plus that adds one rides the Appearance header. The
Outline's Position was filed rather than built that day and **landed on
2026-09-07**; see "Where the outline sits" below, which supersedes the reason
given in "What existing documents must keep drawing". Three parts fit in a fixed
list. The ones people ask for next do not: an inner and an outer border, an
inner and an outer shadow, a glow, a bevel. Adding six more fixed rows is how a
panel turns into a wall. This section writes down how the list scales instead,
so that the next effect costs one entry and no new idea.

### The two ideas the whole thing turns on

**One. Inner and outer are a SETTING, not a different effect.** A border that
sits inside the edge and one that sits outside it are the same idea drawn in a
different place, so they are one part with a Position, exactly as a stroke is in
Figma and Sketch. A shadow thrown behind and one cast into the shape are one
part with a Kind. Four names people ask for collapse to two rows and two
popups, and the list stays short.

**Two. Some effects are COUNTABLE.** A second shadow is the common want: one
tight and dark for contact, one wide and soft for lift. A fixed row cannot hold
two. So the list has to accept more than one of a kind, which turns a fixed set
of rows into a list you add to and remove from. Once it is a list, the order is
visible, and anything visible has to be editable, so rows drag the way layers
do.

A bevel or an inner glow then costs one new kind and no new interaction.

### What a kind is

Every entry in Appearance is one **kind**, and a kind is described by four
things and nothing else:

| | |
| --- | --- |
| **Name** | What the row is called, and the word the add menu offers |
| **Count** | `one` — the layer has it or does not — or `many` |
| **Colour** | The one colour it paints, or none |
| **Settings** | The rows that appear under it while it is on |

That is the extension point. A kind is added by writing those four things down;
nothing about the panel, the switch, the add menu, the remove, the drag or the
document format changes to accept it.

### The kinds

| Kind | Count | Colour | Settings |
| --- | --- | --- | --- |
| Fill | one | the fill colour | none (a gradient is a kind of colour, not a setting) |
| Outline | one for now | the outline colour | Width · Position (Inside · Center · Outside) |
| Shadow | **many** | the shadow colour | **Kind** (Drop · Inner) · Blur · Size · Distance · Direction · Opacity |
| *Glow (next)* | many | the glow colour | Kind (Outer · Inner) · Blur · Size · Opacity |
| *Bevel (next)* | one | two colours, light and dark | Depth · Softness · Direction · Opacity |

Fill and Outline are `one` because nobody has asked for two and the row is the
same either way if they do: promoting a kind from `one` to `many` is a one word
change, not a redesign. Shadow is `many` on day one because that is the ask.

**A shadow's Kind and a border's Position are popups on the row, but the add
menu still names them in full.** The menu offers *Shadow* and *Inner shadow* as
two entries, because that is what a person is looking for and scanning a popup
they have not opened yet is not looking. Picking either adds one Shadow row with
its Kind already set. One row type, two doors into it.

### What order means

The list paints **bottom of the list first**, the same way the layer list does,
so the entry at the top of Appearance is the one nearest the eye. Drag a row and
the picture changes.

Where it is visible:

- Two drop shadows of different colours, where they overlap.
- An inner shadow above or below the fill: below, the fill covers it.
- An outline above or below an inner shadow, which decides whether the shadow
  darkens the line.

Where it is not: a single shadow and a single fill can only go one way round
that makes sense, which is why order has been invisible until now and why it
only becomes editable when a layer can hold two of something.

Today's fixed order — shadow behind, fill, then outline over the top
(`DocumentRenderer`) — is what a freshly converted layer gets, so a document
opened tomorrow paints exactly as it painted yesterday.

### Off is not remove

A row carries both, and they mean different things:

- **The tick** switches the effect off and keeps everything about it. This is
  the one that is used constantly: compare with and without.
- **The remove** takes the entry out of the list. Only entries of a `many` kind
  have one, because taking away the Fill row would leave a shape with no way to
  get its fill back except the add menu, and every rectangle would start life
  needing one.

Two ways to make something go away is the real hazard in this model. The answer
is that only countable things can be removed, so on a plain rectangle there is
exactly one gesture, the tick, and remove appears only once you have added a
second of something.

### What existing documents must keep drawing, and why Position is not built

Two facts, read out of the renderer rather than assumed. The second corrects
what this document said on 2026-09-07 before the code was read closely:

- **A picture, frame, label or group's ring is already an INSIDE border.**
  `bordered(_:box:radius:style:)` insets the box by the full width and cuts the
  middle out, so the ring sits wholly within the layer's edge.
- **A shape's own stroke is already inside its frame too.**
  `AnnotationRasterizer` insets the box by half the stroke width and then
  strokes it, so the stroke straddles that inset path and its OUTER edge lands
  exactly on the frame. Centred on the path, inside the frame.

So Inside is not one default among three: it is the only position anything in
the app has ever drawn, and it is what every existing document is wearing.

Outside is the one people ask for, and it is what made Position a piece of work
of its own rather than a popup: a shape is rasterized into a bitmap exactly the
size of its frame, and the ring round everything else was cropped to the layer's
own extent, so an outline past the edge had nowhere to be drawn. It was filed
rather than half-built on 2026-09-07 and built the same day. See the next
section.

## Where the outline sits

Status: **built in Next** (2026-09-07). One popup, **Position**, on the line
under the Outline part's Width: **Inside · Center · Outside**.

It is offered wherever the choice means something — a rectangle, an ellipse, a
picture, a frame, a group, a callout — and is simply absent where it does not. A
line and an arrow ARE their stroke, so there is no edge for it to sit one side
of, and a letter's outline follows the letters rather than the box; those show a
Width and stop there.

### What each one draws

| | Where the line goes | What happens to the layer |
| --- | --- | --- |
| **Inside** | wholly within the edge | the line eats into the shape; the box keeps its size |
| **Center** | straddling the edge | half in, half out |
| **Outside** | wholly past the edge | the shape keeps its size and the line grows it |

**Inside is where every line the app has ever drawn sits**, so it is what every
existing document opens on and nothing already saved moves a pixel. A style that
has never moved its ring does not even write the key.

Picking one is remembered per kind of shape, the way the Width and the corner
already are: take a box's line outside once and the next box comes out that way,
and the ellipse and the arrow are left alone.

### The one number the whole thing turns on

`BorderPosition.outset(width:)` — 0 inside, half a width centred, a whole width
outside. Everything else follows from it:

- **A shape's own stroke.** `AnnotationRasterizer` grows its bitmap by the
  outset on every side and shifts its drawing in by the same, so the shape goes
  on stating itself in its own box. The pad is symmetric, which is what lets
  `DocumentRenderer` keep centring the picture on the frame — but the scale
  step had to be told too, or the padded bitmap is squashed straight back into
  the frame and the outside line lands inside again.
- **The ring round everything else.** `bordered` pushes its pair of rounded
  rects out by the outset and crops to what they cover rather than back to the
  layer's box, so an outside ring makes the picture bigger. A container's ring
  is laid on AFTER its clip, so a screen that hides what sticks out of it still
  wears its own ring outside itself.
- **How far a layer reaches.** `LayerStyle.previewPadding` carries the ring's
  outset and `Layer.reachPadding` adds the shape's own; `renderBounds`, drag
  sprites, merge-down, rasterize and the dirty rect all read one of those two,
  so nothing inside a group or a frame cuts an outside line off.

### What it deliberately does NOT touch

**The layer's frame.** Selection, hit testing, snapping, the handles and the
size readout all read the frame, and the frame is the shape rather than the line
round it, so clicking goes on following what you can see yourself dragging.
That is also the point of Outside for UI work: a button specified at 120×32 with
a 2pt outside line is still 120×32.

### More than one layer picked

The list still speaks for the whole selection, and one rule extends it: **rows
line up by position in the list, not by kind.** Two boxes that each have one
shadow show one Shadow row whose settings read Mixed where they differ. A box
with two shadows picked beside a box with one shows the first shadow as a normal
row and the second saying it reaches one of the two layers, the same sentence
Fill already says. Adding an effect adds it to every picked layer, so the lists
stay the same length as each other from then on.

### Where the code is

- `PhotonzCore/LayerParts.swift` — `LayerPart.isCountable`, `AppearanceKind`
  (what the plus offers), the shadow rows, and the four list edits: add,
  remove, move, switch. Tested in `Tests/PhotonzCoreTests/AppearanceListTests.swift`.
- `PhotonzCore/Layer.swift` — `LayerStyle.shadows` is the list, nearest the eye
  first; `shadow` still reads and writes the first one, so every caller written
  before this goes on working. `ShadowStyle` gains `kind` and `isOn`. A file
  with one shadow saves exactly the bytes it always did, and one with two writes
  the first where it has always been written so an older build still draws it.
- `PhotonzRender/DocumentRenderer.swift` — `shadowed(_:shadows:)` walks the
  list: inner shadows are cast into the layer and clipped to its silhouette,
  drop shadows go behind it nearest the eye first. Tested in
  `Tests/PhotonzRenderTests/ShadowListRenderTests.swift`.
- `Photonz/PartsInspector.swift` — the plus (on the section header, since the
  dock caps a section's height and scrolls the rest inside it), the Kind popup,
  the cross, the grip, and the row menu that does the same three things in
  words.

### What is rough, as built

- **Two shadows do not fit.** A shadow costs seven rows, so the second one's
  own row is already below the fold of the Appearance section and has to be
  scrolled to. This is the density the decision's option B was about; the user
  chose A, and the cost is now real rather than predicted.
- **A part's settings have no visible owner.** Blur, Size and Opacity under a
  Shadow row read like a second copy of the layer's own Blur and Opacity in
  Effects underneath. Reported by the user on 2026-09-07 from this very build.
- **The grip's drag is not scripted.** A synthesized press cannot start a
  SwiftUI drag, so the walk cannot carry out the reorder; the row's own menu
  (Move Up, Move Down, Remove) does the same thing and what both call is
  covered by tests.


## Appearance and Effects

Status: **built in Next** (2026-09-07), from the user's answer *Appearance is
what it IS, Effects is what you ADD*. It replaces "How the list grows" above
wherever the two disagree: everything that section says about a list you add to
is still true, but the list is **Effects**, not Appearance.

### Why

The user picked a rectangle and saw an Appearance panel and an Effects panel and
could not say what belonged in which. Both appeared to carry an opacity and a
blur. Reproduced: Appearance held Fill, Outline and a Shadow, and the shadow's
own Blur, Size, Distance, Direction and Opacity were drawn flat underneath its
row; Effects held the layer's Opacity, Blur and Corner Radius. Nothing on screen
said which of the two Blurs belonged to what, so a shadow's blur read as a
second top level blur.

Two faults, not one:

1. **There was no rule.** A shadow is in Appearance and a blur is in Effects,
   and no sentence explains why.
2. **A part's settings had no visible owner.** Even with the rule fixed, a
   shadow's Blur drawn in the same column as everything else reads as the
   layer's.

### The rule

> **Appearance is what a shape simply HAS.** Opacity, its fill, its outline, and
> a corner radius only where there are corners. Always there, always in that
> order, never added and never removed.
>
> **Effects is a list you ADD to.** It starts empty. A shadow, a shadow cast
> into the layer, a blur — and later a glow, a bevel, a filter — arrive from one
> plus, can arrive more than once where that means something, and can be taken
> out again.

One sentence tells you which panel a thing is in. The order inside Appearance is
fixed and short, so the hunt is always the same four rows; anything else you set,
you added, and added things are in Effects.

### What moved

| Was | Is |
| --- | --- |
| Effects: Opacity | **Appearance**, first row. It is the one thing every layer has. |
| Effects: Corner Radius | **Appearance**, last row, and only where there are corners. |
| Effects: Blur | **Effects**, but as an entry you ADD rather than a slider that is always there. |
| Appearance: Shadow rows | **Effects**, where the plus puts them. |
| Effects: Border width | Already gone: it is the Outline part's Width, in Appearance. |

**A corner radius only where there are corners.** An ellipse, a line and an
arrow have none, so they show no row rather than a slider that does nothing to
what you have picked (`Layer.hasCorners`). Everything that is not a shape at all
— a picture, a label, a frame, a group — is a box, so it has four. Over a mixed
selection the row is there for the layers that have corners and says how many of
the picked layers it reaches, the sentence Fill already uses.

**The outline stays in Appearance**, for both kinds of ring. A shape's stroke
and a picture's ring are one Outline part with one Width (see above), and both
are what the layer IS rather than something added. The *offset* border the user
asked about — an inner one and an outer one as two rows — is an Effects entry,
and it was built on 2026-09-07 once the renderer could draw outside a layer's
edge at all. See "Outline in Appearance, Border in Effects" below.

### A part's settings are visibly owned

Everything a row says below itself — its Kind, its Blur, its Size, its Width —
sits behind a rule of its own, stepped in from the row that owns it
(`OwnedSettings`). A shadow's Blur is now plainly the shadow's.

This reverses the user's "no indent under a part" ask of 2026-09-06, and it is
theirs: it was inside the option they chose on 2026-09-07. The indent is back
because it is now carrying a meaning it did not carry then.

### The panel, top to bottom

```
Layers
Appearance     Opacity · Fill · Outline (Width) · Corner Radius
Effects        (empty)  + plus on the header
```

**Appearance sits directly under Layers and Effects directly under it**, asked
for by the user on 2026-09-07. That is above the sections named after the thing
you picked, which went up there on 2026-09-06 ("Put what you picked first"), so
those shift down by the height of these two. The trade the user made: Appearance
and Effects are the two sections touched on every single layer, so they are the
two that must never need scrolling to.

A rectangle nobody has touched shows an Effects section with one line in it —
"Nothing added yet. Use the plus above for a shadow or a blur." — and the plus on
its header. An empty section with nothing in it at all reads as broken, and the
plus is small enough to be missed the first time.

### The model

`LayerStyle.effects` is ONE ordered list of `LayerEffect`, top nearest the eye.
`blurRadius` and `shadows` are **views over it**, so the renderer and every
caller written before the list existed go on working untouched — which is what
makes "everything already drawn keeps drawing exactly as it does" true by
construction rather than by inspection.

| Kind | Count | Colour | Its own settings |
| --- | --- | --- | --- |
| Shadow | **many** | the shadow colour | Kind (Drop · Inner) · Blur · Size · Distance · Direction · Opacity |
| Border | **many** | the border colour | Position (Inside · Center · Outside) · Width |
| Blur | one, pinned | none | Amount |
| *Glow (next)* | many | the glow colour | Kind (Outer · Inner) · Blur · Size · Opacity |

**Adding a new kind is a new case in `LayerEffect` plus the settings it
carries.** Nothing about the plus, the tick, the cross, the grip, the reach
sentence over a multiple selection or the saved file changes to accept it.
Border was the first one added that way, on 2026-09-07, and it needed nothing
else. **Glow** is next: a shadow with no offset and a colour that lights rather
than darkens, one new case and one row of settings.

### The plus offers one item per KIND

Settled on 2026-09-07 from the user's report. The menu used to say Shadow, Inner
Shadow, Blur: two entries for one effect, which read as if inner and outer were
unrelated ideas rather than one switch. It says **Shadow, Border, Blur** now, and
what makes a shadow inner is the Kind on the row it becomes, exactly as what
makes a border inner is that border's Position. Nothing about an existing
document changes: the Kind has always been a field on the shadow, so a file
saved with an inner shadow opens with an inner shadow and its popup already set.

### Outline in Appearance, Border in Effects

They are two different things and the panel says which is which by where it puts
them, using the rule the user chose:

- **Outline** is the ONE line the layer HAS. A shape strokes its own path, a
  picture or a frame takes a ring round its box, and every layer has exactly one
  whether or not it is switched on. It is in Appearance, with the layer's
  opacity and its fill.
- **A Border is an EXTRA ring you ADDED.** There can be none, one, or several,
  each with its own colour, width and side of the edge, and each can be taken
  out again. They are in Effects, where the plus put them.

So the question "how thick is this shape's edge" has one answer and one control,
and "put a second ring round this" has somewhere to go. A border sits over the
outline, and the shadows are cast from the layer wearing both.

**Position, not a distance.** A border carries the same Inside · Center ·
Outside popup the Outline row carries, and no number for how far off the edge to
float. Two outside borders of different widths already stack into a real
two-colour double ring, so nothing needs a distance to be worth adding twice.

**Order is real within a kind.** Borders paint over the layer's own edge in list
order, top of the list nearest the eye, and the shadows are then cast from the
result. Which side of a shadow a border sits on in the list changes nothing,
which is the rule the shadows already follow: an inner shadow is applied before
a drop shadow wherever the list holds it.

**Blur is pinned to the top and carries no grip.** The order of the list is the
order things paint, and a blur is laid over the whole layer while shadows are
thrown behind it, so there is nowhere else for a blur to be that would look any
different. A grip that changes nothing is a grip that lies, so it does not have
one, and a shadow cannot be dropped above it. Order among shadows is real and is
what the drag is for.

**Off is not remove**, unchanged: the tick keeps every number on the effect and
stops it drawing, the cross takes the entry out. Everything in Effects was added,
so everything in it carries a cross — which is simpler than the old rule, where
only countable parts did, because nothing in this panel is simply there.

### What existing documents keep drawing

Nothing about the renderer changed. A file written before this opens as the list
its old fields add up to: a blur first if it had one, then its shadows in the
order they were already in, which is exactly the stack `DocumentRenderer` has
always painted. A file saved after it still writes `blurRadius`, `shadow` and
`shadows` where they have always been written, so an older build opens it and
draws the same picture; the `effects` list goes in beside them and older builds
ignore it.

A blur switched OFF saves as `blurRadius: 0`, so an older build agrees with what
is on screen, while this build keeps the number the row was left at.

### Where the code is

- `PhotonzCore/LayerEffects.swift` — `EffectKind`, `LayerEffect`, `BlurEffect`,
  `AddableEffect` (what the plus offers), `LayerEffectRow`, and the four list
  edits: add, remove, move, switch. Tested in
  `Tests/PhotonzCoreTests/EffectsListTests.swift`.
- `PhotonzCore/Layer.swift` — `LayerStyle.effects` is the list; `blurRadius` and
  `shadows` read and write it; Codable migrates and writes both shapes.
- `PhotonzCore/CornerRadiusSelection.swift` — `Layer.hasCorners` and the
  `cornersOnly` selection Appearance uses.
- `Photonz/PartsInspector.swift` — Appearance: opacity, the part rows, corner
  radius, and `OwnedSettings`, the rule that says whose settings these are.
- `PhotonzCore/LayerEffects.swift` — `BorderEffect` and the border's own list
  edits, tested in `Tests/PhotonzCoreTests/BorderEffectTests.swift`; the pixels
  in `Tests/PhotonzRenderTests/BorderEffectRenderTests.swift`.
- `PhotonzRender/DocumentRenderer.swift` — `ringed` draws one ring and both the
  Outline and every added Border go through it.
- `Photonz/EffectsListInspector.swift` — Effects: the rows, the plus, the tick,
  the cross, the grip, the empty line, and the Border's Position and Width.

### What is rough, as built

- **The grip's drag is still not scriptable.** A synthesized press cannot start a
  SwiftUI drag, so a walk reorders through the row's own menu (Move Up, Move
  Down, Remove), which calls exactly what the grip calls.
