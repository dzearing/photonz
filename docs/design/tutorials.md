# Tutorials

A tutorial in Photonz is a **guide**: a short walk through the real app, where
each step puts a ring round a real control and floats a card beside it with one
thing to read and one way on. You keep driving the app the whole time. Nothing
is dimmed, nothing is blocked, and you can close it at any step.

A guide is **data**. Adding one means adding a value to a catalogue; the menu,
the hub window and the progress list pick it up with nothing else edited. That
is the point of the framework and the thing that makes it extensible.

Landed 2026-09-12 with one guide, Take the Tour, as proof.

---

## The shape of it

```
PhotonzCore (pure, Codable, tested)
  Tutorials.swift        anchors, steps, tracks, guides, the catalogue,
                         the run state machine, progress, the copy rules
  TutorialGuides.swift   the guides themselves, and the sample they open
  TutorialCallout.swift  where the card goes: pure geometry, its own tests

Sources/Photonz/Tutorials/ (the app)
  TutorialAnchorRegistry.swift   what a name points at, right now
  TutorialController.swift       runs one guide: panels, following, progress
  TutorialCalloutView.swift      the ring and the card
  TutorialLauncher.swift         how a guide gets started from anywhere
```

Nothing outside `Tutorials/` knows the name of any guide.

## The data model

**`TutorialGuide`** — an id (progress is filed under it, so it is stable for
ever), a track, a title, a one line summary, how many minutes it takes, the
sample document it opens for itself, and ordered steps.

**`TutorialStep`** — the anchor it points at, a title, one or two short
sentences, which side the card sits on, how it advances, and what has to be on
screen first.

**`TutorialTrack`** — Basics, Redlining, Looks, Colours and Styles, Building UI,
Components, Video. Tracks are what keep the tutorials from becoming one long
list: Help shows the tracks, a track shows its guides.

**`TutorialCatalog`** — every guide the app ships. `populatedTracks` is what a
menu builds from, so an empty track never shows an empty submenu.

**`TutorialRun`** — where a person is, as a value. Advance, back, and "is this
event the thing this step was waiting for". The controller holds one; the tests
drive one.

**`TutorialProgress`** — what is finished and where you stopped in anything you
left part way, written on every step and kept in `UserDefaults` under
`tutorials.progress`. Quitting mid guide loses nothing: the menu row says
"Resume the Tour" and picks up where you were.

## The anchor contract

A step names a place in the app, and the overlay turns that name into a
rectangle on screen again and again as the window moves, the panel scrolls, and
the layout changes under it.

**Names come off the model, never off the words.** `TutorialAnchor.tool(.measure)`
is built from `Tool.measure.rawValue`; `TutorialAnchor.panelSection(id.rawValue)`
from the section's id. Rewording the Measure button, or its tooltip, cannot
reach the name a guide points at. Deleting the tool breaks the build at the call
site that builds the name, which is exactly where it should break.

This is the playtest harness's steady-name idea (`PanelTarget.swift`), rebuilt
rather than reused: that registry is compiled out of the shipping build
(`PHOTONZ_PLAYTEST` is defined for the dev and probe variants only) and
tutorials ship to people. **The tutorial registry is compiled in, always.**

**Hanging a name on a control** is one modifier:

```swift
Button { … } label: { … }
    .tutorialAnchor(.tool(tool))
```

It is inert: an invisible `NSView` behind the control that never draws, never
takes a click (`hitTest` returns nil) and never changes layout. That is why it
is safe to hang one on shared code that both releases use.

**Where the names live today.** The canvas, the floating tool bar, every tool
button (through the one `toolButton` funnel, plus the two mode buttons and the
family buttons, which do not go through it), the docked panel, and every panel
section.

**Reading a name back** is `TutorialAnchorRegistry.screenFrame(of:in:)`. It is
scoped to one window, because three editor windows all have a tool bar and a
guide is running in exactly one. It clips the control's rectangle to the window,
so a panel section scrolled off the top stops resolving rather than being
pointed at confidently from above the title bar.

> It does **not** use `NSView.visibleRect`. For a SwiftUI hosted view that
> answers for the hosting view around it, not for the marker: reading it put a
> ring round the whole panel instead of round one section. Measured wrong, so
> not used.

## How a step advances

Two ways, and both are honest.

- **`.next`** — a Next button. For a step that is showing you something.
- **`.waitsFor(trigger)`** — the step waits for the person to really do the
  thing and moves on by itself when they do.

A waiting step **never offers Next**, because Next would be a way to claim you
did something you did not. It offers **Skip This Step**, so nobody is ever stuck
on a step they cannot perform.

Nothing advances on a timer. A step that says "pick the Measure tool" and moves
on five seconds later whether or not you did is a lie, and the person notices.
Triggers are wired at the one place the thing actually happens:

| Trigger | Wired at |
| --- | --- |
| `.toolPicked(tool)` | `EditorState.setTool` — button, key or menu, all land here |
| `.layerSelected` | `EditorState.selectedLayerID` — list or canvas, both land here |
| `.panelShown` | `EditorState.setInspectorVisible` |

When a guide needs to wait for something with no event yet, **add the event
here and wire it where it happens**. Do not fake it.

## Preparing a step

