import CoreGraphics
import Foundation

/// Whether a scripted walk could really press a control where it is sitting,
/// and when it could not, which of three different things is in the way.
///
/// A walk presses by putting the pointer in the middle of a control's box, so
/// a control the panel has scrolled half off is a trap: the sliver still
/// showing is inside the window, the press aimed at the middle lands past an
/// edge, and the walk is told it worked while nothing changed. So the whole
/// box has to be showing before a press may land.
///
/// The judgement used to be made twice, in two different geometries, and the
/// two could disagree: `reveal` worked out how far to scroll from the strip of
/// window the scrolling areas around a control can park it in, while the
/// verdict on whether it had arrived came from AppKit's own `visibleRect`.
/// When those two disagreed a reveal scrolled nothing, decided nothing more
/// could be done, and failed a control that a photograph of the same instant
/// shows sitting in the open (`queue/tasks/…/a-walk-can-reach-a-control-…`).
/// One answer, computed once, cannot disagree with itself: everything here is
/// plain rectangle arithmetic so it can be tested without a window.
///
/// Every rectangle is in the window's own coordinates, which run bottom up: a
/// bigger y is FURTHER UP the window, so a row below the fold has the smaller
/// y and is `.below`.
public enum PlaytestReach {

    /// Which way a control hangs out of the area meant to be holding it.
    public enum Side: String, Sendable, Equatable, Codable {
        case above, below, left, right
    }

    /// What is keeping the control from being pressable, in the order the
    /// three are worth telling apart. A scroll fixes the second and nothing
    /// else; the first needs a bigger window or a collapsed section; the third
    /// is the app doing something a walk cannot undo, and is the one that used
    /// to be reported for all three.
    public enum Cutter: String, Sendable, Equatable, Codable {
        /// It is off the window altogether, and no scrolling area holds it.
        case theWindow
        /// A scrolling area it sits inside has it past its own edge. This is
        /// the one a `reveal` can do something about.
        case aScroller
        /// Inside the window, inside everything that scrolls around it, and
        /// still not wholly showing: something that does not scroll is over it
        /// or cutting it.
        case somethingStill
    }

    /// The whole answer to "why not", ready to be turned into a sentence.
    public struct Problem: Sendable, Equatable, Codable {
        public let cutter: Cutter
        public let side: Side
        /// How many points of the control are past that edge.
        public let points: Double

        public init(cutter: Cutter, side: Side, points: Double) {
            self.cutter = cutter
            self.side = side
            self.points = points
        }
    }

    /// Sub-point overhang is arithmetic, not a hidden control.
    ///
    /// A box is laid out in fractions of a point and the strip it is measured
    /// against is too, so a row drawn exactly against the bottom of its list
    /// can come back a third of a point past it. Judged strictly, that row is
    /// out of reach, the reveal scrolls two points to fix it, the list is
    /// already at its end and cannot, and a walk fails on a control that is
    /// entirely on screen. Nothing a person could see hides in a third of a
    /// point.
    public static let slack: Double = 1.0

    /// How far `box` hangs outside `frame`, and which way, or nil when it is
    /// inside. The biggest overhang wins, because that is the one a scroll has
    /// to close.
    ///
    /// A frame with nothing left of it — a list carried off the window
    /// entirely, so its own viewport is empty — shows no part of anything, and
    /// says so as the whole height of the box.
    public static func overhang(of box: CGRect, in frame: CGRect,
                                slack: Double = PlaytestReach.slack) -> (side: Side, points: Double)? {
        guard !frame.isNull, !frame.isEmpty else {
            return (.below, max(box.height, 1))
        }
        guard !box.isNull else { return nil }
        let measured = box.isEmpty ? CGRect(origin: box.origin, size: CGSize(width: 1, height: 1)) : box
        var worst: (side: Side, points: Double)?
        func consider(_ side: Side, _ points: Double) {
            guard points > slack else { return }
            if let already = worst, already.points >= points { return }
            worst = (side, points)
        }
        consider(.above, measured.maxY - frame.maxY)
        consider(.below, frame.minY - measured.minY)
        consider(.right, measured.maxX - frame.maxX)
        consider(.left, frame.minX - measured.minX)
        return worst
    }

    /// Whether a press could land on the control right now.
    ///
    /// - Parameters:
    ///   - box: the control's own box, in window coordinates.
    ///   - window: the window's content, in the same coordinates.
    ///   - scrollStrip: the window narrowed by every scrolling area the
    ///     control really sits inside, innermost included. This is exactly the
    ///     part of the window a scroll could park it in, so it is also what
    ///     `reveal` measures its distance against.
    ///   - visible: what AppKit says is left of the control after everything
    ///     above it in the view tree has had its say, or `.infinite` when
    ///     nothing is known to clip it.
    public static func problem(box: CGRect, window: CGRect,
                               scrollStrip: CGRect, visible: CGRect = .infinite,
                               slack: Double = PlaytestReach.slack) -> Problem? {
        // The strip is the window already narrowed by every scroller, so one
        // measurement answers both: what makes it a WINDOW problem rather than
        // a scroller's is that the window cuts it too and no scroller was
        // narrowing anything in the first place.
        if let out = overhang(of: box, in: scrollStrip, slack: slack) {
            let windowCutsItToo = overhang(of: box, in: window, slack: slack) != nil
            let nothingScrolls = scrollStrip.contains(window)
            let cutter: Cutter = windowCutsItToo && nothingScrolls ? .theWindow : .aScroller
            return Problem(cutter: cutter, side: out.side, points: out.points)
        }
        if let out = overhang(of: box, in: visible, slack: slack) {
            return Problem(cutter: .somethingStill, side: out.side, points: out.points)
        }
        return nil
    }

    /// What the walk prints. Plain words, naming the control, saying which of
    /// the three it is and by how much, and ending with what would fix it.
    ///
    /// `tried` is whether a scroll has already been attempted and got nowhere.
    /// Without it the one sentence would have to either promise a `reveal`
    /// would help, which is a lie to the reveal that just failed, or announce
    /// a scroller has nothing left to give, which is a lie to the listing of a
    /// panel nobody has scrolled yet.
    public static func sentence(_ problem: Problem, control name: String,
                                tried: Bool = false) -> String {
        let amount = "\(Int(problem.points.rounded()))pt"
        let past: String
        switch problem.side {
        case .above: past = "above the top of"
        case .below: past = "below the bottom of"
        case .left: past = "past the left edge of"
        case .right: past = "past the right edge of"
        }
        switch problem.cutter {
        case .theWindow:
            return "\"\(name)\" is \(amount) \(past) the window itself, and nothing around it "
                + "scrolls, so no step could bring it in. Make the window taller, or collapse a "
                + "section above it."
        case .aScroller:
            let head = "\"\(name)\" is \(amount) \(past) the part of its own scrolling area that "
                + "is on screen"
            return tried
                ? head + ", and that area would not scroll any further. The window may be too "
                    + "short for the section it is in."
                : head + ", so a press would land on the panel's edge instead. A \"reveal\" step "
                    + "brings it in."
        case .somethingStill:
            return "\"\(name)\" is inside the window and inside everything that scrolls around it, "
                + "and \(amount) of it is still hidden \(past) something that does not scroll. No "
                + "step can fix that: something in the window is cutting it off."
        }
    }
}
