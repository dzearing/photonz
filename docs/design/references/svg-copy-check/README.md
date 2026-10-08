# SVG copy check

Where does the SVG a Photonz copy carries actually land? This kit answers it on
one Mac without pasting anything into a real web service. Run 2026-10-08;
findings are in `queue/audits/2026-10-08-copy-an-icon-as-svg.json`. It extends
`../redline-paste-check/` (same page and driver, plus an async clipboard read).

## Steps

1. Save the clipboard: `swiftc -O board.swift -o board && ./board save <dir>`.
2. Put a clipboard on it, either:
   - the real copy: `Scripts/playtest.sh` on `Scripts/playtest/copy-an-icon-as-svg-walk.json`
     cut off after its `4-everything-copied` step (that is Copy Merged on a
     24 unit icon); `./board dump` lists `public.png`, `public.tiff`,
     `public.svg-image`;
   - or a stand-in: `swiftc -O put.swift -o put && ./put svgtype|svgtext|both`
     (a 24 px circle as PNG and TIFF, plus the SVG as its file type, as plain
     text, or both).
3. Chromium, in a real window with a throwaway profile opened in the background:
   ```
   open -g -n -a "Google Chrome" --args --remote-debugging-port=9334 \
     --user-data-dir=/tmp/paste-check-profile --no-first-run about:blank
   node cdp.mjs 9334 file://$PWD/index.html
   pkill -f "user-data-dir=/tmp/paste-check-profile"
   ```
   It prints what `navigator.clipboard.read()` offers, then what each box's
   paste event saw and what landed. `run.sh <mode>` does step 2 (stand-in) and
   this together.
4. WebKit and TextEdit-style text views: `../redline-paste-check/webkit.swift`
   with this folder's `index.html`.
5. Put the clipboard back: `./board restore <dir>`.

## What it found

- Chrome 153 hands a page `public.svg-image` as `image/svg+xml`, in the paste
  event and in `navigator.clipboard.read()`; a contenteditable box still takes
  the PNG, a textarea gets nothing.
- WebKit never offers the SVG type; NSTextView rich takes the picture, plain
  gets nothing.
- Only plain text reaches a textarea, TextEdit's plain mode or a code editor.
