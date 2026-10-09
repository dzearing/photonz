# Should starter components change colour in dark mode?

## What this is about

The Library in Photonz comes with five ready-made components: a Button, a Text
Field, a Card, a Nav Bar and a Badge. You drag one onto the canvas and get a
copy you can adjust. Since 2026-10-09 the Button comes the way the variants
mock draws it: Primary, Secondary or Ghost, in Small, Medium or Large, with an
icon in front of its words.

The mock is here: [ui-variants](http://127.0.0.1:8791/pages/ui-variants.html).
Its grid of nine buttons is drawn in the design system's colours, and the
design system has two sets of them: one for light mode, one for dark.

## What happens today

A dropped Button is painted in the **light** colours: a blue capsule with white
words for Primary, a white capsule with a thin grey edge for Secondary, grey
words on nothing for Ghost. Those colours belong to the document, the same way
the colour of a rectangle you drew belongs to the document. When the Mac
switches to dark mode, the app's panels and tool bar go dark, but the Button on
the canvas stays exactly as it was.

## The two choices

**Keep the colours you dropped (recommended).** Nothing changes. A Button looks
the same in light and dark mode, the same as everything else you draw, and a
picture you export is the same whoever exports it. If you want a dark version
you recolour the Accent, Surface or Text styles in Styles, once, and every
starter wearing them follows. This is how Figma and Photoshop behave: the app
goes dark, your design does not. Picking this closes the question for good.

**Follow the Mac's appearance.** Each of the starter colours gets a second,
dark value (the mock's: a lighter blue `#7F9BFF`, near-white words `#E7E9EE`,
and so on), and a dropped Button switches between them as the Mac does. It
matches the mock's dark cells, but what you export then depends on how the Mac
was set when you exported it, and Styles would need to show and edit two
colours per style.

## Worked example

You drop a Primary Button on a white screenshot in the evening with dark mode
on. With the first choice it is the same blue you saw that afternoon. With the
second it is a lighter blue with dark words, and the PNG you send a colleague
is that lighter blue too.
