# Chrome copy inventory (video surfaces)

Every string the video editor's chrome draws outside the panel, with where it comes from. Taken 2026-09-25 for
`no-sentences-or-debug-readouts-anywhere-in-the-c`, after the user turned down the timeline bar's
"Playhead no animated property @ 0.00s". The rule is UX-PATTERNS §4 "What the chrome may say"; the test that holds
it is `Tests/PhotonzCoreTests/ChromeCopyBudgetTests.swift`. `····` is an interpolated value. Hover tips, walk probes
(`panelReadout`, `playtestControl`) and screen-reader words are not drawn and are not listed.

Regenerate: build `CopyBudget.phrases(inSwift:)` into a small script over the files in `ChromeCopyBudgetTests.videoFiles`.

## What changed

| Where | Before | After |
| --- | --- | --- |
| Timeline bar, right end (`TimelineDock.swift`) | `Playhead Position 900, 330 @ 2.00s` pill, always there with a layer picked; `Playhead no animated property @ 0.00s` with nothing keyed | Removed. The time is in the transport, the value in the panel |
| Timeline bar, Easing (`TimelineDock.swift`) | Always shown; set the curve for keys not made yet | Shown only while keys are picked; reads and sets the picked keys' curve (and the next keys made) |
| Timeline bar while a file is dragged over (`EditorState+TimelineDrop.swift`) | `b-roll lands on V1 at 0:08` / `cutaway goes in on V1 at 0:03, pushing what is after` / `No room on V1` / `a new track, V2` | `Overwrite · V1 · 0:08` / `Insert · V1 · 0:03` / `Occupied` / `Overwrite · New V2 · 0:08` |
| Same bar, the key that changes it | `⌘ inserts` | `⌘ Insert` |
| Transition picker tiles (`TransitionPicker.swift`, `ClipTransitions.swift`) | Dips captioned `no overlap`; a tile the cut cannot afford captioned `no spare` | Dips carry no caption; an unaffordable tile is greyed with its reason in the hover tip, caption unchanged |

Pictures: `queue/audits/2026-09-25-chrome-labels-*.png` (before and after of the bar with a layer picked and with a key picked, the picker, and the drop label after).

## Every string, by file

