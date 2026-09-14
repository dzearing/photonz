import CoreGraphics
import Foundation

/// What goes into the space a piece came out of, so taking the piece out never
/// reveals a hole.
///
/// Two answers only, and the order matters: a flat colour where the ring around
/// the piece agrees with itself, a straight gradient where it varies evenly one
/// way. There is no third, content-aware answer on purpose — see `PatchFill`'s
/// own note and `docs/design/separate-into-layers.md`.
public enum PatchFill: Equatable, Sendable {

    /// Which way a gradient runs across the space being filled.
    public enum Axis: Equatable, Sendable {
        /// Left edge to right edge.
        case across
        /// Top edge to bottom edge.
        case down
    }

    /// One colour, everywhere. The overwhelmingly common case in real UI: words
    /// on a solid button, a bar, a card.
    case solid(RGBA)
    /// A straight ramp from `start` to `end` along `axis`.
    case gradient(start: RGBA, end: RGBA, axis: Axis)

    /// The colour this fill puts at a point, given where that point sits inside
    /// the space being filled: `u` across (0 at the left edge, 1 at the right)
    /// and `v` down (0 at the top, 1 at the bottom).
    public func color(u: Double, v: Double) -> RGBA {
        switch self {
        case .solid(let color):
            return color
        case .gradient(let start, let end, let axis):
            let t = min(max(axis == .across ? u : v, 0), 1)
            return RGBA(r: start.r + (end.r - start.r) * t,
                        g: start.g + (end.g - start.g) * t,
                        b: start.b + (end.b - start.b) * t,
                        a: start.a + (end.a - start.a) * t)
        }
    }
}

/// How the space a piece came out of was filled in, which is the only part of
/// a cut worth saying out loud.
///
/// `matched` never needs announcing: the person watched the canvas change and
/// what went in was read off the picture. The other two are the app admitting
/// what it did not know, and a person who is not told cannot tell a repair
/// from a smudge.
public enum PatchHeal: String, Hashable, Sendable, Codable {
    /// The surroundings agreed with themselves or ramped evenly, so the fill
    /// was READ rather than guessed (`PatchDecision.decide`).
    case matched
    /// The surroundings justified nothing, and the person asked for the cut
    /// anyway, so the middle colour of what was around it went in. One flat
    /// colour, because a guess must not pretend to detail it does not have.
    case guessed
    /// There was no background to read at all, which is what a marquee flung
    /// round the whole layer leaves. The space is honestly empty.
    case cleared
}

/// The background just outside a piece, as read off the picture.
///
/// Samples carry WHERE they sat as well as what colour they were, because that
/// is what lets a ring say "this varies evenly down the box" rather than only
/// "this varies". `u` is 0 at the piece's left edge and 1 at its right, `v` is 0
/// at its top and 1 at its bottom; a sample just outside the box sits a little
/// past 0 or 1, which is exactly where it should sit for a fit.
public struct PatchRing: Equatable, Sendable {

    public struct Sample: Equatable, Sendable {
        public let u: Double
        public let v: Double
        public let color: RGBA

        public init(u: Double, v: Double, color: RGBA) {
            self.u = u
            self.v = v
            self.color = color
        }
    }

    public let samples: [Sample]

    public init(samples: [Sample]) {
        self.samples = samples
    }
}

/// Decides what fills the space a piece came out of, from the background around
/// it — and refuses when nothing it can justify would do.
///
/// Deliberately NOT content-aware. On flat UI, inpainting is unnecessary; on a
/// photograph it invents detail that is not there, and an edge extend smears it
/// sideways. The user was explicit that a visible guess is worse than leaving
/// the thing alone, so a piece whose surroundings neither agree nor ramp is one
/// the app cannot read confidently: it is left in the picture and no layer is
/// made of it.
public enum PatchDecision {

    /// How far a ring sample may sit from the ring's middle and still be called
    /// one flat colour: two levels out of 255. Tight enough that the flat case
    /// is EXACT — white words on a solid dark bar leave that bar one colour,
    /// byte for byte — and loose enough to survive a colour space round trip.
    public static let uniformTolerance = 2.0 / 255

    /// How far a ring sample may sit from a fitted ramp and still be called a
    /// gradient. Looser than flat, because a ramp is dithered in the picture it
    /// was read from, and a sixth of a percent of error is invisible.
    public static let fitTolerance = 6.0 / 255

