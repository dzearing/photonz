# A sizzle reel made through the agent tools, 2026-11-26

Made from the intake window through the Photonz MCP tools alone, to find what holds
a reel back. The user had made one that morning and found it boring, with 3D
transitions that covered the picture at once, text clipped in odd places and dull
transitions.

## What was built

`new_video` 1920x1080 from History recordings 12, 10, 8, 5 (Mac screen recordings,
3456x2234), each trimmed to 3 or 4 seconds; `add_title` Launch "Ghoztty" in front,
Kinetic Bold "Every window. One glance." before the second clip; transitions at
0.8 s: pushInDepth 4 s, cube 7 s, swing 11 s, flip 14 s, doorway 17 s; music from
Apple Loops (`/Library/Audio/Apple Loops/Apple/02 Electro House`, Mega Anthem Synth 2
at 0, 7.5, 15 and Four Four Beat at 7.5, 11.25, 15) through `run_command
add_media_at_playhead`; a text callout at 15 s with `animate_in pop`; `set_speed 200`
on the 14 s clip; `add_zoom` at 12 s; the 11 s clip framed with `set_layer` (1400x905
at 260,140, corners 24, shadow, swing -14, tip 6). Exported:
`reel-agent-attempt-720p.mp4` (a 720p copy of the 1080p export).

## What went wrong, with pictures

| Picture | What it shows |
| --- | --- |
| `kinetic-bold-drops-glance.png` | Kinetic Bold at 184 pt in a 1536 wide box: "glance." is gone, the second line is never drawn |
| `cube-7s-and-kinetic-bold-entrance.png` | cube turns the frame into a panel spinning in black; then the title's entrance cuts the bottoms off its letters (7.2 s) |
| `push-in-depth-4s-covers-title.png` | the incoming clip arrives as a solid plane over the title at 3.8 s, no fade; black around the planes |
| `flip-14s-black-void.png` | mid flip the frame is almost all black |
| `swing-11s.png` | swing: a hard opaque blue plane over the incoming clip |
| `framed-clip-pops-after-swing-and-zoom-overflows.png` | the framed, tilted clip is drawn full frame and flat during the swing, then jumps to its framing at 11.6 s; the zoom at 12 s scales the whole card past the frame edges |
| `speed-200-leaves-black-gap.png` | after set_speed 200 the clip ends at 15.5 and 15.5 to 17 is black with only the callout; the doorway at 17 was taken off; the pop entrance is full size by 15.1 |
| `opening-title-static.png` | the Launch title is still from 0.4 s to 3.5 s: nothing moves |

Sound: `silencedetect -45 dB` on the export finds 14.36 to 15.04 s silent, where the
synth (7.5 to 15) and beat (11.25 to 15) hand over to the next pair at 15; the source
loops have no silence. Each sound added landed on a new audio track (six tracks for
one music bed), with no way to repeat or extend a loop.

Not reachable by an agent at all: any music beyond loose loop files, a fade on a
sound, sound effects, a backdrop behind a framed recording other than a flat colour
shape, a zoom inside a framed recording, continuous motion on a title after its
entrance.

## Correction: the first reel ran on 0.23.0

The intake window's Photonz MCP server is `/Applications/Photonz.app`'s helper, and
that app was still 0.23.0 (installed updates are a user action). Everything above
was rebuilt on Photonz Dev 0.25.0 (main 2026-11-26, driven through
`dist/Photonz Dev.app/Contents/Helpers/photonz-mcp` with `PHOTONZ_APP=dev`), same
steps, Condensed Poster in place of Kinetic Bold. Pictures in `on-0.25-dev/`.

Still there on 0.25.0: every 3D transition finding (dev-push-4s, dev-cube-7s,
dev-flip-14s), the framed clip drawn flat through the swing and the zoom past the
frame (dev-framed-11s), the black 15.5 to 17 s after set_speed 200 and the doorway
at 17 s removed (dev-speed-15s), the sound silent 14.358958 to 15.043938 s (same
numbers), the entrance cutting letter bottoms (dev-cube-7s, 7.2 s).

Different on 0.25.0: Condensed Poster's headline "Every window. One glance." runs
off the right edge of the frame instead of losing its second line (dev-title-9s);
its background is Wind Streams, the same wavy lines as the old Kinetic Bold in
ember on warm black, which the user called "so freaking amateur ... some kind of
bland wood grain" on 2026-11-26.
