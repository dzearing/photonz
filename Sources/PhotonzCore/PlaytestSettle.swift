import Foundation

/// How long a walk's `wait` step actually waits.
///
/// A `wait` in a walk means "let the editor finish what that last step
/// started". Whoever wrote it picked a round number that was comfortably long
/// enough, and on this machine the editor is usually finished long before the
/// number is up. Across the 247 walks in `Scripts/playtest` those numbers add
/// up to 31 minutes of pure sleeping, which was more than half the whole run
/// (measured 2026-09-07).
///
/// So a wait watches instead of counting: it ends as soon as the app has been
/// quiet for a beat, never before `floor` — one run loop turn has to happen
/// whatever else is true — and never after the seconds the walk asked for, so
/// nothing waits LONGER than it used to.
///
/// "Quiet" is two things together, both supplied by the caller: the main run
/// loop has had almost nothing to do, and nothing on the window is still
/// animating. Either one alone would lie. An animation the render server is
/// running on its own leaves the main thread idle, and a window mid-fade with
/// no work queued is not settled.
public struct PlaytestSettle: Sendable, Equatable {
    /// The shortest a wait can ever be, so one turn of the run loop always
    /// happens after the step that came before it.
    public var floor: Double
    /// How long the app has to stay quiet before the wait is over.
    public var quiet: Double
    /// How long to nap between looks.
    public var slice: Double
    /// Main thread work inside one slice that still counts as quiet. The
    /// harness's own looking costs a little, and so does a run loop that woke
    /// up for a timer and went straight back to sleep.
    public var busyBudget: Double
    /// Off means the old behaviour exactly: sleep the number the walk asked
    /// for and nothing else.
    public var watches: Bool

    public init(floor: Double, quiet: Double, slice: Double, busyBudget: Double, watches: Bool) {
        self.floor = floor
        self.quiet = quiet
        self.slice = slice
        self.busyBudget = busyBudget
        self.watches = watches
    }

    /// What the suite runs. `quiet` is deliberately longer than one 60Hz frame
    /// so a redraw that is merely between frames cannot read as finished.
    public static let standard = PlaytestSettle(floor: 0.06, quiet: 0.09, slice: 0.03,
                                                busyBudget: 0.002, watches: true)

    /// Every wait on the clock, as walks ran before 2026-09-07. This is what a
    /// walk that turns flaky gets re-run under, to prove whether the pacing is
    /// what changed under it.
    public static let off = PlaytestSettle(floor: 0, quiet: 0, slice: 0.03,
                                           busyBudget: 0, watches: false)

    /// The pace by name, as `PHOTONZ_PLAYTEST_PACE` gives it. Anything that is
    /// not a request for the old clock is the standard pace, so a typo slows a
    /// run down rather than changing what it proves.
    public static func named(_ name: String?) -> PlaytestSettle {
        switch name?.lowercased() {
        case "full", "off", "clock": .off
        default: .standard
        }
    }

    /// True when a wait that has run for `waited`, out of the `asked` the walk
    /// wrote down, with `quiet` seconds of quiet behind it, may end now.
    public func isOver(waited: Double, asked: Double, quiet: Double) -> Bool {
        if waited >= asked { return true }
        guard watches else { return false }
        return waited >= floor && quiet >= self.quiet
    }

    /// How long to nap before looking again, never past what the walk asked
    /// for.
    public func nap(waited: Double, asked: Double) -> Double {
        max(0, min(slice, asked - waited))
    }

    /// The run of quiet after one more slice: longer when the app did nothing
    /// worth counting, back to nothing when it did.
    public func quiet(after quiet: Double, slice: Double, busy: Double, restless: Bool) -> Double {
        if restless || busy > busyBudget { return 0 }
        return quiet + slice
    }
}
