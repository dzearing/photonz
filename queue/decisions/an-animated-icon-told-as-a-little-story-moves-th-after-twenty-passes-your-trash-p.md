# Story icons after twenty passes: close it on your trash, or keep going?

## What this is about

You asked Ask for: *"make an animated trash icon where the lid opens and some trash is thrown in, bouncing off the lid and causing it to close."* At first you got a still drawing. That was fixed on 2026-11-08: Ask animates every story like this, beat by beat.

The task stayed open for a stricter bar: six test stories (your trash, a bell, a checkbox, a heart, an envelope, a rocket), and five of them should read as asked, 7 or more out of 10 from a judge looking at the frames. On 2026-11-10 you said keep going, judged on your trash. Eleven passes since then have reached 1 or 2 of six. The digest of 2026-11-14 said: if pass 20 does not reach 3 of 6, stop and ask you.

## What you see today

The card's picture is your exact sentence, made in the app on today's build, two laps (the reel is `queue/audits/2026-11-14-story-trash-pass20-two-laps.gif`):

1. 0.78 s: the trash flies in from the right.
2. 0.94 s: it meets the underside of the open lid.
3. 1.09 s: it steps a little way off the lid. **This is the bounce. It is there, but small.**
4. 1.25 s: the lid shuts and the trash is gone inside.

Still rough: the trash reads as a solid block in a line icon, it comes in cut by the frame edge, and a sliver of it shows under the lid in the frame it shuts.

## What pass 20 changed

- Things that pop in part way (a bell's ring marks, smoke, pieces) keep clear of the frame edge. The bell's ring marks used to sit on the edge in every look.
- Ask is told to make shakes and repeated beats big enough to see at icon size.

Two runs on this build: the bell (7.67 both times) and the checkbox (7.11, 7.22) now read as asked every time. The heart, rocket, envelope and your trash do not (between 3.8 and 6.7).

## The options

- **Close it on your trash.** The task ends. Story icons stay as they are. If one disappoints you later, say so and it comes back as a new task with that example.
- **Keep going, behind the video speed work.** The task stays open but moves behind the focus (video editing and playback that stay fast), so the loop works on it only when nothing more important is waiting.
- **Keep going now, ahead of everything.** As it has been: more passes right away, about two hours each, the score read on two runs each time.
