# Sound: a layer that occupies time and draws nothing

**Status: built, behind `next-sound-on-the-timeline` (on by default in Next).**
Landed 2026-09-21. Needs `next-a-recording-is-a-document` on to be reachable,
because sound lives on the timeline and the timeline only exists in a document
that has time (`video.md`).

The clickthrough it was drawn against is
`docs/design/mocks/pages/video-audio.html`. What it kept, what it cut and why is
§7.

---

## 0. The whole thing in four sentences

A layer may play a sound. Sound is a layer, so it has an in and an out, it is
cut into pieces, it is named, switched off and undone by machinery that already
existed. A recording arrives with its sound welded to its picture, and Detach
Sound takes the two apart. What plays and what exports are read off one
function, so they cannot drift.

---

## 1. The model, in three types

| Type | Where | What it says |
| --- | --- | --- |
| `SoundRef` | `SoundClip.swift` | Which file, how long. **No samples and no path**, the same bargain `ImageRef` and `MovieRef` already strike. |
| `LayerContent.sound` | `Layer.swift` | A layer that is only sound. Its own content case, so every switch in the app is asked by the compiler what it means by a layer with nothing to draw. |
| `AudioLevel` | `AudioMix.swift` | A fader and a shape it follows as it runs. They multiply. |

Plus two fields on `Layer`: `soundDetached` (a clip whose sound has been taken
off) and `soundLevel`. Both optional, both written only when set, so every
document saved before this existed reads back byte for byte the same.

### A clip has no sound of its own

`Layer.sound` is COMPUTED:

```swift
if case .sound(let ref) = content { return ref }     // a piece of sound
guard soundDetached != true else { return nil }      // ...a clip that lost its sound
return movie?.soundRef                               // ...a clip that still has it
```

A recording is one file with a picture in it and a sound in it, so its sound
shares its id (`MovieRef.soundRef`). One identity, not two that could drift, and
taking the sound off costs nothing: the new layer points at a file the app has
already opened.

### Detaching

`PhotonzDocument.detachingSound(ofLayer:)` hands back a whole document, the id
of the layer the sound landed on, and the `SoundRef` so the app can file the
URL. The new layer sits directly above the clip with **the same in, the same out
and the same cuts**, and from that moment the two are ordinary layers.

That last part is the whole point, and it is the case
`video-cut-wt` is built around: cut the picture and the voiceover over it is
untouched, because they are two rows and a cut acts on one row.

---

## 2. The one plan

```
PhotonzDocument.audioMix()  ->  [AudioMixSegment]
                            ->  DocumentAudioPlayer   (what you hear)
                            ->  AudioMixdown          (what you export)
```

A segment is one piece of one layer: which file, where it lands, what stretch of
the file it reads, how fast, and **the level end to end as ramps on the
document's own clock**. Nothing downstream works anything out.

This is how "what you hear matches what exports" is settled. It is not a promise
kept by care, it is a promise that cannot be broken, because there is one answer
and two renderers of it. `Tests/PhotonzMediaTests/AudioMixdownTests.swift`
measures the written file — a duck really comes out quieter under the voice, a
cut really reads the stretch it kept, three sounds laid over each other really
are louder where they overlap.

A held frame contributes nothing (`ClipPiece.playsSound`), a layer switched off
in the layers list is neither seen nor heard, and a level pulled all the way down
leaves no segment at all.

---

## 3. Level, and fades

`AudioLevel` is a fader and a list of points, and they multiply.

- **A fade in** is a point at nought and a point at full a second and a half
  later.
- **A fade out** is the same thing at the other end.
- **A duck** is a point either side of a dip.
- **A level that just sits there** is no points at all.

The line across the layer's bar in the timeline draws all of it, with a dot at
every moment somebody has pinned it. Click the line to pin it, drag a dot to
move it in time and level at once, double click to take it out. The Sound
section carries the fader, the reading in decibels, and a Flatten for taking
every point off.

