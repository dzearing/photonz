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
   not in hand is stood in for by the nearest one that is on the side the
   playhead came from, at or before the moment when playing forward
   (`MovieFramesInHand.swift`; a hand scrubbing takes the nearest, item 10). An export leaves the hand out and waits
   for every frame it writes. The renderer's incremental cache also notices a
   picture that lands, or is read again bigger, under a reference the document
   already pointed at, so the landing redraw is never answered with the old
   frame.
5. **Four decoders per recording, eight frames ahead.** One
   `AVAssetImageGenerator` takes about 40ms (up to 100ms) to seek to and read a
   3456x2234 frame, longer than the 33ms it is on screen, and reading smaller
   does not help because the time is in the decode. `MovieDecoder.lanes` = 4
   side by side read one every 14ms or so; `MovieFrameFetcher.playAheadFrames`
   = 8 keeps them busy. **Superseded for playing forwards on 2026-10-07**
   (`a-full-screen-retina-recording-keeps-up-while-it`): measured again on the
   fixture, the four lanes read 90 frames in 6.0s, about 15 a second against
   the 30 the grid shows, so the picture held one up to 16 frames old. While
   the clock plays forwards, ONE `AVAssetReader` pass (`MovieSweeper`, the same
   reader item 11 uses for a hand) reads from the playhead at the size the
   canvas shows it and files every frame sharp; the same three seconds read and
   converted in 0.45s. It paces itself `MoviePlayPass.aheadFrames` (8) ahead of
   the playhead and waits there, and is started over when the playhead goes
   somewhere it is not (a scrub, a cut back in the same recording, a pass
   fallen 4 frames behind). **Across a cut (2026-10-08,
   `a-full-screen-recording-keeps-up-as-it-plays-acr`)** a pass started on the
   far side decodes from the key frame before it, most of a second on the
   fixture, so the picture stuck at every cut (3 of 20 looks late by up to 23
   frames; 6 of 20 by up to 20 across a dissolve). The clock now keeps a
   `MoviePlayLookahead` that finds every stretch coming on within
   `MoviePlayPass.comingLeadMS` (1.5s: a cut's far side, a dissolve's incoming
   shot, a clip starting), looking only at the one new moment each tick. Each
   recording holds up to `passesPerRecording` (3) passes, planned per tick by
   `MoviePlayPass.plan`: one per frame under the playhead (two during a
   dissolve) and one opened `primeFrames` (4) into each stretch coming, which
   simply carries on when the playhead arrives. The budget grows to fit the
   passes (`MoviePlayPass.frameBudget`) and, while playing forwards, lets a
   frame gone by go before one read ahead (`MovieFrameQueue.farthest`,
   `behindWeight` 3): plain distance had been dropping the outgoing shot's
   read-ahead during a dissolve and restarting its pass from the key frame.
   Only a frame further than any pass will go is read exactly by the lanes, and
   so is everything played backwards. Only a frame at or behind its nearest
   playhead redraws when it lands. The colours match the exact read (mean
   difference 0.4 of 255, same colour space). The lateness the walk measures
   now fails it (`PlaybackKeepsUp`: more than 2 of its looks late, or any look
   more than 2 frames behind).
6. **Frames are read at the size they are shown**, in eighths of the
   recording's size (`MovieRef.decodePixelSize`), which is what lets the
   16-frame budget stay small. Zooming in reads the frame on screen again; the
   smaller one shows until the sharper one lands. A read under way only
   answers for asks at its size or smaller (`MovieFrameReads`): the first frame
   is asked for before the canvas has fitted its window, an eighth of the size,
   and until 2026-09-25 the fit's full-size ask was dropped because that small
   read was still going, so every recording opened blurred at 0:00. Writing a
   file always reads at the recording's own size.

Scrubbing (a hand on the playhead) adds five more, since 2026-09-26
(`scrubbing-is-smooth-never-goes-black-and-the-pic`, walk
`scrub-never-blacks-out-walk`, which scrubs at every display frame and
measures each one):

7. **A render draws the pictures that were there when it was asked for.** The
   frame budget used to drop a frame between the canvas choosing it and the
   render drawing it, and the clip drew as nothing. A document with time is
   submitted with `ImageStore.snapshot()`.
8. **The outline sits on the picture, not the playhead.** The composite trails
   the playhead by up to a display frame, so `canvasGeometryDocument` poses
   keyed layers at `shownMomentMS`, the moment the picture on screen was drawn
   at. Handles, outlines and clicks all sit on what you can see.
9. **One picture per refresh, drawn at the size it is shown.** While a hand
   scrubs, the first move in a display refresh is drawn at once and the rest
   wait for the next refresh (`DisplayFrames`); a landing frame never takes a
   refresh of its own. A document with time is composited at
   `CompositeScale.forShown(zoom x backing)`: a fitted Retina recording costs
   7.5ms a refresh instead of 17ms.
10. **Reads follow the hand.** At most one read per decoder lane runs; reads a
   newer moment no longer wants are dropped before they start
   (`MovieFrameQueue`); three moves ahead are read in the direction of travel;
   the budget lets go of the frame farthest from the playhead; and a frame
   still being read is stood in for by the NEAREST frame in hand, ties to the
   side the hand came from (a clock still never shows a frame from ahead).
11. **A moving hand is fed a stretch, not frames** (2026-09-27,
   `scrubbing-back-fast-keeps-the-video-picture-movi`). An exact frame costs
   a decode of every frame since the key frame before it (1.9s into a two
   second key-frame interval: 177ms), and exact reads do not run side by side
   (five at once took 700ms each), so going backwards the picture sat still for
   20 display frames. While a hand moves, `MovieSweeper` reads the 1.5s it is
   heading into in ONE `AVAssetReader` pass (a whole two second stretch, every
   grid frame kept: about 220ms) and files each grid frame at most 800 wide
   under its own reference, on a budget of its own (`MovieSweep.roughBudget`).
   No exact reads run while it moves. Holding still for `MovieSweep.settleMS`
   (30ms) or letting go stops the pass and reads the frame under the playhead
   sharp through the ordinary upgrade path (`MovieFrameReads`). The walk now
   fails if, going back, the picture sits on one frame for 10 display frames,
   or a stop takes over 250ms to turn sharp. Cancelling an `AVAssetReader`
   from another thread while it reads crashes, so a pass stops between samples.

---

### Soft gradients: smoothed where a frame becomes a picture

The Mac draws a dark translucent window (a terminal's sidebar, a sheet's
material) in 8-bit steps, so a recording that copies the screen exactly holds
a staircase: about ten shades over 1300 px, flat bands up to 160 px wide. A
deeper capture cannot add shades that were never drawn. So the steps are
blended **where a decoded frame becomes a picture**, never while recording:
`RecordingSmoothing` (PhotonzRender) runs on the GPU in `MovieSweeper.picture`
(play and scrub), `MovieDecoder.frame`/`picture` (exact seeks, the clip
filmstrip, a library poster) and, at High only, on the frames a drawn export
streams. Switch: `next-soft-gradients-in-a-recording-play-smooth`, on in Next.

