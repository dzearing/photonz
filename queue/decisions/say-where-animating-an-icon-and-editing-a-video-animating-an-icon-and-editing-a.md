# Animating an icon and editing a video: one surface or two?

## What this is about

Photonz is meant to be a good place to build icons, and an icon that moves is
part of that: a notification bell that pulses, a spinner that turns, a bookmark
that fills in when you save something, a success badge that draws itself on.
None of that exists in the app today.

Photonz also has a video editor. It is a separate window that opens one screen
recording and lets you trim it, crop it and export it.

The obvious idea is that these are the same job with different content, because
both are things that change over time, and that one timeline could serve both.
Before building anything, five clickthroughs for animating an icon were drawn
and put beside the ten that already existed for editing a video. This decides
which way to go.

## Look at it first

**The side-by-side:**
<http://127.0.0.1:8791/index.html#time-compare>
Eight jobs, done both ways, with a verdict on each. Every cell says which flow
and which step it came from, and clicking it opens that flow.

**The five animation flows:**
[Make an icon pulse](http://127.0.0.1:8791/index.html#icon-animate-wt) ·
[A spinner that never stops](http://127.0.0.1:8791/index.html#icon-loop-wt) ·
[Animate a toggle](http://127.0.0.1:8791/index.html#icon-states-wt) ·
[Draw a checkmark on](http://127.0.0.1:8791/index.html#icon-drawon-wt) ·
[Hand the animated icon over](http://127.0.0.1:8791/index.html#icon-export-anim-wt)

**Two of the video flows, for the contrast:**
[Move a graphic](http://127.0.0.1:8791/index.html#video-move-wt) ·
[Zoom in over time](http://127.0.0.1:8791/index.html#video-zoom-wt)

The long form of the answer is `docs/design/animation-vs-video.md`.

## What the comparison found

They agree at the two ends and disagree about everything in the middle.

**The same, in three places.** You select a layer and a Motion section is
already sitting in Properties, in both. Easing is a row of named curves on both.
And the idea of a hand-off sheet that asks where the file is going before it
asks for a format would serve both, though it is only drawn on the icon side so
far.

**Different, in the place everybody assumes they match.** An icon animation
repeats and a video finishes. A spinner is one turn plus the word forever. A
notification pulse runs while there is something new. A toggle is two drawings
and a crossing, and it has no duration at all until you tap it. A ruler whose
whole grammar is "this is where it stops" cannot draw any of those. Icon keys
are percentages of one cycle, where the last key IS the first key; video keys
are seconds on a document with a last frame.

Everything else follows from that. Icons type one number for how long a pass
takes; video never types it, you move the playhead and the gap between two keys
is the duration. Icons are judged by looping them at quarter speed across four
copies at 16, 24, 32 and 48 points, because a pulse that reads at 48 is a
shimmer at 16; video is judged by scrubbing to one instant at one size. Icons
leave as 1.2 KB of text that stays sharp at every size; video leaves as encoded
frames.

## What the options would feel like

### a · Motion is a property, no ruler (recommended)

You click the bell layer. Properties shows its geometry, and under it a Motion
row that says None. You open it and get a short list: Pulse, Wiggle, Bounce,
Spin, Breathe, Draw on. You pick Pulse and the bell starts pulsing straight
away, on the artboard and on the four real-size copies. Four fields appear:
how much it grows, how long one pass takes, which curve, and whether it repeats
forever. You slow the preview to a quarter to see the shape of it, notice it
vanishes at 16 points, and push it from 115% to 124%.

Nothing that looks like a timeline appears anywhere.

The one thing it does not do well: an icon with several parts drawing on in
sequence gets a numbered list of start times, which is fine for two parts and
hard to read at six.

### b · The same, plus a cycle strip

Everything above, and the Motion section can also open into a horizontal strip
with a lane per moving part, measured 0 to 100% of one cycle. Six strokes of a
wordmark drawing themselves on becomes six bars you can see overlapping instead
of twelve numbers to hold in your head. The strip has no right-hand end,
because the motion repeats.

Both forms of that case are drawn on the comparison page so you can judge
whether the strip is worth it. The risk is that it looks enough like a video
timeline that it starts being asked for clips, audio and a last frame.

### c · One timeline for both

Icons and video share one bottom dock with a ruler in seconds and a playhead you
scrub. Getting there means video stops being its own window and becomes layers
on a document with a duration, which is a rewrite of the whole video feature,
and it has to happen before the first icon can pulse. And the ruler still cannot
say forever, which is what three of the four icon scenarios need.

### d · Leave icons static for now

Nothing animates. The pen, the icon grid and clean SVG export carry on. Picking
this retires the question rather than handing it back.

## The recommendation, and why

**Option a.** It covers every icon scenario on the table, it is the shortest
path to an icon that moves, and it leaves video better off than it is now
(a settled easing vocabulary, a tested idea of a key, a better hand-off sheet)
without touching it. Option b is not a different direction, it is option a's
second chapter, and it can be added later without changing anything above it.

One thing worth knowing while deciding: **the consolidation actually worth
having is a different pair.** The toggle flow's States group, a named list of
states with a count of what differs and one duration for the crossing, is
structurally the same surface as component variants on the UI side. Both are
live work right now. Built separately they will drift, exactly the way four
different easing vocabularies drifted across six mock pages without anyone
deciding to. Compare
[Animate a toggle](http://127.0.0.1:8791/index.html#icon-states-wt) with
[Component variants](http://127.0.0.1:8791/index.html#ui-variants).