**Fades have their own section as well, as the mock draws them** (2026-09-25,
task `a-sound-shows-its-fade-in-and-fade-out-as-the-mo`). Under Sound, headed
Fades with "drag the diamonds on the lane" beside it: an In box and an Out box
you can read or type seconds into, and a Curve dropdown from the one list of
curves. The boxes and the diamonds at the bar's top corners write the same two
points, so they cannot drift apart. The one thing a point cannot say is the
shape of the rise, so `AudioLevel.fadeCurve` sits beside the points: it bends
the fade in, and the fade out played backwards, and nothing else. A curve is
heard as well as drawn: `AudioLevel.moments` steps along a curved fade (up to 40
pieces, none under 10 ms) and both the lane's line and the mix's ramps are
drawn through those same moments. A fade nobody shaped stays Linear, which is
what every fade written before the curve does.

An earlier version of this section argued the mock's four fade controls were
one fact said four times and shipped only the line. That was a departure from
the mock, and it was put right.

**The line is not drawn on a straight scale.** Level goes to twice as loud (+6
dB), so spread evenly the ordinary level would sit exactly halfway up the bar,
through the middle of the waveform where it reads as an axis rather than as a
control. It is squared instead: unity sits about seven tenths of the way up, the
headroom takes the top third, and the quiet end — where a duck lives — gets the
room. It is also how a fader feels under a hand.

**There is no mute.** A level pulled all the way down reads `Silent` and nothing
is heard. A second switch that also meant silent would be two controls for one
fact.

---

## 4. The waveform

`Waveform` is one peak per twenty milliseconds, the LOUDEST in each bucket
rather than the average, because a drum hit is two milliseconds long and
averaging it away is exactly what makes a waveform useless for aiming at a beat.
Fifty numbers a second keeps a quarter of an hour under fifty thousand floats.

It is **not in the document**. `SoundFile.read(at:)` (PhotonzMedia) decodes the
file forward in one pass and reduces it as it goes, `SoundLibrary` keeps it
against the sound's id, and the bar asks for it every time it draws and never
waits for it: a bar with no waveform yet is a bar, and the peaks land a moment
later and it redraws.

`Waveform.columns(count:forPieces:)` is the arithmetic that keeps the picture of
the sound honest after a cut: a piece thrown away takes its columns with it, a
piece moved takes them along, and a held frame draws flat.

---

## 5. What it costs, and what it refuses

`DocumentAudioPlayer` is one `AVAudioEngine`, one player node per piece of
sound, one mixer per LAYER so the layer's level is one number to move, and an
`AVAudioUnitVarispeed` in front of any piece not at the speed it was recorded at
— so a piece sped up rises in pitch, exactly as `ClipPiece.soundRatePercent`
says it should.

- Everything still to come is scheduled against **one engine start**, so two
  sounds meant to start together do.
- A scrub mid-play schedules it all again from where the hand put the playhead.
  Nothing is faded: a scrub is somebody looking for a moment.
- The level is followed on the document's own clock, thirty times a second. A
  duck is a third of a second long, so ten steps make a slide.
- **`segmentBudget` is 48.** Each piece is an engine node and a decode, and a
  timeline with more than that alive at once is not one anybody is auditioning
  by ear. The rest are dropped and `droppedSegments` says how many.

---

## 5a. Letting one go on the window

`MediaDrop` (pure, `PhotonzCore/MediaDrop.swift`) is the ONE answer for a sound
or a recording dragged onto an editor window, read by three things that must
never disagree: the pointer, the sentence the canvas draws while the file is
still in the air, and the thing that actually lands. There are four answers and
each of them says something:

