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
  TutorialHost.swift             what a guide runs OVER: the picture editor
                                 or a recording's window, three questions each
  TutorialSampleRecording.swift  the one sample that is a real file
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

**A family slot has a name of its own.** The shapes slot and the selection slot
each wear whichever member was reached for last, so `TutorialAnchor.tool(.rectangle)`
is on the bar only for somebody who has drawn a rectangle before.
`TutorialAnchor.toolGroup(.shapes)` is there whatever the slot is wearing, and it
is what a step meaning "the shapes button" points at.

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

## A renamed control breaks the build, not somebody's tour

The day a control is renamed, moved, or put behind a flag, a guide pointing at
it starts pointing at nothing. Three checks stand between that and a person, and
each catches something the others cannot.

**1. The name is one the app promises.** `TutorialCatalogCheck` walks every
guide and holds each step's anchor against `TutorialAnchor.all`. A typo, or a
name nothing ever hangs, fails `Scripts/test.sh`. Cheap, and it cannot tell
whether the app really hangs the name anywhere.

**2. Every guide is really driven.** `TutorialWalkCoverage` reads the walks in
`Scripts/playtest` and holds the catalogue to them: every guide has a walk, that
walk waits on every one of its steps, and no walk is still driving a guide that
has been renamed or taken out. Also `Scripts/test.sh`, and also only JSON, so it
costs nothing. A guide written without a walk fails here.

**3. Every step finds its control, in a real window.** While a walk drives a
guide, each step records whether its control was ever found on screen. A step
that found nothing fails the walk, naming the guide, the step, the missing name
and the names that were there:

```
frames-are-screens step take-the-rectangle points at tool.rectangle, and nothing
in the window carries that name (the step was up for 1.7s). The names on screen
were: canvas, panel, panel.frame, tool.arrow, tool.crop, tool.frame, tool.line, …
```

This one runs in the sweep rather than in the test run, and it adds NO walks to
it: the thirty odd tutorial walks were already there, and they now assert
instead of only photographing. The full sweep is 322 walks and about 52 minutes,
so a walk per guide on top of the walk per guide we already had would have been
pure cost.

Two things the third check will not do. A step that was never on screen long
enough to find anything is reported, not failed: a probe window covered by
another app draws no callout at all, and a covered window is not a missing
control. And a walk can declare, in its `setup` block, that a step is SUPPOSED
to find nothing (`"expectNoControl": ["trim-a-recording/saving-writes-it-in"]`),
which turns the check around rather than switching it off: skip every step of
the trim guide and nothing is trimmed, so there is no Save button, and the last
card has to stand on its own.

> What it caught the day it was written: the Building UI guide's step about the
> rectangle pointed at `tool.rectangle`, and the shapes slot wears whichever
> shape you used last, which on a machine nobody has drawn on yet is the LINE.
> For the exact person a tutorial is for, that step rang nothing. The fix is the
> `toolGroup` anchor below: a family slot answers to its family's name whatever
> member it is wearing.

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

## The Redlining track

The app's real daily job, in five guides that run in the order the job is done
in. Somebody who does only this track can measure a screen and hand a builder a
spec.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Measure a gap | the settings screen | I to pick Measure up, I again for Gap mode, one click for the space between two things |
| Measure something's size | the settings screen | Size mode, `[` and `]` for what is picked, one click for both calipers |
| Let it snap, or drag it free | the settings screen | the three click caliper, ⌘ to free the magnets, ⇧ to hold the direction, and where the tool's settings live |
| The Measurements panel | the same screen, already measured | the list, picking a row, renaming, the row's eye |
| Export a spec list | the same screen, already measured | ⌃⌘C for the list, ⇧⌘C for the picture and the list together, ⌘C for one line |

Four things this track needed that the framework did not have, each added as
DATA or as one more event rather than as a special case:

- **A sample that is a PICTURE.** Measure finds elements and gaps by reading
  pixels (`ElementBounds`, off the `EdgeMap`), and the Basics track's starter
  screen is live shapes over a plain white canvas: there is nothing in those
  pixels to find, so Size and Gap would draw nothing at all. A sample now says
  whether it is flattened (`TutorialSample.isFlattened`), and a flattened one is
  drawn once (`TutorialSampleScreen.pictureLayers`), rendered, and installed as
  the window's single picture. What stays live on top is whatever the guide is
  about: nothing, or the three measurements the panel guide arrives with.