- Three passes: an 8x box shrink, a 32-tap edge-aware disc blur on the small
  copy (reach 128 recording px), and a full-size apply that leaves alone any
  pixel with a neighbour more than 1.5 shades off, any one-pixel line, and any
  pixel the blur would move by more than 2.5 shades or less than a tenth.
- Display and export are both 8-bit, so a smooth ramp alone would round back
  into the same steps: a moved pixel gets up to a shade of triangular grain.
- Comparisons happen in steps of the sRGB curve inside the kernels while the
  numbers stay in linear light; matching to the picture's colours and back
  through half floats moved a pixel of text edge in ten by a shade.
- Measured on the user's recording (2026-11-16): on screen, 8 px means of the
  sidebar went from a 103 to 137 px longest flat run to 8 to 26 px; GPU about
  +1 ms a full-size 3456 frame, +0.2 ms at half size.
- **A High export writes a banded recording out smoothed instead of copying
  it** (`SmoothedCopyWriter`, PhotonzMedia; chosen in
  `EditorState.writeVideoUnswapped` by `ExportSmoothing`). An untouched
  recording, or an edit that is nothing but cuts, used to be copied byte for
  byte, steps and all. Now three frames at a quarter size are read first; when
  the pass would move 0.2% or more of a frame's pixels by a 10-bit code, the
  recording (or its kept stretches) is decoded at its own depth, passed
  through the same kernels with no grain, and encoded again as the same kind
  of file: HEVC Main 10, its own colour tags, the document's mix beside it.
  Otherwise it is still copied. The sheet says the size as "about" while the
  switch is on (`RecordingExport.Source.mayBeSmoothed`).
- The encoder is asked for a quality of 0.9 with spatial adaptive
  quantisation off. Asked for a rate it wrote a ninth of it and blurred text;
  asked for a quality with a rate cap it ignored the quality; with adaptive
  quantisation on it flattened the ramp into 32 px blocks with jumps, and kept
  or dropped added grain by chance. Grain never reliably survives it, so none
  is added: the file holds the ramp as steps of one or two 10-bit codes (a
  quarter to half of the Mac's shade).
- Measured on the user's 9.3 s recording: 121 MB copied in 0.1 s became
  32.7 MB written in 4.3 s; down the sidebar 38 levels and steps of at most 2
  codes against 27 levels and steps of 4, longest flat run 68 px (where the
  gradient bottoms out; a ramp of 31 to 39 codes over 1300 px averages 33 to
  42 px a code, so under 40 px everywhere would need grain); terminal text 9
  codes off at the 99th percentile, the same as a plain re-encode.
- What it still does not do: the recording file itself stays a faithful copy,
  so QuickTime playing the recording shows the steps; only an export from
  Photonz is smoothed. Grain does not survive H.264 at Standard's budget, so
  Standard and Small exports are not smoothed. A player that rounds 10-bit
  video to 8 bits without dithering puts most of the steps back.

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
picked, so they still nudge a layer somebody has taken hold of. That is the
canvas's rule; the timeline's own keys are below.

### Premiere's keys, and who has the keyboard

Most of Premiere's timeline keys are Photoshop tool letters here too (K the
Lens, L the Line, I Measure, O the Ellipse, A the Arrow, M the marquee). So the
window has Premiere's panel focus: **the timeline has the keyboard from the
moment it appears** (a recording opening, a clip dropped into a picture), shown
by a thin accent ring round the dock, so L plays with no click first. A press
anywhere outside the dock gives it to the canvas and the ring goes; a press in
the dock hands it back. (Until 2026-09-24 the canvas had it first, and L on a
fresh recording picked the Line tool.) The rule for every document with time is
UX-PATTERNS D4, "Which letters a document with time gives the timeline". The map is
`Sources/PhotonzCore/TimelineKeys.swift` (tested), the doing is
`EditorState+TimelineKeys.swift`, and `TimelineKeyRouter` gets a press there
before the toolbar's single-letter key equivalents can take it.

| Key | Timeline has the keyboard | Canvas has it |
| --- | --- | --- |
| Space | Play / pause | same |
| J / K / L | Play backward / stop / play forward; J or L again goes 2x, 4x, 8x | tools |
| K held + J / L | One frame back / on, and held it creeps | tools |
| I / O | Set In / Set Out at the playhead | Measure / Ellipse |
| ⌥I / ⌥O | Clear In / Clear Out | same |
| M | Add Marker | marquee |
| ⇧M | Go to Next Marker | cycle the selection tools |
| ⇧⌘M | Go to Previous Marker | same |
| ⌘B | Split at Playhead (Final Cut's Blade; ⌘K is Ask, UX-PATTERNS §7) | same |
| ⌘K | Ask, as on a picture (the user, 2026-10-24) | same |
| ⇧⌘K | Split Everything at Playhead | same |
| ⌘R | Speed: opens the picked piece's Speed list in the panel (Premiere's Speed/Duration) | same |
| ⌫ | Lift: what is picked goes, nothing else moves | delete, as ever |
| ⇧⌫ (and ⌥⌫) | Ripple Delete | ⌥⌫ only |
| ← / → | One frame; ⇧ five | nudge a picked layer, else a frame |
| ↑ / ↓ | Previous / next edit point (any in, out or cut) | nudge |
| Home / End | Start / end | same |
| V / B | Select / Blade, the timeline bar's two tools | Select / nothing |
| = / - / \ | Zoom the timeline in / out / to fit | nothing |

The Video menu prints these, and prints the plain letters only while the
timeline has the keyboard, so it never promises a key the canvas is about to
spend on a tool. A shuttle at anything but 1x forward runs silent; a frame step
is silent too, as Premiere's is by default. A is Premiere's Track Select
Forward and is not bound yet: it is only worth having once everything it picks
can be carried as one.

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

**Retired from Next on 2026-09-26.** Next has one way to open a recording: the
editor, as a document with time. `next-a-recording-is-a-document`, the switch
that chose between the editor and the small recording window, is deleted, so
nothing in Experiments brings the window back. `NextExperience.videoEditor`
hands a `.video` window id to the ordinary `ImageEditorRootView`.

**The window's code is still in the tree, and that is on purpose.** Current,
the shipping release, still opens every recording in it, and a Next task may
not change Current (see `Sources/Photonz/Releases/README.md`). So
`VideoEditorState`, `VideoEditorView`, `TrimTimeline` and `PlaybackScrubber`
are Current's alone now: nothing in Next reaches them, and they go when Next
is promoted and Current becomes Legacy.