| What is in the air | What the document under it is | What happens | What the canvas says |
| --- | --- | --- | --- |
| a sound | runs in time | a sound layer at the playhead, the layer Add Sound would have made | `Sample Music lands on the timeline at 0:04` |
| a sound | a still picture | **nothing**, and the pointer refuses it | `No timeline here for Sample Music. Open a recording first` |
| a recording | runs in time | a clip layer at the playhead, fitted into the box the drag drew | `B Roll lands as a clip at 0:04` |
| a recording | a still picture, or nothing at all | it opens in a window of its own, through the recording door | `B Roll opens in its own window` |

Three things about the shape of it:

- **A sound draws no landing box**, so it answers in WORDS instead. The sentence
  is the same plate a saved text style already uses
  (`CanvasNSView.showDropNote`), accent coloured for a yes and dark for a no.
- **The refusal speaks where the yes would have** and names the one move that
  works, which is the whole of `UX-PATTERNS` §refusals. There is no way to put
  time into a picture today, so "open a recording first" is the answer rather
  than a shrug.
- **A recording opens rather than being refused** because a recording IS a
  document (`video.md` §1), so it behaves exactly as a `.photonz` let go on a
  canvas always has.

Where the drop lands in TIME is the playhead, for both, because a drop on the
picture points at a place on the canvas and not at a place on the timeline.

**Let go on the TIMELINE instead** (2026-09-23, `ClipLanding.swift`,
`TimelineLaneDrop.swift`, `EditorState+TimelineDrop.swift`) and it lands at the
moment and on the track under the pointer, the way b-roll goes in in Premiere:

