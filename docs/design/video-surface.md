# Video, drawn against the app that exists

**Status:** design pass, 2026-09-19; §10 added 2026-09-20 when the trim card
came back answered. Written for the task *Refine the video design so it reads as
the same app*, ahead of the five build tasks that follow it (`a-document-can-have-time`, `cut-arrange-and-retime-what-is-on-the-timeline`,
`audio-you-can-separate-add-see-and-shape`,
`captions-that-write-themselves-and-titles-that-b`,
`transitions-at-a-cut-and-effects-you-can-control`,
`components-on-the-timeline-animated-the-way-ever`).

The arithmetic in §4 is `Tests/PhotonzCoreTests/DockWithTimeTests.swift`, eight
passing tests, so the numbers here stay true or the suite goes red. The drawing
is `docs/design/mocks/pages/video-shell.html`. The primitives are
`docs/design/mocks/pages/comp-video.html`.

---

## 0. The finding in one paragraph

Video needs almost no new chrome. The timing strip across the bottom already
ships, it already groups its rows under the layer they belong to, and its own
source already says video can take it as it stands. What video needs is for the
recording window to stop being a separate little player and become the ordinary
editor with time in it — and for fourteen clickthrough pages to stop drawing a
track model the app does not have. The expensive part is not the timeline. It is
that opening the bottom dock takes 235 points off a panel that only just fits
today, and no amount of tidying video's own sections gets that back.

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

