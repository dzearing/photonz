# Video: the document, with time in it

**Status: built, behind `next-a-recording-is-a-document` (off by default).**
The model and the shell landed on 2026-09-20. What the old recording window
still owns — trim, crop, save, export, revert — is named at the end, with what
happens to each.

Export landed on 2026-09-21 behind `next-export-the-video`: §8.

This is the *what it is* document: it records the model and what has been
built. **The target is the user's mocks**, not this document and not what ships
today: `docs/design/mocks/pages/video.html` (the whole editor), the `video-*.html`
walkthroughs beside it, and `comp-video.html` (the primitives), restored on
2026-09-23 exactly as the user drew them, real tracks included. Where what is
built here differs from them (the timeline below most of all), the mock wins and
the difference is work still to do. The design decisions are
`docs/design/video-surface.md` and UX-PATTERNS D18 (a document with time has
tracks).

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

Until 2026-09-23 that paragraph was a promise no code kept: a clip pointed at
the frame under the playhead whether or not it had been read, and a picture
layer with nothing behind it draws nothing, so a full-screen Retina recording
flickered every time the decoder was late (`playing-a-recording-never-blinks`).
What keeps it now:

4. **A late frame holds the last one.** The canvas draws
   `drawn(atTimeMS:framesInHand:)` with `MovieFrameFetcher.inHand`, and a frame
   not in hand is stood in for by the newest one that is, at or before the
   moment (`MovieFramesInHand.swift`). An export leaves the hand out and waits
   for every frame it writes. The renderer's incremental cache also notices a
   picture that lands, or is read again bigger, under a reference the document
   already pointed at, so the landing redraw is never answered with the old
   frame.
5. **Four decoders per recording, eight frames ahead.** One
   `AVAssetImageGenerator` takes about 40ms (up to 100ms) to seek to and read a
   3456x2234 frame, longer than the 33ms it is on screen, and reading smaller
   does not help because the time is in the decode. `MovieDecoder.lanes` = 4
   side by side read one every 14ms or so; `MovieFrameFetcher.playAheadFrames`
   = 8 keeps them busy.
6. **Frames are read at the size they are shown**, in eighths of the
   recording's size (`MovieRef.decodePixelSize`), which is what lets the
   16-frame budget stay small. Zooming in reads the frame on screen again; the
   smaller one shows until the sharper one lands. Writing a file always reads
   at the recording's own size.

---

## 4. What appears, and on what fact

One fact — **the document has a duration** — puts three things on screen, and
nothing else in the app changes.

