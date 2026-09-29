import CoreGraphics
import Foundation

/// Which way two fingers are spreading (or squeezing) on the trackpad.
public enum TimelinePinchDirection: Hashable, Sendable {
    case horizontal, vertical, diagonal

    /// Side to side opens out time, up and down grows the rows, on the slant
    /// both (user 2026-09-28).
    public var axes: TimelinePinchAxes {
        switch self {
        case .horizontal: .time
        case .vertical: .rows
        case .diagonal: .both
        }
    }
}

/// **Which way a pinch on the timeline zooms, read off the fingers**
/// (`TimelinePinchSteerTests`).
///
/// User 2026-09-28: "if I'm pinch zooming vertically, it just makes the rows
/// bigger. If I'm pinch zooming horizontally it changes the scale." A pinch
/// arrives as one number, how far it has magnified, so the way the fingers
/// moved has to come from the two touches themselves: the change in how far
/// apart they are across and down, since they landed.
///
/// The way is picked once, near the start, and held until the fingers lift,
/// so a pinch never flips from time to rows half way through. Until it is
/// picked the pinch's first nudges are held back rather than guessed at, and
/// handed over all at once when it is: nothing ever zooms the wrong way. With
/// no touches to read (a mouse, or touches that never came) it gives up
/// waiting after a few percent and zooms both, as a pinch always did.
public struct TimelinePinchSteer: Hashable, Sendable {

    /// How far the fingers' spread has to change, in the trackpad's points
    /// (a seventy-second of an inch), before its direction counts: about two
    /// millimetres.
    public static let decidingSpread: CGFloat = 5
    /// How much a pinch may magnify with no direction to go on before it
    /// stops waiting for one: about five percent, either way.
    public static let patience: Double = 0.05
    /// Within this many degrees of flat is sideways, of upright is up and down.
    public static let leeway: Double = 35

    /// The two fingers when they landed, and where they are now.
    public private(set) var start: [CGPoint]?
    public private(set) var latest: [CGPoint]?
    /// What this pinch zooms, once it is known.
    public private(set) var decided: TimelinePinchAxes?
    /// The magnification held back while the way is not known yet.
    public private(set) var held: Double = 1

    public init() {}

    /// Which way the fingers moved from `start` to `now`, or nil while they
    /// have moved too little to say (or are not two fingers).
    public static func direction(from start: [CGPoint], to now: [CGPoint],
                                 atLeast minimum: CGFloat = decidingSpread) -> TimelinePinchDirection? {
        guard start.count == 2, now.count == 2 else { return nil }
        // The change in how far apart they are, across and down. Which finger
        // is which, and the slant they happen to sit at, do not matter.
        let across = abs(now[1].x - now[0].x) - abs(start[1].x - start[0].x)
        let down = abs(now[1].y - now[0].y) - abs(start[1].y - start[0].y)
        guard hypot(across, down) >= minimum else { return nil }
        let degrees = atan2(Double(abs(down)), Double(abs(across))) * 180 / .pi
        if degrees <= leeway { return .horizontal }
        if degrees >= 90 - leeway { return .vertical }
        return .diagonal
    }

    /// The fingers on the trackpad now, in its points. Two fingers are a pinch
    /// to read; any other count (lifted, one, a third) forgets them.
    public mutating func touched(_ points: [CGPoint]) {
        guard points.count == 2 else {
            start = nil
            latest = nil
            return
        }
        if start == nil { start = points }
        latest = points
    }

    /// A pinch begins: whatever the last one picked is forgotten.
    public mutating func begin() {
        decided = nil
        held = 1
    }

    /// The pinch magnified by `factor` since its last nudge. Returns what to
    /// zoom and by how much, or nil while the nudge is held back. `forced` is
    /// ⌥ (time) or ⇧ (rows) held down, which always wins.
    public mutating func magnified(by factor: Double,
                                   forced: TimelinePinchAxes?) -> (axes: TimelinePinchAxes, factor: Double)? {
        guard factor > 0, factor.isFinite else { return nil }
        if let forced { return release(to: forced, factor: factor) }
        if let decided { return (decided, factor) }
        held *= factor
        if let start, let latest, let way = Self.direction(from: start, to: latest) {
            decided = way.axes
        } else if abs(log(held)) >= Self.patience {
            decided = (start.flatMap { from in latest.flatMap { Self.direction(from: from, to: $0, atLeast: 1) } })?
                .axes ?? .both
        }
        guard let decided else { return nil }
        return release(to: decided, factor: 1)
    }

    /// The fingers lift. Anything still held back is handed over, the way the
    /// fingers had begun to go or both, so a small pinch is never lost.
    @discardableResult
    public mutating func end() -> (axes: TimelinePinchAxes, factor: Double)? {
        defer { begin() }
        guard abs(held - 1) > 1e-12 else { return nil }
        let way = decided
            ?? start.flatMap { from in latest.flatMap { Self.direction(from: from, to: $0, atLeast: 1) } }?.axes
            ?? .both
        return (way, held)
    }

    private mutating func release(to axes: TimelinePinchAxes, factor: Double) -> (axes: TimelinePinchAxes, factor: Double) {
        let total = held * factor
        held = 1
        return (axes, total)
    }
}

extension TimelinePinchAxes {
    /// What ⌥ and ⇧ insist on, or nil with neither down, when the fingers
    /// choose (`TimelinePinchSteer`).
    public static func forced(option: Bool, shift: Bool) -> TimelinePinchAxes? {
        guard option || shift else { return nil }
        return TimelinePinchAxes(option: option, shift: shift)
    }
}
