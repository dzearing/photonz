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

## 3. Level, and why there is no fade control

`AudioLevel` is a fader and a list of points, and they multiply.

- **A fade in** is a point at nought and a point at full a second and a half
  later.
- **A fade out** is the same thing at the other end.
- **A duck** is a point either side of a dip.
- **A level that just sits there** is no points at all.

They are one idea, so they are one control: a line across the layer's bar in the
timeline, with a dot at every moment somebody has pinned it. Click the line to
pin it, drag a dot to move it in time and level at once, double click to take it
out. The Sound section carries the fader, the reading in decibels, and a Flatten
for taking every point off.

The mock draws a fade in field, a fade out field, a curve picker AND diamonds on
the lane. Four controls for one fact is four things to keep in step.

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
picture points at a place on the canvas and not at a place on the timeline. The
strip itself is not a drop target yet; that is the follow-up.

Flag: `next-dropping-a-sound-or-a-video`. Off, every one of these is the silent
no-entry pointer it was before.

---

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
| Live VU meters over the canvas | **Cut** | The task notes put meters with ballistics out of scope, and they answer nothing about the edit |
| Mute and Solo | **Cut** | A level at nought IS mute. Solo is a mixer's product |
| EQ and Compressor in Effects | **Cut** | An effects rack is its own feature |
| Fade in field, fade out field, curve picker, diamonds on the lane | **One thing: points on the level line** | §3 |
| "Duck music under voiceover" as a menu command | **Cut** | It needs the app to know which layer is a voice. The points do it by hand |
| No Layers group in the dock | **Not followed** | `video.md` §5 settled this: not everything in a video document has time |

---

## 8. What this deliberately does not do

- **Scrub audio.** Dragging the playhead is silent. Hearing a scrub is its own
  feature (a short window of samples per move) and it is not what makes a cut
  aimable — the waveform is.
- **Video export with sound.** There is no document video export yet
  (`video-share`). `AudioMixdown.composition(for:urls:)` hands back a
  composition with the sound already laid in and its volume ramps beside it, so
  when video export moves onto the document path it adds a video track to the
  same composition rather than growing a second idea of what a mix is.
- **A meter.** Nothing on screen says how loud it is coming out right now.
- **Recording sound in the app.** Sound arrives with a recording, from a file,
  or let go on the window (§5a).
- **Dropping onto the timeline itself.** A sound let go on the picture lands at
  the playhead. Aiming a drop at a moment by pointing at the strip is the
  obvious next thing and is not built.
- **Anything above one file per layer**: no buses, no sends, no sub-mixes.
