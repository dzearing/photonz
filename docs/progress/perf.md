# Render performance baselines

Product target (CLAUDE.md): **<16ms** re-render for a 12-megapixel document with 10 layers.

Benchmark: `RenderPerfTests.renders12MPTenLayerDocumentWithinBudget` — 4000×3000 base
plus 9 layers covering every content type and the expensive style paths (corner radius +
shadow, rotation + border, gaussian blur, screen blend, two text layers, arrow, rectangle,
multiply highlight). One warm-up render, then median of 10 timed runs. Re-run with
`Scripts/test.sh` and look for the `[perf]` line.

| Date | Commit/state | Median | Min | Max | Machine | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-06-12 | End of phase 1 (tasks 1.1–1.6 in place) | 45.5ms | 40.4ms | 48.0ms | arm64 mac, CommandLineTools build | First baseline. ~3× over the 16ms target; optimization deferred to the phase 7 perf pass. Suspects: per-render CGImage→CIImage re-wrapping, no caching of rasterized text/annotation layers, full-canvas annotation rasterization on the CPU. |
| 2026-06-12 | Phase 7.4: content cache (text/annotation rasters + CIImage wraps) | 35.7ms | 35.2ms | 39.8ms | same machine | Full cold-graph render. Probe decomposition: a base-only 12MP GPU pass + readback costs ~15ms on this machine, so the full-render path can never hit 16ms — interactive re-renders needed dirty-rect patching. |
| 2026-06-12 | Phase 7.4: dirty-rect incremental path (`renderInteractive`) | **6.7ms** | 6.0ms | 8.2ms | same machine | `interactiveEditReRenderMeetsBudget`: drag-tick re-render of an 800×600 layer in the 12MP/10-layer doc. **Meets the <16ms budget.** RenderScheduler now uses this path; full `render()` (export, first open) stays ~35ms. Unchanged documents return the previous frame for free. |

| 2026-09-03 | Groups draw as one thing (`A group draws as one thing`) | **5.7ms** | 5.3ms | 6.4ms | same machine | `interactiveEditInsideAGroupMeetsBudget`, plain group: dragging a layer that lives inside a group of five in the 12MP/10-layer doc. A plain group passes through, so only the dragged layer repaints and the cost matches the same layers loose (5.4ms). **Meets the <16ms budget.** |
| 2026-09-03 | same | 35.0ms | 34.3ms | 37.1ms | same machine | Same drag with the group STYLED (opacity + shadow). A styled group is one object: its fade and shadow are computed from all of it, so any edit inside repaints the whole group, and in this benchmark the group covers most of a 4000×3000 canvas — i.e. a full render. The budget still holds for edits outside it, and a styled group over a small area repaints only its own area. |
| 2026-09-03 | same | 27.0ms | 26.0ms | 28.3ms | same machine | `renders12MPDocumentWithAGroupOfFiveWithinBudget`: cold full render of the same document with five layers in one styled group, versus 36.3ms ungrouped on the same run. Grouping does not cost extra on the full-render path. |

| 2026-09-04 | Crisp tile at zoom (`renderTile`) | **9.2 / 9.5 / 10.2ms** | 7.5ms | 11.3ms | same machine | `crispTileWhileZoomedInMeetsBudget` at 200% / 400% / 800% zoom on the 12MP/10-layer doc, in a 1600×1000-point window on a 2x display. The tile covers only what is on screen, so its cost is tied to the size of the WINDOW, not the picture: zooming from 200% to 800% costs a flat ~1ms more, because you can see sixteen times less of the document. Added on top of the interactive composite (5.4ms), and only after a 90ms settle, so a drag or a burst of typing never pays for it. **Meets the <16ms budget.** |

The interactive benchmark (`[perf] … interactive edit`) is the budget-bearing
number: it is what every drag tick and slider tweak pays. The full-render
number still matters for document open and export, where ~35ms is fine.

## How a budget is decided (2026-09-12)

Until now each budget was a flat number, with a second flat number picked when
`CI` was set in the environment. That is a guess about hardware wearing the
clothes of a measurement, and on 2026-09-12 it stopped the v0.15.0 release
twice: a shared GitHub runner measured 210.6ms on the styled-group interactive
edit against a flat 200ms bound the same commit cleared at 46.1ms here, and
842.7ms then 984.7ms on the 2x export against a 700ms bound it cleared at
112.9ms here. The suite was identical in both places (5705 tests in 474
suites). Nothing had got slower; the machine was slower — roughly 4.5x on the
composite and 8x on the export.

Every budget in `RenderPerfTests.swift` now reads:

    bound = (recorded baseline x 2.5 + 8ms) x how much slower this machine is

and the last term is **measured in the same process** by
`Tests/PhotonzRenderTests/MachineSpeed.swift`, which runs two fixed reference
workloads made of plain Core Image and no Photonz code at all:

| Yardstick | What it runs | Calibration reading | Which budgets use it |
| --- | --- | --- | --- |
| `filter graph` | Two gaussian blurs, a colour grade and a composite over a textured 2400x1800 image | 8.0ms | full render, grouped render, interactive edits, zoom tiles |
| `pixel push` | 12 megapixels produced and forced all the way back to bytes | 15.4ms | the 2x export |

Two of them because one scalar cannot describe a machine that is 4.5x slower at
one of these and 8x slower at the other. The yardsticks use their own
`CIContext` with its own fixed options, so a change to how the app builds its
renderer never moves the ruler, and neither of them runs app code, so a
regression in the composite path moves the subject while the reference stays
put and the gate still fires.

The factor is clamped at 1: a quick reading never tightens a budget below what
it was calibrated to allow. Every run prints both yardsticks and every budget
line, so a failure says what it measured, what it was allowed, and how fast the
machine it was on actually is.

**Releases are never gated on a timing.** `.github/workflows/release.yml` sets
`PHOTONZ_PERF_GATE=report`, so the release run collects and prints every number
and asserts none of them. The budgets still gate every push and pull request in
`ci.yml`, which is where a regression belongs — by the time a tag exists, that
code has already been through them.

### Calibration baselines, 2026-09-12

arm64 Mac (the development machine), suite serialized, nothing else running.
"Old bound" is the flat local/CI pair these replaced.

| Measurement | Baseline | New budget here | Old bound (local / CI) | Headroom then | Headroom now |
| --- | --- | --- | --- | --- | --- |
| 12MP/10-layer full render | 36ms | 98ms | 250 / 350 | 7.2x | 2.7x |
| Full render, five in one styled group | 38ms | 103ms | 250 / 350 | 7.0x | 2.7x |
| Interactive edit inside a plain group | 7ms | 26ms | 100 / 175 | 15.4x | 3.8x |
| Interactive edit inside a styled group | 46ms | 123ms | 200 / 350 | 4.5x | 2.7x |
| Crisp tile at 200% / 400% / 800% | 10 / 11 / 11ms | 33 / 36 / 36ms | 100 flat | ~10x | ~3.4x |
| Crisp tile over a redlined capture | 8ms | 28ms | 100 flat | 13.2x | 3.7x |
| 2x export | 125ms | 320ms | 400 / 1400 | 3.1x | 2.6x |
| 12MP/10-layer interactive edit | 7ms | 26ms | 100 flat | 16.1x | 3.8x |

The old flat bounds were so loose that a real regression walked straight
through them: switching the interactive path back to a full repaint (no
dirty-rect patching) took the interactive edit from 6.9ms to 37.3ms and the
edit inside a plain group from 6.3ms to 39.2ms — both comfortably inside the
old 100ms bound, both failing the new one. That is the gate now saying
something true.
