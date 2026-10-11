# Where does the camera live?

## What this is about

With 2.5D, every frame is seen through a camera with perspective: a layer turned away gets narrower at its
far edge, a layer pushed back gets smaller. Someone has to be able to set **how strong the perspective is**,
and, for camera moves (a slow push in on a title, a slight orbit), **move the camera over time**.

**See it:** [Depth (2.5D) mock](http://127.0.0.1:8791/index.html#video-depth), section
*The layers list and the camera* (the second and third panels).

Either way there is exactly one camera, and a document nobody has turned in 3D looks exactly as it does today.

## The options

### A. Camera settings on the frame (recommended)

Click empty canvas and the panel shows the frame, as it does now, with a new **Camera** section:
Perspective, Camera depth, Camera X and Camera Y, each with its key diamond. Once the camera is keyed, a thin
**Camera** row appears at the top of the timeline to hold those keys. Nothing new to add or find; the cost is
that moving the camera is numbers and keys rather than a drag on the canvas.

### B. A camera you add, like Apple Motion

**Layer, Add Camera** puts a Camera track at the top of the timeline. Pick it and the canvas shows the frame
the camera sees, which you drag to pan and push to dolly, with its settings in the panel. Direct and familiar
to Motion and After Effects users, but it is a new kind of layer, and the canvas has to draw the camera's
frame on top of the document's.

## If nobody answers

The model task builds A, which is what its checklist already describes. B can be added on top of A later
without changing anything a person learned.