- **A guide says which features it needs** (`TutorialGuide.requires`, flag names
  from `FeatureCatalog`). A guide teaching a mode somebody switched off in
  Experiments would ring a button that is not there, so it is left out
  altogether: `TutorialCatalog.guides(enabled:)` narrows the list, the app asks
  once (`TutorialLauncher.offered`), and the menu and the window both read that.
  A track whose every guide is switched off loses its shelf as well
  (`populatedTracks(in:)`), which is the same rule an empty track already
  followed. Nothing is dimmed and nothing explains a feature flag to anybody.
- **Two more triggers**, wired where they happen: `.measureMode(mode)` at
  `EditorState.measureToolMode`'s setter, which every way of switching lands in,
  and `.specListCopied` at `copyMeasureSpecList`. The mode event is raised
  whether or not the mode CHANGED, because the thing a step waits on is the
  person asking for it.
- **A step can ask for something already true.** The Measure tool keeps the mode
  you left it in, so "press I until it reads Distance" comes up with the button
  already reading Distance, and a waiting step there strands you: nothing fires
  and the only way on is Skip This Step. Caught on 2026-09-13 by the snapping
  walk, which hung for its whole timeout on exactly that. A step whose trigger
  describes a STATE that already holds now offers a plain **Next**
  (`TutorialRun.stepWasAlreadyTrue`, decided in the controller where the editor
  can be asked). Only a state can be already true: nothing is already true about
  "the person made an edit", and treating an event that way would be the timer
  lie in another costume.

Two rules the track adds to the ones Basics settled:

- **No guide ends on a waiting step.** A guide whose last step waits simply
  vanishes the moment you do the thing, with no closing word. The size guide did
  exactly that until 2026-09-13. Every guide ends on a step you press Done on.
- **A step's copy must be true under the flags the guide asks for, and no
  others.** The snapping guide ends on the Measure Tool section's Snap setting,
  which is the centers flag's, so the guide requires that flag too rather than
  saying something that is only sometimes true.

Reading the Tutorials window back needed a change as well: ten guides made it
scroll, and a row that has scrolled away is in the accessibility tree with no
words worked out for it yet, so four perfectly good Start buttons read as
silent. `WindowReadProbe.fullReading` scrolls the window through and reads at
each stop, and the check is stronger than the one it replaced: every guide must
have a button that says its own name, not merely a button with some words on it.

## The Looks track

How a layer is painted, and what can be added to it. Four guides: the first two
teach the split the panel turns on, and the last two teach the two ways a layer
reaches what is UNDER it.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| What a shape is made of | the starter screen | Appearance is what it IS, Effects is what you added, and the line round the card is in the second one |
| Add a shadow, a border, a glow | the starter screen | the plus on the Effects heading, three things added for real, the order, and that the tool remembers |
| Blur or pixelate what is underneath | an account screen, flattened | K, one drag over an address, Strength, Pixelate, and what really leaves the app |
| Mix a layer with what is below it | the same screen with a box on it | the Blending row under Opacity, Multiply as a highlighter, Screen the other way |

Nothing in the framework had to change: every step is an anchor that already
existed, a trigger that already existed and a prepare that already existed. The
track added two samples and one anchor name (`panel.lens`), which is data.

Three things this track settled, and they are about the CATALOGUE rather than
the machinery:

- **A guide teaches what shipped, not what the task asked for.** The task that
  asked for this track named its first guide "Fill and outline: what a shape
  has". Outline stopped being a row on 2026-09-08 (`OutlineRetirement.swift`):
  a layer's edge is a Border in the Effects list now. So the first guide teaches
  the SPLIT instead, and the edge is named in the list it actually lives in. A
  test over the track fails on the word Outline in any of its copy.
