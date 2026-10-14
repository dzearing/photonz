import Foundation

/// The stretch of values an open value graph shows, top to bottom (task
/// `the-value-graph-zooms-its-value-range-and-the-ti`).
///
/// A graph opens fitted to its own values (`KeyGraph.low`, `high`). A person
/// working on a small change zooms it taller or shorter with ⌥ and the wheel
/// over it, about the value under the pointer, the way ⌥ and the wheel zoom
/// time about the moment under it; a double click on the range's readings
/// goes back to the fit.
public struct GraphValueRange: Hashable, Sendable, Codable {
    public var low: Double
    public var high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }

    public var span: Double { high - low }

    /// How close in a graph goes: a hundredth of its fit.
    public static let closest = 100.0
    /// How far out: twenty times its fit.
    public static let furthest = 20.0

    /// The value `fraction` of the way down from the top.
    public func value(atFractionFromTop fraction: Double) -> Double {
        high - fraction * span
    }

    /// How far down from the top `value` is drawn, nought to one inside.
    public func fraction(of value: Double) -> Double {
        span > 1e-12 ? (high - value) / span : 0.5
    }

    /// This range zoomed by `factor` (above one closer in, a narrower range)
    /// about `anchor`, which keeps its place on screen. Never closer in than a
    /// hundredth of `fit` nor further out than twenty fits; a fit with no
    /// height (one value all along) is measured against the value itself.
    public func zoomed(by factor: Double, about anchor: Double, fit: GraphValueRange) -> GraphValueRange {
        guard factor.isFinite, factor > 0, anchor.isFinite else { return self }
        let base = fit.span > 1e-9 ? fit.span : max(1, abs(fit.low))
        let current = span > 1e-12 ? span : base
        let wanted = min(max(current / factor, base / Self.closest), base * Self.furthest)
        let place = span > 1e-12 ? fraction(of: anchor) : 0.5
        let high = anchor + place * wanted
        return GraphValueRange(low: high - wanted, high: high)
    }

    /// How much one turn of the wheel zooms: the timeline's own rate, so ⌥
    /// and the wheel feel the same over time and over value.
    public static func wheelFactor(deltaY: Double) -> Double {
        guard deltaY.isFinite else { return 1 }
        return exp(deltaY / 200)
    }
}
