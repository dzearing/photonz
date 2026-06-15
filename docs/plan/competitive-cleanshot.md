# Competitive reference — CleanShot X

The product we're benchmarking against (cleanshot.com, by MakeWindow). macOS only,
"50+ features in one", one-time **$29** for app + Cloud Basic (optional Pro
subscription for unlimited cloud/team). Compiled 2026-06-15 from the official
site + third-party reviews. Use this to plan the "compete with CleanShot" phases
(10–13) and the backlog; it is a feature map, not a spec.

## Feature inventory (condensed)

**Capture:** region, window (smart window detection), fullscreen, **scrolling capture**
(vertical + horizontal), capture-previous-area, self-timer, crosshair + **magnifier/loupe
with live pixel coords**, **freeze screen** (capture hover/dropdown UI), capture history
(~1 month, filterable), window backgrounds/shadows/padding at capture time.

**Recording:** MP4 (H.264) + **direct GIF**; scope window/full/region; mic and/or system
audio (independent), external interfaces; **webcam overlay** (position/size/shape); quality/FPS
controls; cursor show/hide; **click visualization**; **keystroke overlay**; built-in video
editor (trim, resolution, audio levels, stereo→mono); auto-DND, hide desktop icons,
menu-bar timer, pause/resume.

**Annotation/editor:** arrows (4 styles incl. **curved**, thickness + curvature, smart
rendering), shapes (rect/filled/ellipse/line), pencil w/ auto-smooth, text (7 styles, font
size/color), highlighter, **blur** (secure/smooth) + **pixelate** redaction, **spotlight**
(dim all but an area), **step/counter numbers**, emoji, crop w/ edge-snap, **custom color
picker w/ saved colors**, rotate/flip, change window background post-capture, **multi-image
combine**, Backgrounds tool (10 social templates, custom image, auto-balance spacing),
editable project file format.

**Organization:** **Quick Access Overlay** (post-capture floating thumbnail → save/copy/drag/
annotate/upload/delete, auto-close), **pin-to-screen** floating screenshots (size/opacity),
capture history, trackpad gesture nav.

**Workflow/sharing:** CleanShot Cloud one-click upload → instant link, **URL overwriting**
(re-upload keeps the link), self-destruct + password-protected links, tagging, custom domain/
branding, comments + view notifications, **on-device OCR** (auto language, → clipboard),
**All-In-One** panel, Raycast AI share, PNG/JPG/WebP/HEIC export, multi-page print for scrolling.

**Menu bar / shortcuts:** menu-bar-first app, fully customizable shortcuts, **one-click takeover
of the macOS system screenshot shortcuts**, deep per-app prefs. (Default bindings vary by
version/review; treat specific keys as approximate.)

## Signature features (what it's most loved for)

1. Quick Access Overlay (post-capture floating thumbnail). 2. One-click Cloud + shareable
links (self-destruct/password/comments/URL-overwrite). 3. Clean output (hide icons, window
backgrounds/padding/shadows). 4. Scrolling capture. 5. Freeze screen. 6. Pin-to-screen.
7. Step counter + smart curved arrows. 8. On-device OCR. 9. Recording extras (clicks/keystrokes/
webcam/GIF). 10. One-time $29 (no forced subscription).

## Gap analysis vs the Photonz plan (phases 10–13)

**Already planned (10–13):** undo/redo (10.1), arrow polish — *extend to curved + 4 styles* (10.2),
annotation shadow fix (10.3), menu-bar agent + ⌘⇧3/⌘⇧4 overrides + history (11), edit round-trip (11.4),
⌘⇧5 recording w/ audio + region/full + floating stop (12), text font/scale (13.1), custom color
picker + MRU (13.2), video trim/crop + MP4/GIF export (13.3–13.5).

**Already shipped (phases 1–9):** zoom callout (≈ a richer Spotlight), layers + non-destructive
styling, crop/resize/skew/rotate, `.photonz` editable project files, capture history carousel,
PNG/JPEG/HEIC export.

**Notable GAPS not yet in the plan (candidates to fold in):**
- *Capture:* **scrolling capture** (signature), **window capture** w/ smart detection,
  **freeze screen**, capture-previous-area, self-timer, magnifier/loupe + pixel coords.
- *Annotation:* **step/counter numbers** (tutorial-grade, signature), **blur + pixelate
  redaction** (privacy — high demand), **spotlight** dim, pencil/freehand, emoji, curved arrows.
- *Organization:* **Quick Access Overlay** (signature post-capture interaction),
  **pin-to-screen** floating screenshots.
- *Recording extras:* webcam overlay, **click visualization**, **keystroke overlay**, cursor
  show/hide, auto-DND + hide-desktop-icons.
- *Output polish:* **Backgrounds tool** (wrap a screenshot in a pretty padded background — very
  popular for social/marketing), WebP export.
- *Workflow:* **on-device OCR → clipboard**, All-In-One capture panel.
- *Sharing (infra-heavy, likely later/optional):* cloud upload + shareable links, URL overwriting,
  self-destruct/password links, comments. This is a backend product on its own — treat as a
  separate track, not a phase-10–13 item.

**Priorities if matching CleanShot's "loved" reputation:** Quick Access Overlay, scrolling
capture, redaction (blur/pixelate), step counter, window capture, pin-to-screen, OCR.
