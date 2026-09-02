# Next Measure — measurement overlays, readouts, alignment & export (Next release)

Status: SPEC, 2026-08-22. Implements the redline concepts from the design-study
mocks for the **Next** release only. Sources of truth:

- `docs/design/mocks/pages/redline.html` — the Measure tool page (hover
  readouts, roles, Measurements panel, export, alignment concept).
- `docs/design/mocks/pages/capture-wt.html` — the capture walkthrough (Measure
  in the tool strip and command menu, marks-are-layers, copy path).
- Baseline: the shipped phase-16 caliper (`docs/design/tools.md § Measure`),
  which this spec builds AROUND, not over.

Ground rule (from the task): **every feature below traces to a mock element**.
Anything the mocks show but do not define (or that history argues against) is an
open question filed as a queue decision, referenced here and NOT specced.

## 1. What already ships (shared code — do not re-spec)

Both releases already have, from phase 16: the 3-point H/V caliper
(`MeasureContent`, feet + head + chip), edge-map smart snapping with luma
landings and the hover snap dot, px/pt units, stroke/chip/text colors +
label-size inspector, persisted `MeasureStyles` (colors, thickness, label size,
layer effects), draw-then-select, marquee multi-select + batch delete, and
exports that bake the caliper (one raster since 16.15). The redline mock's
"click two points for a live distance", "Units", "Snap", color controls, and
"selected measurement in Properties" are therefore **already true**. This spec
adds what the mocks show beyond that.

## 2. Delivery mechanics (Next-only)

Everything here lands behind **feature flags declared in `FeatureCatalog` and
scoped to the `next` release only, default ON in next** (`experiments.md`):

| Flag | Carries |
| --- | --- |
| `next-measure-modes` | § 3 measure modes: Distance, Size, Gap |
| `next-measure-roles` | § 5 roles, legend, show filter |
| `next-measure-panel` | § 6 Measurements panel, count pill, § 7 export surface |
| `next-measure-center-snap` | § 8 centers snapping option |
| `next-measure-align` | § 9 alignment checks |

- No `Release` branching anywhere (the flags ARE the gate); no forked files
  expected — every surface is additive to the shared editor. Fork per
  `Releases/README.md` only if implementation proves a shared file can't host
  a change cleanly.
- New model types live in `PhotonzCore` (pure, Codable, TDD-first). Core is
  shared, which is safe: the fields are inert when the flags are off, and since
  both releases are **one binary**, a document saved in Next always decodes in
  Current (same code; `role` decodes with a default either way — no format
  skew is possible).
- Tool shortcut stays **i** (Photoshop parity: PS groups its Ruler under I; the
  mock's M is PS's marquee and is not adopted).
- The measure tool's canvas code lives in `Sources/Photonz/CanvasMeasure.swift`
  (Size/Gap hover previews, element and gap lookups, readout planning, the
  three-click caliper placement, the alignment-guide drag); `CanvasView.swift`
  keeps the shell, the pointer routing and every other tool.

## 3. Measure modes: Distance, Size, Gap — `next-measure-modes`

Supersedes the old `next-measure-hover` spec. Hover-to-measure shipped as an
always-on readout, playtested badly (2026-08-23) and has been removed: the flag
is gone and the outline only appears in a mode you pick. The modes themselves
ride a Next-only flag, default on there, so Current keeps the plain two-point
caliper.

The Measure tool has **modes**, shown as chips in the tool options and visible at
all times. `MeasureToolMode` (`PhotonzCore`) is the single source of truth for
what each one does:

- **Distance** (default) — the shipped two-point caliper: click a point, click
  another, click to place the head. It is the ONLY mode that draws nothing
  under an idle pointer, which is the point of it being the default.
- **Size** — the element under the pointer, outlined with the width and height
  calipers a click would leave behind. The click commits BOTH calipers in one
  undo step. `[` and `]` shrink and grow the pick.
- **Gap** — the whitespace under the pointer as one caliper, tagged Spacing when
  roles (§ 5) are on, since a gap between two elements is a spacing callout by
  definition.
- **Alignment** — unchanged, still gated on `next-measure-align` (§ 9).

Every mode produces the same caliper. No mode has a look of its own, which is
why Size commits two standard calipers instead of a combined "124 × 30" badge.

**Detection is core, TDD** — `ElementBounds` (`PhotonzCore`):

