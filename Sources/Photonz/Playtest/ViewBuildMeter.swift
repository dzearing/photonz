// A counter for view bodies, so a walk can prove a list builds only the rows
// you can see rather than assert it. Probe-only, like the rest of the harness:
// `PHOTONZ_PLAYTEST` is defined for the dev and probe bundles, so the shipping
// build does not contain this file at all.
#if PHOTONZ_PLAYTEST
import Foundation

/// How many times a view body ran since the last reset.
///
/// This exists because "the layers list builds only the rows you can see" is
/// not something a screenshot can show and not something a timing can prove:
/// once the per-row cost is small, a hundred wasted rows and five useful ones
/// look the same on a stopwatch. Counting the bodies says it outright.
@MainActor
final class ViewBuildMeter {
    static let shared = ViewBuildMeter()

    /// The things worth counting. One case per list that claims to be lazy.
    enum Subject: String, CaseIterable {
        case layersRow
        /// Every time the layers list asks for a picture of a layer. The list
        /// asks only for the rows near the screen, and "near" is not something
        /// a screenshot can show either.
        case layerThumbnail
        /// The whole editor's body: canvas, tool bar, zoom bar, dock, the lot.
        /// Picking a layer must not run this. It used to, and re-measuring
        /// every stack in the window is where the click's 50ms went
        /// (`layer-pick-latency-walk`).
        case editorBody
        /// The dock's body: which sections exist and in what order.
        case inspectorPanel
        /// The layers list's body, which is one step under the dock's.
        case layersList
        /// One colour row of the right hand panel: the chip, the word and the
        /// saved-colours menu beside them. Clicking from one shape to an
        /// identical one must not build a single one of them, and a stopwatch
        /// cannot tell "rebuilt cheaply" from "not rebuilt" once the row is
        /// small (`ColorStyleRow`).
        case colorRow
    }

    private var counts: [Subject: Int] = [:]

    /// Called from a view body. Cheap on purpose: a dictionary bump, and only
    /// in a build that carries the harness at all.
    func built(_ subject: Subject) {
        counts[subject, default: 0] += 1
    }

    /// A line per pass, for the subjects where the COUNT is the question and
    /// the answer is "why four". `report` keeps counting; this says what was
    /// different about each one.
    private var trace: [String] = []

    func note(_ line: String) { if trace.count < 12 { trace.append(line) } }

    var traced: String { trace.isEmpty ? "" : "passes: " + trace.joined(separator: " | ") }

    func reset() { counts.removeAll(); trace.removeAll() }

    func count(_ subject: Subject) -> Int { counts[subject] ?? 0 }

    /// "layer rows built 6" — the phrase a walk's log line carries.
    var report: String {
        counts.isEmpty
            ? "no view bodies counted"
            : counts.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue) bodies \($0.value)" }
                .joined(separator: ", ")
    }
}
#endif
