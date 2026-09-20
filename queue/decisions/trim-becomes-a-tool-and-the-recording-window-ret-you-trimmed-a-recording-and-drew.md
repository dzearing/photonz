# What Command S does to a recording

## What changed under this question

Until now a screen recording opened in a small window of its own. That window
played the recording, let you shorten it from either end, let you crop it, and
had one Save button. Save wrote the shortened video back over the file you
opened, and kept an untouched copy of the original beside it so a trim was
never final.

A recording now opens in the **ordinary Photonz editor** instead: the same
window a screenshot opens in, with the tool bar, the layers list and the panel,
and a timeline across the bottom because the document runs for a length of
time. That is a much bigger room, and it is the point of the change. You can
put an arrow on a recording, a title over it, a blur on a name in it, a
rounded corner, a shadow.

It also breaks Save. The ordinary editor's Command S writes a **Photonz
document** — a project file holding every layer, editable next week. The
recording window's Command S wrote a **video file**. Both are called Save, both
are on the same key, and they are not the same act. Today the app refuses to
choose: Save is dimmed for a recording, and closing the window after drawing on
one loses the drawing without asking. That is the hole this question closes.

## What you would actually do, under each answer

Take the same five minutes in each case: you record a window for eight seconds,
open it, drag the ends in so only the middle four seconds are kept, and draw a
red arrow pointing at the button you are talking about.

### A — Save writes the recording

You press Command S. About half a second later the file on disk is four seconds
long. You drag it out of the capture history into a chat and the person on the
other end gets the four seconds.

The arrow is not in that file. It is on the document, and the document is not
saved anywhere. Close the window and the app tells you so, names the arrow as
the thing that is not kept, and offers Export, which renders the arrow into the
picture.

This is today's behaviour, carried across unchanged, and it is what the eleven
scripted walks that guard trimming already expect.

### B — Save writes a project beside it

You press Command S. A file called `Recording.photonz` appears next to the
recording. Open it tomorrow and the trim and the arrow are both still there and
both still adjustable.

The recording itself is untouched: it is still eight seconds. Anybody you send
it to gets eight seconds. To hand over the four, you export.

### C — Save writes both

You press Command S and get both: the recording becomes four seconds, and a
project file appears beside it carrying the arrow.

Two files exist where you pressed one key. If you later trim the recording again
somewhere else, the project beside it is describing a video that has moved.

## What is not being asked here

- **Export is unchanged.** Command Shift E renders what you can see, arrow
  included, and that stays true under every answer.
- **The original is always preserved.** Under any answer that writes the
  recording, the untouched file is kept beside it, so a trim can be taken back
  with Revert to Original.
- **This does not decide whether trim is a tool.** It is, and it is being built:
  Trim joins Crop's slot in the tool bar, and pressing C twice swaps between
  them. Only what Save means is open.

## Where to look

- The trim tool as it is being built: `docs/design/video-surface.md` §10.
- What a recording document is: `docs/design/video.md`.
