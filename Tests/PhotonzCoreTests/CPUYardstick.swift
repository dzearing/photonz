import Foundation

// MARK: A ruler for the timing checks in this target
//
// The two probe-count checks in `ElementBoundsTests` are steady on a busy
// machine because each one is a RATIO against work of its own: whatever the
// round was competing with slows both halves and divides out. The pick check
// beside them had nothing to divide by, so it kept an absolute budget, and that
// budget went red three times in two days — once reading 28.1 ms against 20 on
// a full suite run and 4.9 ms on its own seconds later. A factor of six.
//
// Reading it on the thread's own CPU clock did not save it, which is the part
// worth knowing: the time is not spent waiting for the core, it is charged to
// the thread and really burned. So this file is the thing to divide by: a fixed
// piece of work that runs no Photonz code at all, taken back to back with the
// measurement inside every round. If the pick gets slower the subject moves and
// the ruler does not, so the check still fires; if the machine gets busier or
// the thread lands on an efficiency core, both move together and the check
// stays quiet.
//
// WHAT THE RULER IS MADE OF IS THE WHOLE TRICK, and it was measured rather than
// guessed. Three candidate rulers were timed beside the pick, idle and then
// during a full 649-suite run with eight spin loops on top:
//
//     pick                 4.41 ms -> 16.68 ms   (3.8x)
//     buffer streamed      3.29 ms ->  3.65 ms   (1.1x)   tracks nothing
//     pointer chase        4.37 ms -> 22.38 ms   (5.1x)   overshoots
//     arrays made and let go
//                          2.19 ms ->  8.46 ms   (3.9x)   tracks
//
// A tight scan over a big buffer barely notices a busy machine, so dividing by
// one would have left the check exactly as fragile as before. What a pick
// actually spends its time on is asking the edge map for candidates, which
// means arrays made and dropped, and THAT is what six hundred suites running at
// once take away from it. So a round here makes arrays and lets them go. The
// ratio it produces held to within two percent across that same pair of runs.
//
// `Tests/PhotonzRenderTests/MachineSpeed.swift` does the same thing for the
// render budgets, against Core Image yardsticks; this is the CPU-side one.
enum CPUYardstick {

    /// What one round cost on the calibration machine: the arm64 Mac this repo
    /// is developed on, `Scripts/test.sh` (unoptimized), measured 2026-09-17
    /// with the rest of the suite quiet. Every run prints what it reads here,
    /// so re-record this only when the calibration machine itself changes.
    static let baselineMS: Double = 4.5

    /// Sized so a round lands near the four and a half milliseconds one pick
    /// costs: two readings at the same scale divide cleanly, and neither is
    /// mostly the cost of reading the clock.
    private static let arrays = 24_000
    private static let width = 64

    /// Kept so the compiler cannot decide the work had no effect and delete it,
    /// which would leave the ruler measuring nothing at all.
    nonisolated(unsafe) static var sink: Double = 0

    /// One round: arrays made, written, read and dropped — the shape of asking
    /// a map for a list of candidates, and nothing this app wrote.
    static func round() {
        var total = 0.0
        for k in 0..<arrays {
            var candidates = [Double](repeating: Double(k), count: width)
            candidates[3] += 1
            total += candidates[3]
        }
        sink += total
    }
}
