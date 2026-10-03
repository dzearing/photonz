# Title pages and name cards on the timeline

Task `insert-title-pages-and-name-cards-on-the-timelin`, epic
`video-titles-graphics`. Written 2026-10-03, before building.

## What the user asked for

Ready-made things to put on the timeline: full title pages (words over a
background with a simple graphic) and name cards (a name and a role that come
in at the bottom of the frame and go again). Several good presets of each, all
of it changeable, and the changed version saved as your own. It must fit the
layout that exists, and the basic edit has to be easy: title page, cross
dissolve into a recording, a name card in and out, cut to other clips, fade
everything out at the end.

## What the mock says

`video-title-wt.html`: *everything you lay over footage is a layer with an in
and an out*. A title is a text layer, clip art is an asset layer, a lower third
is a component instance from the Library. No separate titler. Its command
popover carries an **Insert** group (Title, Shape, Component instance).

## The model: a preset is a group of ordinary layers

Inserting a preset puts ONE group on the timeline, made of the layers a person
could have drawn by hand: a background box (flat or gradient), the words, and a
simple graphic (a bar, a ring, a strip). The group is placed in time like any
title (`TitleTime`) and comes on and goes off with the same keys **Animate In**
and **Animate Out** write (`ClipKeys`). So nothing here is a new kind of object:

* the bar on the timeline is the group's bar: drag its ends, right click it for
  Start/End at Playhead, Fade In/Out, Animate In/Out, transitions;
* the words, colours, fonts, background and graphic are edited with the
  controls that already edit text and shapes: double click into the group, the
  panel speaks for the piece in hand;
* the in and out animation are key diamonds on the bar, draggable, easable,
  deletable.

### Why not a linked component

The mock's lower third is a component instance, and components already work on
the timeline (the mock's own scenario, a component you built dropped from the
Library, ships today). For the app's built-in presets a linked component is the
wrong carrier, and this was checked in the running app rather than assumed: a
component dropped on a recording brings its ORIGINAL with it, drawn on the
frame and given its own extra track, which is what lets you edit the original.
A full-frame title page would arrive as two title pages and two tracks. Premiere
(Essential Graphics templates) and Final Cut (titles) both hand you a copy you
own, so that is what a preset gives. Anyone who wants linked name cards can
still make one a component (Make Component) and drop copies of it.

## Where inserting lives (the placement contract)

| Area | What it carries | Why there |
| --- | --- | --- |
| Menu bar, **Sequence** | `Insert Title Page ▸`, `Insert Name Card ▸`, each listing its presets, the person's own first | The menu bar holds every command. Sequence already holds what adds to the time (Add Sound); Final Cut puts Connect Title in Edit, Premiere in Graphics, and Photonz has neither menu. |
| Right-click on an **empty track** | `Add Title Page ▸`, `Add Name Card ▸` next to Add Text and Add Rectangle | The verbs for the thing under the pointer: an empty track is somewhere to put something. |
| Right-click on the **inserted bar** | `Save as Preset…` beside Animate In and Out | It acts on that clip. |
| Menu bar, **Clip** | `Save as Preset…` | Every right-click verb is also in the menu bar. |

No new panel, no new tool, no new window. The Library shelf is the mock's
browsing surface for things you place, and presets are tiles there too (next
section).

## What one insert does

1. Builds the preset for this document's frame size (built-ins are drawn
   against the frame; a saved preset is scaled from the frame it was saved on).
2. Places it at the playhead on a track of its own, for the kind's length:
   4 seconds for a title page, 5 for a name card.
3. Writes the preset's Animate In and Animate Out.
4. Picks it and opens its main words for typing.

## The type list

`TitleKind` is a list (title page, name card). Each kind says its name, its
length, and its presets. The menus are built by walking the list, so an end
card, a callout or a subscribe card is one more case and its presets, with no
new UI.

## Saving your own

`Save as Preset…` takes the picked group as it is now (words, colours, layout,
its in and out animation kinds, its length) and keeps it in the app's settings
under a name the person types. It then appears at the top of that kind's
submenu, above the built-ins, in every document.

## On the Library shelf

Task `title-page-and-name-card-presets-are-tiles-on-th`, 2026-10-03. The mock
drags a lower third out of the Library at scope Components onto a track
(`video-title-wt.html`, step 10), so in a document with time the Comps shelf
opens with a **Titles** group: every preset, title pages then name cards, your
own first in each, then a **Components** header over the components.

* **The picture.** `TitlePreset.preview(frame:width:)` lands the preset on a
  still document the way an insert does and draws it at the moment it has
  finished arriving, so a slide or a fade is pictured at rest. A title page is
  the whole frame. A name card on the whole frame is a speck, so its picture is
  the bottom left corner of the frame in the tile's 16:10 shape, over a dark
  backdrop. Rendered off the main thread and cached per preset, frame and size
  (`EditorState.titlePresetPicture`).
* **Click** picks it (one selection) and opens a short section: its kind and
  length and Insert at Playhead. **Double click** is Sequence > Insert, at the
  playhead on a track of its own. **Right-click**: Insert at Playhead, and
  Delete Preset on your own.
* **Drag onto the timeline** (`TitlePresetDrag`, type `com.photonz.title-preset`,
  declared in the app's Info.plist). Over a track that takes pictures, is not
  locked and is free for the whole of it, it lands on that track; over a busy
  one it goes on a new track just above it; between tracks it makes one there.
  A title never cuts into a clip, so the ghost names the kind
  (`Name Card · V2 · 0:05`) where a file says Overwrite or Insert, and there is
  no ⌘ Insert hint (`PhotonzDocument.titleLanding`). The moment snaps to clip
  edges and the playhead the way a file's does.
* The shelf's height arithmetic knows about the two headers
  (`LibraryShelfLayout.contentHeight(groups:)`, `tileTop(group:index:groups:)`).

Walk: `title-presets-library-shelf-walk` (Next defaults, pointer double click,
pick-up, held ghosts, drops). Tests: `TitlePresetShelfTests`.