| Source | Shows |
| --- | --- |
| `TimelineDock.swift:76` | Unmute |
| `TimelineDock.swift:76` | Mute |
| `TimelineDock.swift:84` | Go to Start |
| `TimelineDock.swift:90` | Pause |
| `TimelineDock.swift:90` | Play |
| `TimelineDock.swift:96` | Go to End |
| `TimelineDock.swift:137` | Select |
| `TimelineDock.swift:140` | Blade |
| `TimelineDock.swift:149` | Snapping |
| `TimelineDock.swift:158` | Timeline Zoom In |
| `TimelineDock.swift:171` | ⌘ Insert |
| `TimelineDock.swift:206` | EASING |
| `TimelineDock.swift:218` | Mixed |
| `TimelineDock.swift:287` | Fit |
| `TimelineDock.swift:287` | ····x |
| `TimelineDock.swift:413` | Time |
| `TimelineTrackRows.swift:177` | keyed values |
| `TimelineTrackRows.swift:261` | Unmute ···· |
| `TimelineTrackRows.swift:261` | Mute ···· |
| `TimelineTrackRows.swift:262` | Show ···· |
| `TimelineTrackRows.swift:262` | Hide ···· |
| `TimelineTrackRows.swift:268` | S |
| `TimelineTrackRows.swift:269` | Stop soloing ···· |
| `TimelineTrackRows.swift:269` | Solo ···· |
| `TimelineTrackRows.swift:277` | Unlock ···· |
| `TimelineTrackRows.swift:277` | Lock ···· |
| `TimelineTrackRows.swift:326` | Timing ···· |
| `TimelineTrackRows.swift:524` | Rename… |
| `TimelineTrackRows.swift:527` | Unmute Track |
| `TimelineTrackRows.swift:527` | Mute Track |
| `TimelineTrackRows.swift:529` | Show Track |
| `TimelineTrackRows.swift:529` | Hide Track |
| `TimelineTrackRows.swift:531` | Stop Soloing |
| `TimelineTrackRows.swift:531` | Solo Track |
| `TimelineTrackRows.swift:532` | Unlock Track |
| `TimelineTrackRows.swift:532` | Lock Track |
| `TimelineTrackRows.swift:534` | Group ···· Tracks |
| `TimelineTrackRows.swift:534` | Group Track |
| `TimelineTrackRows.swift:538` | Ungroup |
| `TimelineTrackRows.swift:543` | Add Track Above |
| `TimelineTrackRows.swift:544` | Add Track Below |
| `TimelineTrackRows.swift:546` | Delete Track |
| `TimelineTrackRows.swift:609` | ···· sound |
| `TimelineTrackRows.swift:788` | Rename… |
| `TimelineTrackRows.swift:792` | Ungroup |
| `TimelineTrackRows.swift:862` | Video Track |
| `TimelineTrackRows.swift:863` | Audio Track |
| `TimelineTrackRows.swift:864` | Captions Track |
| `ClipPiecesBar.swift:48` | ···· sound |
| `ClipPiecesBar.swift:188` | ···· bar |
| `ClipPiecesBar.swift:535` | ····x |
| `ClipPiecesBar.swift:541` | ···· piece ···· |
| `ClipPiecesBar.swift:541` | ···· clip |
| `ClipPiecesBar.swift:753` | ···· transition at join ···· |
| `ClipPiecesBar.swift:844` | ···· clip start |
| `ClipPiecesBar.swift:845` | ···· clip end |
| `ClipPiecesBar.swift:846` | ···· join ···· |
| `KeyLanesView.swift:36` | key-lanes-···· |
| `KeyLanesView.swift:311` | ···· pt |
| `CaptionWordsLane.swift:36` | Words |
| `CaptionWordsLane.swift:210` | %.2fs |
| `CaptionWordField.swift:31` | Caption word |
| `TimelineZoomBar.swift:30` | Timeline Zoom Out |
| `TimelineZoomBar.swift:35` | Timeline Zoom In |
| `TimelineZoomBar.swift:50` | Fit |
| `TimelineLaneDrop.swift:276` | ···· to ···· |
| `TransitionPicker.swift:22` | At this cut |
| `TransitionPicker.swift:77` | Set as Default Transition |
| `TransitionPicker.swift:88` | \u{2318}T |
| `EditorState+TimelineDrop.swift:17` | Locked |
| `EditorState+TimelineDrop.swift:17` | Occupied |
| `EditorState+TimelineDrop.swift:18` | Insert |
| `EditorState+TimelineDrop.swift:18` | Overwrite |
| `EditorState+TimelineDrop.swift:21` | New ···· |
| `TrimTimeline.swift:219` | Trim the start |
| `TrimTimeline.swift:219` | Trim the end |
| `MotionStripView.swift:207` | Loop Speed |
| `MotionStripView.swift:232` | Cycle Length |
| `MotionStripView.swift:237` | follows the longest |
| `MotionStripView.swift:531` | %.1fs |
| `MotionStripView.swift:938` | Previous Frame |
| `MotionStripView.swift:941` | Pause |
| `MotionStripView.swift:941` | Play |
| `MotionStripView.swift:944` | Next Frame |
| `MotionStripView.swift:1033` | %.1f dB over |
| `VideoEditorView.swift:49` | That recording |
| `VideoEditorView.swift:427` | ···· pieces |
| `VideoEditorView.swift:429` | ···· of ···· pieces |
| `VideoEditorView.swift:608` | Reset |
| `VideoEditorView.swift:612` | Cancel |
| `VideoEditorView.swift:614` | Done |
| `VideoEditorView.swift:666` | Copy Video |
| `VideoEditorView.swift:667` | Copy GIF |
| `VideoEditorView.swift:682` | Export MP4… |
| `VideoEditorView.swift:683` | Export GIF |
| `VideoEditorView.swift:688` | Export HEIC |
| `VideoEditorView.swift:719` | Reset |
| `VideoEditorView.swift:723` | Cancel |
| `VideoEditorView.swift:725` | Done |
| `VideoEditorView.swift:740` | %d:%02d.%02d |
| `VideoKitTransport.swift:174` | Scrub |

## Outside the video surfaces

Still breaking the rule on 2026-09-25, shared with the Current release and held on the shrink-only list in
`ChromeCopyBudgetTests.allowed`: the empty picture's "Drop a photo or screenshot here", the layers search's
"No layer says that", the Mode menu's two row details and its blurb, the capture history's empty states and its
Screen Recording line, the colour picker's "Nothing painted yet." and "Nothing picked yet.", and the recording crop's
"Drag to select the area to keep". Toast messages are passed in by callers across the app and are not read by the test.
