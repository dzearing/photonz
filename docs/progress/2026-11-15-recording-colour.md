# Why screen recordings looked lighter and banded, and what they are now

Answered 2026-11-15 for the task "A screen recording keeps the desktop's colours
and smooth gradients".

## Reproduced

`Scripts/recording-colour-drill.sh` (probe only, `RecordingColourDiag`) puts a
panel the size of the display BEHIND every app's windows and records only that
panel (an including filter): known swatches (sRGB greys and primaries, Display
P3 primaries, dark purples), a slow grey ramp (sRGB 16 to 56) and a slow dark
purple ramp, a dark translucent pane with text, and a strip that moves every
frame (scrolling text and a spinning picture). For each way of writing the file
it screenshots the panel through the same filter, records it, and decodes a
frame 1.5 s in two ways: AVFoundation's own (what QuickTime shows) and the
editor's (`MovieFrames.picture(of:)`). Everything is colour matched into Display
P3 floats before it is read. Delta E is CIEDE2000; ramps are measured in the
display's own code values (Display P3, 0 to 255) across columns averaged over
40 rows: "bands" are flat runs of at least 12 px, "step" the jump between
neighbouring runs.

The screenshot matches the swatches exactly (every grey to the code value).
The recording made the way the app made it until today:

| Swatch (sRGB) | Screenshot | Recording in QuickTime |
| --- | --- | --- |
| grey 16 | 16 | 14 |
| grey 76 | 76 | 86 |
| grey 128 | 128 | 139 |
| pure green (0,255,0) | (0,255,0) | (127,252,87) |
| pure red | (255,0,0) | (236,58,40) |
| sky (51,128,230) | same | (82,138,228) |

Worst Delta E 5.7 inside sRGB, 6.8 on a Display P3 colour. The grey ramp came
out in 36 bands with steps of 3 code values; the screenshot shows 74 bands of
0.66. The user's own recording (3456 x 2234, H.264 Main, 8-bit 4:2:0, about
5 Mbps) has the same contour bands across its dark panes
(`queue/audits/2026-11-15-recording-colour-your-recording.png`).

## Where each error came from

1. **The stream's colours.** With no `colorSpaceName` set, ScreenCaptureKit
   hands over the display's own colours (its ICC profile, "Color LCD", which is
   Display P3 on the sRGB curve) and attaches 709 / 709 / 709 tags that are not
   what it holds.
2. **The file's tags.** `SCRecordingOutput` takes no colour or bit rate
   settings and writes 709 / 709 / 709. Read through the 709 curve, the darks
   lift (76 to 86); read as 709 primaries, P3 greens and reds go off. Setting
   the stream to sRGB fixed the hue but not the curve: 76 still played as 86.
3. **The frames' tags.** Even with Photonz's own writer, an 8-bit frame that
   says "709 curve" is CONVERTED to whatever the file says, so the error
   survives. The 10-bit frames carry no tags at all, and are encoded with the
   **BT.601 matrix whatever `colorMatrix` asks** (tagged 709 they played green
   as 21, 232, 11; tagged 601 every swatch lands within Delta E 0.5).
4. **8-bit 4:2:0.** With the colours right, 8 bits still left 36 bands with
   steps of 2.3 code values on the grey ramp.
5. **The editor's decode.** It read every movie as 8-bit 4:2:0, which put the
   bands straight back on a 10-bit file (45 bands, steps of 3.6).
6. **The bit rate** was not the cause of the banding: 10 and 40 Mbps band the
   same. The encoder's rate mode flattens the screen's own fine dither into
   one-code-value steps; only its top quality keeps it.

## Every candidate, on the moving scene

8 to 10 s each, full Retina display (3456 x 2234) at 60 fps. Load is CPU as a
share of one core, for WindowServer, replayd, VTEncoderXPCService and Photonz
(WindowServer is noisy with the person working: see the paired runs below).

