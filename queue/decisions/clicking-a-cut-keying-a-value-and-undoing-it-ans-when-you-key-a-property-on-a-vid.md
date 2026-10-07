# Should keying a property shrink the picture?

## What this is about

On a video in Photonz Next, you animate a value by picking it from **Animate a property** in the right hand panel (for example Position on a title). The moment you do, the timeline at the bottom of the window opens a **key lane** under the clip: a thin row where the key diamonds sit.

Today that lane is added *on top of* the timeline's height. The timeline gets one lane taller, so the area above it, the picture you are animating, gets shorter, and the picture is refitted to the smaller space. On the sample recording it goes from 74% to 71%. Undo takes the lane away and the picture grows back to 74%.

## What you would see

**Option a, as today.** Every first key and every undo of it makes the picture jump a few percent. Every track stays visible without scrolling. Keying and undoing each keep the app busy about 70 ms, over the 50 ms the video goals ask for.

**Option b, the timeline keeps its height (recommended).** The key lane opens inside the timeline you already have: the tracks under the clip move down a lane, and if they no longer fit, the timeline scrolls. The picture never changes size when you key or undo. This is how Premiere Pro and Final Cut behave: adding a keyframe never resizes the program monitor. It also takes out about 7 ms of every key and every undo, because the canvas no longer has to refit.

The cost of b: on a short timeline, the bottom track (often Audio) can slide below the timeline's edge until you scroll it or drag the divider between the picture and the timeline up.

## Why it is being asked now

This came out of making clicks on the timeline answer inside 50 ms. Clicking a cut and picking a first clip got faster in this pass (the panel now builds only the sections you can see), but keying a value and undoing it did not move, and the largest single piece of what is left is this resize. Changing it is a visible change to how the window behaves, so it is yours to call.

## Where to look

- The video timeline mock: http://127.0.0.1:8791/index.html (video pages under Project)
- Walk that shows it: `Scripts/playtest/perf/animate-pick-cost-walk.json` (the `displayZoom` reading in its log goes 74, 71, 74)
