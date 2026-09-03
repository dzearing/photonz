# Lining layers up with each other

## What this is about

Photonz is now pointed at building UI: drawing boxes, labels and rows and
arranging them into a screen or a component. That job is different from
redlining a screenshot. When you draw three buttons, you want them to share a
left edge and sit an equal distance apart, and you want that without nudging
each one by hand and squinting.

## What the app does today

Dragging a layer pulls it toward the edges and the middle of the whole picture,
and nothing else. Two layers never notice each other. There is no menu item
anywhere in the app for aligning a selection or spacing it evenly. So the only
way to line up three buttons today is to drag each one and trust your eye, or
to zoom in and count pixels.

Separately, a task already in the queue puts the position and size of the
selected layer in the inspector as numbers you can type. That alone makes exact
placement possible: you can give three buttons the same X by typing it three
times. This decision is about whether arranging deserves more help than that.

## Why you are being asked

A version of the "guides while you drag" idea was built in full on 2026-07-02
and you turned it down: "I think this feature sucks. I don't know when I'd use a
guide." That was in a redlining app. The reason to ask again is that the app's
purpose has changed, not that the old answer was ignored. If the answer is still
no, choosing "Skip this for now" retires this work for good rather than sending
it back around.

## What each choice looks like

**Align and space commands.** You select two or more layers. A row of buttons in
the inspector, mirrored in the Layer menu with keys, lines them up: left,
centre, right, top, middle, bottom, and space evenly across or down. Nothing
changes about dragging. This is the recommendation: it is the half of the idea
that was never tried, it works on ten layers at once, and it never interrupts a
drag.

**Guides while you drag.** Dragging a layer makes it stick to the edges and
centres of nearby layers, with a thin line showing the match. Holding Command
drags free. This is the half you saw before.

**Both.** Commands first, guides after.

**Skip this for now.** Arranging stays as it is. The typed position and size
fields carry the exact work.

## Related

- The mock that shows arranging in the UI workspace:
  `docs/design/mocks/pages/ui-build-screen.html`
- The queued task that adds typed position and size fields:
  `the-position-and-size-of-a-layer-can-be-typed-no`
