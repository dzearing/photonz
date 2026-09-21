# Video: the document, with time in it

**Status: built, behind `next-a-recording-is-a-document` (off by default).**
The model and the shell landed on 2026-09-20. What the old recording window
still owns — trim, crop, save, export, revert — is named at the end, with what
happens to each.

This is the *what it is* document. Where the chrome goes and why is
`docs/design/video-surface.md`; the fifteen clickthroughs under
`docs/design/mocks/pages` are the ideas it was drawn against.

---

## 0. The whole thing in four sentences

A document may have a duration. A layer may have an in and an out. A layer may
point at a recording. Everything else follows.

There is no video document, no video window, no video mode and no video state.
A recording opens the editor you already know, and the only thing different
about that document is that something in it occupies time.

---

## 1. What was wrong with what shipped

Video was a separate little editor: `VideoEditorState`, `VideoEditorView`, one
clip, a play button, handles to shorten it from either end. Nothing you had
learned about editing a picture applied in it. You could not put a title on a
recording, draw an arrow on it, see it in a layers list, give it a corner
radius, or put anything underneath it.

And every one of the fifteen clickthroughs says the same thing in its own
words: *a recording opens the same document with a time dimension*; *captions
are what the Text tool does when the document has time*; *the stack is the
timeline*; *a freeze is a clip whose in and out are the same frame*. Every one
of them is impossible in a separate editor and free in a document.

---

## 2. The model, in four types

Three of the four already existed when this task started
(`DocumentTime.swift`, `ClipPieces.swift`). The fourth is what made them
playable.

| Type | Where | What it says |
| --- | --- | --- |
| `PhotonzDocument.durationMS` | `Document.swift` | How long this document runs for. Nil for every screenshot, which is what makes all of this free for one. |
| `LayerTime` | `DocumentTime.swift` | Where a layer arrives and where it goes, plus where in its own source that stretch reads from. |
| `ClipPieces` | `ClipPieces.swift` | The pieces one clip is cut into, laid back to back. A split adds a piece to a clip, never a second clip. |
| `MovieRef` | `MovieClip.swift` | **New.** Which recording a layer plays: an id, a picture size, a length. |

`Layer.movie: MovieRef?` is the only field this task added to the model.

### Nothing here is ever pixels

`CLAUDE.md` puts one rule above the rest: pixel data never lives in the
document model. A clip obeys it exactly as a photo does. `MovieRef` is an
identity, a size and a length — no path, no frames, no asset. Cutting a
recording copies nothing, trimming it throws nothing away, and a clip is a
window onto one file rather than a copy of part of it.

---

## 3. The trick that keeps the renderer out of it

**A clip layer is an ordinary picture layer whose `ImageRef` is the frame it is
showing.**

`PhotonzDocument.drawn(atTimeMS:)` already handed back an ordinary document with
whatever is off screen at that moment hidden. It now also swaps each clip's
picture reference for the one belonging to the frame at that moment. So
`DocumentRenderer` — which has drawn pictures since the first day — draws a
frame of video without having been told time exists. **Not one line of the
renderer changed.**

Which means a clip gets, for free and without a special case anywhere:

- a place in the layer stack, and everything above and below it
- a corner radius, an opacity, a blend mode, a mask
- the Effects list: blur, shadow, glow, anything added later
- a name, an eye, a lock, a thumbnail, rename in place
- selection that agrees between the canvas, the layers list and the panel
- undo, because in and out are ordinary layer values written through `History`

### Where the pixels come from

```
document.movieFrames(atTimeMS:)  ->  [MovieFrameRequest]   (PhotonzCore: what is needed)
MovieFrameFetcher.fetch(_:)      ->  MovieDecoder (actor)  (app: decode it)
                                 ->  ImageStore            (app: file it under the ref)
document.drawn(atTimeMS:)        ->  the renderer draws it
```

Three rules hold this together:

1. **A frame's reference is derived, never stored.** `MovieRef.frameRef(atSourceMS:)`
   folds the frame number into the recording's own id, so the same frame of the
   same recording is the same reference in every window, every render and every
   run. Decode it once, draw it anywhere.
2. **Frames are asked for on a grid**, `MovieRef.frameStepMS` = 33ms. A scrub
   that asked for the exact millisecond under the pointer would decode a frame
   per pixel and cache none of them.
3. **The cache is bounded.** `MovieFrameFetcher.frameBudget` = 16 frames. A
   Retina frame is thirty megabytes; a cache that simply grew would eat a
   gigabyte in a second of playing.

The canvas never waits on a decode. It draws the last frame it has and replaces
it the instant the right one lands, which is what makes a scrub feel like a
scrub rather than a slideshow.

---

## 4. What appears, and on what fact

One fact — **the document has a duration** — puts three things on screen, and
nothing else in the app changes.

| What | Where | Fact |
| --- | --- | --- |
| The timeline | bottom dock, the shipped timing strip | `document.hasTime` |
| The transport | the timeline's top row | the same fact |
| A playhead you can drag | over the timeline's lanes | the same fact |

A document with no duration is untouched: no timeline, no transport, no
playhead, and the arrows and the space bar mean what they always meant.

### The timeline is the timing strip

There is no second component. `MotionStripGroup` grew a bar, so the rule is now
*a layer draws a bar when it has an in and an out, and a heading when it does
not* — true of a clip and of a bell that rotates, one rule, no fork. The rows
are the layers, named with the layer's own name and icon, which is the layers
list turned on its side.

**The ruler is the one thing not shared.** An icon repeats and is read in
milliseconds, because ninety of them is the whole reason the strip exists. A
recording finishes and is read in minutes and seconds, because that is how long
a recording is. `MotionStripRuler` has had two forms since the model landed;
this task gave the document form timecode labels.

