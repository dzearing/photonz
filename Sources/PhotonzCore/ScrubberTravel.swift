import CoreGraphics

/// Where a scrub bar's knob sits for a moment, and which moment a press on the
/// bar means.
///
/// The knob's centre travels from half a knob in at the start to half a knob
/// in at the end, the way a Mac slider's does, so the knob never leaves the
/// bar's own room and never covers the times beside it (the user, 2026-11-14).
/// The knob, the played part, the in and out marks, a press and a hover all
/// read the bar through this one mapping, so they always agree.
public struct ScrubberTravel: Sendable, Equatable {
    /// The bar's width, in points.
    public var width: CGFloat
    /// The knob's width at rest, in points.
    public var knobWidth: CGFloat

    public init(width: CGFloat, knobWidth: CGFloat) {
        self.width = width
        self.knobWidth = knobWidth
    }

    /// How far in from each end the knob's centre stops: half a knob, or half
    /// the bar when the bar is narrower than its knob.
    public var inset: CGFloat { min(knobWidth, max(0, width)) / 2 }

    /// The run the knob's centre has between its two ends.
    public var travel: CGFloat { max(0, width - inset * 2) }

    /// The knob's centre for a moment, 0 at the start and 1 at the end.
    public func x(at fraction: Double) -> CGFloat {
        inset + travel * CGFloat(Self.clamped(fraction))
    }

    /// The moment a press at `x` means: the one whose knob would sit there.
    public func fraction(atX x: CGFloat) -> Double {
        guard travel > 0 else { return 0 }
        return Self.clamped(Double((x - inset) / travel))
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(0, value), 1) : 0
    }
}
