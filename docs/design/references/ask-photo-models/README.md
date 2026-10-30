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

* Z-Image Turbo q8 (what ships): 54.8, 59.5, 67.9 and 73.7 s; peak 13.4 GB
  (`zimage-2026-10-30.jsonl`). In the app the same requests took 60 to 64 s.
* Qwen-Image-2.1 Turbo q8: loaded at 19.7 GB, then refused 1296 x 816 (fixed:
  `photos-32.json`). Not yet painted.
* MOSS-Image-SFT 8-bit, 50 steps: loaded at 15.5 GB; stopped before its first
  picture when the person came back to the Mac.
