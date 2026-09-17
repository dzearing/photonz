# The panel shows the sections that matter

*Next, `next-panel-sections`. Model: `Sources/PhotonzCore/PanelSectionVisibility.swift`
(pure, tested). App: `PanelSectionVisibilityStore`, `PanelSectionsFooter`,
`InspectorPanel.orderedAvailableSections`, `EditorState.panelSectionSituation`.*

## What was wrong

The right hand panel carries twenty-six possible sections. Measured in the
running app on 2026-09-15 (the study `work-out-whether-the-right-hand-pane-is-carrying`,
page `docs/design/mocks/pages/pane-load.html`): a three layer document with one
piece of text picked asked the panel for **1052 points** against the **968** the
largest window on that display can give it. The panel does not fit its own
contents at any window size.

The user's words, looking at it with a component selected:

> the panes are now completely cluttered and hard to read and unpredictable.
> total mess. I feel like we should maybe have a way to not show some panes. I
> think the library pane will almost never be used. But maybe at the bottom of
> the panel is a way to show/hide panes that are questionably necessary so we
> can have an auto mode that only shows panes relevant to the situation.

## What was already true, and why "automatic" needed sharpening

The panel has never shown every section at once. `InspectorPanel.availableSections`
is one long test per section against what is picked: an Annotation section only
for a shape with settings, a Text section only for text, a Frame section only
for a screen. So "an automatic mode that shows what is relevant to the
situation" describes what the panel already did, and adding a mode by that name
would have added a label and nothing else.

Two things were genuinely missing.

1. **No way to say "I never want this one."** A section that applies is a
   section you get, whether or not you have ever used it.
2. **No written rule for the ones that only matter sometimes.** The Library
   shelf waits to be asked for, Measurements waits for a measurement, Component
   waits for a component. Each of those was a separate `if` in a 200 line
   method, decided when that section was built, with nothing saying they were
   the same kind of decision or what the decision was.

## The one rule

> **What you PICK never adds or removes an optional section. Only what the
> document holds, the tool in your hand, and what you asked for may.**

This is the constraint that keeps the panel predictable, and it is the reason
"automatic" is not the clever thing it could have been. A section that appeared
and disappeared as you clicked from one layer to the next would be *worse* than
the clutter: the panel would rearrange itself under your hand on every click,
which is half of what "unpredictable" meant in the complaint above.

So every automatic answer is a fact about the **document** or the **window**.
`PanelSectionVisibility.Situation` holds nothing about the selection at all,
which makes the rule enforceable rather than a promise (see
`noAutomaticAnswerDependsOnWhatIsPicked` in the tests).

## Which sections are optional

The **optional** sections are the ones that answer for a *job* rather than for
every layer. Everything else — the layers list, the section named after the
thing you picked, Appearance, Effects, the tool in your hand — is part of what
the panel *is* and can never be hidden. That is what stops anybody arriving at
an empty panel: there is no combination of answers that empties it.

| Section | Automatic shows it when |
| --- | --- |
| **Library** | you asked for it (View ▸ Show Library) |
| **Library item** | whatever the Library is doing — it is part of the shelf, never its own row in the list |
| **Measurements** | the document holds a measurement |
| **Motion** | always (see below) |
| **Layout** | the document holds a screen or a group |
| **Columns** | a screen in the document is showing its columns |
| **Arrange** | always |
| **Component** | the document holds a component, original or copy |
| **Shadow** | always (this section only exists in the release without the Appearance/Effects split) |

Motion, Arrange and Shadow have no job to wait for: they answer for whatever is
picked, whenever anything is. They are listed anyway, because the point of
listing them is that you can turn them **off**.

**Motion was nearly written the other way, and the reason it is not matters.**
It looked like the clearest win here: it arrives on every single picked layer,
costs about 130 points, and most documents are never animated. But the plus on
the Motion section's own header is how the *first* motion is made, and
`hasMotionStrip` is false until something already moves, so hiding the section
would have left nothing in the window that could start an animation at all. A
rule that hides the only door is not an automatic rule, it is a bug, and it
would have broken `motion-swings-a-layer-walk` on its first step. So Motion
arrives exactly as it did, and somebody who never animates turns it off once.

Every automatic answer is ANDed with the section's existing applicability test.
Pinning Measurements on in a document with no measurement in it still shows
nothing: there is no list to draw. A section you pinned on arrives the moment it
has something to say and then stays.

## The Sections row

One row at the foot of the panel, `PanelSectionsFooter`. It is a **row, not a
section**: no chevron, no grip, nothing to collapse, nothing to reorder, and it
sits **outside the dock's scroller** so it is on screen whatever the panel is
scrolled to. That placement is load bearing rather than tidy — the row is the
way back to anything automatic has left out, and a way back you have to scroll
to find is not a way back.

It reads `Sections` until somebody has actually **turned a section off**, and
`Sections · 3 hidden` from then on. The count is of sections a PERSON hid, and
nothing else: a section automatic left out because the document has no job for it
yet is waiting, not missing, and counting those made a brand new document open
saying `Sections · 5 hidden` about settings it never had. A count that is there
whatever you do is noise; a count that appears is the only cue that something is
missing. `PanelSectionVisibility.footerLabel` is the whole rule, and the walk
reads the words off the row rather than only finding the row.

Pressing it opens the list: every optional section this release actually builds,
each with a switch and a word underneath saying **why it is where it is** —

- **Automatic** — the document earned it and it is on screen.
- **Automatic, not needed in this document yet** — nothing here needs it. Start
  measuring and Measurements arrives on its own.
- **Always shown** — you pinned it on.
- **Always hidden** — you turned it off.

Without that word there is no way to tell a section you hid from one the
document simply has nothing for, and the two want different things from you.
A row you have answered for also carries a small revert arrow, and
**Use Automatic For All** at the foot hands the lot back in one press.

## Where the answer lives

`experiments.<release>.panelSections`, as `motion=1;library=0` — sorted, so the
same answers always write the same string. **Per release**, the way the feature
flags are, so arranging Next's panel never disturbs Current's and the day Next
is promoted nobody inherits a panel they did not arrange. A saved answer naming
a section this build no longer has is dropped on read, exactly as a saved panel
*order* drops ids it no longer knows.

`PanelSectionVisibilityStore` is one store for the whole app, like
`IconKeylinesStore` and `CanvasGridStore`: you are saying how you like the
panel, not decorating one window.

## This is what a MODE is made of

The queue task *Modes you can swap, rather than project types you are stuck in*
describes a mode as a preset of what is visible, which you can always override
by hand. That is exactly `Choices`: a mode will be a named set of these answers,
set in one go. **It must not grow a second mechanism.** If a mode needs to hide
something that is not optional here, the fix is to widen this list and say why,
not to add a parallel switch.

## What this does not fix, stated plainly

**The automatic half of this saves very little on its own, and pretending
otherwise would be dishonest.** Every automatic answer above is ANDed with a
selection test the panel already had, and for most of them the two say the same
thing: Measurements only applied when the document held a measurement, Component
only applied when a component was involved, Columns only applied when a screen
was showing columns. Writing those down as one rule is worth doing — they were
scattered `if`s nobody could read as a set, and the next section added will now
have to answer the question rather than invent an answer — but it moves few
points.

The value is the other half: **you can now say "I never want Layout" and mean
it**, and the panel remembers. That is what was actually asked for.

The panel is still over-subscribed for a rich document. That is the subject of
the other three tasks filed from the same complaint, not this one.
