# Should the Measure tool stay in your hand after a measurement lands?

## What this is about

Photonz Next has a Measure tool (press **I**) with four modes: Distance, Size,
Gap and Alignment. Size and Gap take one click each; Distance takes three
clicks; Alignment is one drag. Today, the moment a measurement lands, the
tool goes away and the arrow (Select) comes back, with the new measurement
selected so you can drag or restyle it.

On the end-to-end walk of the redline flow
(`queue/audits/2026-09-02-redline-walk.json`) taking four measurements cost
seven presses of I, because every landing meant picking the tool up again.
That was the biggest repeated stop on the walk, and it is the kind of thing a
person redlining a whole screen does thirty times.

Pictures from the walk: `queue/audits/2026-09-02-redline-walk-5-size-preview.png`
(Size mode outlining a button before the click) and
`…-6-gap.png` (right after the gap landed: note the arrow tool is active again
in the tool bar).

## What you would experience under each option

**Stay in hand.** You press I once, then click element after element. Each
click leaves a caliper and the crosshair stays. When you are done you press
V or Esc, or click the arrow in the tool bar. Pressing I while the tool is in
hand cycles the mode, as it does today. A stray click at the end can leave an
unwanted caliper; Command Z removes it.

**Hand back to Select (today).** Nothing changes. Every landing selects the
new measurement and returns the arrow. The mode you were in is remembered,
so the next pickup is a single press of I.

**Stay for Size and Gap only.** The one-click modes keep the tool so you can
click across a screen; Distance and Alignment, which are multi-step, hand
back as today. Two rules for one tool, but each rule matches how many clicks
the mode takes.

## Recommendation

Stay in hand. It matches every other measuring tool people know, halves the
keystrokes of a real redline, and the cost (one press of V at the end) is
paid once per sheet rather than once per number.
