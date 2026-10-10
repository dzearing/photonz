# How the Layers panel talks about stacks

## What this is

A **stack** is a group that lines up what is inside it, left to right (a row) or top to bottom (a column), with an even gap. You make one by picking a few layers and choosing **Stack Selection** (Layer menu, Control Command G).

As of 2026-10-10 the Layers panel knows about stacks:

- **Stack Selection** is the first row of the Layers panel's three dots menu, and it is in a layer row's right-click menu, directly under Group.
- Every row of a stack carries a small grey word: the group says **row**, **column** or **grid**, and each piece inside says **hug** (as big as its own contents), **fill** (takes the room left over) or **fixed** (keeps the size it was given). Plain groups and loose layers say nothing, as before.

The mock for this is the auto-layout page: http://127.0.0.1:8791/index.html#ui-autolayout (the Layers panel on the right, and its three dots menu).

## Where the app and the mock differ

1. **The words on the menu row.** The mock says "Wrap in auto-layout" on Shift A. The app says "Stack Selection" on Control Command G, which is what the Layer menu has always called it. Shift A on its own would be a key typed onto the canvas, so the key stays either way; only the words are the question.
2. **Where the small word sits.** The mock prints it at the right end of the row, in front of the eye. The app prints it on the quiet line under the name, where the list already writes "Original", "3 pieces" and the mask notes. That line exists because a chip beside the name once left the name about 30 points wide and the row read as a single ellipsis.

## The options

- **A. Keep it as built.** Stack Selection everywhere, word under the name. Nothing more is built; the mock stays as drawn.
- **B. The mock's way, all of it.** Wrap in Auto Layout in every menu, and the word moves to the row's right end.
- **C. Only the word moves.** Menus keep Stack Selection; the word moves to the row's right end.

The audit with pictures of both light and dark is `queue/audits/2026-10-10-layers-rows-say-row-or-column.json`.