- **A guide points at a shape its sample brought, never at a shape you draw.**
  The rectangle, the ellipse and the line share ONE slot in the tool bar and the
  slot wears whichever you used last, so a step pointing at the rectangle points
  at nothing on an app whose slot is wearing the line. A test enforces it for the
  whole track.
- **Pick a target with no words on top of it.** The first guide said "click the
  blue button", and the button wears a label: on the probe the click landed on
  the words, picked the TEXT layer, and the panel came up with a Color row where
  the step had promised a Fill. It picks the card instead, which is large and
  carries nothing on the part you would click.

Two samples, both flattened, both made up: an **account screen**
(`TutorialSample.accountScreen`) with a name and an address at example.com on
it, which is the picture somebody is about to send on and the reason anybody
wants a lens; and the **same screen with one solid box already lying over the
address** (`.tintedScreen`), so the mixing guide is about the one setting rather
than about drawing a box first.

## The Components track

Build a piece of UI once, fetch it as often as you like, and change one copy
without cutting it loose. Four guides, in the order the job is done in: the
first two are the whole bargain, and the last two are the part everybody gets
wrong.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Make a component | a button drawn as two loose layers | pick both, ⌘G, ⌥⌘K, name it, and where it lands on the shelf |
| Use it again and again | the same button, already a component | the Components shelf, two copies placed, and one colour change reaching both |
| Override one copy | the original with two copies on it | the original's Adjustable list, the knob a copy answers, and the way back |
| One name, two looks | the same desk | Versions, a second drawing, and the Version row on a copy |

**The hard idea is what a copy OWNS**, and nothing on screen says it, so the
guides do. A copy's contents are not its own: they are refilled from the
original after every edit, and the few facts somebody set on the copy are
written back over the top. Every rule in the track falls out of that one
sentence.

Three things the track settled about the CATALOGUE, each of them measured on the
probe rather than reasoned about:

- **A guide names nothing the sample did not bring, and the sample avoids every
  name already in the window.** The shelf arrives stocked with five starters and
  one of them is called Button, so the sample's component is **Save Button** or
  the shelf shows two identical tiles and "your button's tile" points at either.
  A document's own picture is a layer called Background, so the pieces inside
  are **Box** and **Label** rather than Background and Label.
- **No step sends anybody into the layers list on a page that holds copies.**
  Every copy carries its original's name, so an original with two copies puts
  three rows reading Save Button in the list, told apart only by the mark on
  each row. Reaching the original is a click on the drawing, where there is one
  of it. A test enforces this for every guide that brings copies.
- **A step never both says "double click" and waits on a selection.** The first
  click of a double click already selects, which raises the very event the step
  is listening for, so the card moves on halfway through the gesture and the
  next thing the person does lands on the wrong layer. Picking is always its own
  single click, and the double click lives in the step that waits on the EDIT it
  leads to. A test enforces it.

And one about the SAMPLE: **a target with words on it has to be big enough to
click clear of them.** The button was 176 across at first, its label filled the
middle, and a double click aimed at "the box" picked the text layer every time.
At 240 there is room either side. This is the Looks track's "pick a target with
no words on top of it" again, one level down: sometimes the answer is not a
different target, it is a bigger one.

Three things the framework did not have, each added where it happens rather than
worked around in the guide:

- **A rubber band round two layers now raises `.layerSelected`.** It lands in
  `multiSelectedLayerIDs` and leaves the single selection alone, so the trigger,
  wired only at `selectedLayerID`, never fired: the first guide watched somebody
  drag a box round both layers and did not move. The doc already claimed this
  trigger meant "the person selected a layer, on the canvas or in the list", so
  this is the claim being made true.
- **A reveal now holds out for the WHOLE target** (`isWhollyShown`), not for the
  first sliver of it. Make Component sends the dock to the shelf to show you the
  new tile, a beat after the step asked for the Component section; the section
  was left hanging off the top of the panel with its Name box out of sight, and
  a sliver counted as arrived, so the guide stopped asking and rang the two rows
  that were left. The step said "the Name box is waiting" over a rectangle with
  no Name box in it.
