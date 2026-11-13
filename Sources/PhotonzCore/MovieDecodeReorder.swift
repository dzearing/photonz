import Foundation

/// Decoded frames put back in the order they are shown.
///
/// A decoder hands frames back in the order they were decoded, and a
/// recording with B-frames decodes some frames before the ones shown ahead of
/// them (9.750, 9.817, 9.783 on the reference recordings, 2026-11-13). This
/// holds back the last `depth` frames and hands on the earliest of the rest,
/// so a frame decoded up to `depth` places early still comes out in its turn.
/// A frame arriving after a later one has been handed on is dropped: the
/// frames handed on only ever move forwards (`MovieSweepGrid`).
public struct MovieDecodeReorder<Frame> {

    public let depth: Int
    private var held: [(ms: Double, frame: Frame)] = []
    private var handedOn = -Double.infinity

    public init(depth: Int) {
        self.depth = max(0, depth)
    }

    /// A frame the decoder finished, shown at `ms`.
    public mutating func insert(_ ms: Double, _ frame: Frame) {
        guard ms > handedOn else { return }
        let at = held.firstIndex { $0.ms > ms } ?? held.endIndex
        held.insert((ms, frame), at: at)
    }

    /// The earliest frame, once more than `depth` are held.
    public mutating func next() -> (ms: Double, frame: Frame)? {
        guard held.count > depth else { return nil }
        return take()
    }

    /// The earliest frame held, whatever is held: the decoder has finished.
    public mutating func drain() -> (ms: Double, frame: Frame)? {
        held.isEmpty ? nil : take()
    }

    private mutating func take() -> (ms: Double, frame: Frame) {
        let first = held.removeFirst()
        handedOn = first.ms
        return first
    }
}
