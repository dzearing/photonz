import Foundation

// Reading frames for a playhead that moves faster than frames can be read
// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
//
// A hand dragging the playhead asks for a new frame every display refresh, and
// a full-screen Retina frame takes longer than that to read. Queuing every ask
// meant the frame under the hand waited behind every frame the hand had
// already passed. So only a few reads run at once, and the ones nobody has
// started on yet are replaced wholesale by what the newest moment wants.

/// The reads waiting to start and how many are running, latest moment wins.
public struct MovieFrameQueue<Item: Sendable>: Sendable {

    /// How many reads run at once.
    public let capacity: Int
    public private(set) var waiting: [Item] = []
    public private(set) var running = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// What the playhead wants now, most wanted first. Everything still
    /// waiting was wanted by a moment the playhead has left, and goes.
    public mutating func replace(with items: [Item]) {
        waiting = items
    }

    /// The next read to start, or nil when enough are running already or
    /// nothing is waiting.
    public mutating func take() -> Item? {
        guard running < capacity, !waiting.isEmpty else { return nil }
        running += 1
        return waiting.removeFirst()
    }

    /// A read finished, whatever it found.
    public mutating func finished() {
        running = max(0, running - 1)
    }

    /// How much farther a frame gone by counts than one ahead, playing forwards.
    public static var behindWeight: Int { 3 }
    public static var backwardBehindWeight: Int { 8 }

    /// Which of the frames in hand to let go when there are too many: the one
    /// farthest from where its recording's playhead is, so the frames either
    /// side of the playhead stay and a hand reversing finds the ones it just
    /// saw. A recording nothing is looking at any more goes first.
    public static func farthest(_ resident: [(movie: UUID, frame: Int)],
                                from focus: [UUID: Int]) -> Int? {
        var worst: (index: Int, distance: Int)?
        for (index, entry) in resident.enumerated() {
            let distance = focus[entry.movie].map { abs($0 - entry.frame) } ?? Int.max
            if worst == nil || distance > (worst?.distance ?? 0) {
                worst = (index, distance)
            }
        }
        return worst?.index
    }

    /// The same with more than one place being played in a recording (a cut
    /// coming up, a dissolve between two parts of it): the frame let go is
    /// the one farthest from the nearest of them.
    ///
    /// Played `forward`, a frame gone by counts `behindWeight` times as far
    /// as one the same distance ahead: the frames read ahead are the next
    /// ones shown, and letting one go to keep a frame already shown starts
    /// its pass again from the key frame (a dissolve stuck that way,
    /// 2026-10-07). Played `backward`, the frames gone by are the ones above
    /// it, and they count `backwardBehindWeight` times as far: the window
    /// holds a reach and a block below the playhead, and a frame shown a
    /// moment ago must go before the bottom of that block (`MoviePlayBackward`).
    public static func farthest(_ resident: [(movie: UUID, frame: Int)],
                                from foci: [UUID: [Int]], forward: Bool = false,
                                backward: Bool = false) -> Int? {
        func distance(_ frame: Int, _ focus: Int) -> Int {
            if frame < focus && forward { return (focus - frame) * behindWeight }
            if frame > focus && backward { return (frame - focus) * backwardBehindWeight }
            return abs(frame - focus)
        }
        var worst: (index: Int, distance: Int)?
        for (index, entry) in resident.enumerated() {
            let distance = foci[entry.movie]?.map { distance(entry.frame, $0) }.min() ?? Int.max
            if worst == nil || distance > (worst?.distance ?? 0) {
                worst = (index, distance)
            }
        }
        return worst?.index
    }
}