| Thing | Where it went in Next |
| --- | --- |
| Trim | `Tool.trim` in Crop's slot, `ClipTrimSession` (PhotonzCore), `EditorState+Trim`, handles on the clip's bar in `MotionStripView`, one glass capsule in `EditorView.trimActionBar` (`video-surface.md` §10). The handles run over a cut clip's cuts, catch on them while the timeline snaps (Command frees the drag), and a handle on or past a cut throws away the pieces wholly outside it. |
| Save | A recording that lives in history saves INTO history (2026-10-07, `HistoryVideoSave`, `EditorState+HistoryVideoSave`, `CaptureStore+VideoSaves`): the edit is kept beside the tile as `<name>.photonz`, the recording as made is cloned into `.photonz-originals/` and the edit plays from there, and the finished video (High, full size, all of it) is written over the tile's file in the background, the window free to close. The corner card says Saving, then copies it. Opening the tile opens the project; an edit taken back to the recording puts the recording back. A `.mov` tile gets a QuickTime `.mov`. Unfinished writes are listed in user defaults and finished at the next launch. A recording NOT in history saves a project through the save box (§8a) and its file is never written over. |
| Save a copy | File ▸ Save As, a project. |
| Export | The video sheet, `VideoExportDialog` (§8). |
| Revert to Original | Video ▸ Revert to Original (`EditorState+RevertRecording`): every edit thrown away, back to the recording as it opened, as one undo step. Dimmed until something has changed. |
| Crop | The ordinary Crop tool, on the canvas, as for any layer. |
| The two old-window guides | `trim-a-recording` and `export-a-recording` are gone: tutorials are Next-only, and they only ever showed with the switch off. The editor's six video guides replace them. |
| The old window's walks | The eleven trim walks were rewritten against the editor and pass; `opening-a-recording-walk` passes unchanged on the editor. The seven that only described the old window's own chrome (its cut strip, its button row, its export sheet, its save toast) were deleted; `cut-on-the-timeline-walk`, `delete-key-drops-a-timeline-piece-walk`, `an-edited-recording-comes-out-as-a-video-walk` and `command-s-saves-a-video-project-walk` cover the same ground in the editor. |
| `VideoCutList` | **Reused.** `ClipPieces(cutList:)` projects a cut recording straight into the document model. |
| `VideoExporter`, `VideoAssetCommit` | Current's recording window only. A document with time leaves through `DocumentMovieWriter` (§8). |

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

## 8a. Keeping an edit: the project

File > Save As on a video writes a `.photonz` package like any other document:
`document.json` holds the whole edit (tracks, pieces, transitions, keys, titles,
captions, sound levels). It never holds a frame: a clip layer's picture is the
frame under the playhead, fetched from the recording, so `PackageIO` skips clip
layers when it collects bitmaps. Beside it, `media.json` (`ProjectMedia`, core,
tested) lists each recording and sound the edit plays or holds on its shelf,
by the id the document knows it by, with its full path and its path relative to
the project's folder. Recordings are pointed at, never copied in and never
changed, the way a Premiere project points at its footage.

Opening a project resolves every row, first where it was saved, then the same
place relative to wherever the project is now (a folder moved whole to another
disk still opens whole), and files each found one back with `MovieLibrary.adopt`
/ `SoundLibrary.link` under its saved id BEFORE the document is installed. A row
found in neither place leaves its clips blank and is named on a sheet on the
window; the project still opens.

Command S on a video saves the project (the card answered 2026-09-25, option a):
it never writes over a recording. On a recording that has never been saved,
Save is live and opens the save box for a `.photonz` project, exactly as Save on
any untitled document does and as Premiere does on an untitled project
(`SaveAffordance.unsavedRecording`). The close sheet on an edited one is the
ordinary save question with Export… beside Save…, so a trim to send is still
one button from the sheet. Once saved, the window is an ordinary package and
Command S saves it in place. Walk: `command-s-saves-a-video-project-walk` (a
plain trim and a multi-clip edit, each checked on disk, the recording byte for
byte unchanged).

Walks: `a-video-edit-saves-as-a-project-walk` (edit, export, save, close,
reopen, the document must equal the saved one, play, export again, Command S),
`a-project-whose-files-moved-walk`, and the close sheet in
`a-recording-opens-in-the-editor-at-defaults-walk`.

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

## 8d. The reference edit: what every speed fix measures

A speed fix needs the same long, busy edit before and after, so its numbers
mean something (objective `video-perf`). `ReferenceEdit` (PhotonzCore) lays
it out from a seed, with the model's own operations and the shared title and
transition catalogues: four screen recordings at 3456 x 2234 cut onto V1,
inset over a liquid-gradient background track, picture-in-picture b-roll on
V2, titles on the Title track (an opening page on a moving background, a name
card and a chapter card every six minutes, an end card), dissolves at most
cuts with a push, a cube and a flip in every twelve, a zoom on every third
clip, each clip's own sound and music under the whole edit. The same seed
gives the same document, ids and all. It comes at 6, 20 and 60 minutes; the
long ones are the recipe carried on with fresh cuts, about 37 cuts every six
minutes, 524 clips in the hour.

`ReferenceFootage` (PhotonzMedia) draws and encodes the recordings once per
Mac (60 fps H.264, a voice-like sound, two minutes of music), into a folder
named for `ReferenceEdit.recipeVersion`, so changing what they look like means
bumping it. `Scripts/perf/reference-edit.sh 6|20|60` writes the project and
opens it in the probe; a walk says `"setup": { "referenceEdit": 6 }`;
`ReferenceEditTool --sheet` draws twelve moments of it through the renderer.

The builder places clips straight onto their tracks and fits each transition
on its two clips alone, because at an hour long `land` cost about 40 ms a clip
and `setTransition` about 100 ms a cut: the track layout is worked out again
on every call. That cost is the app's too, and is the speed tasks' to remove.

## 8e. The speed walk: how a speed fix is judged

`speed` steps (`Sources/Photonz/Playtest/PlaytestSpeedWalk.swift`, counted by
`SpeedWalk` in PhotonzCore) use the reference edit the way a person does and
write every number into one `speed.json`:

- **play**: frames due on the app's 33 ms clock against the different moments
  the canvas actually showed, dropped frames, the worst wait between two new
  pictures, the same for each transition (a stall over a cut is charged to the
  cut, even with no look inside it), what the sound engine left out, and how
  long the renderer took to draw each picture it was asked for.
- **scrub**: the playhead dragged end to end in 5 s, 2 s and a third of a
  second, and hunted across 10 s of the edit in 2 s. The hand moves by the
  clock, as a person's does, so a stall shows as the picture trailing the
  hand, in display refreshes, three ways: **lag** (the moment the picture is
  stamped with; a stand-in counts as caught up), **frame lag** (only a picture
  drawn from the very frames under the hand counts) and **sight lag** (what a
  person sees: how many refreshes from the hand the recording frames the
  picture is drawn from are, along every frame the hand crossed, stand-ins
  and key frames included; `SpeedWalk.sightLags`, `SpeedWalk.handPath`).
  Sight lag is the scrub bar's number.
