# Should a video document show the Library without being asked?

## What the Library is

The Library is a section of the right-hand dock with four shelves: Media,
Comps, Styles and Systems. Media is what the open document holds. For a
picture that means the images placed in it. As of 2026-09-23 it also holds the
**recordings and sounds** a video document has been given, each as a tile with
its length in the corner. A tile stays on the shelf after its last clip is
deleted, the way a Premiere bin does, and dragging it onto a track lands it
exactly as dragging the same file in from the Finder would.

## Why this is a question

Today the Library is hidden until **View > Library** is turned on. That was
your call for pictures: *"the library pane will almost never be used"*. So
someone who only captures and redlines never sees it.

The video mock does the opposite for video. Its dock keeps the Library group
(folded, header showing) so "the media pool is still one click away", and its
blank-project steps start by filling the Library and then dragging a tile onto
an empty track:

- Mock: http://127.0.0.1:8791/pages/video.html (the dock's Library group, and
  the "Blank project" steps: Fill the Library, then Drop a first clip)

A Premiere or Final Cut editor expects the bin to be there. With the Library
hidden, they have to know to look in the View menu first.

## The options

**A. Show it folded, for video (recommended).** Any document with a timeline
shows the Library header at the bottom of the dock, folded. One click opens the
shelf. Pictures do not change: still hidden until View > Library.

**B. Show it open, for video.** Same, but opened, so the tiles are visible the
moment a recording opens. Costs dock height on every recording.

**C. Keep it behind View > Library.** One rule for everything. The video
feature still works, but only after the person finds the menu item. Picking
this retires the task.

## What it looks like today

With View > Library on, a recording plus a piece of music brought in and then
deleted shows two tiles: the recording with its first frame and `0:08`, and
the music on the mock's dark green with a waveform and `0:14`. See the audit
`queue/audits/2026-09-23-library-clips.json`.
