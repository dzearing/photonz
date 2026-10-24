# Memory

Photonz stays light however long it has been open, and gives back what it no
longer needs. This page is the budget, how it is measured, and what was found
when a colleague saw Photonz near 4 GB (2026-10-23).

## The budget

Counted the way Activity Monitor's Memory column counts it: the process's
physical footprint (`footprint -p`, `task_info` `phys_footprint`), never RSS.
A model file the Ask chat server maps in shows as 22 GB of RSS and is not
memory anybody holds.

| What | Budget | Held by |
| --- | --- | --- |
| Photonz idle with one screenshot open | under 300 MB | `closed-windows-give-their-memory-back-walk`, every rotating check |
| Photonz after a long session, windows closed | within 20% of where it started | the same walk (six rounds of a 12 MP picture), and `Scripts/memory-session.sh` for the long one |
| Closed windows | freed: at most one editor alive with nothing open | the same walk |
| Repeating the same open and close | memory does not keep climbing | the same walk (`risingOver`) |
| Ask's chat model and picture model | started only when Ask needs them, let go after 5 idle minutes and when Photonz quits | `AskBuiltInServerPlan.idleSeconds`, measured in the long session |

The numbers live in `MemoryBudget` (PhotonzCore, unit tested). A walk holds the
app to them with the `memory` step:

```json
{ "do": "memory", "mark": "start", "underMB": 300 }
{ "do": "memory", "mark": "end", "withinPercentOf": "start", "percent": 20,
  "editorsAtMost": 1, "risingOver": "round" }
```

It hands freed pages back first, then reads the footprint and how many picture
editors are alive. It needs no window and no name, so it runs under a lock.

## What made Photonz use gigabytes

Measured on the probe on 2026-10-23, opening and closing 20 screenshots and five
12-megapixel pictures: 400 MB growing to 1.96 GB, and it never came back.

1. **Every closed window stayed in memory.** The right hand panel's fold store
   held a closure that held the panel, and the panel's own state held the store:
   a retain cycle that kept each closed window's editor, its pictures and its
   frame buffer alive for good. `heap` counted 25 editors alive after 25 windows
   had closed. Fixed: the panel lets go of the closure when it disappears.
2. **Something can always keep the last editor.** SwiftUI's menu commands hold
   the last focused editor, AppKit keeps a closed window a while, and a walk-only
   tool bar hook held one in every build. So an editor now gives back its
   pictures, frames and caches the moment its window closes
   (`EditorState.letGoOnClose`), whoever still holds it. The tool bar hook only
   registers in the probe.
3. **The system allocator never gave large freed blocks back.** On macOS 26,
   freeing a large block keeps it counted against the app (`MALLOC_LARGE
   (empty)` in `vmmap`), at the session's peak, and `malloc_zone_pressure_relief`
   does not release it: eight 48 MB blocks freed left a test program at 367 MB.
   With every window closed the probe still held 318 MB, 180 MB of it this. The
   bundle now launches with `MallocLargeCache=0` (`LSEnvironment`, checked by
   `Scripts/build-app.sh`): freed pictures go back at once. Cost measured on the
   render perf tests: a full 12 MP render 27.2 to 28.1 ms median, an interactive
   edit unchanged at 5.4 ms, a 2x export about 4 percent slower.
4. **The walk harness kept every editor too** (probe only): its list of editors
   was strong. It is weak now, or no memory reading in a walk could be trusted.

After the fixes, the same open and close: 165 MB with one screenshot open, 113 MB
with nothing open, 120 MB after six rounds of 12 MP pictures, flat.

The long session (`Scripts/memory-session.sh`: 20 screenshots, a 12 MP picture
edited and undone, five minutes of captioned talk played and scrubbed, history,
Ask drawing twice, ten idle minutes), Photonz itself:

| | one screenshot | after 20 screenshots | editing 12 MP | idle, all closed |
| --- | --- | --- | --- | --- |
| before | 203 MB | 693 MB (21 editors alive) | 1430 MB | 1247 MB (26 editors) |
| after | 165 MB | 87 MB | 501 MB | 180 MB (3 emptied editors) |

Charts: `queue/audits/2026-10-23-memory-*.png`.

What is left: up to three closed windows' editors stay reachable after a long
session, through a closed window AppKit keeps (its SwiftUI focus storage and menu
observation). Each was emptied when its window closed, so they cost almost
nothing; the quick guard allows one, the long session three, and the footprint
checks are what hold the memory.

## Caches

The renderer's caches are capped by count (32 rasters, 32 wraps, an 8 MP mask
budget). When the Mac runs short of memory (`DispatchSource` memory pressure,
`MemoryRelief`) Photonz empties Core Image's shared caches and every open
editor's renderer caches and thumbnails, and hands freed pages back.

## The Ask helpers

The chat model server (`llama-server`) and the picture model (`python`) are
programs of their own. Activity Monitor lists each in its own row under its own
name, not as Photonz; macOS does count them as Photonz's (its responsible
process), which is what the "out of application memory" dialog sums. They
start only when Ask needs them, are let go after five idle minutes, and stop when
Photonz quits (measured: both gone about five minutes after Ask's last drawing,
and within two seconds of quitting). Loaded, the chat server holds about 3 GB of
footprint (its 20 GB model file is mapped, not copied, so its RSS reads 22 GB),
and the picture model 13 GB while it paints and about 5 GB while it waits.

A Mac is offered the best chat model that fits in 60 percent of its memory
(`AskModels.memoryShare`): a 48 GB or larger Mac gets Qwen3.8 27B (24.4 GB held with
its draft), a 40 GB Mac Qwen3.6 35B, a 36 GB Mac Gemma 4 26B, a 16 GB Mac Gemma 4
E4B (7.5 GB), and the picture model (12 GB) is offered only where it fits beside
the chat model, so not on 16 GB.

## Measuring

```
Scripts/playtest.sh Scripts/playtest/closed-windows-give-their-memory-back-walk.json   # about a minute
Scripts/memory-session.sh /tmp/photonz-memory/session                                 # about 25 minutes
Scripts/memory-watch.sh out.csv --every 5 --for 600    # sample the probe and its helpers
node Scripts/memory-chart.mjs out.csv out.svg          # draw it
```

To find what holds memory: `leaks --outputGraph=<file> <pid>`, then
`heap <file>` for counts by type and `leaks --traceTree=<address> <file>` for
what keeps one object alive.
