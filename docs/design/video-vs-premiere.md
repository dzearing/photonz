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
| J, K, L shuttle | Works on the timeline | Works, up to 8x, **only after the timeline's own Select button is clicked**; on open, L picks the Line tool | **Gap 2** |
| Drag clips between tracks | Drag up or down | Carry up onto the track above, or past the top for a new track (tracks walk) | Works |
| A layer over video | Type tool, Essential Graphics | T and a click makes a title on its own track, keyable Position | Works, but **Gap 5** on its look |
| Detach audio | Unlink | Right-click Detach Audio | Works |
| Snapping | On, S toggles | On, snaps to playhead and clip ends; no way to switch it off | **Gap 9** |
| Undo | Command Z | Every edit is one step, including track groups and new tracks | Works |

## Gaps

| # | Gap | What Premiere does | What Photonz does | Picture | Severity | Task |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | The ruler names the wrong time when zoomed in | Ruler labels sit on the frame they name | Zoomed and scrolled, every label shifts left by the distance of the first visible tick: at 4x, 1:15 sits about 4 s from 1:15; in another view 14 s off | [4x](video-vs-premiere/ruler-at-4x.jpg), [deepest zoom](video-vs-premiere/ruler-at-max-zoom.jpg) | High (bug) | `the-timeline-ruler-names-the-right-time-when-zoo` |
| 2 | Timeline keys need a click first | J K L, I O, M, B work as soon as the sequence is open | After opening a recording the canvas has the keyboard: L is the Line tool, I Measure, K the Lens. They mean play, mark and blade only after the timeline's Select button is clicked | [L on open](video-vs-premiere/l-on-open-picks-line.jpg) | High | `premiere-s-timeline-keys-work-the-moment-a-recor` |
| 3 | Nothing removes a marked stretch | I, O, then apostrophe (Extract) or semicolon (Lift) | I and O draw the green span; apostrophe, semicolon and Shift Delete do nothing. Each stretch costs two cuts, a click on the middle piece and Delete | [marked](video-vs-premiere/in-out-marked.jpg), [after Shift Delete](video-vs-premiere/after-shift-delete.jpg) | High | `marking-an-in-and-an-out-and-pressing-one-key-ta` |
| 4 | A captioned five minute timeline freezes on every press | No hitch | With 173 captions, I freezes the app about 170 ms, backslash 445 ms, others up to 680 ms. With the captions cleared the same keys stay under 31 ms | (walk timings, in the task) | High (performance) | `a-long-captioned-recording-edits-without-freezin` |
| 5 | A new title can't be read on video | New titles start large and white | 24 pt black regular text, invisible on a dark recording | [title](video-vs-premiere/title-default-look.jpg) | Medium | `a-title-typed-over-a-video-is-readable-without-r` |
| 6 | No ripple trim to the playhead | Q and W trim the clip's start or end to the playhead and close the gap | Nothing on Q or W; the same trim is a cut, a click and Delete | none | Medium | `q-and-w-trim-the-clip-under-the-playhead-up-to-i` |
| 7 | No key for the usual transition | Command D (Final Cut: Command T) puts the default dissolve on the nearest cut | Click the cut, pick a tile, every time; Command D is Deselect | [picker](video-vs-premiere/transition-picker.jpg) | Medium | `one-key-puts-the-usual-transition-on-the-cut-at` |
| 8 | Export can't make a smaller video | 1080p, 720p and more | Format, Quality and Captions only. A 2880 x 1800 recording can only come out at full size, estimated 678 MB for five minutes | [sheet](video-vs-premiere/export-sheet-5-min.jpg) | Medium | `the-export-sheet-lets-you-pick-the-size-of-the-v` |
| 9 | Snapping can't be switched off | S, and a magnet button | Always on | none | Low | `s-switches-timeline-snapping-off-and-on` |
| 10 | A long clip is a blank bar | Frames drawn along each clip | One gradient bar. At Fit, five minutes of captions is a comb of 173 tiny pills. The mock also draws plain bars, so this is the user's call | [five minutes at Fit](video-vs-premiere/five-minutes-at-fit.jpg) | Medium | `clips-on-the-timeline-show-pictures-of-what-is-i` (decision card) |

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

Removing one stretch from the middle of a talking recording:

- **Premiere**: put the playhead there, I, move, O, apostrophe. 5 actions, nothing to aim at.
- **Photonz today**: click the timeline's Select button (once), move, Command K,
  move, Command K, click the middle piece, Delete. 6 actions plus the first
  click, and the click on the piece has to hit it.

Trimming the head of a clip to the playhead:

- **Premiere**: move, Q. 2 actions.
- **Photonz today**: move, Command K, click the front piece, Delete. 4 actions.

After gaps 2, 3 and 6 close, both counts match Premiere's. Gap 4 decides whether
they feel as fast.

## Re-running this

`Scripts/playtest/an-editing-session-walk.json` runs in every rotating check.
For the five minute half, make a long talking recording
(`say -f script.txt -o talk.aiff`, then `ffmpeg -f lavfi -i testsrc2=size=2880x1800:rate=30 -i talk.aiff -t 300 …`)
and open it with an `open` step. The walks used on 2026-09-24 are summarised in
the task log of `measure-the-video-editor-against-premiere-and-fi`.
