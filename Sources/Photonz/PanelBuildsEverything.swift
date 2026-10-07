import Observation

/// The way a scripted walk gets every dock section built at once.
///
/// On a video the dock leaves a section that arrives well below the fold
/// unbuilt until somebody scrolls near it (`PanelBodyReach`). A person finds
/// such a control by scrolling, which builds it. A walk finds controls by
/// name, so a control in a waiting section is simply not there yet. When a
/// walk's look for something comes up empty while sections are waiting, the
/// harness turns this on and looks again; the dock then builds everything, as
/// it did before, for the rest of that walk.
///
/// Observed, so turning it on redraws the dock. Never turned on in the
/// shipping app: nothing but the walk harness writes `isOn`.
@MainActor @Observable
final class PanelBuildsEverything {
    static let shared = PanelBuildsEverything()

    var isOn = false

    /// Whether any section is waiting right now. Written by the dock on every
    /// pass, so deliberately not watched.
    @ObservationIgnored var somethingWaits = false
    /// Whether rows inside a section have been let go this walk
    /// (`PanelRowsArrival`).
    @ObservationIgnored var rowsHaveWaited = false

    /// Whether the dock may leave anything unbuilt for being out of sight:
    /// the switch is on, no guide is running (a guide points at controls, and
    /// one not built yet is nothing to point at), and no walk has asked for
    /// everything.
    static var dockMayWait: Bool {
        Experiments.shared.panelBuildsWhatYouSeeEnabled
            && !TutorialController.shared.isRunning && !shared.isOn
    }

    /// Turns it on when there is something to build. True when it did, so the
    /// caller knows another look is worth it.
    @discardableResult
    func buildWhatWaits() -> Bool {
        guard somethingWaits || rowsHaveWaited, !isOn else { return false }
        isOn = true
        return true
    }
}