- **A third prepare, `showComponentShelf`.** The shelf remembers the scope you
  left it on and that is your captures until somebody changes it, so ringing the
  Library for a step about a button rings a shelf of screenshots. It is still
  reveal only: turning to a shelf is not fetching anything off it, and it is the
  same two lines Make Component already runs for the same reason.

It also turned up one ordinary bug, fixed with it: **Add Version handed the
keyboard to the new version's name field one pass too early.** Adding a version
changes the selection, so the section is rebuilt around that row in the pass it
first appears in, and a focus asked for before the field is in the responder
chain is dropped. Typing went to the canvas. The component's own Name field
survives the same trick because its section is already standing.

**It is called One name, two looks, not Variants.** The task that asked for the
track named that guide Variants; the app has never used the word. A component
holds VERSIONS, the panel says Versions, and a guide teaches what shipped. Same
rule the Looks track settled over Outline, and a test enforces it.

## The Colours and Styles track

Name a colour or a piece of type once, use the name wherever you like, and
change it in one place. Four guides, and the payoff is the second one's last
step.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Save a colour as a style | the settings card | the small button at the end of the Fill row, Save as Style, and the tile that lands on the shelf |
| Change it everywhere | the same card | one name on two layers at once, one edit to the tile, and the third layer that did not move |
| Text styles | the same card | the Style row at the top of Text, the name put on a second heading, and the tile dragged onto a third |
| The Library | the same card | the four scopes, a colour let go of ON the shelf, and what a tile's own settings do |

Nothing in the framework had to change. No new trigger, no new prepare, no new
anchor name: saving a colour or a text style already turns the Library to Styles
by itself (`showStylesShelf`), so every step that points at the shelf finds the
right one standing there.

**One sample for the whole track** (`TutorialSample.stylesScreen`): a settings
card with three rows, each a heading, a line under it and a blue switch.
Somebody doing the track back to back sees the same card every time, so the
second guide starts on ground the first one covered.

Four things the track settled, each measured on the probe rather than reasoned
about:

- **Three of each, because two only shows that something happened.** Two
  switches repainting together says an edit reached two layers. The third
  switch, which never had the name and so stands still, is the only thing on
  screen that says WHY, and it is the closing step of the second guide.
- **A guide has to CHANGE something you can see.** The card's three headings
  were set identically at first, which made every step of the text guide
  invisible: save the type, put the name on the second heading, drop it on the
  third, and the picture never moved. Only the first heading is set like a
  heading now. The other two are the same words typed in a hurry, so setting one
  by the name grows it into place in front of you.
- **A drag needs both its ends on screen.** The step that drops a colour on the
  Library rang the whole dock at first, which left the shelf scrolled off the
  bottom of the very ring that was meant to contain it: the card said "let go
  anywhere on the Library" over a panel with no Library in it. It rings the
  SHELF instead, which scrolls it up and leaves the Fill row the drag starts on
  above it.
- **A step may not name a control that only exists after an optional click.**
  The Library guide ended on two cards, the first saying "click the tile and its
  settings open" and the second naming the Remove button in those settings.
  Pressing Next rather than clicking took you straight to a card about a button
  that was not there. They are one card now.

And one ordinary bug, found by the track and fixed with it: **a style's name
field asked for the keyboard one pass too early.** The field is installed by the
very change that asks for focus, and a focus asked for before the field is in
the responder chain is dropped without a word. It got away with it until a guide
was running over the window, where the following timer put the race the other
way about half the time and the name somebody typed went into the picture
instead. Measured on the probe on 2026-09-13: four runs of the text styles walk,
two failed. Fixed in all four naming fields that share the shape (the Style row,
a colour row, an effect's Style row, and the field the Library raises when a
colour is let go of on it), each one now asking one pass later. It is the same
bug the Components track found in Add Version, in a different costume.

**The copy names no section.** The colour a shape is painted lives in a section
headed Color or Appearance depending on `next-shape-parts`, so every step here
says "the Fill row" and points, which is true under both. Same rule the Basics
track settled about menu rows and keys.

## The Building UI track

