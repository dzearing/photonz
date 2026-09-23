# What a recording should do with the pointer and the clicks

## What this is about

When you record your screen in Photonz, the pointer is painted into the video
like everything else on screen. Nothing else about it is kept: not where it
went, not when you clicked, not which button.

The tools people use for screen recordings keep that information beside the
video, and it is what makes their recordings easy to follow:

- **ScreenFlow and CleanShot** draw a ring where each click happened, so a
  viewer sees what was pressed.
- **Screen Studio** zooms the picture in toward each click and eases back out,
  so a small button on a big screen is readable without any editing.
- **All three** can smooth a jittery pointer, make it larger, or hide it.

None of that can be added to a recording afterwards if the pointer was never
kept. That is the one reason to ask now rather than later: every recording made
until this is answered has lost it for good.

## What you would see under each answer

Take the same recording: you record a window for five seconds and click two
buttons.

### A: Clicks light up

You open the recording and see a soft ring appear at each of your two clicks,
for a moment, where you clicked. The rings sit on a track of their own in the
timeline. You can turn them off for this recording or drag one to a slightly
different moment.

### B: The picture follows the clicks

You open the recording and the app offers to follow your clicks. Say yes and
the picture eases in toward the first button just before you click it, holds,
and eases back out. Each zoom is an ordinary punch-in on the timeline, the same
kind you can already make by hand, so you can move it, stretch it or delete it.

### C: A clean pointer

The pointer is no longer part of the picture. It is drawn over it, so you can
smooth its path so it glides, make it bigger for a small screen, or hide it for
the whole recording. Export puts it back into the video unless you hid it.

### D: Not now

Nothing changes. Recordings keep the pointer painted in and nothing else. The
video work already queued (the timeline, tracks, clips, transitions, titles and
captions) carries on without this.

## Whatever you pick

- Recordings you already have open exactly as they do today.
- Every option but D also starts keeping the pointer and clicks for every new
  recording, so the other two options stay possible later.
- This waits behind the timeline rebuild you asked for today. It will not jump
  ahead of it.

## Where to look

- The video pages: http://127.0.0.1:8791/index.html (video section).
- Punch-in, which option B reuses, already ships in Next.
