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
| `next-measure-hover` | § 3 hover-to-measure size readout |
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

## 3. Hover-to-measure: element size readout — `next-measure-hover`

Mock: `redline.html` `.rl-hover` red outline + the two `hoverc` calipers
(width below, height right), driven by hovering a `.hit` element; hint chip
"Measure mode: click two points for a live distance".

The Measure tool's idle hover today shows only a snap **dot**. In Next, hovering
also reads the **element under the pointer**:

- While the Measure tool is active, no drag/placement in progress, and the
  pointer rests over the image: detect the element rect at the pointer and show
  a tinted outline over it plus two **transient size calipers** — width along
  the bottom edge, height along the right edge — labeled in the current unit.
- Pointer moves to another element → readout follows. Leaving the image,
  starting a click/drag placement, Esc, or switching tools clears it. Holding
  **⌘** suppresses it (same key that bypasses snapping today).
- **Detection is core, TDD** — `ElementBounds.detect(at:in:) -> CGRect?`
  (`PhotonzCore`): from the probe point, walk each of the four directions for
  the nearest accepted edge using the existing windowed `EdgeMap` queries
  (`horizontalEdges(inXRange:)` / `verticalEdges(inYRange:)`, absolute floor,
  luma landings on the element side), the perpendicular window centered on the
  probe. All four sides found within a max radius (default 600 image px, a flag
  parameter) → that rect; any side missing → `nil` and **no highlight** (a
  quiet miss, never a wrong box). Nested hits resolve to the innermost rect
  (nearest edges win by construction).
- **Overlay chrome only.** The readout is canvas overlay layers in
  `CanvasNSView` (like the snap dot and guides) styled from the size-role
  colors (§ 5) at reduced opacity — it never enters the document, makes no
  history entries, and triggers no composite re-render.
- Perf: queries hit the block-summed fields; budget < 1 ms per mouse-move,
  and hover is a no-op until the edge map has finished computing (same gate
  snapping uses).
- The **hint chip** from the mock ships with this flag: a small glass pill
  ("Click two points for a live distance") shown while the Measure tool is
  active and the document has no measurements yet; it disappears forever once
  the first caliper lands (per document).

Committing a measurement stays exactly the shipped flow (click-click or drag,
then head placement). The mock shows hover as a **readout only** — no
click-to-stamp is shown, so none is specced.

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
exists. All UI behind `next-measure-roles` (Next, default ON).

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

## 7. Export: the redline sheet — `next-measure-panel`

Mock: `redline.html` Properties "Export · redline sheet" section (Copy image /
Export PNG / Describe specs) and the Measurements panel menu "Copy as spec
list"; `capture-wt.html` step 11 (Copy image, ⌘C).

- **Copy image / Export PNG** already exist app-wide, and since 16.15 the
  caliper (chip included) is baked into every export by construction. The
  delta is surfacing the two existing actions as convenience buttons in an
  Export section of the measure inspector, per the mock.
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
release tag). The inspector's Export section offers Copy Image
(`copyCompositeToClipboard`) and Export PNG (`exportComposite(.png, 1)`).

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
px `tolerance` parameter, default 1):

- **Creation.** The Measure tool gains a two-chip mode control (Distance |
  Alignment) in the toolbar, shown only when the flag is on. In Alignment
  mode, press-drag draws a dashed guide leveled onto the drag's dominant axis;
  the anchor edge-snaps like a caliper foot (⌘ = free). Release scans; a
  click without a real drag is a quiet no-op. Esc cancels.
- **Scan (core, TDD).** `AlignmentScan.items(axis:position:span:in:)`
  (`PhotonzCore/AlignmentCheck.swift`) samples the guide every 8px, captures
  the nearest `EdgeMap` edge within 12px of the drawn line, and merges
  consecutive samples seeing the same edge (±1.5px) into per-element
  `AlignmentItem`s (edge position + along-axis span). Block-summed resolution
  caveat: stacked elements with sub-block gaps can merge — harmless, since
  merged items agreed with each other.
- **Verdict (derived, never stored).** `AlignmentCheck.verdict`: reference =
  median of item edges (the majority defines aligned), worst deviation beyond
  `tolerance` names the outlier. Fewer than two items → no verdict
  ("no edges").
- **Model.** Not a new layer kind: `MeasureContent.alignment: AlignmentCheck?`
  (headOffset 0, feet = guide ends). Old documents decode with nil; the § 5
  role model can treat `alignment != nil` as the Align role when it lands.
  The committed guide settles on the reference edge, one undo step, then
  draw-then-select as usual. No endpoint/frame handles (a stretched guide
  would carry a stale scan) — move, restyle, or delete and redraw.
- **Render.** `MeasureRasterizer` branch: dashed guide split around the chip,
  a small tick where each aligned element crosses, the outlier's REAL edge
  drawn beside the guide with a connector, and the verdict chip ("aligned" /
  "off 4 px", unit-aware) at the guide midpoint. Baked into the layer raster,
  so exports carry it (16.15 rule).

## 10. Decision index (open questions → queue, not this doc)

| # | Question | Queue task holding the decision |
| --- | --- | --- |
| D1 | ~~Build alignment checks (and how are they created), fold into the 16.7 auto-inspect spike, or skip?~~ **Resolved: draw the guide yourself (§ 9, shipped)** | `next-measure-alignment-checks-blocked-on-decisio` |
| D2 | Two-point measure: stay H/V-only (16.12 decision) or offer the mock's free-angle caliper? | `next-measure-free-angle-two-point-measure-blocke` |
| D3 | ~~Measurement names: derived defaults + rename, or OCR semantic names like the mock's "Save Changes · width"?~~ **Resolved 2026-08-22: derived automatic names + double-click rename, no OCR (§ 6, shipped)** | `next-measure-measurement-naming-blocked-on-decis` |
| D4 | ~~The mock's "Describe specs" agent action: omit, script-surface only, or build?~~ **Resolved 2026-08-22: omitted (§ 7)** | `next-measure-describe-specs-agent-action-blocked` |

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

- `next-measure-hover`: hovering a settings-style capture with the Measure tool
  outlines the row/button/field under the pointer with width + height readouts;
  a fully flat region shows nothing; ⌘ suppresses; no history entries appear;
  `ElementBounds` unit tests cover found/partial/nested/radius-capped cases.
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
  along a shared edge commits a dashed guide reading "aligned"; a 4px-off
  element gets its real edge drawn with a connector and the chip reads
  "off 4 px"; the guide settles on the majority edge even when drawn a few px
  away; scan/verdict/builder/label unit tests and a rasterizer pixel test
  cover it; exports bake the guide.
- All of it: flags appear only in the Next release's Experiments list; Current
  behavior is byte-identical with flags absent/off; `Scripts/test.sh` green.
