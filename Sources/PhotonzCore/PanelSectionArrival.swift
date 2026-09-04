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
    public static func showing(target: [String], mounted: [String]) -> [String] {
        guard !mounted.isEmpty else { return target }
        let have = Set(mounted)
        return target.filter { have.contains($0) }
    }

    /// True when the selection has asked for a section the dock has not built,
    /// so the dock owes it one more pass. False the moment everything asked
    /// for is on screen, which is how the panel can never settle part-built.
    public static func isWaiting(target: [String], mounted: [String]) -> Bool {
        showing(target: target, mounted: mounted) != target
    }
}
