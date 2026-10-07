# Option Delete on a video

## What this is about

Editors who learned on Premiere Pro on a Mac take a stretch out of a video and close the hole with **Option Delete** (Premiere calls it Ripple Delete). They press it many times while cutting a long recording down.

In Photonz, Option Delete belongs to Photoshop's **Edit > Fill with Foreground**, and Ripple Delete is on **Shift Delete** (Sequence menu). That was set on 2026-09-30 so that no key is printed on two menu rows.

## What happens today

On a video, with In and Out marked or with a piece of a clip picked, Option Delete does nothing at all. Fill has nothing to fill on a clip, and the timeline does not take the key. There is no message, so a Premiere editor just sees their key fail.

## Option A: Option Delete ripple deletes on the timeline

While you are working in the timeline and have a clip or a marked stretch of time picked, Option Delete takes it out and closes the gap, exactly like Shift Delete. On a title, a shape, a picture, or anywhere outside the timeline, it is still Fill with Foreground. The menu keeps showing Shift Delete as the key for Ripple Delete, so the menu still prints each key once.

## Option B: leave it

Option Delete stays Fill with Foreground and keeps doing nothing on a clip. Ripple delete is Shift Delete only. Choosing this retires the task.

## Where to look

- The video editor mock: http://127.0.0.1:8791/index.html (Project section, video pages)
- Premiere's Mac keys are listed in `docs/design/video-vs-premiere.md`.