- **Overwrite** by default: whatever is on that track under the new clip is
  trimmed back, split round it (two layers reading the same file, since a
  clip's pieces cannot hold a hole) or taken away when wholly covered.
- **Insert** with ⌘ held: the clip it lands inside is split and everything on
  that track from the moment on is pushed along; on other unlocked tracks only
  what starts at or after the moment moves, so a title stays over its picture
  and a music bed already playing plays on.
- A sound over a picture track goes to the nearest sound track, or a new one
  under the picture; a video over a sound track to the nearest picture track.
  Between two tracks makes a new one there. A locked track refuses, in words.
- The start snaps (8pt) onto any clip edge or the playhead, and so does the
  end. While the file is in the air the lanes show a dashed ghost the length
  of the file, the bar over the tracks says where it lands and that ⌘ inserts,
  and the timeline makes room past its end so a clip appended there is seen.
- Clips that meet on a track have an **edit point** (`comp-video.html` §02):
  a faint hairline, amber on hover, an amber ring when picked. Clips along a
  track alternate the mock's two clip colours (`.clip.v1`, `.clip.v2`).

Walk: `second-clip-on-the-timeline-walk` (`dropOnTimeline`, `expectClip`).

Flag: `next-dropping-a-sound-or-a-video`. Off, every one of these is the silent
no-entry pointer it was before.

---

## 5b. Hearing the scrub

Dragging the playhead used to be silent, and finding the exact word somebody
says meant reading the picture of the sound and aiming at it. §8 called scrub
audio out of scope for exactly one reason — it is not what makes a cut aimable,
the waveform is — and that reason held right up until the waveform was there
and people started asking the second question: *which word is that?*

**A scrub is the same plan, read a sliver at a time.**
`ScrubAudition.windows(in:movingFromMS:toMS:)` (pure, `PhotonzCore`) takes the
mix and the two moments the playhead moved between, and says which file, which
frames of it, which way round and how loud. Nothing else works anything out, so
what you hunt with is what you hear when you press space and what lands in an
export.

- **A grain is 60ms** and they butt up against each other: one is allowed to
  start every 60ms, so a hand moving steadily makes a continuous sound and a
  hand that stops goes quiet inside a grain. That is why standing still on the
  timeline is silent: what a scrub plays is MOVEMENT.
- **A click is not a drag.** The first grain is not due until 60ms after the
  press, and a click is over long before that, so putting the playhead
  somewhere makes no sound at all.
- **Backwards plays backwards.** Going forward a grain starts where the
  playhead is; going back it ends there and the samples are turned round.
- **Both ends of a grain are faded**, 5ms each. A waveform cut off mid-cycle is
  a click, and a run of them is a buzz loud enough to drown the thing you were
  listening for.
- **Every piece of sound under the playhead gets its own grain and its own
  node**, at the level its own line says at that moment, so two sounds laid
  over each other are both heard.
- **Not while it is playing.** A scrub mid-play already restarts the whole mix
  from where the hand put the playhead (§5), and that IS the sound of that
  moment.

### None of it is on the main thread

`ScrubAudioPlayer` (main actor) does the arithmetic and the pacing and nothing
else. `ScrubAudioEngine` (an actor) owns the `AVAudioEngine`, the open files
and the nodes, and everything crossing into it is a value.

This is not tidiness, it is the feature working at all. The first build did the
engine start and the file reads on the main thread and the walk caught it at
once: **the worst grain cost 70ms**, which is four frames of the playhead
standing still to listen. Moving the warm up to the press left an 18.9ms grain
on the second drag — a compressed file seek — so the reads went off the main
thread too. The hand now pays 0.1ms a grain, and `soundScrubAcrossIt` in
`hear-the-scrub-walk` fails the walk if any single move costs a frame.

The walk also asks what was actually on the engine rather than how many buffers
went to it: fifteen grains of silence schedule exactly as well as fifteen
grains of somebody talking, so the loudest sample played is checked too.

Behind `next-hear-the-scrub`, which leans on `next-sound-on-the-timeline`:
with no sound on the timeline there is nothing under the playhead to hear.

---

## 5c. How loud it adds up to

Sound adds up. Three things playing at the level they were recorded at are
three times as loud as one of them where they overlap, and a sound file has no
room for that: everything past the top is sheared off flat, and what should
have been three sounds comes out as noise. Until 2026-09-22 the app said
nothing about it — no meter, no mark on the export, and a written file you
found out about by listening to it. §8 listed a meter as deliberately absent
and §7 cut the mock's VU meters as answering nothing about the edit. Both were
right about a meter with ballistics and wrong about the fact underneath it,
which is not decoration: it is a file coming out broken.

**One piece of arithmetic answers all of it.** `AudioHeadroom` (pure,
`PhotonzCore`) takes the mix plan and the shape of each file it plays and says
how loud the whole thing gets:

```
AudioHeadroom.reading(of: mix, peaks:)   -> the loudest it ever gets, where, and how far over
AudioHeadroom.level(of: mix, peaks:, atMS:) -> how loud it is at ONE moment   (the meter)
AudioHeadroom.limited(mix, peaks:)       -> the same plan, held under the ceiling
```

- **It measures the sound, not the fader.** A layer at full level playing a
  quiet recording is quiet, and the only thing that knows that is the file. The
  app has already read every file to draw its waveform (§4), so the shapes cost
  nothing extra. A file not read yet is counted at full scale: the guess is
  quieter than the truth, never louder.
- **It is a worst case on purpose.** Peaks are summed rather than combined by
  power, so two sounds that might line up are assumed to line up. A ceiling
  that holds only for sounds that disagree is not a ceiling.
- **The ceiling is full scale, not a decibel under it.** A recording that
  already peaks at the top is a legal file, and pulling it down on the way out
  would be the app quietly turning somebody's work down for a reason nobody can
  hear.

### Holding it down

`limited` multiplies every level by one number, so the balance between the
layers and the shape of every fade survive: it is the whole mix brought down,
not a limiter chewing at whichever layer happened to be loudest. A mix that
already fits is handed back untouched — nothing is ever quietly turned down —
and trimming an already-trimmed mix changes nothing, which is what lets it be
applied wherever the plan is read without anybody tracking whether it was
applied already.

`EditorState.audioMix` hands over the held-down plan, so the player, the scrub
and the export are all given a mix that cannot clip, and §2's promise stays
true of the trim as well as of everything else. `AudioMixdown.composition` does
it again on the way past, which means a headless export or a video export
cannot write a clipped file whatever it was handed.

### The meter

A slim bar in the **transport**, beside the play button. Not over the canvas,
where the mock drew it: the canvas is the picture being judged and a meter
parked on it is the one thing you cannot move out of the way. Not in the Sound
section either, because that is only there when a layer that makes a sound is
picked, and how loud the mix is is a question about the whole document.

**It reads the plan, not the engine.** Every piece under the playhead, at the
level its own line says, times how loud its file actually is there. Two things
follow, and both are better than a tap on the mixer would have been: it moves
while you DRAG the playhead and not only while it plays, so the loud moment can
be hunted by hand; and it says the same thing the export will, because it is
the same arithmetic.

Over the ceiling the bar turns amber and says the number of decibels it is
over, which is exactly the number coming off every layer. A meter that only
pins at the top says something is wrong without saying what.

Export Sound's notice says when the mix had to be held down and by how much
(`CopyConfirmation.mixHeldDown`), so it is marked before the file is written
rather than discovered afterwards.

Behind `next-the-mix-says-how-loud-it-is`, which leans on
`next-sound-on-the-timeline`. The FLAG is the meter and the mark; holding the
mix inside what a file can hold happens either way, because writing a
distorted file is a fault rather than an experiment.

The walk is `mix-says-how-loud-walk`, and it checks rather than photographs:
`soundExpectMeterReads` fails unless the meter follows the mix (high where the
plan says sound, nothing past the end of it), and `soundExpectMixOver` fails
unless the plan really is over, what plays is not, and every layer came down by
the same amount.

---

## 5d. Gain and Normalize (2026-09-26)

The user: system audio "barely registers" on the tracks. Measured before
changing anything: ScreenCaptureKit takes system audio at unity, before the
Mac's output volume (a -9.0 dBFS tone came back at -8.7 dBFS with the volume at
6 of 100; `--audio-capture-diag` in the probe reproduces it). The recordings
are quiet because the SOURCES are quiet (their own files: -25 to -45 dBFS
peaks, -40 to -65 LUFS), and the waveform drew straight amplitude, so a -30
dBFS peak was three per cent of the lane.

