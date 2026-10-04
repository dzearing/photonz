import Foundation

/// Whether a run of brightness readings is a fade or a jump.
///
/// A dip of a fifth of a second each way is six frames, and a picture of any
/// one of them looks like a fade, so "it just goes to black" has to be read
/// off numbers: the brightness at evenly spaced moments across the fade. A
/// fade moves a little between each pair of neighbours; a jump moves most of
/// the way in one. The bar is a third of everything the run covers, between
/// two neighbours (`dip-to-black-and-dip-to-white-visibly-fade-out-a`).
public enum FadeRamp {

    /// Two neighbouring moments that are too far apart.
    public struct Jump: Hashable, Sendable {
        public let fromMS: Int
        public let toMS: Int
        public let from: Double
        public let to: Double
        /// The most two neighbours may differ by: a third of the run's range.
        public let allowed: Double
    }

    /// Every pair of neighbours, in time order, further apart than a third of
    /// the range the whole run covers. Empty for a ramp, and for a run with
    /// nothing in it to jump.
    public static func jumps(in readings: [(ms: Int, value: Double)]) -> [Jump] {
        let ordered = readings.sorted { $0.ms < $1.ms }
        guard let low = ordered.map(\.value).min(), let high = ordered.map(\.value).max(),
              high > low else { return [] }
        let allowed = (high - low) / 3
        return zip(ordered, ordered.dropFirst()).compactMap { pair in
            abs(pair.1.value - pair.0.value) > allowed
                ? Jump(fromMS: pair.0.ms, toMS: pair.1.ms, from: pair.0.value, to: pair.1.value,
                       allowed: allowed)
                : nil
        }
    }
}
