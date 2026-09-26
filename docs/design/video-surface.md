# Video: the surface, the decisions, and what has been built

> **Read this first (2026-09-23).** The target for video is **the user's
> mocks**: `docs/design/mocks/pages/video.html` (the whole editor), the thirteen
> `video-*.html` walkthroughs and studies beside it, and
> `docs/design/mocks/pages/comp-video.html` (the primitives). They were put back
> on 2026-09-23 exactly as the user drew them, **real tracks included**, after
> this document's first pass (2026-09-19) and a follow-up (2026-09-22) had
> rewritten them to fit the code: tracks renamed into layer rows, the audio
> tracks folded into clips, a Layers group put back into docks the user drew
> without one, and a page of its own (`video-shell.html`, now deleted) arguing
> that video "needs almost no new chrome" and could reuse the icon animation
> timing strip. The user rejected all of that. **Video gets the timeline the
> mock draws** (transport with scrubber and volume, ruler in seconds, red
> playhead, named track headers, clips as bars, zoom), **not the icon timing
> strip**, and **a document with time has tracks** (UX-PATTERNS D18, rewritten
> the same day).
>
> What still stands below: the transport rules (D8), the panel budget arithmetic
> (§4, as a fact about height, not an argument against tracks), trim as a tool
> (§10, answered by the user), and the cutting, titles and zoom decisions and
> their built behaviour (§11 to §13). Where those sections speak of a layer's
> "row", the mock's track is the target. §0, the row half of §2, §3 and the
> first four rows of §7 are withdrawn and say so where they stand.


**Status:** design pass, 2026-09-19; §10 added 2026-09-20 when the trim card
came back answered. Written for the task *Refine the video design so it reads as
the same app*, ahead of the five build tasks that follow it (`a-document-can-have-time`, `cut-arrange-and-retime-what-is-on-the-timeline`,
`audio-you-can-separate-add-see-and-shape`,
`captions-that-write-themselves-and-titles-that-b`,
`transitions-at-a-cut-and-effects-you-can-control`,
`components-on-the-timeline-animated-the-way-ever`).

The arithmetic in §4 is `Tests/PhotonzCoreTests/DockWithTimeTests.swift`, eight
passing tests, so the numbers here stay true or the suite goes red. The drawing
is the user's `docs/design/mocks/pages/video.html` and its walkthroughs. The
primitives are `docs/design/mocks/pages/comp-video.html`.

---

## 0. The finding in one paragraph

*Withdrawn 2026-09-23.* This section said video needed almost no new chrome,
that the icon animation timing strip could carry video as it stood, and that the
fourteen pages should stop drawing a track model. The user rejected every part
of that. What video needs is what `video.html` draws: its own timeline, with a
transport, a ruler, a playhead and tracks that hold clips, inside the ordinary
editor window. The one part of the old finding that stands is the cost: opening
the bottom dock takes height off a panel that only just fits (§4), and the
timeline has to be designed with that number in view, not argued away with it.

---

## 1. What ships today, looked at honestly

Two pictures, taken 2026-09-19 on an unlocked screen from
`Scripts/playtest/trim-with-pieces-walk.json`
(`queue/manager/shots/2026-09-19-video-three-pieces.png` and
`…-video-trim-handles.png`). They are the first honest look anybody has had at
the thing being redesigned, and five things are wrong with it.

1. **There is no shell.** No tool bar, no layers list, no panel, no document
   name. A player, one opaque bar, a row of blocks. UX-PATTERNS §1 region 8 says
   the transport and timeline appear inside the ordinary window when the
   document has time. What ships is the one shape that rule forbids.
2. **The bar teaches two vocabularies one keystroke apart.** Idle it is nine
   unlabelled glyphs with no grouping. In trim it is mostly words (Reset,
   Cancel, Done) with two glyphs left standing. The same bar, two languages, and
   the transition between them is the answer to "where did my buttons go".
   Neither language is the app's: the ordinary editor ends a crop with
   **Cancel** and a primary button named for the verb, on a glass capsule over
   the canvas. §10 settles that trim ends the same way.
3. **It is flat opaque dark**, not a glass surface, so it does not read as the
   same material as the app's other floating chrome.
4. **The accent outline means the opposite of itself.** On the strip it rings
   the piece you are holding, the one Delete takes. In trim it rings the range
   you are KEEPING, and everything outside it is thrown away. Same colour, same
   shape, opposite senses of keep and drop, on the same strip.
5. **The selected piece is the faintest block on the strip.** Unselected pieces
   are bright grey; selecting one makes it dark with a thin ring. Filed
   separately as `the-piece-you-picked-is-the-faintest-block-on-th`.

None of these are video problems. They are what happens when a feature gets its
own window.

---

## 2. The model

**A document may have a duration. A layer may have an in and an out.** That is
the whole of it, and everything else follows.

- **A clip is a layer.** It is picked on the timeline and on the canvas, styled,
  given effects, and it has an in and an out. `comp-video` §01 says it: "a clip
  is a layer with an in and an out".
- **A document with time has tracks** (UX-PATTERNS D18, rewritten 2026-09-23).
  Video, titles, audio and captions tracks, named (`V1`, `V2`, `Audio`,
  `Title`), renamable, groupable, each holding many clips, and a clip can be
  dragged from one track to another. Where there is a timeline, the timeline is
  the layer list, and the video docks carry no Layers group (`video.html`'s own
  caption, "Resolved - what the dock is for").
- *Withdrawn 2026-09-23:* "a row in the timeline is a layer", "there are no
  numbered tracks" and "a row carries a bar when the layer occupies time". The
  rows are tracks, and the timeline is the one `video.html` draws rather than
  the icon strip grown a bar.
