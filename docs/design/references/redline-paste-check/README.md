# Redline paste check

Does a Shift Command C copy from Photonz paste as the picture or as the spec
list? This kit answers it on one Mac without pasting anything into a real chat
or web service. Run 2026-10-08; findings are in
`queue/audits/2026-10-08-redline-paste.json`.

## Steps

1. Save whatever is on the clipboard: `swiftc -O board.swift -o board && ./board save <dir>`.
2. Put a real redline copy on it: `Scripts/playtest.sh Scripts/playtest/redline-walk.json`
   (it ends on Copy Merged, Shift Command C, with five measurements).
   `./board dump` should list `public.png`, `public.tiff`, `public.utf8-plain-text`.
3. Chromium. Headless Chrome has its own empty clipboard, so use a real window
   with a throwaway profile, opened in the background:
   ```
   open -g -n -a "Google Chrome" --args --remote-debugging-port=9334 \
     --user-data-dir=/tmp/paste-check-profile --no-first-run about:blank
   node cdp.mjs 9334 file://$PWD/index.html
   pkill -f "user-data-dir=/tmp/paste-check-profile"
   ```
   `cdp.mjs` focuses each box and sends Command V as the editor's own Paste
   command, then prints what the page's paste event saw and what landed.
   Same for Microsoft Edge with `-a "Microsoft Edge"`.
4. WebKit and TextEdit-style text views: `swiftc webkit.swift -o webkit && ./webkit $PWD/index.html`.
5. Put the clipboard back: `./board restore <dir>`.

`index.html` also works by hand: open it, click a box, press Command V.
