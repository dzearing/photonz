# How long may a line of text in the right hand panel be?

## What this is about

The right hand panel is where you tune whatever you picked: its size, colour,
effects, layout. Each section is a list of short labels with a value or a
control beside them. Some sections also print a line of grey text under their
controls, and over time some of those lines grew into paragraphs.

On 2026-09-14 the design rules settled this: **a section says at most one short
line, and only when it says something you cannot see on screen.** The reason
behind a control goes into its hover tip, one pointer away.

## What changed already

A test now reads every panel section and fails when a line is longer than 60
characters. The 32 lines already over it are listed and will be cut; the test
stops that list from growing. The video sections have none left.

## The question

Which length do the cuts aim for?

- **60 characters.** A line like *"Shows this layer where Title is light."* fits
  with room for a name. At the panel's default width a 60 character line can
  wrap onto a second line. 32 lines need cutting.
- **40 characters.** Every line fits on one line at the default width, which is
  what "one sentence, one line" in the design rules literally says. 62 lines
  need cutting, including a few already cut for video.

## Examples of lines over budget today

- Placement: *"Placed by hand, in front of the rest, with the others arranged as though it
  were not there. Horizontal and Vertical say which edges it holds when the
  group is resized."* (167 characters)
- Columns: *"This screen keeps no room at its edges, so the columns use this margin. Give
  it padding in Layout and they follow the padding instead."* (134)
- Components: *"Comes with the app. Adding it puts it in this picture, along with the colors
  it is painted from."* (96)

The rules themselves: `docs/design/mocks/shared/UX-PATTERNS.md`, section 4,
"How much a section may say".
