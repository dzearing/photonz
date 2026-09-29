/// When the sections of the right dock are allowed to appear.
///
/// Clicking a layer after nothing was selected is the slowest click in the
/// app, because the whole right hand panel has to be built from nothing:
/// Position & Size, Layout, Component, Effects and Shadow all arrive together,
/// with their text fields, sliders and colour wells, and the click waits for
/// every one of them before anything on screen moves. Measured on 2026-09-04
/// that click cost about half again as much main-thread time as a click that
/// only moves the selection between two things the panel already describes.
///
/// The fix is not to build less, it is to build it a beat later. A section
/// that the dock already has answers in the click's own pass; a section that
/// has to be made from nothing waits one run-loop pass, so the canvas gets its
/// handles and its highlight on screen first and the panel catches up behind
/// them. One pass is about a frame, so nobody sees the gap; what they see is a
/// click that stops feeling like it is thinking.
///
/// Sections leaving is the other half, and it is not symmetrical. A section
/// goes the instant the selection stops wanting it: a Shadow section left
/// standing over nothing for a frame would be describing something that is not
/// there, which is worse than a panel that is briefly shorter.
///
/// Section ids are plain strings here so this stays free of the app's view
/// layer; the dock passes its own section ids through.
public enum PanelSectionArrival {

    /// The sections the dock may show in THIS pass.
    ///
    /// - Parameters:
    ///   - target: the sections the current selection asks for, in the order
    ///     the dock wants to draw them.
    ///   - mounted: the sections the dock already has built.
    /// - Returns: `target`, in `target`'s own order, minus anything that is not
    ///   mounted yet. Order always comes from `target` so that re-ordering the
    ///   dock by hand is never a pass behind the drag.
    ///
    /// With nothing mounted at all this is the whole of `target`: a window
    /// opening has no previous frame to protect, and holding everything back
    /// would be a visible flash of an empty dock.
    ///
    /// When nothing in `target` is mounted, the top section of it answers at
    /// once and the rest follow a pass at a time (`next`). Holding all of it
    /// back is an empty dock, and one that shares nothing with the last pass
    /// would leave nothing mounted and so nothing counted as waiting. It never
    /// happened while the layers list was in every dock; on a video the
    /// timeline stands in for the list (`TimelineIsTheLayerList`), and picking
    /// a cut after a clip swaps every section at once.
    public static func showing(target: [String], mounted: [String]) -> [String] {
        guard !mounted.isEmpty else { return target }
        let have = Set(mounted)
        let built = target.filter { have.contains($0) }
        return built.isEmpty ? Array(target.prefix(1)) : built
    }

    /// True when the selection has asked for a section the dock has not built,
    /// so the dock owes it one more pass. False the moment everything asked
    /// for is on screen, which is how the panel can never settle part-built.
    public static func isWaiting(target: [String], mounted: [String]) -> Bool {
        showing(target: target, mounted: mounted) != target
    }

    /// What the dock has built after one catch-up pass: what it shows now and
    /// the highest section still waiting, never more than one.
    ///
    /// All the waiting sections used to arrive in a single pass. Picking a
    /// caption after the canvas asks for six the dock has never built, and
    /// building them together held the window for a tenth of a second
    /// (2026-09-24, `caption-pick-answers-at-once-walk`); one at a time, top
    /// down, every pass stays short and the section you are looking at is
    /// never the one kept waiting.
    public static func next(target: [String], mounted: [String]) -> [String] {
        let shown = showing(target: target, mounted: mounted)
        let have = Set(shown)
        guard let arriving = target.first(where: { !have.contains($0) }) else { return target }
        return target.filter { have.contains($0) || $0 == arriving }
    }
}

/// What the dock has built, pass to pass, over `PanelSectionArrival`.
///
/// One case starts from nothing on purpose: a dock SLIDING INTO a window that
/// is already up (Edit mode arriving on a recording opened in View). There is
/// a previous frame to protect there, the picture and the transport, and the
/// panel is still mostly off the window's edge, so its first pass builds no
/// section at all and they follow one pass at a time while it moves. Building
/// them all in the pass that started the slide held a five minute captioned
/// recording's window for about 190ms (2026-09-28).
public struct DockArrival: Sendable, Equatable {
    public private(set) var mounted: [String] = []
    /// Nothing built yet, and nothing to be built until the next pass.
    public private(set) var isHeld: Bool

    public init(slidingIn: Bool = false) {
        isHeld = slidingIn
    }

    /// The sections the dock may draw this pass, noted for the next one.
    public mutating func showing(_ target: [String]) -> [String] {
        guard !isHeld else { return [] }
        mounted = PanelSectionArrival.showing(target: target, mounted: mounted)
        return mounted
    }

    /// True when the dock owes `target` another pass.
    public func isWaiting(for target: [String]) -> Bool {
        isHeld ? !target.isEmpty : PanelSectionArrival.isWaiting(target: target, mounted: mounted)
    }

    /// Let the next section in: the top one, when the dock was held.
    public mutating func allowNext(_ target: [String]) {
        if isHeld {
            isHeld = false
            mounted = Array(target.prefix(1))
        } else {
            mounted = PanelSectionArrival.next(target: target, mounted: mounted)
        }
    }
}
