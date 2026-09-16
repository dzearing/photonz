# Appearance and Effects will not both fit a laptop window

## What this is about

The right hand panel in the editor is a stack of sections: the layers list at
the top, then the section named after whatever you just clicked, then
**Appearance** (opacity, fill, outline, corner radius, and the parts a thing is
made of), then **Effects** (the list you add shadows and blurs to), then
whatever else applies.

On 2026-09-07 you said Appearance and Effects are the two sections nobody
should ever have to scroll to. They are the two you touch on every single
layer, so they are the two that should always be whole on screen.

They are not. This card is about how to make them.

## What was measured, and how

Every scripted run of the app records where each section sat in the panel. On
2026-09-16 there were **3,334 of those recordings, from 185 different runs**.
Reading them all back:

| Panel height | How often Appearance or Effects was below the fold |
| --- | --- |
| 621 points (a 1200 by 720 window) | **44%** |
| 781 points | **50%** |
| 969 points (the biggest window this display can open) | **12%** |

At 1200 by 720 the panel has **609 points to share**. Four real examples of
what it was asked for:

| With this picked | Layers | The pick | Appearance | Effects | Asked for | Over by |
| --- | --- | --- | --- | --- | --- | --- |
| a piece of text | 163 | 198 | 231 | 68 | 747 | **126** |
| an arrow | 163 | — | **447** | 68 | 765 | **144** |
| a component copy | 163 | 311 | 195 | 68 | 1102 | **481** |
| a measurement | 163 | 109 | **489** | 68 | 702 | **81** |

It is never close. And the tallest Appearance recorded all day is **669
points**, which is more than the entire 621 point panel.

## Why it has not been fixed already

It has been attacked seven times, and every one of those attempts was an
ordering change: move Position and Size above Appearance, move the picked
thing above both, move Appearance up under the layers list. **Ordering only
decides which section is the one left below the fold.** The total never moved,
so each fix pushed the problem onto whichever section came last.

The measurement above says why, and it is something none of those seven
attempts knew: **Appearance is not a small form, it is the biggest thing in the
panel.** It lists the parts a thing is made of, and every switched-on part
unfolds all of its settings at once. An arrow's line, head and caption are all
open together, and that comes to 447 points. A measurement's parts come to 489.

So there are only three honest ways out, and one way of saying no.

## What you would see under each answer

### a. Guarantee the fold (recommended)

The panel decides, before it draws, that Appearance and Effects must both fit.
If everything above them plus Appearance's full height will not fit, Appearance
gets a small scrollbar inside its own section and everything stays on screen.

You would see: Appearance and Effects always both there, on every layer, in
every window. On an arrow or a measurement, Appearance itself scrolls a little.

This is already what the panel does to the layers list, to Effects, to
Measurements and to the Library shelf. Appearance is the only one of the
promised sections exempt from it. Making it obey is the one answer that cannot
quietly fail later, because the next section anybody adds has to satisfy the
same arithmetic before it is allowed to draw.

### b. One part at a time

Appearance's parts fold, the way the rows of the Effects list under it already
do. The part you are working on is open; the rest are one row each.

You would see: Appearance drop from 447 points to roughly 300 on an arrow.
One click to open a part. The part you last opened stays open.

This is the answer that makes Appearance stop being enormous rather than
finding room for something enormous, and it answers the original complaint
("the panes are completely cluttered and hard to read") in its own words. But
it only fixes the tallest two cases. With a piece of text picked the panel is
still over by 15 points, and with a component copy by 93.

### c. Layers gets its own side

The layers list leaves the right hand panel and becomes a dock on the left,
where Figma and Sketch put it. The right panel is properties only and gets the
full height of the window.

You would see: the biggest rearrangement of the three. The properties panel
gains 163 points outright, which fixes text, arrows and component copies. The
layers list stops being cut to three rows. The canvas loses some width, unless
you collapse the left dock to a rail.

It still does not fit a measurement, whose Appearance alone is 489 points, so
it would want (a) or (b) alongside it eventually.

### d. Leave it, you scroll

Drop the promise, change nothing. Worth saying out loud as an option, because
the alternative to choosing is the panel being re-ordered again in a week by
whoever gets the next complaint.

## What happens after you choose

Whichever way this goes, the measurement above is now written into
`Sources/Photonz/InspectorDockLayout.swift`, next to the two rules that already
govern the panel's order and its cast, as a third rule about height: a section
may not be added, and an existing one may not grow, without saying which line
of that table it spends from. That part is done regardless of the answer, so
this does not get walked back again by the next feature that wants room.
