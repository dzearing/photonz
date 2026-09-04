# Should a component hold several versions of itself?

## What this is about

In Photonz today a component is one drawing with a name. You draw a button, make
it a component, and every copy of it follows that one drawing. You can expose
knobs on it: the wording, whether a part shows, a colour, and a choice between
two shapes that are both already inside it (Make Alternatives).

What you cannot do is say "this is the same button, disabled". A disabled button
has a grey fill, dimmer words and sometimes an extra mark. Right now the only
way to show one is to make a second component called Button Disabled. From that
moment the two are separate things: change the corner radius on one and the
other keeps the old one. That is how a set of buttons stops matching.

Every design tool people come from solves this the same way, with a name for the
component and a second name for which version you are looking at.

## What you would see under each option

### Versions under one name (recommended)

Picking a component gives it an "Add version" button. A new version starts as a
copy of the one you are looking at, and you name it: Normal, Hover, Disabled.
Each version is a real drawing you edit like any other, so a version can differ
in any way at all, including holding an extra icon or arranging its contents
differently.

A copy on the canvas gains a Version menu in its Component section, next to the
knobs it already has. Pick Disabled and that one copy shows the disabled
drawing. Everything else that copy owns, its wording and any colour you gave it,
stays where it was.

The cost is real and worth knowing: rounding the corners on all three versions
is three edits, because there are three drawings.

### One drawing, versions record only the differences

There is still one drawing. A version is a short list of what changes about it:
this fill goes grey, these words change, this part hides. A copy picks a version
by name and those differences are laid on top.

Rounding the corners is one edit and every version follows, which is the whole
appeal. The limit is that a version can only change the things on that list, so
a disabled button cannot gain a lock icon that the normal one does not have. It
would have to become its own component after all.

### Leave it as Make Alternatives

Nothing changes. A component can hold two shapes and a copy picks between them,
which covers an icon swap but not a state. A button with three looks stays three
components, kept in step by hand.

Picking this retires the task rather than sending it back to be built.

## Why it is being asked now

The objective for this epic reads "create, reuse, variants, overrides", so
versions are named in the goal. The written plan for the work, in
`docs/design/ui-building.md`, deliberately left states out of the first version.
The two disagree, and which way it goes changes what gets built next, so it is
yours to settle rather than the loop's.

## What happens after

Whichever way it goes, the first piece of work is the model and the menu on a
copy: make a version, name it, switch a copy to it. The Library tile counting
versions, the marks on the canvas, and any way of editing something across every
version at once are separate tasks filed afterwards.