- **A property lane opens under the track whose clip it animates**, indented and
  quieter than a track (`video-move-wt`'s Position lane, `video-zoom-wt`'s Scale
  and Centre).
- **A transition belongs to the join.** `comp-video` §02–§04 is right and
  nothing here changes it: the edit point is the selectable thing, the band
  draws over both clips, spare media draws outside them, and a dip is an outline
  inside each clip's own time.
- **Time is never a number in the panel.** In, out, duration, speed, a
  transition's length, a caption's timing: all of it is set by dragging on the
  strip. When an exact number is wanted it opens the way Position & Size now
  opens — a popover on a command and a right click — because that is the answer
  the user gave on 2026-09-15 and it is worth 130 points every time it is
  applied.

### Where each region goes

Nothing new is invented. Every row of this table is a region UX-PATTERNS §1
already names.

| What | Where | Note |
| --- | --- | --- |
| The picture | `.canvas` | The document, same as ever. Playing is the canvas drawing a different moment. |
| Play, scrub, timecodes | `.transport`, bottom dock, top row | D8 stands: volume · skip · play · loop · timecode · scrubber · timecode, nothing else. |
| Tracks, clips, cuts, waveforms, property lanes | `.timeline`, bottom dock, under the transport | The timeline `video.html` draws: track headers, clips as bars, a ruler in seconds, a red playhead. Not the icon timing strip. |
| Timeline zoom, blade, and what is scoped to the timeline | `.tlbar`, the timeline's own local bar | D8's last row. The zoom is built, §13. The blade is not: cutting is the playhead and B. |
| Which layers exist, their order, their eyes | The timeline's tracks and their headers | Where there is a timeline, the timeline is the layer list (D18). The video dock has no Layers group. |
| What the thing you picked IS | the section named after it, in the one dock | Clip · Transition · Caption · Title. It REPLACES Text, it does not stack on it. |
| What it looks like | Appearance, Effects | Unchanged. A clip takes a drop shadow like anything else. |
| What moves, and by how much | Motion | Unchanged, as the pane-load study settled. |
| Every caption in the document | Captions, an optional section | The one section video adds. Same shape as Measurements. |
| Media to pull from | Library, scope Media | D1. Not a media pool, not a new window. |
| Pick a transition | `.libtile` grid | `comp-video` §05. Not a bespoke picker. |

---

## 3. Withdrawn: "Layers does not leave"

*Withdrawn 2026-09-23.* This section argued that the user's `video.html` was
wrong to take the Layers group out of the video dock, and on the strength of it
the fourteen pages were given a Layers group on 2026-09-22. The user's design
stands: where there is a timeline, the timeline is the layer list, and the video
dock is the clip detail pane. The pages are back to that. The one fact from the
old argument worth keeping is mechanical: the app's panel code does not let
Layers be hidden today (`PanelSectionVisibility.optionalSections` omits it), so
building the user's dock is work for the timeline build, not a switch to flip.

---

## 4. The panel budget, in numbers

All of this is `DockWithTimeTests`, eight tests, green. Inputs are the heights
the pane-load study read off the running app on 2026-09-15 and the constants in
`MotionStripView`.

**Today, largest window (1680 × 1000):** the dock viewport is 968 and a piece of
text picked in a three layer document draws to **962**. It fits, for the first
time ever, and that was the entire point of taking Position & Size out a week
ago. There are six points of headroom.

**What the bottom dock costs:**

| The document | Strip height | Dock viewport left |
| --- | --- | --- |
| No time at all | 0 | 968 |
| Strip railed | 30 | 938 |
| A recording just opened: one clip, nothing animated | **88** | 880 |
| A real edit: three clips, two moving properties each | **235** | **733** |
| Twenty clips, sixty lanes | 235 (it scrolls) | 733 |

235 is a ceiling, not a trend: `bodyCeiling` is 188 and the strip scrolls rather
than growing past it.

**What video's own sections cost:** a clip picked in a five layer recording with
one drop shadow open draws to **922** — six points LESS than the same window
asks for with text picked, because the layers list is the section giving way.
Adding the Captions section costs **163**: its chrome plus a three row floor,
because it is a list and lists give up room. Nothing video adds is expensive.

**The answer, then:** at 733 the panel is **189 points over**. Not one of those
points is a section video added. It is the bottom dock, taking room off a panel
that had six points spare.

On a laptop window (688) with the strip open the viewport is **453** and the
panel is **over 280 points over**. That is not a video regression either — the
same selection is over on the same laptop today — but video makes it worse and
this document is not going to pretend otherwise.

**What the design does about it, in order:**

1. **Railing the strip buys back 205 points**, which is more than the whole
   Captions section costs. The first answer to a full panel in a video document
   is a control already on screen, and the strip's rail row says what you are
   still editing so you can find your way back (`comp-video` §06, D9).
2. **The strip opens at its shortest.** A recording just opened is one row, 88
   points, not 235. It grows as the document does.
3. **Nothing about WHEN goes in the panel.** That is what keeps the Clip section
   inside the 198 points the Text section already spends.
4. **Captions is optional**, automatic = the document has captions, so a
   document without them never pays for it.
5. **The Graph leaves the panel.** `video.html` puts a value graph in the dock
   as its own group. A graph is a picture of time and it belongs in the bottom
   dock with everything else about time, which is also the only place it has the
   width to be readable. Same argument pane-load made for the strip itself.
6. **The 189 points that are left are not video's to fix.** They belong to the
   panel work already open. This document names the number and stops.

---

## 5. Every new control against the five rules the panel just learned

The rules, from the task: a section is named for its job in words somebody
knows; a section needing a paragraph inside it is misnamed; a grid of number
boxes is the laziest answer; things set by dragging do not get permanent room;
panes can be hidden and there is an automatic mode.

