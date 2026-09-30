# How many buttons may the right hand panel keep?

## What this is about

The right hand panel in the editor shows the thing you picked: a clip, a
sound, a caption track, a shape, a measurement. The new placement contract
(the table at the top of the design rules, written on 2026-09-29 after "zoom
isn't a tool") gives every area of the window one purpose, and the panel's is
**what the picked thing IS**: short label and value rows you read and tune.

Today the panel also carries about forty buttons that DO something once:
Normalize and Flatten on a sound, Key it on a picture layer, Copy Measurement,
Clear, Earlier and Later on captions, Apply to Every Cut on a transition, the
align buttons under Arrange, and more. The full list is in
`docs/design/ia-audit-2026-09-29.md`.

Whatever you choose, every one of these actions also gets a row in the menu bar
with its shortcut (that is already filed), and the ones that act on a thing are
on that thing's right-click menu.

## What you would see

**One main action per section (recommended).** A section keeps at most one
button: the action the section exists for. An empty Captions section still
shows Add Captions; a sound still shows Normalize; a layer you can key still
shows Key it. The rest (Flatten, Clear, Earlier, Later, Copy Measurement,
Apply to Every Cut and so on) leave the panel and live on right-click and in
the menu bar. This is how Photoshop's Properties panel behaves: mostly values,
with a small Quick Actions row.

**No buttons at all.** The panel is only rows of values, plus the + at the head
of a list (Effects, Motion) that adds to it. Adding captions to a clip is
right-click on the clip or the menu bar. This is closest to Final Cut's
inspector. The cost is that an empty section shows nothing you can press.

**Leave it as it is.** Nothing leaves the panel. The actions still get menu
rows through the menu bar task.

## Worth looking at

- The panel on a recording in Edit: `queue/audits/2026-09-29-every-area-has-one-purpose-2.png`
- The contract: `docs/design/mocks/shared/UX-PATTERNS.md`, first section.
