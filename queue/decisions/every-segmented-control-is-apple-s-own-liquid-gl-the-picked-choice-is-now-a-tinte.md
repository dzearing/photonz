# The tinted glass chip on every segmented control

## What this is

A segmented control is a row of side-by-side choices where you pick one: the
title bar's **View | Edit**, the history bar's **All | Screenshots | Videos**,
and about forty rows in the panel and the dialogs (text alignment, units,
formats). The component is documented at
[comp-segmented](http://127.0.0.1:8791/pages/comp-segmented.html).

On 2026-09-30 you sent back the Mac's own segmented control ("it's ugly and I
want to go back to our custom one") and asked for the picked choice to be a
**tinted Liquid Glass chip** that moves between choices as liquid glass, with
every word readable in every state.

## What was built

- **Our rail is back**: a solid grey capsule, lighter in Light mode and darker
  in Dark, the same in the title bar, the panel and the history bar.
- **The picked choice sits on a chip of Liquid Glass tinted with your accent**,
  its word in white.
- **When you pick another choice, the chip stretches across to it**: its front
  edge leaves first and its back edge follows, so for a moment it spans both
  choices, then it draws in and settles. About a third of a second. It never
  goes past the end of the rail (filmed at 120 frames a second in all three
  places).
- **A word the chip passes over turns white only where the chip covers it**,
  so there is never a grey word on the blue chip mid-move.

Pictures, all taken of the real app window:

- Title bar, View to Edit: `queue/audits/2026-09-30-tinted-segmented-film-title-bar-sc.png`
- A panel row, Left to Right: `queue/audits/2026-09-30-tinted-segmented-film-panel-sc.png`
- History bar, All to Screenshots: `queue/audits/2026-09-30-tinted-segmented-film-history-sc.png`
- Stills of each place, light and dark: `queue/audits/2026-09-30-tinted-segmented-*-light-sc.png` and `*-dark-sc.png`

## The one thing that differs from "tinted glass"

Tinted glass on its own could not carry a white word. Measured in the app in
Light mode, the glass veils whatever is under it toward white: the chip came out
pale blue, and a white word on it read **1.6:1** (regular glass) or **3.3:1**
(clearer glass), far below the 4.5:1 you asked for everywhere. So the accent is
laid over the glass: the glass shows at the chip's rim and a little through,
and a white word reads **5.4:1 in Light and 7.2:1 in Dark** on the real window.
The chip is also a slightly deeper shade of your accent, because white on the
Mac's own blue is only 4.0:1.

## The options

- **Yes, keep it.** What you see in the pictures.
- **More glass, dark word.** A mostly clear chip with a light tint, and the
  picked word dark instead of white. More glass, but not white on the accent.
- **Keep it, slower stretch.** The same look, travelling in about half a second
  so the stretch is easier to see.
