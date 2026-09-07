# How often should the panel say that a change reaches everything you picked?

## What this is about

The panel down the right hand side of the editor is where you change what you
have picked: how big the text is, where it sits, whether it has a shadow, how
round its corners are. It is split into sections with headers you can collapse:
Layers, Arrange, Text, Position & Size, Appearance, Effects.

When you pick **more than one thing at once**, most of those sections print a
grey line under their controls that says the same thing in slightly different
words:

> 2 layers. A change here changes every one of them, in one step.

> 2 layers, all at once. X sets every left edge, Y every top edge, W and H each
> layer's own size. Arrow steps them all by 1, Shift by 10.

> 2 layers. A tick or a colour picked here reaches every one of them, in one step.

> 2 layers line up with each other. Spacing evenly needs three.

It appears under Arrange, under Text, under Position & Size, under Effects, and
**twice** inside Appearance. Six times, in one panel, for one idea.

## Why it matters now

Together those lines come to roughly **190 points** of panel height. The whole
panel is 996 points tall on a laptop, so they are about a fifth of it.

On 2026-09-07 the panel was rebuilt so that its list-shaped sections (Layers,
Appearance) give up room and scroll inside themselves, and its form-shaped
sections (Text, Position & Size, Effects) are always drawn whole. That got the
look controls back above the fold in every case that was measured except one:

| What is picked | Where Effects sits | Fits the 996pt panel? |
| --- | --- | --- |
| One piece of text | 838 – 996 | yes, exactly |
| **Two pieces of text** | **838 – 1030** | **34 points over** |
| Four layers at once | 574 – 732 | yes |
| An arrow | 712 – 870 | yes |
| A zoom callout | 835 – 993 | yes |
| Fifteen layers, one picked | 574 – 732 | yes |

Two pieces of text picked is the case people hit most, and it is 34 points
short. The repeated sentence is worth 190. It is the largest thing left to give,
and nothing else in the panel can be shortened without hiding a control.

See the audit `2026-09-07-dock-fits-the-window` for the pictures, and
`queue/audits/2026-09-07-dock-fits-two-text.png` for the case in question: the
sentence under Corner Radius is the one being cut off.

## What you would see under each option

### a. Say it once, at the top (recommended)

The panel already prints "2 layers selected" under the Layers list. That line
grows a few words: **"2 layers. What you change here reaches both."** It sits
above every section and does not scroll away, so it is on screen wherever you
are in the panel.

Every section below then shows its controls and nothing else. Effects gains
real room under Corner Radius rather than ending on the window's edge, and the
Appearance section stops being squeezed to a third of its height.

### b. Say it only where it is surprising

Keep the sentence in the two or three places where "this reaches all of them" is
genuinely not obvious, and drop it everywhere else. Position & Size is the
strongest candidate to keep, because W and H behave differently from X and Y
across a multi-selection and the sentence is the only place that is explained.

You would still see explanations, just fewer of them, and the panel would gain
most of the height back.

### c. Leave the words alone

Nothing changes. With two pieces of text picked, Corner Radius sits on the very
bottom edge of the window, the line under it is cut off, and the panel still
scrolls a little. This is the state that four separate audits filed against on
2026-09-07.

Picking this retires the task.

## Where to look

- The panel itself: pick two pieces of text in the editor and read down it.
- The capture: `queue/audits/2026-09-07-dock-fits-two-text.png`.
- The panel rules this follows:
  `docs/design/mocks/shared/UX-PATTERNS.md` section 3, panel group.
