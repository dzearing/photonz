# How the segmented thumb moves

## What this is

A segmented control is the row of two to four options where exactly one is
picked: View | Edit in the title bar, Left / Center / Right for text
alignment in the panel, and about forty more across the app. The picked one
sits on a **thumb**, a raised capsule under its word.

On 2026-09-29 you asked for the thumb to be lighter than its rail and to move
like Liquid Glass. Both are built. This card is only about the movement.

The component page shows it: http://127.0.0.1:8791/pages/comp-segmented.html
(section "Changing the value"). Click between Fill, Fit and Crop there.

## What it does now

When you pick another option, the glass:

1. stretches until it covers both the old option and the new one, squashed a
   little like a drop being pulled;
2. lets go of the old end;
3. runs at most 3 points past the new option (never outside the rail) and
   settles back.

The whole move takes 420 milliseconds. If you click again mid-move it carries
on from where it is. You can also press on the thumb and drag it; it lands on
the option under it when you let go.

The audit has a strip of frames 60 ms apart:
`queue/audits/2026-09-29-segmented-thumb-morph-frames.png`.

## The options

- **Keep it as it is.** Retires the follow-up; nothing changes.
- **Quicker, same shape.** The same stretch and settle in about 250 ms.
- **A plain glide.** No stretch: the glass slides across and eases to a stop,
  the way the system's own segmented control does.

With Reduce Motion on, all three become a quick fade, whichever you pick.
