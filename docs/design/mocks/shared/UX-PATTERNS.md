# Photonz — UX patterns & interaction model (the app's spine)

**Status: v1.9. §4 gains "A control that can only act over part of its range",
the row the ladder never had: a control that works, and simply does not reach
everywhere, is neither dimmed nor removed. The refused stretch of its track is
drawn spent and its fill starts at the wall, so a knob resting on a floor of 18
stops looking like a knob at nothing, and a range spent to nothing stops looking
like a slider nobody has touched. Written 2026-09-14 from four surfaces that met
the same wall in a week and answered it four ways, and it sorts the three things
that look alike: nothing to act on gets no row, a range merely wider than the
subject uses gets no wall, and only a range something else clamps gets this
treatment. `.slider.clamped` draws it in a mock. One audit gate in §9 to match.
No behaviour changed, and the shipped cases the rule names as wrong were left
filed rather than quietly fixed. v1.8: §4 gains "How much a section may say", the budget the line under
a section never had: at most one short line, and only when it says something you
cannot work out from what is already on screen. Written 2026-09-14 from the
decision "How much should the right hand panel explain itself in words?",
answered "One short line, and only when it earns it", after picking three layers
printed seven lines of grey prose ahead of the controls in a panel already 176
points over its own viewport. It supersedes the 2026-09-07 answer that left the
words alone, names where a cut sentence goes instead (the control's hover tip,
or the section header), and says which register the budget does NOT cap: a note
that reports a condition, shown only while that condition holds. v1.7: §4 gains
"What a key press says when it cannot act", the row
the ladder never had: a key has nothing to dim, so either the canvas notice says
what it could not do and names the way out, or something already on screen does
and the key stays quiet, and there is a test for which. §3's Modal and toast
entry gains "the question you can silence": when a command has earned the right
to stop and ask, how the question is worded, where the answer is remembered, and
that a person must be able to get it back. Both are written from what shipped in
the two days before, three keys and one question that each decided for
themselves, and both cite the commits and audits they were taken from. Two audit
gates in §9 to match. Written 2026-09-08. No behaviour changed, and one thing
already shipped that the new rules name as wrong was filed rather than quietly
fixed. v1.6: §0, §3 and D9 say out loud what was always meant: these rules
govern the shipping app as well as the mock pages. §3's panel-group height rule
is rewritten to lead with the behaviour in plain words (a group holds itself to
its own height; lists give up room and forms do not; when it still does not fit
the DOCK scrolls and no section is cut down to make it fit), with the class
names second as one way of spelling it. D9 is rewritten the same way and now
records how the app satisfies it. Written 2026-09-08 after four fixes in two
days each took a slice off one panel section instead of adopting the rule,
which was readable as a note about the design study. No behaviour changed. v1.5: §4
gains "The line under a section", one rule for the line under
a panel section that was quietly doing three jobs: what it may say, which
message wins when two want it at once, and how long each stays. Written
2026-09-08 with `a-number-that-springs-back-says-why-it-did`, which was about to
give it a fourth. v1.4: §3 gains the canvas guide as a named surface and D16
states the rule it follows: a guide drawn on the canvas goes OVER your work, reads as a
wash or a hairline rather than as something you drew, and never reaches an
export. Written 2026-09-07, after the canvas grid and a screen's columns each
worked the same answer out from scratch a day apart, with an audit gate in §9.
v1.3: §4 gains "a control that cannot act", one rule replacing the six
different answers six fixes gave the same question on 2026-09-04, with an audit
gate in §9. Scrubbed 2026-09-04 against what the app actually ships: §3 gains
the reveal rule, §4 gains "a property keeps its home", and §5's component-copy row
is rewritten to match. Every rule that changed names the audit or commit that
overtook it, and where the app is the thing that is wrong, the rule stands and a
task was filed. §1 and §3 describe the LEAN, SCALABLE shell (PRODUCT-MODEL.md
§4b): canvas-first, a floating bottom tool bar, one right dock of collapsible /
resizable / scrollable panel groups, rails, overlays, and a real responsive
contract. D1/D2 are amended (Library is a right-dock group or an overlay, not a
left dock); D3–D6 stand as written. This is the source of truth for how the
product behaves, above and beyond how a single page looks.** `AGENTS.md` governs how one page is
*styled*; this doc governs how the whole app *works* so that every page feels like
the same product, not a different app by a different person.

The problem this fixes: pages were authored in parallel, each inventing its own
chrome, its own way to reach tools/panels/catalogs, its own selection behavior,
and its own icons. Result: walking the pages feels like visiting many different
apps. Every page MUST now sit inside one shell, use one navigation model, one
selection model, and one icon library. When a page shows a surface (a media pool,
a component catalog, a vector tool), it must be obvious *how you got there, where
it lives, and how you get back*.

---

## 0. How to use this doc

- **These rules bind the shipping app, not only the mock pages.** A rule here
  describes how the PRODUCT behaves; the class names and stylesheet variables
  are how a mock page happens to spell it, and the app spells the same rule in
  Swift. So "that is a note about the design study" is never a reason for the
  app to do something else, and when a page and a build disagree, this doc says
  which one is wrong. Where the app is the thing that is wrong, the rule stands
  as written and a task is filed against the app.
- Read this BEFORE authoring or auditing any page.
- Every claim here should become either a shared DS class/pattern or an audit
  rule. If a page needs something not covered, add the pattern here first, then
  use it, so the next page reuses it instead of reinventing it.
- Keep it concrete: name the surface, say where it docks, say how you open it,
  say how you get back.

---

## 1. One app shell: lean, canvas-first, and built to scale

There is ONE window shell hosting ONE document (see `PRODUCT-MODEL.md` §1 and
especially **§4b, the layout system**, which this section implements). The
shipping app is deliberately **lean and canvas-first**, and it must stay that way
as scope grows. The resolution is **one scalable dock system that grows by
collapsing, resizing, and scrolling, never by inventing new chrome per feature**.

**Image · UI · Video are not separate apps, and they are not modes you toggle**
(PRODUCT-MODEL.md §4f). A workspace exists only as a **starting template chosen
at New**; once you are in a document there is no lens switcher anywhere in the
chrome. What varies follows the **document itself**: the **tool strip** carries
the inventory for the document's kind (D4), **tools and Properties are
contextual to the selected layer** (select a raster layer and brush/heal/clone
apply; select a frame and auto-layout appears), and the **timeline dock and
transport bar appear only when the document has time**, "timeline when time".
The canvas, layer model, Library, and Inspector are the same everywhere, so an
adjustment/filter layer grades a UI frame exactly as it grades a photo. You do
not switch experiences mid-document; you open a different document.

### The regions, always in the same place

1. **Title bar** (`.titlebar`) — traffic lights, **document identity** (name +
   context: "settings-capture · 2560 x 1440"), an optional status readout, and
   the right-aligned **Ask launcher**. Nothing else: no document actions (the
   native menu bar owns Share/Export) and no workspace switcher.
2. **Command surface** — the **native macOS menu bar is the real command
   surface** in the shipping app (File, Edit, Select, Layer, Type, Effect, View,
   Window, Help), and it is the literal expression of "everything the UI does is
   one API call". The mock never draws a fake one (D3); it shows a compact
   command button (`.tool` + `ic-more`) plus the **Ask launcher** (`.askbtn`, D6
   revised) as the secondary path, along with the **History** entry.
3. **Canvas** (`.cnv` > `.canvas`) — the document, and the dominant region. It is
   the only region that grows when everything else collapses. Selection lives
   here. Everything that floats, floats over this: the tool bar, the canvas
   action cluster, and overlays.
4. **Floating bottom tool bar** (`.cnv > .tbar`) — a rounded glass capsule
   centered at the bottom of the canvas: the **tool strip**, a separator, the
   **foreground/background swatch pair with a swap affordance** (`.swpair`), a
   separator, and the **zoom slider + percent** (`.zoomctl`). Overflow tools
   (`.ovf`) collapse into a **more** affordance (`.tbar-more`) when the window is
   narrow. This is the canonical tool surface for canvas work; there is no
   permanent options-bar row.
5. **Canvas action cluster** (`.cnv-act`) — top-right of the canvas: the **panel
   toggle** (`ic-sidebar`, `[data-dock-toggle]`) that shows or hides the dock, and
   the **history** entry. Panel visibility is controlled where the canvas is, not
   in a distant toolbar.
6. **Right dock** (`.pdock`) — ONE dock holding **stacked panel groups**
   (`.dgrp`): Layers, Properties/Inspector, Effects, Library. Every group is
   independently **collapsible** and independently **scrollable** with its own
   bounded height. The dock **resizes** by dragging a `.splitter.v`, and
   **collapses entirely** to a `.drail`.
7. **Rail** (`.drail` > `.drailtab`) — what the dock collapses to: a slim labeled
   strip. Clicking a rail tab restores the dock and reveals that group. At tight
   widths the rail drops its labels and becomes icons only.
8. **Bottom dock, only when the document has time** — the **transport bar**
   (`.transport`: volume, skip back, play, skip forward, a scrubber with in/out
   marks and timecodes, then edit actions) and the **timeline** (`.timeline`).
   Hidden in every other workspace.
9. **Overlays** — the **slide-down history sheet** (`.sheet.down`, ⇧⌘H) and
   anything catalog-like that would crowd the canvas. Overlays slide over the
   canvas instead of permanently consuming width.

A page does not have to render every region, but whatever it renders must be in
the region above, at the same edge, with the same affordance. No page invents a
floating panel where a docked one belongs, and no page invents new chrome when a
panel group would do.

### Responsive behavior (non-negotiable, PRODUCT-MODEL §4b req. 1)

Put `.cq` on the `.win` and it becomes the container-query root, so the shell
adapts to the **window** width rather than the viewport. Two breakpoints, both in
`shared/photonz-ds.css`:

- **≤ 880px (narrow)** — the dock stops consuming width: it becomes a **rail**
  plus an on-demand **overlay** beside the rail. The vertical splitter goes away.
  The tool bar's `.ovf` tools fold into `.tbar-more`. Transport buttons drop their
  labels.
- **≤ 620px (tight)** — the rail drops its labels, the zoom slider drops out, the
  transport compacts further.

Every editor page must render sensibly at both. Test it by narrowing the window,
not by drawing a separate small mock.

---

## 2. Navigation: how you reach a surface (and get back)

Rule: **surfaces dock; they do not pop into unexplained new windows.** For each
surface the mock shows, it must make the entry+exit legible:

- **Media pool / Component catalog / Style library / Design system**: these are
  the SAME surface family — a **Library** panel group (`.dgrp`) in the **right
  dock**, or the same content as a slide-down overlay when it needs room to
  browse. Inside Library, a **scope switch** (Media · Components · Styles · Systems)
  picks which reusable content you are browsing (D1/D2, amended). You reveal it
  from the canvas **panel toggle**, its **rail tab**, `⌥⌘L`, or the command
  palette; you add to it via the group's own "+ Import" affordance, drag-drop onto
  the group/canvas, or right-click "Add to Library" on a selection (video also
  adds via Capture). It is NOT a separate window and NOT a bespoke per-page
  widget. Video's "media pool" is this same Library group with scope = Media.
  Getting back = it never left; it is a persistent group in the one dock.
- **Tools** (pen, brush, crop, measure, etc.): always in the **floating bottom
  tool bar**'s tool strip (§6). Selecting a tool changes the canvas cursor and the
  active tool's options. You "get to the vector tool" by picking the Pen in the
  tool strip, not by teleporting to a different screen. When the window is narrow
  the tool may be under the **more** affordance, never somewhere else.
- **Guided walkthroughs** are the exception: they are teaching flows, explicitly
  framed as steppers, and should say so. But the SURFACES they show inside each
  step must still be the docked, real ones (Library in the left dock, Inspector on
  the right), so the walkthrough teaches the real app, not a diorama.

Every editor page should be able to answer, on screen: *what document am I in
(title bar), what tool is active (the floating tool bar), what is selected (canvas
+ the Properties group), where is my content library (the Library group in the
right dock), where do my captures live (the ⇧⌘H history overlay), how do I run a
command (the native menu bar, plus the compact command surface and the Ask
chat at ⌘K)*.

---

## 3. Panels & surfaces taxonomy (the whole vocabulary)

This is the complete list. **A feature that needs chrome outside this list is a
signal to adjust the foundation, not to invent locally** (PRODUCT-MODEL §4b req.
6). Learn these twelve and you can read every surface in the app.

- **Dock** (`.pdock`) — ONE persistent column on the right holding stacked panel
  groups. Resizable by a `.splitter.v`, collapsible to a `.drail`. There is no
  left dock: Layers, Properties, Effects, and **Library** are all groups in this
  one dock (see D1/D2, amended).
