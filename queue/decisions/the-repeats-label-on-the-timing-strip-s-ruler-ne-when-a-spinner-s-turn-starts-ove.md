# Where the restart label goes when a turn ends on a ruler number

## What this is

When something loops forever (a spinner, a bell that swings), the timing strip
at the bottom of the window draws a blue dashed line where the loop starts over,
with a small label beside it. The bell and knob pages
([icon-animate-wt](http://127.0.0.1:8791/index.html#icon-animate-wt),
[icon-phase-wt](http://127.0.0.1:8791/index.html#icon-phase-wt)) label it
**repeats** and put it up on the ruler, between the numbers.

The spinner page ([icon-loop-wt](http://127.0.0.1:8791/index.html#icon-loop-wt),
step 5) labels the same line **and again** and puts it under the last lane,
below the bars.

## Why it came up

A lone 800 ms spinner starts over exactly on the ruler's **800**. With the label
up on the ruler, the two printed on top of each other and read "800eats". That
is fixed: the label never sits on a ruler number any more. The question is only
which of the two mock pages the fixed version should look like.

## The options

- **a. "repeats", just under the 800 (built, recommended).** Between ruler
  numbers nothing changes. When the label would land on a number, it drops one
  line, so it reads just under the 800, beside the dashed line. The strip keeps
  its height. Picture: `queue/audits/2026-10-15-repeats-label-on-a-tick.png`.
- **b. "and again", below the last lane.** Exactly the spinner page. The strip
  has no room under its last lane today, so it would grow a short row there.
- **c. "repeats", below the last lane.** The spinner page's placement with the
  word the other loop pages use. Also needs the extra row.