| What | Where | Fact |
| --- | --- | --- |
| The timeline | bottom dock (today the icon timing strip; the target is `video.html`'s timeline) | `document.hasTime` |
| The transport | the timeline's top row | the same fact |
| A playhead you can drag | over the timeline's lanes | the same fact |

A document with no duration is untouched: no timeline, no transport, no
playhead, and the arrows and the space bar mean what they always meant.

### What ships today, and what the timeline is meant to be

**What ships** is the icon animation timing strip with a bar added:
`MotionStripGroup` grew a bar, so a layer with an in and an out draws one and
every other layer draws a heading, and the rows are the layers under their own
names. That was a stopgap, and on 2026-09-23 the user said it looks nothing like
the timeline they designed.

**The target** is the timeline `video.html` draws: a transport with volume, a
large play button, the current time, a full-width scrubber and the duration; a
ruler in seconds; a red playhead that spans every track; **tracks** (video,
titles, audio, captions) with headers that carry a name and their switches,
each holding many clips drawn as rounded bars with the clip's name inside; and
zoom. A document with time has tracks (UX-PATTERNS D18). Building that is the
task *The timeline is the one in the mock*, and real tracks are *Tracks you can
add, rename, group, hide, mute, lock*.

**The ruler is the one thing not shared.** An icon repeats and is read in
milliseconds, because ninety of them is the whole reason the strip exists. A
recording finishes and is read in minutes and seconds, because that is how long
a recording is. `MotionStripRuler` has had two forms since the model landed;
this task gave the document form timecode labels.

### The transport

What ships today is below. The mock's transport (`video.html`) also carries a
volume control and a full-width scrubber, and the mock is the target; what
follows is the reasoning the built one was made with.

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
| `VideoExporter`, `VideoAssetCommit` | Untouched, and still what the old window's Export uses. A DOCUMENT with time leaves through `DocumentMovieWriter` instead (§8): the old exporter is a function of one file plus a cut list, and cannot say a reordered piece, a held frame, a second sound layer or an arrow drawn over the picture. |

**Why there are two ways in for now.** Eleven walks drive the shipped trim flow
through the old window, and the trim TOOL that replaces it (`video-surface.md`
§10: Crop's slot, handles on the clip's bar, one capsule reading Cancel then
Trim) is not built. Moving the window before the tool exists would take trim,
save and export away from anybody who opened a recording. So the document path
ships behind its own flag, off by default, and the old window stays the default
until the tool and the walks move with it. That is one flag with two settings,
not two editors nobody chose between, and the flag's whole job is to be deleted.

---

## 8. Getting it out: the document as a video file

Built on 2026-09-21 (`next-export-the-video`). Until then the timeline could cut
a recording into pieces, throw one away, carry them into a different order,
speed one up, hold a frame, take the sound off the picture, put music under it
and duck the music, and **none of it could leave the app**: Export wrote the
recording that was opened, ignoring every edit, and Export Sound wrote the mix
on its own.

**One sentence: a video export is the canvas, photographed at every moment, with
the mix laid beside it.**

Three pieces, and each of them was already there but one:

| Piece | Where | What it answers |
| --- | --- | --- |
| `DocumentVideoExport.plan` | PhotonzCore | Which moments get photographed and how big each picture is. Pure, and tested without writing a file. |
| `PhotonzDocument.drawn(atTimeMS:)` | PhotonzCore | What the picture at a moment IS. Unchanged: §3's trick is what makes an export free. |
| `PhotonzDocument.audioMix()` → `AudioMixdown` | PhotonzCore / PhotonzMedia | What it sounds like. Unchanged: the very function Export Sound calls. |
| `DocumentMovieWriter` | PhotonzMedia | The loop between them, and the file. |

So the exported frame and the frame on screen cannot be two different pictures,
and the mix on disk cannot be a different mix from the one in the room. Neither
is a promise anybody has to keep by hand; there is only one answer to each
question and two readers of it.

### How the file is made

1. **Photograph it.** One picture per frame of the plan, at 33ms apart — the
   grid a clip's frames are decoded on (`MovieRef.frameStepMS`), so asking for
   more would photograph the same decoded frame twice. Each one is the window's
   own renderer handed `drawn(atTimeMS:)`, off the main actor.
2. **Write the mix** with `AudioMixdown.write`, which is Export Sound.
3. **Put the two in one container**, passthrough, so the pictures are never
   compressed twice and the sound is byte for byte the mix.

Feeding pictures and sound into ONE `AVAssetWriter` would be a pass fewer and
it deadlocks: a writer holds one input back until the other catches up, and the
pictures cannot be interleaved with a mix that is not made yet. That was
measured, not guessed — a walk hung for ten minutes on it.

### Two things that are easy to get wrong

- **A frame with nothing on it.** Pixel buffers come from a pool and a picture
  is drawn OVER what is in one, so an empty frame — a document whose music runs
  past its last clip — came out as whatever frame used that buffer last, which
  reads as a freeze frame nobody asked for. Every buffer is cleared to black
  first. A movie has no transparency to keep, so black is what an empty frame
  is. There is a test.
- **The recording nobody has touched.** Photographing a recording back into
  existence to get the file it came from is minutes of work for a worse file.
  `PhotonzDocument.untouchedRecording` answers "is this document EXACTLY what
  opening that recording makes", by rebuilding it and comparing, so a layer
  property added tomorrow takes the fast path away tomorrow without anybody
  remembering to add it to a list. Anything at all different and the file is
  made frame by frame.

### What the sheet offers

The recording Export sheet's own vocabulary, not a second one: MP4, GIF and
HEIC in that order, the same size presets on all three, and the same
`RecordingExport` lines saying what the file will be and what it will weigh.

**Every format says what it will weigh, and they get there differently.** An
untouched recording going out as MP4 at the top choice is copied, so its weight
is the file that is already there. Any other MP4 is weighed from the budget the
encoder is asked for, which is why it says "about" (`VideoExportRecipe`). A GIF
or a HEIC has no budget and no formula: measured, eight frames sampled from
across a recording and multiplied came out 100 to 400 per cent over, and runs of
consecutive frames swung from 76 per cent under to 120 per cent over, because
ImageIO compresses each frame against the one before it. So the sheet WRITES
one, into a scratch file, while it is open, counts up in whole per cent as it
goes, and says the size of what landed (`ExportWeigh`). That number is exact
rather than an estimate because an animated export written twice lands at the
same size, and pressing Export moves that very file into place, so the seconds
spent answering the question are the seconds the export would have cost anyway.

Nothing is written when nobody is looking: the weigh starts when the sheet shows
an animated format, starts again when the format or the preset changes, and is
cancelled with its scratch file when the sheet closes.

While it writes for real, a card says how far along it is and can stop it.
Stopping takes the half-written file with it.

### What it does not do yet

- **No MP4 quality choice.** That is `a-recording-can-be-made-small-enough-to-send`,
  and inventing one here would be a second set of answers to the same question.
- **No still picture from a timed document.** Export on a document with time is
  the video sheet, so the PNG of one frame that Export used to write is not
  reachable. Nobody has asked for it; when somebody does, it is a fourth row on
  the same sheet rather than a second sheet.
- **The export borrows the window's picture store** for the frames it decodes
  and gives every one of them back. While it runs, the canvas can lose a frame
  it was holding and has to fetch it again.

---

## 8b. The way in: one door, and it tells you when it cannot take you

*Built 2026-09-21, `next-opening-a-recording`.*

Opening a recording was an act of faith. A window opened first and the file was
read afterwards, so three ordinary situations all produced the same nothing:

- **A recording that has gone.** `MovieLibrary.movie(at:)` hands back nil and
  `openRecordingAsDocument` returned, leaving a window that never became
  anything. The old recording window did the same thing differently: its
  metadata load finished with `isReady == false` and its spinner spun for ever.
- **A recording still landing on disk**, which is any big file being copied into
  the capture folder. It reads as unplayable and gets the same empty window,
  even though waiting a second would have worked.
- **A recording that is not in the capture folder at all.** History was the only
  door. `File ▸ Open` greyed movies out, the bundle declared no movie document
  type, so Finder never offered the app, and `openWindow(.file(<an mp4>))` sent
  it to the picture door, which read a video as a photograph and got nothing.

### The check

`RecordingDoor` (PhotonzCore, pure, tested) turns three facts about the file
into one of four answers, and `RecordingDoor.message(for:name:)` is the plain
sentence for each. `RecordingFileReader` (app) reads the facts:

1. Does anything exist there.
2. Can a length be read off it (`AVURLAsset`, and a video track).
3. Only when the length could not be read: does the file get BIGGER between two
   looks 0.4s apart. So a recording that plays opens after one look and never
   pays for the second sample.

`AppCoordinator.openRecording` runs the check before it opens a window. `gone`
and `unplayable` open nothing and say so by name in the corner.
`stillWriting` says it is still being saved and then opens by itself as soon as
the file finishes, for up to `RecordingDoor.patienceSeconds` (20).

A window ALREADY holding that recording skips the check entirely
(`hasOpenRecordingWindow`, a weak mark set by both window roots). What is in
that window is somebody's work, and refusing to focus it because the file was
moved underneath would lose it.

The race that survives — the file goes between the check and the window's own
load — is answered in the window: the document path calls
`onRecordingWouldNotOpen`, which says the same sentence and closes the window it
was going to fill, and the old recording window draws the sentence where the
picture would have been instead of spinning.

### One door, whichever way you ask

`openFileWindow` is where Finder, the dock, a recent item and the Open panel all
come through, so a movie is routed to `openRecording` there and every one of
them is covered at once. `File ▸ Open` offers exactly the three extensions
`CaptureLibrary.videoExtensions` names, never `UTType.movie`, which conforms to
formats the app cannot open and would just move the empty window into the panel.
The bundle declares the movie types at `LSHandlerRank: Alternate`, so Photonz
appears under Finder's Open With and can never take `.mp4` off whatever opens it
today by being installed.

Dropping a recording on the window is still refused by `FileDrop`, deliberately:
a picture dropped on an open document becomes a layer, and a recording dropped
on one should become a clip on the timeline, which is `video-cutting` work and
not a door.

### Where you were

`RecordingPlaces` (PhotonzCore, pure, tested) remembers the playhead per
recording, keyed on the file's size and modification time, at most 40 of them.
It is APP state and not document state, for the reason `MovieLibrary` is: where
somebody else got up to does not travel with the file.

It is forgetful on purpose. A moment in the first 1.5 seconds is where a
recording opens anyway, and a moment in the last second means it was watched
out; both forget the recording instead of storing something useless, so a
restart really restarts. A file whose fingerprint changed (a save wrote the trim
into it) starts over, because the old moment may no longer be in the file.

A recording nobody left off in still autoplays from the top. One you DID leave
part way through opens PAUSED on that moment: coming back to a recording is
coming back to work on it, and a clip that starts running the instant the window
appears has moved off the moment before you can look at it.

---

## 8c. Something you built, on the timeline

*Built 2026-09-21, `next-a-component-on-the-timeline`.*

This is the part no other editor can do, and the reason for all of the above:
**what you draw and what you edit are one document**, so a component you built
goes on a video timeline without being exported, converted or imported. The
chain the user asked for — "you can make an icon and use it in your component",
"you can create a component, and then show that on a video timeline" — is two
walks: `icon-into-a-component-onto-the-timeline-walk` draws an icon, makes it a
component, shares it and drops it on a recording;
`component-on-the-timeline-walk` does the rest.

It cost one rule, one bug fix and one correction.

### The rule: anything placed arrives at the playhead

`ComponentsInTime.placeInTime(_:atTimeMS:)` is the whole of it, and it is the
rule titles already had, said about everything: **something that lands in a
document with time arrives at the playhead and runs for three seconds**
(`TitleTime.placedSpan`). It refuses four cases, all harmlessly: a document with
no time in it, something that already says when it is on screen, something with
media behind it, and something dropped INSIDE a layer that is itself placed —
a part of a thing arrives when the thing does, and a second opinion is how a
part goes missing while its parent is on screen.

The three ways a component arrives each take a moment now
(`insertComponentInstance`, `adoptSharedComponent`, `insertStarterComponent`,
all `atTimeMS:`), and the app hands them one answer, `placementMomentMS`, so a
component cannot land knowing when it is on screen by one route and not by
another. It is inside the same `perform`, so the copy and its stretch are one
undo step.

Everything else was already there and needed nothing: the bar on the timeline
(a row draws a bar when its layer has a time), the Time section with Start Here,
End Here and Fade (it asks `placedLayerInHand`, never "is this text"), the
dragging of either end, `drawn(atTimeMS:)` taking it off screen outside its
stretch, and the export writing it because the export is the canvas
photographed.

### The bug: a copy did not move

`rebound` builds a copy's contents field by field, and it did not carry
`motions`. So a component whose pieces animate **stopped animating the moment it
was copied**, silently: the copy simply stood still, and nothing anywhere said
why. One line, and with it the model answers the question the animation model
was chosen against — two parts of one thing moving out of phase — for a
component placed on a film, with each copy running the animation from the moment
IT arrives rather than from the start of the recording. That last part is free:
`movedTree(atDocumentTimeMS:)` already gives a child the clock of the thing it
is inside.

What is deliberately NOT carried is a part's own `time`. A part inside a copy is
on screen when the copy is.

### The correction: a lane drawn where it happens

`motionStrip()` shifted a lane by its OWN layer's `motionShiftMS`, which is
nought for a part inside a placed component. So a badge placed at four seconds
whose pieces move drew those lanes at the start of the film: the strip said the
badge moves three seconds before it exists, while the canvas played it
correctly. The strip now carries the shift down the tree, the same inheritance
`drawn(atTimeMS:)` samples by.

### What it does not do

- **A placed thing cannot be cut in two with the blade.** A clip has frames
  behind it, so cutting it is a cut into media; a component has none, and
  `TitleTime` already refuses a speed, a hold and a split for anything placed.
  Cutting a placed thing in two would be a different gesture and nobody has
  asked for it.
- **A motion cannot be overridden per copy.** Animate the ORIGINAL and every
  copy runs it from its own in point, which is the smaller answer and the one
  that matches what a component is. A copy's own motions are its own and
  survive an edit to the original; what a copy cannot do is change the
  original's.
- **A shape drawn straight onto a recording still stands over the whole film.**
  Only components take the new rule. That is deliberate rather than forgotten:
  `an-edited-recording-comes-out-as-a-video-walk` asserts a box drawn over a
  video is in every frame, and changing what a mark drawn on a film means is a
  question for the user, not a side effect of this task.

## 9. What this deliberately does not do

Each of these will push back on the model, and the model is right when they can
be added without it changing shape.

- ~~**Transitions.**~~ **Built on 2026-09-21** (`video-transitions.md`), and the
  model pushed back exactly where it was expected to: one optional field on a
  `ClipPiece`, and `drawn(atTimeMS:)` handing back TWO layers for the moments a
  transition is running. The renderer still does not know transitions exist.
- ~~**Audio.**~~ **Built on 2026-09-21** (`video-audio.md`), and it pushed back
  on the model exactly as little as hoped: one computed property on `Layer`, one
  content case, two optional fields, and the strip drew it without being asked.
  A separated track is a layer with an in and an out, so it rides the same axis
  and the same trim.
- **Captions.** What the Title / Text tool does when the document has time.
- **Keyframes.** Already settled by the user on 2026-09-15: motion is a property
  of a layer opening into a timing surface with a lane per moving part. An icon
  animating and a clip moving are the same machinery, and the strip is already
  that machinery. **An EFFECT changing over a shot joined that machinery on
  2026-09-21** as one more `MotionProperty` (`video-transitions.md` §5): a blur
  coming on over a second is a motion like any other.
- **Trimming by dragging the end of a clip's bar OUTSIDE a trim session.** The
  bar has grips while Trim is in hand, and none the rest of the time. The quick
  nudge `video-surface.md` §10.4 describes — Select, drag the end of a clip —
  is not built.
- **Scrubbing into the spare tells you nothing new yet.** During a session the
  clip is laid out at full length and the canvas draws any frame of it, which
  is the point; what it cannot do is show the trim's own in and out marked on
  the CANVAS the way a crop darkens what it is about to lose.