- **Panel group** (`.dgrp` > `.dgrp-h` + `.dgrp-b`) — the unit of panel scope:
  one titled section of the dock. Header = chevron + title + optional count +
  optional buttons; clicking it collapses the group to its header
  (`.dgrp.collapsed`). **New capability is a new group.**

  **The height rule, and it governs the app, not only the mock pages.**
  Everything under this heading is a law about how the product behaves. The
  class names and stylesheet variables are only how a mock page happens to
  spell it; the shipping app spells the same law in `DockHeightBudget`
  (PhotonzCore) and the bounded group bodies in `LayersPanel`. Where a page and
  a build disagree, one of them is wrong, and this is what decides which.

  1. **Every group holds itself to its own height and scrolls inside itself.**
     A 60-layer stack scrolls inside Layers and never pushes Effects or Library
     off the bottom of the dock. A group is never stretched to fill room it
     does not need: three layers draw three rows and the glass under them stays
     empty. At most one group in a dock may be the one that takes the leftover
     space (`.grow`).
  2. **Lists give up room, forms do not** (added 2026-09-07, from building this
     in the app: `the-properties-panel-fits-on-the-screen-it-has`, audit
     `2026-09-07-dock-fits-the-window`). Holding every group to an equal share
     makes the dock worse, not better: six groups sharing 996 points get about
     138 each, which puts Corner Radius inside a scroller in Effects, the same
     hunt one level deeper. What decides it is what the body IS. A **list**
     (Layers, the parts of what you picked, Measurements, the Library shelf) is
     as long as the document happens to make it, so nobody designed its height
     and shortening it costs a scroll you were going to do anyway. A **form**
     (Text, Appearance, Effects, Arrange) is a set of controls somebody
     chose, and shortening it compresses nothing, it hides controls. So forms
     are drawn whole and paid for first, and the lists share what is left,
     tallest first, each down to its own floor of about three rows.

     **A list of PANES has a taller floor** (added 2026-09-08, from
     `one-open-effect-fits-in-the-effects-list`, audit
     `2026-09-08-effects-list-fits-one-open-effect`). Effects is a list whose
     entries are small panes: a heading with its own settings under it. Three
     rows of floor cuts a pane across the middle, and half a slider reads as a
     rendering fault however carefully the edge is faded (a Border opened in a
     full dock lost the bottom half of its Width slider). So a pane list's floor
     is **everything down to and including its first OPEN pane, drawn whole,
     plus a peek at the next entry**. Nothing below that peek is protected:
     three effects open is a list you scroll. The floor stops at 45% of the
     dock, so one enormous pane cannot starve every group under it, and when the
     floor makes the dock over-subscribed rule 3 applies as it always does.
  3. **When it still does not fit, the dock scrolls and nothing is thrown
     away.** This is the case that keeps being met, so it is written down here
     rather than re-decided each time. A dock can simply be asked for more than
     it has: every list at its floor, every form drawn whole, and the total
     still taller than the window. Then the DOCK scrolls, because a dock that
     scrolls a little beats six peepholes. **What must not happen is a section
     losing content to make the arithmetic work.** Cutting one panel's rows,
     deleting a caption or hiding a control because the dock is full fixes one
     screenshot and leaves the law unimplemented everywhere else: on 2026-09-06
     and 2026-09-07 four tasks in a row each took a slice off one section
     (three shipped, the fourth was dropped once the real rule was found) and
     the dock still did not fit. If a dock overflows, the answer is the budget
     above, or a group the user can collapse, or one fewer group. It is not
     fewer words. The one exception is a wording change a person actually asked
     for: on 2026-09-07 the user was asked about the multi-selection caption
     repeated in six sections and answered leave the words alone.
  4. **A body that has been shortened says so.** Its cut edge fades out. macOS
     hides its scrollers at rest, so a control clipped in half with no cue
     reads as a rendering fault rather than as something to scroll. **The cut
     must leave something to fade**: squeezed to exactly one whole entry, a
     list ends on clean empty glass and reads as a list holding one thing, with
     the rest gone and nothing saying so. That is why the floor in rule 2 pays
     for a peek at the next entry as well as for the entry it protects.

  **Reveal** (added 2026-09-04 to describe shipped behavior: commit `4a6aac7`,
  audit `2026-09-03-library-reveal`): when the app brings a group into view for
  you it scrolls the DOCK, by the shortest move that puts the whole group on
  screen, and a group already fully visible must not twitch. The reveal stops at
  the group; it reaches INSIDE the group's own scroller only when the command
  named a particular thing in it, the way making a component scrolls the shelf on
  to that tile (commit `17dca1e`, audit `2026-09-03-shelf-tile-reveal`), or the
  way opening an effect scrolls the Effects list on to that effect (audit
  `2026-09-08-effect-reveal`). When both have to move, the DOCK goes first and
  the group's own scroller second, against the room it will have rather than the
  room it had: a group hanging past the bottom of the panel is room the thing
  inside it could have been given.
  **Only a command the user just issued about that group may re-open a group they
  collapsed on purpose** (Show Library, or making the thing the group holds). A
  section somebody shut on purpose stays shut. Ambient changes never may: a
  document loading, an undo running, a background update, a tool dropping what
  was selected all leave a shut header shut and do not scroll. The Library reveal
  audit put the remaining question to the user, whether even a direct command
  should overrule a deliberate collapse; until they answer, it does, because
  scrolling to a shut header shows a title and nothing else.

  **What you picked sits at the top, and a pick never scrolls the dock**
  (settled 2026-09-14; chosen by the user on 2026-09-13 from
  `queue/decisions/picking-a-text-layer-leaves-its-settings-below-t-when-you-pick-something-on-the-c.json`,
  built in the app as the panel's one rule, `Sources/Photonz/InspectorDockLayout.swift`).
  The section named after the thing you just clicked is the first thing under
  the layers list, then what it is placed against and what it is a copy of
  (Arrange, Component), then Appearance, then Effects, then everything general.
  Pick a piece of text and Text is what you are looking at.

  **A permanent section has to earn the room it takes, and Position & Size did
  not** (2026-09-15). Where a layer sits and how big it is was four number boxes
  sitting open at the top of the panel for every layer, forever. Measured on
  2026-09-15: a piece of text picked in a three layer document asked the dock
  for 1052 points against the 688 a laptop window gives and the 968 the largest
  window on this display gives, and 130 of those points were those four boxes.
  Moving something is what the pointer is for, and an exact number is wanted
  rarely and precisely, so they are now something you ASK for: Layer ▸ Position
  and Size…, Option Command P, or a right click on the layer's own row, opening
  over the thing they are about. The dock for that same selection is 922 points
  now, and in the largest window it fits for the first time.

  The general rule this is an instance of: **a panel is where a thing lives, a
  popover is where a thing happens.** A control belongs in the panel when it is
  looked at as often as it is changed. A control that is wanted rarely, and
  precisely, and is done with the moment it lands, belongs behind a command
  where it can be summoned over the thing it acts on. The cost is real and has
  to be paid on purpose: what is asked for no longer FOLLOWS, so anything whose
  job is to be watched while something else moves needs a readout on the canvas
  rather than a section in the column.

  **Because the order puts the pick on screen, there is no reveal on selection,
  at all.** That is the whole point of settling it: the panel used to fight
  itself three ways over the same job — the order the sections sat in, a scroll
  that chased each pick, and the room the Effects list kept for the effect you
  had just opened — and each one undid the others. Picking text left its
  settings off the bottom; picking a plain rectangle after it left the panel
  parked where the first pick put it, so the top of the panel was a colour row
  with no heading over it; and picking a row scrolled the layers list you had
  just clicked in off the top. One rule replaces all three:

  1. **The order puts what you picked on screen.** Nothing has to move, because
     nothing is in the wrong place.
  2. **The height budget keeps it there**, by shortening the LISTS and never the
     forms (the height rule above). The only thing between the top of the dock
     and the pick's own section is the layers list, and a list is the thing that
     gives way.
  3. **Selection scrolls nothing.** Not the dock, and not the layers list off
     its own top: click a row and the next row you want is still under your
     hand.

  What a reveal is still for, unchanged: something the app opened for you that
  you could not have known was there. The Library shelf a command has just
  filled, and an effect's settings — whether you opened them with its chevron or
  added the effect and they arrived with it. **Adding an effect reveals it
  exactly as opening one does**, because in both cases settings appeared and in
  both cases they are no use below the cut. Those two are the whole list.

- **Splitter** (`.splitter.v` / `.splitter.h`) — the drag-to-resize handle.
  Vertical between canvas and dock, horizontal between stacked groups. Visible
  grip at rest, accent on hover and drag, keyboard-resizable, bounded by
  `data-min` / `data-max`. Sizes persist for the session.
- **Rail** (`.drail` > `.drailtab`) — the dock fully collapsed to a slim labeled
  strip so the canvas dominates. Clicking a tab restores the dock and reveals
  that group. Icons only at tight widths.
- **Floating tool bar** (`.cnv > .tbar`) — the canvas tool surface: tool strip,
  color swatch pair, zoom. Overflow tools collapse into `.tbar-more`.
- **Transport bar** (`.transport`) — the bottom bar for documents with time.
  Volume, transport buttons, scrubber with in/out marks and timecodes, edit
  actions.
- **Overlay** (`.sheet.down`) — a surface that slides over the canvas rather than
  consuming width forever. The **history overlay** (⇧⌘H) is the canonical one:
  segmented All / Screenshots / Videos, a `.filmstrip` of `.filmcard`s with
  relative timestamps, and a selected card revealing its action row. Reach for an
  overlay when the surface is browsed occasionally, and a panel group when it is
  referenced constantly.
- **Popover / menu** (`.popover.pop` + `.menu`/`.menuitem`) — transient, anchored
  to its trigger via `[data-menu="#id"]`. Color pickers, add-adjustment menus,
  panel menus, tool-bar overflow, context menus. Dismiss on outside-click or Esc.
- **Canvas guide** (the canvas grid, a screen's columns, a guide you pinned,
  the snap line that lights under a drag) — chrome drawn INSIDE the picture's
  own rectangle to help you place things. It draws over your work, it is a wash
  or a hairline you can read straight through, and it can never reach an export
  or a copy. Full rule and the reasoning in **D16**. Not an annotation: a guide
  helps you PLACE something, while an arrow, a caliper or a gap label EXPLAINS
  something in the picture and is governed by D14 instead.
- **Canvas furniture** — chrome that floats OVER the canvas and is about the
  app rather than about the picture: the floating tool bar, the tool settings
  capsule, the zoom bar, the icon previews strip, a layer's name chip, and the
  canvas notice below. It is the third kind of canvas chrome, told from the
  other two by what it is for: it helps you place nothing (not a guide) and it
  explains nothing in the picture (not an annotation). Full rule, including
  what gives way when two pieces of it want the same corner, in **D16**.
- **Canvas notice** (`.cnv-hint`, bottom centre) — the one transient pill on
  the canvas, shared by the Measure tool's mode hint ("**Gap** Click the space
  between two elements") and the "Copied" confirmation after ⌘C. Its slot
  rule: **bottom centre of the canvas, just above the floating tool bar, never
  behind it; one notice at a time**, never a stack, with a confirmation winning
  over a hint while it is up. **While the Measure tool is in hand the slot is reserved for its mode
  hint**, so nothing else may park there. It has no close control and fades
  with whatever put it up. Not a tooltip (D12): it is on screen unprompted and
  never anchored to a control.
  - **It takes no input**, with one narrow exception added 2026-09-08 (audit
    `2026-09-08-notice-carries-the-way-out`): **a notice that REFUSES something
    may carry the way out of that refusal, as a single button**. Nothing else
    may. The test is strict: the person just asked for a thing, the app knows
    the one command that would let it through, and without the button they
    would have to go and find that command themselves. "Cannot delete a piece
    — Only a picture can have a piece taken out. **Turn Into Picture ⇧⌘R**" is
    the case it was written for.
  - Everything else about a notice survives the exception. **One action, never
    two.** No close control, no field, no menu inside the pill. It still fades
    on its own, it still never takes the keyboard off the canvas, and the
    button is never the only door to that command: it is a shortcut to a row
    that already has a permanent home in a menu, and the button **shows that
    row's keyboard shortcut**, so somebody who never touches a pointer has the
    same way out and keeps it after the pill has gone.
  - Two things a notice with a button must do that an inert one does not.
    **It stays up longer** (6s rather than 3s): three seconds is enough to read
    a refusal and not enough to read it, decide, and travel to a control.
    **Resting the pointer on it stops its clock**, so it cannot leave while
    somebody is reaching for it. And **only a notice with a button takes the
    pointer at all** — an inert one stays click-through, so it can never
    swallow a click meant for the canvas underneath it.
- **Modal + toast** — rare document-scoped dialogs (export, new document), and
  transient confirmations ("Saved", "42 instances updated"). The **capture
  toast** is the global one: it belongs to the menu-bar agent, sits bottom
  right of the screen, and carries its own Edit row (AGENTS.md, GLOBAL
  surfaces).
  - **A notice that fades may only carry a result you are FINISHED with**
    (added 2026-09-17, because this bullet filed every result under "transient
    confirmation" and one of them was not one). The test is asked after the
    pill has gone: **is there anything left for you to do about what it said?**
    "Saved", "Copied" and "42 instances updated" pass — it happened, the
    document shows it, you are done. "142 pieces out, 580 left in the picture,
    run it again for more" fails. That is not a confirmation, it is a standing
    count with an action attached, and three seconds later the app knew a number
    nobody could reach. Four audits on 2026-09-13 each put that to the user in
    their own words (`2026-09-13-separate-into-layers`, `-separate-boxes`,
    `-separate-hierarchy`, and `-separate-whole-screenshot`, whose evaluate item
    three is "The pill ends with 'run it again for more' rather than offering a
    button to press. Is a sentence enough, or do you want the button?").
  - **What a command does instead, when the result is something you are
    expected to act on later.** It owes both of these, and the fading pill is
    neither (built 2026-09-17 as
    `what-separate-left-behind-is-still-there-after-t`):
    1. **A lasting readout on the thing the result is ABOUT.** The separation's
       count sits on the picture's own row in the layers list for as long as it
       is true, held against that picture rather than against the command, so an
       undo takes the count away with the separation it describes. Attach it to
       the command and it outlives what it is talking about.
    2. **The action one press away, somewhere nothing can scroll it off.** A
       readout on a row is not enough on its own: separating a dense page leaves
       a 173 row list with the picture's row about thirty screens below the
       panel, so the count was kept and still nobody could see it. The press
       lives under the whole list, where there is a row's width for a real
       label, it speaks for the last thing acted on, and it goes quiet rather
       than sitting there reading zero.
    The pill may still say it first, because it is the fastest way to tell
    somebody what just happened. It is the headline, never the record.
  - **The question you can silence** (added 2026-09-08, from the first one the
    app shipped: `RasterizePrompt` and `EditorState+LayerOps`, commit
    `3c59faa6`, audit `2026-09-08-turn-into-a-picture`). A command that stops
    and asks before it acts is a tax on every use of that command forever, so
    the bar to ask is high and there is one bar, not one per feature.
  - **When a command may ask.** Only when what it takes away is invisible the
    instant after. Turn Into Picture is the case it was written for: the moment
    it is done the picture is identical, same shape, same colour, same place,
    and what is gone is that the shape or the words could be edited at all. A
    person finds out a week later, reaching for words that are no longer there.
    **Being destructive is not the test, and neither is being big.** Undo
    covers destructive: deleting a layer is as destructive as it gets and asks
    nothing, because you can see it go and ⌘Z brings it back. Ask only when a
    person could not have noticed. If in doubt, do not ask: the app has one of
    these questions and should grow them one at a time, each with its reason
    written down.
  - **How it is worded.** Four fixed parts. **The title is the question**, and
    it names the thing by the name it wears on screen: "Turn “Card” into a
    picture?", falling back to the kind of thing it is when it has no name.
    **The body is gain, then cost, then the way back, in that order**: what you
    get is what they came for, the cost is the part they cannot see, and "Undo
    puts it back" is the sentence that lets somebody say yes. **The buttons
    carry the verb**, so reading only the buttons still says which one does the
    thing: Turn Into Picture / Cancel, never OK / Cancel. **The menu row that
    raises it ends in an ellipsis**, the macOS promise that a question comes
    next; the button inside a canvas notice drops the ellipsis, since on a
    button three dots read as "more options".
  - **It rides the window as a sheet**, never a free floating box that stops
    the whole app, so a question about one document leaves the others alone.
  - **The silence box is standard macOS "Don't ask again"**, and it is only
    allowed on a question whose answer is nearly always yes and whose cost undo
    can put back. **A question the app cannot undo keeps asking, every single
    time**: "Clear capture history?" moves files to the Trash and must never
    grow a box. **A question that forks** (Save to Capture History offers
    Override Original and Save as New) may never be silenced either, because
    silencing it would pick one of two different outcomes on the person's
    behalf.
  - **Where the answer is remembered.** In the app's own settings, under a key
    named for the command (`photonz.turnIntoPicture.dontAsk`), per app bundle,
    so dev, probe and the shipping app each keep their own answer and neither
    can turn a question off for the other. **Never in the document**: a file you
    send someone must not carry your answer, and a question silenced on one
    machine is not silenced on the next.
  - **A person must be able to get the question back**, in one place that lists
    every question they have silenced and turns any of them back on. This ships
    in Next as of 2026-09-17 (`next-settings-window`): the app's first Settings
    window, on Command-comma and in the menu-bar menu, whose one page lists each
    silenced question by the name of the command that asks it, with a button
    that starts it asking again from the very next use. It lists ONLY what was
    actually silenced and says one plain sentence when that is nothing, because
    a page of unticked switches is an invitation to go and turn warnings off.
    Current does not have it yet and gets it when Next is promoted, so on
    Current an answer of "don't ask again" is still a door that locks behind
    you. **No release may grow a second silenceable question without the way
    back being reachable in it.**

### One setting, two doors

Added 2026-09-17, because there was no rule at all and three slices in one day
each needed one. On 2026-09-15 the loop speed shipped on the previews card AND
on the timing strip header (`2026-09-15-motion-loop-preview`, evaluate item
five); Start and Over shipped as numbers in the side column AND as bars you drag
on the strip (`2026-09-15-motion-timing-strip`, evaluate item six); and the
pivot's Around menu shipped directly above an At row saying the same two numbers
(`2026-09-15-motion-pivot`, rough item six). Three authors reasoned it out from
scratch, and all three ended up asking the user rather than citing anything. So:

**A second home for a setting has to pass one of these two tests. It is a
duplicate otherwise.**

1. **The first door is not reachable from where the work is.** Loop speed passes
   on this. The previews card only exists inside an icon frame, and motion is on
   every layer, so a shape animating on a phone frame has no card to reach for.
   A door you cannot get to is not a door. **A door earned this way still has to
   answer for the case where both are present**: inside an icon frame the card
   and the strip are on screen together, each showing the same rate, and that is
   what `2026-09-15-motion-loop-preview` puts to the user in evaluate item five.
   Until they answer, both stay: two rate controls reading the same number are a
   smaller cost than a control that is missing wherever you happen to be
   working.
2. **The second door answers a question the first cannot.** Start and Over pass
   on this. A number box sets a value exactly; a bar on a shared ruler says
   whether this part starts before that one, which no column of numbers can
   show. Same value, two different questions.

**A second door that passes neither test is a duplicate**, however reasonable
each half looked on its own: two controls on screen at once, next to each other,
of the same kind, answering the same question, are one control drawn twice.

**And passing a test is not the end of it, because two doors can still say the
same thing twice.** The pivot is the case that shows the difference. Around (a
menu of named spots) and At (two number boxes) pass test 2 honestly — a menu
cannot set 142, and boxes cannot say "its centre". But the menu has no name for
a pivot dragged somewhere of its own, so it falls back to printing the two
numbers, and the At row directly beneath it prints the same two numbers
(`2026-09-15-motion-pivot`, rough item six; both rows are drawn unconditionally
in `MotionListInspector.settings`). **Only one door is the readout.** The other
offers its choices, and where it has nothing to offer for the current value it
says so in its own terms rather than repeating the reading from the row below.
The shipped pivot rows disagree with that and are filed as
`a-turning-layer-says-where-its-pivot-is-twice`.

**What two doors owe each other.**

- **One value, moving together, live.** Change either and the other has changed
  before the gesture ends. No commit step, and never a door that only catches up
  when you leave it.
- **One name, one spelling, one set of stops.** A menu of rates behind one door
  and a free number behind the other are two settings that people will believe
  are two settings.
- **One undo step, with one description.** Which door you used is not part of
  what you did.
- **One of them is the home**, and it is the one the menus and the keyboard
  reach. The other is a shortcut to the same setting and is never the only way
  in, for the same reason a button inside a canvas notice is never the only way
  to a command.
- **The audit says which test it passed.** A second door is a real cost paid on
  purpose, so the slice that ships one names the test in its audit rather than
  leaving the next reader to work out whether it was deliberate.

### What a surface looks like while something is held over it

Added 2026-09-04 (audit `2026-09-04-panel-shows-landing`). Every surface that
takes a drop answers the same two questions BEFORE the user lets go, and it
answers them on screen, never only in the shape of the pointer. The pointer's
sign lives in the window server: it cannot be looked at closely, it cannot be
photographed, and on a big surface it is nowhere near the thing that is about
to change.

- **Will you take this?** The surface that will take the drop draws an accent
  edge around itself and a faint accent wash inside it. The surface that will
  REFUSE it draws a dashed warning edge and no wash. Two answers, told apart at
  a glance rather than by reading.
- **Where exactly will it go?** Whatever precision the surface has, it draws.
  A canvas draws the box the thing will fill. A list draws the same insertion
  line it already draws for its own rows: a line above or below a row for a
  slot in that list, an outline around a row for landing inside it. A surface
  with no finer answer than "somewhere in here" draws only the edge.
- **The promise is kept, exactly.** Whatever is drawn is where the thing lands.
  A surface that cannot honour a precise promise must make a coarser one rather
  than a prettier lie: a picture that will really land on top of the stack draws
  its line at the top of the stack even while the pointer is halfway down.
- **The edge is not the answer on its own.** A surface that can say where must
  say where. The edge says the surface is live; the line says what happens.

#### And it says a sentence, in words, when the drawing cannot say it

Added 2026-09-17 (merged from `the-drop-rules-say-what-a-surface-says-while-som`).
The three rules above are about what a surface DRAWS. There is a third question
they do not cover and the app has been answering ad hoc in three different
places: **what would letting go actually DO?** An accent edge says the surface
is live and an insertion line says where, and neither of them can say "sets this
text in Heading" or "Rectangle is not text".

**When a sentence is owed.** A drop that MOVES something says everything in the
drawing: the line is the slot, and words would be a caption on a picture that is
already clear. A drop that CHANGES something does not: the outline says which
things are about to change and nothing says into what. So **a drop that changes
rather than moves says what it changes, in one sentence, on screen.** A sentence
the app works out and does not draw is the failure this rule exists to stop: the
colour drop computed its sentence for three days and put it only in a tooltip
and an accessibility value, so the swatch lit up and said nothing, which nobody
chose (`2026-09-12-both-of-them-drop-line`, rough three).

**Where the sentence sits**, in this order, first one that fits:

1. **Under the pointer**, when what it is about is what the pointer is over and
   there is nothing underneath worth reading. The canvas: carrying a text style
   over words puts the sentence right where you are looking.
2. **Beside the target, level with it and clear of the surface it sits in**,
   when under the pointer would cover a neighbour that is part of the judgment.
   A column of colour rows is the case: the row below the one you are aiming at
   is usually the row you are comparing against, so the words stand off the
   whole panel and line up with the swatch instead
   (`2026-09-15-colour-drop-says-what-it-will-do`, rough four, which changed
   this away from the task as filed).
3. **At one end of the list, the end the aimed row is not near**, when the
   target is a row too narrow to hold a sentence and has no clear side. It
   covers a row at the far end while it is up, and that is the price of the
   third case rather than a defect (`2026-09-09-text-style-row-drop`, rough
   three).

It never lives only in a tooltip, only in an accessibility value, or nowhere.

**What it says when the surface will refuse.** A refusal speaks in the same
place a yes would have, and it says WHY, and it names the one thing to do
instead when there is one. Three shapes cover everything shipped so far:
nothing here can take it, so say where it does go ("Drop this on a piece of text
to set it in Heading"); this is the wrong kind of thing, so name the thing and
the kind ("Rectangle is not text, so it cannot wear Heading"); this is already
true ("This text is already Heading"). A surface that refuses by going quiet is
the thing every one of these replaced.

**One spelling for the whole family.** It is what letting go DOES, in the
present tense, not what you are doing: "Sets this text in Heading". It names the
PART it will change and not the layer, where the outline already says which
layer — a made-up layer name says less than the drawing does. Counting stops at
two: "both of them", then "all 3 of them"
(`2026-09-12-both-of-them-drop-line`). And the picture and the sentence must
agree about the same drop: every box the drop would reach is outlined, and the
sentence counts exactly what is outlined, which is the bug that shipped first
and was caught in review — one outline under the pointer beside words reading
"all 2 of them".

Audit failing examples: a component catalog rendered as a bespoke centered card
with no dock and no open/close affordance; a panel that grows the window instead
of scrolling inside its group; a page that only works wide; a dock that takes a
dropped file with no sign at all that it was going to. Correct: a `.dgrp` in
the dock, or a `.sheet.down` overlay.

---

## 4. Selection model: global vs contextual

- **Global, always present** regardless of selection: the tool strip, the menu
  bar, the Library dock, document actions, zoom.
- **Contextual to selection**: the **Inspector** (right dock). Nothing selected =
  document/artboard properties. One layer selected = that layer's properties. A
  component instance selected = instance props + overrides + variant. Multi-select
  = shared properties only. This is the pattern users learn: *look right to see
  what the current selection can do.*
- **A property keeps its home, whatever the count.** The section a property sits
  in must not change with how many layers are picked. Fill is under the same
  heading for one layer as for five; picking a second layer changes what a row
  ANSWERS FOR (all of them, or "Mixed"), never where that row lives. A section
  that appears only during multi-select is for properties with no single-layer
  home at all, such as aligning and distributing, and never for re-homing ones
  that already have a home. Selecting a second layer must not move the control
  you were just using. *(The app follows this: the Color section is on screen as
  soon as anything with a color is picked, and Fill, Outline and Text sit under
  it for one layer and for five. `Scripts/playtest/color-one-home-walk.json` is
  the walk that keeps it true. The one thing that does still shift is vertical:
  Arrange appears above it on a multi-selection and pushes the sections below it
  down the panel, which is the allowance this rule makes for a section with no
  single-layer home.)*
- **Selection is shown in one consistent way**: the frame on canvas, the matching
  `.lrow.sel` in Layers, and a selection label. One object selected in three
  places reads as one selection.
- **Declare the canvas frame, never draw it**: `data-sel-frame="Hero · 220 × 120"`
  on the object's own box, and `selection.js` builds the ring, the four corner
  grabs and the size tag. Hand-writing that markup is how five pages ended up
  claiming a selection in their copy and drawing nothing on canvas.
  `node shared/check-selection.mjs` fails any page that makes the claim and
  breaks the promise.
- Tools are global; the *tool options* are contextual to the active tool. A mode
  lives in the tool's own button; a setting rides in the **tool settings
  capsule**, a small glass row floating on its own line just above the tool bar,
  and in the top of the Inspector, bound to the same value. There is no options
  bar and there never was one: this line used to promise one, and the capsule is
  what actually got built. D15 has the whole rule.
- **A control that cannot act is answered by what kind of control it is**, not
  case by case: commands dim in place, choosers are replaced by their answer,
  fields keep their number, bare handles go away. The rule is right below.
- **Mixed is one word, one weight, in the value's own place.** The rule is
  written out below.
- **A control over several picked things reaches all of them, some of them, or
  none**, and that count decides what it shows and whether its section is on
  screen at all. Disappearing is only ever the "none" answer. The rule is below.

### What Mixed looks like

Added 2026-09-04 (task `mixed-reads-the-same-way-in-every-control`, audit
`2026-09-04-mixed-one-look`). Every control in the inspector has to answer the
same question — the picked layers do not agree, so what goes where the value
would be — and before this each answered it differently: a menu said Mixed at
full strength, like a choice someone had made; a slider said it two steps down;
a field said it one step down; a padding field said it as a placeholder, paler
again; and the alignment rows said nothing at all and simply went blank.

One rule now, and every new control follows it:

- **One word.** `Mixed`, spelled and capitalised that way, from
  `MixedValue.text`. Never `Multiple`, never a dash, never blank.
- **One weight.** One step quieter than a real value, `MixedLook.style`. Mixed
  is not something you chose, so it must not read as loud as something you did;
  it is not a hint either, so it must not fade into the captions around it.
- **In the value's own place.** In the box for a field, as the closed title for
  a menu, in the readout for a slider, as the chip for a color well.
- **A control with no room for a word says it beside its caption.** A segmented
  row of pictures has no text in it at all. The word goes next to that row's own
  caption — `Across  Mixed` — never out at the trailing edge, where it lands
  against the next column's caption and stops saying which of the two differs.
- **Mixed is never absence.** A control that goes blank says "the layers differ"
  and "nothing is set here" in exactly the same way, and those are different
  answers.
- **A control saying Mixed is still a control.** Whatever you set from it
  reaches every picked layer, in one undo step.

Known exception, on purpose: a read-only number is quiet all over, so its Mixed
is quieter than the rule (`H` over a text layer). The word is not being singled
out there; the whole readout is quiet. That is settled, not pending: the user
answered
`a-number-you-cannot-type-into-stops-looking-like-a-number-the-app-worked-out-for`
on 2026-09-05 with "plain number, no box", so a read-only number now has no box
to be quiet inside. See **What a number you cannot type looks like** below.

A dash is not a contradiction of "never a dash". A dash means there is no number
here at all, and only a readout can say it: an arrow has no width of its own, so
its W would otherwise be a lone letter with a gap after it. `Mixed` means the
layers have numbers and disagree. Two different answers, two different marks,
and a box you can type in still says "nothing set" by staying empty.

### What a control DOES for several picked things

Added 2026-09-05 (task `one-rule-for-a-control-that-speaks-for-several-p`).
**What Mixed looks like** above settled the word and the weight. It did not say
what a control DOES, so every control that shipped after it settled that part
again on its own: the shadow switch shows plain off and explains itself in grey
underneath, the whole Component section vanishes rather than speak for two
copies, and W goes on showing 200 after both layers landed on 204. This is the
behaviour half of the same rule.

**Ask one question, of the control and not of the feature: how many of the
picked things does this control reach?**

| How many it reaches | What the control shows | What setting it does |
| --- | --- | --- |
| **All of them, agreeing** | the value | sets all of them, in one undo step |
| **All of them, disagreeing** | `Mixed` | sets all of them to what you set, in one undo step |
| **Some of them** | the value, or `Mixed`, for the ones it reaches | reaches only those, and one line under the section says how many, in words |
| **None of them** | the whole section is not on screen | nothing to set |

Everything below is a consequence of that table.

- **Absence is not disagreement.** A thing that does not have this property at
  all is not a thing that disagrees. Two red rectangles and a text layer with no
  fill make a Fill row that says red, not Mixed. This is the mirror of "Mixed is
  never absence" above: neither answer may be dressed as the other.
  *(`ColorStyleSelection.members` is exactly the reachable subset, and
  `selectionCount` is everything picked, so a row can say both.)*
- **A control never changes kind because you picked another thing.** A switch
  stays a switch, a menu stays a menu, a field stays a field. Selecting a second
  layer must not swap a switch for a checkbox any more than it may move a
  control to another section. Mixed is drawn INTO the control you were already
  using.
- **Speaking for some is the normal case, and it says so out loud.** When a
  control reaches fewer than all the picked things, the section carries one
  visible line saying how many and what the rest will do. Already the practice
  and the exemplar to copy: `shadowReachNote` and `borderReachNote` in
  `LayerEffectsInspector.swift` ("3 of the 5 selected layers have a shadow. The rows below
  change those; the switch gives the rest one too."). One line under the
  section, never a tip per control, same as the placement rule in **Where the
  explanation goes** below.
- **Disappearing is the last row of the table and nothing else.** A control goes
  away only when NOTHING picked has its property, which is the same reason a
  rectangle has no Text section. It never goes away because the picked things
  disagree, because only some of them qualify, or because nobody has decided yet
  what Mixed means there.
  The thing that leaves is the thing whose property is absent, and nothing
  larger. Pick two outlined boxes with no fill and the Fill row leaves while the
  Color section and the Outline row stay, which is what the app already does:
  `colorRowSlots` in `EditorState+ColorStyles.swift` lists only the slots the
  picked layers actually have. A whole section leaving is that same answer when
  every control in it is absent.
  **So the Component section vanishing on a second copy was a bug, not the
  rule.** Both copies have knobs; the panel reaches both; it stays and speaks
  for them. *(Fixed 2026-09-05, `the-knobs-panel-speaks-for-several-copies-at-onc`,
  audit `2026-09-05-copies-share-knobs`. `ComponentKnobSelection` is the reading,
  and it is the same value for one copy as for five, so the panel has one path
  rather than two that can drift. The walk that keeps it true is
  `Scripts/playtest/copies-share-knobs-walk.json`.)*
  The Layout section was the same bug in a different room, found and fixed the
  same way: every layer inside a container has a place in it, so picking a
  second one must not take the rows away. *(Fixed 2026-09-06,
  `the-layout-section-speaks-for-several-picked-lay`, audit
  `2026-09-06-layout-for-several`. `PlacementSelection` is the reading, again
  the same value for one layer as for five, and the walk is
  `Scripts/playtest/layout-for-several-walk.json`.)*
- **When the section applies but no control inside it is shared, the section
  stays and says so in one sentence.** Pick copies of two different components
  and every picked thing has knobs, so a panel that silently goes blank reads as
  a fault. The section keeps its heading and holds one sentence in the two
  halves the wording law asks for, who owns this and the one thing to do:
  "These copies come from different components. Pick copies of one component to
  set their knobs together."
  *(Shipped 2026-09-05 as `ComponentKnobSelection.differentComponentsNote`, which
  is where that sentence lives so two surfaces cannot write two of it. Layout
  says its own version of it, `PlacementSelection.differentContainersNote`, when
  the picked layers are not all in the same group: two layers in two groups are
  placed by two different containers, so a row averaging them would be setting a
  rule against a container neither of them answers to.)*
  Two controls are the same control when they are the same property of the same
  thing, never when they merely share a name. A knob called Label on one
  component and a knob called Label on another are two knobs, and a row that
  averaged them would be inventing a control neither original has.

#### What a control shows after a set the picked things refused

- **Read back what they took. Never echo what was asked.** After a set, the
  control shows the state the picked things are actually in, read from the
  document after the change, not a landing worked out before it. A number in a
  box that nothing has is the worst answer a panel can give: it is wrong, it
  looks authoritative, and the next arrow key steps from it.
- **All landed on the same value: show that value.** Type 200 into W over two
  labels that both floor at 204 and the box reads 204.
- **They landed on different values: show `Mixed`.** One label floored at 204
  and a rectangle that took 200 do not have a number in common, and the box must
  not pick a favourite.
- **An arrow key steps from what is on screen**, which is now true by
  construction, because what is on screen is what they have.
- **Nothing moved at all: say why, do not just snap back.** The control returns
  to the value it had and the line under the section carries the reason, in the
  wording law's two halves. A value silently springing back reads as a control
  that is broken rather than a selection that refused.
- **No toast, no flash, no error.** The number changing under your hand from 200
  to 204 IS the message. Refusing a width is ordinary, not an incident.

*(Done for the Position & Size fields on 2026-09-06, and true of every typed
number in a panel since 2026-09-16, when the three hand-rolled boxes became one
`PanelNumberField` on top of `NumberBox` in PhotonzCore: the panel sets the
layers and then reads `geometrySelection` again, and `LayerGeometrySelection`
no longer offers a landing worked out in advance at all. It could not have been right: a group held to a smallest width
by its own flow refused a typed 50 and kept 160, and the box went on showing a
50 that nothing on the canvas had. The saying-why half landed 2026-09-08,
`a-number-that-springs-back-says-why-it-did`: `LayerGeometrySelection.refusal`
is the sentence and `LayerSizeRule` is where it comes from. See **The line under
a section** below for the rule the line follows.)*

- **A rule that refuses a typed number owes the panel its own name.** The
  sentence is written from a limit that KNOWS what it is — the Layout section's
  Smallest and Largest, a text layer's own words — not guessed from the
  before-and-after pair. Every layer also has a floor of one point that nobody
  set, and "Smallest width holds this at 1 px" would send a person looking for a
  control that is not there, so a limit with no name says nothing at all.
  *(`LayerSizeRule` and `LayerGeometryEditing.limitReason`. Where a new rule
  cannot name itself, the fix is to give it a name, not to write a vaguer
  sentence.)*
- **A limit the panel can say afterwards is a limit it can say BEFORE.** The
  same numbers went into the field's hover tip ("Will not go below 160 px. Will
  not go past 260 px.") and into what a typed number clamps to, so the panel
  stops handing the flow a number it already knows will come back.

#### How much a section may say

**A section says at most ONE short line, and only when it earns it.** Settled
2026-09-14 by the decision "How much should the right hand panel explain itself
in words?", answered "One short line, and only when it earns it". Before that,
picking three layers printed seven lines of small grey prose before you reached
a control, in a panel already carrying 1,044 points of sections in an 868 point
viewport. The rule below is what every section is now held to, and what the next
section that wants to explain itself has to obey.

- **A line earns its place only when it says something you CANNOT work out from
  what is already on screen.** That is the whole test. Apply it before writing
  the sentence, not after.
- **Never repeat what the panel already says.** The Layers section prints
  "3 layers selected" whenever more than one is picked. So no section repeats
  the count, and none promises that a change reaches everything picked: that is
  what picking several things means, in this app and in every other one.
- **Never describe a control.** What a slider, a field or a button does belongs
  in its hover tip, where it costs no room and is one pointer away. Keyboard
  stepping, units and ranges belong there too.
- **A limit, a scope that is not the selection, or a control that is missing
  DOES earn a line**, because none of those can be seen. Prefer the section
  HEADER for a scope: a word beside the heading costs no line at all and
  survives the section being collapsed (`sectionAccessory` in
  `InspectorPanel.swift` already does this for Columns and Library).
- **One sentence, one line.** About forty characters at the panel's default
  width. Two facts will not fit, and that is the point: the second one belongs
  in a hover tip.
- **An empty section still says one short line**, because a section with
  nothing in it at all reads as broken.
- **A CONDITION the panel is in is not section prose, and this budget does not
  cap it.** A row speaking for three of five layers, colours that disagree, a
  number kept while its row is hidden: those are readouts of state, said by the
  row they belong to and shown only while that state holds. `row.reachNote`,
  `corners.note`, `unlinkNote`, `legibilityNote` are all this register and all
  stay.
- **Nothing is deleted without a home.** Where a sentence was the ONLY place a
  limit or a scope was written down, it moves to the control's hover tip or to
  the section header before the line goes.

#### The line under a section

One line, one voice, and it was doing three jobs with no shared rule before
2026-09-08. Settled here so the fourth use of it does not invent a fourth
answer.

- **At rest it is the section's CAPTION**: what these controls mean and, where
  it is not obvious, what they reach. `caption`, `shadowReachNote`,
  `borderReachNote`, `ComponentKnobSelection.differentComponentsNote` are all
  this register. How much it may say is the budget directly above; the register
  rules below are about which message wins the line and how long it stays.
- **The caption describes only controls that are actually there.** It promised
  "Up or down arrow steps by 1, Shift by 10" while three of the four numbers
  were plain text and only one of them stepped (audit
  `2026-09-06-a-decided-number-looks-decided`, rough 4). Now it names them: "Up
  or down arrow steps W and H by 1, Shift by 10", and where NOTHING takes a
  number it stops promising a keyboard at all and points at the thing that does
  answer, "These numbers are worked out for you. Click one to see what decides
  it."
- **An ANSWER takes the line when you do something the section has to explain**:
  a click on a number you cannot type, a number the picked things refused. It
  goes one step less quiet than the caption (tertiary becomes secondary) so the
  change is visible without a flash, and it is never a toast.
- **One answer at a time, and the newest wins.** There is no queue. A queue of
  sentences under a panel is not a thing anybody reads.
- **Six seconds, then the caption comes back**, and sooner if what it explained
  is gone: a different selection clears it at once, and so does the rule itself
  being taken off.
- **An answer is never HELD as a sentence.** What is kept is what you DID, and
  the words are worked out afresh every draw. Hold the string and it outlives
  its rule for the rest of its six seconds, which is exactly the bug the same
  audit recorded.
- **Silence is the answer to a number that landed.** Nothing is said when the
  picked things took what was typed. The line does not congratulate anybody.

*(`GeometryInspector.Answer` is the shape of this: two cases, one `@State`, one
`.task(id:)` that fades it. `LayerGeometrySelection.refusal(asking:for:landedOn:)`
and `.explanation(for:)` are the two sentences, both worked out live.)*

#### What a switch does, since a Mac switch has no third position

A checkbox has a mixed state; a switch has on and off and nothing else. That is
the one control the look rule cannot simply be dropped into, so it is decided
here rather than in the middle of whatever feature meets it next.

- **It stays a switch.** It does not become a checkbox when you pick a second
  layer, per the rule above.
- **The word goes beside the switch's own caption**, `Enable Shadow  Mixed`, the
  same place a segmented row of pictures puts it, and for the same reason: there
  is no room for a word inside the control, and out at the trailing edge the
  word lands against the next column's caption.
- **The switch itself must not read as a state anyone chose.** Off is a true
  answer, the one that means none of them have it, so a disagreeing selection
  may not borrow it. While it has no position the switch wears the same one step
  quieter that `MixedLook.style` gives every other Mixed.
- **The first press resolves to on**, for every picked layer, in one undo step,
  the way a mixed checkbox has always behaved on this platform. The press after
  that turns them all off. It never returns to Mixed: Mixed is a report about
  the selection, not a state you can set.
- **The reach line underneath stays.** It answers a different question, how many
  the rows below reach, and the switch saying Mixed does not say that.

*(Shipped 2026-09-06, `a-switch-says-mixed-the-way-every-other-control`,
audit `2026-09-06-switch-says-mixed`. The reading is
`LayerStyleSelection.shadowIsMixed` for the Shadow section's own switch and
`LayerPartRow.isMixed` for the parts list, so what a switch SAYS and what it
DOES cannot drift. The walk that keeps it true is
`Scripts/playtest/switch-says-mixed-walk.json`.*

*Two things the rule did not anticipate, both settled the same way. The switch
in the parts list is a CHECKBOX rather than a switch, and a Mac checkbox does
have a third position, the dash; it is not used, because SwiftUI only draws it
for a Toggle built from one binding per layer, and that would split "give the
other two a shadow" into one undo step per layer. So a checkbox over layers that
disagree says it the way everything else does: the word beside it, the control
one step quieter. And a part in that list is switched on and off from a row
rather than from a section, so the word goes where the row shows its value,
which is where its colour says Mixed too, and the sentence underneath is what
says which of the two the word is about.)*

**Built, and the thing to copy:** `InstanceShowKnob` in `ComponentPanel.swift`
(2026-09-05), the show-or-hide knob over several copies. It wears
`MixedLook.controlOpacity`, which is the one step quieter for a control made of
picture rather than words, and the word sits beside the switch. The Shadow
switch wears the same two as of 2026-09-06, and so does every switch in the
parts list: `ShadowInspector` in `LayerEffectsInspector.swift` and `PartRowView` in
`PartsInspector.swift`.

**The word goes AFTER the control, not between it and its caption.** Both were
built and looked at: putting it in the middle moves the switch sideways the
moment a second layer is picked, which is the one thing this rule has been
saying not to do everywhere else. After it, nothing on the row moves for a
selection that agrees.

### A control that cannot act

Six fixes landed on 2026-09-04 that were all the same shape: the app offered
something that could not do anything, and each one was answered a different way.
Take it away, dim it, replace it with words, leave it and explain. This is the
one rule, written so the seventh does not have to invent it.

**Ask these in order. The first answer that applies wins.**

**0. Could it be made to work instead?** A control is not inert because of a law
of nature; usually it is inert because nobody finished it. Stretch on a text
layer did nothing for months and the tempting fix was to hide it. The fix that
shipped was to make Stretch fill the height, and it is the best of the six. Ask
this first, every time, and only go down the ladder once the answer is a real
constraint you can name in a sentence.

**0b. Does it really not act, or does it act over less than you expected?** A
slider with a floor under it works; it just never goes below the floor. Every
row of the table below is about a control that cannot act AT ALL, so putting a
clamped one through it produces a wrong answer with confidence: dim a control
that works, or take away one doing real work. Sort it out here, against **A
control that can only act over part of its range** below, before you read on.

**Then answer by what kind of control it is**, because that, not the feature, is
what decides:

| Kind of control | What it is | The answer |
| --- | --- | --- |
| **A command** | a verb with something to act on: a button, a menu item, a toolbar item | **Stays in place, dimmed.** Never hidden. A command that disappears takes the map with it, and you cannot learn an app whose menus change shape. This is what the app already does in about a hundred places, and it is the platform convention. |
| **A chooser whose value is decided elsewhere** | a menu, a segmented row, a toggle, where something above has already answered the question | **Replaced by the answer, in the same row.** Show the value in plain words and name who owns it. Keep the row in its place and its column so the section still reads as a set of settings. |
| **A field that still has a number to report** | a width, a height, a position the layer really has, that you cannot type | **Keeps the number, read only.** A number you can read is worth more than an empty box, even when it is not yours to set. It must not look like something the keyboard will accept. A field with nothing true to report is the one that stays blank: a line or a caliper has no width of its own, so a number there would be about nothing you drew. |
| **A bare affordance** | a resize handle, a rotate knob, a drag target: something with no label, grabbed rather than read | **Removed.** There is nowhere on a handle to say why it refuses, and a handle you can see but not drag teaches the wrong thing about the state that froze it. Take it away and make sure the state itself is visible somewhere with words, such as the padlock on the layer's row. Only the grabs go: the frame that says what is selected stays, because that answers a different question. |
| **A control with a range that something else clamps** | a slider or a stepper that works, but not across all of it: a floor under it, a ceiling over it, or nothing left to give | **Stays, and the stretch of range that is not yours is drawn spent.** The fill measures what you added past the wall, so a knob resting on the wall reads as a knob against a wall rather than a knob at nothing. Never dimmed, because it works, and never removed, because it does real work. Full rules in "A control that can only act over part of its range" below. |
| **A key press** | a shortcut with nothing on screen to dim: ⌥⌫, an arrow key, ⌘X aimed at a marquee | **Either the canvas notice says so, or something already on screen does and the key stays quiet.** Which one it is has a test, below, and it is not a judgment call. A key cannot be dimmed, so the answer that works for a button is not available to it, and a key that changes nothing and says nothing reads as an app that has stopped listening. |

#### What a number you cannot type looks like

Settled 2026-09-05 by the decision above, after both looks were built and
photographed side by side. This is the field row of the table above, drawn.

- **No box.** The rounded bezel is the panel's promise that the keyboard lands
  there, so a number you cannot type does not wear one. It is plain text in the
  same place: same letter in front, same column, same right edge, same 21pt row
  height as the field beside it, so nothing shifts when a layer is locked.
- **Quiet, but readable.** Secondary strength, monospaced digits, so a locked
  layer reads as a plain statement of where it sits rather than four boxes that
  refuse the keyboard.
- **A dash when there is no number.** An arrow has no width, so its W and H show
  a short dash (an en dash, `U+2013`) rather than nothing. A readout has no box
  left to hold the place, and a lone letter with a gap after it reads as a row
  that failed to draw.
- **Never a placeholder.** A field's grey placeholder is a promise that typing
  that thing here would work. On a readout it is a lie, and it puts the letter
  on the row twice.
- **Clicking it answers.** The whole slot is the control, including the empty
  space beside a dash, and pressing it puts the reason in the line under the
  section straight away. Never a hover tip alone.
- **Never in the tab order.** Tab moves between the numbers you can type.

Built as `GeometryReadout` in `Sources/Photonz/GeometryInspector.swift`, with the
words and the spelling in `LayerGeometrySelection` (`readoutText`, `blankText`)
so the panel cannot drift from what is tested.

**Drawing one in a mock: `.reading`**, in `shared/components/input.css`, added
2026-09-07. It is `.stepper`'s geometry with the bezel turned transparent, so a
readout is exactly as tall and as wide as the field beside it and its last digit
lands in the same column. Leave `.v` empty and the en dash appears; the class
supplies it so no page spells it with a hyphen.

```html
<span class="reading sm"><span class="k">W</span><span class="v">204</span></span>
<span class="reading sm"><span class="k">H</span><span class="v"></span></span>          <!-- no number -->
<button class="reading sm" tabindex="-1">…</button>                     <!-- when the page can answer the click -->
```

`.val` in `app-patterns.css` is NOT this: it is bare ink for a stray number in
prose or a status strip, with no letter, no column and no slot, so four of them
do not line up with four fields. And `.stepper.disabled` is not this either: a
disabled field is one that will take the keyboard again once you fix what is in
the way. Dimming a field to say a number is never yours is the look that was
rejected. Specimen and rules: `pages/comp-fields.html`, block **03**.

**Which numbers these are is one question, asked once.** The look above was
settled for a paragraph's height and then applied a case at a time, so three
audits in one cycle reported the same wart in three rooms: a piece stretched
across a column stack, a title spanning a nav bar and the surface behind a
button all went on offering a box, took the number, and had the flow put its
own answer back a moment later. Fixed 2026-09-06
(`a-stretched-piece-stops-offering-a-size-you-cann`, audit
`2026-09-06-a-decided-number-looks-decided`). The question now lives in one
place, `Layer.sizeIsDecidedByItsContainer`, and it has three answers that are
one sentence said three ways: the piece is painted to the container's own
edges, it is taking the room the flow has left over, or it is stretched across
an axis the flow hands out. A container with no arrangement at all decides
nothing, so a Stretch there is a rule about the next resize and its number
stays typeable.

The sentence a click puts under the fields is worked out afresh every draw
rather than held. Take a rule off and the answer that explained it goes at
once, instead of outliving it for the rest of its six seconds.

**A corollary, for things that are not controls.** A count or a list that
reports state ("1 layer has a rule of its own") reports only what has an effect.
A rule that changes nothing is not an exception and is not counted. The place a
dead rule shows is on the layer that carries it, with a way to clear it.

#### The wording, so two places do not invent two sentences

Every reason is **one sentence in two halves: who owns this now, and the one
thing to do about it.** Never "Not available", never "This control is disabled",
never a bare "cannot".

- "This layer is locked. Unlock it in the Layers list to change its position or size."
- "Height follows the text. Change the width to re-wrap it, or the font size in the Text section."
- "A copy is the size of the original. Resize the original component and every copy follows."
- "The stack this is in lays its contents out top to bottom, so it decides where each one sits down the page. Change the group's Gap or Direction in the Layout section."

Name the owner with the noun the user already sees on screen: *the stack*, *the
row*, *the Layers list*, *the Layout section*, *the original*. A replaced
chooser is labelled **`Set by <owner>`** ("Set by the stack", "Set by the row"),
using the same noun its sentence uses.

**Write the sentence once, in `PhotonzCore`, next to the state that causes it**,
and have every place that says it read that constant:
`LayerGeometryEditing.lockedReason`, `.textHeightReason`, `.stackedReason`,
`.instanceSizeReason`, `PlacementEditing.stackReason` / `.rowReason` /
`.stackTitle` / `.rowTitle`. The caption under a section and the tip on a
control saying the identical words is the point, not duplication. This is the
mechanical half of the rule: if the sentence lives in one place, two surfaces
cannot drift.

#### Where the explanation goes (hover is never the only place)

**The "who owns this" half is always on screen. Only the "what to do" half may
live in a tip.** Three of the six left a reason living only on hover and all three
audits flagged it: a tip that needs a 400ms hover on a control you have already
decided is broken is a reason nobody reads.

- **One state that takes a whole section at once** (a lock takes all four
  numbers): one line under that section, always visible. Not a tip per field.
- **One dead control among live siblings**: the control's own appearance carries
  the first half, and the tip carries the rest.
- **A chooser replaced by its answer**: the words in the row are the first half,
  already on screen, and the tip adds what to do.

#### A control that can only act over part of its range

Written 2026-09-14 after four surfaces met the same wall in a week and each
answered it its own way. Evidence: audit `2026-09-12-corner-over-a-group`, its
last two rough notes, and audit `2026-09-14-icon-stroke-weight`, its fourth.

The ladder above answers a control that **cannot act**. None of its rows fit a
control that acts perfectly well and simply does not reach everywhere, which is
what Corner Radius over a group rounded 18 is: it works, from the first nudge,
just never below 18. Dimming it is a lie, because it works. Replacing it with
its answer throws away a control doing real work. Taking it away is worse, and
that is not a guess: the group audit's own third rough note records trying
exactly that and calls it the mistake, because "hiding the row would have taken
away a working control". So this is its own row, not a rung of that ladder.

**Sort it first. Three things look alike and only one of them is this.**

| What you are looking at | The tell | The answer |
| --- | --- | --- |
| **Nothing to act on** | there is no true number to report at any value. A caliper has no corners, the way an arrow has no width | **No row at all.** This is the ladder's field row, already decided. Never a slider pinned at nought standing in for a property the layer does not have |
| **A range wider than the subject uses** | nothing is stopping you. Every value is reachable and does what it says, and most of them are merely silly here: Border Width running 0 to 20 on a 24 pixel icon | **Not this rule.** Nothing is refused, so nothing is drawn spent. Measure the travel before you call it a problem (below) |
| **A range something else has clamped** | there is a wall, you can name in one sentence what put it there, and the values behind it are refused: Corner Radius over a group whose contents are rounded 18 | **This rule.** Keep the control and draw the wall |

**Draw the wall. Three rules, and they hold for a floor, a ceiling, or both.**

- **The refused stretch of track is drawn spent**, from that end of the track to
  the wall: the groove one shade down, no fill in it, a hairline at the wall,
  and no thumb travel into it. It reads as range that exists and is not yours,
  which is the true thing, and it is on screen the whole time with nothing
  hovered. That is the acceptance this row exists to meet.
- **The fill starts at the wall, not at the end of the track.** The fill
  measures what YOU added past what was already there. A knob resting on a floor
  of 18 therefore shows no fill at all, which is exactly right: you have added
  nothing yet. This is the fix for the thing the audit named, that "the knob at
  the far left reading 18 looks exactly like the old knob at the far left
  reading 0". It no longer does. The old one had a live empty track in front of
  it; this one has a spent one.
- **A range clamped to nothing is the whole track spent**, thumb at the wall,
  and the thumb stops taking the pointer while the row still answers a click. A
  pill has nothing left to round. Silently switching the slider off was the
  fourth rough note, because a switched-off slider looks the same as one you
  have not grabbed yet. A wholly spent groove does not. **Do not dim the row
  instead:** dimming says broken or waiting, and this one has simply been spent.

**The number beside it keeps its box.** A clamped slider's field still takes the
keyboard, because typing a number and watching it settle to the wall is how a
person learns where the wall is. Type 5 against a floor of 18 and it lands on 18
and says why, in the line under the section, the ANSWER register in **The line
under a section** above. Settling in silence is the one thing it must not do.

**The words.** The wall on the track is the "who owns this" half, on screen with
no pointer on it, which is exactly the allowance **Where the explanation goes**
already makes for one control among live siblings. The rest is the ordinary §4
sentence, who owns this and the one thing to do, and it arrives two ways:

- **Clicking the row answers**, in the line under the section. The whole row is
  the target, spent track included, the way the whole slot of a number you
  cannot type is. Never a hover tip alone.
- **The hover tip carries the same sentence**, from the same constant, for
  somebody whose pointer is already resting there.

*("What is inside this is already rounded 18 px. Round the contents less to take
it lower." Owner named with the noun on screen, one thing to do, one constant in
PhotonzCore, per **The wording** above.)*

**Drawing the wall is what buys back the section's line.** The budget in **How
much a section may say** grants a line to a limit, "because none of those can be
seen". Once the wall is on the track it CAN be seen, so a clamped control does
not also get a permanent caption saying it. Draw the wall or write the line,
never both, and prefer the wall: it survives the section being scrolled past and
costs no height.

**When the range is merely too wide, fix the range, never the chrome.** Measure
it on the real window before calling it anything: what decides it is how much
travel one meaningful step costs. The icon border case was measured at about 205
points of track for 0 to 20, so one whole point of width is about 10 points of
travel, which is a comfortable target, and the honest answer there is to leave
it alone. Only when a meaningful step is too small to hit does the range itself
scale to the subject, and it does that quietly: no spent track, no sentence,
because nothing is being refused.

**Drawing one in a mock: `.slider.clamped`**, in `shared/components/slider.css`,
added 2026-09-14. `--p0` is where the wall sits, on the same 0 to 1 scale `--p`
already uses; the spent stretch and the start of the fill both come off that one
number so they cannot disagree. Add `.spent` when the wall is the whole range.
Specimen and rules: `pages/comp-sliders.html`, block **05**.

```html
<span class="slider clamped" style="--p0:.28;--p:.28">…</span>          <!-- floor, nothing added yet -->
<span class="slider clamped" style="--p0:.28;--p:.62">…</span>          <!-- floor, pulled past it -->
<span class="slider clamped spent" style="--p0:1;--p:1">…</span>        <!-- nothing left to give -->
```

**The four cases it was taken from, answered.**

| The case | Which row | What it gets |
| --- | --- | --- |
| Corner Radius over a group whose contents are rounded 18 | clamped | track spent from 0 to 18, fill starting at 18, click or hover saying what is inside is already rounded 18 px |
| Corner Radius on a pill, nothing left to round | clamped to nothing | the whole track spent, thumb at the wall, row still answers a click. Not dimmed, and never mistakable for untouched |
| Corner Radius on a measurement, no corners at all | nothing to act on | no row. The ladder's field row settled this already: a caliper has no radius the way an arrow has no width |
| Border Width 0 to 20 on a 24 pixel icon frame | range wider than the subject uses | nothing. Nothing refuses you, and one point of width costs about 10 points of travel, which is a fine target. Left alone on purpose, and that is the rule's answer rather than an omission |

**Built in the app on 2026-09-16**, first two cases, by
`a-slider-says-where-its-track-starts-when-someth`
(`Sources/Photonz/AnnotationInspector.swift`, `CornerRadiusRow`). The third,
a measurement with no corners at all, is still open in
`a-measurement-offers-a-corner-radius-it-has-noth`.

Two things the app had to settle that the mock did not:

- **The wall is DRAWN, not just implied by two tones.** The mock leans on the
  accent either side of the keyline to carry the difference. A macOS panel
  cannot: with a grey accent picked in System Settings the filled stretch is
  grey too, and measured off the real window the spent stretch (106), the
  filled stretch (135) and the empty groove (79) sit close enough that tone
  alone is thin. So the keyline is a one point mark standing a little proud of
  the bar, which also puts an end stop beside a knob resting against it.
- **No custom slider was needed.** A small `NSSlider` puts its bar across its
  whole frame and its knob's LEFT EDGE at the value's fraction of the leftover
  width, so a live slider inset by the spent width starts its own fill exactly
  at the wall, for free. Only the spent stretch is drawn.

Since the rule was written, one of the two cases it was taken from has narrowed:
a plain group now hands the row to what is inside it
(`ContainerRounding.swift`, 2026-09-15), so it has no wall at all and starts at
nought. A wall is now what a container that really does mask has — a frame, a
copy of a component, or a group somebody masked by hand.

#### What a key press says when it cannot act

Written 2026-09-08 from what three keys shipped in two days, not invented. ⌘X,
⌫ and ⌥⌫ each met the same wall, a marquee over a rectangle, and each answered
it on its own before the third one made the pattern plain (`c6c8b74e`,
`14e2372f`, `23f14863`; audits `2026-09-08-cut-says-what-it-cannot-do`,
`2026-09-08-delete-over-a-marquee`, `2026-09-08-fill-over-a-marquee`,
`2026-09-08-notice-carries-the-way-out`). The words and the yes/no live in
`RegionSliceRefusal` (PhotonzCore).

**A key is not a control, and that is the whole difficulty.** Every other row
of the table above answers by changing how something looks: dim it, replace it,
take it away. A key press has nothing on screen to change. It has already
happened by the time anybody could have been warned, and the only thing a person
sees is whether the picture moved.

**The test: what refused, the command or the aim?**

1. **The whole command cannot act.** There is nothing to act on, or the thing
   picked is not the kind this command takes. Then the command's own row in the
   menu is dimmed, per the first row of the table, and the key inherits that
   answer: it stays quiet and lets macOS beep. The reason is already on screen,
   in a menu a person can open, and repeating it on the canvas every time a
   thumb brushes a key would be noise. Nudging a locked layer is this case: the
   layer's own row says it is locked, and Position and Size says so in words
   the moment you ask for it.
2. **The command can act, and it is what this press was AIMED at that it cannot
   honour.** Cut works. Cut with a marquee over a shape does not, because a
   marquee takes a piece out of pixels and a rectangle is a description of a
   drawing. Nothing is dimmed, because at the command level nothing is wrong,
   and nothing on screen changed. **This is the case that must speak**, and it
   is the one every silent key in this family turned out to be.

The tell for case 2 is that the aim is something the person made a moment ago
and can see: a marquee, a region, a part they picked. They are looking straight
at it. Silence there does not read as a refusal, it reads as a key that missed.

**Where it says it, and for how long.** The canvas notice (§3), bottom centre,
the same pill the Copied confirmation uses. Never a dialog: a refusal is not
worth a click to dismiss. Never a beep alone. Never only in the menu, since the
person is on the canvas with a key under their finger. Three seconds when it is
words only, six when it carries a button, and the pointer resting on it stops
its clock (§3).

**The sentence, in two parts.** The verdict first, in its own weight, saying
what the key you just pressed did not do: "Cannot delete a piece", "Cannot fill
a piece". Then the ordinary §4 sentence, who owns this and the one thing to do.
The verdict is what a key press adds to the wording rule above, and it is there
because the person does not yet know which of the things they just did was the
problem.

**Naming the way out is required, and it is the difference between a refusal
that helps and one that dead-ends.** This is not a style preference; it was
learned. The first refusal shipped saying only "Only a picture can have a piece
taken out", which is true and leaves somebody holding a marquee over a rectangle
with nowhere to go. Its own audit said so, a follow-up added the way out
(`3c59faa6`), and a second added it as a button inside the pill
(`23f14863`).

- **Name the way out that gets them what they asked for**, when one exists.
  "Turn it into a picture from the Layer menu, then try again" leads to the
  piece coming out. "Clear the marquee to delete the whole layer" is the
  fallback, and it deletes something bigger than they aimed at.
- **When the app already knows the single command that would let it through,
  the pill carries it as a button** (§3, the one exception to a notice taking
  no input), and then the sentence stops pointing at the menu, because the
  button is the answer.
- **When there is genuinely no way out**, say what the layer is instead, and
  point at the coarser thing that does work: a measurement can never become a
  picture, so its refusal names clearing the marquee and nothing else.

**One family, one sentence, one place.** Three keys asking the same question of
the same layer must get the same answer, differing only by the verb: "a piece
taken out" for ⌘X and ⌫, "a piece filled in" for ⌥⌫, because ⌥⌫ puts colour in
rather than taking anything out. Write it once in PhotonzCore next to the state
that causes it, the way the wording rule above requires, and have the yes/no
come from the same predicate the command itself uses
(`RegionTarget.canSlice`), so the sentence on screen can never disagree with
what the key actually does. A key that works says nothing at all: deleting a
corner out of a real picture is silent, and should be.

**A key with no menu row of its own is the one to watch.** An arrow nudge has no
row anywhere, so case 1's dimmed row does not exist for it and the state that
froze it must be visible in words somewhere else on screen. If it is not, the
key has to speak.

#### The six from 2026-09-04, scored against this

**The example to copy is "Set by the stack"** (`2026-09-04-stack-owns-axis`): a
dead chooser replaced by its answer, in place, owner named on screen in the
user's own nouns, sentence and label both from one constant.

| The fix | What could not act | What was done | Verdict |
| --- | --- | --- | --- |
| `2026-09-04-text-fills-height` | Stretch on a text layer | made to actually fill the height | rung 0, and the reason rung 0 is first |
| `2026-09-04-stack-owns-axis` | the axis menu a stack has already decided | replaced by "Set by the stack" plus a tip | chooser. **The exemplar.** |
| `2026-09-04-locked-caption` | X, Y, W and H on a locked layer | numbers stay, one line under the section says locked and how to unlock | field, and the exemplar for a state that takes a whole section at once. |
| `2026-09-04-locked-layer-handles` | eight resize handles and a rotate knob on a locked layer | removed | bare affordance |
| `2026-09-04-inert-placement-rule` | a placement rule on the axis the stack owns | stopped being counted as an exception, Clear offered on the layer itself | the corollary |
| `2026-09-04-text-height-readout` | the H field for text | shows the height as plain text with no box, and clicking it says why | field. **Closed 2026-09-05**, and now the pattern the row above describes. |

That row was the one exception for a day. It is closed. A text layer's H keeps
its number, which was always right, and it has stopped wearing the rounded box
of a field you can type in, which its own audit called the clumsiest part of the
feature.

Both halves shipped. Clicking a number you cannot type answers in the line under
the fields, so no reason lives on hover alone. And the box is gone: the two
looks were built side by side, photographed, and put to the user as
`a-number-you-cannot-type-into-stops-looking-like-a-number-the-app-worked-out-for`,
who chose the plain number on 2026-09-05. The switch that held it back is
retired rather than left sitting there turned on, so there is one look now.
Copy it: the rules are in **What a number you cannot type looks like** above.

---

## 5. Layers representation: flat vs grouped (be consistent)

- Layers panel is a single tree. **Flat list** when the doc is flat; **groups**
  (`.lgroup`) when structure exists (a component is a group; a frame with children
  is a group). Do not show a flat list on one page and an arbitrarily grouped one
  on another for the same kind of content.
- A **component instance** renders in Layers as a single row with the component
  glyph, and that row does **not** twist open. What is inside a copy belongs to
  its original, so a row you could open would show pieces nobody can keep an edit
  to. The knobs a copy does have, its exposed properties, its own look, Edit
  Original and Detach, live in the Component section of the dock beside the
  copy's name, not in the layers tree. *(Revised 2026-09-04 to match what
  shipped: commit `fcdb672` makes the row non-openable, and audit
  `2026-09-03-component-overrides` records cutting the mock's separate instance
  props section for the same reason. This rule previously promised a row
  expandable to show overrides.)*
- Visibility (eye), lock, and reorder affordances are identical on every row.

---

## 6. Tools: where they live, how they change context

- The **tool strip** is the left cluster of the **floating bottom tool bar**
  (`.cnv > .tbar > .tstrip`), followed by a separator, the foreground/background
  swatch pair, and zoom. Same order across workspaces where a tool exists
  (Select/Move first; then create tools; then measure/crop; view tools last).
  Tools marked `.ovf` fold into the `.tbar-more` menu when the window is narrow;
  they are never re-slotted or dropped.
- Selecting a tool: (a) highlights it (`.tool.on`), (b) changes the canvas cursor
  / interaction, (c) swaps what the tool settings capsule above the bar, and the
  top of the inspector, are showing.
- A page that shows "drawing vectors" must show the Pen selected in the strip and
  its options, so the user understands they entered a mode, not a new app.
- The **canonical per-app tool inventory** (ordered) is fixed in §10 decision D4.
  Shared tools (Select, Hand, Zoom, Text, Shape, Measure) keep the same glyph and
  slot in every app; app-specific tools slot between the create cluster and the
  view cluster. Never reorder or re-glyph a shared tool per page.

---

## 7. Menu / command system (the API made browsable)

- Every command maps to one API call (`run("tool.text")`, `panel.dock("right")`,
  `layer.group()`). There are FOUR ways to reach the same call, all equal: the
  toolbar/tool strip, a right-click context menu, the **command surface** (D3),
  and the **agent chat** (D6 revised) — reached by the Ask button or ⌘K, where a
  `/` command and a plain-language request issue the same call. An agent drives
  the identical calls.
- In the mock shell we express the menu as a **compact command surface** in the
  toolbar (a menu/command button) plus the **Ask launcher** (`.askbtn`), NOT a
  faked full macOS menu bar (see D3). The shipping app additionally has the native
  menu bar; the mock does not render it. Keep the command surface + Ask present on
  every editor page so the "UI == API == agent" story is always visible.

---

## 8. Iconography: ONE library, one style (no exceptions)

The single biggest consistency smell was mixed icon styles and ascii/emoji
glyphs. Rules:

- One monochrome line-icon library on one grid: 24x24 viewBox, 20x20 live area,
  square keyline 18x18, circle keyline d17.2, 1.75 stroke, round caps/joins,
  `currentColor`, no fills except where the glyph is intrinsically solid.
  Authored in `shared/icons.mjs`, generated into `photonz-ds.css` as `.ic-*` by
  `node shared/build-icons.mjs`, and documented on `pages/iconography.html`
  (searchable, click to copy).
- Use `<i class="ic ic-NAME"></i>` everywhere. NEVER ascii/unicode symbols
  (◄ ▭ ✎ ◈ ⌗ ▾ ◉ ◆ ✦ → ← etc.) as icons, NEVER emoji, NEVER a second icon style.
- One concept = one icon, app-wide (e.g. component is always `ic-component`; add
  is always `ic-plus`). Maintain the concept->icon mapping in AGENTS.md.
- If a glyph is missing, ADD it to `shared/icons.mjs` and regenerate, rather
  than substituting a near-miss or an ascii symbol. Keep the new glyph in the
  same grammar and drawn to a keyline. Never hand-edit the generated CSS block.
- Sizes come from `.ic.xs` 12 / `.ic.sm` 14 / `.ic` 16 / `.ic.lg` 20 /
  `.ic.xl` 24, never ad-hoc px.

Done: the set was redrawn to one grid and one weight (199 glyphs in 12 groups,
plus aliases for the older names). Remaining action item: keep auditing pages
for conformance (see the audit agent). The icon set must look drawn by one hand.

---

## 9. Per-page consistency checklist (audit gates)

Every editor/scenario page must satisfy:

- [ ] Sits in the one shell: title bar, canvas-dominant `.edit.lean` row, the
      floating tool bar, the right dock of panel groups.
- [ ] Answers "how did I get here": the active tool/mode is visible; the surface
      shown (Library/media pool/tool) is a panel group or an overlay, reachable
      via a visible affordance, not teleported in.
- [ ] Library/media/catalog is the Library group in the right dock (or the same
      content as an overlay), with an add/import affordance.
- [ ] Selection drives the Properties group; selection shown consistently on
      canvas + in Layers. If the copy says something is selected, the canvas
      draws the frame — declared with `data-sel-frame`, never hand-written.
- [ ] **Responsive**: the `.win` carries `.cq`, and the page renders sensibly
      narrowed (dock rails or overlays, tool bar overflows).
- [ ] **Bounded panels** (§3, the height rule, which binds the app too): every
      long list is bounded and scrolls inside its own group, forms are drawn
      whole, and no list stretches the window. When the whole thing still does
      not fit, the dock scrolls; no section is cut down to make it fit.
- [ ] Layers use flat-vs-group consistently; rows have identical affordances.
- [ ] Every glyph is an `.ic-*` from the one library; zero ascii/emoji/mixed
      styles.
- [ ] Controls are canonical `.btn`/`.seg`/etc. with real states.
- [ ] **Transport bar holds time controls only** (D8): nothing but volume,
      skip, play/pause, loop, the two timecodes and the scrubber shares that row.
- [ ] **Every animatable property shows how to animate it** (D10): property
      rows list the whole catalogue, not only the keyed ones.
- [ ] **Every dock can be pushed away** (D9): from a control on the dock
      itself, with a visible way back the whole time it is away, and it comes
      back to the size it had. A bottom dock collapsed to a row names what is
      still selected.
- [ ] **Guides draw over the work** (D16): a grid, a screen's columns or a
      pinned guide sits above the artwork as a wash or hairline you can read
      straight through, never behind it, and never inside whatever the page
      presents as the exported picture.
- [ ] **Nothing inert without an answer** (§4): every control that cannot act
      is dimmed, replaced by its answer, or gone per its kind, and the "who owns
      this" half of its reason is on screen rather than only on hover.
- [ ] **A clamped range shows its wall** (§4): a slider or stepper that works
      over only part of its range draws the refused stretch of track as spent,
      starts its fill at the wall, and is neither dimmed nor removed. A range
      spent to nothing reads as spent, never as a slider nobody has touched. A
      control with nothing to act on has no row at all, and a range that is
      merely wider than the subject uses draws no wall, because nothing refuses
      you.
- [ ] **No key press refuses in silence** (§4): a key that cannot do what it was
      aimed at, while the command behind it is perfectly able to act, says so on
      the canvas notice, verdict first, and names the way out. A key whose whole
      command is dimmed may stay quiet.
- [ ] **A question earns the right to ask** (§3): a command only stops and asks
      when what it takes away is invisible the instant after; it is worded gain,
      cost, way back, with the verb on the button; and it may only carry "Don't
      ask again" when the answer is nearly always yes and undo can put the cost
      back.
- [ ] Copy: plain, no em dashes, "agent" not "Claude".

---

## 10. Resolved decisions (baked in — build to these)

These were the review open questions. They are now DECIDED. Every page, the app
shell, and the audit agent conform to these. If a decision must change, change it
here first, then propagate.

### D1 — Media pool is the Library panel group, scope = Media

> **Amended (PRODUCT-MODEL §4b).** The Library no longer lives in a **left** dock.
> There is exactly ONE dock, on the right, and Library is a **panel group**
> (`.dgrp`) inside it, alongside Layers, Properties, and Effects. The scope switch
> and every rule below are unchanged; only its home moved. When Library needs room
> to browse, show the same content as a `.sheet.down` overlay rather than widening
> the dock.

The "media pool" is not its own surface. It is the **Library** group in the right
dock with its scope switch set to **Media**. Locked rules for every video/media
page:

- **Open path:** the canvas **panel toggle**, the **Library rail tab**, `⌥⌘L`,
  `Window > Library` in the menu model, or Ask (⌘K) `→ "/library"`. It is a persistent
  group in the dock, so the normal state is "already there".
- **Add media (three ways, always all present):** the panel's **+ Import** button
  (file picker), **drag-drop** a file onto the panel or the canvas, and **Capture**
  (screenshot/recording from the menu-bar agent) which lands new media here.
- **Contents:** clips, images, audio, each a thumbnail tile with duration/size
  meta; drag a tile to the timeline or canvas to use it. Selecting a tile shows
  its properties in the **Properties group**, same selection model as §4.
- No video page renders a bespoke "media bin" widget outside this group.

### D2 — One Library surface with an internal scope switch (not N panels)

> **Amended (PRODUCT-MODEL §4b).** Read "the left dock has two top-level tabs" as
> "the right dock has stacked panel groups". Layers and Library are two of those
> groups, not two tabs. Everything else stands.

Component catalog, style library, media pool, and the design system are the SAME
surface. Inside the Library group, a **segmented scope switch** picks the content
family: **Media · Components · Styles · Systems**. Rationale: they are all
"reusable content you browse and drag onto the canvas"; one location + one scope
switch beats four competing panels and keeps the mental model flat. Each scope has
the same shape (search, grid of tiles, + affordance, right-click "Add to
Library"). Selecting any tile drives the Properties group. Do NOT promote a scope
to its own dock or window.

**Systems** is the fourth scope (decision, 2026-08-23: it replaced the older
Assets scope). It holds the document's named design system — draft or published —
and later a catalog of systems you can browse and apply (see ds-build-wt for the
system card and publish flow, dsys for the catalog overlay). It completes the
ladder the product teaches: tokens → styles → components → system. Flat reusable
files (clip art, icon sets, logo marks) live under **Media**; there is no generic
Assets drawer.

Brush-driven surfaces (draw, the brush library and editor, brushed vector
strokes) show **Brushes** in the row where Components sits: PRODUCT-MODEL
"Vector strokes are brushes" defines picking a brush from the Library with
scope = Brushes, and those scenarios have no component story. That is the one
sanctioned swap; a page must not invent any other scope name.

### D3 — No fake menu bar. Compact command surface + Ask (still holds)

> **Enforced (2026-07-26).** The title bar, the Ask launcher and the `…` command
> surface button are now BUILT by the shell component in `photonz-ds.js` from
> `data-shell` / `data-ws` / `data-status` on the `.win`. Pages had each retyped
> that chrome and drifted: Share/Export/Done in the header, a `.toolbar` command
> strip `app-shell.html` had already deleted, 56 copies of the `.cmdk` well. The
> component deletes any `.titlebar`/`.toolbar` found inside `[data-shell]`, so it
> cannot drift again. A page authors its own `.cmdpop` menu ITEMS (content); the
> button that opens them is chrome. See AGENTS.md, "The shell is a COMPONENT".

The **shipping app's real command surface is the native macOS menu bar** (File,
Edit, Select, Layer, Type, Effect, View, Window, Help), and that is the primary
story. But the mock `.win` frames live inside an iframe shell, so drawing a full
menu bar would read as fake chrome. Decision, unchanged in substance: the mock
expresses the command system as a **compact command surface** (a `.tool`
`ic-more` button that opens a grouped `.popover.menu`) plus the **Ask launcher**
(`.askbtn`, D6 revised), and it says in copy that the native menu bar is the real
one. Ask is the **secondary** path, not the headline. No page draws a full
horizontal menu bar, and no page adds a permanent options-bar row of tools: tools
live in the floating bottom tool bar.

### D4 — Canonical tool-strip inventory per app

Ordered left→right in the tool strip. **Shared tools keep the same glyph and the
same relative slot in every app.** Structure is always: `Select → [create/edit
cluster] → [measure/crop] → Hand → Zoom`.

- **Shared (identical glyph + slot wherever present):** Select (`ic-cursor`),
  Hand (`ic-hand`), Zoom (`ic-zoom`), Text (`ic-text`), Shape (`ic-square` /
  `ic-circle`), Measure (`ic-ruler`).
- **UI design:** Select · Frame (`ic-frame`) · Component-insert (`ic-component`) ·
  Shape · Pen (`ic-pen`) · Text · Measure · Hand · Zoom.
- **Image:** Select (marquee/lasso/wand `ic-lasso`/`ic-wand` as a select subgroup)
  · Crop (`ic-crop`) · Brush (`ic-brush`) · Eraser (`ic-eraser`) · Heal
  (`ic-heal`) · Clone (`ic-clone`) · Pen · Text · Shape · Measure · Hand · Zoom.
- **Video:** Select · Blade/split (`ic-blade`) · Title/Text · Shape · Measure ·
  Hand · Zoom. (The timeline has its own Select/Blade in its local toolbar; they
  mirror the same tools.)
- **Draw:** Select · Pen · Brush · Eraser · Shape · Text · Measure · Hand · Zoom.

App-specific tools slot between the create cluster and the view cluster (Hand/
Zoom). If an app lacks a shared tool (e.g. no Measure), omit it — never re-slot
the ones it has.

### D5 — Walkthroughs embed the REAL shell (may be reduced, never relocated)

Guided-walkthrough steppers teach the real app. The `.win` illustration in each
step must show the **canonical docked surfaces** relevant to that step: tool strip
in the toolbar, Library in the left dock, Inspector in the right dock, timeline at
the bottom for video. A step MAY hide docks irrelevant to what it teaches
(reduced), but MUST NOT relocate a surface, invent a floating panel where a docked
one belongs, or use non-canonical chrome. The stepper frame (`.wsteps`/`.wbar`) is
the only walkthrough-specific UI; everything inside a step is the real shell.

### D6 (revised) — The agent chat IS the command palette. One entry point, not two

> **Revised.** D6 used to adopt a separate ⌘K command palette, shown in the title
> bar as a `.cmdk` search well. That is superseded: the title bar's right slot now
> holds **one launcher** and it opens the **agent chat**.

There is a global fourth entry point alongside the tool strip, context menus, and
the command surface (D3), and it is the **agent chat**. It is reached exactly two
ways, both landing on the same surface:

- **`.askbtn`** — the Ask button in the title bar's right slot. A raised `.btn`
  variant (sparkle glyph + "Ask" + a `⌘K` hint), because it opens a surface. The
  old `.cmdk` was an inset well because you typed into it in place; nothing in the
  title bar is a well any more.
- **`⌘K`** — opens the same overlay and focuses its composer.

What opens is **`.askpal`**: a centred overlay at elevation 2 (glass + blur +
shadow + scrim, per the ladder on `pages/lang-elevation.html`), living inside
`.edit.lean` so it dims the canvas and the dock but leaves the title bar lit. It
does not restate the conversation UI, it **hosts the shared `.chat` component**, so
the overlay and the Agent panel group in the dock are the same conversation in two
places.

**Every window has the launcher, including the ones with no document.** The front
door has no canvas and no dock, so its content row is `.shell-body` rather than
`.edit.lean`; the shell component treats the two the same and puts the title bar
and the overlay on both. A window without a document is still a window you can
ask.

**One field, two modes.** The composer takes plain language ("make the headline
bigger") or, when it starts with `/`, becomes the command palette: a filtered
`.cplist` of `.cpx` rows appears inline above the composer, each showing its real
API name (`image.removeBackground`, `panel.dock`). Same field, same Enter key. A
sentence you ask and a command you run issue the identical call, which is the most
direct on-screen proof of "UI == API == agent" — stronger than the old palette,
because the proof and the agent are now literally the same box.

Pages that demonstrate command-running route it through this surface rather than
inventing a one-off runner. Do NOT add a `.cmdk` to any page; it is deprecated and
survives only until the sweep finishes.

### D7 — One color picker, one trigger, every color slot

Color is picked exactly one way. The **trigger is always a swatch** showing the
current color (`.cpick-btn` in a row, the `.swpair` in the tool bar, a `.gstop` on
a gradient ramp), and what opens is always the **one shared picker**
(`.cpick`, styled in `photonz-ds.css`, driven by `initColorPickers()` in
`photonz-ds.js`). No page authors a second color UI, no slot falls through to the
system color panel, and no slot uses a labelled "Choose..." button instead of a
swatch. The picker is a `.popover` but it is **sticky**: clicks inside it do not
dismiss it, because you operate it rather than pick one item from it.

Its regions, in this order, always: before/after preview + slot name + eyedropper
· **four paint-type thumbnails** · (gradients only) the **aim pad + ramp + selected
stop** · saturation/value field · a centered **HSL / RGB / HEX** switch · **one
slider per channel** · **one swatch row with a scope switch** (shades of this
color / related hues / in this document) · contrast readout and "Save style".

Two rules inside it matter more than the layout:

1. **One control per channel.** The format switch picks which channels you are
   sliding; it is not a second way to see the same ones. So there is no hue
   slider sitting next to an H field. HEX has no channels to slide, so that mode
   keeps the hue and alpha tracks and adds a text field, which is also the paste
   target (it takes hex, `rgb()` or `hsl()`).
2. **Every value is typable where it lives.** Each slider carries its number as
   an editable field on the right, and right-clicking a track focuses it. There
   is no separate numeric-entry row to reach for.

The shades row is the point of the whole control: the most common color edit is
"the same color, a bit darker", and it must cost one click and no numbers.

**A color slot holds a PAINT, not a color.** That is how you get a gradient onto a
fill, a stroke or a text layer, and it is the first control in the popover:
**Solid / Linear / Radial / Angular**, drawn as four thumbnails that each render
the CURRENT stops at the CURRENT angle. You choose between four outcomes, not four
words. Pick a gradient and the aim pad, ramp and selected-stop row appear in
place, seeded from the color you already had; the picker below then edits whichever
stop is selected. A stop is a color slot like any other, so selecting one costs
nothing new to learn: drag a key to move it, click the bare strip to add one.

**Direction is aimed, never typed.** The aim pad is a small square showing the
paint with handles you drag; the angle readout follows the handles rather than
leading them. "135°" is a value a person has to decode, so it is a readout, not
the control.

The pad carries **two handles of one family**: a small dot for the paint's
**origin** and a larger one for its **direction**, with a line between them so
they read as one object. Both are live on every gradient type, including linear -
a CSS linear gradient has no origin of its own, so moving it slides every stop
along the axis, and a sideways move correctly does nothing. A radial has no
direction, so it shows the origin alone.

Three rules came out of getting this wrong:

- **Never draw a handle on something the pointer cannot pick up.** A dead dot
  that looks grabbable is worse than no dot.
- **Grab, do not teleport.** Pressing near a handle keeps the offset so it does
  not jump out from under the pointer. The cursor is `grab`/`grabbing`, never
  `crosshair` (which promises "click to place"), and the handles react to hover
  even though the SVG they live in cannot take pointer events.
- **A hover-revealed overlay needs hover intent.** The stop callout floats clear
  of the ramp, so travelling between them crosses a few pixels of nothing.
  Hiding on that gap makes the card vanish exactly when you reach for it, so
  leaving only schedules the hide and arriving anywhere in the pair cancels it.

**The selected stop names itself, where it is.** Its color, its number and a
labelled Position field ride in a small beaked card over the stop on the ramp,
not in a row underneath. A row parks the label away from its subject and competes
for width the row does not have; the card is an overlay, so it costs no layout
height. It is up while you are working the ramp AND while anything in the ramp
block holds focus, because a focused thing must not lose its label just because
the pointer wandered off.

That card is also the DS's only **elev 3** surface, and it is the reason the level
exists: a card sitting ON an elev-2 popover cannot reuse the popover's own tokens,
or it reads as a hole punched in it rather than a plate above it. In dark it lifts
by growing **lighter**, in light by casting **further**, never both, and it is
opaque because glass over glass doubles the blur. Use `.elev-3`; see
`pages/lang-elevation.html`.

**Two rules that keep it usable:**

3. **Show the outcome, do not name it.** A word or a number is the fallback for
   when a control cannot show you the answer. Here it can.
4. **The popover has a height budget.** It must fit a laptop window with room to
   spare, which means nothing stacks a second copy of anything: no preview beside
   a type list, no aim pad beside an angle row, and the shades / related /
   in-document families share one row behind a scope switch rather than stacking
   three labelled grids.

**The switch appears only where a paint applies.** A drop shadow takes a flat
color, so the Shadow row opens straight into the picker with no type switch, the
same rule as opacity: a control that cannot apply is not shown doing nothing. The
non-color paint types (image, noise) are the same switch with their own body; see
`pages/paint.html`.

**Spacing inside it:** 12 between blocks, 8 inside a block, 4 between swatches in
a grid. Nothing else. (`.popover.pop.on{display:block}` out-specifies a bare
`.cpick{display:flex}`, so the layout declaration is written as
`.cpick, .popover.pop.on.cpick` - get that wrong and every gap silently dies.)

Authoring: `data-cp-color` seeds it, `data-cp-fill` / `data-cp-text` bind live
outputs, a `cp:change` event carries `{hex, rgba, r,g,b,a, h,s,l}`, and a
`cp:set` event re-points the same popover at another slot. The eight regions are
built by the component, so an empty `<div class="popover cpick pop">` is a whole
picker, and a slot is a `.cpick-btn` carrying `data-cp-slot` (its name) plus
`data-cp-color` / `data-cp-paint` (what it currently holds). See AGENTS.md
"Color" for the two-line adoption. Canonical page: `pages/color.html`.

---

### D8 — The transport bar holds time controls only

The scrubber is the one control in the app whose usefulness is measured in
pixels. At a 15-second document a 323px track gives you 21px per second, so
"put the playhead on 6.40s" is a two-pixel gesture and you cannot land it.
Anything parked on that row is taken directly out of that budget.

So the transport row is **volume · skip · play/pause · loop · timecode ·
scrubber · timecode**, and nothing else. The scrubber is the only flexible
child; every sibling is `flex:none`. It carries an invisible 24px pointer band
(`.scrub::before`), because 6px is what a track should be *drawn* at and has
never been what it should be *grabbed* at.

Fourteen pages had violated this identically, because they were copied from
each other: `video.html` carried Cut · Add key · Delete key · Export, a 353px
block that was **wider than the 323px scrubber it was starving**. Every one of
those buttons already existed somewhere better, which is the tell — a control
lands on the transport when nobody decided where it belonged.

Where an evicted action goes, in order of preference:

| The action is… | It belongs… | Example |
| --- | --- | --- |
| about the whole document | the title bar (`.tbtns`) or the command menu | Export — already the primary button up there on all 14 pages |
| a mode you enter | the tool strip (D4) | Cut → the Blade tool, already in the canvas strip *and* the timeline's |
| about the current selection | next to that selection | Key it → the button already in Properties; Apply / Hard cut → the timeline bar that names the cut |
| about one property at one time | on that property's own row | Add key / Delete key → one diamond per lane in the keyframe editor |
| scoped to the timeline dock | the dock's local bar (`.tlbar`) | Duck, Clear, Reset |

The last row of that table is the one worth internalising. **A keyframe is
never document-level** — it is one value, on one property, at one time — so
"Add key" phrased as a global command had to guess all three. As a diamond on
the property's lane it guesses nothing: the lane says which property, the
playhead says when, and the diamond's own fill says whether a key is already
there (hollow = click to set, filled = click to clear). That is the After
Effects / Final Cut idiom, and it replaces two labelled buttons with one
control that also reads as state. Canonical page: `pages/video.html`.

---

### D9 — Every dock can be pushed away, and it always says how to get back

**The rule, in plain words, and it governs the app as well as the mock pages.**
You can always get your canvas back. Every dock — the side dock of panel groups,
and the bottom dock a document with time gets — can be pushed out of the way
from a control on the dock itself, comes back to exactly the size it had, and
leaves a visible way back on screen the whole time it is away. A collapse that
reclaims no room is theatre, and a collapse with no visible way back is a trap.
There is ONE collapse idiom for this: a second one is worse than none.

**A dock collapsed to a row states the selection, not just the panel's name.**
The reason you pushed the timeline away was to look at the canvas, so the
question you then have is "what am I still editing", not "is there a timeline".
The row answers that: on `video.html` it reads `Lower-third · 0:04 / 0:15`.

The rest of this entry is how each half of the product spells that rule today.

**In the mock pages.** The panel dock could be dismissed to a rail and the
timeline could not, which made the two inconsistent in the one way that matters.
On a laptop the timeline is the single biggest thing between you and a
full-height preview, so it is the one people most want to push away, and it was
the one with no handle to do it. It now follows the side dock exactly:

| | expanded | collapsed |
| --- | --- | --- |
| side dock | `.dock-close` (×) in its header | `.drail` — a vertical rail of `.drailtab`s |
| bottom dock | `.tl-close` (×) at the end of `.tlbar` | `.tlrail` — ONE row |

Both are injected by `dock.js`, not authored per page, so all fourteen timeline
pages get the control without editing fourteen files. Pages keep the row current
by writing `data-tl-summary` on the `.timeline`; `dock.js` observes the attribute
so the page never has to know a rail exists. Verified: 14/14 dock timelines
collapse to a 30px row and restore to their exact original height, and on
`video.html` collapsing takes the canvas from 460px to 697px.

Two page traps, both of which produce the same symptom, contents correctly
hidden inside a dock that never shrank:

1. `.timeline` carries `min-height:172px` for the expanded case, so the collapsed
   rule must release it (`min-height:0`).
2. Several pages pin their dock with an **inline** `style="min-height:170px"`,
   and an inline declaration outranks any stylesheet rule. `dock.js` stashes the
   inline `minHeight`/`height`/`maxHeight` on the way down and restores them on
   the way up, rather than escalating to `!important` — the page keeps ownership
   of its own expanded size, and it comes back to the pixel.

**In the app** (checked 2026-09-08 against `Sources/Photonz`). The side dock
slides away entirely rather than leaving a rail: Show Panel in the View menu
(⌥⌘L) and the toggle in the window's own title bar are the same one state, so
the way back is on screen the whole time the dock is away, and the dock returns
at the width it had. That satisfies the rule — a way out, a visible way back,
and real room reclaimed — by a different spelling from the pages, and it is fine
as long as the dock is one column: a rail earns its keep when there are several
groups you want to jump straight back into, not when there is one thing to
re-open.

The bottom dock arrived on 2026-09-15 and owes the row half of the rule, which
it now pays (checked against `Sources/Photonz/MotionStripView.swift`). The
timing strip's × puts it away to ONE 30 point row across the bottom
(`MotionStripRailView`) which opens the strip again when it is clicked, so the
way back is on screen the whole time it is away rather than only in the View
menu and on ⌥⌘T. The row states the selection, not the surface's name: it reads
`Rectangle · Rotation · 900 ms`, the layer you are on, what is moving on it and
how long a lap is, and it falls back to `2 layers moving · 900 ms` when the
layer you have picked is not one of the movers, because naming one of two would
be picking a side. The words are decided in `PhotonzCore`
(`MotionStripSummary`), where they are tested. It comes back to the height it
had for free, the strip being exactly as tall as the lanes it holds; the day
that height can be dragged, it has to be stored. No second collapse idiom was
invented for it: the × on the surface's own header, one visible control back,
same as the dock above.

**What a bottom dock owes that a side dock does not** (added 2026-09-17, after
the strip shipped closing to nothing at all and had to be fixed:
`closing-the-timing-strip-leaves-no-way-back-on-t`). The side dock's spelling
was accepted above on the grounds that "a rail earns its keep when there are
several groups you want to jump straight back into". That is a reason about
CONTENT, and it was read straight across to a dock on a different edge of the
window, where it decides nothing: the timing strip holds one thing, so by that
reasoning it owed no row, and what shipped closed to nothing with the View menu
as the only way back. The reason was never the number of groups.

1. **The way back lives on the edge the dock went away from.** The side dock's
   toggle is in the title bar, which shares a corner of the window with the dock
   it restores, so the eye finds the way back an inch from where the thing
   vanished. A bottom dock's way back in the title bar is the whole height of
   the window away from the surface it restores, and somebody who has just
   watched a strip drop off the bottom of the screen looks DOWN. That, and not
   the group count, is why a bottom dock owes a row across the bottom while the
   side dock does not owe a rail. **A menu item and a keyboard shortcut are
   never the way back**, in either direction; they are extra doors to it.
2. **A dock over something that is still happening keeps saying what is
   happening.** The canvas goes on moving while the timing strip is away, so the
   row is not only a way back: it is the only thing on screen saying what is
   moving and how long a lap is. A side dock pushed away costs you a control; a
   bottom dock pushed away can cost you a reading. So anything in the row that
   can become untrue while the dock is away is kept true in the row. A position
   is not a reading and is not owed — the strip's row shipped without a playhead
   on purpose.
3. **Height is the scarce axis**, which is both why the bottom dock is the one
   people push away most and why its collapsed state has to earn its 30 points.
   It earns them by stating what you are still editing, never by naming itself.

---

### D10 — A property list shows what CAN be animated, not what is

Rendering only already-keyed properties hides the mechanism exactly when it is
needed most: on a clip with nothing animated there is nothing to click, and on a
clip with three keyed properties it looks as though those are the only three that
exist. Neither is true.

So the inspector renders a **catalogue** — every property the selected kind can
animate — and the keyed set is only a record of what it currently *is* animating.
Every row carries the same control, so "how do I animate this?" has one answer
everywhere: click the diamond on its row. The diamond carries three states, and
they must be distinguishable at 8px:

| state | look | click does |
| --- | --- | --- |
| dormant | dim outline, quietest thing in the row | starts animating it, first key at the playhead |
| animated, no key here | outline in the property colour | adds a key at the playhead |
| animated, key here | solid fill | removes that key |

Clearing the last key retires the property to dormant rather than deleting the
row — one key is a constant, not an animation, and a row that vanishes when you
undo the thing that created it is a trapdoor.

The catalogue is per kind: a visual clip offers Opacity/Position/Scale/Rotation/
Blur, an audio clip offers Volume/Pan. Canonical page: `pages/video.html`.

**Which surfaces print the catalogue, and which show only what is** (added
2026-09-17; the app now answers this both ways, and both are right). D10 was
written for a video clip inspector and then read as though it governed every
surface where something can be animated. It does not. Next's Motion section
lists only the properties that ARE moving, and the catalogue of what could move
lives behind the plus on its header — one item per thing the layer in front of
you actually has, each showing the value it is wearing now
(`MotionProperty.offered(for:)`). That is not a slip: it is the answered model
(decision `say-where-animating-an-icon-and-editing-a-video`, answered b with the
user's correction that motion is a property applied like an effect and that
there is no canned list of motions).

Two questions decide which spelling a surface gets, and on every surface so far
they agree:

- **Is time the surface's whole job?** The inspector beside a timeline has
  nothing else to say about a clip, so five dormant rows cost nothing and buy
  the answer to "how do I animate this" for free. A layer's panel column is
  shared with Appearance, Effects, Arrange and the rest, where room is the
  binding constraint (section 3's height rule), and a permanent catalogue there
  is a second inspector stacked on the first.
- **Is the animatable set fixed by KIND?** Every visual clip offers the same
  five properties, so a catalogue can be printed once and be true. A layer's set
  is decided by the layer in front of you: a photograph has no colour to
  animate, and a rectangle has no stroke width now that a box's edge is a Border
  in the Effects list. A list that has to be built from the thing you picked is
  built when it is asked for.

**What both spellings owe, which is the part D10 exists to protect.** "How do I
animate this?" has ONE answer on a surface, and that answer is on screen before
anything is animated: the diamond on every row where the catalogue is printed,
the plus on the Motion header where it is not, and a section that says in words
that nothing moves yet rather than being empty. A surface that shows only what
is moving and offers no visible door to what COULD is the failure D10 names, and
the plus is what keeps Next out of it. The second obligation carries too: losing
the last of something must not be a trapdoor. On a printed catalogue the row
retires to dormant instead of vanishing; where there is no catalogue, whatever
leaves the list is back in the plus's menu and one undo press away.

`pages/video.html` remains canonical for the printed catalogue. It is the CLIP
spelling, and nothing on it should be copied into a document layer's panel.

---

### D11 — Overlays and lists have ONE choreography, and it is interruptible

Motion had tokens (`lang-motion`: three durations, three easings, enter/exit/move)
but no **choreography**: nothing said what happens when two things must move at
once, or in what order. So every surface improvised, and improvised motion is
exactly what reads as unpolished — things pop, jump, or animate on top of each
other. The rules below are the missing half, and they are implemented once, in
`dialog.js` and `listfx.js`, so no page choreographs anything by hand.

#### Overlays: the scrim and the surface are one gesture, and dismissal is soft

Every overlay (dialog, sheet, popover, the decision carousel's cards) enters and
leaves the same way:

| | scrim | surface | why |
| --- | --- | --- | --- |
| **enter** | fade in, `dur-2`, standard | fade + rise 6px + scale from .97, `dur-3`, **decelerate** | the surface lands softly, arriving after the scrim has begun to darken so it never appears against a bright backdrop |
| **exit** | fade out, `dur-2`, standard | fade + sink 4px + scale to .985, `dur-2`, **standard** | leaving is quicker and plainer than arriving (lang-motion §03); a slow exit reads as the app hesitating |

The surface's transition is longer than the scrim's on the way in and **the same
length** on the way out, so the two never separate visibly.

**Soft dismiss is mandatory, and it is three gestures, not one.** Every overlay
closes on **Escape**, on a **click on the scrim itself** (not on a child, which
is a click that merely bubbled), and via its own **close control**. An overlay
you can only leave through one specific button is a trap; the only exceptions are
destructive confirmations, which state their choices explicitly. Escape closes
the **topmost** overlay only, so a popover inside a dialog does not take the
dialog with it.

**Focus is part of the animation.** On open, focus moves to the **surface
itself**, not to its first control; on close it returns to whatever opened the
overlay. Focus never sits on an element that is fading away.

Focusing the surface rather than the first button is deliberate twice over. It
is what announces the dialog to a screen reader, and it keeps the keyboard ring
honest: a scripted `.focus()` on a button counts as non-pointer focus, so
`:focus-visible` matches and a plain mouse click drew a keyboard ring around the
close button. Rings mean "the keyboard is here" and must never appear for a
pointer user. The container takes focus and draws nothing; every control inside
keeps its own `:focus-visible`, so keyboard users lose nothing. A dialog whose
job is typing opts in with `data-dialog-autofocus`, where landing in the field
is the point.

#### Lists: exits, then moves, then enters — three phases, never simultaneous

When a list changes, the change is almost never one thing: an item leaves, the
rest close the gap, and something new arrives. Doing those at once produces the
"everything slid at once and I could not tell what happened" effect. So a list
change is **sequenced**, and each phase has one job:

1. **Exit** (`dur-2`, standard) — departing rows fade out **in place** and
   collapse their height. Nothing else moves yet, so the eye sees *what left*.
2. **Move** (`dur-3`, standard) — surviving rows travel from their old positions
   to their new ones (FLIP: measure, invert, play). Nothing is fading now, so
   the eye sees *where things went*.
3. **Enter** (`dur-3`, decelerate, **staggered 24ms per row, capped at 6 rows**)
   — arriving rows fade + rise into their final positions, last. The stagger is
   what makes a batch read as "these arrived" rather than one block appearing.

Phases overlap by a hair (each starts 20ms before its predecessor ends) so the
sequence reads as one motion instead of three, and the whole thing is capped at
roughly 600ms: past that a list feels slow rather than smooth.

**A list that only moves skips phase 1 and 3.** Reordering (a sort, a
resequence) is phase 2 alone, and it must be a real move: rows travel, they do
not cross-fade in place.

#### Interruption: retarget from where things ARE, never queue and never jump

Data arrives on its own schedule (the dashboard polls every 4s), so a second
change will land mid-sequence. Three rules, in priority order:

1. **Never queue.** The new state is the truth; finishing an animation toward a
   state that is already stale wastes the user's attention.
2. **Measure live, not logical.** The "before" positions for the new sequence are
   the rows' **current on-screen rectangles, mid-flight** (`getBoundingClientRect`
   reports the transformed position). Retargeting from live geometry is the whole
   trick: rows curve toward their new destination instead of snapping back to
   where they logically were and starting over.
3. **In-flight exits finish, they do not resurrect.** A row already fading out
   keeps fading (it is nearly gone; reversing it is more confusing than letting
   it go), and if the same key returns it enters as a new row.

**Never animate what the user is touching.** A list must not re-choreograph while
a row's own control has focus, or while a pointer is held down inside it. The
dashboard already suspends its poll-driven re-render for open dialogs and focused
fields for the same reason.

#### Views: a screen arrives, it does not cross-fade

The third motion component, beside overlays and lists, and the one that was
missing longest: changing what the whole page shows. It is **one entrance, no
exit** (`view.css` / `view.js`, `PZ.view.enter(el)`), and the absence of an exit
is the decision, not an omission. Fading the outgoing view out first would delay
the incoming one by the exit's entire duration, and navigation is where added
latency is felt most. The new view paints immediately and rises the last 8px
into place: it reads as arriving, and costs nothing.

It applies at every scale, and it is always the same motion:

- **A page loads** — `view.js` plays it once on the page's stage, so every page
  in the site enters identically without doing anything.
- **A section swaps in place** — the region that changed calls
  `PZ.view.enter(el)`; navigating between pages and switching sections within
  one then look like the same act, because they are.
- **Re-render is not arrival.** Only play it when the view actually CHANGED. A
  polled refresh of the section you are already reading must not re-animate it,
  or the page twitches on every poll.

A page-local page-transition is a bug, the same way a page-local tooltip is:
the next page invents a slightly different one and the site drifts a single
animation at a time.

#### Reduced motion collapses the sequence, never the outcome

Under `prefers-reduced-motion: reduce`, all three phases become instant and the
final state is identical. This is not a lesser experience with things missing; it
is the same result without the travel. Every component here checks it once and
takes the instant path.

---

### D12 — Two kinds of tooltip, and one placement law

A tooltip existed in the system (`tooltip.css` / `tooltip.js`, `data-tip`), and
it was still hand-rolled again on the dashboard's charts, because the component
answered only half the problem. There are **two** kinds, they look the same and
behave differently, and only one of them was covered:

| | **Hint** | **Readout** |
| --- | --- | --- |
| labels | a **control** | a **position** (a point on a chart, a spot on a canvas) |
| anchored to | the element | the **pointer** |
| markup | `data-tip="Split at playhead"` | `PZ.tip.readout(html, event)` |
| beak | yes, aimed at the control | none: a beak aimed at a moving cursor reads as jitter |
| delay | ~400ms in, so it never flickers past | none: it is already the answer to a deliberate hover |
| content | one short label, optional shortcut | values, tabular figures, several lines |

Neither is a second tooltip system. They are one component with one plate, one
elevation, and one placement law.

**A paragraph is not a tooltip.** A hint is one short line, and a readout is a
few values. When the content is longer than that, it belongs in the surface the
thing already opens: the dashboard put a task's whole notes field into a row's
`title`, which the component dutifully turned into a tooltip that covered the
list it was describing and could not be read. The row opened a detail dialog the
whole time. If you are reaching for a tooltip to carry a paragraph, the answer
is the detail view, not a bigger tooltip.

**Watch `title`.** Any element with a `title` and no `data-tip` is upgraded
automatically, which is a feature for real labels and a trap for text that was
never meant to be one.

#### The placement law (in this order, and the order is the point)

1. **Never cover the subject.** A hint sits off its control; a readout sits
   clear of the pointer by a gap. A label that covers the pixel you are
   inspecting has defeated itself.
2. **Prefer the side with room**, biased away from the content: above for a
   hint, below-right of the pointer for a readout, which is where a
   right-handed cursor leaves the most visible.
3. **Flip before anything else.** If the preferred side does not fit, move to
   the opposite side of the anchor. Flipping is the primary response to an
   edge, not a fallback.
4. **Clamp only when both sides fail**, and keep the beak pointing at the real
   anchor rather than at the tooltip's own middle.
5. **NEVER resize to fit.** This is the rule that was missing, and it is not a
   nicety: a readout squeezed into the last 40px of the window wraps and then
   clips, so the number you are reading is the one that got cut off. A label
   MOVES; it never shrinks. Any `max-width` on a data readout is a bug.

#### It must never be in the way

A tooltip is `pointer-events: none`, always, so the mouse passes straight
through it: hovering "onto" a tooltip is impossible, so it can never steal a
hover, block a click, or trap the pointer between itself and its subject. It
hides the moment the pointer leaves its subject, and it dies immediately if the
element it labels is removed from the document, so a label never outlives the
thing it labels.

---

### D13 — Chart hover: snap to the data, and anchor the readout to the crosshair

Charts are read by pointing at them, so the hover behaviour IS the chart's
interface. One model, and it applies to every time-series chart in the app.

**The crosshair snaps to a data point, never to the pointer.** A line chart has
values at discrete positions; the space between them is interpolation, not data.
So the vertical crosshair jumps to the nearest data point's x and the readout
reports THAT point. A crosshair that tracks the cursor continuously implies a
precision the data does not have, and it makes the reported value change while
the line under it does not.

**Every series is reported at once.** With two lines, one crosshair, one readout
carrying both values plus anything derived from them (the dashboard's chart adds
the gap between them, which is the number the chart exists to show). Do not make
the user hover each line in turn.

**The marker sits on each line.** At the snapped x, each series gets a dot at its
own value, so the crosshair, the dots, and the numbers in the readout are
visibly the same moment.

**The readout is anchored to the crosshair, not to the cursor.** This is the
rule that was violated first: the readout floated wherever the mouse happened
to be, so the numbers and the line they described were in different places and
the eye had to pair them up. It sits beside the crosshair line, flipping to its
other side near an edge (D12's placement law), so the value and its position
are always adjacent.

**The whole plot is the target.** A hover band spans the full plot height, so
you can point anywhere in the column rather than tracing a 2px line, and the
readout appears from the first pixel of the plot area rather than only near a
mark.

**Bars anchor to the bar.** A bar chart has no crosshair; each bar is its own
target and its readout anchors to the bar's top edge, which is where its value
is.

**Leaving is immediate.** The crosshair, the dots, and the readout all disappear
the moment the pointer leaves the plot: a stale crosshair pointing at a value
you are no longer asking about is worse than none.

---

### D14 — A callout never covers what it is talking about

An annotation on the canvas exists to explain something in the picture. The
moment it sits on top of that something, it has destroyed the evidence for its
own claim. This is not a polish item: an alignment chip reading "off 5 px" was
drawn at the midpoint of its own guide, which is exactly where the misaligned
label was, so the one element you needed to look at was the one hidden.

The rule is the same one the tooltip placement law states (D12), applied to the
canvas, and it governs every annotation the measure tools draw: the alignment
verdict, caliper value chips, gap labels, hover outlines and the role legend.

1. **Never overlap the subject.** The elements being measured, checked or
   compared stay fully visible. If the only place a label fits is on top of its
   subject, the label moves; the subject does not.
2. **Prefer the empty side.** Put the callout in whitespace: outside the span of
   the checked elements, beyond the end of a guide, or on the side of a caliper
   where nothing is drawn. Whitespace is where a label costs nothing.

   **When there is no empty side** (added 2026-09-17, from audit
   `2026-09-13-tutorials-building-ui-track` rough one; behaviour built as
   `a-tutorial-card-about-the-picture-stops-covering`,
   `TutorialCalloutLayout.place(busy:)`). A canvas with work on it often has no
   margin to put a label in, and rule 2 as first written then had no answer at
   all: a tutorial step about the whole picture drew its card across the top of
   the picture, so "the two left closed up on their own" was read out from over
   the two that were left. **The callout is what moves, and it moves itself.**
   It looks for the band BETWEEN two things as well as the space around them, it
   takes the smallest move from its usual home that gets it clear, and only when
   the picture fills every inch does it cover anything at all — and then the
   least it can, and never its own subject. It reads what is in its way ONCE,
   when it arrives, so it settles rather than chasing a drag.

   **The answer is never something the content is authored around.** Both
   workarounds tried before this one were the wrong shape: every tutorial sample
   was composed 120 points down the page to leave a strip free for a card, and
   the guide about lining things up swept from the LEFT because a callout was
   going to be on the right. A guide that knows where a callout will be is
   backwards, and the arrangement is gone the moment a person makes a document
   of their own. If a callout can only be placed by everything else agreeing to
   stay out of its way, it is not placed.
3. **Stay attached.** A callout that has moved must still read as belonging to
   its subject: a leader line, a tick, or simple adjacency. Moving it is not
   permission to orphan it.
4. **Never cover another annotation either.** Two measurements close together
   nudge their labels apart rather than stacking, because two overlapping
   numbers are worse than one.
5. **Keep the geometry honest.** Moving a label must never move what it
   describes. The guide, the ticks and the connector stay exactly where the
   measurement is; only the readout relocates.

The test for any annotation: cover the callout with your thumb, and the picture
should still show everything the callout is claiming.

**A tutorial guide's card is an annotation, not a guide** (settled 2026-09-17,
because it had been treated as neither, and so was governed by nothing). It
explains something in the picture, which is D16's own test for the difference,
so every rule above applies to it. How it is DRAWN is not in question: it is an
opaque card because it is read rather than looked through. Where it is allowed
to sit is this rule.

---

### D15 — A tool's modes live in the tool, not in a row beside it

The floating tool bar is a fixed, scarce strip: it holds every tool, the colour
pair and zoom, and it has to survive a narrow window. So its width must not
grow with the tool you happen to have selected. Picking Measure was adding four
labelled mode chips plus a Snap menu plus a Show menu, six controls of running
text, and every future tool with modes would have done the same.

**The tool button owns its modes**, the way a pro editor has always done it:

- The tool button shows the **active mode's glyph**, so the bar says what you
  are about to do without a word of text.
- Pressing and holding it, or clicking its chevron, opens a **flyout that
  expands upward** out of the bar (the bar sits at the bottom, so up is the only
  direction with room). The flyout lists the modes with names and glyphs, plus
  one line naming the cycle key, and it closes on pick, on Escape, and on an
  outside click.
- **The flyout is the platform's own pull-down**, the same control the bar's
  selection slot (rectangle / ellipse / wand) already uses: a click runs the
  primary action, a press-and-hold or a click on the chevron opens the list. A
  hand-rolled popover would put a second "there is more inside me" idiom in one
  300pt strip, and would have to re-earn press-and-hold, Escape, outside click
  and arrow-key navigation that the system gives away. Per-mode shortcut hints
  are noise: every mode shares the tool's key, so the list says it once.
- **The keyboard is the fast path.** Pressing the tool's key again cycles its
  modes, so a mode is never more than a keystroke away and the flyout is for
  discovery rather than for daily use.
- A tool with exactly one mode has no flyout and no marker: the affordance
  appears only when there is a choice.

**Options that are not modes do not belong in the bar at all.** A mode changes
what a click does; everything else (Snap behaviour, which roles are shown, a
tolerance) is a setting. The test: if it changes what the pointer does, it can be
a mode; if it changes how the result looks or what is displayed, it is a setting.

**A setting gets a capsule of its own above the bar, and the Inspector keeps it
too.** Settings first went to the Inspector alone, and that turned out to hide
them: the panel gets closed often, and the shell also closes it for you on a
narrow window, so the Zoom Callout's shape and magnification, the wand's
tolerance and Measure's Snap and Show simply stopped existing for anyone working
with the panel away.
Decided on 2026-09-05, over the alternative of a settings foot on the tool's own
flyout (a real NSMenu, which takes a picker but not a slider, so the wand's
tolerance would have been demoted to stepped choices). The settings for the tool
in hand ride in a small capsule of their own, on its own row just above the tool
bar, open without pressing anything and changing as the tool changes. Three
things make it safe: it is NOT part of the bar, so the bar never changes width
whatever you pick up; it disappears entirely, taking no room, for a tool with
nothing to set; and it wraps rather than running off the edge of the picture.
The Inspector keeps every one of the same settings, bound to the same value, so
changing either moves both. The cost, accepted knowingly: it covers a band
across the bottom of the picture, which on a screenshot is often where the
buttons being redlined are.

**A setting the tool holds is not the same setting a drawn layer holds, and it
never learns from it.** The Zoom Callout carries how much the NEXT callout
magnifies, beside its shape; a callout already on the picture carries its own,
in its own Inspector section. They read the same word and look the same, and
they are separate values on purpose: pulling a drawn callout's corners, or its
own slider, must never quietly re-arm the tool with whatever that resize landed
on. Added 2026-09-06 with the callout's magnification, and the rule holds for
every tool memory that comes after it.

The result the bar must hold to: **selecting any tool leaves the tool bar the
same width it was**. If a tool needs more room to explain itself, it needs a
flyout, not a wider bar.

**Keep the mode readable somewhere in words.** A glyph is enough to say what the
next click does while your hand is on the tool, and not enough to remind you
three minutes later. The tool's properties carry the live mode as a word next to
its settings, so the flyout stays the fast path rather than the only path.

**A family of tools is the same idiom, one level up.** Tools that do the same
kind of thing (the three region selectors; line, rectangle and ellipse) share
ONE slot: the button wears the member you used last, a click picks it up,
press-and-hold lists the family, each member keeps its own letter, and shift
plus any of those letters walks the family. Same pull-down, same corner
wedge as a tool's modes, so the bar has one way of saying "more inside". The
bar is laid out as families in a fixed order (pick, cut and measure the
picture; draw on it; paint it) with a hairline between families, so a person
can predict where a tool lives. What is NOT a tool (Resize Image is a dialog)
does not get a slot: it rides at the foot of the family it belongs to.

**Actions are the third kind, and they belong on the thing they end.** A mode
changes what a click does and lives in the tool button; a setting changes how
the result looks and lives in the tool's properties; an ACTION ends a state
(Apply a crop, Cancel it) and belongs on the canvas that state has taken over,
not in the bar. Crop shows Cancel and Crop as words in a glass pill floating
just clear of the tool bar, and the pill leaves with the crop. Two glyphs at the
far end of an 1100pt strip were never what a first-timer reached for.

**A mode that reshapes existing work is picked, never cycled.** Measure's key
walks its modes because a mode only changes what the NEXT click does. Crop's
does not: switching aspect refits the rect you already dragged, so a stray
second press of C would silently reshape your crop. C picks the tool up and
nothing more; the lock is chosen in the flyout or the inspector.

Built for Measure on 2026-08-23: picking it up moved the bar from 1356pt to
960pt, the same width as every other tool. Crop and the Magic Wand followed the
same day: crop's four aspect chips plus its checkmark and cross (207pt) and the
wand's tolerance slider (152pt) left the bar, and picking up either tool now
leaves it at exactly the width Select leaves it.


---

### D16 — A guide draws over your work, and never gets into the picture

A **guide** is anything the app draws on the canvas to help you place things:
the canvas grid, a screen's columns, a guide you pinned, the snap line that
lights up mid-drag, a ruler. It is chrome that happens to be drawn inside the
picture's own rectangle, which is exactly why it needs a rule. It is NOT an
annotation. The two are told apart by what they are for: a guide helps you PLACE
something and says nothing about the picture, while an annotation EXPLAINS
something in the picture (an arrow, a caliper, a gap label, an alignment
verdict) and D14 governs where it is allowed to sit.

**A tutorial guide's card is an annotation** (settled 2026-09-17, because it was
being treated as neither and so was governed by nothing). It is the app talking
about the picture, which is the test above, so its placement is D14's business
and not this rule's. The word "guide" in "tutorial guide" is about the lesson,
not about the chrome.

Two features on 2026-09-05 were each asked for a guide drawn behind the work,
each decided on its own that behind was wrong, and each shipped it in front:
the canvas grid (audit `2026-09-05-canvas-grid`) and a screen's columns (audit
`2026-09-05-screen-columns`). The same answer, reasoned out from scratch twice
in two days, written down nowhere. Here it is, so the third one does not have to
argue it again.

**1. Over your work, by default.** The test is one question: *would the first
thing anybody draws hide it?* A grid you build against has to survive the first
filled box, and a grid behind your layers is invisible the moment the canvas has
anything on it. A screen paints itself white, so a column band behind it is a
band nobody can see and the feature ships looking broken on the very first
screen anyone makes. A guide that only works on an empty canvas is a guide that
stops working the moment you start working.

**2. Under only when the guide is acting as the work SURFACE.** There is one
shipped exception and it is narrow. The grey surround around the canvas always
carries the grid, and while the grid is switched OFF over the picture the same
lines run UNDER it, so the canvas's own drop shadow falls across the paper and
it reads as the surface the picture is lying on rather than as ink printed over
its shadow (asked for by the user on 2026-09-05, task
`the-grid-is-always-behind-the-canvas-and-things`). Over the picture it is a
guide; under the picture it is the desk. If what you are drawing is not the
desk, it goes over.

**3. Drawn over, it must not read as part of the picture.** Being mistaken for
something a person drew is the failure mode of rule 1, and every guide we ship
avoids it the same five ways:

- **Washes and hairlines, never a solid fill and never a hard outline.** What is
  underneath stays completely readable through it. A guide with a border is a
  rectangle somebody drew.
- **Ink sunk out of the way.** The canvas grid is the accent colour mixed most
  of the way into grey; the columns are a soft warm wash. Nothing saturated,
  nothing a layer would plausibly be painted.
- **Two guides that can be on at once differ in KIND, not only in colour** —
  **and so does a guide against anything on the canvas that is not a guide.**
  Fine cool lines against soft warm bands. Two things that read alike read as one
  broken thing.

  The case that forced the second half (added 2026-09-17, audit
  `2026-09-14-icon-keylines` rough three; its own evaluate item two puts the
  same question to the user): an icon frame's keyline margin ships as a violet
  dashed rectangle, and a frame you have just made arrives SELECTED, so the
  first thing anybody sees is two dashed rectangles a few points apart meaning
  completely different things. They were told apart by making the guide's dashes
  longer than the selection's, which is a difference of degree. At a glance, and
  at any distance, it still reads as one selection drawn wrong.

  **The selection outline owns the traced border.** It is the one piece of
  canvas chrome that draws a hard line round the exact edge of a thing, with
  grips on it, because that is how you know what the next gesture will act on.
  So a guide may not draw a hard line round the edge of anything. Where a guide
  has to mark out an area it marks it the way a guide marks everything else: a
  wash over the part that is outside it, or hairlines running out to the edges
  of the frame. The test is asked of a picture rather than of a stylesheet:
  with the frame selected, point at the selection. If a person has to look
  twice, the guide is wearing the selection's clothes. The shipped keyline
  margin disagrees with this and is filed as
  `an-icon-frame-s-guides-stop-looking-like-a-secon`, with the picture, rather
  than being re-described here as though it were fine.
- **Judged against the surface it lies on, not against the app's theme.** A
  white screen in a dark app is still white, so the columns strengthen on a dark
  screen and fade on a light one.
- **Weight in SCREEN points, not document points.** A hairline stays a hairline
  at every zoom instead of growing into a bar, and a guide that would get too
  dense thins out rather than filling in (the grid's level-of-detail ladder).

**4. Never in an export, a copy, or a composited render.** A guide is drawn by
the canvas view, not by the renderer, so it cannot reach a picture even by
accident, and switching one off leaves the canvas byte for byte what it was.
Both shipped guides prove it in their walks: the grid walk photographs the
canvas off, on and off again and the two off pictures hash identically, and the
columns walk renders the document straight after a snapped drag and finds no
bands in it. If a guide is tempting to draw in the renderer, the answer is no.

**5. A guide you pinned outlives the ruler you pinned it with.** Switch the grid
off and a guide dropped onto it stays, and things go on catching it. Something a
person placed on purpose is not chrome that comes and goes with a view switch,
even though it is drawn like one.

**A third kind of canvas chrome: furniture** (added 2026-09-17, audit
`2026-09-14-icon-previews` rough one). A guide helps you PLACE something; an
annotation EXPLAINS something in the picture. The icon previews strip does
neither, and neither do the floating tool bar, the tool settings capsule, the
zoom bar, the canvas notice or a layer's name chip. They are **furniture**:
chrome that floats over the canvas and is about the APP rather than about the
picture. Nothing said where furniture may live, so the previews strip was put in
the top left corner of the canvas by eye, and its audit had to argue the corner
from scratch and then ask the user whether it was right. It also reported the
strip lying over the ruler this rule names as a guide; the app has no ruler yet
and neither does `pages/icon-draw-wt.html`, so rule 4 below is written before
that collision rather than after it, and the shipped strip does not break it
(re-checked 2026-09-17 on the probe with `icon-keylines-walk`: the strip abuts
the frame's name chip and covers nothing).

Four rules, and they are furniture's own rather than the guide rules above:

1. **Furniture is opaque and it floats.** That is the opposite of a guide, on
   purpose: glass with an edge and a shadow, plainly sitting above the work
   rather than in it. Something you can read through that also takes clicks is a
   trap, because the only way to find out whether a click lands on it or on the
   picture is to try.
2. **It is pinned to the canvas VIEW**, so it does not scroll, zoom or rotate
   with the document, and the guides' fourth rule above applies to it word for
   word: it never reaches an export, a copy or a composited render.
3. **It keeps out of the picture's way.** D14's test, applied to the whole
   canvas rather than to one subject: of the places it could sit, it takes the
   one the document is least in.
4. **When two pieces of canvas chrome want the same place, the one whose
   position carries MEANING stays, and the other moves.** A ruler runs along the
   edge it measures, a grid is where the grid is, a callout is attached to its
   subject: move any of those and they stop being true. A tool bar, a previews
   strip or a zoom bar could sit in any corner and only habit says which, so
   they are the ones that move — along their own edge, or to the next corner.
   If neither can move, then the one that is gone in seconds may lie over the
   one that is always there, and nothing else may: a notice that fades may cross
   a ruler, a strip that stays up may not.

**Drawing a new guide in a mock:** stack it above the artwork, at an alpha low
enough to read straight through, as a wash or a hairline; give it a different
kind from any other guide the page can show at the same time; and keep it out of
whatever that page presents as the exported or copied picture. If it looks right
on an empty canvas, that proves nothing.

The test for any guide: **put a filled black rectangle across the whole canvas.**
The guide should still be visible, and should still be obviously not part of the
rectangle. Fail the first half and it belongs over; fail the second half and it
is drawn too strongly.

---

### D17 — "On what curve" is ONE question with ONE answer everywhere

Anywhere a value moves over time, something has to ask how it travels: an icon's
Motion entry, a video punch-in, a move across the frame, a title cascade, an
audio fade. In September 2026 four different lists were on screen at once, drawn
by four different hands. The same control offered you **Spring** on one page and
not on the next, **Ease out** on a third and **Ease in-out** on a fourth, and
there was nothing a person could see that explained the difference.

**The list is one list.** It lives in `shared/components/curve.js` and is never
retyped in a page:

| | | |
| --- | --- | --- |
| **Standard** | Linear · Ease in out · Ease in · Ease out | the four nearly every motion wants |
| **Shaped** | Ease in out sine · Ease out back · Ease out elastic · Steps, 4 | the ones that overshoot or jump |
| | **Draw a curve…** | two handles and a `cubic-bezier(a,b,c,d)` readout, for the curve no name covers |

Three of the eight ARE the design language's own motion tokens under the names
people use for them: **Ease in out** is `--ease-standard`, **Ease out** is
`--ease-decel`, and `--ease-spring` is what **Ease out back** does. The names
and the numbers are also the app's (`EasingCurve` in
`Sources/PhotonzCore/LayerMotion.swift`), so a mock and the thing it proposes
cannot say different words for the same shape.

**The shape is drawn beside every name, and that is the control.** Nobody can
tell *ease out back* from *ease out elastic* by reading them, so every row
draws what it does and you pick by eye. That is also why this is a menu rather
than a segmented group of two or three: three buttons can only offer three
curves, and the fourth thing anybody wants is not on it.

**How a page asks for it.** An empty host, and the component fills it:

```html
<div class="popover menu pop" id="curveMenu" data-curve-menu></div>
<div class="popover pop" id="bezPop" data-curve-editor=".4,0,.2,1"></div>
```

with the ordinary `.select` row as the trigger:
`<span class="select" data-menu="#curveMenu"><span class="lead">Ease in out</span>…`.
A page that needs to animate off the choice calls `PZ.curve.at(id, t)` rather
than writing its own easing maths. `node shared/check-easing.mjs` fails a page
that draws its own rows or offers its own vocabulary, and fails the component
itself if the list drifts from the app's.

**Hold is not a curve, and it does not join the list.** "Jump at the next key,
no transition" is the *absence* of a transition, so where it exists (the video
keyframe card) it sits beside the curve as its own control, and the curve it
suspends is shown faded rather than replaced. Folding it into the list would
have made the list mean two different kinds of thing.

Canonical pages: `pages/icon-animate-wt.html` (the Motion entry's Curve row and
the drawn curve), `pages/video.html` (the default for new keys, and the curve
leaving a selected key), `pages/lang-motion.html` (the list itself, beside the
three interface tokens it shares its shapes with).
