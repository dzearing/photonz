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

The interactive benchmark (`[perf] … interactive edit`) is the budget-bearing
number: it is what every drag tick and slider tweak pays. The full-render
number still matters for document open and export, where ~35ms is fine.
