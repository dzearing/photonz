# Animating an icon and editing a video: where they are the same job

Written 2026-09-14, from the fifteen clickthroughs that now exist: five for
animating an icon (`icon-animate-wt`, `icon-loop-wt`, `icon-states-wt`,
`icon-drawon-wt`, `icon-export-anim-wt`) and ten for editing a video
(`video-entry-wt`, `video-cut-wt`, `video-move-wt`, `video-zoom-wt`,
`video-transition-wt`, `video-freeze-wt`, `video-title-wt`, `video-captions`,
`video-compositing`, `video-speed`).

The side-by-side this summarises is a page, not a table in a document:
<http://127.0.0.1:8791/index.html#time-compare>. Read it first. Everything below
is the short form.

## The answer in one paragraph

They are one experience in three narrow places and two experiences everywhere
else. The three shared things are small and worth building once. The thing
everybody assumes is shared, a ruler you scrub a playhead along, is the one
thing they cannot share, because an icon animation repeats and a video finishes,
and that single fact drives every other difference between them.

## What is genuinely the same job

1. **Motion is a section on the selected layer.** Both flows do exactly the
   same thing at step 1: click a layer, Properties fills in, and a Motion
   (icon) or Animate (video) section is already there. Neither has an animate
   mode to enter. This already holds in the app, because the selection model
   and the inspector are shared, so it costs nothing to keep.
2. **Easing is a named curve on a segment.** Both put an Easing row in the
   same place with the same meaning: how a value gets from one value to the
   next. **And it has already drifted**: four different vocabularies across six
   mock pages (Linear / Ease in-out / Spring on the pulse and spinner; Linear /
   Ease out / Spring on the toggle; Linear / Ease out / Ease in-out on the
   draw-on; Linear / Ease in-out on both video flows). Nobody decided that. It
   is the clearest argument on the page for building one easing vocabulary
   once, and it is a small piece of work: a list of names and a curve for each.
3. **A hand-off sheet that asks where the file is going before it asks for a
   format.** This is the weakest of the three: it exists on the icon side and
   nowhere on the video side, where all ten flows export with one button and no
   questions. The reasoning transfers exactly (people know their destination and
   do not know their formats) but it is a proposal until a video flow is drawn
   with it.

## What looks the same and is not

- **The ruler.** Icon keys are percentages of one cycle (0%, 50%, 100%, where
  the last key IS the first key). Video keys are absolute seconds on a document
  with a last frame. The percentage form is not a simplification, it is
  literally what a CSS keyframe block and a SMIL `keyTimes` list are.
- **The front door to animating anything.** Icons open a list of named motions
  (Pulse, Wiggle, Bounce, Spin, Breathe, Draw on) and the keys are the room
  behind it. Video has no named motions anywhere in ten flows: the keyframe
  diamond is the front door.
- **How long it takes.** Icons type one number (Over 0.9s, or Per turn 0.9s on
  a loop). Video never types it: you move the playhead and the distance between
  two keys is the duration.
- **The preview.** Icons loop the motion at 0.25x across four copies at 16, 24,
  32 and 48 points, because a pulse that reads at 48 is a shimmer at 16.
  Video scrubs the playhead to one instant at one size. Neither review is any
  use for the other job: you cannot scrub 600 milliseconds, and a video at 16
  points means nothing.
- **The export.** Icons emit text: 1.2 KB of animated SVG, sharp at every size,
  and stripped entirely by a code host. Video encodes frames: pixels at one
  resolution, playable anywhere. The same motion as a GIF is 74 KB.

## What only one of them will ever need

Only video: audio detached from the picture, blade and split, in and out
points, transitions paid for with spare frames either side of a cut, freeze
frame, speed and retiming, codecs and a render wait.

Only icons: review at 16/24/32/48 points at once, stroke length so a path can
draw itself on, the point a shape turns around, two states and a crossing
between them, a trigger the exported file cannot carry, and closing the loop so
the last key equals the first.

## What consolidating would cost

Video in Photonz today is **a separate editor, not a document**:
`Sources/Photonz/VideoEditorState.swift` and `VideoEditorView.swift`, its own
window, one clip. The whole stored model is `VideoEdits` in
`Sources/PhotonzCore/VideoEdit.swift`: an in point, an out point and a crop
rectangle. The layer document has no notion of time, and there is no keyframe
type anywhere in `PhotonzCore` or `PhotonzRender`.

So "share a timeline with video" does not mean connecting two things that
exist. It means first rewriting video into a multi-clip, multi-track document
with audio, a playhead in the render path and a compositor that samples media
per frame, and only then having something to share. That is the whole video
feature, built before an icon can pulse, and the icon side gets nothing from
it: no part of codecs, audio or frame scheduling teaches you how to emit a SMIL
keyframe block.

The asymmetry runs one way, and it is the expected direction rather than a
surprise. Animation first genuinely helps video later (a settled easing
vocabulary, a tested idea of a key as a value on a property at a moment, a
destination-first hand-off sheet). Video first helps animation not at all.

## The gap the mocks left, and what it decides

None of the five animation flows shows more than two moving parts, and at two
parts the numbered Order list in `icon-drawon-wt` is plainly enough. The
`time-compare` page draws the case they skipped: six strokes of a wordmark
drawing themselves on in sequence, as a list of twelve numbers and as six lanes
on one cycle.

The honest reading: **a whole icon SET does not animate together**, because
icons animate on their own triggers in whatever app they end up in, so there is
no case for a shared ruler across a library. What does happen is ONE icon with
several parts, and the list holds up to about three of them and stops. So the
lanes are worth building, and worth building **second**: they are a second view
of numbers that already exist, so adding them later changes nothing above them.

## What to build first

1. **Motion is a property of a layer.** Named motion list, plus how much, how
   long one pass takes, which curve, whether it repeats, what it turns around.
   No playhead, no ruler, no tracks. This is the whole pulse flow and the whole
   spinner flow.
2. **The preview is the review.** The icon preview strip already in the app
   (`IconPreviewsStrip.swift`) runs the motion at every size at once, with a
   speed control. Without it nobody can judge whether the motion is any good.
3. **It leaves as an animated SVG**, alongside the static SVG export already
   planned, with the destination-first sheet.
4. **Later, and only on evidence: the cycle strip.** 0 to 100% of a cycle, a
   lane per animated part. It earns its place the first time somebody animates
   four parts of one icon and cannot read the list.

**No project type picker.** The two jobs already live in separate windows, so
nothing needs hiding from anything. The surface can keep following the document:
a document with a duration gets a transport, a document with a repeating motion
gets a cycle strip, and neither has to ask which kind of thing you are making
before you start.

## The consolidation actually worth having is a different one

The toggle flow's States group (a named list of states, a count of how many
things differ between them, one duration for the crossing) is structurally the
same surface as component variants on the UI side. Both are live work right now,
unlike video, and built separately they will drift exactly the way the four
easing vocabularies drifted. Compare `icon-states-wt` with `ui-variants`: the
overlap is closer than anything between icons and video.
