import CoreGraphics
import Foundation

/// What a drag remembers about the snap it already caught.
///
/// The rule this exists to keep is one sentence long: **a snap that is showing
/// is a snap you get.** A magnet reaches a fixed distance, so a pointer sitting
/// on that distance is a coin toss — one event inside, the next outside, the
/// edge taken and dropped and taken again while the hand barely moves. That is
/// the flicker: not a bug in any one snap, but the absence of any memory
/// between them.
///
/// So a drag carries the lines it is standing on, and a caught line keeps the
/// point until the pointer has moved clearly away from it: `releaseFactor`
/// times as far as it took to catch. Between the catching distance and the
/// letting-go distance nothing can change the answer, which is exactly the
/// room a wobbling hand needs.
///
/// The held value IS the guide being drawn, which is what makes the promise
/// literal rather than approximate: the yellow line on screen is the state.
public struct SnapHold: Equatable, Sendable {
    /// The vertical guide the drag is standing on, if any.
    public var x: CGFloat?
    /// The horizontal guide the drag is standing on, if any.
    public var y: CGFloat?
    /// ⌘ was held at some point during this drag. It latches on and never off,
    /// the way ⌥ latches a copy drag: a key released a moment early is not a
    /// change of mind, and a magnet that came back mid-drag would move the
    /// thing you were already placing by hand.
    public var isFree: Bool

    public init(x: CGFloat? = nil, y: CGFloat? = nil, isFree: Bool = false) {
        self.x = x
        self.y = y
        self.isFree = isFree
    }

    /// Nothing caught, nothing freed: what every drag starts from.
    public static let none = SnapHold()

    /// How much farther than the catch the pointer must travel before the
    /// caught line lets go. Two means: caught within 8 screen points, kept
    /// until 16 — a wobble can never lose you a line you are standing on.
    public static let releaseFactor: CGFloat = 2

    /// Remember what this event's snap caught, so the next one can keep it.
    /// A freed drag catches nothing, whatever it is told.
    public mutating func caught(x: CGFloat?, y: CGFloat?) {
        guard !isFree else { return }
        self.x = x
        self.y = y
    }

    /// ⌘: drop every magnet now and keep them off for the rest of the drag.
    public mutating func free() {
        x = nil
        y = nil
        isFree = true
    }

    /// Whether `line` still holds the drag when the pointer's own answer for
    /// that axis is `value` and the magnet's reach is `tolerance`.
    public static func keeps(_ line: CGFloat?, at value: CGFloat, tolerance: CGFloat) -> Bool {
        guard let line else { return false }
        return abs(line - value) <= tolerance * releaseFactor
    }
}
