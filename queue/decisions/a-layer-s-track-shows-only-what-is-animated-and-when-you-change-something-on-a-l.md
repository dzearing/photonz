# When does a change become a key?

## What this is about

On 2026-10-12 you asked for three things that together change how animating feels:

- a small glass bar beside a layer while you move, size, turn or tilt it, with the numbers to type and a Reset;
- the same bar when you click a key, to set that key's value;
- a layer's track that lists **only what is animated**, where a property can leave (pick its row, press Delete) and come back (right-click the clip's key line for Animate, or just change it at a key).

All of it is drawn, live, on the mock page **Animate with the overlay**:
<http://127.0.0.1:8791/index.html#video-animate> (Prototype, Video). The editor at the top works: drag the title, turn it, click the diamonds, right-click the clip.

One thing the mock cannot settle without you: **when a change you make on a layer that already has keys becomes a key**. Everything else on the page is built either way.

## A worked example

A title slides in: Position has keys at 1s and 2.6s. The playhead is at 3.5s and you turn the title 30°.

- **A, always:** a Rotation row appears with keys at 1s, 2.6s (0°, what it was) and 3.5s (30°). The title turns between 2.6s and 3.5s.
- **B, record switch:** with record on, the same as A. With record off, the title is turned 30° for the whole clip and no row appears.
- **C, only on a key moment:** 3.5s is not a key moment, so the title is turned 30° for the whole clip. To animate the turn you first press Add Key at 3.5s (or click a key moment), then turn it.

## The options

**A. Always (recommended).** No switch. It is what you described ("I can click it, tweak something and the options are automatically added to that keyframe") and how Position already behaves. The cost: moving a whole animation means picking all its keys first (click the row, then drag on the canvas).

**B. A record switch**, like Apple Motion's record button, in the timeline bar. Most control, but it is a mode, and a mode in the wrong state fails silently.

**C. Only on a key moment.** No switch, and shifting a whole animation is easy, but whether a drag keys or shifts depends on exactly where the playhead sits.

## What waits on this

Only the last build task, "A layer's track shows only what is animated, and you add or remove animated properties directly". The transform bar, the key bar and the graph go ahead as drawn.
