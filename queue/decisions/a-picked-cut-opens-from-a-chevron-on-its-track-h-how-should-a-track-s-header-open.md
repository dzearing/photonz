# How should a track's header open the picked cut?

## What this is about

A **cut** is the place where one clip ends and the next begins on a track. When a
transition such as a cross dissolve sits on a cut, the two clips briefly overlap:
the first runs on a little past the cut while the second comes up a little early.

**Expand the Cut** opens the picked cut into two rows under its track, **A** (the
clip going out) over **B** (the clip coming in), so you can see that overlap and
the spare frames it spends. It works today from:

- the cut's right-click menu (**Expand the Cut**, ticked while open),
- the menu bar, **Clip > Expand the Cut**,
- the key **Option E**.

## What the mock asks for

The transition walkthrough mock
(<http://127.0.0.1:8791/pages/video-transition-wt.html>, step 5, "See the
overlap") also opens it from a **small chevron on the V1 track label**.

The app's track header already has an arrow there. It opens the track's
**keyed-value lanes** (the rows of keyframes under a clip), the way Premiere and
After Effects open a track. The mock has no such arrow, so its chevron cannot
simply replace this one without taking a job away from it.

## The options

**A. A second chevron while a cut is picked (recommended).** Pick a cut and a
small down chevron appears on that track's header beside its name. Click it to
open A and B; click again to close. The keyed-values arrow stays put and keeps
its one job. Cost: for as long as a cut is picked, the header has two arrows.

**B. The existing arrow does it.** With a cut picked, the header's one arrow opens
A and B; otherwise it opens keyed values. One control, as the mock draws it, but
the same arrow means two different things depending on what you picked.

**C. No header control.** Leave it on the right-click, the Clip menu and Option E.
Choosing this retires the task.
