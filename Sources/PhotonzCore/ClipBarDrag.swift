import Foundation

// A hand on a clip's bar in the timeline (`docs/design/video-surface.md` §10.4).
//
// The bar is the one place cutting happens, so every edge on it has to answer
// the hand the same way. That is the whole rule this file exists to keep:
//
//   **Every edge you can take hold of follows your hand.**
//
// It sounds obvious and it is not free. A clip's pieces lie end to end with no
// holes between them (`ClipPieces`), so shortening one moves everything after
// it — which means an edge can only follow the hand if the thing it belongs to
// is the thing that changes length. Reading the bar left to right:
//
//  - The bar's LEFT end is the clip's in point. Pulling it in shortens the
//    first piece from the front, and the CLIP STAYS WHERE IT WAS PUT: the
//    frames that are left play from the moment the clip already started at,
//    and the bar's far end comes in to meet them. That is the same value the
//    Trim tool writes (§10.4), and it is the only one that answers the job
//    people actually do — dragging the dead air off the front of a recording
//    and having the recording start at nought rather than start with a hole
//    where the dead air used to be. The edge still follows the hand WHILE the
//    drag runs, because the strip draws the frames being dropped as spare in
//    place and closes the bar up when you let go.
//  - Every JOIN, and the bar's right end, is the END of the piece to its left.
//    That piece grows or shrinks, the join goes where the hand puts it, and
//    everything after slides along behind it.
//
// **What is deliberately not here: dragging the START of a piece that is not
// the first one.** There is no edge that could follow the hand while doing it
// — the join is pinned by the piece before it — so it would be the one gesture
// in the timeline where the thing you are holding runs away from you. The job
// it would do is done better by the playhead: put the playhead where the good
// part starts, split (B), and throw the short piece away (⌫). Two presses,
// frame exact, and no aiming at a four point edge.
//
// Nothing here is a view and nothing here writes to a document. A drag holds
// what the bar was when it was GRABBED and works every answer out from that,
// so the numbers cannot creep — the same bargain `MotionStripDrag` strikes.

/// Which part of a clip's bar is in the hand.
public enum ClipBarGrab: Hashable, Sendable {
    /// The bar's left hand end: the clip's in point.
    case clipStart
    /// The join after this piece, which is the bar's right hand end when it is
    /// the last one. The piece to the LEFT of the join is the one that changes.
    case seam(after: Int)
    /// A piece itself, being carried to a different place in the order.
    case carry(piece: Int)
    /// The bar itself: the whole clip slides along the document keeping its
    /// length, and nothing about what it plays changes.
    case body
}

/// A clip's bar under a hand.
public struct ClipBarDrag: Hashable, Sendable {

    public let grab: ClipBarGrab
    /// The pieces the clip had when the bar was taken hold of.
    public let pieces: ClipPieces
    /// Where the clip started on the document's own clock when it was grabbed.
    public let clipStartMS: Int
    /// What the moving edge can catch on: other clips' ends and joins, the
    /// playhead, and the two ends of the document.
    public let others: [MotionStripEdge]
    /// How near a drop has to land to catch on one of those.
    public let snapWithinMS: Int

    public init(grab: ClipBarGrab, pieces: ClipPieces, clipStartMS: Int,
                others: [MotionStripEdge] = [], snapWithinMS: Int = 0) {
        self.grab = grab
        self.pieces = pieces
        self.clipStartMS = clipStartMS
        self.others = others
        self.snapWithinMS = snapWithinMS
    }

    // MARK: Where the thing in the hand is right now

    /// The moment on the document's clock the grabbed edge sat at. What a snap
    /// is measured from, and what the drag's whole arithmetic hangs off.
    public var grabbedMS: Int {
        switch grab {
        case .clipStart, .body:
            return clipStartMS
        case .seam(let after):
            guard let range = pieces.rangeMS(ofPiece: after) else { return clipStartMS }
            return clipStartMS + range.end
        case .carry(let piece):
            return clipStartMS + pieces.startMS(ofPiece: piece)
        }
    }

    /// How far the hand may take it: the smallest and largest delta that means
    /// anything, with nil for an end nothing stops.
    ///
    /// **A gesture clamps with this and then asks.** The edits in `ClipPieces`
    /// refuse rather than guess, so a drag that would go too far is stopped
    /// here, where the drag knows where the pointer is.
    public var limits: (least: Int?, most: Int?) {
        switch grab {
        case .clipStart:
            guard let range = pieces.trimStartRange(ofPiece: 0) else { return (0, 0) }
            // The only thing stopping it going left is how much recording
            // there is behind the first frame. The clip does not move, so the
            // start of the document has nothing to say about it.
            return (range.out, range.in)
        case .seam(let after):
            guard let range = pieces.trimEndRange(ofPiece: after) else { return (0, 0) }
            return (range.in, range.out)
        case .body:
            // A clip cannot start before the first frame of the document.
            // Nothing stops it going the other way: the document grows.
            return (-clipStartMS, nil)
        case .carry:
            return (nil, nil)
        }
    }

