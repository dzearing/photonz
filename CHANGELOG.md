# Changelog

All notable user-visible changes. Format: `## <version> — <date>`, newest first.

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
