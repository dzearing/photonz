# Does the direction of a pinch pick what the timeline zooms?

## What this is

The timeline under a recording (Photonz Dev, release Next, open any recording
in Edit) can be pinched on a trackpad. Until now a pinch always zoomed two
things together: the time scale (how many seconds fit across) and the row
height (how tall each track is).

You asked on 2026-09-28 for the direction of the pinch to choose:

- **Side to side** (fingers spreading or squeezing horizontally): time only.
- **Up and down**: row height only.
- **On the slant** (about 35 to 55 degrees): both, as before.
- **Option** held: time only. **Shift** held: rows only. Unchanged.

The direction is picked in the first couple of millimetres of finger travel
and then held until you lift your fingers, so a pinch never flips half way.

## Why we are asking

The loop's walks drive the choice with made-up fingers and it works every
time. What a script cannot do is put two real fingers on your trackpad, so
whether the Mac hands the timeline your touches, and whether the choice
feels natural, needs you.

## How to try it

1. Open a recording, pointer over the tracks.
2. Spread two fingers side to side: the seconds on the ruler spread out, the
   rows stay the same height.
3. Spread two fingers straight up and down: the rows grow, the ruler does not
   change.
4. Pinch on a slant: both change.

## The options

- **Feels right**: nothing more to do.
- **Direction makes no difference**: every pinch still does both. That means
  the touches are not reaching the timeline and the loop needs to read them
  another way.
- **Works but needs tuning**: say in a comment whether it lands on "both" too
  often, or decides too early or too late.