How to build a screen rather than annotate one. Four guides in the order a
screen actually gets built, and the idea underneath all four, which nothing on
screen ever says out loud: **a screen is a group with a size**. Everything a
group can do it can do, everything you draw inside it joins it, and the numbers
that arrange a group arrange a screen.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Frames are screens | a page with nothing on it | F, a screen dragged out, the Frame section, and a card drawn inside it turning up INSIDE it in the layers list |
| Let a screen arrange its contents | a screen with three cards placed by eye | Arrangement set to Stack reading the spacing back, one typed Gap moving all three, and a card deleted with nothing left to tidy |
| Padding and columns | the same screen, cards flush to its edges | Padding in Layout, Show columns, and the one fact that connects them: the columns start where the padding does |
| Line things up | three boxes, none of them in line | the Arrange row shown once, then ⌥W and ⌃⌥H |

Nothing in the framework had to change. Two anchor names were added
(`panel.frame` and `panel.columns`), which is data, not machinery.

**Two samples, one screen.** `handPlacedScreen` and `tightScreen` are the same
320 by 344 screen called Home with the same three cards in it, in the two states
the guides start from: dropped in by hand at 44 and then 36 apart, and stacked
evenly with nothing clear at its edges. Somebody doing the track back to back
sees one screen throughout.

Four things the track settled, each measured on the probe rather than reasoned
about:

- **A canvas step draws its card ACROSS the picture, so nothing may live under
  it.** A step pointing at the whole canvas has no side of the canvas to sit
  beside, so the placement puts the card inside the picture, along the top and
  centred (`TutorialCalloutLayout.insideSurface`). At the size a tutorial window
  opens at that band reaches about 113 points down the page. The first cut put
  the screen at the top of the page and the payoff step — two cards closing up
  by themselves — was read out from behind the very card talking about it. Every
  sample here now starts below `TutorialSampleScreen.calloutSkirt`, and the
  lining-up guide asks you to sweep from the clear page to the LEFT of the boxes
  rather than above them. Filed as a framework follow-up as well, because a
  guide should not have to know this.
- **A screen is a fixed box, so the demo gap has to go DOWN.** Growing the gap
  on a screen whose cards already reach the bottom pushes the last one past the
  edge, where the screen clips it and the panel starts reporting an overflow: the
  guide would be teaching a number that breaks the thing it is teaching on. The
  sample is spaced too loosely on purpose, and the guide tightens it to 24.
- **A card has to stretch, or padding moves it sideways and cuts it off.** Type
  24 into Padding on a screen whose cards are a fixed width and they slide right
  and hang over the far edge. `tightScreen` sets the screen's own rule for its
  contents to Stretch across, so the same number brings them IN on both sides,
  which is what the step promises.
- **The columns already come out right for the screen you have.** Switching them
  on a phone-shaped screen gives four columns with a 16 gutter
  (`FrameColumns.suggested(forWidth:)`), so the step that asked you to type four
  was asking you to type the number already in the box, and the guide never
  advanced. It sets the gutter instead, and says out loud that the four came
  ready.

**White cards were a hairline.** The first samples drew white cards on a white
screen with a pale stroke, which on the probe read as nothing at all. Every
guide here is about watching cards MOVE, so they are a soft grey fill now.

## The Video track

The smallest track, and the only one that does not teach in the picture editor
at all. A recording opens in a window of its own: one picture, and one floating
glass controller over it. No tool bar, no docked panel, no layers.

| Guide | Brings | What it teaches |
| --- | --- | --- |
| Trim a recording | a recording it wrote itself | the transport, the scissors, a handle at each end, Done, and what saving does |
| Export MP4, GIF or HEIC | the same recording | which of the three to pick, what the quality levels are for, and Copy GIF as the way to skip the file |

**This is the track that made the framework grow**, and the shape of the growth
is the point: three things were added, each of them where the difference really
is, and nothing was special cased in the catalogue.

- **`TutorialHost`**, a protocol with three questions on it: what window am I
  in, reveal this, and is this already so. The controller used to hold an
  `EditorState` and ask it those directly. Both editors answer them now, the
  controller never asks which it is holding, and a third kind of window becomes
  a third conformance rather than a branch.
