# Photonz — UX patterns & interaction model (the app's spine)

**Status: v1.3. §4 gains "a control that cannot act", one rule replacing the six
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
6). Learn these ten and you can read every surface in the app.

- **Dock** (`.pdock`) — ONE persistent column on the right holding stacked panel
  groups. Resizable by a `.splitter.v`, collapsible to a `.drail`. There is no
  left dock: Layers, Properties, Effects, and **Library** are all groups in this
  one dock (see D1/D2, amended).
- **Panel group** (`.dgrp` > `.dgrp-h` + `.dgrp-b`) — the unit of panel scope.
  Header = chevron + title + optional count + optional buttons; clicking it
  collapses the group to its header (`.dgrp.collapsed`). The body has its **own
  bounded max-height (`--gh`) and its own scroller**, so a 60-layer stack scrolls
  inside Layers and never pushes Effects or Library off screen. Exactly one group
  per dock may be `.grow` and take the leftover space. **New capability is a new
  group.**
  **Reveal** (added 2026-09-04 to describe shipped behavior: commit `4a6aac7`,
  audit `2026-09-03-library-reveal`): when the app brings a group into view for
  you it scrolls the DOCK, by the shortest move that puts the whole group on
  screen, and a group already fully visible must not twitch. The reveal stops at
  the group; it reaches INSIDE the group's own scroller only when the command
  named a particular thing in it, the way making a component scrolls the shelf on
  to that tile (commit `17dca1e`, audit `2026-09-03-shelf-tile-reveal`).
  **Only a command the user just issued about that group may re-open a group they
  collapsed on purpose** (Show Library, or making the thing the group holds).
  Ambient changes never may: a selection moving, a document loading, a background
  update leave a shut header shut and do not scroll. The Library reveal audit put
  the remaining question to the user, whether even a direct command should
  overrule a deliberate collapse; until they answer, it does, because scrolling
  to a shut header shows a title and nothing else.
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
- **Canvas notice** (`.cnv-hint`, bottom centre) — the one transient pill on
  the canvas, shared by the Measure tool's mode hint ("**Gap** Click the space
  between two elements") and the "Copied" confirmation after ⌘C. Its slot
  rule: **bottom centre of the canvas, just above the floating tool bar, never
  behind it; one notice at a time**, never a stack, with a confirmation winning
  over a hint while it is up. **While the Measure tool is in hand the slot is reserved for its mode
  hint**, so nothing else may park there. It takes no input, has no close
  control, and fades with whatever put it up. Not a tooltip (D12): it is on
  screen unprompted and never anchored to a control.