### The transport

Only the controls that do something: where the playhead is, back a frame, play
or pause, on a frame, and how long the whole thing runs for. No volume: sound
landed on 2026-09-21 and its level is a property of each LAYER that makes one
(`video-audio.md`), so a master fader here would be a second place to turn the
same thing down. No loop, because a recording finishes. A control that only
promises a feature is a dead end.

`space` plays and pauses. `←` and `→` step a frame, and only while nothing is
picked, so they still nudge a layer somebody has taken hold of.

### The clock is real time

The playhead is worked out from the wall clock rather than counted in frames, so
a frame that takes too long to decode costs that frame and never the timing of
everything after it. Playing prefetches three frames ahead of itself. Both
matter more than they sound: see §6.

---

## 5. Layers does not leave

Every one of the fourteen video clickthroughs draws a dock of Properties ·
Effects · Library and no Layers, and `video.html` says why: the list looked like
a second rendering of the timeline.

The complaint is right and the conclusion is wrong, and
`video-surface.md` §3 is the argument. The short of it: **not everything in a
video document has time.** A background, an adjustment, a frame, a component
master, a matte — with Layers deleted, anything without an in and an out has no
row anywhere and becomes unreachable. The pages get fixed, not the dock.

---

## 6. What it costs, measured

Numbers and method in `docs/progress/perf.md` (2026-09-20).

| Recording | One frame, decode + composite |
| --- | --- |
| 1280×800, the size of a window | ~9ms, inside the 16ms budget |
| 3456×2234, a full Retina screen recording | ~44ms, about 23fps |

Said plainly: **a recording the size of a window plays at the rate it was
recorded at; a full-Retina screen recording does not.** Three quarters of the
cost is AVFoundation handing over a 7.7 megapixel frame, so that is where the
work goes when it is worth doing: an `AVAssetReader` reading forward beats a
generator seeking, and decoding at the size of the WINDOW rather than the size
of the file beats both. Neither is built. Nothing about it lands on the main
actor, so the window stays responsive either way; what suffers is the frame
rate of the picture, and this document says so rather than shipping a timeline
that quietly stutters.

---

## 7. What happened to the old video editor

Not retired yet, and deliberately not pretended otherwise.

**Trim moved on 2026-09-20.** It is now a tool in the ordinary window, in
Crop's slot, and `video-surface.md` §10 describes what was built. What is left
in the old window is save, export, crop and revert to original, and one
question about the first of those is with the user: a recording document can
now be styled, and Save cannot mean both "write the video back" and "write a
project holding the arrow you drew on it". The window stays the default until
that is answered, which is why `next-a-recording-is-a-document` is still off.

| Thing | What happened |
| --- | --- |
| Trim | **Moved.** `Tool.trim`, `ClipTrimSession` (PhotonzCore), `EditorState+Trim`, handles on the clip's bar in `MotionStripView`, one glass capsule in `EditorView.trimActionBar`. `trim-is-a-tool-walk` drives the whole session. |
| `VideoEditorState` | **Still standing.** It is what a recording opens with the flag off, and it still owns save, crop, export and revert to original. Its own trim is still there and still what that window uses; nothing has been taken away from anybody. |
| `VideoEditorView` | Still standing, same reason. |
| `TrimTimeline` | Untouched. It is bound to `VideoEditorState` and goes when that does. |
| `PlaybackScrubber` | Untouched, same reason. |
| `VideoCutList` | **Reused.** `ClipPieces(cutList:)` and `VideoCutList.layerTimes()` project a cut recording straight into the document model, so the two agree about time without either owning the other's arithmetic. |
| `VideoExporter`, `VideoAssetCommit` | Untouched. Export is `video-share` and is unchanged by any of this. |

**Why there are two ways in for now.** Eleven walks drive the shipped trim flow
through the old window, and the trim TOOL that replaces it (`video-surface.md`
§10: Crop's slot, handles on the clip's bar, one capsule reading Cancel then
Trim) is not built. Moving the window before the tool exists would take trim,
save and export away from anybody who opened a recording. So the document path
ships behind its own flag, off by default, and the old window stays the default
until the tool and the walks move with it. That is one flag with two settings,
not two editors nobody chose between, and the flag's whole job is to be deleted.

---

## 8. What this deliberately does not do

Each of these will push back on the model, and the model is right when they can
be added without it changing shape.

- **Transitions.** A relationship between two clips at a cut, not a filter on a
  clip. `comp-video` §02–§04.
- ~~**Audio.**~~ **Built on 2026-09-21** (`video-audio.md`), and it pushed back
  on the model exactly as little as hoped: one computed property on `Layer`, one
  content case, two optional fields, and the strip drew it without being asked.
  A separated track is a layer with an in and an out, so it rides the same axis
  and the same trim.
- **Captions.** What the Title / Text tool does when the document has time.
- **Keyframes.** Already settled by the user on 2026-09-15: motion is a property
  of a layer opening into a timing surface with a lane per moving part. An icon
  animating and a clip moving are the same machinery, and the strip is already
  that machinery.
- **Trimming by dragging the end of a clip's bar OUTSIDE a trim session.** The
  bar has grips while Trim is in hand, and none the rest of the time. The quick
  nudge `video-surface.md` §10.4 describes — Select, drag the end of a clip —
  is not built.
- **Scrubbing into the spare tells you nothing new yet.** During a session the
  clip is laid out at full length and the canvas draws any frame of it, which
  is the point; what it cannot do is show the trim's own in and out marked on
  the CANVAS the way a crop darkens what it is about to lose.