- **Gain** (`AudioLevel.clipGainDB`, -48 to +48 dB) is a stage before the
  fader, like Premiere's clip gain under its volume band. It multiplies every
  ramp in `audioMix()`, so playback, export, the meter and the headroom guard
  all honour it with no new code path. AVAudioMix ramps and
  `AVAudioMixerNode.volume` both take values far above 1 (x50 measured linear).
- **Normalize** (right-click ▸ Normalize ▸ Peaks to -1 dB, or the panel's
  button) reads the peak off the waveform over the stretches the pieces play.
  **Loudness for Web / Podcast** measures BS.1770 integrated loudness off the
  file (`LoudnessMeter`, `SoundFile.loudnessLUFS`) and never lets the peak pass
  -1 dBFS. Several picked sounds normalize together, one undo step.
- **The waveform draws in decibels** (`Waveform.drawnHeight`, 54 dB of
  range) and includes the gain, so a Normalize grows it. The segment wears the
  gain as a small `+N dB` label.
- Normalizing new recordings automatically on open was left out: the capture
  is not the quiet part. It is a question in the audit for the user.

## 6. Where it is in the window

| What | Where |
| --- | --- |
| The waveform | inside each piece of the layer's bar, on the timeline |
| The level | a line across the whole bar, with a dot per point |
| The fader, the reading, Flatten | the **Sound** section in the panel, directly above Motion |
| Detach Sound, Add Sound, Flatten Level, Export Sound | the Video menu |
| A sound layer's row | the layers list, wearing a waveform where a thumbnail would be |

A sound layer's bar is **taller** than every other bar (36pt against 18pt), and
it is the one thing in the strip that is: a waveform squeezed into eighteen
points is a smear and a level line has nowhere to be dragged.

---

## 7. What the mock said and what was built

