# Reusing a component in more than one document

## What happens today

You draw a button, press Make Component, and it lands on the Library shelf. It
is yours for the rest of that document: drop as many copies as you like, edit
the original, watch them all follow.

Open a new document tomorrow and it is gone. The shelf is empty apart from the
five starter components the app ships with. The only way to get yesterday's
button into today's file is to open both windows and copy and paste it, which
gives you a second original that has no connection to the first. Fix a padding
mistake in one and the other still has it.

## Why it is worth deciding now

The objective this work sits under is "Component design: create once, reuse
everywhere". The spec (`docs/design/ui-building.md`) is honest that the first
version stopped short: "Components live in the document they were made in.
There is no shared library across documents, no publishing, no versioning and
no update notifications." That was the right call while components were being
built. Everything else in that list has since landed: copies, overrides,
versions, knobs, styles, auto layout. This is the last piece of the promise
still missing, and it is the one that turns Photonz from a tool you build a
screen in into a tool you build a design system in.

## The three answers

**One shelf the whole app shares.** The Library grows a shared section. Put a
component on it and it is on the shelf in every document you open on this Mac.
Copies stay linked to it, so editing the original repaints every open document
and any document you open later comes up already following it. This is exactly
how the starter components work today, so it is one idea rather than two: the
starter set becomes the shelf the app fills, and this is the shelf you fill.

The cost is that something now lives outside your documents. A file you hand to
somebody else arrives without the originals behind its copies. Photonz already
has an answer for that shape of problem: when a link breaks, the copy keeps its
drawing and says so, which is what a broken style link does today.

**Pull from another document.** No shared store. When you want the button you
built last week, you point at last week's file and pull it in. Nothing lives
outside your documents, so a folder of files is still the whole truth, and
there is no new place to manage. The cost is that reuse becomes a chore you
repeat in every new file, and the link breaks whenever somebody moves the file
you pulled from.

**Leave it in one document.** Components stay where they were made. The starter
set stays the one shared thing. Copy and paste between windows is the way to
move one. Choosing this retires the task, and "create once, reuse everywhere"
means "reuse everywhere in this file".

## The recommendation

One shelf the whole app shares. It is the only one of the three that makes the
second document as fast as the first, and the machinery already exists: the
starter components are components that live outside any document, carry a
stable id, and are copied in on drop. Building on that is a smaller change than
it sounds, and it keeps one mechanism instead of two.

## What would ship first

Not publishing, not versions, not update notifications. One slice: put a
component on the shared shelf, drop it into another document, edit the original,
watch the other document follow, and open a document whose original is gone and
see it say so rather than lose the drawing. Everything else waits until that has
been played with.