- `candidates(at:in:luma:)` returns the nested LADDER of element rects,
  innermost first, grown one boundary at a time from the windowed `EdgeMap`
  queries snapping uses PLUS the picture itself (see "Detection reads the
  pixels" below). A flat bitmap has no element tree, so even the best guess is a
  guess; the ladder is what makes a wrong one a keypress to fix rather than a
  dead end. Each rung must CONTAIN the one before it, and rungs that barely
  differ are thinned, so every press visibly changes the pick.
- `detect(at:in:luma:)` is the first rung, unchanged in meaning.
- **A line of text is an element.** The pair rule cannot see text (a glyph's
  top never agrees with its baseline), so `TextLineBounds.detect(at:in:gap:)`
  reads the words under the pointer straight off the brightness field: the
  commonest brightness nearby is the background, the ink nearest the pointer
  seeds a band, the band runs along the line while the clean stretches stay
  under the visible gap (`AlignmentScan.visibleGap`, scaled) and grows up and
  down while any column still carries ink. What comes back must look like
  words (taller than a hairline, shorter than a panel, daylight between at
  least two letters, not a solid fill) or it is quiet. The box is the INK box,
  cap or ascender top to descender bottom: a screenshot has no line height,
  and the ink box is what a hand-laid caliper across the letters already says.
  `candidates` puts the line first on the ladder, so `]` climbs from a row
  label to its row and card. The one exception is a control's own label:
  words centered in a rung not much taller than they are (a button, a tab, a
  chip) stay that rung's caption, because a pick that flickered between a
  word and its button as the pointer crossed the letters would be worse than
  one that is quietly wrong. Pinned on the fixture: the General heading (157 x
  34 px), the Launch at login label (181 x 25 px), and the buttons unchanged.
  `subjects(from:to:)` sees the same rungs, so a Distance caliper across a
  label hands the label to the readout planner and its number stays off the
  words.
- `gap(at:in:)` needs only ONE axis: the space between two stacked cards has a
  top and a bottom and no sides, and the shorter span wins when both read. It
  measures whitespace, so it keeps reading to the probe-side landing (the clean
  background hugging each element) rather than to the element boundary.
- Perf budget unchanged: under 1 ms per mouse-move (measured ~32 µs), and a
  no-op until the analysis has finished — the edge map and the brightness field
  arrive together, which is the same gate snapping uses.

**Placement.** Modes that place their own calipers use
`MeasureBuilder.clearingHeadOffset`, which stands the readout off far enough to
clear what it measures. A 12 px gap with a 90 px pill parked on it tells you
nothing.

Near the edge of a capture that standoff will not fit, and the head fits itself
to the picture in a fixed order: full standoff outward, then **as far outward as
the margin allows** (down to `minimumClearingReach`, below which the pill
swallows the head line), and only then turn round and reach inward over the
thing being measured. The middle step is the one that matters — a card 64 px
from the image edge has room for the number in its margin, and the older
straight-to-flip rule parked that number on the switch it had just measured.
`canvasEdgeGap` keeps the pill from kissing the edge.

When even that leaves the head over the element — an element flush with the
picture's edge — the head has done all it can and the readout planner finishes
the job. `MeasureLabelPlanner.plan(..., describing:)` takes the rects a
measurement is ABOUT, and Size mode hands it the element it just measured: a
caliper on its own only knows its thin measuring line, so without this the
number happily sits on the box it is quoting. The planner's costs run, worst
first: off the picture (a number you cannot read is not a measurement), on the
subject, on a neighbour or another readout, then rank and travel. That order is
what makes the last resort sane — when a full-bleed element leaves nowhere
clear, every option is equally bad and the classic on-the-line spot wins, so
nothing jumps.

**Neighbours.** `ElementBounds.neighbors(of:in:luma:reaches:)` probes the middle
of each side at two distances — one close enough to catch what is touching the
element, one as far out as the number itself travels — and drops anything that
swallows the element or bleeds back over it (a container is not something a
readout can steer out of, and a band read off the picture is not a neighbour).
`CanvasNSView` reads them once per pick, keeps the answer while the pointer
stays inside that element, and hands the SAME list to the hover preview and to
`EditorState.addElementSize`, so the numbers cannot shift on click.

**Overlay chrome only.** The Size/Gap preview is canvas overlay layers in
`CanvasNSView` (like the snap dot and guides), rasterized through the real
caliper pipeline so the preview and the commit cannot disagree. It never enters
the document and makes no history entries.

**Hint chip.** A small glass pill saying what a click does in the current mode,
shown while the Measure tool is active and the document has no measurements
yet; it disappears forever once the first measurement lands (per document).

**Detection reads the pixels, not just the edge map (2026-08-23).** The first
version walked outward from the pointer and took the nearest accepted edge on
each side, which is why a button read a sliver of a letter and a settings row
stopped at its label. It is now built the other way round:

- A pair of horizontal boundaries, one above the pointer and one below, defines
  the element. `EdgeRun` (core) walks each one along the picture — in
  `LumaField`, the full-resolution brightness the analyzer already computes and
  now keeps — to find how far it actually reaches. The pair has to AGREE (share
  85% of the longer run) to be one element: a button's top and bottom borders
  start and stop together, a glyph's baseline does not line up with the border
  above it.
- The agreed run is the element's width. That is the only way a settings row can
  read 624 wide: it has no left or right border at all, and its width is
  knowable only from how far the hairline under it runs (the card it sits in is
  32 px wider).
- Vertical boundaries then sharpen the sides, but only OUTWARD: a border a few
  pixels past the run's end is the real edge (runs stop just inside a rounded
  corner); one inside the run is something painted on the element, and following
  it would make the readout wobble as the pointer moves.
- Sides land on the outer flank of the boundary pixel, never more than half a
  pixel out, so a drop shadow cannot inflate a card.
- A boundary under the pointer cannot define the element (nobody pointing at the
  middle of a switch means the knob whose edge passes under the cursor), and
  nothing under ten logical points is offered at all (a word's cap-height band
  looks exactly like a wide, short box).