    // MARK: Where it lands

    /// The bar as the hand would leave it, and what it caught on to get there.
    public struct Landing: Hashable, Sendable {
        /// The pieces as they would be. The same pieces for a `.body` move,
        /// which changes where the clip is and not what it plays.
        public let pieces: ClipPieces
        /// Where the clip would start on the document's clock.
        public let clipStartMS: Int
        /// What the thing in the hand actually did, after clamping and
        /// catching. Nought is a drag that has not changed anything yet.
        public let movedMS: Int
        /// For a carry: where in the order the piece would land, or nil for a
        /// carry that would put it back where it came from.
        public let dropIndex: Int?
        /// The edge it caught on, for the line the strip draws.
        public let snappedTo: MotionStripEdge?

        public init(pieces: ClipPieces, clipStartMS: Int, movedMS: Int,
                    dropIndex: Int? = nil, snappedTo: MotionStripEdge? = nil) {
            self.pieces = pieces
            self.clipStartMS = clipStartMS
            self.movedMS = movedMS
            self.dropIndex = dropIndex
            self.snappedTo = snappedTo
        }
    }

    /// What the bar becomes when the hand has moved this many milliseconds.
    public func landing(byMS delta: Int) -> Landing {
        if case .carry(let piece) = grab { return carried(piece: piece, byMS: delta) }
        let (moved, caught) = clampedAndCaught(delta)
        switch grab {
        case .clipStart:
            var next = pieces
            guard moved != 0, next.trimStart(ofPiece: 0, byMS: moved) else {
                return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: 0)
            }
            // The clip stays where it was put and the bar closes up from its
            // far end, so a recording trimmed at the front still starts at the
            // moment it started at rather than opening on a hole.
            return Landing(pieces: next, clipStartMS: clipStartMS,
                           movedMS: moved, snappedTo: caught)
        case .seam(let after):
            var next = pieces
            guard moved != 0, next.trimEnd(ofPiece: after, byMS: moved) else {
                return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: 0)
            }
            return Landing(pieces: next, clipStartMS: clipStartMS,
                           movedMS: moved, snappedTo: caught)
        case .body:
            guard moved != 0 else {
                return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: 0)
            }
            return Landing(pieces: pieces, clipStartMS: clipStartMS + moved,
                           movedMS: moved, snappedTo: caught)
        case .carry:
            return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: 0)
        }
    }

    /// A piece being carried: which join it would drop into.
    ///
    /// The piece is taken out of the list and its moved START is compared
    /// against the joins of what is left, nearest winning. At nought it is
    /// back where it came from by construction, which is what stops a carry
    /// that has not gone anywhere from reading as a move.
    private func carried(piece: Int, byMS delta: Int) -> Landing {
        guard pieces.count > 1, pieces.piece(at: piece) != nil else {
            return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: delta)
        }
        var rest = pieces
        _ = rest.remove(at: piece)
        let wanted = pieces.startMS(ofPiece: piece) + delta
        var best = 0
        var bestDistance = Int.max
        for index in 0...rest.count {
            let join = index == rest.count ? rest.totalLengthMS : rest.startMS(ofPiece: index)
            let distance = abs(join - wanted)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        guard best != piece else {
            return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: delta)
        }
        var next = pieces
        guard next.move(from: piece, to: best) else {
            return Landing(pieces: pieces, clipStartMS: clipStartMS, movedMS: delta)
        }
        return Landing(pieces: next, clipStartMS: clipStartMS, movedMS: delta, dropIndex: best)
    }

    /// The delta the hand asked for, brought inside what is possible, and
    /// caught on a nearby edge where there is one it can reach.
    ///
    /// Catching is tried on the RAW delta and then checked against the limits,
    /// so an edge outside what the clip can do never silently drags it there.
    private func clampedAndCaught(_ delta: Int) -> (Int, MotionStripEdge?) {
        let (least, most) = limits
        func clamp(_ value: Int) -> Int {
            var out = value
            if let least { out = max(least, out) }
            if let most { out = min(most, out) }
            return out
        }
        let plain = clamp(delta)
        guard snapWithinMS > 0, !others.isEmpty else { return (plain, nil) }
        let moving = grabbedMS + delta
        let nearest = others
            .filter { abs($0.ms - moving) <= snapWithinMS }
            // Nearest wins; a tie goes to a start, because lining up with
            // where something BEGINS is the commoner thing to want.
            .min { a, b in
                let da = abs(a.ms - moving), db = abs(b.ms - moving)
                return da == db ? (a.isStart && !b.isStart) : da < db
            }
        guard let nearest else { return (plain, nil) }
        let caught = nearest.ms - grabbedMS
        guard clamp(caught) == caught else { return (plain, nil) }
        return (caught, nearest)
    }
}