| Candidate | dE in sRGB | dE P3 colours | Grey ramp bands / step | Purple ramp bands / step | Text sharpness | MB a minute moving / still |
| --- | --- | --- | --- | --- | --- | --- |
| Screenshot | | | 74 / 0.66 | 93 / 0.65 | 1 | |
| macOS, H.264 (before) | 5.74 | 6.79 | 36 / 3.02 | 48 / 2.97 | 0.98 | 237 / 46 |
| macOS, HEVC | 5.74 | 6.79 | 39 / 3.05 | 49 / 3.15 | 0.99 | 308 / |
| H.264 40 Mbps, P3, tagged | 1.35 | 0.06 | 37 / 2.25 | 54 / 3.11 | 1.00 | 153 / |
| HEVC 8-bit 20 Mbps, P3, tagged | 1.35 | 0.06 | 36 / 2.25 | 48 / 3.03 | 0.98 | 105 / |
| HEVC 10-bit 20 Mbps, P3, 601 | 0.48 | 0.09 | 70 / 0.81 | 78 / 1.16 | 0.98 | 97 / 13 |
| HEVC 10-bit 40 Mbps | 0.48 | 0.09 | 70 / 0.80 | 76 / 1.17 | 1.00 | 153 / |
| HEVC 10-bit quality 0.9 | 0.48 | 0.09 | 75 / 0.74 | 78 / 1.08 | 0.97 | 521 / |
| HEVC 10-bit quality 1.0 | 0.47 | 0.06 | 77 / 0.76 | 93 / 0.80 | 0.97 | 924 / 37 |
| ProRes 422, P3 | 0.45 | 0.02 | 78 / 0.81 | 94 / 0.88 | 0.98 | 4215 / 2912 |
| ProRes 422 HQ, P3 | 0.45 | 0.02 | 76 / 0.74 | 94 / 1.10 | 0.97 | 7917 / |

No candidate dropped a frame: every frame the stream delivered is in the file,
and the encoder was never not ready. A data rate ceiling is ignored at quality
1.0 (915 MB a minute with a 40 or 80 Mbps ceiling).

## What ships (Next, `next-a-recording-keeps-the-screens-colours`, on by default)

Photonz writes the file itself (`RecordingFileWriter`): the stream is asked for
10-bit 4:2:0 in Display P3 with the 601 matrix, every frame is tagged P3 /
sRGB curve / 601 before it is written, the file says the same, and nothing
converts on the way. HEVC Main 10, at the encoder's top quality by default.
Settings > Recording > Quality offers **Best** (default) and **Smaller files**
(an average of 0.045 bits per pixel per frame, about 20 Mbps for this screen).
The editor and the cut-copy writer read a 10-bit file at 10 bits
(`MovieDecodeFormat`). With both the Mac's sound and the microphone and macOS
left to mix them (`next-two-sounds-mixed-as-you-record` off), macOS still writes
the file.

Measured through the app's own writer and stream settings, two runs each,
alternating:

| | dE QuickTime / editor | Grey ramp QuickTime / editor | Purple ramp QuickTime / editor | MB a minute moving / still | Recording CPU (% of a core) |
| --- | --- | --- | --- | --- | --- |
| Before | 5.74 / 5.44 | 36 / 3.02, 35 / 2.85 | 48 / 2.97, 48 / 2.58 | 251 / 46 | 63.5 |
| Best (default) | 0.47 / 1.04 | 77 / 0.76, 73 / 0.99 | 93 / 0.80, 84 / 1.21 | 923 / 37 | 68.2 |
| Smaller files | 0.48 / 1.12 | 70 / 0.81, 41 / 1.25 | 77 / 1.21, 56 / 1.23 | 118 / 13 | 67.6 |

The editor's pictures are 8-bit, so a band there is one code value at least;
the encoder's noise adds a fraction. GPU busy and memory are the same in all
three. The CPU of the processes that do the recording (Photonz, replayd, the
encoder service) goes from 9.5 to 13.5 percent of one core; WindowServer is the
same (paired A/B, median difference -0.35 points).

Start, through the app's own card (`Scripts/recording-start-drill.sh`):

| | Return to first frame, median (worst) |
| --- | --- |
| Before, no sound (warm stream) | 14.7 ms (21.2) |
| After, no sound | 9.6 ms (12.7) |
| Before, the Mac's sound (cold stream) | 83.2 ms (87.4) |
| After, the Mac's sound | 69.1 ms (77.5) |

The file is made off the main thread while the stream starts, and the frames
counted meanwhile wait for it, so the file and the clock start on the same
frame (clock error 0 on every run). With sound the stream's first frame comes
after the drill's square has turned, before and after alike. Stop: the file
closes 16 ms after Stop (`Scripts/recording-latency-drill.sh`, every budget
met).

## Left rough

- At Best a screen moving end to end costs about 15 MB a second, four times
  macOS's file; a still screen costs less than macOS's. Smaller files is in
  Settings for anyone who minds.
- The editor shows its frames in 8 bits; steps there are one code value
  (measured 1.0 to 1.25 with the encoder's noise), as in any 8-bit picture.
- Exports stay sRGB (`MovieColour`): a P3 colour beyond sRGB is clipped on the
  way out, as it always was; in-gamut colours stay within two code values
  (`RecordingFileWriterTests`).
