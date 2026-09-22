# Captions: what the Title / Text tool does when the document has time

**Status: built, behind `next-captions-from-the-sound` (on by default in Next).**
Landed 2026-09-21. Needs `next-a-recording-is-a-document` and
`next-sound-on-the-timeline` on to be reachable, because captions are written
off a sound on a timeline and neither exists without those (`video.md`,
`video-audio.md`). Builds on the title work in `TitleTime.swift`: a caption is a
title with words somebody else wrote.

The clickthrough it was drawn against is
`docs/design/mocks/pages/video-captions.html`. What it kept, what it cut and why
is §7.

---

## 0. The whole thing in four sentences

Write Captions listens to the recording on this Mac and puts the words on the
timeline at the moments they were said. Each line is an ordinary text layer with
an in and an out, so correcting one is typing, restyling one is the Text
section, moving one is dragging its bar, and all of it undoes. A long recording
is heard in overlapping pieces so the panel can say how far along it is and Stop
can keep what it already heard. What plays is what exports, so the words are in
the film without anything being written to put them there.

---

## 1. The model, in four types

| Type | Where | What it says |
| --- | --- | --- |
| `TranscribedWord` | `Captions.swift` | One word, the stretch of the RECORDING it was said in, and how sure the machine was. |
| `CaptionCue` | `Captions.swift` | One line: the words in it and when it is on screen. |
| `Layer.captionWords` | `Layer.swift` | The words a caption layer was written from. Nil for everything else, so a document written before captions existed reads back byte for byte the same. |
| `HeardWords` | `SpeechTranscription.swift` | What came back from listening: the words, how much was listened to, and whether it was stopped. |

There is no caption object, no caption track and no caption mode. A caption is
`content: .text` plus a `LayerTime` plus `captionWords`, and the third of those
is a record of where the words came from rather than a new kind of thing.

**Why keep the word timings at all**, when the layer's own in and out already
say when the line is on screen: a line can be re-cut at a word rather than at a
guess, the whole track can be nudged with each word moving with it, and
subtitles written out later carry the timings the words really had. Correcting
the WORDS never touches any of it — the string on a text layer is the string on
a text layer.

---

## 2. Where the words come from

`SpeechTranscription.words(of:)` in `PhotonzMedia`. It uses macOS 26's
`SpeechTranscriber`, on device.

**Measured on this machine on 2026-09-21, not guessed:**

| | Apple `SpeechTranscriber` | Whisper (`whisper.cpp`) |
| --- | --- | --- |
| Where it runs | On device | On device |
| Permission | **None at all.** Nothing leaves the Mac, so there is no dialog | None |
| Timings | **Word level**, with a confidence per word | Word level with extra flags |
| Speed | **89x faster than listening**: 42:05 of speech in 28.3s | Roughly realtime to a few times faster on this class of Mac |
| What it costs the app | Nothing. Already installed | A model file of tens to hundreds of MB, in an app whose whole DMG is 8MB |
| Languages | 30, with nine English variants installed here | ~100 |

The older `SFSpeechRecognizer` was measured too and is the wrong answer for a
different reason: it asks for a TCC permission (`auth: 1`, denied, from a
command-line binary with no usage string), and the new API asks for none.

So Apple's wins on weight, speed and the absence of a permission dialog. The
case for carrying Whisper would be accuracy on hard audio or a language Apple
does not do; neither is established, and the evidence for re-deciding is a
recording where Apple's answer is not good enough. Nothing here would have to
change but the one file.

---

## 3. Pieces, and the joins between them

A recording is heard in windows (`ChunkWindow`: two minutes, four seconds of
overlap). Not because the recogniser cannot take more — it streams, so it can —
but because everything a person wants from a long job needs the pieces:

- a progress reading that moves, and a word count that goes up;
- a Stop that answers at once and **keeps** what it already heard;
- a failure that costs one piece rather than forty minutes.

**The joins are the hard part.** A cut on a fixed clock lands in the middle of a
word, and the word is lost twice over. Two rules, both in `TranscriptSeam` and
both unit tested:

1. **Cut in a silence where there is one.** Silences are measured on the samples
   on their way past to the recogniser, so it costs one pass over a buffer that
   has already been read. A cut in a silence needs no overlap.
2. **Overlap where there is not, and stitch by what was said.** The next piece
   starts four seconds before the last one ended, so every word is wholly inside
   at least one piece, and the join is made where three or more words agree
   (case and punctuation stripped). Where the two pieces disagree outright, the
   clock is the fallback and nothing is doubled.

**Timings stay absolute.** Every piece comes back on its own clock and is put
back on the recording's the moment it lands. An off-by-one-chunk error is
invisible at the start and enormous at the end, which is why the long test
asserts that the last word lands near the end of the RECORDING.