- **edits**: trim, move, blade, undo, a transition and a title's words, each
  made just ahead of the playhead while it plays, with the longest main thread
  pass from the edit to 1.5 s after.
- **idleBuilds**: view bodies built per new picture while it plays untouched
  (`ViewBuildMeter`).
- **timeline**: refresh times zooming in and out and scrolling end to end.
- **memory**: footprint and resident once a second for ten minutes of play,
  the hand taking the playhead elsewhere every half minute.
- **export**: wall time at the export sheet's defaults (MP4, Standard, Full).
- **compare**: the run against a baseline file; fails on any number worse by
  more than a margin (50% by default, 100% in the short walk) plus a floor in
  its own unit (`SpeedCompare.slack`). A transition's own worst gap is shown
  but not judged: the whole run's worst gap already bounds it, and which cut a
  multi-second stall lands on is chance.

Every measure is capped in time, so an app that cannot keep up still ends the
walk with a number rather than a timeout. The short form,
`Scripts/playtest/speed-walk.json`, is in the walk set: a minute of play across
six transitions, one medium scrub, a trim, a blade and an undo, judged against
`Scripts/perf/baselines/short-6.json`. A speed fix that makes it faster writes
a new baseline with `Scripts/perf/speed-walk.sh --baseline`: three short runs,
the worst of them number by number (`SpeedRun.envelope`), because while stalls
last seconds one run differs from the next by half again (the whole run's
worst gap read 17 to 28 s across four runs of one build on 2026-11-12). The long form (`Scripts/perf/speed-walk.sh --long 6 20 60`, walks in
`Scripts/perf/walks/`) is a command and never in a sweep;
`Scripts/perf/compare.sh before.json after.json` sets two runs side by side.

### What a hand on the playhead is shown (2026-11-17)

A recording keeps a whole picture only every so often (about every two seconds
in a Mac screen recording); any other frame is decoded from the key frame
before it. So the frames a moving hand is shown depend on how fast it moves
(`MovieSweep`, `MovieKeyFrames`, `MovieFrameFetcher.sweep`):

1. **Hunting** (under ten seconds of the edit a second, `MovieSweep.glimpses`):
   the stretch it is heading into is read in one pass, small. Only frames the
   hand has not passed are made into pictures (`MovieSweep.worthShowing`):
   making the picture is most of a frame's cost, and a hand at five times
   playing speed kept pace with a stretch that made every one. Clips it is
   about to cross into are looked for a quarter second of its pace ahead
   (`MovieSweep.cutReachMS`), and a read for a recording the hand has left
   stops, since it shares the decoder.
2. **Dragging fast** (over ten seconds a second): the key frame nearest the
   hand, read on its own at exactly its moment in the file, one read at a
   time. At three minutes of the edit a second a key frame a second of film
   away was under the hand less than a refresh ago; a stretch started at every
   move instead piled eight reads into the decoder, each taking 200 to 600 ms
   to show anything. QuickTime Player does the same. Since pass 15:
   - aimed where the hand will be when the read lands, 25 ms of its pace
     ahead (`MovieSweep.glimpseLeadMS`), so a clip it is about to cross into
     is read before it gets there;
   - the nearest key frame the clip PLAYS (`MovieKeyFrames.nearest(to:within:)`,
     `Layer.playedSourceSpanMS`): the nearest at all is often just before the
     clip's first frame, a picture the edit never shows;
   - one per clip on screen, not per recording, the clip that waited longest
     next: two takes of one recording in a dissolve each need their own;
   - every recording's key frame table is read when a hand takes the
     playhead, not when it first meets the recording.
3. **Holding still** for 30 ms: the frame under the hand, sharp. Once the
   sharp frames are in, the second around it is read small and filed quietly
   (`MovieSweep.restingWindow`, `MovieFrameFetcher.readAroundRest`), so a hunt
   from rest has a picture for its first move instead of the frame it started
   on for a fifth of a second.

Every frame a recording shows on screen at once counts as where its playhead is
for the small frames' budget (`MovieFrameFetcher.focus`): kept to the first,
the second take in a dissolve had each key frame let go the moment it landed.

**The reference edit's recordings need ids that differ in their first eight
bytes.** A frame's picture id is its recording's id with the frame number
folded into the last eight (`MovieRef.frameID`). Until 2026-11-17 the
reference recordings differed only in their last byte, so they shared picture
ids, a scrub drew one recording's frame where another's belonged, and every
scrub number before pass 15 was measured on frames shared between recordings
(honestly measured, the medium drag's worst sight lag was 163, not 67).

### What a composite may hold between frames (2026-11-18)

**Anything drawn on more than one frame lives on a GPU surface, never in a
plain bitmap.** Core Image copies a bitmap's bytes into GPU memory on every
render that draws it, however long the CIImage made of it is kept; a surface
(`IOSurface` behind a `CVPixelBuffer`) it reads where it is. Two such copies
were most of the composite's time on the 6 minute edit: every decoded frame
was read back off the GPU into a bitmap and copied in again by each composite
that drew it, and the moving background's full-frame mask (3456 x 2234,
30 MB) was copied in on every frame. Now a decoded frame is drawn onto a
surface of its own and registered with it (`FrameOnASurface.draw`,
`ImageStore.register(_:as:surface:)`), and a kept raster of 512 x 512 pixels
or more is copied onto one once (`FrameOnASurface.keep`), with the same
pixels exactly. Composite median 8.6 -> 5.5 ms. To find the next one: attach
lldb to the probe, break on `CI::MetalContext::bind_cgimage` and print `x1`:
a pointer that comes back on every frame is a bitmap being copied in every
frame.

## 8f. Who may watch the playhead

While a video plays the playhead moves thirty times a second, and everything
that watches it is woken thirty times a second. What that costs is not the
views woken. **Every pass SwiftUI makes over the window costs about as much
again as the timeline has views, whatever started the pass.** On the 6 minute
reference edit (2026-11-13), playing 20 s showed 500 of 606 frames; hiding only
the tracks showed 605, even with every per-tick view still updating, and
counting bodies showed that not one clip, track or row body ran while it
played. The cost is SwiftUI walking a big graph once per pass, so the number of
passes per frame is what to keep down, not only what each one rebuilds.

The rule, for any view added to the editor window:

1. **What moves with the playhead inside a clip is not a SwiftUI view at
   all.** The playhead line, the scrub bar's played part and knob, the
   transport's time and the time scroller's mark are drawn with Core
   Animation layers by `VideoKit.LayerIsland`, which reads and watches the
   playhead itself, outside any pass of the window's, and moves its layers
   only when what they show changes (rounded to half a point, a whole
   second). As small SwiftUI views of their own they still made one window
   pass each per frame and per move of a scrubbing hand, and so did small
   SwiftUI hosts of their own (`NSHostingView` in a representable): a host
   that draws again is laid out again, and the window's host with it. On the
   6 minute reference edit (2026-11-13) a medium scrub was answered at 73 to 82
   of the display's 240 refreshes with them as views, 94 to 108 in hosts of
   their own, and 232 to 241 as layers. A new thing that has to follow the
   playhead every frame is a `LayerIsland`, never a view that reads it.