- **Anchors for the recording's window** (`TutorialAnchor.video(_:)`): the
  picture, the transport, the scissors, the trim timeline, Done, save, copy and
  export. Named off the part rather than off the glyph on it, the same rule as
  everywhere else. Deliberately short: every one of them is somewhere a guide
  really sends people.
- **Five triggers**, wired where they happen in `VideoEditorState`:
  `.trimModeOpened` at `beginTrim`, `.trimStartMoved` and `.trimEndMoved` at the
  two handle setters, `.trimApplied` at `commitTrim`, and `.recordingCopied` at
  `copyRecording`. The two handles get an event EACH rather than one between
  them, so dragging the left one twice cannot satisfy the step about the right
  one.

Five things the track settled, each measured on the probe:

- **The controller hides, and every control a video guide points at lives on
  it.** It fades 2.4 seconds after the pointer leaves, and hitting play clears
  it out of the way immediately. A ring round a faded out button is the worst
  failure this framework has, so a guide running over the window pins it up for
  the whole guide (`isTutorialRunning`, which `editing` counts and `forceHide`
  respects). Reveal only, like every other thing a guide may do, and the fade
  comes straight back when the guide closes.
- **A sample that is a real file.** Every other sample is a few layers put into
  a window; this one is an MP4 written to the caches folder before the window
  opens (`TutorialSampleRecording`), and rewritten every time a guide is started
  because the guide teaches that saving bakes the trim in. It is eight seconds
  with two seconds of nothing happening at each end, so trimming it has a point
  rather than being a gesture practised on nothing. Writing it costs about a
  third of a second.
- **Where the clip draws matters.** A card is a fixed width in the middle of
  the window, and in a window this shape the cards cover the middle column from
  top to bottom: a clip whose only moving part was in the centre would be a clip
  you could not watch while the card told you to watch it. So the sample puts
  its filling bar along the very top edge, above the highest a card reaches, and
  its counter in the left column, clear of the widest one. Same lesson the
  Building UI track learned as `calloutSkirt`, in a window with less room.
- **Nothing in a menu can be pointed at, and Export runs a MODAL save dialog.**
  The three formats are rows in a popup, which is its own window, and picking
  one runs `NSSavePanel.runModal`, which would sit on top of the card with
  nothing to press. So the export guide rings the Export button and says what is
  inside it, and the one thing it asks anybody to do is Copy GIF, which needs no
  dialog and is what most people want anyway.
- **The window autoplays as it opens.** A first step saying "press space to play
  it" would come up already finished every single time. So the first two cards
  describe the clip and teach the transport, and nothing waits until the
  scissors.

And the one it says out loud rather than hiding: **trimming is the only edit in
the app that is baked in when you save.** The last card says so, names Revert to
Original as the way back, and does not make anybody save. A guide that quietly
rewrote a file on its way past would not be a guide.

**Walked three ways.** `tutorial-trim-a-recording-walk` and
`tutorial-export-a-recording-walk` drive the real window through every step, and
`tutorial-trim-a-recording-skipped-walk` skips every waiting step to prove the
last card stands on its own when there is no trim, so no save button, and
nothing to ring. That is the framework's centred fallback doing its job, checked
rather than assumed.

Two things the walk harness had to learn, because it had never seen a recording:

- **It can adopt a window with no editor in it** (`adoptRecording`), and
  `waitFor tutorialStep` no longer insists on one: where a guide has got to is a
  fact about the guide, not about a window.
- **A recording's window is left VISIBLE for the walk.** Every other walk hides
  the window it drives. Here the offscreen render draws the video as a black
  rectangle and the glass controller as very nearly nothing, and a screen
  capture of a window at zero alpha comes back blank, so a picture taken either
  of those ways shows neither the clip nor the controls. Visible, the capture
  shows both.

## Where the rest of it is

Landed here: the framework, the anchors, the callout, Take the Tour, the Help
menu, the track submenus, the hub window, the first launch offer, and all seven
tracks. Still queued:

- **A renamed control breaks the build, not somebody's tutorial** — a generated
  walk per guide that drives the real editor and asserts every step's anchor
  resolves. The unit check here (`TutorialCatalogCheck`) is the promise; that
  one is the proof.