| The mock | What landed | Why |
| --- | --- | --- |
| Audio tracks are lanes on the timeline dock | Kept, exactly | It is the thesis, and it came free: a sound is a layer with a time, so the strip already drew it |
| The selected track's channel strip opens in Properties | Kept, as the Sound section | |
| Source files live in Library, scope Media | **Not built.** Add Sound opens a file; the shelf is a follow-up | The shelf is not what makes sound work, and the task said not to invent a third place for media — this invents none, it just has no shelf yet |
| Live VU meters over the canvas | **Built, somewhere else** | Cut on 2026-09-21 as answering nothing about the edit. That was right about a meter with ballistics and wrong about the fact underneath it: a mix that adds up past full scale writes a broken file. The meter is in the transport rather than on the canvas, and it reads the plan rather than the engine (§5c) |
| Mute and Solo | **Cut** | A level at nought IS mute. Solo is a mixer's product |
| EQ and Compressor in Effects | **Cut** | An effects rack is its own feature |
| Fade in field, fade out field, curve picker, diamonds on the lane | **One thing: points on the level line** | §3 |
| "Duck music under voiceover" as a menu command | **Cut** | It needs the app to know which layer is a voice. The points do it by hand |
| No Layers group in the dock | **Not followed** | `video.md` §5 settled this: not everything in a video document has time |

---

## 8. What this deliberately does not do

- ~~**Scrub audio.**~~ Built on 2026-09-22, and §5b says how. The reason it was
  out of scope — it is not what makes a cut aimable, the waveform is — was
  right, and it stopped being a reason the moment the waveform was there and
  the next question people asked was which word that is.
- **Video export with sound.** There is no document video export yet
  (`video-share`). `AudioMixdown.composition(for:urls:)` hands back a
  composition with the sound already laid in and its volume ramps beside it, so
  when video export moves onto the document path it adds a video track to the
  same composition rather than growing a second idea of what a mix is.
- ~~**A meter.**~~ Built on 2026-09-22, and §5c says where and why. The reason
  it was out of scope — a meter with ballistics answers nothing about the edit
  — was right about ballistics and missed the thing underneath: three sounds
  at the level they were recorded at wrote a file that was clipped, and nothing
  said so.
- **Recording sound in the app.** Sound arrives with a recording, from a file,
  or let go on the window (§5a).
- **Dropping onto the timeline itself.** A sound let go on the picture lands at
  the playhead. Aiming a drop at a moment by pointing at the strip is the
  obvious next thing and is not built.
- **Anything above one file per layer**: no buses, no sends, no sub-mixes.

## Linked sound (2026-09-23)

A clip's own sound is on the timeline from the moment it opens: a segment with
its waveform on an Audio track under the picture, the way Premiere puts a
clip's audio on A1 under V1. It is not a second layer. It is the clip's own
time, cuts and level drawn again as sound (`PhotonzDocument.linkedSoundTrackID`
/ `linkedSoundClipIDs`, `DocumentTracks.swift`), so every edit to the clip moves,
trims and cuts its sound with nothing to keep in step, and every drag on the
segment is a drag on the clip.

- Placement: the bottom picture's sound takes the first audio track; a sound
  that would overlap something already on a track goes to the next, and a new
  one is made when none is free (its id is the clip's id with the first byte
  turned, so it is stable). A sound layer (music) always wins a lane over a
  linked segment. A video with no sound still shows an empty Audio track.
- Detach Audio (right-click, the Video menu, the panel) writes the tracks down
  and puts the new sound layer on the very track the segment was on.
- Mute or solo on that audio track decides whether the clip is heard; deleting
  it takes the clip's sound away and keeps its picture.
- Fades are two points on the level (`AudioLevel.setFadeIn/Out`), written by a
  handle at each top corner of a sound segment. Dragging the level line up or
  down is the fader; a click on the line pins a point. The rest of the segment
  picks up and moves the clip.
