# Should the panel come in with the slide?

## What this is about

A recording opens in **View**: just the picture and the transport, like a player.
Pressing **Cmd-2** (or the View | Edit switch in the title bar) slides in the
editor: the tool bar along the bottom of the canvas, the tracks under the
transport, and the panel on the right.

Until today, on a long recording with captions, the tool bar, the tracks and the
panel all filled in **after** the slide, over about 0.7 seconds, one piece at a
time.

## What changed

The tool bar and the tracks are now built out of sight while you watch in View,
so they ride in **with** the slide. The slide itself stays perfectly smooth.

The panel is the one piece that still fills in afterwards. A panel full of
settings (the Captions section alone has a dozen controls and six playing style
tiles) makes every frame of the slide more expensive: built ahead and slid in
whole, the slide drops from about 28 pictures in its first third of a second to
about 17, with pauses of up to 40ms. So by default the panel slides in empty and
its sections fill in as soon as the slide lands: Time right away, Captions about
a tenth of a second later.

## The options

- **Panel just after the slide** (what ships now). Smooth slide, panel fills in
  about 0.1s after it lands.
- **Panel with the slide.** One motion, nothing arrives afterwards, but the slide
  is noticeably less smooth on a long recording.
- **Keep looking for both.** Stay with the first for now and spend one more task
  trying to make a full panel cheap to slide. Ten different ways of moving or
  hiding the panel were measured on 2026-10-02 and none helped; only having fewer
  controls in it did.

## Try it yourself

Open a long screen recording with captions, wait a second, press Cmd-2. Then open
the Experiments window, turn on **The panel comes in with the slide**, go back to
View with Cmd-1, wait a second, and press Cmd-2 again.

Pictures of the slide as it ships:
`queue/audits/2026-10-02-edit-arrives-1-mid-slide-sc.png`,
`-2-landed-sc.png`, `-3-panel-filled-sc.png`
(audit: `queue/audits/2026-10-02-edit-arrives-with-the-slide.json`).
