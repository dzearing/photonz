# Modes you can swap, and the chain that tests them

**The prototype:** <http://127.0.0.1:8791/index.html#modes>
**The shelves it drags off:** <http://127.0.0.1:8791/index.html#shelves>

## What a mode is, in one paragraph

Today a Photonz window shows everything it can do, all the time. A **mode** is a
name for an arrangement of that window: which panel sections are unfolded, and
which handful of tools sit in the tool bar rather than in its overflow menu. You
swap modes from a quiet chip beside the document's name, or with a key, and the
swap takes about as long as changing the zoom.

The important half is what a mode is **not**. It is not a kind of document. Your
file does not know about it, nothing is written when you save, and a document
made last year opens exactly the way it always did. Two windows onto the same
file can be in different modes. And nothing is ever taken away: every tool keeps
its keyboard shortcut and its place in the macOS menus in every mode, so the
worst thing a mode can do is move something out of your line of sight.

## The bit that decides whether it is one app or four

You asked for one app that does four jobs, not four apps sharing a window. The
prototype tests that with the hardest flow it could find, drawn before any of the
tidy pictures:

> Draw a bell at 24 points. Put that bell inside a Notifications button you
> built. Put that button on the timeline over a screen recording, from 0:04 to
> 0:09. Then go back and change the bell's stroke, and watch it change in the
> button and on the timeline.

**No export, no import, no "convert to" anywhere.** It works because the icon,
the component and the recording are all layers in one document, and the timeline
is simply a view of the layers that have a start and an end. The link that makes
an edit travel is the one the app already has: a component.

**The catch, and it is the expensive sentence on the page.** Video in Photonz
today is a separate window with its own state and no layer list, so there is
nothing for a component to be dropped onto. For that chain to be real, a
recording has to become a layer in an ordinary document. That re-aims the video
work already queued, and playing a composite at thirty frames a second is a
harder bar than drawing a still canvas. It is worth paying and it is not small,
which is why option **a** and option **b** are separated: modes are worth
building either way.

## The thing that would make this feel broken, and what stops it

A preset that hides a tool is indistinguishable from a broken app in the second
you reach for that tool. Every editor that has tried workspaces has had to solve
"where did my thing go". The prototype answers it five ways, and four of them
already exist in the app:

1. **The shortcut still works.** Press `I` for Measure in Icon mode and Measure
   is armed, with a quiet line saying where it is now living.
2. **Folded tools are in the tool bar's overflow menu**, which a narrow window
   already uses, so it is a place you have learned for another reason.
3. **Folded panels are listed** by the **Panels** button at the foot of the dock,
   and the panel's own list says *"you turned this off"* instead of leaving a
   blank. The app already tells that apart from *"nothing in this document needs
   it yet"*.
4. **A mode you bend stays bent.** The chip reads "Icon, edited", and Reset this
   mode is right there.
5. **Show everything** unfolds the lot in one click, and swapping back to a mode
   restores exactly the arrangement you left.

The last three are pinned by tests that run in the suite
(`ModeIsAPresetTests`), so "you can always get back" is a fact about the code
rather than a promise on a page.

## Modes are written down, not coded

If the four modes we ship are the only four possible, they are four applications
wearing a costume. So the prototype shows what a mode is **made of**, and adds a
fifth one, **pixel art**, as a worked example: a 32 by 32 canvas at 1600%, a grid
at one pixel, magnification that shows squares rather than smudges, a pencil at
one pixel with hard edges, and five panel sections folded. Three of those five
ingredients are already running in the app.

Pixel art is also the case that tests the one line that must not be crossed. A
mode may set a default for the **next** thing you draw, and may change what you
are **looking at** (the grid, the magnification), because those are view settings
exactly like zoom. A mode may **not** change how work that already exists comes
out. Switch to pixel art with a smooth curve on the canvas and that curve stays
smooth. If it did not, the document would be in a mode after all, and swapping
would stop being free, which is the idea you already rejected wearing a better
name.

## Where you pick things up from

The chain starts with a drag, so the companion page settles which shelf. Split by
**reach**, as you said:

- **History is the global shelf**: everything you have made or captured, across
  every document, from the menu bar with no window open.
- **The Library is this document's shelf**: what this file contains and can place
  again.

Something dropped from History into a document arrives as **a copy that
follows**, which is exactly what shared components already do, so no second
linking rule is invented. One consequence to note: the Library's Media scope
shows the global capture folder today, and under this model those captures belong
to History.

## The recommendation

**Option a: modes now, the video chain later.** It gives you the swap you asked
for, most of it is already built, nothing is written into a document, and it does
not commit the loop to re-aiming the video work before you have seen modes in
your hands. The chain is drawn in full on the page so the bill can be judged on
its own, and nothing in option a has to be undone to get there.
