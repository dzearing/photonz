/// When a section the dock stops showing is pulled down.
///
/// Showing and building are different things. A section the selection no
/// longer asks for leaves the SCREEN in the click's own pass, as it always
/// has (`PanelSectionArrival` says why a section must never stand over
/// something that is not there). Pulling it down is the expensive half: every
/// text field, slider and dropdown in it leaves AppKit and the accessibility
/// tree one at a time. A click on a clip's cut takes five to nine of a clip's
/// sections away at once, and in `clip-click-cost-walk` (2026-10-08) keeping
/// them built took the cut click from about 52ms to about 40.
///
/// So a section that leaves while the pick stays on the same thing lingers,
/// unseen and out of the dock's layout, until the next pass pulls it down
/// (`release`). The pick staying put is the whole condition: what a lingering
/// section reads is still true of the thing picked, so it lingers as it was.
/// When the pick moves (Undo putting it back to nothing, a click on another
/// layer) every section the selection no longer wants goes at once, as before.
///
/// Section ids and the pick are plain strings so this stays free of the
/// app's view layer.
public struct PanelSectionDeparture: Sendable, Equatable {
    /// The sections that have left the screen and are still built, oldest
    /// first, each in the order it stood.
    public private(set) var lingering: [String] = []
    private var drawn: [String] = []
    private var pick: String?

    public init() {}

    /// Notes the sections the dock shows this pass and returns those that
    /// linger. Safe to call more than once a pass.
    ///
    /// - Parameters:
    ///   - sections: what the dock shows this pass, in order.
    ///   - pick: what the panel is describing, nil for nothing.
    ///   - lingers: off, nothing ever lingers.
    @discardableResult
    public mutating func draw(_ sections: [String], pick: String?, lingers: Bool = true) -> [String] {
        let shown = Set(sections)
        if lingers, pick == self.pick {
            lingering.removeAll { shown.contains($0) }
            let already = Set(lingering)
            lingering += drawn.filter { !shown.contains($0) && !already.contains($0) }
        } else {
            lingering = []
        }
        drawn = sections
        self.pick = pick
        return lingering
    }

    /// True while something lingers, so the dock owes a pass that pulls it down.
    public var isHolding: Bool { !lingering.isEmpty }

    /// Lets every lingering section go: the next pass pulls them down.
    public mutating func release() {
        lingering = []
    }
}
