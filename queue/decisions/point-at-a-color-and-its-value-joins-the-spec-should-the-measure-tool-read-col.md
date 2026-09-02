# Should the Measure tool read colors off the picture?

## What this is about

Photonz Next has a Measure tool for redlining a screenshot. Press I, and you can
read an element's size in one click, a gap between two elements in one click,
drop a two point caliper, or drag an alignment guide. Every measurement lands as
a row in the Measurements list and as a line in the spec list you copy with
Control-Command-C.

What the tool cannot do is tell you a color. If a hand-off needs the button's
blue or the border's gray, you leave Photonz, open Digital Color Meter or a
design tool, and type the value in by hand.

## Where it lives

- The Measure tool in the editor's floating tool bar (Next release, flags
  `next-measure-modes` and `next-measure-panel`, both on by default).
- The design study's redline page: http://127.0.0.1:8791/index.html#redline

## What you would see under each option

### Add a Color mode to Measure

The Measure tool's flyout gains a fourth mode, Color, after Distance, Size and
Gap. Hover the picture and a small swatch pill follows the pointer, reading the
pixel under it as a hex value such as `#3478F6`. Click, and the swatch lands on
the picture as a pill you can move, appears in the Measurements list as a row
named by its value, and adds a line to the spec list:

```
- #3478F6: Save Changes fill (color)
```

Option-click samples the average of a small area instead of one pixel, so the
edge of anti-aliased text does not hand you a half-blended gray.

The value is the rendered color. A shadow, a blend or a display profile can make
it differ slightly from the token in the design file. The pill would say the
value is read from the picture.

### Not now

Nothing changes. Measure stays about sizes, gaps and alignment. The manager
pass can raise this card again after you have redlined a few real captures and
know whether colors are the thing you keep leaving the app for.

## Why this is a card and not a task

You asked that speculative features be confirmed before they are built. Figma
and Sketch show colors in inspect mode; the screenshot tools Photonz competes
with do not. Whether a color readout belongs in a screenshot redliner is your
call.
