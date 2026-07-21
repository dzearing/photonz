# UX consistency audit agent (Photonz mock)

A reusable auditor. Dispatch it (general-purpose subagent) at ONE page (or a small
batch of disjoint pages) to check conformance to the product's interaction model,
not just per-page styling. It reads the patterns, inspects the page, and reports
structured findings. It does NOT edit pages unless explicitly told to fix.

## Inputs the agent must read first
- `shared/UX-PATTERNS.md` — the interaction model (shell, navigation, selection,
  panels, tools, menu, icon library). This is the rubric.
- `shared/AGENTS.md` — per-page styling contract (controls, spacing, icons, copy).
- `shared/photonz-ds.css` — the real classes and the `.ic-*` icon inventory.
- The target page file under `pages/`.

## What it audits (per page), scored high/med/low

**0. THE FIRST QUESTION — is this a real screen, or a sketch of an idea?**
Before anything else, ask of every window: *does this make sense as a screen of
the product we are designing, or is it just a sketch someone drew?* Judge it
against `PRODUCT-MODEL.md` §4c, the screen contract:
   - **If it wears traffic lights and a title bar, it is claiming to be the app**
     and must be complete: the real shell, a toolbar, and the dock groups its
     workspace calls for. Flag **arbitrarily missing toolbars, missing docks, and
     missing panels** as high severity — "just stuff" in a window frame.
   - **Title bar content must be document identity** (name + context, e.g.
     `settings-capture · 2560 x 1440`). Flag any title bar containing a lesson
     title, feature name, or explanatory phrase ("Vector pen · resolution-
     independent shape") as high severity: that copy belongs outside the window.
   - **A specimen must not wear app chrome** — no fake traffic lights or title
     bar around a concept diagram. Flag those.
   - If the screen is genuinely an idea sketch that cannot be a complete app
     screen, flag it as belonging in **Prototypes & Ideas**, not presented as the
     product.
   - **Cross-screen question:** does this screen fit the set of screens we will
     have designed, or does it contradict its siblings (different panels, a
     different frame, a different idea of what the app is)?

**0b. Walkthrough pages — one app, operated (§4d).** A walkthrough must be ONE
persistent app screen whose state changes per step, with a click cue anchored to
the real control and a *Click / Where / Result* caption. Flag any walkthrough
that is a **slideshow of separate windows**, or whose steps never show what was
clicked or where the control lives, as high severity.

**0a. RENDER VERIFICATION — measure, don't assume.** HTTP 200 and "the right
classes are present" do NOT prove a page works; a page can serve 200, contain a
perfect shell, and still be visibly broken. Open the page in a browser and
measure:
- **Flag any meaningful element that renders at zero width or height.** This is
  the most common silent failure. Cause: a percentage/`min()` width on a child of
  `.canvas` (which is `display:grid; place-items:center`), so the width resolves
  against a shrink-to-fit parent and collapses to 0. Put the definite width on the
  direct grid child (`.selwrap`), not the inner element. Real example:
  `brush-library.html` rendered its sample stroke at `0x250` while passing every
  structural check.
- **Flag `<canvas>` elements with nothing painted** (sample the alpha channel).
- **Flag content that overflows its container** or forces page-level horizontal
  scroll, at wide AND narrow widths.
- Re-check at a narrow window, not just a wide one.

**0c. Page-local class collisions with the DS.** Grep the page's `<style>` for
local class names that also exist in `shared/photonz-ds.css` — especially
`bar`, `btn`, `card`, `sw`, `dsub`, `tbar`, `dock`, `rail`, `sheet`, `val`,
`tool`. A local `.bar` silently inherits the DS rule (e.g. `overflow:hidden`,
uppercase text) and breaks layout in ways that look like a mystery bug. Flag each
collision and recommend namespacing the local class.

1. **Shell conformance** — title bar, options bar + tool strip, docks in correct
   regions. Flag bespoke chrome or floating panels where docked belongs.
2. **Wayfinding** — can the page answer "how did I get here / where is this
   surface / how do I get back"? Flag surfaces (media pool, catalog, tool UI)
   that appear with no dock, no open affordance, no back path.
3. **Library/assets** — is the component catalog / media pool the left-dock
   Library tab with add/import, or a one-off widget? Flag one-offs.
4. **Selection model** — does the right-dock Inspector track selection? Is
   selection shown consistently on canvas + Layers? Flag global/contextual
   confusion (e.g. selection-specific controls shown globally).
5. **Layers pattern** — flat vs grouped used consistently; identical row
   affordances (eye/lock/reorder); instances as single groups.
6. **Icon library** — EVERY glyph an `.ic-*` from the one library; zero
   ascii/unicode/emoji; one-concept-one-icon; missing glyphs flagged as
   "add to library", never near-miss. List every offending glyph with its line.
7. **Controls & states** — canonical `.btn`/`.seg`/etc. with real
   hover/active/focus/disabled; no inert or ad-hoc controls.
8. **Copy** — plain language, no em dashes, "agent" not "Claude", no "leverage".
9. **Cross-page coherence** — does this page's version of a shared surface match
   how sibling pages present the same surface? Name the mismatch and the sibling.

## Output format (write to `ux-audit-findings.json`, append, do not overwrite)
```json
{ "page": "video.html",
  "findings": [
    { "id": "ux-###", "severity": "high|med|low", "category": "shell|wayfinding|library|selection|layers|icons|controls|copy|coherence",
      "what": "one sentence problem", "where": "selector or line", "fix": "concrete change",
      "pattern": "UX-PATTERNS section it violates" }
  ] }
```

## Rules
- Report, do not fix, unless told "fix". When fixing, obey AGENTS.md + UX-PATTERNS
  exactly and keep the change scoped to the one page (or shared DS if the fix is a
  missing shared pattern/icon, which is allowed for shared-DS tasks).
- Prefer proposing a SHARED pattern/class/icon when the same problem appears on
  many pages, so the fix is reused, not copied.
- Verify the page still serves 200 after any fix.

## How the coordinator uses it
- Phase 1: run the auditor across all pages (batched, disjoint) -> findings.
- Phase 2: cluster findings; promote repeated ones into shared DS
  patterns/classes/icons + new AGENTS.md/UX-PATTERNS rules.
- Phase 3: reconcile pages to the shared patterns (batched), re-audit.
