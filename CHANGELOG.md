# Changelog

All notable user-visible changes. Format: `## <version> — <date>`, newest first.

## 0.1.0 — 2026-06-12

First preview release — the foundation, not the product.

- Native macOS app (Apple silicon, macOS 26+) with a Liquid Glass toolbar.
- Open or drag-and-drop an image; zoom in/out; undo/redo.
- Under the hood: layered document model, GPU-accelerated Core Image compositor, snapshot undo history, and a fully tested geometry core for the editing tools to come.
- Known limits: annotation/crop/text/zoom-callout tools are visible but not wired up yet. Unsigned build — right-click → Open on first launch.
