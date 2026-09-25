# Video editing in Photonz Next, measured against Premiere

2026-09-24. One editing session at Next defaults, no flag touched, in the probe
app with Screen Recording granted and the screen unlocked, so every picture
below is the real window.

What was edited:

- **The standing session walk** (`Scripts/playtest/an-editing-session-walk.json`):
  the 17 second Sample Talk, cut with Command K twice and Delete, a second clip,
  a cross dissolve from the picker, a title moved from A to B, a 21 second
  play-through, an MP4 export. It passes.
- **A real five minute recording**: 2880 x 1800 at 30 fps, H.264, 1018 spoken
  words (made with `say` and `ffmpeg`, kept out of the repo), plus a two minute
  music bed. Driven by three throwaway walks that pressed Premiere's keys and
  photographed what happened.

Severity: **High** stops or misleads a real edit, **Medium** is slower or
clumsier than Premiere, **Low** is a nicety a Premiere user would miss.

## The basics, checked first

| Basic | Premiere | Photonz Next today | Verdict |
| --- | --- | --- | --- |
| Blade at the playhead | Command K, C for the razor | Command K anywhere, B then a click on a clip, right-click Split at Playhead ([picture](video-vs-premiere/blade-cut.jpg)) | Works |
| Ripple delete | Shift Delete | Shift Delete with the timeline focused, right-click Ripple Delete; plain Delete closes the gap too | Works |
| J, K, L shuttle | Works on the timeline | Works, up to 8x, from the moment a recording opens ([picture](video-vs-premiere/closed-2-l-plays-on-open.jpg)) | Works (was **Gap 2**) |
| Drag clips between tracks | Drag up or down | Carry up onto the track above, or past the top for a new track (tracks walk) | Works |
| A layer over video | Type tool, Essential Graphics | T and a click makes a title on its own track, keyable Position | Works, but **Gap 5** on its look |
| Detach audio | Unlink | Right-click Detach Audio | Works |
| Snapping | On, S toggles | On, snaps to playhead and clip ends; S and the magnet button switch it ([picture](video-vs-premiere/closed-9-snapping-off.jpg)) | Works (was **Gap 9**) |
| Undo | Command Z | Every edit is one step, including track groups and new tracks | Works |

## Gaps

The table as found on 2026-09-24. The **Now** column is the re-check on
2026-09-24 evening, after the fixes landed: each closed gap has a fresh
picture from the walk that guards it, all nine walks green at Next defaults
with real window captures.

