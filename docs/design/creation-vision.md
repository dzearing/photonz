# Photonz — creation & automation vision (direction study)

Status: **exploration**. This is a north-star spec to align on before scoping phases.
Companion clickable mock: `docs/design/mocks/creation-vision.html`.

## The bet

Photonz today is the fastest way to *capture, redline, and annotate*. The next
chapter makes it the fastest way to **create** — a blend of CleanShot's speed,
Figma's structure, and Photoshop's pixel/effect control — with one thing none of
them have: **Claude can drive the whole thing.**

## The organizing principle: Primitives → API → UI

Design order is deliberate and not the same as build order.

1. **Primitives** — a tiny, shared vocabulary every feature is expressed in.
2. **API** — those primitives serialized into a command surface (IPC, like the
   ghoztty relay) that Claude and the app both speak.
3. **UI** — panels and tools that are *thin clients* over the API.

Why API-first: a scriptable command model can't be vague. To let Claude "add a
card with a linear-gradient fill, 24px radius, a soft glow, and a headline in the
type scale," we must define — precisely, once — what a fill/effect/layer/type
style *is*. **That serialized command model IS the design system.** Design
features UI-first and every panel reinvents "gradient" slightly differently; that
is exactly the confusing sprawl to avoid. Design them API-first and the primitives
are shared by construction.

## The five primitives

Everything on the feature wishlist collapses into these:

- **Paint** — `solid · linear · radial · angular · image · noise`. Used
  *anywhere* color appears: fills, strokes, text, shadow/glow color. Build once →
  "rich gradient fill" is done for every object forever.
- **Effect stack** — ordered, non-destructive: `outer glow · drop shadow ·
  inner shadow · background blur · stroke · blend mode`. Generalizes today's
  `LayerStyle`. Glow is an outer shadow with a Paint + spread.
- **Layer** — polymorphic: `raster · vector shape · text · group · adjustment`.
  Same transform + Paint + Effect surfaces on all of them. The model is already
  value-typed/Sendable/Codable, so this extends rather than rewrites.
- **Type system** — real type ramp (family, size, weight, tracking,
  line-height), text-on-Paint, styles as reusable tokens.
- **Tokens** — the design system for *produced content*: spacing, radius, color,
  type ramps. This is what makes Claude's output look designed, and what keeps the
  UI predictable.

Get these right and "add glow" / "add gradients" stop being features — they become
configuration of shared primitives.

### The design-system tier (reuse, Figma-style)

On top of the five primitives sits a three-tier reuse model — this is what keeps
creation consistent instead of sprawling:

- **Tokens** — raw values (color, spacing, radius, type scale).
- **Styles** — *named* Paint / Effect / Type. Edit "Brand gradient" once → every
  use updates.
- **Components** — reusable layer trees you **instance and re-paint** with any
  Style; edit the main → all instances update. A component is just a layer tree,
  so the same one drops onto a UI canvas, a **photo**, or a **video timeline**
  (as a keyframed lower-third). All three tiers are first-class in the API.
- **Semantic names & portability.** Every token, **typeface**, style, and
  component carries a semantic name you can rename (a "Display" typeface aliases
  New York; re-point it and every use follows). A whole design system is a
  portable, versioned artifact: **export / import** it as JSON (or a
  `.photonz-ds` bundle), share it with a team, and the agent reads and applies it
  through the same API.

## Major user scenarios (what the mock walks through)

1. **Fast redline (keep it).** Capture → measure/annotate → clipboard. One
   keystroke away. The creation suite is *additive*; it must never slow this down.
2. **Create from scratch.** New canvas → shapes/text/gradients/effects → a
   designed card/social image/UI mock, guided by tokens.
3. **Claude automates it.** A prompt drives the canvas via the API. Three
   candidate UI treatments in the mock (command palette · docked assistant ·
   inline ghost) — all calling the same commands.

## Automation is model-agnostic (local-first)

The command API is the contract; **the model is pluggable.** "Describe what you
want" is just NL → a sequence of validated, undoable commands, so any tool-calling
model can drive Photonz:

- **Local model, default & private.** Host an open-source model (e.g. Qwen) on
  device via MLX / LM Studio (Apple Silicon runs these well). No network, no
  frontier dependency — works offline, keeps content private. This is the baseline
  "describe what you want" engine.
- **Frontier via MCP, opt-in.** Expose the same command surface as an **MCP
  server** so Claude Code / Claude / any MCP client can drive the app when more
  capability is wanted. Same commands, remote brain.
- **The schema is the safety rail.** Because the model can only emit valid,
  schema-checked, undoable commands, a smaller local model degrades gracefully
  (bad plan → no-op / undo) instead of producing garbage pixels. The API
  constrains the model; execution stays deterministic and reversible.

Design implication: build the **command API + validation/execution** first and
model-neutral; wire a local runtime as the default planner; ship the MCP server as
the frontier path. Never hard-couple the app to one model or one vendor.

## Scope discipline

- **Bet now:** image creation + the automation API. This is the coherent,
  differentiated near-term chapter.
- **Defer:** Premiere-class layered video (timeline, transitions, captions,
  keyframes). Phase 13 already shipped basic video; the ambitious version is its
  own chapter, N+1 — do not let it gate image creation.
- **Validate each creative feature** against a concrete "make this specific piece
  of content" test before building. (We shipped alignment guides, then dropped
  them — the mega-suite is a vision, not yet a validated need.)

## Process & tracking

- **Two tiers, kept separate.** `docs/plan/*.json` stays the source of truth for
  architecture + sequencing (versioned, read at session start). **GitHub issues
  become the parallel work queue** — epics = labelled issues with checklists,
  tasks = child issues. Reason beyond querying: parallel agents editing
  `overview.json` collide on every status write; issues have no merge conflict.
- **~200k per task**, run through the existing `/wt` → `/prep` → `/babysit`
  loop; build/test/ship, close the issue, clear context, next.
- **Parallelism is bounded by the merge surface.** Foundation work on shared
  primitives serializes; independent feature tracks fan out once primitives freeze.

## First vertical slice (de-risks everything after it)

Paint model + one real IPC command (`create-layer` with a Paint fill) driven
end-to-end — canvas ← API ← Claude. Proves the whole Primitives→API→UI loop on the
smallest surface before we scale it out.
