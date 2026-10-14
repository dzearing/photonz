# Should a recording's own sound look like part of its picture?

## What this is about

On the timeline, a screen recording is drawn as a blue-to-violet bar on its video track (V1, V2...). The sound it was recorded with now sits on a row directly under that bar, belonging to the same track: it moves when the track moves and never ends up anywhere else. You asked for that on 2026-10-13, along with "some sort of ui affordance that it is attached".

Today the attachment is shown by:

- a short cyan staple from the picture bar down into the sound bar, where the clip starts;
- a small link mark at the start of the sound bar;
- an elbow and link mark in the sound row's header instead of a track name.

The sound bar itself keeps the dark green every sound clip wears, as the sound mock draws it: http://127.0.0.1:8791/index.html#video-audio

The picture to look at is in the audit for this work: `queue/audits/2026-10-13-sound-under-its-video-0-opened.png`.

## The options

**A. Keep sound green, joined by a staple (recommended).** Nothing changes. Sound always looks like sound, and the staple and link mark carry the join. The risk is that blue over green still reads as two things side by side.

**B. Tint the attached sound like its picture.** The sound bar under a recording takes a darker shade of the picture's own blue to violet. Picture and sound read as one clip in two parts. When you Detach Audio, the sound goes back to green on an Audio track at the bottom, so the colour change itself says the link was broken. Music and detached sound keep the mock's colours.

**C. Leave it, no more work.** This question closes and the look stays as it is.
