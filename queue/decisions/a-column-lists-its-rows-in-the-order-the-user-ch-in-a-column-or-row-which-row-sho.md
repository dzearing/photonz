# Which row does the Layers list show first in a column?

## What this is about

The **Layers list** on the right of the window lists every layer in the
document. Today it always puts whatever sits **on top** first, the way
Photoshop and Figma do.

A **column** is a frame or group that lays its contents out top to bottom (a
row does it left to right). The new **Design UI** start opens a Login screen
laid out as a column: a headline, a line under it, an email field and a
password field.

## What differs

The UI entry mock (http://127.0.0.1:8791/index.html#ui-entry-wt, the Layers
group) lists that column in **reading order**:

    Login
      Headline
      Subhead
      Email field
      Password field

The app lists it **top of the stack first**, which in a column means bottom row
first:

    Login
      Password field
      Email field
      Subhead
      Headline

A Button dragged onto the bottom of the column shows up at the top of the
list under (a) and at the bottom under (b).

## The options

- **(a) Keep top of the stack first, everywhere.** One rule for every group.
  Figma people expect it: Figma lists auto-layout children this way. The list
  reads upside down against the screen.
- **(b) Reading order inside rows and columns.** The list reads like the
  screen and matches the mock. Free groups and the canvas keep top first, so
  one list holds two orders.

The recommendation is (a), because it is what Figma and Photoshop users already
know, but the mock draws (b).