| Wanted | Naming | Explains itself? | Numbers | Dragged? | Optional? |
| --- | --- | --- | --- | --- | --- |
| **Clip** (what you picked is a clip) | the word on the row in Layers | no line needed | source name, one row; in/out/speed are NOT here | yes, on the strip | no, it is the selection section |
| **Transition** | the word people use | one line, and only while there is no spare left to spend | length is dragged at the cut, not typed | yes | no |
| **Caption** (one picked) | the word on screen | no | the text itself, timing on the strip | yes | no |
| **Captions** (all of them) | plural of the same word | no | a list, like Measurements | n/a | yes, automatic on captions present |
| **Motion** | already named | already settled | one entry per moving property | bars on the strip | yes, already optional |
| Audio level | one row, "Volume", inside the selection section | no | one row with a way in; the shape over time is a lane | yes | n/a |
| Pan | second row of the same | no | one row | yes | n/a |
| **A channel strip** | — | — | — | — | **cut, see below** |

Applied to the pages on 2026-09-22: every `.grid2` of boxed `.field`s holding a
clip's in, out or duration is gone from the fourteen, and so is every paragraph
inside a panel section that existed to say what the section was for. A clip's
selection section is `Reads · Volume · Speed`; a row with a way in (the Volume
stepper, the transition's Length select) is NOT a number box and stays.

Three things the clickthroughs ask for are cut here:

- **A channel strip.** `video-audio` wants a mixer-shaped column of faders. That
  is a grid of boxes wearing a costume, and everything in it is either one row
  in the selection section (level, pan) or a shape over time (a lane). The
  master level is the volume control already on the transport. Cut.
- **The Graph group.** Moved to the bottom dock, §4 item 5.
- **A caption list inside the transport row.** `video-captions` puts "Caption
  track · Clear · Reset" on the transport row. D8: the transport holds time
  controls only. Clear and Reset are scoped to the timeline, so they go on the
  timeline's local bar.

And one rule the shipped surface breaks and the design fixes: **the accent
outline means "this is selected", always.** In trim, what is being thrown away
is drawn spent — the treatment §4 of UX-PATTERNS already defines for a stretch
of a track that is refused — and what is kept is simply not dimmed. Keep and
drop stop sharing a colour.

---

## 6. Small window, large window, no window at all

- **No time in the document:** no transport, no timeline, nothing. The window is
  exactly today's window. Already true in the app: `motionStripPhase` has a
  `.none` and `EditorView` draws nothing for it.
- **≤ 880 wide (narrow):** the dock is already a rail plus an overlay, so the
  bottom dock has the full width, which is the dimension it actually wanted.
  Transport buttons drop their labels. Unchanged from §1's responsive rules.
- **≤ 620 (tight):** the rail drops its labels, the transport compacts. The
  timeline keeps the ruler and the rows; it is the last thing to give up width
  because width is what it is for.
- **Large:** the strip does not grow with the window. It keeps the height it was
  left at and the canvas takes the rest, which is the rule pane-load set and the
  app implements. Width is what it gains, and at 1680 that is where a 200
  millisecond lag becomes a drag you can land.

### Modes and "timeline when time" are not the same mechanism, and do not need reconciling into one

They are two questions and they compose cleanly:

- **"Timeline when time" is about existence, and it is automatic.** The bottom
  dock exists because the document has a duration. Nobody chooses it; nothing
  can turn it off, because turning it off would hide the document.
- **A mode is about visibility, and it is a preset you pick.** It says which of
  the surfaces that exist are on screen right now.

So a mode may open or rail the timeline in a document that has one. It may never
conjure one in a document that does not, and it may never take one away — the
best it can do is rail it, which leaves the row that says what you are still
editing. The same split already holds in the panel:
`PanelSectionVisibility.Situation` carries facts about the DOCUMENT, and the
per-section switches carry what the person chose. Video needs nothing new here
and the modes card (`work-out-whether-the-app-needs-project-types-at`) is not
blocked by this document, nor this by it.

---

## 7. The fifteen pages, reconciled

Six questions get answered twice or more across the set. Each row says which
answer wins and what happens to the pages.

| The question | Answered N ways | The answer | What changes |
| --- | --- | --- | --- |
| **Is Layers in the dock?** | `video*` (14): no. `pane-load`, `modes`: yes. | **No, in a document with a timeline** (the user's `video.html`, restored 2026-09-23; D18). | The 2026-09-22 change that put Layers into all fourteen docks was reverted with the rest. |
| **What is a timeline row called?** | `V1 V2 V3 V4` · `Gfx` · `Audio` · `Title` · `CAP` | **A track name**, as the pages draw it, renamable by the person. | The 2026-09-19 relabelling to layer names and the 92px lowercase label column were reverted; `.track .tl` is 58px and uppercase again. |
| **What can a row BE?** | a track · a property lane · a before/after comparison | **A track, or a property lane under one.** `video-speed`'s Source/Retimed pair is the user's before-and-after and stays as drawn. | Reverted to the pages as drawn. |
| **Where does the audio of a clip live?** | on an `Audio` track | **On an audio track**, the way Premiere does it. | The 2026-09-19 answer (inside the clip until separated) is withdrawn. |
| **What does the transport's scrubber measure?** | document time (12 pages) · transition progress (`video-transitions`) · speed (`video-speed`) | **Document time. Always.** D8, and the one control whose meaning may never change. | A transition's own progress preview sits beside the transition, in its settings. |
| **Can you zoom the timeline?** | yes, `Fit 1x 2x 4x` (`video.html` only) · no (13 pages) | **Yes, on every page, on the timeline's local bar.** | `.tlbar` gets a fixed left group (select · blade · zoom) and a variable right group (what the selection is about). The Duck/Clear/Reset that pages already put there stay on the right. |

`video-cut-wt` is separately **not to be reconciled by building it**: the
2026-09-15 video-cutting audit already recorded that its last two steps open a
gap and then drag it shut by hand, which the page itself files as wrong.

---

## 8. Walking it as somebody who knows Photonz and has never seen this

Six places where a person who can use the rest of the app would predict wrong.
Honest limit: this is the runner's walk, not a person's. A real one is still
owed and the audit says so.

1. **"Where did my document go?"** Today, opening a recording opens a window
   with no title, no panel and no tools. Someone who has been redlining
   screenshots all week would not recognise it as the same app. *Fixed by the
   model: it opens the ordinary editor.*
2. **"Which of these is selected?"** On the strip, picking a piece makes it
   darker than the ones you did not pick. Everywhere else in Photonz picking
   something makes it brighter. *Fixed: accent means selected, dropped media is
   drawn spent.*
3. **"V1. Is that a layer?"** Someone whose layers are called "settings
   capture" and "Lower third" has no idea what V1 is or how it relates to the
   list they know. *Fixed: rows are layers.*
4. **"I trimmed it. Where is the bit I cut off?"** Photonz is a
   non-destructive app — nothing is baked, everything reverts — and a video
   trim that threw frames away would be the first thing in the app that did
   not. The spare-media drawing in `comp-video` §03 is the answer and it should
   not wait for transitions to arrive. *Carried into the design: trimmed media
   draws outside the clip, at low contrast, on the clip you have picked.*
5. **"How do I animate this?"** D10's obligation. On a clip the answer is the
   diamond on every property row; on a layer's panel it is the plus on Motion's
   header. Two spellings, and video uses the SECOND one, because a clip in
   Photonz is a layer and its panel is a layer's panel. `video.html` prints the
   clip catalogue in the dock, which is D10's first spelling, and D10's own
   2026-09-17 amendment says that spelling is for a surface whose whole job is
   time. *A clip's panel gets Motion with a plus, like every other layer.*
6. **"Why did my panel jump?"** Opening the strip takes 235 points off the dock
   and whatever you were reading moves. Nothing in the design fixes this; §4
   names it.

---

## 9. What this is NOT doing

So the build tasks know their edges.

- **Not choosing a codec, a container, a frame rate or an export preset.** That
  is `video-share` and it is not designed here.
- **Not designing the recorder.** How a capture starts and stops is unchanged.
- **Not building the trim tool.** §10 settles what it is and where it lives;
  moving the recording window into the ordinary one is the build task
  `a-document-can-have-time`, and the trim session moves with it.
- **Not designing send.** What Export offers a recording, and what "send it"
  means past Share, is `video-share`. §10 only says that trim hands off to the
  ordinary export the rest of the app already uses.
- **Not moving the Graph out of `video.html`'s dock.** §4 item 5 settles that a
  value graph belongs in the bottom dock, but the group on that page carries its
  own interaction code and relocating it is building. The page keeps it for now
  and the rule stands against it.
- **Not re-authoring the fourteen clickthrough walkthroughs.** Their steps are
  scripted flows. (The row renames, the label column and the Layers groups that
  a 2026-09-19 and 2026-09-22 pass did apply to them were reverted on
  2026-09-23: the pages are the user's.)
- **Not building a mixer.** §5.
- **Not fixing the panel's 189 point overflow.** §4 item 6.
- **Not deciding multi-camera, colour management, proxies or collaborative
  edit.** None of them are in the epic.

---

## 10. Trim, answered: a tool in the ordinary window

The card asked what happens to trim-and-send once a recording opens in the
ordinary window, and the answer on 2026-09-20 was **"One window, with a trim
mode in it"**: opening a recording lands you in the ordinary window, and Trim is
a tool you pick, like Crop.

That settles the shape. What follows is what it costs and what it takes, worked
out against the app rather than asserted, because "like Crop" is only an answer
if Crop is copied exactly.

### 10.1 What Crop actually does, since that is the promise

`EditorView.cropActionBar` is the shipped idiom and it has four parts:

1. **A tool in the strip.** `C` picks it, the button lights, and the canvas
   changes what a drag means.
2. **Handles on the thing whose bounds you are changing.** The picture.
3. **One glass capsule floating just clear of the tool bar**, carrying the
   tool's own settings (the aspect locks) and, at its right, **Cancel** and a
   primary button named for the verb: **Crop**.
4. **⏎ commits, ⎋ cancels**, and the capsule leaves with the mode.

Note what is NOT there. No "Done": the button says the verb, because *"a
checkmark at the far end of an 1100pt bar was never the thing a first-timer
reached for"*. No "Reset" beside Cancel. The recording window's **Reset · Cancel
· Done** is a third vocabulary, and §1 item 2 already counted it as one of the
five things wrong with that window. Copying Crop means dropping it.

### 10.2 Trim, then

- **Where it lives:** Crop's slot. That slot is already the family *change the
  picture's bounds* — Resize Image rides at the foot of its flyout — and Trim is
  bounds in time. Crop and Trim become a `ToolGroup`, so **no slot in the bar
  moves**, which is the rule `ToolBarLayout` states for every tool a flag adds.
  The flyout reads Crop · Trim, with Resize Image still at its foot.
- **Its letter:** `C`, and both members answer to it. `C` hands you the member
  you used last, `C` again swaps, and `⇧C` walks — the marquee pair's bargain,
  said with two letters instead of none.

  **Built 2026-09-20 one step away from what this said.** The plan was for Crop
  to give its `c` up to the family, the way the marquees have no letters of
  their own. That cannot be done without taking `C` off Crop in the UNGROUPED
  bar, which is what Current ships and what Next shows with tool groups off:
  that bar reads `Tool.crop.shortcutKey` directly and has no family to fall back
  on, so a nil there is a C that crops nothing. So `Tool.trim.shortcutKey` is
  `"c"` too, and `ToolGroup.bounds.groupKey` is nil. `tools(answeringTo: "c")`
  then answers `[Crop, Trim]` and everything downstream — the swap, the walk,
  the tooltip — works out the same. Nothing prints Crop's key off the family,
  because Crop never lost it.
- **When it is offered:** when the document has a duration. This is D19:
  existence is automatic, and the timeline and the tool appear on the same fact.
  In a screenshot document the slot is Crop and pressing `C` twice does nothing
  new, which means the family's ring is filtered to the members this document
  can use before it is walked. Built as `ToolGroup.tools(offered:)`, which every
  key-resolving call now takes, defaulting to the whole family so nothing else
  in the bar changed. A family filtered down to nothing still stands for its
  first member, because a slot that vanishes is a slot that moves.
- **What it puts on screen:** the handles on **the clip's bar in the timeline**,
  held up without hover, and the frames outside the clip's in and out drawn as
  **spare** at both ends, with their durations (`comp-video` §01 `.edge`, §03
  `.xspare`). The canvas keeps showing the frame under the playhead, which is
  what you are keeping. Crop puts handles on the picture because the picture is
  what it bounds; trim puts them on the bar for the same reason.
- **Its capsule:** the same glass capsule Crop uses, in the same place, floating
  clear of the tool bar. It reads `In 0:02 · Out 0:11 · 0:09 kept`, then
  **Reset**, then **Cancel** and **Trim**. Reset earns its place here and not in
  Crop's because a trim is cumulative: the clip you are trimming may already
  have been trimmed, and Reset means give me the whole recording back. It is a
  quiet button in the settings half of the capsule, not a third action beside
  the other two.
- **Its keys:** `⏎` trims, `⎋` cancels. The same two keys as Crop, and the same
  meanings.

### 10.3 A recording opens to watch (the fast lane is gone)

This section used to say a recording that is one clip and has never been edited
opens with the clip picked and Trim in hand. The user turned that down on
2026-09-25: "When I open a video, it seems defaulted into a trim workflow. I'd
prefer to be in playback mode where the edit tools are collapsed but can be
expanded." (queue task `a-recording-opens-to-watch-with-the-editing-tuck`.)

The rule now, in `PhotonzCore/TimelineOpening.swift`:

- **An untouched recording opens to watch.** Nothing picked, the arrow in hand,
  the picture over the transport, and the timeline tucked down to the mock's one
  row under it (`dock.css` `.timeline[data-tl="closed"]`: chevron, TIMELINE, the
  pick and the time, *click to expand*). Space, J/K/L and the arrows work there.
- **The row, ⌥⌘T (View ▸ Show Timeline) or the × on the timeline's bar** open
  and close it, and that choice is remembered: the next untouched recording
  opens the way you last left it.
- **Starting an edit opens it by itself**, and is not remembered: an edit key (I,
  O, M, B, Q, W, ;, ', ⌘K, ⌘T, S, the zoom keys), a Split from a right click,
  picking up Trim, or any change to the document. Captions the app writes by
  itself are not an edit.
- **A document already worked on** (a second layer, a cut, a trim) and a guide's
  sample open with the tracks showing.

Trim-and-send is now open, C for Trim (it sits in Crop's slot), drag a handle, ⏎, export:
Trim with nothing picked still finds the clip under the playhead (§10.5).

### 10.4 The two ways to change a clip's length, reconciled

The chosen option's own con. Both exist and they are not the same gesture:

- **Select, drag the end of a clip.** The quick nudge. It changes the in or the
  out and that is all you see.
- **Trim.** A session. Both ends are held up at once, the spare at each end is
  drawn so you can see what there is to take back, the capsule says the numbers,
  and ⎋ puts the clip back the way it was when you picked the tool.

Same values, same undo step, same numbers on screen. The tool adds the preview
and the way out, which is exactly the difference between dragging a layer's
corner and entering Crop.

### 10.5 The awkward corners, decided rather than left

- **Trim with nothing picked** picks the topmost layer with time under the
  playhead. In a just-opened recording that is the one clip, which is why
  picking Trim up needs no click first.
- **Trim on a layer with no time** (a background, an adjustment) does nothing
  and says so where the capsule would be: *Pick a clip to trim*. The tool is not
  hidden, because a tool that vanishes per selection is a slot that moves.
- **Clicking another clip during a session** moves the session to it. Nothing is
  lost and nothing is asked: the in and out are ordinary layer values, every
  change is already one History step, and ⌘Z is the way back. ⎋ only ever
  restores the clip you are on, and the capsule is the thing that says which one
  that is.
- **Nothing is thrown away, ever.** Trimming moves a clip's in and out. The
  frames outside them stay in the document, which is what makes the spare
  drawing honest and what answers §8's fourth prediction. A trim that deleted
  frames would be the first destructive edit in the app.
- **A cut never adds a track.** Cutting makes two clips on the same track
  (D18 item 3). Trim acts on the clip you picked.

### 10.6 What this costs, so the build task is not surprised

| What moves | Where it goes |
| --- | --- |
| `VideoEditorView`'s trim row (Reset · Cancel · Done) | one glass capsule shaped like `cropActionBar`, words changed — built 2026-09-20 as `EditorView.trimActionBar` |
| The trim handles on the piece strip | `.edge` handles on the clip's bar in the timeline |
| "Done" | "Trim", the verb, as the primary button |
| The separate recording window | gone; a recording is a document, `a-document-can-have-time` |
| `trimBeforeSession`, `resetTrimSelection`, `commitTrim`, `cancelTrim` | kept as they are, renamed to the tool's session |
| `Tool.crop.shortcutKey` | becomes nil, and `ToolGroup` carries `c`, so anything printing Crop's key (the menu item, the tooltip) reads it off the family |

**Eleven walks** exercise the shipped trim flow (`trim-*`, `undo-while-trimming`,
`save-is-live-after-a-trim`, `close-a-trimmed-recording`, the two
`tutorial-trim-a-recording` ones). They drive it through action ids —
`videoTrimDone`, not a button called "Done" — so the ids survive the move, but
every one of them opens the separate recording window and reads its strip, and
those steps do not. They are rewritten in the commit that moves the window, or
the build lands green against a surface nobody can see any more. Named in the
build task, not fixed here.

### 10.7 What §10 does not settle

- **The recorder is unchanged.** How a capture starts and stops is not touched.
- **Send is `video-share`.** Trim hands off to the export the rest of the app
  already has.
- **A trim tool for audio alone** is not a separate thing. A separated voice
  track is a layer with an in and an out, so the same tool trims it.

## 11. Cutting, arranging and retiming, answered

Built 2026-09-20. The rules the timeline keeps, written down here because the
one most likely to be got wrong by leaving it implicit is ripple, and every
editor has a different answer.

### 11.1 The ripple rule, in one sentence

**A clip's pieces lie end to end and there is never a hole between them, so
anything that changes a piece's length moves everything after it and nothing
before it.**

That one sentence covers all six edits, and it is the same sentence every time:

| What you do | What moves |
| --- | --- |
| Throw a piece away | everything after it slides back; the join closes |
| Drag a join | the piece to its left changes length; everything after slides |
| Drag the clip's left end | the clip's in point moves and the clip moves with it, so **nothing else moves at all** |
| Drag the clip's right end | nothing else moves; the clip ends somewhere new |
| Hold a frame | everything after the hold slides along |
| Retime a piece | everything after it slides along |
| Slide the whole clip | nothing inside it changes; only when it plays |

Ripple never crosses to another layer. A title under a cut stays where the
title was put, which is what makes detaching audio worth doing and what the
cut clickthrough is really about.

### 11.2 Every edge follows your hand

The gesture rule, and it is the reason the grips are arranged the way they are:

- The bar's **left end** is the clip's in point. Pulling it in shortens the
  first piece from the front and slides the clip by the same amount, so the
  edge lands under the hand and every other frame keeps the moment it had.
- Every **join**, and the bar's **right end**, is the END of the piece to its
  left. That piece grows or shrinks and the join goes where the hand puts it.

**There is deliberately no gesture for the start of a piece that is not the
first one.** The join is pinned by the piece before it, so such an edge could
only run away from the hand — the one place in the timeline where the thing you
are holding does not follow you. The job it would do belongs to the playhead
instead: B where the good part starts, then ⌫. Frame exact, and no aiming at a
four point edge.

### 11.3 What is in your hand after a cut

**The piece BEFORE the cut.** Chosen for the job people come here for: getting
rid of a fumble in the middle of a take. Cut where it starts, cut where it
ends, and the second cut leaves you holding exactly the bad bit, so ⌫ throws it
away with no click in between. Trimming dead air off an end does not need this
at all — the bar's own ends are draggable and drop nothing.

### 11.4 ⌫ takes a picked piece, never the one under the playhead

⌫ already means delete the layer. A key that silently meant something else
because of where the playhead happened to be would be the most expensive
surprise in the app, so throwing a piece away takes an explicitly picked one.
Cutting hands you one, so the common job still costs no clicks.

### 11.5 Where the mock was wrong, and why the app is shorter than it

`video-cut-wt.html` steps 7 and 8 drag a piece's left edge right so "a gap
opens where they were", then drag the piece left "until it snaps against the
first half". **Neither is possible and neither is needed**: a clip's pieces
cannot have a hole in them, so trimming already closes the join and step 8 has
nothing to do. One gesture where the mock needs two, and no way to leave a gap
you did not mean to leave.

The snap line the mock draws for step 8 still earns its place, for the job that
does need it: lining a **whole clip** up against another clip, against the
playhead, and against the two ends of the document.

The mock also makes the blade a tool ("Blade is a tool, not a menu command").
It is a command here. The playhead is already the cut line and you already
scrubbed to the frame you are looking at, so a tool to pick up and put down
buys only cutting somewhere the playhead is not — which costs you the aim
anyway.

### 11.6 A frame held (built 2026-09-21)

**A freeze is not a special object: it is a piece whose in and out are the same
frame**, which is the one sentence `video-freeze-wt` and this section share. It
is `ClipPiece` at `speedPercent` nought, so it trims, moves, takes a transition,
throws away and undoes through exactly the calls every other piece uses, and the
timeline draws it as a bar badged `hold` rather than as a second kind of object.

Four things the surface adds to that model, and nothing else:

- **The way in is where you are looking.** Freeze Frame is a button in the
  Time section and a row in the Video menu; both hold the frame under the
  playhead, because the frame you are watching is the frame you mean.
- **A chosen length**, from a short list — 1, 2, 3, 5 and 10 seconds
  (`ClipPieces.holdStopsMS`) — for the same reason the speeds are a list. Any
  other length is the hold's own end dragged on the timeline, which has no
  ceiling: a frame is held for as long as it needs.
- **The picture says it is frozen.** A badge at the top right of the canvas
  names the frame being held (`HeldFrame.badge`). A stopped picture and a
  stalled one look identical, and the difference is whether somebody trusts what
  they are watching.
- **A mark drawn on a held frame is on screen for exactly that hold.** Every
  drawing tool lands through `PhotonzDocument.addLayerDrawn(_:atTimeMS:)`, so an
  arrow drawn while the playhead stands in a hold takes the hold's in and out,
  gets its own bar lined up with it on the timeline, and animates over it
  because a layer's motion is read on its own clock. Pointing at the frozen
  frame is the reason people freeze one, and an arrow that outlives the frame it
  was pointing at is an arrow pointing at the wrong thing. Where the picture is
  playing, nothing changes: a mark stays up for the whole document as before.

**A hold pushes what the person says it pushes** (built 2026-09-22,
`HoldPush.swift`). Holding a frame inserts time, and whose time it is was the
clickthrough's own open question:

- **Everything waits**, the default. Time goes into the whole document at that
  moment: a layer starting later starts later still, and a layer the hold lands
  inside pauses and resumes where it left off — a frozen frame on a picture,
  silence on a sound. A voice recorded with the shot stays over that shot. It
  is the default because a voice that has quietly slid five seconds out of step
  is a mistake you find at the end of the edit, while a pause over a frozen
  frame is one you hear at once and undo with a click.
- **The rest carries on.** Only this clip gets longer, which is what you want
  when you froze the frame in order to talk over it, and everything after the
  hold is out of step with the picture by the hold's length on purpose.

The row is in the **Time** section, where the freeze is made, and it is the same
control before and after: before a freeze it is what the next one will do
(remembered for the window), and with a hold in hand it is what THAT hold did,
changeable there and then. `setHoldPush` is exact both ways — turned on and off
again the document is byte for byte what it was, down to the two halves of the
voice closing back into the one piece they were.

The clickthrough draws this as a segmented row called "The insert pushes", with
Everything and Picture only on it. Two things are different: it is the same list
of circles as "Hold for" directly above it rather than a segmented control the
panel uses nowhere else, and the choices are named for what you would HEAR,
because "ripple" is a word you have to already know.

**The drift is drawn, and only where there is drift.** That is the
clickthrough's closing question ("should the timeline show it, or does that
clutter the common case?") answered the narrow way: a bar running under a hold
that pushed the picture alone carries an orange hairline at the hold with `5s
out` beside it (`PhotonzDocument.holdDrifts`), and two such holds add up. A
document nobody has frozen, and one frozen with everything waiting, are both
left clean. The walk is `hold-pushes-the-sound-walk`, and it proves each choice
in the exported file: the same three layers and one click between them come out
as a nineteen second file and a fourteen second one.

What the clickthrough draws and this does not: the **hatched bar**. The bar
already badges a piece with what is unusual about it, and a second visual
language on the same bar is a lesson to learn for nothing.

### 11.7 What §11 does not settle

- **A hole INSIDE a clip cannot be written down**, so there is no "lift leaving
  a gap". That needs a model change and a card first.
- **Roll trim** (moving a join without changing the clip's length) is absent on
  purpose.
- **Reverse speed** is absent.
- **Pitch correction** is absent, and deliberately so. Retiming takes the sound
  with it at the same rate between half speed and double, so a piece sped up is
  pitched up; outside that band it plays SILENT rather than as a squeal or a
  drone, and the panel says which of the two is happening in a sentence
  (`ClipSpeedSound`). A control that holds the pitch while the speed changes
  belongs with the rest of a clip's sound if anybody asks for it.
- **A speed is chosen from a short list**, not typed: 25, 50, 100, 200, 400,
  1000 and 3000 per cent (`ClipSpeed.stops`). It runs to thirty times because
  the job is a two minute wait becoming four seconds. The list is in Video ▸
  Speed and in the **Time** section of the Properties panel, which is the same
  call and so the same single undo step (`SpeedInspector`, built 2026-09-21).
- **That section is called Time, not Speed** (renamed 2026-09-21). It carries
  everything the picked PIECE does with time — the speeds, and holding one of
  its frames — because `video-freeze-wt` is right that they are one question:
  "everything about how a clip behaves in time lives in one place: freeze,
  speed, and hold". Two sections would be two places to look for one thing.
- **Speed varies across a clip by the clip being in PIECES**, each with its own
  speed, rather than by a curve laid over the top. `video-speed` draws a speed
  curve with draggable stops and a ramp between them; a ramp is a cinematic
  flourish where these recordings are screens, and the useful shape is the
  install bar at thirty times next to the click at a quarter, which is
  piecewise. The bar in the timeline is the plot: every piece is drawn at the
  width its speed gives it and badged with it.
- **Retiming samples and never invents.** Sped up, frames are skipped and none
  are blended; slowed down, each recorded frame is shown more than once and
  nothing is made up in between. There is no optical flow in the path, and the
  panel says so rather than letting "slow motion" imply smoothing that is not
  there (`ClipSpeedFrames`).

## 12. Titles, answered: text that knows when it is on screen

Built 2026-09-21 (`next-a-title-has-an-in-and-an-out`, `TitleTime.swift`), out
of `video-title-wt`'s own sentence: **a title is a text layer that happens to
live in a document with time, so it gets an in and an out, and nothing else
about it is special.** So there is no Titles panel, no title preset, no Insert ▸
Title and no fade property. You press T, click, and type, the way you would on a
screenshot.

### 12.1 Placed in time, as against playing

The one distinction the timeline could not do without:

**A layer PLACED in time is not a layer that PLAYS.**

A clip has frames behind both its ends. A title has nothing behind it. Three
things follow, and each of them was got wrong before this was written down:

| | A clip | A title |
| --- | --- | --- |
| Left end of the bar | trims into the frames behind it; the clip stays where it was put (§11.1) | moves the moment it arrives; the far end does not budge |
| Right end | the piece ends somewhere new, as far as the media goes | ends somewhere new, and nothing stops it |
| Speed, hold a frame, split | yes, they are about frames | no: there are no frames |

`Layer.isPlacedInTime` is the whole test, and `clipToTrim` answers with nothing
while one is picked, so the Reframe, Transition and Sound sections leave the
panel rather than talking about the clip underneath while the words are
selected.

### 12.2 Where a title comes from and how long it is

It arrives at the playhead and runs for three seconds
(`TitleTime.defaultLengthMS`), never past the last frame. On a HELD frame it
takes the hold instead, which is the rule `HeldFrame` already set for a mark
drawn on a frozen frame: what is there to be pointed at is there for as long as
the frame is.

### 12.3 A fade is an animation, not a setting

**The Fade row writes one ordinary Opacity motion** with four keys — nought at
the in, full after the fade, full again before the out, nought at the out — so
it appears in the Motion list, gets a lane on the timeline, takes any curve,
undoes and reaches the export with nothing written for it. Two motions on one
property would be two answers to one question, which is why it is one motion
with stops rather than a fade-in and a fade-out.

What the clickthrough could not know: a motion is written in absolute
milliseconds, so dragging the title longer would leave the last key where it was
and the words would go out early and stay gone. `refitFade` re-cuts a fade of
that shape whenever the stretch changes length, and leaves a motion somebody has
edited by hand exactly as they left it.

### 12.4 A lane is drawn where it happens

A motion is written in its layer's own clock and the strip is drawn in the
document's, so a lane is moved along by `Layer.motionShiftMS` to be drawn where
it actually happens. Before this, a fade on a title arriving at three seconds
drew its lane at nought, saying the words come on before they exist. The hand
then works in the document's clock for the whole drag, and the landing is put
back into the layer's own clock when it is written down.

### 12.5 Chrome goes with the layer

A layer with an in and an out draws no selection box and no handles at a moment
it is not on screen. Scrub off the hold an arrow was drawn on and the arrow
goes; its box staying behind on the empty picture read as the arrow being there
and broken. The way back to it is its bar on the timeline and its row in the
layers list, both of which are still there and still picked.

---

## 13. Opening the timeline out, answered (built 2026-09-22)

The strip drew the whole document across whatever width the window happened to
be. Eight seconds fits; five minutes, which is what a real screen recording is,
is a bar a few hundred points wide where every cut is a guess.

### 13.1 A zoom is the ruler measuring less, and nothing else

`MotionStripRuler` carries a `startMS` as well as a span, and everything on the
strip is already laid out through its two calls. So the whole feature is the
ruler covering a WINDOW of the document instead of all of it
(`TimelineZoom.swift`): no second layout, no zoomed mode, and no bar, join,
waveform, grip or playhead that has to know it happened.

The one trap, and it is worth naming because it would have been silent: half
the strip asks where a MOMENT falls and the other half asks how wide a LENGTH
is. Unwindowed they are the same arithmetic. Windowed they are not, so the
ruler now answers them separately (`fraction(ofMS:)` against
`fraction(spanningMS:)`), and a duration that went through the moment call
would have drawn every bar on a zoomed timeline the wrong size.

### 13.2 Steps and a Fit, not a slider

Five minutes opens out three hundred times. A slider from the whole thing to a
second of it spends nine tenths of its travel in the first two seconds of
useful range, so the control is a minus, a plus, what is on screen said as two
moments (`1:00 to 1:30`), and Fit. Doubling reaches the closest window in eight
presses and every press is the same size. Fit is the whole way back in one
press, from however far in.

The closest window is **one second across the width**, which on an ordinary
lane is about six hundred points a second: a spoken word of a third of a second
is two hundred points of timeline, so a cut goes in the middle of a word rather
than near it. Closer buys nothing, because the frames are forty milliseconds
apart.

### 13.3 It opens out around the moment you are looking at

Every zoom keeps the playhead exactly where it is on screen. Opening out about
the left hand edge would throw you back towards the start of the recording on
every press, so the cut you were lining up would be the first thing you lost. A
playhead that is somewhere else entirely is not chased: the middle of the
window is held still instead, because holding a playhead you cannot see would
throw away the stretch you were actually looking at.

Near either end of the recording the window stops at the end, so the playhead
can sit hard against an edge. That is not the zoom failing to centre it: there
is nothing after the last frame to show.

### 13.4 Where you are, and how to move

A zoom creates a question the ruler cannot answer: how much of the recording is
behind and ahead of you. So while the strip is opened out, a thin bar over the
ruler draws the whole recording with your window marked on it and the playhead
in it. Drag the mark to move along; press the track anywhere else and the
window jumps there. It is not drawn at all when the whole document is on
screen, because then it would say only what the strip already says.

Playing a recording that is opened out **pages**: when the playhead runs off the
end, the window jumps a screenful and the playhead lands near its left hand
edge, so what is about to happen is on screen. A window that crept along a
frame at a time would pin the playhead to the right hand edge and slide the
whole strip under the pointer.

### 13.5 What is drawn is what is on screen

Opened right out, a five minute clip's bar is a hundred and eighty thousand
points wide and a waveform sampled across it is a hundred and eighty thousand
columns nobody can see. Every piece, spare, band and level line is drawn only
where it shows, plus enough slack to carry its rounded ends off screen where
the lane clips them (`TimelineSpan`). The drawing is identical; the work is
bounded by the width of the window rather than by how far the zoom has gone. A
waveform is read from the part of the file in the window, which is what makes a
zoomed waveform real detail instead of the same picture stretched.
