# Reserved class names: the triage pass (2026-09-01)

`node shared/check-reserved.mjs` gates the decidable damage: a page that styles a
design-system bare class without redeclaring a structural property the DS
imposes (grid columns and rows, grid area, float, absolute or fixed position,
and since this pass a pixel-literal width). Everything else a page does with a
DS name has to be judged by a person, because `#dashboard .db-ttrow .btn{flex}`
refines the real button and `.erase-cap .tag{…}` invented a new thing under an
old name, and no property list tells those apart.

This file is that judgment, so the next person does not redo it. Regenerate the
shortlist with `node shared/check-reserved.mjs --pairs`: every page rule whose
key selector is a DS bare class, the property overlap with the DS rule, and the
elements carrying the class. Judge a pair by reading the markup, not the CSS.

## How to judge a pair

- **Refinement**: the element IS the DS component and the page tunes it in
  place. `#dsys .actrow .btn{flex:1}`, `#lang-frame .lf-narrow .win{height}`,
  `.mobj .sel-ring{display:none}`. Keep the name. Zero property overlap means
  nothing here: most refinements share nothing with the DS rule.
- **Borrowing**: the element is a page-local box that happens to share a word
  with a DS component. It inherits whatever the DS rule says whether the page
  wanted it or not, and the page's own CSS looks innocent. Rename with a page
  prefix. A borrowing that redeclares everything the DS imposes is still a
  borrowing: the next DS change lands on it.
- **Hand-rolled DS component**: the page rewrote a component the DS already owns
  (`.masklist .tag` was `.masklist .rtag`). Delete the page rule and use the DS
  class.

## Renamed in this pass (borrowings)

| Page | Was | Now | What it is | What it inherited |
| --- | --- | --- | --- | --- |
| video-cut-wt, video-freeze-wt, video-move-wt, video-title-wt, video-transition-wt, video-zoom-wt | `.shot` | `.pvshot` | the fake app window inside the preview frame | `width:420px` from inspector.css's redline screenshot card. The page positioned it `left:12%;right:12%`; a set width beats `right`, so the window was 420px in a 470px frame, ran 6px past the frame and lost its right margin (measured live). Also a heavy 40px drop shadow. |
| lang-elevation | `.side .row` | `.scene-row` | a layer row in the live-example scene | `margin:7px 0` from the inspector row, stretching a 24px list row to 38px of pitch |
| lang-elevation | `.scene .tag` | `.scene-tag` | the stacking-order caption on the artboard | `white-space:nowrap` only, but `tag` is a reserved spec.css name |
| lang-spacing | `.align .tag` | `.align-tag` | the pass/fail caption under an alignment example | same |
| draw | `.erase-cap .tag` | `.cap-tag` | the Destructive / Layer mask pill in an erase caption | same |
| components | `.way .wt` | `.wname` | the title of a "ways to insert" card | `position:relative` from the walkthrough root. walkthrough.js runs `all('.wt')` and only bails because these have no steps; a future walkthrough helper that does not bail would pick them up. |
| video-captions | `.wchip .wt` | `.wword` | the word inside a caption word chip (built in JS) | same |
| iconography | `.ramp` | `.sizeramp` | the icon size ramp (a row) | the DS `.ramp` is a token ramp (a column); the page redeclared display and direction, so nothing showed yet |
| image | `.masklist .tag` | `.rtag.accent` | the "editing" state word on a mask row | not a rename: this was the DS row tag written out by hand, so the page rule is gone and the DS class is used |
| dsys | `.dspec .ramp{width:220px}` | removed | dead rule; no element in the page carries `.ramp` | nothing, it matched nothing |

## Kept as refinements (the rest of the 79 classes)

Every other pair on the `--pairs` list was read and is the DS component used as
itself. The recurring shapes, so you can recognise them fast:

- **Sizing a DS component inside a page frame**: `.selwrap{width}`,
  `.win{height;min-height}` in the narrow-window specimens, `.canvas{min-height}`
  on twenty pages, `.desk{height}`, `.pdock{width;height}`, `.vframe`, `.photo`,
  `.work{width}`, `.slrow{width}`, `.splitter{width;height;margin}` in the
  splitter spec, `.rl-frame{--rl-gut}` on every component reference page.
- **Recolouring or resizing the icon** (`.ic`): 20 pages. `.ic` is now
  allowlisted for the width guard because that is what these are.
- **Hiding or showing selection furniture** per page-local selected object:
  `.sel-ring`, `.handle`, `.mtag`, `.cring`, `.cbadge` with `display` or
  `inset`/`top` nudges. All allowlisted already.
- **Video timeline primitives that live in inspector.css**: `.track`, `.clip`,
  `.ruler`, `.playhead`, `.timeline`, `.wave`, `.xband`, `.tlrail` are refined
  on every video page. Same component, same meaning. (`video-motion` and
  `video` show 0 elements for some of these because JS builds the timeline.)
- **Layout tweaks to a DS shell part**: `.dgrp-b`, `.chat`, `.chat-h`,
  `.chat-b`, `.chat-in`, `.libgrid`, `.libtile`, `.titlebar`, `.wtitle`,
  `.lights`, `.drail`, `.cnv`, `.tiles`, `.specs`, `.hero-card`, `.hc-h`,
  `.hc-sub`, `.dlg-scrim`, `.dlg-h`, `.dlg-b`, `.mlabel`, `.setrow`, `.input`,
  `.select`, `.stepper`, `.btn`, `.chip`, `.badge`, `.kbd`, `.dot`, `.bar`,
  `.val`, `.rl`, `.note`, `.field`, `.empty`, `.tip`, `.spin`, `.cpick`,
  `.cpx`, `.cpin`, `.cplist`, `.uibtn`, `.wobj`, `.gramp`, `.codeblk`,
  `.artstack`, `.artboard-label`, `.resizer`, `.sec-h`, `.lrow`, `.shot` on
  redline (that one really is the screenshot card).

Borderline calls, recorded so nobody re-argues them from scratch:

- `lang-elevation .plate .dot` puts a digit inside the DS status dot (adds
  font and colour). It is still a dot; the inherited box-shadow is the DS's
  intent. Kept.
- `video .prow .rl` restyles the row label as a clickable, focusable target
  with sixteen properties. It is still the label of a row, so kept; if it grows
  a background at rest it has become a button and wants `.btn`.
- `ui-nested` and `ui-prototype` style `.toolbar .chip` with no chip in the
  markup. Not dead: shell.js injects `.chip` into overflowed tool bars. Kept.
- `lang-spacing .note` and `video-zoom-wt .mtag` match nothing in the markup
  today. Left alone; they are DS names used correctly if an element appears.

## Where the gate stands after this pass

- Hazard set grew from 62 to 86 guarded names by adding pixel-literal `width`.
  Three allowlist entries came with it (`ic`, `cpick`, `work-st`), each a DS
  component that pages resize in place.
- Widening to padding, overflow or backdrop-filter was tried on 2026-08-24 and
  rejected at 74 hits, nearly all refinements. Still true; do not retry without
  a new idea for telling the two apart.
- Classes DS JavaScript queries document-wide (`.wt`, `.seg`, `.cpick`,
  `.slider`, `.splitter`, `.pdock`, `.rl-frame`, `.sel-ring`, `.scrub`,
  `.zslider`, `.askpal`) are the sharper hazard: borrowing one hands your
  element to a script. Not gated, because pages use every one of them as
  itself too; this list is the checklist when a control "does nothing".
