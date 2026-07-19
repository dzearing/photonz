# Changelog

All notable user-visible changes. Format: `## <version> — <date>`, newest first.

## 0.10.0 — 2026-07-18

**The capture history is easier to browse and quicker to navigate.** The history overlay now has matching margins on the left, right, and top, so it opens wider and gives your captures more room. When it opens, the first item is selected with a highlighted outline, and you can move between captures with the left and right arrow keys. The selected item shows its action buttons, while the others show a friendly note like "15 seconds ago" or "30 minutes ago" so you can see at a glance when each one was taken.

**Filter by what you captured.** A new segmented control at the top lets you switch between All, Screenshots, and Videos, so you can zero in on just the kind of capture you're looking for.

**Copy as GIF shows its progress.** Turning a recording into a GIF takes a moment, so a small progress toast now appears in the bottom-right corner while it's being prepared, instead of leaving you wondering whether anything is happening.

## 0.9.0 — 2026-07-18

**Video controls float and stay out of your way.** The playback controls now hover over the video, QuickTime style, instead of sitting in a fixed strip below it. They stay hidden until you move the pointer toward the bottom of the window, then fade away again once you move off, so nothing covers the video while it plays. Resting the pointer on the controls keeps them up; pressing play tucks them away. You can drag the whole controller to reposition it.

**A real volume control.** The controller now carries a volume slider and a speaker button to mute or unmute, and it remembers your level when you toggle mute. The scrubber and volume slider also got a cleaner, more native look, with a thicker rail and rounded thumbs.

**Undo only when there's something to undo.** The undo button now appears only for an edit you made this session, and its tooltip spells out exactly which action it will reverse.

## 0.8.0 — 2026-07-17

**The video editor plays like a real player.** Recordings now autoplay when opened and get a proper scrubber: a progress line with a draggable thumb, click-to-seek, and timecodes at each end, with the playback controls centered beneath it. Trim handles no longer take over the window the moment a video opens.

**Trim is now a mode, like crop.** A new scissors button (next to crop) opens trim mode with the familiar Reset, Cancel, and Done controls. Done applies your selection (undo brings it back), Cancel restores things as they were. All the edit buttons on the right side now share the same circular style, so copy and export no longer look out of place.

**Mic recordings can't fail silently anymore.** Starting a recording with a microphone selected used to hang or quietly discard the capture if macOS hadn't settled mic permission yet. Photonz now resolves microphone access before the recording starts, and if something does go wrong you get told instead of losing the take.

## 0.7.0 — 2026-07-13

**Copy straight from the capture toast.** Right after a recording finishes, the toast now has a Copy button: pick **Copy Video** for the MP4 or **Copy GIF** for an animated GIF — no need to open history first. GIFs export at the recording's own frame rate, so the motion is as smooth as what you captured.

**Recording never steals your focus.** Kicking off a recording with <kbd>⌘⇧5</kbd> from another app (say, your browser) no longer yanks an open Photonz editor window to the front. Focus stays right where you left it — whether you start the recording or cancel the setup card.

## 0.6.0 — 2026-07-10

**The video editor grew up.** Recordings now open in a window sized to show the video at its real size, appearing in one step instead of opening small and resizing. You can pinch to zoom and two-finger scroll to pan the video just like images, double-tap the trackpad to jump between fit and 100%, and double-click the empty background to maximize the window.

**Crop by drawing a rectangle.** Cropping a video now works the way you expect: drag a rectangle around the part you want to keep, then fine-tune with the handles. The moment you hit Done, the preview shows just the cropped region, so what you see is what exports. Cancel puts things back the way they were.

**Thumbnails tell the truth.** After you trim or crop a recording, its thumbnail in the capture history updates to match: the picture shows the cropped region from inside the trimmed range, and the length badge shows the trimmed duration. Recording toasts now show a real thumbnail too, with the same play button and length badge as history.

## 0.5.1 — 2026-07-07

**No more permission prompt loops.** Photonz now asks for Screen Recording and Microphone access at most once per launch. If macOS has already recorded a decision, the app respects it instead of re-prompting, and it registers itself with the system before sending you to System Settings, so the Photonz row is already there when you arrive.

**Copy polish.** All in-app text got a pass for plainer, friendlier wording.

## 0.5.0 — 2026-07-06

**Photonz updates itself.** When a new version ships, a small dot appears on the menu-bar icon and the menu offers "Update to vX.Y.Z & Restart" — one click downloads the release, verifies its signature and notarization, swaps it in, and relaunches. "Check for Updates…" offers the same in-place update. No more manual DMG downloads.

**A menu-bar icon that's actually Photonz.** The status item now shows the app icon's ring-and-aperture mark instead of a generic camera symbol, so it's easy to spot at a glance.

**Smoother permission setup.** The microphone prompt now comes to the front instead of appearing behind other windows, and the welcome panel no longer vanishes while you answer it. If macOS refuses to add Photonz to the Screen Recording list (it happens), the walkthrough now explains the fix — use the + button in System Settings — with a "Show Photonz in Finder" button that puts the app in hand for picking.

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
