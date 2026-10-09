# Which tool should the H key pick: the Hand or Highlight?

## What the Hand is

The Hand is a tool for moving around a picture that is bigger than the window.
Pick it, press on the canvas and drag, and the view slides with your pointer.
Nothing in the document moves and nothing gets picked: it only changes where you
are looking. Photoshop has always kept it at the foot of its tool bar.

In Photonz Next it is now the last button on the tool bar, after Measure. In the
Design mode it sits exactly where the UI design mock draws it
([UI entry walkthrough, step 4](http://127.0.0.1:8791/index.html#ui-entry-wt)):

> Select | Frame, Component insert, Shape, Pen, Text | Measure | **Hand**

Before this, the only way to pan was two finger scrolling on a trackpad, so a
mouse user had no way at all.

## Why there is a question

Your mocks print the tool as **Hand (H)** in 79 tool bars across the pages, and
Photoshop's Hand is H too. But H has been **Highlight** in Photonz since the
first picture tool bar, and one key can only pick one tool.

Your standing rule for clashes is that Photoshop keeps the key and the Photonz
tool moves (that is how Measure ended up on I). Highlight has no Photoshop
equivalent, so under that rule it is the one to move. It is still a key people
who mark up screenshots already use, so the call is yours.

Until you answer, the Hand ships with **no key**: click it on the bar, find it
under More when the window is narrow, or pick it from Edit > Tools.

## What each answer feels like

- **H picks the Hand, Highlight moves to U.** Press H and the Hand is in your
  hand, exactly as in Photoshop. Highlight answers to U, which is Photoshop's
  letter for its shape tools (a highlight is a see-through box). Only Photonz
  Next changes; the release app keeps H for Highlight.
- **H stays Highlight, the Hand has no key.** Today's behaviour, kept. Nothing
  you already know changes, and the Hand is the one tool on the bar with no key.
- **H picks the Hand only in Design.** Design gets the Photoshop key and picture
  work keeps its key. The cost is one key doing two things depending on the
  mode, and Highlight losing its key while you are in Design.
- **No Hand tool.** The button comes off the bar and the Design bar no longer
  matches the mock. Two finger scrolling stays the only way to pan.

## Recommendation

H picks the Hand, and Highlight moves to U. It matches the mocks, Photoshop and
your own rule for clashes, and Highlight's new key shows in its tooltip and its
menu row the moment it moves.