2. **A view that shows what the playhead is ON (the clip, piece, cut, speed
   stop, title in hand) watches the answer, not the clock.** The answers are
   worked out on every tick but written only when one changes, and the view
   reads the playhead unwatched inside the matching scope:
   - the menu bar: `MenuPlayhead`, `EditorState.beginMenuRead`;
   - the panel: `PanelPlayhead`, `readingThePlayheadForThePanel`
     (`EditorState+PanelPlayhead.swift`); the Time section and the facts that
     decide the panel's cut rows read through it;
   - timeline right-click menus: `timelineMenuRows`, built again on each
     right click instead.
   If a new view needs an answer that is not in one of those values, add it
   there rather than reading the playhead. The panel's answers wait while a
   hand is moving the playhead and catch up once it holds still for
   `MovieSweep.settleMS` or lets go (`catchUpPanelPlayhead`): a quick scrub
   crosses a clip on nearly every move, and following each one cost the
   scrub two thirds of its refreshes.
3. **Something that needs the playhead only when it draws asks for it then.**
   The canvas reads `documentTimeMSUnwatched` through a closure
   (`CanvasView.documentTimeMS`) instead of being handed it, because every new
   picture redraws its chrome anyway.
4. **A playing or scrubbed frame reaches the canvas without SwiftUI.**
   `EditorState.showPlayingPicture` puts it straight on the canvas's layer and
   keeps `renderedImage` and `shownMomentMS` up to date without telling their
   watchers, then tells them once when play stops or the hand lets go
   (`catchUpOnQuietPictures`). It steps aside, and the frame goes the usual
   way, whenever something else on the canvas could change with the picture
   (something picked, a drag, a stroke landing, a crisp tile up).
5. **Never write an observed property with the value it already has** on a
   path that runs per frame: `@Observable` tells every watcher about a write
   whether or not the value changed, and that is a pass.
6. **An edit made on a video draws the picture in its own pass, and the
   timeline's tracks and the panel follow in the next.** `perform` marks it
   (`catchUpOnTheNextPassOnAVideo`, as Undo and Redo already did), unless
   the edit is a drag being let go, whose bar would spring back for a frame
   (`isHandLettingGo`). On the 6 minute reference edit (2026-11-14) a trim or
   a move while playing held the window 30 to 35 ms in one pass, and about 18
   in two. Until 2026-11-15 this waited for play; stopped, with a clip
   picked so the panel holds its ten sections, a trim held the window 54 to
   55 ms in one pass and 31 to 44 in two, so it no longer does. A new view
   that reads the document belongs inside `readingALatePass` if it shows the
   timeline or the panel.
7. **A view per clip reads nothing off the editor itself; its lane hands it
   values, and makes it only for a clip with something to draw.** Every view
   that reads the document is woken by every edit to any clip, so 55 empty
   part-timing views (`TimelineChildMarks`) ran on every edit until the lane
   worked out the marks and made views only for the clips that have them.
   The same holds for anything that changes only at a key or a hold: the
   header key diamond, Add Key and the held-frame badge watch their answers
   in `PanelPlayhead` (rule 2), where they had rebuilt on every tick of a
   video played with a clip picked.
