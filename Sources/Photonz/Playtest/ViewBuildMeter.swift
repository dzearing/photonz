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
    enum Subject: String {
        case layersRow
    }

    private var counts: [Subject: Int] = [:]

    /// Called from a view body. Cheap on purpose: a dictionary bump, and only
    /// in a build that carries the harness at all.
    func built(_ subject: Subject) {
        counts[subject, default: 0] += 1
    }

    func reset() { counts.removeAll() }

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
