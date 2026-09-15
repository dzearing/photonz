# What a drag off the Library shelf should hand you

## What you reported

Looking at the Component section with a component selected, you said:

> the component ui for component instances . super confusing. info overload,
> can't adjust specific component properties defined for it, select a variant...

The task filed from that assumed a copy shows the same wall of authoring
controls an original does. It does not, and that is the useful finding.

## What a copy's panel actually shows today

Click a copy of a Button and the Component section is six short things:

- the component's name, as a label with one violet diamond beside it
- one sentence: "A copy. Editing the original changes this one too."
- **Properties**, and the first row in it is the look picker, wearing whatever
  the author named that property (Variant, or State, or Type)
- one row per property the original exposed, with the copy's value in it
- **Edit Original** and **Detach**

There is no name field, no Share across documents switch, no list of looks with
an Add beside it, no minus buttons. All of that is on the original only.

## What actually happened

The Button you clicked was the original.

The first time you drag a component off the shelf, the app has to bring the
component itself into the document, so what lands is the ORIGINAL. Every drag
after that lands a copy. Your screenshot proves it: the sentence on it reads
"This is the original. Copies you place will follow it.", and the app only says
"copies you place" when the count is zero. One drag, no copies.

So the panel was doing its job. The app handed you the wrong thing to click,
and what a drag gives you depends on something invisible: whether you have
dropped that component before.

## What each option would feel like

### A. Always a copy (recommended)

You drag a Button onto the canvas. A copy lands under your pointer, ready to
configure, exactly like the second and third one you drag. The original lands
off to one side, in the same clear spot a second look of a component already
goes, and its layers row wears the four-diamond mark so you can tell it apart.

Clicking what you just dropped always gives you the short panel. The behaviour
stops depending on history.

The cost is one drawing you did not ask for, the first time, sitting beside
your drop.

### B. Say it plainly and offer a copy

Nothing about the canvas changes. The first drop is still the original, but its
panel leads with what it is and a single **Place a Copy** press directly under
the name. You click, you read one line, you press once, and you have the copy.

The cost is that you still have to notice, and a drag still gives you different
things on different days.

### C. Originals leave the canvas

The canvas only ever holds copies. An original lives on the Library shelf and
is edited in a room of its own, where all its looks sit side by side. A drag
can only give you a copy, because there is nothing else on the canvas to give.

This is the cleanest rule and the biggest change: it touches how components are
made and edited, not only how they are dropped.

### D. Leave it as it is

The first drop stays the original. Anyone who wants a copy drags a second one
on, or uses Place a Copy on the Library tile. Picking this retires the task.

## Worth looking at

- The Component section for an original and for a copy:
  `Sources/Photonz/ComponentPanel.swift` — `ComponentInspector` is the
  original's, `ComponentInstanceInspector` is the copy's.
- This morning's rename, which gave both sides one word: 
  `queue/audits/2026-09-15-component-properties-naming.json`.
- There are no fresh pictures of either panel. The Mac's screen has been locked
  all afternoon, so no walk can run and macOS refuses every screen capture.