`TutorialPrep` is a closed list, and the closure is the guard rail: a prepare
action may only **reveal**. It may never do the thing the step is asking the
person to do. Showing the panel so a step can point at the Layers list is fine;
picking the Measure tool for a step that says "pick the Measure tool" is the
timer lie in another costume.

- `.showPanel` — bring the docked panel on screen if it is hidden.
- `.showLibrary` — bring the Library shelf on screen if it is hidden.
- `.revealTarget` — scroll this step's own target into view. AppKit does the
  work (`scrollToVisible` on the marker, which walks up to the nearest clip
  view), and the ask is repeated for about a second so it survives a section
  that arrives with the selection a beat late. It stops the moment the target
  is on screen, so a person who scrolls somewhere else is not fought.

## Where the callout goes

Two surfaces, kept apart because they want opposite things from the mouse.

- The **cue**: an accent ring with a pulse, on the control. Its panel ignores
  the mouse completely, so the control under it is pressed exactly as it would
  be with no guide running. This is the mock's `.wt-cue`
  (`docs/design/mocks/shared/components/walkthrough.css`).
- The **card**: the step number, the title, the copy, "n of m", Back, the one
  button, and a close. Its panel takes clicks for its own buttons and never
  takes key focus away from the window you are working in.

Both are borderless child panels of the editor window, so they move with it.
The idiom is the app's own tooltip (`HintTooltip.swift`) and the card wears the
same beak shape, so the two read as one family. Not the zoom callout's leader
lines, which are drawn INTO the picture and belong to the document; not a
popover, which is attached to one control and closes the moment you touch
anything else. A guide has to survive you using the app.

**Placement is pure geometry** (`TutorialCalloutLayout`), so the rule that
matters is tested rather than eyeballed: **UX-PATTERNS D14, a callout never
covers what it is talking about.** It tries the side the step asked for first,
then the rest roomiest-first, and takes the first side where the card fits
inside the window and lands clear of the control. If no side works, the roomiest
side wins and the card is pushed fully off the control even if that costs the
window's edge inset: a callout half off the edge is readable, a callout on top
of the button it names is not.

**Following** is a 30Hz read of the marker's frame rather than a subscription.
There is no one notification for "the panel scrolled, the window resized, a
section collapsed, the tool bar shed a button"; reading the frame a few dozen
times a second covers all of them and costs one coordinate conversion.

**When the target is not on screen at all**, nobody is stranded: the card goes
to the middle of the window with no beak and no ring, the copy is unchanged, and
the way on still works. That is the last line of defence, not the plan. The plan
is the checks below.

## Adding a guide

1. Write the value in `TutorialGuides.swift` and list it in
   `TutorialCatalog.guides`. That is the whole of it for the menu and the hub.
2. Point every step at an anchor that already exists. If the control you want
   has no name yet, add `.tutorialAnchor(…)` where it is built, add the name to
   `TutorialAnchor.all`, and only then write the step.
3. Keep the copy to product copy: short plain sentences, no dashes standing in
   for punctuation, nothing about how the app was built. A test enforces this
   (`TutorialCopyRules`) and it also fails copy too long to read off a card.
4. Give a waiting step a real trigger, or use `.next` and say what to look at.
5. Run the guide. `Scripts/playtest.sh Scripts/playtest/tutorial-tour-walk.json`
   is the pattern: `startTour` opens the guide's own window and moves the walk
   over to it, `waitFor tutorialStep` fails the walk when a step does not
   advance, and the log carries where every anchor resolved to.

## What a guide brings with it

A guide that names a `sample` opens a window of its own holding that sample and
teaches in there, so it **never touches what you have open**. `EditorWindowID`
has a `.tutorial` case for it; the drawing itself is data
(`TutorialSampleScreen`), and all the app adds is a white canvas under it. The
window is called "Tutorial Sample" so it is obvious it is not your work.

A guide with no sample runs over the window you are already in, and must say so
in its first step before changing anything.

## What this framework deliberately does not do

- **No scrim, no modal, no blocking.** You can ignore a guide completely and go
  on working; it follows the controls it is talking about while you do.
- **No dots you can click.** A dot promises you can jump to step five, and step
  five may depend on something step three made. It says "3 of 6" instead.
- **No branching, no conditions, no scripting.** A guide is a straight line. A
  teaching flow that needs branches is two guides.
- **Prepare never acts for you.** See above. This is the rule most likely to be
  bent, and bending it is how a tutorial starts lying.
- **No pointing at something that is not on screen.** A tool hidden inside a
  family button or behind the tool bar's more affordance cannot be pointed at
  until it is showing. A family button answers to the member it is wearing.
- **No back-porting.** Tutorials are Next only, behind `next-tutorials`.

## Where the rest of it is

Landed here: the framework, the anchors, the callout, Take the Tour, and one
row on a Help menu that did not exist before. Still queued:

- **Help has a Tutorials menu organised in tracks, and a window that shows your
  progress** — the track submenus and the hub.
- **First launch offers the tour or gets out of your way.**
- **The seven tracks**, one task each.
- **A renamed control breaks the build, not somebody's tutorial** — a generated
  walk per guide that drives the real editor and asserts every step's anchor
  resolves. The unit check here (`TutorialCatalogCheck`) is the promise; that
  one is the proof.