8. **A busy lane paints its plain clips and cuts; a clip somebody is working
   on is its full view again.** A lane builds only what is in sight plus half
   a window each side (`TimelineSight`). When 24 or more clips are in sight,
   or its track holds 24 or more in all (`TimelinePaint.busyLane`, so a long
   track paints at every zoom), it paints the plain ones and the cuts between
   them in two Canvas layers (`TimelinePaintedClips`, `TimelinePaintedCuts`),
   because a bar per clip was the whole cost of zooming the hour-long edit
   (570 ms a frame built, 50 painted, 2026-11-14). Plain is a picture clip
   (pictures along it included, read from `ClipFilmstripFrames` and faded in
   as they land) or a sound of its own on the panel's ground, with its name
   tag (2026-11-15), or a title, and every track of a long edit paints,
   however few clips it holds (200 or more in the edit,
   `TimelinePaint.longEdit`: the hour-long edit's 22 titles were 4 to 6 ms of
   a frame near the whole-hour view, 2026-11-16). A clip goes back to its full
   view when it is picked, in a hand, being trimmed or renamed, or under the
   pointer, and when it carries anything the painting does not draw (pieces,
   a still, a badge, keys, a drift, level points, a sound badge); a cut goes
   back when it is picked, under a grip, under the
   pointer, holding on black or white, or one of its clips is in a hand. So:
   - **Everything a clip bar shows is drawn twice**: once in `ClipPiecesBar`
     and once in the painting. A new thing on a clip either is drawn in
     `TimelinePaintedClips.paint` too, pixel for pixel, or is added to
     `TimelinePaint.Clip` so a clip carrying it stays a view. Never only the
     bar: it would vanish on a busy lane.
   - **What is under the pointer is read again when the timeline moves**, not
     only when the pointer does. A pointer held still while the timeline
     scrolls or zooms is over something new with no move to say so, and a
     click there must reach the cut or clip now under it
     (`TimelineTrackRow.readPointer`, `a-cut-slid-under-a-still-pointer-walk`).
   - **The painting is laid on the drawn stretch and slid, not painted
     again, by a scroll** (`TimelinePaint.Canvas`): it covers every clip and
     cut on `timelineDrawnMS`, measured from where that starts, and the lane
     offsets it to a whole pixel. Only a name that can be pushed along by the
     lane's left edge in this stretch (`TimelinePaint.nameFollowsTheEdge`) is
     drawn against the window, by `TimelinePaintedNames`, every frame.
   - **While the timeline zooms, the painting covers only the window**
     (`TimelinePaint.paintedMS`, `EditorState.timelinePaintsTheWindow`): a
     change of scale paints every lane again whatever the canvas covers, so
     after a zoom the canvas is the window and a thirty-second of it either
     side, and the first move along at the same scale puts it back on the
     wide stretch. Zooming the hour-long reference edit painted two and a
     half windows on every frame until then: 16 to 18 ms a frame, 12 after
     (2026-11-16). What is built past the painting follows it (`builds`).
   - **A strip fades in only when it appears on a clip that was already
     painted**, as a zoom in brings a clip's pictures up. A clip that slides
     in with a scroll or a zoom out brings its strip with it, drawn at once,
     and noting it paints nothing (`TimelinePaintedClips.Painted`, kept out of
     the view's updates). Each such clip was a fade, and a fade paints the
     whole canvas on every frame for a fifth of a second: on a fast scroll
     clips came onto the stretch every other frame, so the painting a scroll
     only slides was painted on every frame (15 ms a frame, 12 after,
     2026-11-16).
   - **Fixed pieces of time, each its own canvas, are slower, not faster**:
     tried on 2026-11-16 with half-window pieces in view only. Each canvas is
     a texture of its own, and a zoom resized every one of them on every
     frame: scroll and zoom both went from about 16 ms a frame to 25.
   - **Past the stretch, a painting lane builds nothing but what somebody is
     working on** (`TimelinePaint.builds`). The sight reaches up to half a
     window past the stretch either side, all of it off screen, and near the
     whole-hour view every clip and cut there was built as a full view on
     every frame of a zoom: 4x went from 58 ms a frame to 22 (2026-11-16).
   - A painted clip takes a click, a drag and a right click of its own
     (`TimelinePaintedHands`), for the click that comes with no pointer move
     first; a grip, a fade diamond or the level line is reached only on the
     full view, which the pointer resting there has already brought back.
   - **What a clip or cut is, the painting reads off the document once**
     (`TimelinePaintedFacts`), kept until the document's layers or tracks
     are written (`PhotonzDocument.sharesWorkedOutAnswers`) or a switch it
     names flips: its pieces, badges, keys, holds, fades, level, the sound it
     plays, a cut's band. Only where it is and what the view does to it
     (picked, under the pointer, how strongly its pictures show, a cleaning
     in progress) is worked out each frame. Looked up afresh on every frame
     of a zoom it was a fifth of the frame near the whole-hour view
     (2026-11-16). A new fact read from anything but the layers and tracks
     (a library that loads later, an editor setting) is either read each
     frame beside the cleaning progress or added to its `Switches`, or a
     painted clip goes on showing the old answer.
   - **A lane that paints its clips paints its gaps too**, under the clips on
     the same canvas, and builds a view for one gap only: the one under the
     pointer, with no look of its own, carrying the gap's press and its
     right-click menu (`TimelinePaint.gapViews`, read again with the pointer
     by `readPointer`, `a-painted-gap-takes-a-right-click-walk`). Each gap
     was a striped Canvas, a dashed edge, a press and a menu: near the
     whole-hour view the Title and V2 lanes held about seventy, rebuilt and
     drawn as separate layers on every frame of a zoom, 5 ms of a 22 ms
     frame (2026-11-17). Their stripes are one clip and one fill per lane;
     each edge is stroked on its own, because one dashed path through every
     gap carries its dashes on from one edge into the next. A painted gap
     runs off the window's edge as a painted clip does, where a gap's view is
     cut at the edge.
   - **Nothing a painting lane reads on every frame is worked out again from
     the clips.** Which clips are shaded as alternates is part of the row
     (`TimelineTrackRowModel.alternates`), made with the rows once per
     document; a cut is told by its two clips (`TimelineCutKey`), never by
     its `id`, which builds text out of both clip ids each time it is read;
     a closure handed to `map` or `sort` inside a view's paint checks it is
     on the main thread once an element, so a loop over points is a plain
     loop in a `nonisolated` helper. A band's shadow is cast by its opaque
     base, not by a layer of its own. Together about 1 ms of a 16 ms frame
     near the whole-hour view and of an 11 ms scroll frame (2026-11-17).
     What is left near Fit is spread thin: the paint of every clip is about
     2 ms, rasterising the lanes about 3, SwiftUI's own upkeep the rest; no
     single element of the paint (waveforms, level lines, names, clipping,
     shadows) was worth more than 0.5 ms switched off on its own.
   - **A lane that paints its clips draws its gridlines on the same
     canvas**, first, under the gaps and clips, across the whole drawn
     stretch at the window's step (`MotionStripRuler.secondTickMS(across:)`,
     `TimelinePaintedClips.gridlines`), so a scroll slides them with the
     clips. As a shape of their own they were drawn again on every frame of
     a scroll and a zoom, for about six lines a lane: 0.1 to 0.5 ms of a
     near-Fit zoom frame and of a scroll frame on the hour-long edit, in
     four paired runs (2026-11-17). A lane with nothing painted keeps
     `TimelineGridlines`.
   - **Where a near-Fit zoom frame goes**, measured on the hour-long edit by
     switching parts off (2026-11-17, about 17 ms a frame then): with every
     lane empty the window takes 8.4 ms a frame (p95 8.9), at the display's
     120 Hz; the lanes' views without their canvases add 2.5; the canvases'
     views, drawing nothing, 1.6; what the canvases draw, 4.5 (the clips'
     fills alone about 1.5; the rest a thousand small fills and strokes, no
     one of them worth half a millisecond). So the window outside the lanes
     is already at the bar, and what is left is the lanes' own drawing and
     SwiftUI's upkeep of them, spread thin.
   - **Tried and left out** (2026-11-17): painting each lane's cuts on the
     clips' canvas, one layer rasterised a frame instead of two, saved
     0.35 ms near Fit, but only with the cuts drawn over the click ticks,
     which a full lane draws over its bands; keeping the bands over the
     ticks meant reading where every tick falls on every frame, which cost
     what the merge saved. Rendering the canvases asynchronously saved about
     0.4 ms; it was not kept because such a canvas may present what it drew
     after the frame that moved it, which on a scroll would be a jump of a
     whole stretch for a frame (not watched for, only reasoned).