// MARK: - What a bar can catch on

extension PhotonzDocument {

    /// Everything on the timeline a clip's edge can land on: the two ends of
    /// the document, the playhead, and every other clip's ends and joins.
    ///
    /// Its own joins are NOT in here. A seam catching on the seam next to it
    /// would make the piece between them collapse to nothing the moment you
    /// looked at it.
    public func clipBarEdges(excluding layerID: UUID, playheadMS: Int?) -> [MotionStripEdge] {
        var edges = [MotionStripEdge(ms: 0, name: ClipBarCopy.theStart, isStart: true)]
        let end = documentDurationMS
        if end > 0 { edges.append(MotionStripEdge(ms: end, name: ClipBarCopy.theEnd, isStart: false)) }
        if let playheadMS {
            edges.append(MotionStripEdge(ms: playheadMS, name: ClipBarCopy.thePlayhead, isStart: true))
        }
        for layer in allLayers where layer.id != layerID {
            guard let time = layer.time else { continue }
            edges.append(MotionStripEdge(ms: time.inMS, name: layer.name, isStart: true))
            edges.append(MotionStripEdge(ms: time.outMS, name: layer.name, isStart: false))
            guard let pieces = layer.clipPieces, pieces.count > 1 else { continue }
            for index in 1..<pieces.count {
                edges.append(MotionStripEdge(ms: time.inMS + pieces.startMS(ofPiece: index),
                                             name: layer.name, isStart: true))
            }
        }
        return edges
    }
}

// MARK: - Landing one on the document

extension PhotonzDocument {

    /// Slide a whole clip along the document. What it plays does not change,
    /// only when it plays.
    @discardableResult
    public mutating func moveClip(_ id: UUID, toInMS ms: Int) -> Bool {
        guard let layer = layer(id: id), let time = layer.time,
              max(0, ms) != time.inMS else { return false }
        updateLayer(id: id) { $0.time = time.moved(toInMS: ms) }
        refreshDuration()
        return true
    }

    /// A document that was told how long it runs for is told again, because
    /// the thing it was measuring just changed length. The same rule
    /// `applyTrim` follows: a recording cut down to four seconds IS four
    /// seconds long, on the ruler and in the transport and everywhere else.
    mutating func refreshDuration() {
        guard durationMS != nil else { return }
        durationMS = allLayers.compactMap { $0.time?.outMS }.max()
    }
}

// MARK: - What the bar says while it is being dragged

/// The words a clip bar uses. One place, so the capsule, the readout a walk
/// reads and the help text cannot drift apart.
public enum ClipBarCopy {

    public static let theStart = "the start"
    public static let theEnd = "the end"
    public static let thePlayhead = "the playhead"

    /// `2.4s`, the way a length is said on the bar: seconds with one decimal,
    /// because what it answers is how much there is rather than when.
    public static func length(_ ms: Int) -> String {
        String(format: "%.1fs", Double(max(0, ms)) / 1000)
    }

    /// `+0.4s` or `-1.2s`, and `0.0s` for a drag that has not moved.
    public static func change(_ ms: Int) -> String {
        ms > 0 ? "+\(length(ms))" : (ms < 0 ? "-\(length(-ms))" : "0.0s")
    }

    /// What the capsule says while an edge is being dragged.
    public static func trimming(pieceNumber: Int, of count: Int,
                                lengthMS: Int, changeMS: Int) -> String {
        let piece = count > 1 ? "Piece \(pieceNumber) · " : ""
        return "\(piece)\(length(lengthMS)) · \(change(changeMS))"
    }

    /// What it says while a whole clip is sliding.
    public static func moving(startMS: Int, changeMS: Int) -> String {
        "Starts \(MotionStripRuler.timecode(Double(startMS))) · \(change(changeMS))"
    }

    /// What it says while a piece is being carried somewhere else in the
    /// order: where it is going, counted the way a person counts.
    public static func carrying(pieceNumber: Int, toPlace place: Int, of count: Int) -> String {
        "Piece \(pieceNumber) → place \(place) of \(count)"
    }

    /// `caught on the playhead`, said under the line the strip draws.
    public static func caught(on edge: MotionStripEdge) -> String {
        "caught on \(edge.name)"
    }
}
