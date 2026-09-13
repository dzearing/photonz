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
  TutorialMenu.swift     what the Help menu holds and what the window shows,
                         both read off the catalogue, and every word they say
  TutorialGuides.swift   the guides themselves, and the sample they open
  TutorialCallout.swift  where the card goes: pure geometry, its own tests

Sources/Photonz/Tutorials/ (the app)
  TutorialAnchorRegistry.swift   what a name points at, right now
  TutorialController.swift       runs one guide: panels, following, progress
  TutorialCalloutView.swift      the ring and the card
  TutorialLauncher.swift         how a guide gets started from anywhere
  TutorialHubView.swift          the Tutorials window's list
  TutorialHubWindowController.swift  the window it lives in
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

**Where the names live today.** The rows of the card an empty window shows
(`start.open`, `start.capture`, `start.paste` — the only places in a window
where getting a picture IN is a control rather than a key), the canvas, the
floating tool bar, every tool
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
| `.editMade` | `EditorState.perform` — every command in the app funnels here, and only a change that really changed the document counts |
| `.undone` | `EditorState.undo`, and only when something came back |
| `.pictureCopied` | `EditorState.copyCompositeToClipboard`, before the notice, which only exists with the measurements panel on |

`.editMade` is deliberately one event for "the person did something to the
picture" rather than one per command. It is raised at the single funnel every
mutation already goes through, so a step can say "drag one out" or "take it off"
without the framework growing an event per verb, and a guide that asks for a
drag cannot be satisfied by picking a tool.

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

