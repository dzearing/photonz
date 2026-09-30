# Every segmented control is now the Mac's own. Is this what you wanted?

## What changed

A **segmented control** is a row of two to four side-by-side choices where
exactly one is picked. Photonz has them in four kinds of place:

- the title bar of a recording window: **View | Edit**
- the history bar's filter: **All | Screenshots | Videos**
- panel rows, such as the Text section's **Across** and **Down** pictures, or
  the Transition section's **The overlap sits**
- dialogs, such as the export sheets

Until today Photonz drew these itself: a darker rail with a pane of glass that
slid to the picked option. You asked on 2026-09-29 why it was not the Mac's own
Liquid Glass control. Now every one of them is macOS's own segmented control,
and Photonz draws nothing on it.

## What macOS actually draws

Photographed and filmed in the app on this Mac (macOS 26):

- **One continuous track**, in the title bar too. The first View | Edit switch
  was reported as two loose buttons; that did not happen in any of today's
  pictures.
- **In the window in front**, the picked segment is **filled with your accent
  colour** (blue here).
- **In a window behind**, the picked segment is a **grey plate**.
- **A new pick switches at once.** Filmed frame by frame, Cmd-2 goes from View
  to Edit in one frame, with no slide.

Pictures (on the audit, "Every segmented control is the system's own"):

- `2026-09-29-system-segmented-before-after-sc.png`: every place, light and
  dark, before (drawn) and after (behind, then in front)
- `2026-09-29-system-segmented-title-bar-film-sc.png`: the title bar switch
  filmed across a click
- The component page, now documenting the system control:
  http://127.0.0.1:8791/pages/comp-segmented.html

## The options

**A. Keep the Mac's own control (recommended).** It stays as macOS draws it.
It follows every macOS update, matches every other Mac app, and the picked word
is always readable because nothing of ours is drawn over it.

**B. A glass toolbar for View | Edit.** Finder's view switcher looks like glass
because it sits in a real window toolbar. Recording windows would get a
toolbar, so View | Edit sits in glass. The cost is a bar across the top of the
window, which the editor was built not to have. Panel rows and dialogs stay as
in A.

**C. Back to the drawn glass.** Put back our own rail and sliding glass pane.
That is the control that overshot its rail and put a white word on white glass
in the history filter, so those would be fixed first.
