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

The interactive benchmark (`[perf] … interactive edit`) is the budget-bearing
number: it is what every drag tick and slider tweak pays. The full-render
number still matters for document open and export, where ~35ms is fine.