**An anchor that is a SURFACE rather than a control** gets the card INSIDE it,
near the top and with no beak. The canvas fills the window bar the panel, so no
side of it has room, and the old answer (shove the card clear of the anchor,
whatever that costs at the window's edge) hung it half out of the window with
one of its buttons unreadable. A step about the whole picture is not pointing at
an edge of the picture, so there is nothing for a beak to point at either. The
rule is "the anchor can hold the card with a gap all round it", which is true of
the canvas and false of every control and every panel section.

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
5. Run the guide. One walk per guide, and the pattern is
   `Scripts/playtest/tutorial-mark-it-up-walk.json`: `startGuide` takes the
   guide's id, starts it the way the Help menu does and moves the walk into
   whatever window it teaches in, `waitFor tutorialStep` fails the walk when a
   step does not advance, and the log carries where every anchor resolved to.

## What a guide brings with it

A guide that names a `sample` opens a window of its own holding that sample and
teaches in there, so it **never touches what you have open**. `EditorWindowID`
has a `.tutorial` case for it; the drawing itself is data
(`TutorialSampleScreen`), and all the app adds is a white canvas under it. The
window is called "Tutorial Sample" so it is obvious it is not your work.

A guide with no sample runs over the window you are already in, and must say so
in its first step before changing anything.

**An empty window is a sample too** (`TutorialSample.emptyWindow`). The card
offering the ways to get a picture in only exists while a window has nothing in
it, so the guide that teaches those ways brings a window with nothing in it.
`openTutorialSample` installs no document for that case, and the walk that
drives it takes the window over without a canvas (`adoptEmpty`), because there
is none.

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

## The first launch

A new person is asked **once** whether they want showing round, and never
again. The question lives in the setup window that already owns first launch
(`WelcomeController`), because a second welcome surface asking a second welcome
question is exactly the thing this is trying not to be.

```
Welcome to Photonz
Everything is ready. Take a quick lap of the window, or jump
straight in. The tour is under Help whenever you want it.

  ✓ Screen Recording   Required
  ✓ Microphone         Optional

⇧⌘4 captures a region · ⇧⌘3 the full screen · ⇧⌘5 records
⇧⌘6 opens the last capture for editing
                              [ Start Working ]  [ Take the Tour ]
```

The rules live in `FirstRunOffer` (PhotonzCore), which is pure, so the whole
sequence is driven in tests rather than guessed at. They exist because the real
first run is not the happy one:

- **The question waits until the app actually works.** A Screen Recording grant
  only takes effect in a fresh process, so on a brand new Mac the setup window's
  last act is "Relaunch Photonz". A tour offered there is a tour the restart
  kills twenty seconds later. So the choice appears only with Screen Recording
  granted and no restart pending, which lands it on the first launch where
  Photonz can do anything. It does NOT wait on the recommended step (the
  screenshot key conflicts), because somebody who never frees those keys would
  then be asked on every launch for ever.
- **Closing the window is an answer**, and the answer is skip. Without that,
  reaching for the red button instead of either offered button means being asked
  again on every launch, which is the nagging this exists to prevent.
- **Skipping is final.** Both buttons write `tutorials.firstRunOffer`, and the
  window never asks again. There is no second "would you like a tour" anywhere
  in the app. Help ▸ Tutorials is the way back.
- **An upgrade is left alone.** The launch condition widened, so without care
  every existing install would be shown first run setup again. A one time stamp
  (`tutorials.firstRunOffer.migrated`) marks anyone who had already finished
  setup as answered, before the condition is ever read.
- **The stamp happens once, not every launch.** This is the quiet bug in the
  obvious version: run every launch, the migration fires on the NEW person the
  moment they restart for the grant, because by then their setup is complete
  too, and it eats the offer they were owed.

**Take the Tour closes the window first, then starts the guide.** The setup
window is a floating panel above every editor window, so a guide started
underneath it would be ringing controls hidden behind it. Same rule the
Tutorials window follows. The tour brings a sample, so it opens a window of its
own with a picture already in it: nobody is ever pointed at an empty canvas.

**The empty editor onboarding card and this offer never collide.** They are
sequential, not simultaneous. `PhotonzApp` uses a `WindowGroup`, so no window is
forced open at launch and there is no editor behind the offer; the card only
exists inside an editor window with nothing in it. The offer asks "shall I show
you around", and the card, later, answers "how do I get a picture in". Take the
Tour opens a window with a sample in it, so the card is not there either.

Walked end to end from a clean slate by
`Scripts/playtest/first-run-walk.json`, which forgets every first run setting,
runs the real launch hook, and drives all three endings: take the tour, start
working, and an install that finished its setup before any of this existed.

## Where the guides are found

Two doors, both read off the catalogue, neither of which knows the name of any
guide.

### Help ▸ Tutorials

```
Help
  Tutorials
    Take the Tour            the promoted guide
    ---
    Basics          ▸        one submenu per track that has something on it
    Redlining       ▸
    ...
    ---
    All Tutorials...         the window
```

The promoted guide is a **shortcut, not an exception**: the same guide is still
listed under its own track, because a track list that leaves a guide out is a
lie. A track with nothing on it is left out entirely (`populatedTracks`), so the
menu reads correctly today with one track holding one guide, and the six empty
ones appear as their tasks land.

**A menu row says the guide's name and nothing else.** Carrying where you got to
("Take the Tour (step 3 of 6)") was built and then taken out: a command menu
fixes its item titles when the menu is built, so after the guide was finished the
row still said step 3 of 6. Measured on 2026-09-12 with
`Scripts/playtest/tutorial-hub-walk.json`, which leaves the tour part way and
reads the menu bar back. A row that is sometimes wrong is worse than a row that
only says its name, so **every word a menu row says is true whatever you have
done before**, and progress lives in the window.

The one thing a row does read off live state is whether it is **dimmed**: a guide
with no sample teaches over the picture you have open, so it is dimmed with
nothing open. That is honest because focus changes rebuild the menu, and opening
or closing a window is a focus change.

### The Tutorials window

An ordinary titled window owned by the menu-bar agent
(`TutorialHubWindowController`), the same shape as the Experiments window: a
header outside a grouped `Form`, one `Section` per track. Not a fourth kind of
window.

Per track: the name, its one line blurb, and how far through it you are ("1 of 3
finished", "None finished yet", "All finished"). Per guide: the title, what it is
for, how long it takes, a tick when you have finished it, a line saying where you
stopped when you left one part way, and one button reading **Start**, **Continue**
or **Again**.

**Starting a guide closes the window.** A guide points at a control in the editor,
and a window sitting in front of that control is the one thing a walkthrough
cannot survive.

**Forgetting.** A guide with something to forget carries a small More menu:
*Start from the Beginning* and *Forget My Progress*. A guide nobody has run
carries nothing, so a fresh list is a list of guides and not a list of menus.
*Reset All Progress* appears along the bottom only when there is anything at all
to reset, and asks first.

Every word on this window is generated in `TutorialMenu.swift` (PhotonzCore),
where a test runs the repo's copy rules over the lot.

### Reachable without a mouse

The window is a plain SwiftUI surface, so there are no playtest markers in it and
its controls are not `NSButton`s. It is checked through the **accessibility
tree** instead, which is the same tree VoiceOver reads and needs no grant when
you ask your own process (`TutorialHubProbe`). The walk fails if a button says
nothing or if a guide in the catalogue is never said out loud. It reads:

```
StaticText: Tutorials, Short walks through the real app...
Heading:    Basics. Find your way around... None finished yet.
StaticText: Take the Tour. A quick lap of the window... Takes 2 min.
Button:     Start Take the Tour
```

The same probe presses the row's own button, which is how the walk proves that
starting a guide from the window really closes the window and really starts the
guide.

## The Basics track

The four guides a brand new person needs, in the order they need them. Somebody
who does only this track can do the app's whole job end to end.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Your first capture | an empty window | ⇧⌘4, ⌘O and ⌘V, pointed at the three rows of the card |
| Mark it up and hand it over | the starter screen | the arrow, the text tool, and ⇧⌘C as the handoff |
| Everything is a layer, and undo always works | the starter screen | the stack, that a look is added rather than painted on, and ⌘⌫ then ⌘Z |
| Save it, export it, copy it | the starter screen | ⇧⌘C, ⇧⌘E and ⌘S, and which one keeps the layers |

Three things the track had to settle, and every later track inherits them:

- **A guide names keys, never menu rows.** ⇧⌘C is Copy Image with
  `next-copy-picks-your-layer` off and Copy Merged with it on, and both put the
  whole picture on the clipboard when nothing is selected: the key is true under
  both, the menu row is true under one. `next-shape-parts` moves the shadow out
  of Effects and into Appearance, so a step may point at a section whose
  contents move under a flag but must not ask for a named control inside it. A
  test over the Basics track enforces the rule.
- **Capture cannot be walked, so it is taught.** Capture is a menu-bar agent
  flow: a global key, a fullscreen selection overlay, and a new window for the
  result. A guide cannot ring any of that, and a step that waited for a real
  capture would be left behind in the old window the moment the capture landed.
  So the capture guide points at the three ways in that DO live in a window and
  names the keys.
- **⌘Return commits a text draft, Escape throws it away.** The first draft of
  "Mark it up" said Escape, and the walk caught it: the words were typed and
  then lost, and the guide never moved on because nothing was ever edited.

## Where the rest of it is

Landed here: the framework, the anchors, the callout, Take the Tour, the Help
menu, the track submenus, the hub window, the first launch offer and the Basics
track. Still queued:

- **The other six tracks**, one task each.
- **A renamed control breaks the build, not somebody's tutorial** — a generated
  walk per guide that drives the real editor and asserts every step's anchor
  resolves. The unit check here (`TutorialCatalogCheck`) is the promise; that
  one is the proof.