    /// The fewest ring samples worth deciding on. Below this the ring is mostly
    /// ink or mostly off the edge of the picture, and the reading is a guess.
    public static let minimumSamples = 24

    /// The fill for a piece with this ring, or nil when the surroundings do not
    /// justify one.
    public static func decide(_ ring: PatchRing,
                              minimumSamples: Int = minimumSamples) -> PatchFill? {
        let samples = ring.samples
        guard samples.count >= minimumSamples else { return nil }

        // 1. Flat. The middle is the median per channel rather than the mean,
        // so one stray sample cannot drag the answer off the panel colour it
        // should land on exactly.
        let middle = median(samples.map(\.color))
        if maximumDeviation(samples.map(\.color), from: { _ in middle }) <= uniformTolerance {
            return .solid(middle)
        }

        // 2. A straight ramp, whichever way fits better.
        let down = fit(samples, along: { $0.v })
        let across = fit(samples, along: { $0.u })
        let candidates = [(down, PatchFill.Axis.down), (across, PatchFill.Axis.across)]
            .compactMap { fit, axis -> (residual: Double, fill: PatchFill)? in
                guard let fit else { return nil }
                return (fit.residual, .gradient(start: fit.start, end: fit.end, axis: axis))
            }
            .filter { $0.residual <= fitTolerance }
        return candidates.min(by: { $0.residual < $1.residual })?.fill
    }

    /// The middle of a ring: the per-channel median of everything in it.
    ///
    /// What goes into the space when `decide` can justify nothing and the
    /// person asked for the cut anyway (`PatchHeal.guessed`). The median
    /// rather than the mean for the same reason `decide` uses it: it lands ON
    /// a colour that was really there rather than between two that were.
    public static func middle(of ring: PatchRing) -> RGBA? {
        guard !ring.samples.isEmpty else { return nil }
        return median(ring.samples.map(\.color))
    }

    // MARK: - Reading the ring

    /// The per-channel median of a set of colours.
    private static func median(_ colors: [RGBA]) -> RGBA {
        func middle(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return RGBA(r: middle(colors.map(\.r)), g: middle(colors.map(\.g)),
                    b: middle(colors.map(\.b)), a: middle(colors.map(\.a)))
    }

    /// The largest single-channel difference between any colour and what the
    /// model says should be there.
    private static func maximumDeviation(_ colors: [RGBA],
                                         from model: (Int) -> RGBA) -> Double {
        var worst = 0.0
        for (i, color) in colors.enumerated() {
            let want = model(i)
            worst = max(worst, abs(color.r - want.r))
            worst = max(worst, abs(color.g - want.g))
            worst = max(worst, abs(color.b - want.b))
            worst = max(worst, abs(color.a - want.a))
        }
        return worst
    }

    /// A least squares line through the ring along one axis, reported as the
    /// colour at 0 and the colour at 1 plus the worst error it leaves behind.
    /// Nil when the samples do not span enough of the axis to fit anything —
    /// a ring read entirely off one edge says nothing about a ramp.
    private static func fit(_ samples: [PatchRing.Sample],
                            along position: (PatchRing.Sample) -> Double)
        -> (start: RGBA, end: RGBA, residual: Double)? {
        let t = samples.map(position)
        guard let low = t.min(), let high = t.max(), high - low >= 0.5 else { return nil }
        let n = Double(samples.count)
        let meanT = t.reduce(0, +) / n
        let variance = t.reduce(0) { $0 + ($1 - meanT) * ($1 - meanT) }
        guard variance > 0 else { return nil }

        func line(_ channel: (RGBA) -> Double) -> (intercept: Double, slope: Double) {
            let values = samples.map { channel($0.color) }
            let meanV = values.reduce(0, +) / n
            var covariance = 0.0
            for i in samples.indices { covariance += (t[i] - meanT) * (values[i] - meanV) }
            let slope = covariance / variance
            return (meanV - slope * meanT, slope)
        }
        let r = line(\.r), g = line(\.g), b = line(\.b), a = line(\.a)
        func at(_ x: Double) -> RGBA {
            RGBA(r: r.intercept + r.slope * x, g: g.intercept + g.slope * x,
                 b: b.intercept + b.slope * x, a: a.intercept + a.slope * x)
        }
        let residual = maximumDeviation(samples.map(\.color), from: { at(t[$0]) })
        return (at(0), at(1), residual)
    }
}
