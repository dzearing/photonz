# What the Shape slot's tip says

## The surface

When you build a screen in the Design mode, the tool bar along the bottom of the
canvas holds the tools for that job: Select, Frame, Component insert, Shape,
Pen, Text, Measure and Hand. The Shape slot is one button that stands for three
shapes (Line, Rectangle, Ellipse). Click it and you draw the one it is showing.
Press and hold it and you get the list of all three.

The UI mock draws this slot as a square, with the tip **Shape (R)**:
http://127.0.0.1:8791/index.html#ui-entry (step 4, the tool bar).

As of 2026-10-09 the slot starts on the Rectangle in Design, as the mock draws
it. That leaves one gap: the words in the tip.

## Option A: the tip names the shape (recommended)

Rest the pointer on the slot and the tip says **Rectangle R**. Pick the Ellipse
and it says **Ellipse O**. Every family slot in the bar already works this
way: the Selection slot says Rectangle Select, the Crop slot says Crop.
Photoshop's tips do the same ("Rectangle Tool (U)"). You learn which shape a
click will draw and which key gets you there.

Picture: `queue/audits/2026-10-09-design-shape-slot-1.png`.

## Option B: the tip says Shape R, as in the mock

The tip reads **Shape R** whatever shape the slot holds. The words match the
mock exactly. The tip no longer says which shape you get, though the icon on
the slot still shows it, and this slot would read unlike the other family
slots.