| # | Gap | What Premiere does | What Photonz did | Picture | Severity | Task | Now |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | The ruler names the wrong time when zoomed in | Ruler labels sit on the frame they name | Zoomed and scrolled, every label shifts left by the distance of the first visible tick: at 4x, 1:15 sits about 4 s from 1:15; in another view 14 s off | [4x](video-vs-premiere/ruler-at-4x.jpg), [deepest zoom](video-vs-premiere/ruler-at-max-zoom.jpg) | High (bug) | `the-timeline-ruler-names-the-right-time-when-zoo` | **Closed.** Numbers sit over their moment at every zoom ([4x, playhead on 1:15](video-vs-premiere/closed-1-ruler-at-4x.jpg)); `ruler-names-the-right-time-zoomed-walk` |
| 2 | Timeline keys need a click first | J K L, I O, M, B work as soon as the sequence is open | After opening a recording the canvas has the keyboard: L is the Line tool, I Measure, K the Lens. They mean play, mark and blade only after the timeline's Select button is clicked | [L on open](video-vs-premiere/l-on-open-picks-line.jpg) | High | `premiere-s-timeline-keys-work-the-moment-a-recor` | **Closed.** L plays as the first press after opening ([picture](video-vs-premiere/closed-2-l-plays-on-open.jpg)); `timeline-keys-on-open-walk` |
| 3 | Nothing removes a marked stretch | I, O, then apostrophe (Extract) or semicolon (Lift) | I and O draw the green span; apostrophe, semicolon and Shift Delete do nothing. Each stretch costs two cuts, a click on the middle piece and Delete | [marked](video-vs-premiere/in-out-marked.jpg), [after Shift Delete](video-vs-premiere/after-shift-delete.jpg) | High | `marking-an-in-and-an-out-and-pressing-one-key-ta` | **Closed.** Apostrophe extracts, semicolon lifts, one undo step ([5:00 to 3:45](video-vs-premiere/closed-3-extracted.jpg)); `extract-a-marked-stretch-walk` |
| 4 | A captioned five minute timeline freezes on every press | No hitch | With 173 captions, I freezes the app about 170 ms, backslash 445 ms, others up to 680 ms. With the captions cleared the same keys stay under 31 ms | (walk timings, in the task) | High (performance) | `a-long-captioned-recording-edits-without-freezin` | **Closed.** 20 to 47 ms a key on a quiet Mac; the ninety second cut below never held the app more than 83 ms ([picture](video-vs-premiere/closed-4-long-talk-marked.jpg)); `a-long-captioned-recording-walk` |
| 5 | A new title can't be read on video | New titles start large and white | 24 pt black regular text, invisible on a dark recording | [title](video-vs-premiere/title-default-look.jpg) | Medium | `a-title-typed-over-a-video-is-readable-without-r` | **Closed.** A new title starts white, bold, a tenth of the picture tall, with a soft shadow ([picture](video-vs-premiere/closed-5-title.jpg)); `a-title-reads-over-a-video-walk` |
| 6 | No ripple trim to the playhead | Q and W trim the clip's start or end to the playhead and close the gap | Nothing on Q or W; the same trim is a cut, a click and Delete | none | Medium | `q-and-w-trim-the-clip-under-the-playhead-up-to-i` | **Closed.** Q and W ripple trim to the playhead ([Q](video-vs-premiere/closed-6-q-trimmed.jpg)); `ripple-trim-to-playhead-walk` |
| 7 | No key for the usual transition | Command D (Final Cut: Command T) puts the default dissolve on the nearest cut | Click the cut, pick a tile, every time; Command D is Deselect | [picker](video-vs-premiere/transition-picker.jpg) | Medium | `one-key-puts-the-usual-transition-on-the-cut-at` | **Closed.** Command T (Final Cut's key; Command D stays Deselect) puts the default dissolve on the cut ([picture](video-vs-premiere/closed-7-command-t.jpg)); `default-transition-key-walk` |
| 8 | Export can't make a smaller video | 1080p, 720p and more | Format, Quality and Captions only. A 2880 x 1800 recording can only come out at full size, estimated 678 MB for five minutes | [sheet](video-vs-premiere/export-sheet-5-min.jpg) | Medium | `the-export-sheet-lets-you-pick-the-size-of-the-v` | **Closed.** Size row: Full, 1080p, 720p ([picture](video-vs-premiere/closed-8-export-1080p.jpg)); `export-a-video-at-1080p-walk` |
| 9 | Snapping can't be switched off | S, and a magnet button | Always on | none | Low | `s-switches-timeline-snapping-off-and-on` | **Closed.** S and a magnet button ([off](video-vs-premiere/closed-9-snapping-off.jpg)); `snapping-switches-with-s-walk` |
| 10 | A long clip is a blank bar | Frames drawn along each clip | One gradient bar. At Fit, five minutes of captions is a comb of 173 tiny pills. The mock also draws plain bars, so this is the user's call | [five minutes at Fit](video-vs-premiere/five-minutes-at-fit.jpg) | Medium | `clips-on-the-timeline-show-pictures-of-what-is-i` (decision card) | Open: waiting on the user's answer to the decision card |

### Gaps already in the queue (not filed again)

- A cut leaves the captions behind: `cutting-a-stretch-out-of-a-recording-takes-its-c`.
- An edit can't be saved as a project: `a-video-edit-can-be-saved-as-a-project-and-opene`.
- The export size estimate is about fourteen times too big: `the-export-sheet-s-size-for-an-edited-video-is-c`.
- A dissolve cuts the sound hard: `a-transition-carries-the-sound-across-the-cut-to`.
- Export ignores In and Out: `export-and-playback-keep-to-the-in-and-out-marks`.
- A recording from disk opens with the trim bar over its captions: `the-trim-bar-a-recording-opens-with-stays-clear`, `trim-becomes-a-tool-and-the-recording-window-ret`.
- A video gets the whole 16 button picture tool bar and no Blade: `on-a-video-the-tool-bar-holds-the-video-tools-an`.
- Layers repeats the timeline: `on-a-video-the-timeline-is-the-layer-list-and-th`.
- A (Track Select Forward) is still the Arrow tool: `a-picks-everything-after-a-clip-and-moves-it-as`.
- The media pool (Library) is hidden on a video: `a-video-document-shows-the-library-in-its-dock` (decision card).

### Seen, not filed

- **No frames in the time readout.** The transport says 0:04 and the ruler counts
  seconds; Premiere shows 00:00:04:12. The playhead readout does give 4.31 s.
  Low; left in the task log.
- **The picture shrinks as tracks are added** (35 % to 32 % after a video track
  and a music bed). Premiere keeps the monitor still and scrolls the tracks.
  Low; left in the task log.
- **The title bar says "Everything"** where the mock says the document's name,
  size, length and whether it is saved. That comes with saving a project.
- **Shuttle sound.** An earlier pass heard no sound while shuttling at 2x or
  backwards, where Premiere plays it pitched. A walk can't listen, so it was
  not reproduced here.

## Where Photonz is already ahead

- **Captions write themselves, fast.** Five minutes of speech became 173
  captions and 1018 timed words about three seconds after opening, on this Mac,
  with nothing pressed. Premiere's Transcribe and Create Captions take minutes
  and three dialogs.
- **Playback never blanked**: a 2880 x 1800 recording played with every frame
  read before the playhead reached it; the 21 second session edit played
  through its dissolve with no empty frame in 30 looks.
- **Opening is quick**: the five minute recording was ready to edit in about
  1.3 s.
- **Right-click carries the verbs**: split, ripple delete, roll edit, speed,
  detach audio, add transition and rename are all on the thing they act on.

## The workflow, counted

### The ninety second cut (2026-09-24, after the gaps closed)

The five minute talking recording, 2880 x 1800 at 30 fps (the walk's own copy
runs 5:19 and writes 191 captions as it opens), cut to exactly 1:30 at Next
defaults with no switch turned on, by keys and ruler clicks only. Driven by
`Scripts/playtest/the-ninety-second-cut-walk.json`, which passes and fails if
any step stops doing what is counted.

| Step | Photonz Next | Actions |
| --- | --- | --- |
| Lose the head | click the ruler at 0:12, Q | 2 |
| First stretch | click the ruler, I, click the ruler, O, apostrophe | 5 |
| Second stretch | the same | 5 |
| Third stretch | the same | 5 |
| Lose the tail | click the ruler at 1:30, W | 2 |
| **Total** | 5:19 to 1:30 | **19** |

Nothing had to be pressed first: the recording opened paused, with the timeline
holding the keyboard, and every key above was taken by the timeline. The longest
the app held still after any of them was 83 ms. The captions went with the cut
(191 to 58), and eight seconds of the result played with every frame drawn.
Pictures: [opened](video-vs-premiere/cut-0-opened.jpg),
[first stretch marked](video-vs-premiere/cut-1-first-stretch-marked.jpg),
[ninety seconds](video-vs-premiere/cut-2-ninety-seconds.jpg).

**Premiere, the same cut**: the same 19 with its default keys (a click in the
time ruler, Q, I, O, apostrophe, W), plus making a sequence from the clip before
the first of them (a drag onto the empty timeline, or New Sequence From Clip),
so **20**. Premiere is not on this Mac, so its count is from its documented
default keys, not a timed run; the keys are the same ones the Photonz walk
presses. Premiere's captions come after the cut, from Transcribe and Create
Captions; Photonz's were there before the first press and followed every edit.

The success line for `video-beats-premiere` was under 40. It is 19, one fewer
than Premiere.

**One marked stretch**, counted alone: I, O, apostrophe, **3 presses**, plus
the two clicks that put the playhead on each end, which Premiere needs too.
Five actions in both.

Trimming the head of a clip to the playhead: click, Q. **2 actions**, as in
Premiere.

### Before the gaps closed (2026-09-24 morning)

- One stretch: click the timeline's Select button (once), move, Command K,
  move, Command K, click the middle piece, Delete. 6 actions plus the first
  click, and the click on the piece had to hit it.
- Head trim: move, Command K, click the front piece, Delete. 4 actions.

## Re-running this

`Scripts/playtest/an-editing-session-walk.json` runs in every rotating check.
The ninety second cut is `Scripts/playtest/the-ninety-second-cut-walk.json`
(about 20 s: `Scripts/playtest.sh Scripts/playtest/the-ninety-second-cut-walk.json --no-build`);
its `clickRuler` step is one click on the ruler at a named moment, since a
walk's plain click reaches the canvas and never the ruler.
For the rest of the five minute half, make a long talking recording
(`say -f script.txt -o talk.aiff`, then `ffmpeg -f lavfi -i testsrc2=size=2880x1800:rate=30 -i talk.aiff -t 300 …`)
and open it with an `open` step. The walks used on 2026-09-24 are summarised in
the task log of `measure-the-video-editor-against-premiere-and-fi`.
