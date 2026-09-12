import Foundation

/// Whether a timing measurement is allowed to fail the build.
///
/// Set `PHOTONZ_PERF_GATE=report` and every timing check still runs and still
/// prints its numbers, but none of them assert. The release workflow does
/// exactly that: v0.15.0 failed to publish twice on a shared runner that was
/// several times slower than the machine the app is developed on, with nothing
/// actually slower in the app. Regressions are caught on every push and pull
/// request, where the same budgets do gate; a stopwatch reading taken on hired
/// hardware is not a reason to hold a release.
///
/// `Tests/PhotonzRenderTests/MachineSpeed.swift` reads the same variable for
/// the render budgets in its own target.
enum PerfGate {
    static func gates(mode: String?) -> Bool {
        (mode ?? "").lowercased() != "report"
    }

    static var isOn: Bool {
        gates(mode: ProcessInfo.processInfo.environment["PHOTONZ_PERF_GATE"])
    }
}