- **Modal + toast** — rare document-scoped dialogs (export, new document), and
  transient confirmations ("Saved", "42 instances updated"). The **capture
  toast** is the global one: it belongs to the menu-bar agent, sits bottom
  right of the screen, and carries its own Edit row (AGENTS.md, GLOBAL
  surfaces).

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
  `LayersPanel.swift` ("3 of the 5 selected layers have a shadow. The rows below
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

*(`GeometryField.land()` in `GeometryInspector.swift` computes `landing(parsed)`
BEFORE `commit(parsed)`, which is how it misses a per-layer clamp on a
multi-layer selection. Fixing it is
`a-width-the-layers-refused-stops-claiming-the-nu`.)*

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

*(`ShadowInspector` binds to `selection.hasShadowEverywhere`, which is why a
part-shadowed selection currently reads plain off. Fixing it is
`a-switch-says-mixed-the-way-every-other-control`.)*

**Built, and the thing to copy:** `InstanceShowKnob` in `ComponentPanel.swift`
(2026-09-05), the show-or-hide knob over several copies. It wears
`MixedLook.controlOpacity`, which is the one step quieter for a control made of
picture rather than words, and the word sits beside the switch. The Shadow
switch adopts the same two when its own task lands.

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

**Then answer by what kind of control it is**, because that, not the feature, is
what decides:

| Kind of control | What it is | The answer |
| --- | --- | --- |
| **A command** | a verb with something to act on: a button, a menu item, a toolbar item | **Stays in place, dimmed.** Never hidden. A command that disappears takes the map with it, and you cannot learn an app whose menus change shape. This is what the app already does in about a hundred places, and it is the platform convention. |
| **A chooser whose value is decided elsewhere** | a menu, a segmented row, a toggle, where something above has already answered the question | **Replaced by the answer, in the same row.** Show the value in plain words and name who owns it. Keep the row in its place and its column so the section still reads as a set of settings. |
| **A field that still has a number to report** | a width, a height, a position the layer really has, that you cannot type | **Keeps the number, read only.** A number you can read is worth more than an empty box, even when it is not yours to set. It must not look like something the keyboard will accept. A field with nothing true to report is the one that stays blank: a line or a caliper has no width of its own, so a number there would be about nothing you drew. |
| **A bare affordance** | a resize handle, a rotate knob, a drag target: something with no label, grabbed rather than read | **Removed.** There is nowhere on a handle to say why it refuses, and a handle you can see but not drag teaches the wrong thing about the state that froze it. Take it away and make sure the state itself is visible somewhere with words, such as the padlock on the layer's row. Only the grabs go: the frame that says what is selected stays, because that answers a different question. |

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
- [ ] **Bounded panels**: every long list is inside a `.dgrp-b` with its own
      max-height and scroller; no list stretches the window.
- [ ] Layers use flat-vs-group consistently; rows have identical affordances.
- [ ] Every glyph is an `.ic-*` from the one library; zero ascii/emoji/mixed
      styles.
- [ ] Controls are canonical `.btn`/`.seg`/etc. with real states.
- [ ] **Transport bar holds time controls only** (D8): nothing but volume,
      skip, play/pause, loop, the two timecodes and the scrubber shares that row.
- [ ] **Every animatable property shows how to animate it** (D10): property
      rows list the whole catalogue, not only the keyed ones.
- [ ] **Both docks collapse** (D9): the side dock to a rail, the bottom dock to
      one row that names the selection.
- [ ] **Nothing inert without an answer** (§4): every control that cannot act
      is dimmed, replaced by its answer, or gone per its kind, and the "who owns
      this" half of its reason is on screen rather than only on hover.
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

### D9 — Every dock collapses, and the bottom one collapses to a row

The panel dock could be dismissed to a rail. The timeline could not, which made
the two inconsistent in the one way that matters: whether you can get your canvas
back. On a laptop the timeline is the single biggest thing between you and a
full-height preview, so it is the one people most want to push away — and it was
the one with no handle to do it.

It now follows the side dock exactly, because a second collapse idiom is worse
than none:

| | expanded | collapsed |
| --- | --- | --- |
| side dock | `.dock-close` (×) in its header | `.drail` — a vertical rail of `.drailtab`s |
| bottom dock | `.tl-close` (×) at the end of `.tlbar` | `.tlrail` — ONE row |

Both are injected by `dock.js`, not authored per page, so all fourteen timeline
pages get the control without editing fourteen files.

**The collapsed row states the selection, not just the panel's name.** The reason
you collapsed the timeline was to look at the canvas, so the question you then
have is "what am I still editing" — not "is there a timeline". Pages keep it
current by writing `data-tl-summary` on the `.timeline`; `dock.js` observes the
attribute so the page never has to know a rail exists. On `video.html` that reads
`Lower-third · 0:04 / 0:15`, and collapsing takes the canvas from 460px to 697px.

Two traps, both of which produce the same symptom — contents correctly hidden
inside a dock that never shrank:

1. `.timeline` carries `min-height:172px` for the expanded case, so the collapsed
   rule must release it (`min-height:0`).
2. Several pages pin their dock with an **inline** `style="min-height:170px"`,
   and an inline declaration outranks any stylesheet rule. `dock.js` stashes the
   inline `minHeight`/`height`/`maxHeight` on the way down and restores them on
   the way up, rather than escalating to `!important` — the page keeps ownership
   of its own expanded size, and it comes back to the pixel.

A collapse that reclaims nothing is theatre. Verified: 14/14 dock timelines
collapse to a 30px row and restore to their exact original height.

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
