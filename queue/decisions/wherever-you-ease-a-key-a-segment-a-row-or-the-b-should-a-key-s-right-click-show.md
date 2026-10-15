# One list of curves, or a key keeps its own?

## What this is about

When something animates, it moves from one key to the next. How it speeds up
and slows down on the way is its **easing**. Today you can choose easing in
four places in the timeline:

- **right-click a key** (a diamond on a row, or a point on an open graph)
- **right-click a segment** (the line between two points on an open graph)
- **right-click a row**, under Easing
- **the Easing menu at the right of the timeline bar**, while something is picked

The animate mock draws one list for all of them:
[video-animate](http://127.0.0.1:8791/index.html#video-animate), in the
interactions table: *"Right-click a key or a segment: the easing list (the same
ten curves everywhere, then Draw a Curve), Hold, Copy Ease, Paste Ease."*

The app shows two lists today:

| Where | List |
| --- | --- |
| A key's right-click, a clip's diamond, the bar with only keys picked | Linear, Ease In, Ease Out, Ease In and Out, Hold, Bezier (Premiere's key menu) |
| A segment's right-click, a row's Easing, the bar once a segment is picked | Linear, Ease in out, Ease in, Ease out, Ease out quint, Ease out expo, Ease in out sine, Ease out back, Ease out elastic, Steps, Hold, Draw a Curve |

The key list is there because your keyframe tasks of 2026-09-23 asked for
exactly those six words.

## The catch: one word, two meanings

- On a **key**, *Ease In* means the motion slows as it **arrives** at that key
  (Premiere's meaning).
- On a **segment**, *Ease in* means the motion starts slowly as it **leaves**
  the key before it (the meaning used on the web and in the curve list).

So a person who chooses Ease In on a key and then Ease in on the segment after
it gets two different shapes from what reads like the same choice.

## Option A (recommended): one list everywhere

Every place shows the ten curves, Hold and Draw a Curve. A curve chosen on a key
shapes the segment that leaves that key, the way the mock's keys work. The
last key starts no segment, so it shapes the one arriving at it. Bezier stays
reachable by dragging a handle on the graph. The timeline bar already works
this way when a segment and points are picked together (shipped with this
card).

## Option B: keep both lists

Nothing changes. Keys keep Premiere's six; segments keep the ten curves. The
menus would gain a small heading each so they at least say which list they are.