Measured on the audit capture, at ~32 µs per mouse move: primary button 124 x 30
(true 124 x 30), secondary button 72 x 30 (true 72 x 30), switch 42 x 24 (true
42 x 24), settings row 624 x 44 (true 624 x 44), card 652 x 132 (true 656 x 132),
empty field 218 x 26 (true 220 x 26). Flat background still reads nothing.
Pinned in `ElementDetectionFixtureTests` against the capture itself.

**Still off.** A 1 px border between two whites (the text field) puts the
gradient peak on its inside flank at both ends, so the field reads 2 px narrow;
the card's own outline is white-on-near-white under a drop shadow and reads ~4 px
narrow. Both are pinned so they cannot get worse.

**Cost.** The brightness field is one byte per pixel (12 MB for a 12-megapixel
capture), cached beside the edge map and built in the same pass, so it exists
only for documents a snapping tool has been pointed at.

Not specced here: the mock's live caliper rotates to any angle between the two
clicked points; the shipped caliper is deliberately H/V-only (16.12). That
conflict is queue decision **D2** (§ 10).

## 4. Gap and size readouts — what the numbers mean

Unchanged from the baseline and restated only for traceability: the two-point
flow measures **gaps** (feet snapped to opposing edges via luma landings, so a
baseline-to-divider gap reads the designer's number), hover (§ 3) measures
**sizes**, and both display via the caliper chip in px (default) or pt. The
mock's `From / To / Distance / Units` fields in Properties map to the shipped
feet coordinates and `rawDistance`; exposing them read-only in the measure
inspector is part of § 6.

### 4.1 Where every label lands — one placer, one fallback order

Three things get parked on the picture by the app rather than by the user: a
measurement's readout, an arrow's caption pill, and the roles legend. They all
go through **one** scorer, `LabelPlacer` (PhotonzCore). Each surface says only
which spots it would accept, in the order it prefers them, and what the label
has to keep off; the ranking lives in the placer, so UX-PATTERNS **D14** ("a
callout never covers what it is talking about") is one rule in one place.

**The ladder, worst to cheapest.** The gaps between the rungs are the point:
nothing lower can ever outvote something higher, however many times it is
charged.

| Rung | Cost | What it means |
| --- | --- | --- |
| Forbidden | veto | Chrome drawn ON TOP of the label (tool bar, mode-hint slot). A slot behind it is not a worse spot, it is no spot: the label would be invisible. |
| Off the picture | 500 | A number you cannot read is not a measurement. Outranks even covering the subject. |
| On the subject | 400 | What the label is describing: the measured span, the element in Size mode, the arrowhead, the measurements the legend explains. **Flat** — covering two is no worse than covering one. |
| Into a neighbour | 120 | Another readout, the row next door. **By depth**, as a share of the label's own extent across the line, so clipping a corner is not priced as parking in the middle of the row. |
| Leader across something | 100 | The line home runs over the subject, or the arrow's shaft runs under its own pill. |
| One step down the order | 4 | The surface's own preference order. |
| One nudge along the line | 1 | A readout sliding along its own line. |
| Travel | 0.02 / pt | A pull back toward the thing being labelled, so of two clear spots the nearer wins. A tie-breaker only. |

**The fallback order each surface offers.**

- **Caliper readout** (Distance, Size, Gap): on the line → out past the head
  → past the far end → past the near end → out on the other side. The head bar
  is space the caliper already claimed off the thing being measured, so the
  number stays there and only steps further out when the head is too shallow.
- **Alignment verdict**: past the far end → past the near end → on the line →
  out to one side → out to the other. A guide runs THROUGH the elements it is
  judging, so anywhere along it is on top of the evidence; sideways is the last
  resort because which side the elements are on cannot be read from the edges.
- **Arrow caption**: the default spot behind the tail → above the tail → below
  it → left of it → right of it, each pulled back onto the picture first.
- **Roles legend**: top-left → top-right → bottom-left → bottom-right → middle
  of the left edge → middle of the right edge.

Each caliper spot is also tried at five slides along the line (centre, ±1, ±2
chip steps) and, for the sideways ones, at the far edge of each subject in
reach.

**Two user decisions are baked into this ladder** and un-picking either changes
pictures the user has already judged (`MeasureLabelPlacementTests` and
`MeasureCalloutClearanceTests` fail if they do):

- **Boxed in** (2026-09-02): a gap caliper between two full-width rows, with
  nothing clear in reach, keeps its number ON the line straddling both rows,
  rather than shrinking it, stepping past a foot, or sending it to the page
  margin. That is what the flat subject cost buys.
- **How far a number may travel** (2026-09-02): a readout steps sideways up to
  three of its own cross extents to find whitespace, and no further, on a
  connector home. The pill is wider than it is tall, so a vertical
  measurement's number may travel further than a horizontal one's; the even
  leash was offered and turned down.

## 5. Measurement roles — `next-measure-roles`

Mock: `redline.html` legend (Size red / Spacing blue / Alignment dashed), the
`Role` segmented control on the selected measurement, role swatches on every
Measurements row, and blue gap calipers vs red size calipers on the canvas.

- **Model (core, TDD):** `MeasureRole { size, spacing }` on `MeasureContent`.
  Codable via `decodeIfPresent` defaulting to `.size`, so every existing
  document decodes unchanged. (`alignment` joins the enum only if decision
  **D1** lands — the type is written to absorb the case.)
- **Role styling:** `MeasureStyles` becomes per-role — size keeps the shipped
  red set (#FF3B30 stroke, #8C201A chip, white text); spacing defaults to the
  blue set (#0A84FF stroke, #1B3A66 chip, white text). Switching a
  measurement's role applies that role's remembered style; subsequent style
  edits absorb into that role's memory (same absorb rule the tool already
  uses). One undo step per role switch.
- **Creation default:** a new caliper takes the last-used role (absorbed into
  `MeasureStyles` like every other default). The mock puts no role picker in
  tool options, so none is added — the role is edited on the selected
  measurement (`Role` segmented control in the measure inspector, per the
  mock's Properties section).
- **Legend:** the mock's top-left glass legend renders while the Measure tool
  is active, listing only the roles present in the document (plus Alignment if
  D1 lands). Canvas overlay, not exported unless the user's measurements are.
- **Show filter:** tool options gain the mock's `Show` control —
  All / Size / Spacing. It is an **`EditorState` display filter**: filtered
  measure layers are excluded from the interactive render (like a temporary
  eye-off) without touching the model — never persisted, and exports always
  include every visible layer regardless of the filter.

Shipped shape (2026-08-23): `MeasureRole { size, spacing }` on `MeasureContent`
(decode default `.size`, encoded always; `MeasureBuilder.restyled(role:)`).
`MeasureStyles` keeps a `MeasureRoleColors` set per role (`sizeColors` red /
`spacingColors` blue, flat accessors read the active role; pre-roles prefs seed
the Size memory, and the active set mirrors to the flat keys for older builds).
Color edits absorb into the SELECTED measure's role memory; `setMeasureRole`
applies the target role's ink in one undo step and makes it the creation
default. The Show filter lives in `EditorState.measureShowFilter` and is
applied in `submit()` plus both drag-preview underlays; alignment guides are
neither role, so they always show. The legend swatches each kind with the
top-most measurement's actual ink and lists Alignment (dashed) when a check
exists. All UI behind `next-measure-roles` (Next, default ON). Placement
(2026-09-02): `PanelPlacement` walks the four corners, then the middle of the
left edge, then the right, taking the first slot clear of every measurement and
of the bottom chrome (hint slot, tool bar); chrome is never overlapped, a
measurement only as a last resort.

## 6. The Measurements panel — `next-measure-panel`

Mock: `redline.html` dock group "Measurements" (count badge, rows with role
swatch + name + value + per-row eye, panel menu Show all / Hide all / Copy as
spec list / Clear measurements), the toolbar pill "7 measurements", and the
command-menu items (Measure tool / Show all measurements / Clear measurements).

- A dock group listing the document's measure layers, top-most first. It is a
  **filtered view of the layer list, not new state**: selection is the shared
  selection (mock: "one selection, three places" — canvas caliper, panel row,
  Properties), the row eye is the layer's visibility, delete is layer delete.
- Rows show role swatch (§ 5), name, and the formatted value. Until decision
  **D3** resolves, the name is derived: axis word + value ("Width 128 px",
  "Gap 16 px") — D3 decides semantic auto-names (mock shows
  "Save Changes · width", which needs text recognition) and a rename
  affordance.
- Panel menu: **Show all** / **Hide all** (set visibility on every measure
  layer, one undo step), **Copy as spec list** (§ 7), **Clear measurements**
  (delete every measure layer, one undo step; undo is the safety net, no
  confirmation dialog — matches the mock).
- Command surface: "Show all measurements" and "Clear measurements" join the
  editor's command menu next to the Measure tool entry, exactly the mock's
  `Measure` group.
- The toolbar **count pill** ("7 measurements") appears when the document has
  at least one measurement; clicking it reveals/scrolls to the panel.
- The measure inspector gains the mock's read-only **From / To / Distance /
  Units** grid for the selected measurement (values from `caliperGeometry()` —
  no new model state).

Shipped shape (2026-08-23): `InspectorSectionID.measurements` — a dock group in
the inspector, present whenever the document holds a measure layer. Rows come
from `MeasureSpecList.measureLayers` (top-most first, a filtered view of the
stack); each shows the measurement's own ink as its swatch (dashed ring for an
alignment guide), the D3 derived name (`MeasureSpecList.displayName`: "Width" /
"Height" / "Gap" / "Alignment" until renamed — double-click renames, custom
names stick), the formatted value, and the layer's eye. Selection, visibility,
and delete are the shared layer operations. The section header carries the
count badge and the panel menu (Show All / Hide All / Copy as Spec List /
Clear Measurements — one undo step each, no confirmation on Clear). The
toolbar pill ("7 measurements", glass capsule beside the color bar) shows
while the count is nonzero; clicking calls `revealMeasurementsPanel()` (opens
the inspector, un-collapses the group). The menu-bar Measure menu (the app has
no ⌘K palette) adds Measure Tool / Show All Measurements / Clear Measurements.
The measure inspector gains the read-only From/To/Distance/Units grid (feet in
document coordinates from `caliperGeometry()` + the layer frame). All behind
`next-measure-panel` (Next, default ON).

**Mirror rule (2026-09-02).** A panel menu never offers a command the menu bar
lacks, and both call it by one name, in one order. The panel menu is the
close-at-hand copy of the Measure menu, not a second vocabulary: someone who
learns "Hide All Measurements" in the panel finds it under Measure too, and
someone working from the keyboard never has to open the panel for a command.
Both menus now read Show All Measurements / Hide All Measurements / Copy as
Spec List / Clear Measurements (the Measure menu adds Measure Tool first and
Copy Measurement beside the spec list, since those act on the tool and the
selection rather than the whole document). Every item is disabled when it
would change nothing: Show All while all are showing, Hide All and Copy as
Spec List while none is, Clear while there are none. Show All and Hide All
are one undo step each. The rule generalizes: when a command grows a second
home, it keeps its name and its neighbours.

Added 2026-09-02: a guide's derived name says which edges it judged and how
many things it checked ("Left edges, 4 items"; "Vertical edges, 4 items" when
the scan could not tell the side, see § 9). The mock's "Left edge alignment,
4 items" measured 162pt in the row's font against about 149pt of room at the
panel's default 264pt width, so it truncated and lost the count; "alignment"
is already carried by the dashed swatch, the verdict beside the name and the
spec line's role word. The measure inspector gains a **Name** field for any
measurement (commits through the same `renameLayer` as the row's double-click,
one undo step; clearing it restores the current name), and for a guide the
grid reads **Length** instead of Distance and adds **Edge** ("Left, x 48 px";
the reference line in the measurement's unit) and **Items** ("4 items, 1
off").

## 7. Export: the redline sheet — `next-measure-panel`

Mock: `redline.html` Properties "Export · redline sheet" section (Copy image /
Export PNG / Describe specs) and the Measurements panel menu "Copy as spec
list"; `capture-wt.html` step 11 (Copy image, ⌘C).

- **Copy image / Export PNG** already exist app-wide, and since 16.15 the
  caliper (chip included) is baked into every export by construction. The mock
  staged them as convenience buttons in an Export section of the measure
  inspector; that shipped, and was removed again on 2026-09-02 (see the last
  note in this section) because both act on the whole document and read, under
  a selected measurement, as if they exported it.
- **Copy as spec list** is new — `MeasureSpecList.render(document:) -> String`
  in `PhotonzCore` (TDD, format pinned by tests): a header line
  `<document name> · <W> × <H> px`, then one line per **visible** measurement
  in panel order: `- <name>: <value> <unit> (<role>)`. Plain text to the
  clipboard. This is the deterministic half of the mock's "the agent can hand
  back the spec list" promise.
- **Describe specs** (the mock's agent button) is NOT specced — queue decision
  **D4**. (Resolved 2026-08-22: omitted. The copyable spec list and the two
  export buttons are the whole surface.)

Shipped shape (2026-08-23): `MeasureSpecList.render(document:name:)` in
`PhotonzCore` (format pinned by `MeasureSpecListTests`): header
`<name> · <W> × <H> px`, then `- <name>: <value> (<role>)` per visible
measurement in panel order — the value from `MeasureContent.label` (so an
alignment guide reads its verdict, role word `alignment`). The panel menu's
Copy as Spec List puts it on the clipboard via
`EditorState.copyMeasureSpecList()` (header name = document file name, no
release tag).

Added 2026-09-02: the whole hand-off runs from the keyboard. The menu-bar
Measure menu gains **Copy as Spec List** (⌃⌘C, the copy family's free chord:
⇧⌘C is Copy Image, ⌥⌘C Canvas Size and ⌥⇧⌘C Content-Aware Scale are
Photoshop keys) and **Copy Measurement** (no chord; reads "Copy Measurements"
for a multi-selection). Both call the same `EditorState` paths as the panel
menu. Copy Measurement puts the selected measurements' lines on the clipboard
with no header, panel order, via `MeasureSpecList.render(document:ids:)`; an
explicit pick outranks the eye, so a hidden measurement still copies. A
measurement row's context menu offers Copy Measurement for that row without
touching the selection. Plain ⌘C on a selected measurement now carries its
spec line as text beside the private layer payload, so ⌘C then ⌘V in a chat
pastes the line while Photonz's own paste still lands the layer. The mock's
"Copy measurement" lived in a Properties panel menu Photonz does not have.

Added 2026-09-02 (one copy hands off both): with `next-measure-panel` on,
**Copy Image** (⇧⌘C, File menu) also puts the spec
list on the clipboard as plain text whenever the document has at least one
visible measurement. `CompositeCopy` in `PhotonzCore` pins the flavors and
their order (PNG, TIFF, then text; `CompositeCopyTests`), and
`EditorState.copyCompositeToClipboard` walks that list. Image-aware consumers
take the picture (probed: `NSTextView` with `importsGraphics`, which is
TextEdit rich and Notes, and a WebKit editable field, which is Mail compose),
text-only fields take the list (`NSTextField`, plain `NSTextView`). A
header-only list (measurements present but all hidden) is not attached: it
says nothing the picture does not and would leave a stray line in a plain
field. The "Copied" notice gains an `image(measurements:)` subject: "Image",
or "Image and spec list with N measurements". A document without
measurements copies exactly what it did before, and Current is untouched.

Changed 2026-09-02 (the inspector carries only what is about the selection):
the measure inspector's Export section is gone. Copy Image and Export PNG are
whole-document actions with a whole-document home already — File ▸ Copy Image
(⇧⌘C) and File ▸ Export… (⇧⌘E, which opens on PNG at 1× so Return is the old
button) — and beside one selected measurement they read as if they exported
that measurement. In their place the inspector shows one measurement-specific
action, **Copy Measurement** (`copyMeasurement(id:)`, the same call the
measurement row's context menu and the Measure menu make), with the exact
line it will copy rendered under it in tertiary monospace, live from the
document (`MeasureSpecList.specLine`) so a rename, recolor or unit change
updates it in place. `LayersPanel.swift` → `copySection`, still behind
`next-measure-panel`.


## 8. Snapping option: centers — `next-measure-center-snap` (shipped)

Mock: `redline.html` tool options row `Snap: Edges and centers`.

Tool options gain the mock's Snap control with two values, **Edges** and
**Edges and centers**. With centers on, `EdgeSnapping` also offers **midpoint
candidates**: the midpoint between each pair of adjacent accepted edges in the
query window (element centers and gap centers fall out of the same rule),
scored below a real edge at equal distance so an edge always wins a tie. Core
TDD alongside the existing snapping tests. Default follows the mock: Edges and
centers. ⌘ bypass covers both.

Shipped shape (2026-08-23): `EdgeSnapping.snap(includeCenters:)` builds the
midpoints from the UNFILTERED accepted list (the approach-side rule governs
which side of a text run an EDGE snap may land on; a center is its own
target) and scores them at `centerScoreFactor` (0.5) of the pair's FAINTER
strength, so ghost-pair midpoints stay too weak to steal a snap. The option
rides in `MeasureStyles.snapsToCenters` (persisted with the tool's styles);
the Snap menu shows in the Measure options row only when the flag is on, and
center snapping covers the caliper feet and the alignment-guide anchor — the
region-select tools stay edges-only.

## 9. Alignment checks — `next-measure-align` (decision D1: resolved)

Mock: `redline.html` dashed guide spanning four left edges with an `aligned`
tag, the legend's Alignment row, the Measurements row "Left edge alignment ·
4 items", and the `Align` option in the Role control.

**D1 resolved 2026-08-22: "Draw an alignment guide yourself."** You drag a
guide along the edge you care about; every element the line crosses gets
checked, and the guide reads aligned or points at the one that is off. The
16.6 history (draggable guides rejected as busywork) is answered by the
difference the decision named: this guide answers a question, it is not a
snapping ruler.

Shipped shape (all behind `next-measure-align`, Next-only, default ON, with a
`tolerance` parameter in LOGICAL px, default 1, multiplied by the capture's
pixel scale before it meets device-px edges: on a 2x capture one device px of
wobble is half a point, not a misalignment):

- **Creation.** The Measure tool gains a two-chip mode control (Distance |
  Alignment) in the toolbar, shown only when the flag is on. In Alignment
  mode, press-drag draws a dashed guide leveled onto the drag's dominant axis;
  the anchor edge-snaps like a caliper foot (⌘ = free). Release scans; a
  click without a real drag is a quiet no-op. Esc cancels.
- **Scan (core, TDD).** `AlignmentScan.items(axis:position:span:in:)`
  (`PhotonzCore/AlignmentCheck.swift`) samples the guide every 8px, captures
  the nearest `EdgeMap` edge within 12px of the drawn line that is at least
  `defaultElementStrength` (0.2) as bold as the boldest boundary its own sample
  window offers, and merges consecutive samples seeing the same edge (±1.5px)
  into per-element `AlignmentItem`s (edge position + along-axis span). That
  strength floor is the same fraction `ElementBounds` uses, and it is what
  keeps ghosts out: the block-summed map echoes a line of text's left edge for
  a sample or two BELOW the words, a couple of pixels further out and a
  fraction as strong, and before 2026-08-23 that echo became an item and won
  the worst-offender vote, so a 4px offset read "off 5 px". Block-summed
  resolution caveat: stacked elements with sub-block gaps can merge — harmless,
  since merged items agreed with each other. Since 2026-09-02 the scan also
  knows that one boundary can be read twice: a bordered button's top is its
  outer edge and, 3 device px inside it at 2x, the fainter flank where the
  border meets the fill, and a guide whose anchor snapped onto that inner
  flank used to take it along the straight run and the outer edge at the
  rounded corners, so one button became three items and read "off 1 px" with
  4 items against the filled button beside it. Boldness cannot pick the right
  flank (a glyph stem's two sides are equally bold), so extent does: every
  candidate is chained into a track along the guide, and where two tracks sit
  within `pairSeparation` (5 px, the same distance `ElementBounds` uses) and
  one runs strictly inside the other, the shorter is the flank and is left
  out of the pick (`AlignmentScan.borderFlanks`). A border's inner side stops
  at the corners; a descender line stops at the descender; the edge that runs
  the whole element is the element's. Equal-extent pairs (stems) still go to
  the guide's own position, so text edges behave as before.
- **Items are elements, not runs (2026-09-02).** Runs are what the block-summed
  map sees, and a person counts none of them that way: on the settings-pane
  fixture the left edges of six labels read 9 items (the S of "Show in menu
  bar" was three edges), the top of one label read 10 (cap line and x-height
  line by turns), four toggles read 11 (each rounded end its own run), and
  the page's heading, two cards and a button read 10 (a white card's edge is
  a fraction as bold as the text beside it, so the strength floor dropped it
  wherever they shared a block and each card split in two). So `items` now
  takes the `LumaField` the analyzer already keeps for Size mode and regroups
  the runs by walking the guide one device px at a time
  (`AlignmentScan.groupedByPixels`): a position is "present" when the
  boundary itself still reads within `boundaryDrift` (2 px) of the
  bracketing runs' edges (`boundaryFloor` 0.02, the floor `EdgeRun` uses, low
  enough for a white card on `#F2F2F7`), or when there is ink on either side
  of the edge in the 3..20 px band (`inkFloor` 0.15, above a hairline
  divider, under any glyph or fill edge). Only the response ACROSS the guide
  counts, so a divider crossing a vertical guide's band is not an element
  continuing. A clean stretch of `visibleGap` (8 logical px, scaled by the
  capture's pixel scale) is whitespace a person can see and ends an item;
  anything closer is one thing, which keeps a word space and a curved
  letter inside their label and, honestly, folds an icon hugging its label
  into the label. Each item's edge is its dominant (longest) run, so a text
  line is judged by the line most of its letters share, consistently across
  labels; its span is the stretch the pixels covered, so the tick and the
  outlier bracket run the element's real length. A run the pixels never
  backed is dropped. Without pixels (`luma` empty) runs a sample apart are
  joined and nothing more is known, and `AlignmentCheck.itemsAreElements`
  says which kind the check holds: the row and the inspector print the count
  ("Left edges, 3 items", "3 items, 1 off") only when it is true, and
  otherwise say "Left edges" and "not counted". Guides saved before this
  decode false, since their counts were runs. Pinned on the fixture in
  `AlignmentFixtureTests` (six labels 6, one label's top 1, two button
  labels 2 along their tops and along their baselines, four toggles 4,
  heading + cards + button 4, a label and its toggle 2) and on painted scenes
  in `AlignmentElementCountTests`.
- **Verdict (derived, never stored).** `AlignmentCheck.verdict`: the reference
  is the edge the MAJORITY of the crossed elements agree on, and the worst
  deviation beyond `tolerance` names the outlier. Fewer than two items → no
  verdict ("no edges"). Majority means the heaviest CLUSTER (edges grouped
  within `tolerance`), weighed by the guide length its elements occupy rather
  than by item count — corrected 2026-08-23 after the playtest audit found the
  original plain median settling the guide between two clusters, on a line no
  element sat on, whenever the item count was even or the scan split one label
  into two runs. A genuine tie (two edges, nothing to break it) still falls back
  to the median and splits the difference.
- **Model.** Not a new layer kind: `MeasureContent.alignment: AlignmentCheck?`
  (headOffset 0, feet = guide ends). Old documents decode with nil; the § 5
  role model can treat `alignment != nil` as the Align role when it lands.
  The committed guide settles on the reference edge, one undo step, then
  draw-then-select as usual. No endpoint/frame handles (a stretched guide
  would carry a stale scan) — move, restyle, or delete and redraw.
- **Render.** `MeasureRasterizer` branch, and the whole point is that the
  answer is legible without reading the chip:
  - The guide is **dashed where it is only travelling and solid across every
    element whose edge it confirms**, so what the check actually covered is
    visible without counting anything, plus a short perpendicular tick
    (`MeasureBuilder.alignmentTickHalf`, 8px) at each crossing.
  - The offender gets a **bracket, not a tick**: out from the guide to where
    that element's edge really sits, down the edge for the element's whole run,
    and back — drawn at twice the stroke, so it encloses the error as a shape
    you see at a glance and can never be confused with a tick meaning "agrees".
    It replaced a 1px edge line plus a midpoint connector that read as nothing
    at 1:1 (2026-08-23).
  - The verdict chip names the edge as well as the verdict ("Left edges
    aligned" / "Left edges, off 4 px", unit-aware; "Vertical edges" when the
    side is unknown, "No edges" with nothing to compare): an exported picture
    carries no row name, so the chip is all a reader gets (2026-09-02). It
    lands wherever `MeasureLabelPlacement` puts it — past the end of the guide
    by preference, never on a row being judged (D14). Being words, it is often
    wider than the margin a left-edge guide runs in, so a centred chip that
    would hang off the picture slides across the line by exactly the overhang
    (`labelCrossReach` on the on-line and past-the-end placements).
  All of it is baked into the layer raster, so exports carry it (16.15 rule).
- **Which edge (2026-09-02).** The edge map stores no polarity, so "left
  edge" cannot be read off an item. `AlignmentScan.elementSide` looks for the
  element's own ink instead: the mean gradient (`EdgeMap.verticalGradientEnergy`
  / `horizontalGradientEnergy`, |Gx| for a vertical guide, |Gy| for a
  horizontal one) in the band 3..20px on each side of the edge, over the
  item's span; the side that is at least twice as busy and above a 0.02 floor
  wins, otherwise nil. Stored per item as `AlignmentItem.elementSide`
  (optional; old documents decode nil). `AlignmentCheck.referenceSide` is the
  span-weighted vote of the items on the reference line (an outlier facing
  the other way does not vote), and `MeasureContent.alignedEdge` turns that
  plus the guide axis into `AlignedEdge` (.left/.right/.top/.bottom). Named
  in the row and the inspector; when unknown, the row falls back to the
  guide's axis ("Vertical edges") rather than guess a side. Verified on the
  real settings-pane fixture (all three labels: element to the right, so left
  edges).

## 10. Decision index (open questions → queue, not this doc)

| # | Question | Queue task holding the decision |
| --- | --- | --- |
| D1 | ~~Build alignment checks (and how are they created), fold into the 16.7 auto-inspect spike, or skip?~~ **Resolved: draw the guide yourself (§ 9, shipped)** | `next-measure-alignment-checks-blocked-on-decisio` |
| D2 | Two-point measure: stay H/V-only (16.12 decision) or offer the mock's free-angle caliper? | `next-measure-free-angle-two-point-measure-blocke` |
| D3 | ~~Measurement names: derived defaults + rename, or OCR semantic names like the mock's "Save Changes · width"?~~ **Resolved 2026-08-22: derived automatic names + double-click rename, no OCR (§ 6, shipped)** | `next-measure-measurement-naming-blocked-on-decis` |
| D4 | ~~The mock's "Describe specs" agent action: omit, script-surface only, or build?~~ **Resolved 2026-08-22: omitted (§ 7)** | `next-measure-describe-specs-agent-action-blocked` |
| D5 | ~~Where does a gap caliper's number go when two full-width rows box it in?~~ **Resolved 2026-09-02: stay on the line, straddling both rows (§ 4.1)** | `a-caliper-boxed-in-by-two-full-width-rows-finds` |
| D6 | ~~How far may a readout travel sideways to find whitespace?~~ **Resolved 2026-09-02: keep the long leash, three of the pill's own cross extents (§ 4.1)** | `how-far-a-readout-may-travel-to-find-whitespace` |

## 11. Shown in the mocks but deliberately out of scope

- **Saved measure Styles / redline Components** (`capture-wt.html` Library tile
  "Caliper / red", caption "A direction"): the mock itself labels this
  directional, and per-role style memory (§ 5) already covers "same calipers on
  every capture". Revisit only with explicit user demand.
- **Workspace switcher (Image / UI / Video), ⌘K palette, History sheet**: shell
  furniture of the mock study, owned by other tracks, unchanged by this spec.
- **Hover click-to-stamp**: hover is a readout in the mock; committing stays
  the existing placement flow.
- **Units**: "Logical (px)" is the shipped px/pt control; `pixelScale`
  auto-detect from capture DPI remains a phase-16 follow-up, not re-specced.

## 12. Done when (per flag)

- `next-measure-modes`: the tool options always show Distance, Size and
  Gap and which one is active; Distance draws nothing on the canvas until you
  click; Size outlines the pick and one click commits its width and height as
  one undo step, with `[` and `]` changing the pick; Gap turns a click in
  whitespace into one spacing caliper; a fully flat region shows nothing at
  all; no preview makes a history entry; `ElementBounds` unit tests cover
  found/partial/nested/radius-capped cases, the candidate ladder, and a gap
  that has only one axis to read.
- `next-measure-roles`: a caliper can be re-roled between Size and Spacing with
  the role's colors applied and remembered per role; legend appears in measure
  mode listing only present roles; Show filter hides the other role on canvas
  but never in an export. Codable round-trip + legacy-decode tests green.
- `next-measure-panel`: panel rows, canvas selection, and the inspector agree
  on selection; eye/Show all/Hide all/Clear behave as one undo step each;
  count pill matches the panel count; Copy as spec list output matches the
  pinned format for a fixture document.
- `next-measure-center-snap`: with centers enabled a foot drag lands on the
  midpoint between two rows when nearer than either edge; edges win ties;
  option persists with the tool's styles.
- `next-measure-align`: with the Measure tool in Alignment mode, dragging
  along a shared edge commits a dashed guide reading "Left edges aligned"; a
  4px-off element gets its real edge drawn with a connector and the chip reads
  "Left edges, off 4 px"; the guide settles on the majority edge even when drawn a few px
  away; scan/verdict/builder/label unit tests and a rasterizer pixel test
  cover it; exports bake the guide.
- All of it: flags appear only in the Next release's Experiments list; Current
  behavior is byte-identical with flags absent/off; `Scripts/test.sh` green.