- **A clip is a layer.** It is picked in the layers list, named, hidden,
  reordered, styled, given effects, and it appears in the timeline because it
  has an in and an out. There is no clip object, no track object, no media
  object. `comp-video` §01 already said this ("a clip is a layer with an in and
  an out"); the fourteen pages then drew a track model on top of it anyway.
- **A row in the timeline is a layer.** It is named with the layer's own name,
  in the layer's own letters, with the layer's own icon. It is the layers list
  turned on its side. There are no numbered tracks.
- **A row carries a bar when the layer occupies time, and is a bare heading
  when it does not.** This is the one place the shipped strip has to grow.
  `MotionStrip.swift` says today: *"A layer row is a HEADING and not a bar: the
  layer itself does not occupy time, the properties on it do."* True of a bell
  that rotates. False of a clip, which is exactly a start and an end. So the
  group row gains an optional bar, and the rule becomes: **a layer draws a bar
  when it has an in and an out, and a heading when it does not.** One rule, both
  jobs, no fork.
- **A property lane is a child of its layer's row**, revealed by the same
  disclosure the layers list already uses for a group. It is never a sibling of
  a clip. This is already how the shipped strip is built
  (`MotionStripGroup` holds `lanes`).
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
| Clips, cuts, waveforms, property lanes | `.timeline`, bottom dock, under the transport | The shipped timing strip, given a duration instead of a lap. |
| Timeline zoom, blade, and what is scoped to the timeline | `.tlbar`, the timeline's own local bar | D8's last row. Today only `video.html` draws a zoom at all. |
| Which layers exist, their order, their eyes | Layers, in the one dock | Not deleted. See §3. |
| What the thing you picked IS | the section named after it, in the one dock | Clip · Transition · Caption · Title. It REPLACES Text, it does not stack on it. |
| What it looks like | Appearance, Effects | Unchanged. A clip takes a drop shadow like anything else. |
| What moves, and by how much | Motion | Unchanged, as the pane-load study settled. |
| Every caption in the document | Captions, an optional section | The one section video adds. Same shape as Measurements. |
| Media to pull from | Library, scope Media | D1. Not a media pool, not a new window. |
| Pick a transition | `.libtile` grid | `comp-video` §05. Not a bespoke picker. |

---

## 3. Layers does not leave, and this is the pass's main correction

Every one of the fourteen video pages draws a dock of **Properties · Effects ·
Library** and no Layers. `video.html` says out loud why:

> Layers listed the same seven objects, in the same five groups, in the same
> order as the timeline — a second rendering of what you had just clicked, so
> the dock read as having no job. It is gone from this lens; where there is a
> timeline, the timeline *is* the layer list.

**The complaint is right and the conclusion is wrong.** Three reasons, and the
third is fatal.

1. **"This lens" is the language §1 forbids.** *"Image · UI · Video are not
   separate apps, and they are not modes you toggle."* A dock that loses a
   section when the document gains a duration is a lens by another name.
2. **The list is not a duplicate of the timeline, it is a projection of it.**
   The timeline orders by time across and by stack down. The layers list orders
   by stack only, and it carries what a timeline row has no room for: the eye,
   the lock, nesting, the thumbnail, rename in place. Two views of one model is
   the app's normal condition — canvas, layers and panel already all show the
   same selection.
3. **Not everything in a video document has time.** A background, an adjustment
   layer, a frame, a component master, a matte: `video-compositing` draws four
   of these and calls them V1–V4. With Layers deleted, anything without an in
   and an out has no row anywhere and becomes unreachable. That is the case the
   whole `components-on-the-timeline` task is about.

There is also no escape hatch. `PanelSectionVisibility.optionalSections` is
`library, libraryItem, measurements, motion, placement, columns, arrange,
component, shadow`. **Layers is not in it, deliberately** — *"the core sections
are not in the list at all so no set of answers can empty the panel"*. It cannot
be hidden by automatic, by a mode, or by the user.

So: **Layers stays, and the timeline's rows are named for the same layers, in
the same order, with the same icons.** The duplication `video.html` objected to
becomes the point: you learn one list and read it two ways. `pane-load.html`
already drew it this way for the icon strip — rows called "Bell body" and
"Knob", with their layer icons, under a Layers group listing the same two — and
that page is what shipped.

**The pages are wrong and they get fixed.** See §7.

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
| **Is Layers in the dock?** | `video*` (14): no. `pane-load`, `modes`: yes. | **Yes.** §3. | `video.html`'s "Resolved" caption is wrong and is rewritten (done 2026-09-19). Putting the group back into the fourteen docks is a change to fourteen laid-out pages and their scripts, so it is filed rather than claimed: only `video-shell` draws it today. |
| **What is a timeline row called?** | `V1 V2 V3 V4` · `Gfx` · `Audio` · `Source`/`Retimed` · `Position`/`Scale`/`Centre` · layer names (`pane-load`, and the shipped strip) | **The layer's own name, in the layer's own letters.** | `.track .tl` widens 58 → 92 to match `MotionStripView.labelWidth` and stops uppercasing somebody's layer name. Page labels change with it. |
| **What can a row BE?** | a track · a property lane · a before/after comparison | **A layer, or a property lane nested under one.** Nothing else. | `video-speed`'s Source/Retimed rows are a diagram about retiming, not timeline rows, and belong inside the retime settings. `video-move-wt`/`video-zoom-wt` property lanes nest under their layer. |
| **Where does the audio of a clip live?** | a permanent `Audio` track on six pages · welded to the clip on others | **Inside the clip's own row as a waveform, until you separate it; then it is its own layer with its own name and its own row.** | The permanent empty `Audio` track goes. |
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
  scripted flows; re-drawing them is building, and this is the design pass. The
  answers are settled here and in UX-PATTERNS D18; the mechanical half (row
  names, the label column, `video.html`'s wrong caption) is applied now and the
  rest is filed.
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

### 10.3 The fast lane is kept by what the window opens as, not by a second view

The chosen option says trim-and-send costs one more click than today, and its
mitigation is that Trim is the tool your hand is already on. That has to be
built, so it is stated here as a rule:

**A recording that is one clip and has never been edited opens with the clip
picked and Trim in hand.** More than one layer, or any edit in its history, and
it opens with Select, like every other document. So the flow that shipped on
2026-09-19 survives move for move:

| Today, in its own window | After, in the ordinary window |
| --- | --- |
| Open the recording | Open the recording |
| Drag a handle | Drag a handle |
| Press Done | Press ⏎ |
| Save / send | ⌘⇧E, the export the rest of the app uses |

No extra click. The tool bar shows Trim lit, so the mode is visible rather than
implied, and `V` leaves it — which is more than today's window offers, where the
only way out of trim is one of three buttons.

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
  playhead. In a just-opened recording that is the one clip, which is why the
  fast lane needs no click at all.
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
- **The strip of pieces stays a strip of pieces.** Splitting adds a piece to a
  row, not a row (D18 item 3). Trim acts on the piece you picked.

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
