import CoreGraphics
import Foundation

/// An edge on the timeline dragged by a walk, read against the pointer at every
/// step (`dragGrip` in `docs/design/playtest-harness.md`).
///
/// The standard is Premiere's and Final Cut's: the edge you are holding sits
/// under the pointer every frame, is caught only when it comes near something,
/// and lets go cleanly. A picture cannot show that, because the fault lives
/// BETWEEN pictures: on 2026-09-26 a rectangle's bar end flickered as the user
/// dragged it left, landing half way and then jumping back, and every still
/// frame of it looked like a bar. So the walk writes down where the pointer
/// was and where the grip was drawn at each move, and this reads the two.
///
/// The first sample is the grab. Where the hand took hold of the grip is kept
/// for the whole drag, so a grip held three points left of its middle is right
/// to stay three points left of the pointer.
public struct GripTrace: Hashable, Sendable {

    public struct Sample: Hashable, Sendable {
        /// Where the pointer was, in window points.
        public var pointerX: CGFloat
        /// The middle of the grip as drawn after that move, in the same space.
        public var gripX: CGFloat
        /// Whether the grip was caught on an edge at that move, which is the
        /// one time it is right for it to sit somewhere other than the hand.
        public var snapped: Bool

        public init(pointerX: CGFloat, gripX: CGFloat, snapped: Bool = false) {
            self.pointerX = pointerX
            self.gripX = gripX
            self.snapped = snapped
        }
    }

    public let samples: [Sample]

    public init(_ samples: [Sample]) {
        self.samples = samples
    }

    /// How far each step's grip was from where the hand put it, grab included
    /// as nought. Nil for a step that was caught on something.
    public var misses: [CGFloat?] {
        guard let grab = samples.first else { return [] }
        let held = grab.gripX - grab.pointerX
        return samples.map { sample in
            sample.snapped ? nil : abs(sample.gripX - sample.pointerX - held)
        }
    }

    /// The furthest the grip was from under the hand, over the steps that were
    /// not caught on anything.
    public var worstMiss: CGFloat {
        misses.compactMap { $0 }.max() ?? 0
    }

    /// How many moves the grip went the OTHER way from the pointer. The
    /// flicker, counted: a grip that tracks never does this, however fast the
    /// hand goes. Being caught, and let go on the far side, can honestly jump
    /// it back to the hand, so a move into or out of a catch is not counted.
    public var wentBack: Int {
        guard samples.count > 1 else { return 0 }
        var count = 0
        for index in 1..<samples.count {
            if samples[index].snapped || samples[index - 1].snapped { continue }
            let hand = samples[index].pointerX - samples[index - 1].pointerX
            let grip = samples[index].gripX - samples[index - 1].gripX
            // A quarter point either way is rounding, not a reversal.
            if hand != 0, abs(grip) > 0.25, (grip > 0) != (hand > 0) { count += 1 }
        }
        return count
    }

    /// How many steps were caught on an edge.
    public var snappedSteps: Int { samples.filter(\.snapped).count }

    /// Whether the grip stayed within `points` of the hand at every free step
    /// and never once went the other way.
    public func follows(within points: CGFloat) -> Bool {
        worstMiss <= points && wentBack == 0
    }

    /// The line a walk's log carries.
    public var summary: String {
        "\(samples.count) steps, worst \(String(format: "%.1f", worstMiss))pt off the pointer, "
            + "went back on itself \(wentBack) times, caught \(snappedSteps)"
    }
}
