# What the part after a cut says on the timeline

## What this is about

On the video timeline every clip is a coloured bar with its name written on it.
When you cut a clip with Command K, or take a stretch out of the middle with
Lift (the semicolon key), one bar becomes two parts.

Until 2026-10-08 Lift named the second part **Sample Talk copy**, as if you had
duplicated the clip. That was a bug and it is fixed: both parts now read
**Sample Talk**, which is also what Command K and Extract have always shown.

## Where the mock differs

The cut walkthrough mock (http://127.0.0.1:8791/index.html#video-cut-wt, the
step "the second half, screen-recording · 2") labels the part after a blade cut
with a number: **screen-recording · 2**.

## The two choices

- **Both parts show the clip name.** What the app does today, and what Premiere
  and Final Cut do. Picking either part still shows its own in and out in the
  panel. Choosing this closes the question; nothing gets built.
- **The part after the cut adds a number.** The first part reads Sample Talk,
  the next Sample Talk · 2, then · 3, for Command K, Lift and Extract alike, as
  the mock draws it. The number is only the label on the bar.

## Worked example

A seventeen second talk, I at 0:04, O at 0:08, semicolon:

| Choice | Left of the gap | Right of the gap |
|---|---|---|
| Clip name | Sample Talk | Sample Talk |
| Numbered | Sample Talk | Sample Talk · 2 |
