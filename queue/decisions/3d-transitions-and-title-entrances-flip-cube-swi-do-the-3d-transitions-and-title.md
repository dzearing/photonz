# Do the 3D transitions and title entrances look right?

## What this is

You asked for 3D moves that make a video feel produced, built on the 2.5D
model (flat layers turning about X and Y and moving in depth under one camera,
the way Keynote and Apple Motion do it). They are built and on in Next by
default. This card asks you to judge how they look, from a reel.

## Where to look

- **Contact sheet:** `queue/audits/2026-10-11-depth-reel-contact.png`. One row
  per move, five moments of it: start, a quarter, the midpoint, three quarters,
  the end.
- **The moves playing:** one three second MP4 and GIF per move beside it,
  named `2026-10-11-depth-reel-transition-<name>` and
  `2026-10-11-depth-reel-entrance-<name>`.
- **The numbers:** `2026-10-11-depth-reel-numbers.json`: how far each one is
  turned at its midpoint and how far it moves in a tenth of a second.
- The mock these grow from: the Depth page,
  http://127.0.0.1:8791/index.html#video-depth ("How it feels").

## The six transitions (at a cut, in the tiles and in right-click Add Transition)

- **Flip**: the outgoing shot is the front of a card and the incoming one its
  back; the card turns over.
- **Cube**: the two shots are faces of a box that turns, backing off a little
  in the middle as the mock's cube does.
- **Swing**: the outgoing shot swings away on one edge like a door, uncovering
  the incoming one, which comes forward.
- **Doorway**: the outgoing shot parts into two doors that open toward you; the
  incoming one comes forward through them.
- **Revolve**: the outgoing shot swings away on one edge while the incoming one
  swings in on the other, like a revolving door.
- **Push in depth**: both shots sink back, slide across turned like cards on a
  carousel, and the incoming one comes forward.

Each has Length, Curve (the shared list, Ease in out to start), Direction and
Motion blur in the panel.

## The four title entrances (Part In, whole or by line, word or letter)

- **Swing In**: hangs from an edge and swings up to face you.
- **Flip Up**: flips up about its middle from facing away.
- **Fly In From Depth**: comes forward from far back, turning to face you.
- **Tilt Settle**: arrives tipped back and a little turned, and settles flat.

Each has an out that turns it away again.

## What each answer means

- **A, keep as filmed**: nothing changes.
- **B, retune Swing, Revolve and Doorway**: tell me what is off in your note;
  the other moves stay.
- **C, ship a shorter list**: Flip, Cube, Push in depth, Swing In and Fly In
  From Depth stay; the rest leave the tiles and menus.