---

## 4. From the file's clock to the document's

The recogniser heard a FILE. The timeline is not the file: a trim, a cut or a
change of speed moves every word after it, and a piece thrown away takes its
words with it. `CaptionTiming.onTheTimeline` maps one to the other using
`PhotonzDocument.audioMix()` — the same plan playback and export read — so a
caption cannot drift from what you hear. A word in a held frame is dropped,
because a held frame plays no sound.

---

## 5. Where the lines break, and where they sit

`CaptionCues.cues(from:)`. Four things end a line, in the order a person would
use them: a full stop, a silence of 700ms, forty two characters, six seconds.
Then every line is **fitted**: held at least 1.2s so a short one is not a flash,
and never a millisecond into the next one.

That last clause is not theoretical. The first walk on real speech failed at
2160ms with two captions on screen at once: in continuous speech the next line
starts the instant this one's last word ends, so a line that lingers for another
300ms lingers over the line after it. Pinned by
`testNoLineIsEverOnScreenWhileTheNextOneIs`.

A caption's box is the full width inside a 10% title-safe inset, sitting on the
title-safe floor, with the words centred and the same auto-contrast shadow every
text layer over a picture gets (`TextBuilder.autoContrastShadow`). The size is a
share of the picture's height rather than a number of points, so a caption on a
phone-sized recording and one on a 4K recording read the same size to the eye.

---

## 6. The ways out

- **Burned into the picture.** Free, and verified: a caption is an ordinary text
  layer, so `DocumentMovieWriter` draws it with everything else. The walk writes
  an MP4 and the frame at four seconds carries the words.
- **A subtitle file.** `Export Captions…` writes SubRip (`.srt`), which every
  player, every video site and every editor reads, and which leaves the words
  switchable-off and searchable.
- **WebVTT, burned-in styling per cue, a sidecar in the document package**: not
  built. SRT covers the case and adding a second text format would be the same
  feature said twice.

---

## 7. What the clickthrough asked for, and what was built

| The mock | Built? | Why |
| --- | --- | --- |
| Auto-generate captions with word-level timing | **Yes** | The whole point. |
| Cues land on the timeline as a normal track | **Yes**, one text layer per line, in a `Captions` group so the layers list has one row rather than four hundred. The strip walks into groups, so each line still gets its own bar | |
| Each word owns its own time span | **Yes**, kept on the layer | |
| The active word lights up as the playhead moves | **No** | Karaoke highlighting is a second rendering path for text and its value is decorative next to correcting. The timings are all kept, so it can be added without re-transcribing anything. |
| A Language picker | **No** | A question asked before anybody has a reason to answer it. The Mac's own language is used, and the model refuses honestly where it is not supported. Worth adding the day somebody captions a second language. |
| Title-safe / action-safe guides, and a safe-area picker | **Partly** | Captions LAND inside the title-safe inset, which is the outcome the guides exist to produce. Drawing the guides is a separate feature about every layer, not about captions. |
| A caption style picker (Caption / Lower third / Karaoke) | **No** | A caption wears a text style, and text styles already exist and are already in the Text section. A second picker here would be a second place to change one thing. |
| "Clear caption track", "Export SRT" | **Yes**, both | |
| The open question: per-word nudge chips vs re-transcription plus a global offset | **The global offset**, plus the per-line drag the timeline already had | Two controls, no new surface. A recogniser that runs late runs late everywhere, and one line out of step is a bar end. Per-word chips would be a new editing surface for the rarest of the three cases. |

---

## 8. Where it is

| What | Where |
| --- | --- |
| Model: words, cues, seams, chunks, placement, SRT, progress copy | `Sources/PhotonzCore/Captions.swift` |
| The words on a layer | `Sources/PhotonzCore/Layer.swift` (`captionWordsStorage`) |
| Listening | `Sources/PhotonzMedia/SpeechTranscription.swift` |
| The window: write, stop, nudge, clear, export | `Sources/Photonz/EditorState+Captions.swift` |
| The panel section | `Sources/Photonz/CaptionsInspector.swift` |
| The menu | `Sources/Photonz/EditorCommands.swift`, Video menu |
| A voice to caption | `Sources/Photonz/Tutorials/TutorialSampleVoiceover.swift` |
| Tests | `Tests/PhotonzCoreTests/CaptionsTests.swift`, `Tests/PhotonzMediaTests/SpeechTranscriptionTests.swift` |
| Walk | `Scripts/playtest/captions-from-the-sound-walk.json` |

The forty minute case is far too slow for every commit, so it runs on demand:

```
PHOTONZ_LONG_SPEECH=/path/to/long.aiff Scripts/test.sh --filter SpeechTranscription
```