9. **Nothing per clip reads the window unless it is near it.** A scroll
   writes the window every frame, so whatever reads it is built again every
   frame. A clip's bar is handed the stretch it draws across by its lane, cut
   to the clip, or its whole span when it is no wider than two windows
   (`TimelineDrawnStretch.cut`), so a bar wholly in view is not built again
   for a scroll. A row that lives outside the lane (a track's Zoom lane) first
   asks the rows' sight (`EditorState.timelineRowsSight`, `TimelineSight.rows`:
   the window and two more either side, moved in steps of two windows and
   more) and reads the window only when something of its own reaches it; the
   hour-long reference edit's 126 Zoom lanes were each built on every frame
   of a scroll (2026-11-15). Scrolled out of the tracks' view (more than a
   few rows past its top or foot, `TimelineSight.rowShows`), such a row reads
   and draws nothing at all, so a zoom leaves it alone: the 126 lanes, a
   handful on screen, still cost 6 to 10 ms of every frame of a zoom at every
   zoom level until they did (2026-11-16). A new row per clip under a track
   follows the same rule. Since 2026-11-18 a track has ONE Zoom lane, holding
   the bars of every zoomed clip on it side by side (a clip's zooms stay
   inside the clip and a track's clips do not stack), so the hour-long edit
   has one Zoom row under V1 where it had 126; the lane still asks the rows'
   sight before it reads the window.
10. **A pick wakes the track it left, the track it landed on, and those two
   clips; nothing else on the timeline reads the selection.** The grid works
   out each track's share of the pick (`TrackPickShare`: picked on its header,
   in hand, which of its clips and sounds are picked, the single pick and the
   layer its header's key diamond keys) and hands it to the row, which is
   compared for equality, so a track the pick did not reach is not built
   again. A clip bar asks `EditorState.isClipPicked`, a watch of its own that
   only the clip the pick leaves and the one it lands on are told about,
   never `selectedLayerID`. On the 6 minute reference edit (2026-11-16) a
   pick from one clip to another built all five track rows and lanes and
   seven to nine clip bars and held the window 36 to 41 ms; with this it
   builds one row, one lane and one bar and holds it about 31. A new thing
   on a track row or a clip bar that depends on what is picked reads it from
   the share or from the clip's watch, or is added to them.

Measured with these in place (short speed walk, 2026-11-13): a minute of 1x
play dropped 4 of about 1,820 frames, against 379 before; every transition
played without a dropped frame. With the layer islands and the panel waiting
for the hand (later the same day): the worst of three runs dropped 4 a minute,
and a medium scrub showed the frame under the hand 2 display frames after it
moved in the middle and 4 at worst, against 8 and 21. With rules 6 and 7
(2026-11-14): 1 dropped a minute, worst gap 67 ms; trim, blade and undo while
playing 33, 85 and 62 ms at worst, against 87, 223 and 119. `ViewBuildMeter`'s `idleBuilds` and the play
measure of `Scripts/perf/speed-walk.sh` are how a new view is checked against
this.

**What the 30 ms left in an edit's own pass is not** (2026-11-14, pass 5 of
`a-long-edit-with-transitions-plays-scrubs-and-ed`). With rules 6 and 7 in
place a trim while the 6 minute edit plays still holds the window about 30 ms
in its own pass, and a SwiftUI pass with no body run at all follows it at
about 20 ms. Taking pieces out one at a time, behind a file switch, on the
same build:

| shown | trim | blade | undo |
| --- | --- | --- | --- |
| the whole window | 30 | 53 to 58 | 59 to 62 |
| no timeline | 12 to 17 | 25 to 33 | 31 to 34 |
| no panel | 17 to 28 | 36 to 39 | 35 |
| neither | 7 to 9 | 12 to 13 | 7 to 12 |
| lanes empty, the rest of the timeline kept | 18 to 21 | 35 to 40 | 39 to 42 |

and things that changed nothing measurable: no clip bar rebuilding at all on
an edit (36 bodies down to 2), no click ticks on the lanes, the panel's body
not run in the edit's pass, and three thumbnail caches no longer rewritten by
every edit. So the cost is not bodies rebuilding: the edit's pass costs about
as much as the window has views, whichever of them it touches. The profile
agrees: the pass is AttributeGraph dirtying and walking attributes
(`ObservationGraphMutation.apply`, `propagate_dirty`, `UpdateStack::update`),
then the hosting view's layout and display list, with almost no app code in
it. What would move it is fewer views in the lanes and the panel (paint what
nobody is touching, as busy lanes already do) or the timeline in a graph of
its own that an edit's pass does not walk; which of the two is the next pass
of that task. The speed walk's edit line now lists every pass of 6 ms or more
after an edit, with what it built (`MainThreadMeter.longPasses`); that list,
and watching each editor property with `withObservationTracking` during one
edit, were the tools that settled it. lldb breakpoints on property setters
did not work on the probe.

**What a graph of its own for the tracks does not do either** (2026-11-14,
pass 6). The timeline's whole grid of tracks was put in an `NSHostingView` of
its own, a separate SwiftUI graph the window's pass never walks, with the dock
reading the rows and the sound plan a pass late so it did not hand that host a
new root in the edit's pass. A trim while the 6 minute edit played still held
the window 27 to 28 ms in its own pass, a blade 51 to 54 and an undo 55 to 57,
the same as with the tracks in the window's graph. So the edit's own pass is
not the window's graph being big: it is the views that are woken by the edit's
writes, wherever they live, plus the window's render. Do not try the separate
host again for this; find what the edit wakes.

One that was found that way, and is rule 2 again: the panel's Properties
section named the piece of the clip under the playhead by reading the clock
(`clipPieceInHand`), so with a cut clip picked it was built again on every
tick of play, 44 to 46 times in the second and a half after a blade. It reads
the piece through `readingThePlayheadForThePanel` now and is built once or
twice. And one value per kind of answer: the key diamond and Add Key's
answers had been put in `PanelPlayhead` beside the clip, piece and cut, so a
key added built the Time section again (`keyframe-anything-walk`); they are
`PanelKeyPlayhead` now, read with `readingThePlayheadForThePanel(keys: true)`. The three questions drawing a moment asks of the whole tree (does
anything fade, zoom or show its clicks) are kept beside the document
(`DocumentDerived.TreeFacts`) instead of copying every layer three times on
every tick.

**What a pick of a clip costs after the edit** (2026-11-15, pass 7). A
blade on a clip nothing had picked yet held the window about 50 ms in its own
pass and then kept it busy for another 450: the clip's ten sections arrive
one per pass (`PanelSectionArrival`), and each one is unmeasured in the pass
it arrives in. While any section above it was unmeasured, the Library's pane
at the foot of the panel forgot it was folded and drew at its chosen 163 pt,
then went back to its 45 pt header the pass after: a bounce on screen and two
more window passes for every section. It now stays where it was last drawn
until the section is measured (`PanelShelfPane.drawnHeight(lastDrawn:)`).
That took the panel's builds after the first blade from 35 to 31 and the
bounce off the screen, but not the half second: what is left is a window pass
per arriving section, 15 to 65 ms each, the biggest when Appearance and
Effects arrive. A later blade on the same clip builds the panel 7 times, not
31. Pausing costs 6 to 9 ms; a blade made while stopped with the clip already
picked still holds the window 47 to 75 ms, and the undo after it 56 to 66,
against 31 to 44 for a trim, so the extra is the piece the blade picks and
the undo hands back, not the cut.

**The piece a cut picks follows a pass later** (2026-11-15, pass 8). A cut,
a hold and an undo that stays on the same clip pick a piece; on Next's videos
that pick reaches the views (the ring round the piece, its rows in the panel)
one pass after the edit, while every command reads it at once, so B then ⌫
still throws away the piece the cut handed you
(`EditorState.pickPieceAPassLater`: `selectedClipPieceIndex` answers the owed
pick, `pickedPieceShown` is what views watch). With the recording picked and
playing, the blade's longest pass went from 42 to 45 ms to 29 to 36 (one run
44), level with a trim's 28 to 33; the undo after it from 43 to 46 to 38 to
45. What is left in that undo's own pass, against about 20 for the undo of a
trim, is the clip going from two pieces to one: a Time Profiler run over six
of each showed the extra spread through SwiftUI's own graph and layout work
with no view of ours above 2 ms. A new edit that picks something as it lands
on a video picks it this way.

