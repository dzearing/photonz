# Transitions at a cut, and effects over time

**Status: built, behind `next-transitions-at-a-cut` (on by default in Next).**
It needs `next-a-recording-is-a-document`, because a cut is something that
exists on the timeline in the ordinary editor, and `next-cut-a-recording` to
have made a cut in the first place.

The clickthroughs this was drawn against: `video-transitions.html` and
`video-transition-wt.html`. They are ideas, not specs, and §6 says where this
went further or differently and why.

---

## 0. The whole thing in four sentences

A cut is hard: one shot stops and the next starts on the same frame. A
transition is a relationship between the two pieces either side of that cut, so
it lives at the cut and costs spare media rather than position. Some of them put
both shots on screen at once, which has to be paid for; the dips do not. And an
effect a layer already has can change over a shot through the motion machinery
that was already there, not through a second one.

---

## 1. What a cut IS in this app

The study draws three separate clips butting against each other on a V1 track,
and picks the seam between two of them. **That does not exist here.** A Photonz
document holds ONE clip layer per recording, cut into pieces (`ClipPieces`, "a
split adds a piece to a clip, never a second clip"), and there is no way to put
a second recording into a document at all yet.

So the cut that a person can actually make is **the join between two pieces of
one clip**, and that is where a transition goes. Building it between two layers
would have been building for a situation nobody can create.

Everything else about the study's thesis survives intact, and it is the part
worth keeping: a transition is a relationship between two pieces at a cut, it is
drawn over the join rather than wedged between them, and it opens in the panel
like any other selection.

## 2. The model, in three types

| Type | Where | What it says |
| --- | --- | --- |
| `ClipTransitionKind` | `ClipTransitions.swift` | What happens: a cross dissolve, a dip to black, a dip to white. |
| `ClipTransition` | same | What is written down: the kind and how long it takes. Nothing about WHERE, because where is the cut it is on. |
| `ClipCut` | same | A cut and everything it can afford: which pieces, where it is, what spare media each side has, and what is on it. Handed out, never stored, so a piece that was just trimmed cannot leave a stale bill on screen. |

### Where it is written down, and why that is not a compromise

A transition is stored on the piece that **arrives** at the cut
(`ClipPiece.transitionIn`).

A cut has no object of its own in this model — it is the moment one piece stops
and the next starts — so the choice was between a list keyed by join number and
a property of the incoming piece. Keyed by number, every reorder, split and
delete has to renumber a second list, and the day one of them forgets, a
dissolve appears at a cut nobody put it at. Stored on the piece, a piece carried
somewhere else in the order takes its arrival with it and nothing has to be kept
in step.

It is **read, drawn, selected and paid for as a property of the CUT**. The piece
is only where it lives.

One consequence worth knowing: **the first piece arrives at no cut**, so
carrying a piece to the front of the order drops what it arrived with.
`ClipPieces.settleFirstArrival()` enforces that after every edit, so an inert
transition can never come back to life the moment a piece is carried back.

## 3. What it costs, and what it never costs

**An overlap is paid for with spare media, never with position.** Putting a
dissolve on a cut moves no piece, changes no length, and shifts nothing after
it. What it spends is frames the recording already has and the clip is not
playing — exactly what a trim puts out of play, answered by exactly the same
arithmetic (`trimStartRange`, `trimEndRange`).

- **Cross dissolve** needs an overlap. The outgoing piece plays on past its out
  point for half the length, the incoming piece starts early by the other half,
  and for that interval both are on screen.
- **Dip to black** and **dip to white** need none. Each piece plays the frames it
  already had, and the picture goes through a colour between them.

Two limits, and the smaller one wins (`ClipCut.longestMS(of:)`):

1. **It may not reach past the middle of either piece it joins**, so two cuts on
   one piece can never fight over the same frames — which is what makes "at most
   one transition is running at any moment" true by construction rather than by
   housekeeping.
2. One that needs an overlap may not spend spare media that is not there.

**A cut that cannot pay says so.** `setTransition` REFUSES a length the cut
cannot afford rather than quietly making a shorter one; the surface clamps with
`longestMS(of:)` first and then asks, so the gesture lands where the hand put it
and the model never guesses. In the panel, a kind that cannot be afforded is
unavailable and says "no spare", and the sentence under it says why.

### The invisible dissolve, said out loud

After a plain split, the two pieces read frames that are next to each other in
the file. A cross dissolve there blends a picture with itself and **nothing
visible happens**. `ClipCut.isContinuous` answers that, and the panel says so in
orange before the choice is made, because a feature that looks broken on the
first press is worse than one that is not there.

## 4. The trick that keeps the renderer out of it, again

`PhotonzDocument.drawn(atTimeMS:)` already handed back an ordinary document.
It now also **expands a clip into two layers while a transition is running**:

- a dissolve adds a second picture layer above, showing the incoming frame at
  the opacity the ramp is at;
- a dip adds a rectangle of the colour above, at the opacity the ramp is at.

Both of them are ordinary layers, so `DocumentRenderer` draws a transition
without having been told transitions exist — the same bargain that let a clip be
a picture layer in the first place. **Not one line of the renderer changed.**

The second layer gets a derived id (`Layer.transitionPartnerID`), the way a
frame's reference is derived from its recording's, so it is the same id in every
render of the same moment and can never collide with a layer somebody has.

`movieFrames(atTimeMS:)` asks for BOTH frames during a dissolve, so neither is
missing when it is drawn.

One thing that cost a walk: a rectangle's box lives in `annotation.start`/`end`,
in the layer's own coordinates, and a rectangle whose start and end are both
nought is a rectangle of no size. The model test passed while the frame on the
cut came out as the incoming shot instead of black. There is now a render test
(`TransitionRenderTests`) that asks the question a person asks — *is the frame
on the cut black* — and an export test (`TransitionExportTests`) that writes a
real MP4 and reads the frames back out of it.

## 5. Effects over time: no new mechanism

The second half of this work is one enum case.

`MotionProperty.blur` joins position, scale, rotation, opacity, colour and
stroke width. It is offered only on a layer that HAS a blur in its Effects list,
it reads and writes `style.blurRadius` — the very number the Effects panel's own
slider sets — and it gets the lane on the strip, the From and To row, the easing
curves, undo and the export without a line written for it.

**There is no keyframe window and no animate mode**, exactly as the user settled
on 2026-09-15. An icon animating and a shot going out of focus are the same
machinery.

One thing had to change for a document, and it is a real fix rather than a
detail: **a motion added to a layer with a stretch of time plays once**
(`LayerMotion.starting`). The icon default is there and back for ever, which is
what an icon is; a blur that came on over a second and then quietly took itself
back off again is not what anybody means by a blur coming on. A document
finishes; an icon repeats.

## 6. What the study drew and this does not

- **Six behaviours are three.** Cross dissolve, dip to black, dip to white. The
  study's own open question asks whether to ship the honest few or the full
  shelf, and push, wipe and morph are moves rather than answers to "what happens
  at this cut", each wanting geometry the cut has no opinion about. The model
  takes a fourth kind as one case; nothing about the shape of it has to change.
- **"The overlap sits: before / across / after" is gone.** A dissolve means
  across. Three answers to a question nobody asks is three ways to get it wrong.
- **"Hold on black 3.0s" is gone.** Inserting real black is inserting a PIECE,
  not putting something on a cut, and it is the one thing on that page that
  MOVES clips. It belongs with the cutting work.
- **"Expand the cut" into A and B rows is gone.** It is a second drawing of the
  timeline for one gesture. The bill is said in words on the panel instead:
  which pieces, what spare there is, and how much of it is being spent.
- **Transitions are not a library shelf.** The study browses them as tiles
  beside media and components. There are three, they are a property of the thing
  you have picked, and a shelf of three tiles is a shelf.

## 7. Where the surface is

| What | Where |
| --- | --- |
| Pick a cut | Click a join grip on the clip's bar in the timeline, or click the band over one. The playhead goes to the cut, so the canvas shows the frames the panel is talking about. |
| The panel | `TransitionInspector`, the Transition section, present only when the clip in hand has a cut at all. |
| The band | `ClipPiecesBar.band`, drawn over the join, with a grip at each end. Both ends do the same thing, because a transition is measured across the join. |
| The menu | Video ▸ Transition at Cut, acting on the cut in hand: the one picked, else the one the playhead is standing on (within a second of it). |
| The walk | `Scripts/playtest/transitions-at-a-cut-walk.json`, eleven real pictures. |

## 8. What this deliberately does not do

- **No transition between two clip LAYERS**, because two clips cannot be put in
  one document yet. When they can, a cut between two layers is a second kind of
  `ClipCut` and everything above it is unchanged.
- **No push, wipe or morph.** §6.
- **No default transition and no "apply to every cut".** Both are in the study.
  Neither is worth having until somebody has put the same transition on the same
  kind of cut more than twice.
- **The length is not typed.** It is dragged at the cut or pulled on the panel's
  slider. A number field is one line when somebody asks for it.
- **A blur is the only effect on offer over time.** It is the one the video work
  needs and the one the task named. A glow or a shadow changing over a shot is
  one case each in `MotionProperty`, added the day somebody wants it.
