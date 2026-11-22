import Foundation

// Scrubbing fast shows the key frames (`a-long-edit-with-transitions-plays-
// scrubs-and-ed`, pass 14).
//
// A recording keeps a whole picture only every so often (about every two
// seconds in a Mac screen recording) and, between them, what changed. Any other
// frame is decoded from the key frame before it, about sixty decodes on
// average, which is 40 to 100ms for a full-screen Retina recording even with
// the decoder to itself. A hand dragging the playhead across a six minute edit
// in two seconds is somewhere else by then. A key frame decodes on its own, and
// at that pace the key frame a second of film away was under the hand less
// than one refresh ago. QuickTime Player shows key frames while you drag fast
// for the same reason.

/// Which grid frames of a recording are key frames, and exactly when each is.
public struct MovieKeyFrames: Equatable, Sendable {

    /// Where each key frame is in the file, in milliseconds, in order, once
    /// each. Asked for at exactly this moment, a key frame decodes on its
    /// own; asked for at its grid frame's moment, up to a frame earlier
    /// (`MovieRef.frameIndex(atSourceMS:)` rounds down), it is decoded from
    /// the key frame before it, two seconds of decoding (2026-11-17: 100ms
    /// against 20).
    public let sourceMS: [Int]
    /// Their grid frames (`MovieRef.frameIndex(atSourceMS:)`), in the same order.
    public let frames: [Int]

    public init(sourceMS: [Int]) {
        let sorted = Array(Set(sourceMS)).sorted()
        self.sourceMS = sorted
        self.frames = sorted.map { MovieRef.gridFrame(atMS: $0) }
    }

    /// The key frame nearest `frame` inside `within` (grid frames: the
    /// stretch of the recording a clip plays, `Layer.playedSourceSpanMS`),
    /// or the nearest at all where none is inside it. The nearest at all can
    /// be one the clip never plays, just before its first frame or after its
    /// last: a picture the edit never shows, from a part of the recording the
    /// hand was nowhere near (2026-11-17).
    public func nearest(to frame: Int, within: ClosedRange<Int>?) -> (frame: Int, sourceMS: Int)? {
        guard let within else { return nearest(to: frame) }
        let clamped = min(max(frame, within.lowerBound), within.upperBound)
        // The first key frame after the clamped frame, and the one before.
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid] <= clamped { low = mid + 1 } else { high = mid }
        }
        let inside = [low - 1, low].filter { frames.indices.contains($0) && within.contains(frames[$0]) }
        guard let best = inside.min(by: { abs(frames[$0] - frame) < abs(frames[$1] - frame) }) else {
            return nearest(to: frame)
        }
        return (frames[best], sourceMS[best])
    }

    /// The last key frame at or before `frame`: where a pass opened on
    /// `frame` starts decoding. Nil before the first one.
    public func latest(atOrBefore frame: Int) -> Int? {
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid] <= frame { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? frames[low - 1] : nil
    }

    /// The key frame nearest `frame`, either side; a tie goes to the one
    /// behind. Nil for a recording with none.
    public func nearest(to frame: Int) -> (frame: Int, sourceMS: Int)? {
        guard !frames.isEmpty else { return nil }
        // The first key frame after `frame`.
        var low = 0, high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid] <= frame { low = mid + 1 } else { high = mid }
        }
        let index: Int
        switch (low > 0, low < frames.count) {
        case (true, true): index = frames[low] - frame < frame - frames[low - 1] ? low : low - 1
        case (true, false): index = low - 1
        case (false, true): index = low
        case (false, false): return nil
        }
        return (frames[index], sourceMS[index])
    }
}
