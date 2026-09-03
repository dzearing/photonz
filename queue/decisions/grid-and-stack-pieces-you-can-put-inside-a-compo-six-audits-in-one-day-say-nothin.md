# Does auto layout move up now?

## What this is about

On 2026-09-03 the UI building work shipped most of a component system: groups,
frames, the Library, making a component, copies that follow their original,
knobs a copy can change, named colors, align and space. Every one of those got
an audit written the same day.

Six of those audits, written by different runs about different features,
independently named the same limit:

- **Starter components.** "A longer label overflows the button it sits in,
  because nothing resizes to its contents yet."
- **Overrides.** "A long wording override still overflows the box it sits in.
  There is no auto layout, so this is a known limit rather than a bug."
- **The whole component walk.** "When you widen the original, the label stays
  where it was rather than staying centred. Is that acceptable for now, or is it
  the thing that makes this unusable without auto layout?"
- **Resizing a group.** "Text does not re-wrap. Its box scales but the glyphs
  keep their point size, so shrinking a group a long way can leave a label
  hanging over its box."
- **Frames.** "A frame does not lay out or resize what is inside it: resizing
  the box only moves where it clips."
- **Lining layers up.** Aligning is per layer against other layers; nothing
  keeps a row spaced as things are added and removed.

And when you answered the alignment question on 2026-09-03 you said it yourself:
"We should probably also have grid components that can be placed within a
component, grid and stack."

## Why you are being asked

Auto layout lives in the plan as its own sub epic of UI building, and it is
staged **later**. That staging is the only reason your grid and stack ask is
sitting in the queue with nowhere to go, and the loop is not allowed to restage
an epic on its own.

The queue also holds four smaller component fixes right now: dragging a
multi-selection on the canvas, setting several layers to one off-the-cuff color,
a component name you can click the way you can click a screen name, and text on
a screen without the screenshot halo. Each of those is under a day. So the real
question is ordering, not whether.

## What each choice looks like

**Move auto layout up.** A stack and a grid become things you can put inside a
component. A button sizes to its label. A row re-flows when you add to it. The
gap and the number of columns are typed numbers. Turning a hand-arranged group
into a stack leaves everything where it already is. The four small fixes stay in
the queue and get done in the gaps.

**Finish the small fixes first.** A few days on the four queued fixes, then auto
layout. Nothing is lost either way; the audits will keep repeating the same
sentence until it lands.

**Leave it later.** Components stay hand-arranged: typed width and height, and
the align and space buttons that shipped today. Choosing this retires the grid
and stack task rather than parking it, and it can be asked again whenever you
want.

## Related

- The task waiting on this: `grid-and-stack-pieces-you-can-put-inside-a-compo`
- The answer that started it:
  `queue/decisions/layers-line-up-with-each-other-while-you-build-when-you-are-arranging-layers-to.json`
- The audits quoted above are all in `queue/audits/`, dated 2026-09-03.
