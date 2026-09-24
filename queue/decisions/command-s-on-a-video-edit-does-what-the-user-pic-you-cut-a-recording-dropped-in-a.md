# What Command S does on a video edit

## What this is about

A screen recording opens in the ordinary editor in Photonz Next. There you can
cut it into pieces, drop a second clip beside it, add music on its own track,
put a title on top that moves from one place to another, and let the captions
write themselves from the speech. The timeline looks like the one in the video
mock: `http://127.0.0.1:8791/index.html` (Video pages, `video.html`).

Today none of that can be saved. Save is dimmed, and closing the window offers
only Export. A task in the queue fixes the saving itself: File > Save As will
write a Photonz project that holds the whole edit and points at the recordings
it uses, and opening that project brings everything back.

What is left is one question: what the Command S key does on a video.

## Why it is asked again

On 2026-09-20 you were asked "You trimmed a recording and drew an arrow on it.
What should Command S do?" At the time a recording in the editor was one clip.
It is not any more: there can be many clips, sounds and captions, and there is
no single recording to write back over. That card was taken down unanswered and
this one replaces it.

## The choices

**a. Command S saves the project.** Always, whatever you did. The recordings
you used are never changed. To get a video file you Export. This is how Premiere
and Final Cut behave.

**b. A plain trim writes the recording.** If the only thing you did was shorten
one recording, Command S writes the shorter video back over the file, with the
original kept beside it, exactly as the old small recording window did. The
moment you add anything else (a second clip, a title, music, captions),
Command S saves a project instead. The window says which one it will do.

**c. Not now.** Command S stays dimmed on a video. Save As and Export are the
two ways to keep your work. Picking this retires the task.

## Worked example

You record a two minute demo, cut out a stumble, and want to send it.

- Under a: Command S saves a project. File > Export writes the MP4.
- Under b: Command S writes the shorter MP4 straight over the recording.
- Under c: Export writes the MP4; Command S does nothing.

Now you add a title and a second clip. Under a and b, Command S saves a project.
Under c, you use Save As.
