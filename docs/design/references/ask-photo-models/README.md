# Photo models on this Mac: Z-Image Turbo, Qwen-Image-2.1, MOSS-Image

The same four photo prompts (`photos.json`: the Ask eval's photo requests plus
the app's photographic look, 1296 x 816, seed 7; Qwen-Image-2.1 needs sides in
multiples of 32, so `photos-32.json` is 1280 x 800) painted by each model, one
process per model, timing each picture and reading the process's physical
footprint (what MLX's buffers count against).

    /tmp/.../guarded.sh <log> docs/design/references/ask-photo-models/benches.sh

`guarded.sh` stops the run the moment anybody touches the Mac. Needs the
Qwen-Image-2.1 scratch setup from `measure-whether-qwen-image-2-1-can-paint-and-edi`
(`~/Library/Caches/photonz-measure-qwen21`, envA for Qwen, envB for MOSS-Image)
and MOSS-Image-SFT downloaded to `~/Library/Caches/photonz-measure-photo/hf`
(25 GB, done 2026-10-30). Pictures land in `~/Library/Caches/photonz-measure-photo/out`.

## 2026-10-30

Contact sheet: `queue/audits/2026-10-30-ask-photo-models-sheet.png` (columns Z-Image,
Qwen, MOSS; rows dog, kitten, lighthouse, coffee). One line per picture in
`zimage-`, `qwen-` and `moss-2026-10-30.jsonl`.

| Model | Seconds a photo (dog, kitten, lighthouse, coffee) | Peak footprint |
| --- | --- | --- |
| Z-Image Turbo q8, 9 steps (what ships) | 54.8, 59.5, 67.9, 73.7 | 13.4 GB |
| Qwen-Image-2.1 Turbo q8, 8 steps, 1280 x 800 | 61.8, 64.6, 78.6, 81.5 | 30.6 GB |
| MOSS-Image-SFT 8-bit, 50 steps | 685.5, 685.7, 690.7, 683.0 | 21.2 GB |

All twelve read as real photographs. Qwen and MOSS put the lighthouse on a
cliff as asked, where Z-Image put it on shore rocks; MOSS has the richest light
and texture, Qwen adds props nobody asked for (latte art, a saucer).

**Picked: Z-Image Turbo stays.** Qwen-Image-2.1 is as quick but holds 30.6 GB,
which beside the planning model's 29 GB is about 60 of this Mac's 64 GB, with
the person's own apps still to fit. MOSS-Image takes eleven and a half minutes
a photo, about ten times Z-Image's minute. Worth measuring again if the
planning model is ever let go while a picture is painted (Qwen) or MOSS gains a
few step turbo.
