# Animating an icon and editing a video: where they are the same job

Written 2026-09-14. **Rewritten 2026-09-15**, after the first round of animation
mocks was rejected and rebuilt. The first version compared a set of flows that
offered a short menu of canned motions (Pulse, Spin, Draw on) and concluded that
icon timing was one typed number and that a list of parts beat a track. That
premise is gone: you animate **a property** of a layer, the way you add an effect
to one, and the timing needs a surface with real width. Everything below is read
off the rebuilt pages.

Sixteen clickthroughs: six for animating an icon (`icon-animate-wt`,
`icon-phase-wt`, `icon-loop-wt`, `icon-states-wt`, `icon-drawon-wt`,
`icon-export-anim-wt`) and ten for editing a video (`video-entry-wt`,
`video-cut-wt`, `video-move-wt`, `video-zoom-wt`, `video-transition-wt`,
`video-freeze-wt`, `video-title-wt`, `video-captions`, `video-compositing`,
`video-speed`).

The side-by-side this summarises is a page, not a table in a document:
<http://127.0.0.1:8791/index.html#time-compare>. Read it first. Everything below
is the short form.

## The answer in one paragraph

They are one experience in four places and two experiences everywhere else. The
rebuild moved three rows of the comparison towards video, and the fourth shared
thing is the surprise: **the timing surface itself**, tracks, bars, playhead and
all, which both sides already draw out of the same component. What they still
cannot share is the thing most people mean by "one timeline": the **ruler**. An
icon repeats and a video finishes, and that single fact drives every remaining
difference between them.

## What is genuinely the same job

1. **Motion is a list on the selected layer, wearing the row an effect already
   uses.** Both flows click a layer and find what moves as one more list in
   Properties; neither has an animate mode to enter. One detail is worth
   settling once: the icon side **adds an entry**, so a motion can be copied,
   pasted, switched off and reordered, while the video side **marks a property
   row** that is already there. The list form is the stronger one, because
   copying an entry is exactly how the knob gets the bell's swing.
2. **The timing surface is one component, not two.** Both pages build it from
   the same shared parts (`.timeline`, `.ruler`, `.track > .tl + .lane`,
   `.playhead` in `shared/components/inspector.css`): a docked strip, a label
   column, a lane per thing, a bar you drag. This is the single largest piece of
   shared work the study found, and it was not true a day ago.
3. **The curve is a named shape, and the drift is now one-sided.** It used to be
   four vocabularies across six pages. The icon pages have settled on one list
   with the shape drawn beside each name plus a curve you can draw yourself
   (`cubic-bezier(.45, 0, .55, 1)`); the video pages still carry two buttons in
   a segmented control. That is no longer a disagreement, it is a gap with a
   known answer, and it is already a task in the queue.
4. **A hand-off sheet that asks where the file is going before it asks for a
   format.** Still the weakest of the four: it exists on the icon side and
   nowhere on the video side, where all ten flows export with one button and no
   questions. The reasoning transfers exactly, but it is a proposal until a
   video flow is drawn with it.

## What looks the same and is not

- **The ruler.** The icon strip measures **one cycle**; the video strip measures
  **a document**. The clearest proof is one step of `icon-phase-wt`: the knob's
  bar runs past the dashed line where the cycle restarts, because the knob is
  still finishing its swing while the bell has already begun the next one. A
  ruler whose grammar is "this is where it stops" cannot say that sentence. On
  the way out the icon's milliseconds become percentages of a cycle, which is
  literally what a CSS keyframe block and a SMIL `keyTimes` list are.
- **How long something takes.** Icons carry Start and Over as a pair of fields
  *and* as a bar; the two are the same numbers. Video never types it: the
  distance between two keys is the duration. Same surface, different hand.
- **What a shape turns around.** Rotation on an icon puts a **pivot on the
  canvas** from the moment it exists, and dragging it from the middle of the
  bell to its mount turns a bobblehead into a bell without a number changing.
  There is no pivot anywhere in ten video flows.
- **The preview.** Icons loop at 0.25x across four copies at 16, 24, 32 and 48
  points, lag included, because ninety milliseconds is under six frames. Video
  scrubs the playhead to one instant at one size. Neither review is any use for
  the other job.
- **The export.** Icons emit text: 1.2 KB of animated SVG, sharp at every size,
  and stripped entirely by a code host. Video encodes frames: pixels at one
  resolution, playable anywhere.

## What only one of them will ever need

Only video: audio detached from the picture, blade and split, in and out points,
transitions paid for with spare frames either side of a cut, freeze frame, speed
and retiming, codecs and a render wait.

Only icons: review at 16/24/32/48 points at once, stroke length and dash so a
path can draw itself on, the point a shape turns around, a bar that runs past the
end of the cycle, a trigger the exported file cannot carry, and closing the loop
so the last value is the first value.

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
feature, built before an icon can swing, and the icon side gets nothing from
it: no part of codecs, audio or frame scheduling teaches you how to emit a
keyframe block as text.

The asymmetry runs one way, and it is the expected direction rather than a
surprise. Animation first genuinely helps video later: a settled curve
vocabulary, a tested idea of a motion as an entry on a property, and the timing
strip itself. Video first helps animation not at all.

## The case that settled the strip, and the case beyond it

At one moving part a column of fields is enough. **Two parts is where that stops
being true**, and two parts is now walked end to end: the bell swings, the knob
carries the same motion ninety milliseconds later, and the only way to set that
is to drag one bar against another and read the gap. That is why the strip is no
longer a "later, on evidence" item; the evidence is the flagship flow.

What is still unproved is everything past two parts: six strokes of a wordmark
drawing themselves on, where the question becomes whether lanes want grouping.
`icon-drawon-wt` still carries the old numbered Order list, and rebuilding it
onto the strip is already filed.

A whole icon SET does not animate together, because icons animate on their own
triggers in whatever app they end up in, so there is still no case for a shared
ruler across a library.

## What to build first

1. **A property of a layer can change over one cycle.** Motion is a list in
   Properties with a plus that offers this layer's own properties; one entry
   carries from, to, start, over, curve and repeat, and the icon plays in the
   canvas. Nothing else works until this does.
2. **Rotation says what it turns around**, with a pivot you drag on the canvas.
   Without it the flagship motion is a bobblehead.
3. **The timing strip across the bottom**: one cycle, a lane per animated
   property, a bar you drag, a dashed line where it repeats, and a bar allowed
   to cross that line. This is what makes a second moving part possible, and it
   is the surface video would inherit unchanged.
4. **The loop is the review**: play it at 16, 24, 32 and 48 points at once with
   a speed control. This replaces scrubbing.
5. **It leaves as an animated SVG**, alongside the static SVG export already
   planned, with the destination-first sheet.

**Video does not move.** It stays the separate editor it is today and inherits
the curve list and the timing strip when it is its turn, by using the same
components rather than by being rewritten first.

**No project type picker.** The two jobs already live in separate windows, so
nothing needs hiding from anything. The surface can keep following the document:
a document with a duration gets a transport, a document with a repeating motion
gets a cycle strip, and neither has to ask which kind of thing you are making
before you start.

## The consolidation actually worth having is a different one

The toggle flow's States group (a named list of states, a count of how many
things differ between them, one duration for the crossing) is structurally the
same surface as component variants on the UI side. Both are live work right now,
unlike video, and built separately they will drift the way the curve controls
drifted. Compare `icon-states-wt` with `ui-variants`: the overlap is closer than
anything between icons and video.
