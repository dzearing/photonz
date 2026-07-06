# Changelog

All notable user-visible changes. Format: `## <version> — <date>`, newest first.

## 0.4.0 — 2026-07-06

**Copy recordings as video or GIF.** The copy button on a recording (history overlay and video editor) now lets you choose: **Copy Video** puts the MP4 on the clipboard, **Copy GIF** re-encodes and copies an animated GIF — and both paste properly into chat apps like Microsoft Teams and Slack (the clipboard now carries the same file flavors a Finder copy does). Edited copies confirm with a toast when the clipboard is ready.

**Your trim sticks.** Trims and crops made in the video editor are now remembered next to the recording, so exporting or copying from the capture history produces the trimmed clip — not the full-length original. Reopen a recording and your trim handles are right where you left them.

**Friendlier first run.** A welcome walkthrough now guides new installs through the one-time macOS setup: granting Screen Recording (with a relaunch handoff), optionally enabling the microphone for narrated recordings, and freeing <kbd>⌘⇧3/4/5</kbd> when macOS's own screenshot shortcuts are holding them. Reopen it anytime via "Welcome & Permissions…" in the menu.

## 0.3.1 — 2026-07-05

No app changes — a cleaner install. The app bundle itself is now notarized and stapled (not just the DMG), so Photonz launches without any Gatekeeper prompt on other Macs, even on first launch with no network. If an earlier download warned that Apple "could not verify" the app, re-download — that build predated the fix.

## 0.3.0 — 2026-07-05

Photonz grew from an editor into a resident screenshot studio: it now lives in your menu bar, records your screen, measures UI like a design tool, and selects regions like Photoshop.

**Lives in your menu bar.** Photonz is now an always-available agent: capture a region (<kbd>⌘⇧4</kbd>) or full screen (<kbd>⌘⇧3</kbd>) from anywhere, slide down a global capture history overlay (<kbd>⌘⇧H</kbd>), pin any capture as a floating window, and open as many editor windows as you like — one per image. A Quick Access Overlay pops in after each capture for instant pin/edit/copy/save.

**Screen recording.** <kbd>⌘⇧5</kbd> records a region or the full screen with your choice of microphone and a floating stop button. Recordings land in history; trim and crop them in the video editor, then export MP4, GIF, or animated HEIC.

**Measure like a designer.** The new dimension tool (<kbd>I</kbd>) drags pixel-perfect measures with automatic labels, bracket or line caps, and units — and its corners magnetize to the actual UI edges in your screenshot (text baselines, buttons, borders), with ⌘ to drag free. Perfect for spacing audits and redlines.

**Photoshop-style region selection.** Box (<kbd>M</kbd>), ellipse (<kbd>⇧M</kbd>), and magic wand (<kbd>W</kbd>) selections with ⇧ add / ⌥ subtract / ⇧⌥ intersect (the cursor shows a live +/−/× badge), edge snapping, and marching ants for any shape. While a region is active: the bucket fills it, <kbd>⌫</kbd> slices it out of the layer (the layer's frame tightens to what survives), dragging moves the pixels (⌥ for a copy), <kbd>⌘C</kbd> copies the clipped composite, and <kbd>⌘J</kbd> promotes it to a layer. <kbd>⌘N</kbd> makes a new empty layer while keeping the selection, <kbd>⌘D</kbd> deselects, <kbd>⇧⌘I</kbd> inverts.

**A real fill kit.** Paint bucket (<kbd>G</kbd>) with Photoshop-style foreground/background swatches (<kbd>X</kbd> swaps), ⌥⌫ fill, ⌫ clears the Background to your background color, and growing the canvas paints the new area with it. New shapes and text draw in the current foreground color.

**Collage & canvas.** Arrange photo layers into a collage layer with live slots — drop, swap, and reflow by resizing; a Canvas pseudo-layer in the panel lets you resize the document by dragging its edges (⇧ for centered).

**Editor upgrades.** Multi-select layers by marquee and batch-delete; text scaling and a full font picker; a proper color picker with recent colors; the toolbar split into tools / colors / zoom bars with a zoom slider and % stops; undo/redo hardening and redesigned arrows.

**Shortcuts are Photoshop-consistent now**: <kbd>M</kbd>/<kbd>⇧M</kbd>/<kbd>W</kbd> select, <kbd>⌘D</kbd> deselect, <kbd>⌘N</kbd> new layer (New from Clipboard moved to <kbd>⌥⌘N</kbd>), Measure moved to <kbd>I</kbd> (Photoshop's ruler group).

## 0.2.0 — 2026-06-13

Beta. Every editing tool that was a placeholder in 0.1.0 is now wired up — Photonz is feature-complete for daily use, but still pre-1.0 while it gets real-world testing.

**Zoom callouts (the signature feature).** Press <kbd>Z</kbd>, drag a box over any detail, and Photonz flies in a magnified callout connected by leader lines. Choose a rectangle or circle, dial the magnification, and restyle the border — perfect for documentation and bug reports.

**Annotate anything.** Arrows, rectangles, ellipses, highlights, and rich text with full font control. Tools stay sticky for rapid markup, and every annotation remains editable after the fact — re-color it, change stroke width, drag its endpoints, or resize the whole thing. Text gets an automatic contrast shadow so it stays legible on any background.

**Transform tools.** Crop with a dimmed surround, thirds grid, and aspect locks; resize in pixels or percent with presets and an aspect lock; set the canvas size from any anchor; rotate with a knob and skew from the corners. Image layers can be cropped individually.

**Real layers.** A full layers panel with thumbnails, visibility, lock, opacity, drag-to-reorder, and rename. Promote any selection to its own layer (<kbd>⌘J</kbd>), then style it non-destructively — blur, opacity, borders, rounded corners, and drop shadows are all applied live at render time and never baked into pixels. One-click blur-behind (<kbd>⇧⌘B</kbd>) builds a blurred backdrop with a sharp focal cutout. Copy and paste layers, or paste images straight from the clipboard.

**Capture &amp; share.** Grab a screen region (<kbd>⌘⇧4</kbd>) or a full screen (<kbd>⌘⇧3</kbd>) directly into Photonz, browse past captures in a history carousel (<kbd>⌘⇧H</kbd>), save editable `.photonz` documents, and export PNG, JPEG, or HEIC at 1× or 2× (or copy the composite with <kbd>⇧⌘C</kbd>).

**Feels like macOS.** Liquid Glass surfaces throughout, fluid micro-animations, an app icon and About panel, an onboarding empty-state, and a complete, audited keyboard-shortcut set with full menus.

**Fast.** Metal-accelerated Core Image compositing with a content cache and dirty-rect incremental rendering: a 12-megapixel, 10-layer document re-renders in single-digit milliseconds — comfortably under one frame.

Developer ID signed. Notarization is still being finalized, so macOS may ask you to right-click → Open on first launch until a notarized build lands.

## 0.1.0 — 2026-06-12

First preview release — the foundation, not the product.

- Native macOS app (Apple silicon, macOS 26+) with a Liquid Glass toolbar.
- Open or drag-and-drop an image; zoom in/out; undo/redo.
- Under the hood: layered document model, GPU-accelerated Core Image compositor, snapshot undo history, and a fully tested geometry core for the editing tools to come.
- Known limits: annotation/crop/text/zoom-callout tools are visible but not wired up yet. Unsigned build — right-click → Open on first launch.
