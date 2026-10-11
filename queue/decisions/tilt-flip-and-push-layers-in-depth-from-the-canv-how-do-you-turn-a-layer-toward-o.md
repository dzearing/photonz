# How do you turn a layer toward or away from you on the canvas?

## What this is about

Photonz is getting **2.5D**: any flat layer (a title, a picture, a shape, a group, a video clip) can tip back,
swing sideways and move nearer or further away, seen through a camera with real perspective. It is the kind of
3D Keynote and Apple Motion have: flat cards in space, not modelled objects. It is what the 3D transitions
(card flip, cube) and the new title entrances will be built from.

Today a picked layer shows a frame with eight resize squares, a **turn knob** floating above its top edge, and
a crosshair for the point it turns around. This card decides how a person grabs the new turns on the canvas.

**See and try it:** [Depth (2.5D) mock](http://127.0.0.1:8791/index.html#video-depth), section
*Three ways to turn a layer in 3D*. Every canvas there is live: pick the big or the small layer and drag.

## What stays the same whichever you pick

- The panel gets a short **3D** section: Rotation X, Rotation Y, Depth, and Pivot depth once the layer is
  turned. Each row has the key diamond every animatable row has.
- The crosshair gets a small **depth arrow**: drag it to push the layer away or pull it nearer.
- The tool bar gains nothing. Turning is a handle on the picked layer, not a tool.
- Layer menu and right-click: Reset 3D Rotation, Bring Nearer, Send Further.
- Shift steps turns in 15° increments. A readout shows the angle only while you drag.

## The three options

### A. Arcs on the turn knob (recommended)

Rest the pointer on the turn knob and two arcs appear on it. Drag the **flat arc** sideways to swing the
layer (Rotation Y) or the **tall arc** up and down to tip it (Rotation X). Drag the knob itself and it turns
flat, exactly as today. No mode, nothing new to find, and the arcs are the same size on a small badge as on a
full-screen title. The cost is small targets that only show on hover.

### B. Click the knob, then tip the edges

Click the knob and the frame switches to a 3D frame: the side handles become tabs. Pull the top tab toward
you and the top comes toward you; push a side tab in and that side swings away. It feels like holding a card
by its edge, but it is a mode (the resize handles are gone while you are in it), and on a small layer the
four tabs crowd together.

### C. Coloured rings round the pivot

Final Cut Pro's and Motion's control: a red ring to tip, a green ring to swing, a blue ring to turn flat,
centred on the pivot. Most precise and familiar to those users, but it is a second turn control next to the
knob, and on a small layer the rings cover the whole thing.

## If nobody answers

The controls task builds the recommended option (A) and says so in its log. The model and renderer work does
not wait on this card.
