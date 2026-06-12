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