The speed walk had been charging the edit after a blade for starting play
again: the blade stops play, and the next edit was made in the same turn as
the restart. Play now has a second to get going first (as a person presses
Space, watches, then edits). That alone took the undo after a blade from 57 to
61 ms to 38 to 46. Its `pick` edit picks the recording under the playhead,
and every edit after it is counted again under its own name with ", picked"
on the end; the short walk makes its trim, blade and undo both ways.

**The ruler watches its own facts, and a pick carried into the history is no
edit** (2026-11-15, pass 9). A census of every read of the document made in an
edit's own pass (a stack written per read, in a temporary probe build) found
that about nine reads in ten came through the timeline's ruler: every clip
bar, its pieces' names, every cut, click tick, zoom lane and the time scroller
asks `motionStripRuler` where it is, and the ruler read the whole document for
its length (and, with a clip picked, for the end of its Source ghost). So
every edit woke every one of them in the edit's own pass, whatever rule 6
said. The ruler now reads `rulerDocument`: the document as a hand shows it
while one is in a trim, a clip drag, a speed stop or a caption word, and
otherwise the stored document watched only through `rulerDocumentRevision`,
which moves on when the ruler's facts change (has time, length, the furthest
Source ghost for the pick as it is), a pass late for an edit that follows one.
The click ticks, a cut's view, a zoom lane, a clip bar's pieces, bands and
grips (rows of a `ForEach`, built outside the body that holds them) and
anything drawn on its own (`DrawnOnItsOwn`) read the document late. Handing
`ClickTicksView` its ticks from the lane as an Equatable view, as rule 7
asks, stopped the tick drag in `a-click-tick-is-hidden-and-slid-walk` from
sliding the click, on 2026-11-14 and again on 2026-11-15, cause not found; it
reads for itself, late, until somebody finds why. Reads in that pass went from about
9,500 to about 1,200 over the same six edits.

The second find was a write to the history that changed nothing. The first
edit after a pick carries the pick into the history before it marks itself to
follow a pass later (`flushSelectionToHistory`), and that write moved
`latePassRevision` on as if the document had changed: the whole timeline was
built in the edit's own pass and again in the next. A history write that
leaves the document equal to what it was moves no revision now. On the 6
minute edit, trims and undos one after another while it plays: the first trim
of the session 26 ms in its own pass to 13; the first trim after a pick 31 to
24 at worst; a run of trims with nothing picked about 11 in their own pass
and 17 to 19 in the timeline's pass after it.

So two more things to keep, beside rules 1 to 8: **a value many views read
(the ruler, a length) is worked out from facts that change only when it does,
and watched through those**, never through the document; and **a write to an
observed property that leaves its meaning as it was is not a change** (rule 5
for the history). The longest pass after an edit is now the timeline's own
late pass, where every clip bar in sight is built again because each reads
the document through `latePassRevision`; a clip bar handed its own values by
its lane, as rule 7 asks of every view per clip, is what would take that pass
down next.

**Each clip bar watches its own clip** (2026-11-16, pass 10). A clip bar
(`ClipPiecesBar`, its pieces, bands and grips) is built inside
`readingForAClipBar(layerID)`: a read of the document there watches that
clip's own `ClipBarWatch`, not `latePassRevision`. The watch moves on in the
same late pass as the rest of the timeline, but only when the edit changed
what the bar draws (`PhotonzDocument.clipBarsChange(since:)`, tested in
`ClipBarsChangeTests`): the clip's own values, plus the clips on its track it
touched before or touches now, since an edit point there may have come or
gone. Anything else (a clip added, taken away or reordered, a track, a hold
that pushes the picture alone, which puts drift marks on other bars, anything
outside the layers) moves every watch. A temporary build with the bars
watching nothing showed the size of it first: on the 6 minute reference edit
the timeline's pass after a trim went from 18 ms to 12 with 18 to 20 bars no
longer built. Shipped, a trim's longest pass went from 18 ms to 13, with a clip
picked from 18 to 13, and that pass builds 1 or 2 clip bars where it built 18
to 20.

So, for rule 7: **a view per clip that has to read the document reads it
inside its clip's scope**, so the document it watches is that clip's, and a
new thing a bar draws from outside its own clip is added to
`clipBarsChange` (and its test) in the same change, or it will go stale.

**The ruler does not watch the pick** (2026-11-16, pass 10). The room the
ruler leaves past the end for a picked clip's Source ghost was worked out
inside the ruler, which read which clips are picked, so every view that reads
the ruler (every clip bar, cut, tick and zoom lane) was built again for every
pick: 22 clip bars for one click on the 6 minute reference edit. It is kept as
`EditorState.rulerGhostEndMS` now, written on a pick and with the late pass
only when a ghost really runs past the end, and a pick builds 9 bars. Like
the history write in pass 9, this is rule 5 again: **a value many views read is
watched through the answer, never through what the answer was worked out
from.**

**One piece of the panel per pass, and a rest after rows** (2026-11-16, pass
12). Picking a clip after nothing was picked fills the panel in about 400 ms
of passes, a piece at a time: the dock lets in one section a pass
(`PanelSectionArrival`) and a big section brings its later rows a pass or
more after itself (`PanelRowsArrival`). Each paced itself and neither knew
about the other, so a section and another section's rows often landed in the
same pass, and those were the long ones: 46 to 89 ms against 15 to 36 for any
piece on its own. Every piece now asks `PanelLanding.mayLand` for its pass
(`PanelLandingTurns`, tested): one piece a pass, and a set of rows keeps the
pass after it quiet, because SwiftUI pays for the controls a pass adds a
second time a pass later (focus and accessibility for each new control; a
section landing in that pass was the next long one). Ten picks from nothing
while the 6 minute edit played: longest pass median 56 ms to 31, worst 89 to
63, at about 13 per cent more passes in all. What is left: a section that
lands whole and is full of controls (Appearance) is followed by a pass of its
own of up to 55 ms with nothing landing in it, which only splitting it into
rows would spread.

How a panel pass was measured: the speed walk names what landed in each long
pass (`landed: section color`, `rows effect 0 settings`), and the main thread
meter leaves a Points of Interest mark at the end of each pass, so a Time
Profiler trace recorded with `--instrument os_signpost` is cut into exactly
those passes by `Scripts/perf/trace-bursts.py --passes`. In passes of 25 ms or
more: about half SwiftUI's own graph work, about a quarter focus and
accessibility (`AccessibilityNode.updateFocus`, the accessibility graph,
`NSWindow _resetDragMargins`), a seventh layout. Hiding the timeline took a
quarter off the panel filling in (simple section passes 19 to 14 ms); the
panel in a SwiftUI host of its own took a tenth off and left section passes
as they were, so the window-wide part is mostly the focus and accessibility
walk, which a separate host does not avoid. Not kept, for that reason.

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
