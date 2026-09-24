# Should clips on the timeline show pictures?

## What this is about

When you open a screen recording in Photonz Next, the timeline along the
bottom shows the recording as one long coloured bar. That bar has the clip's
name on it and nothing else. Your video mock draws clips the same way:
see the timeline at http://127.0.0.1:8791/index.html#video (the bars
labelled clip-01, clip-02, b-roll).

Premiere Pro and Final Cut Pro draw a row of small frames along each clip,
so you can see where the part you want is without playing it.

## Why it came up

A measuring pass cut a real five minute talking recording at Next defaults.
At Fit, the whole five minutes is one bar
(`docs/design/video-vs-premiere/five-minutes-at-fit.jpg`). The only ways to
find a moment were to play, to scrub, or to read the captions track.

## What you would see

- **Pictures along every clip (a).** Every video clip is a strip of small
  frames with its name in a pill. Most like Premiere. Busier than the mock.
- **Pictures only when zoomed in (b, recommended).** At Fit the timeline
  looks like the mock. Zoom in and frames fade into the clips, which is the
  moment you are looking for something.
- **Keep plain bars (c).** Exactly the mock. Finding a moment stays a job for
  scrubbing and the captions. This option retires the task.

The full comparison with Premiere is in `docs/design/video-vs-premiere.md`.
