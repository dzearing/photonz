/// One piece of the dock per run-loop pass.
///
/// The right hand panel fills in a piece at a time so no single pass has to
/// build all of it: the dock lets one section in per pass
/// (`PanelSectionArrival`), and a big section brings its later rows a pass or
/// more after itself (`PanelRowsArrival` in the app). Each paces itself, but
/// neither knew about the other, so a section and another section's rows
/// often landed in the same pass, and that pass cost what the two would have
/// cost apart plus the pass itself: picking a clip from nothing on the 6
/// minute reference edit while it played, the passes where two pieces landed
/// together were the 46 to 73 ms ones, against 15 to 36 ms for each piece on
/// its own (`a-long-edit-with-transitions-plays-scrubs-and-ed`, 2026-11-16).
///
/// So every piece asks for its pass first. The first to ask in a pass gets
/// it; any other waits for the next pass and asks again. Order is first come,
/// which is top down in practice: a section's rows wait on the section, which
/// arrives before anything under it.
public struct PanelLandingTurns: Sendable, Equatable {
    /// The pass a piece last landed in, and how many passes after it stay
    /// quiet.
    private var landedIn: Int?
    private var rest = 0

    public init() {}

    /// Whether a piece may land in `pass`, and if so the pass is taken, with
    /// `restAfter` passes after it kept free of any other piece.
    ///
    /// Rest is for a piece full of controls. SwiftUI pays for what a pass
    /// adds twice: building it, and a pass later working out focus and
    /// accessibility for every control in it. A section landing in that
    /// second pass paid for both, and was the longest pass left once two
    /// pieces no longer shared one (the Fades or Sound section right after a
    /// shadow's slider rows, 40 to 51 ms, 2026-11-16).
    public mutating func claim(pass: Int, restAfter: Int = 0) -> Bool {
        if let landedIn {
            let since = pass &- landedIn
            guard since < 0 || since > rest else { return false }
        }
        landedIn = pass
        rest = max(0, restAfter)
        return true
    }
}
