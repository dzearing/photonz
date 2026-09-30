# Which segmented thumb should stay?

## What this is about

A segmented control is a row of side-by-side choices with one highlighted:
View | Edit in the title bar of a recording, and rows like Across (Left,
Center, Right) in the panel. The highlight is the **thumb**: a lighter pane that
sits under the picked choice and moves when you pick another. The component
page is `http://127.0.0.1:8791/index.html#comp-segmented`.

You asked whether the thumb is real Liquid Glass or faked, and to try it moved
by the Mac's own glass. Both versions are now in the app, and one switch in the
Experiments window flips between them: **Choices slide as system glass**. It is
on by default, so what you see today is the system version.

## The two versions, filmed

Both were filmed from the real window at 120 frames a second, in dark, moving
Edit to View in the title bar and Left to Right in the panel. Neither ever left
its rail or went past where it stops.

- Title bar, frame by frame: `../audits/2026-09-29-segmented-system-glass-title-bar-film-sc.png`
- Panel, frame by frame: `../audits/2026-09-29-segmented-system-glass-panel-film-sc.png`
- At rest, both themes: `../audits/2026-09-29-segmented-system-glass-at-rest-sc.png`

**System glass (A).** One plain pane of the Mac's Liquid Glass. The system
slides it straight to the new choice in about 0.3 seconds and it eases to a
stop. Nothing is painted on it. It looks calm and native, but softer: no edge
line, no lit top.

**Drawn glide (B).** A white plate with a hairline and a lit top edge, painted
over glass. Its front edge reaches the new choice first, so for a moment it
spans both, then the back edge catches up.

## How well you can see it

You asked for the thumb to be clearly lighter than its rail, at least 1.5 to 1.

| Where | System glass | Drawn glide |
| --- | --- | --- |
| Panel, light | 1.64 | 1.75 |
| Panel, dark | 1.55 to 1.61 | 1.99 to 2.15 |
| Title bar, dark | 1.58 | clearly lighter |
| Title bar, light | 1.45, or 1.14 after switching from dark to light | 1.61 |

The system glass picks its own shade from what is behind it, so the light
title bar, the palest place a thumb sits, is where it fades. Tinting it white
made it greyer, not lighter.

## One thing the system could not do

Liquid Glass has a second kind of move, where the glass leaves one choice and
grows out on the next, like a drop. Filmed four different ways, it never moved:
the glass was on View one frame and on Edit the next. So the system version is
the slide, not the drop.

## The options

- **A. System glass.** Keep what is on by default. To fix the light title bar,
  the rail there gets a little darker so the plain glass clears 1.5 to 1, with
  nothing painted over it.
- **B. Drawn glide.** Go back to the drawn thumb and its stretch. Clearest
  everywhere, but the look and the motion are ours.
- **C. System slide, drawn look.** The system slides the pane, but the pane
  wears the drawn white plate and edges again. Not built yet; small to do.

Whichever you pick, the other version and the switch are deleted.
