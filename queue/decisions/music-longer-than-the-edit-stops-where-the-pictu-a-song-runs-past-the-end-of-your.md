# A song that runs past the end of your cut

## What this is about

A video in Photonz is as long as whatever on its timeline ends last. Most of
the time that is the picture. A music bed changes that: songs are usually
longer than the cut they sit under.

Here is what happens today. Open a five minute recording, cut it down to
ninety seconds, press Home, and add a three minute song with
Sequence > Add Media at Playhead. The song lands on its own sound track under
the talk, and:

- the title bar says **2:59**
- the timeline runs to 3:00, the picture stopping at 1:30
- the Export sheet says **2880 × 1800 px · 30 fps · 2:59**

Export it and you get your ninety seconds, then ninety seconds of song over a
blank picture. Nothing on screen points this out except that one line on the
Export sheet.

Pictures from that run:

- `queue/manager/shots/2026-10-08-0640-music-past-the-cut.png` (the timeline)
- `queue/manager/shots/2026-10-08-0640-export-says-2-59.png` (the Export sheet)

## What other apps do

- **Premiere** does what Photonz does: the sequence runs to the end of its
  longest track, and you trim the song yourself.
- **iMovie and Clips** trim background music to the movie, and fade it out.
- **Final Cut** ends the project with its main storyline, so a song longer than
  the cut stops with it.

## The choices

### A. The song stops with the picture (recommended)

A sound you add under an edit that already has pictures is shortened to end
where the last clip ends, with a two second fade out. The video stays ninety
seconds. Drag the song's end out again if you want more of it. A sound you add
to an empty timeline, or one shorter than the cut, is left alone.

### B. The video ends at the last picture

The song keeps its full length on the timeline, and the part past the last clip
is drawn faded. The title bar, playback and the Export sheet stop where the
picture stops. A sound-only intro or outro would never be exported.

### C. Keep it as it is

Same as Premiere. Picking this closes the question and nothing gets built.

## Worked example

A ninety second cut, a three minute song added at 0:00:

| Choice | Song on the timeline | Video length | End of the song |
|---|---|---|---|
| A | 0:00 to 1:30 | 1:30 | fades out over the last two seconds |
| B | 0:00 to 3:00, faded past 1:30 | 1:30 | cut off at 1:30 |
| C | 0:00 to 3:00 | 3:00 | plays over a blank picture to 3:00 |
