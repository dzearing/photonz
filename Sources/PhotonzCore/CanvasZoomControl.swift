import CoreGraphics

/// The small zoom control that floats in the canvas's bottom right corner
/// while somebody is zooming, and goes away by itself when they stop (Next).
///
/// The user, 2026-10-07: "when I zoom in, I would like a zoom toolbar to
/// appear briefly, and then fade out after 5s of not zooming, or fade back in
/// on hover. I want to be able to quickly double click the zoom to get to
/// actual size (100%)". It is the one zoom control on screen, and it is not in
/// the tool bar (zoom is not a tool, 2026-09-29): it is canvas furniture that
/// is only there while the zoom is what you are doing (UX-PATTERNS, the
/// placement contract's named exceptions).
///
/// Two pure halves, so both are tested: `Clock` says whether it is up at a
/// moment, `frame` says where it sits.
public enum CanvasZoomControl {
    /// How long it stays after the last zoom, or after the pointer leaves it.
    public static let holdSeconds: Double = 5
    /// How quickly it comes up.
    public static let fadeInSeconds: Double = 0.2
    /// How quickly it goes.
    public static let fadeOutSeconds: Double = 0.3
    /// How far in from the canvas's right and bottom edges it floats: the one
    /// corner inset every piece of corner chrome shares.
    public static let inset: CGFloat = EditorChromeLayout.cornerInset
    /// What it takes when nothing has measured it yet, generous on purpose:
    /// over-reserving only makes the measure legend pick another corner.
    public static let reservedSize = CGSize(width: 176, height: 34)

    /// What keeps it up other than the clock.
    public enum Hold: Hashable, Sendable {
        /// The pointer is resting on its spot.
        case pointer
        /// Its zoom stops menu is open.
        case menu
    }

    /// Whether the control is up, as a function of time.
    public struct Clock: Equatable, Sendable {
        /// When the five seconds last started: a zoom, a press on one of its
        /// buttons, or the last hold letting go.
        public private(set) var lastActivity: Double?
        /// What is holding it up regardless of the clock.
        public private(set) var holds: Set<Hold> = []

        public init() {}

        /// The zoom changed, from anywhere: a pinch, a key, a menu row.
        public mutating func zoomed(at time: Double) { lastActivity = time }

        /// One of its own buttons was used.
        public mutating func used(at time: Double) { lastActivity = time }

        /// Something started or stopped holding it up. Letting go starts the
        /// five seconds from the letting go, so a long rest on it does not end
        /// with it vanishing the moment the pointer comes off.
        public mutating func hold(_ hold: Hold, _ on: Bool, at time: Double) {
            if on {
                holds.insert(hold)
            } else if holds.remove(hold) != nil, holds.isEmpty {
                lastActivity = time
            }
        }

        /// Whether it is up at `time`.
        public func isShown(at time: Double) -> Bool {
            if !holds.isEmpty { return true }
            guard let lastActivity else { return false }
            return time < lastActivity + CanvasZoomControl.holdSeconds
        }

        /// When it will go if nothing else happens, or nil while something is
        /// holding it up or it has never been up.
        public var hidesAt: Double? {
            guard holds.isEmpty else { return nil }
            return lastActivity.map { $0 + CanvasZoomControl.holdSeconds }
        }
    }

    /// Where a control of `size` sits in a canvas of `canvasSize`, top-left
    /// origin: the bottom right corner, `inset` in, lifted a stack gap clear
    /// of anything in `avoiding` that it would otherwise cover or touch (the
    /// floating tool bar and the tool settings capsule, which on a narrow
    /// canvas reach the corner). Never above the canvas's top edge.
    public static func frame(canvasSize: CGSize, size: CGSize, avoiding: [CGRect]) -> CGRect {
        let gap = EditorChromeLayout.toolBarStackGap
        var frame = CGRect(x: canvasSize.width - inset - size.width,
                           y: canvasSize.height - inset - size.height,
                           width: size.width, height: size.height)
        // Each pass lifts it over the highest thing it is in the way of, and
        // lifting can only bring a higher one into the way, so as many passes
        // as there are things is always enough.
        for _ in 0...avoiding.count {
            let near = frame.insetBy(dx: -gap, dy: -gap)
            let inTheWay = avoiding.filter { !$0.isEmpty && near.intersects($0) }
            guard let top = inTheWay.map(\.minY).min() else { break }
            frame.origin.y = top - gap - size.height
        }
        frame.origin.y = max(0, frame.origin.y)
        return frame
    }

    /// The slot it keeps for itself whether or not it is up, so the measure
    /// legend never parks where it is about to appear.
    public static func reservedFrame(canvasSize: CGSize, avoiding: [CGRect]) -> CGRect {
        frame(canvasSize: canvasSize, size: reservedSize, avoiding: avoiding)
    }
}
