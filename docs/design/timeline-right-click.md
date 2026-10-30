# What a right click on the timeline offers

One table, one menu per kind of thing. The code is `TimelineMenuTable`
(`Sources/PhotonzCore/TimelineMenuTable.swift`, tested by
`TimelineMenuTableTests`); the app only draws each row
(`EditorState+TimelineMenus`, `EditorState+TimelineGap`, `EditorState+Zoom`).

## Why

The user, 2026-10-17: "I right click on a clip, and i get this enormous right
click menu which makes nearly no sense to me. It is as if we didn't consider
what these things meant in a particular context."

Measured at Next defaults on the tutorial recording, before this change: a video
clip offered **21** rows in five groups, two of them greyed; a gap offered
Ripple Delete and then the whole track header (11 rows); empty space on a busy
track offered the header's 9.

## The rules

These follow the placement contract's Right-click row (UX-PATTERNS.md: "The
verbs for the thing under the pointer", never "settings, commands about
something else"):

1. **About ten rows on top, in at most four groups.** More counts as a row.
2. **What you do at the playhead first, the clipboard and the deletes after,
   the long tail last** under one **More ▸**.
3. **A row that cannot act here is absent, not greyed.** Split is offered only
   where the playhead runs through the clip, Follow Cursor only on a zoom that
   has a cursor to follow, Join Through Edit only on a cut that reads straight
   across, Add Zoom only where a zoom fits.
4. **Rows that act at the playhead say where it is**: Split at 0:02.00, Freeze
   Frame at 0:02.00, Start at 0:03.00, End at 0:06.00, Roll Edit to 0:03.00,
   Add Key at 0:02.00, Add Click at 0:02.00…. A right click never moves the
   playhead, so the time tells you where the row will act.
5. **What a range or a box pick does still leads**, above the table's rows, as
   the range task set it up (`EditorState+RangeSection`, `EditorState+TrackRange`).
6. **Everything that left the top level is one level down under More**, so
   nothing a person could reach before is gone, and every one of those rows is
   also in the menu bar with its key (`EveryCommandIsInTheMenuBarTests`).

## The table

Each group is one block between separators. A row in brackets is only there
when it can act.

| Thing | Top level | More ▸ |
| --- | --- | --- |
| **Video clip** (a recording, a video, clips merged into one) | [Split at t ⌘B] · [Freeze Frame at t ▸] · [Speed ▸] / [Transition…] (or Transition ▸ At the Start… · At the End… where it meets clips at both ends) · [Detach Audio ⌃⇧D] · [Audio ▸] / Cut ⌘X · Copy ⌘C · Delete ⌫ · Ripple Delete ⇧⌫ / More ▸ | [Show Picture] · [Ripple Trim Start to Playhead Q] · [Ripple Trim End to Playhead W] / [Punch In ▸] · [Add Zoom] · [Suggest Zooms] · [Add Click at t…] / [Animate ▸] · [Add Key at t] · [Paste Keys] / [Break Apart] · Select Forward · Duplicate ⌘J · Rename… · [Reveal in Finder] |
| **A video's sound** (linked, under its picture) | [Split at t] · [Speed ▸] / [Detach Audio] · [Normalize ▸] · [Clean Noise] · [Reset Gain] / Cut · Copy · Delete · Ripple Delete / More ▸ | [Ripple Trim Start] · [Ripple Trim End] / [Add Captions] / Select Forward · Duplicate · Rename… · [Reveal in Finder] |
| **Sound clip** (music, a voice-over, a detached sound) | as a video's sound, Re-attach Audio in Detach Audio's place once detached | as a video's sound, and [Break Apart] |
| **Title** (a title page or a name card) | [Split at t] · [Start at t] · [End at t] / [Fade In and Out ⌃⌥F] · [Animate In ▸] · [Animate Out ▸] / Cut · Copy · Delete · Ripple Delete / More ▸ | [Fade In ▸] · [Fade Out ▸] · [Transition…] · [Animate ▸] · [Add Key at t] · [Paste Keys] / [Replay Title] · [Save as Preset…] / Select Forward · Duplicate · Rename… |
| **Picture** (a picture, a shape, clip art) | as a title | as a title |
| **Caption** | Edit Words · [Join with Next Line] · Start Here / Delete / More ▸ | the Captions track's own rows: Rewrite Captions, Timing ▸, Export Subtitles ▸, Safe Areas, [Reset Captions], [Clear Captions] |
| **Zoom bar** | [Follow Cursor] · Zoom ▸ / Delete Zoom ⌫ | none |
| **Join** (a cut in a clip, or the edit point between two) | with no transition: Apply Default Transition ⌘T · Transition…; with one: Transition… · Length ▸ · Curve ▸ · Remove Transition; then Expand the Cut ⌥E (a toggle) / [Copy Transition] · [Paste Transition] / [Roll Edit to t] · [Join Through Edit] | none |
| **Gap** | Ripple Delete ⇧⌫ / [Zoom to Fit] · [Compact Tracks] / Track ▸ | the track header's own menu |
| **Empty space** | on an empty picture track: Add Title Page ▸ · Add Name Card ▸ · Add Text · Add Rectangle · [Put Layer Here ▸] · [Paste Here]; on the Captions track its rows / [Zoom to Fit] · [Compact Tracks] / Track ▸ | the track header's own menu |

Fade In and Out leads a placed thing's second group since 2026-10-20 (the user:
"I had to select each one, add a fade in, then add a fade out"); Transition…,
which only acts where two of them meet, went under More to keep the top level
at its limit.

A recording has no fade rows since 2026-10-29 (the user: "like transition fade
out, fade in, black out. these are super redundant and one sided"). Transition…
opens the tiles at the cut, the same ones a click on the cut opens, and the dips
are tiles there; it is offered only where the clip meets another. An end that
meets nothing fades by its handle on the bar, or from the Time section, and the
handle is not drawn at an end that meets a clip unless it already fades. The
cut's own menu and the ruler's open the same tiles. Every fade row acts on all the picks when the clicked one is among
them.

Empty space with nothing to put there or take out (a busy track, at the default
zoom) shows the header's rows themselves: a menu holding only Track ▸ would be a
door to one room.

The track header's own right-click is unchanged: it is about the track.

## Before and after

Top-level rows (separators not counted), measured by
`Scripts/playtest/timeline-right-click-menus-walk.json` on the tutorial
recording, playhead parked at two seconds:

| Thing | Before | After |
| --- | --- | --- |
| Video clip | 21 | 11 |
| A video's sound | 14 | 10 |
| Sound clip (playhead before it) | 13 | 8 |
| Title | 15 | 10 |
| Picture (playhead before it) | 13 | 8 |
| Caption | no menu at all from a walk's right click; 10 rows when hovered first | 5 |
| Zoom bar | 3 | 2 (Follow Cursor absent with no cursor recorded) |
| Join (no transition) | 6 (2 greyed) | 3 |
| Gap | 11 | 2 |
| Empty space on a busy track | 9 | 9, the track's rows (unchanged) |
| Empty picture track (lane) | 15 | 7 |
