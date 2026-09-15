import Foundation

/// One kept stretch of a recording, in **source-file seconds**. A piece is not
/// a copy of anything: it is a start and an end, a window onto the one file, so
/// putting a cut in a recording costs nothing and throwing a piece away throws
/// away no pixels.
public struct VideoPiece: Codable, Sendable, Hashable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    /// How long this piece plays for.
    public var duration: TimeInterval { max(0, end - start) }
}

/// A recording cut into pieces: the source length plus the ordered list of
/// stretches that are still kept. This is the generalization of `VideoTrim` —
/// a trim is a cut list with exactly one piece — and it is what makes it
/// possible to drop something out of the MIDDLE of a recording, which a single
/// pair of handles can never do.
///
/// Two clocks, and keeping them apart is the whole trick:
///
/// - **source time** is a position in the recorded file. Pieces are stored in it.
/// - **timeline time** is a position in what you actually watch: the pieces
///   played back to back with nothing in between. Dropping a piece shortens the
///   timeline and everything after it slides up, so a closed gap is closed by
///   construction — there is never a hole to drag shut.
///
/// The playhead, the strip and every key the user presses work in timeline
/// time; only the player and the exporter need source time, and they ask for it
/// through `sourceTime(forTimeline:)` / `sourceRanges`.
///
/// Pure value type: the AVFoundation composition that plays it lives app-side.
public struct VideoCutList: Codable, Sendable, Hashable {
    /// Length of the source file the pieces index into, in seconds.
    public private(set) var sourceDuration: TimeInterval
    /// The kept stretches, in play order. Never empty: a recording always has
    /// at least one piece, because a recording of nothing is not a thing you can
    /// be looking at.
    public private(set) var pieces: [VideoPiece]

    /// The shortest piece a cut may leave behind, in seconds — the same floor
    /// the trim handles enforce, so a cut can never make a piece too small to
    /// grab or to play.
    public static let minPieceDuration: TimeInterval = VideoTrim.defaultMinDuration

    /// Seconds of drift treated as the same instant, so a cut asked for at a
    /// boundary reads as being at that boundary.
    private static let epsilon: TimeInterval = 1e-6

    /// An uncut recording: one piece covering the whole clip.
    public init(duration: TimeInterval) {
        let d = max(0, duration)
        self.sourceDuration = d
        self.pieces = [VideoPiece(start: 0, end: d)]
    }

    /// A cut list from explicit pieces, clamped into the clip with empty ones
    /// dropped. Play order is preserved as given (the app only ever produces
    /// ascending pieces; decoding trusts what it is handed). An empty result
    /// falls back to the whole clip rather than to a recording with nothing in
    /// it.
    public init(pieces: [VideoPiece], sourceDuration: TimeInterval) {
        let d = max(0, sourceDuration)
        let cleaned = pieces.compactMap { piece -> VideoPiece? in
            let lo = min(max(0, piece.start), d)
            let hi = min(max(0, piece.end), d)
            guard hi - lo > Self.epsilon else { return nil }
            return VideoPiece(start: lo, end: hi)
        }
        self.sourceDuration = d
        self.pieces = cleaned.isEmpty ? [VideoPiece(start: 0, end: d)] : cleaned
    }

    /// The one-piece cut list a trim window describes.
    public init(trim: VideoTrim) {
        self.init(pieces: [VideoPiece(start: trim.inPoint, end: trim.outPoint)],
                  sourceDuration: trim.clipDuration)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pieces = try container.decode([VideoPiece].self, forKey: .pieces)
        let duration = try container.decode(TimeInterval.self, forKey: .sourceDuration)
        self.init(pieces: pieces, sourceDuration: duration)
    }

    // MARK: - Reading

    /// How long the kept pieces play for, back to back.
    public var timelineDuration: TimeInterval { pieces.reduce(0) { $0 + $1.duration } }

    /// How many pieces the recording is in.
    public var pieceCount: Int { pieces.count }

    /// True when the recording is still one uncut piece covering the whole file
    /// — the state a freshly opened recording is in, where nothing needs a
    /// composition and nothing needs saving.
    public var isWholeClip: Bool {
        guard pieces.count == 1, let only = pieces.first else { return false }
        return only.start <= Self.epsilon && only.end >= sourceDuration - Self.epsilon
    }

    /// True once there is more than one piece, which is when the strip stops
    /// looking like an ordinary scrubber.
    public var isCut: Bool { pieces.count > 1 }

    /// Where a piece begins on the timeline.
    public func timelineStart(ofPiece index: Int) -> TimeInterval {
        guard pieces.indices.contains(index) else { return 0 }
        return pieces[..<index].reduce(0) { $0 + $1.duration }
    }

    /// Where a piece sits on the timeline, or nil for an index that isn't there.
    public func timelineRange(ofPiece index: Int) -> (start: TimeInterval, end: TimeInterval)? {
        guard pieces.indices.contains(index) else { return nil }
        let start = timelineStart(ofPiece: index)
        return (start, start + pieces[index].duration)
    }

    /// The piece a timeline position falls in. A position exactly on a cut
    /// belongs to the piece that STARTS there (the playhead has arrived at the
    /// new piece), and the very end of the timeline belongs to the last piece
    /// rather than to nothing, so there is never a moment with no piece under
    /// the playhead.
    public func pieceIndex(atTimeline seconds: TimeInterval) -> Int? {
        guard !pieces.isEmpty else { return nil }
        let t = min(max(0, seconds), timelineDuration)
        var elapsed: TimeInterval = 0
        for (index, piece) in pieces.enumerated() {
            let next = elapsed + piece.duration
            if t < next - Self.epsilon { return index }
            elapsed = next
        }
        return pieces.count - 1
    }

    /// Where in the source file a timeline position reads from. Clamped at both
    /// ends, so a playhead past the finish maps to the last frame kept.
    public func sourceTime(forTimeline seconds: TimeInterval) -> TimeInterval {
        guard let index = pieceIndex(atTimeline: seconds) else { return 0 }
        let t = min(max(0, seconds), timelineDuration)
        let piece = pieces[index]
        // Reading through the piece the playhead is IN, so a position sitting
        // exactly on a cut reads the first frame of the piece that starts
        // there rather than the last frame of the one that ended.
        return min(piece.start + (t - timelineStart(ofPiece: index)), piece.end)
    }

    /// The kept stretches as `(start, length)` pairs, in play order — what a
    /// composition inserts and what an export reads.
    public var sourceRanges: [(start: TimeInterval, length: TimeInterval)] {
        pieces.map { ($0.start, $0.duration) }
    }

    /// The trim window this cut list describes, when it is still one piece; nil
    /// once there is a cut in it, because two pieces are not a window. Lets an
    /// uncut recording keep travelling through every path that already speaks
    /// `VideoTrim` — saving, exporting, the sidecar — completely unchanged.
    public var singleTrim: VideoTrim? {
        guard pieces.count == 1, let only = pieces.first else { return nil }
        return VideoTrim(inPoint: only.start, outPoint: only.end, duration: sourceDuration)
    }

    // MARK: - Editing

    /// Whether a cut at this timeline position would actually make two pieces:
    /// it has to land inside a piece, with room for the minimum on both sides.
    public func canSplit(atTimeline seconds: TimeInterval) -> Bool {
        guard let index = pieceIndex(atTimeline: seconds),
              let range = timelineRange(ofPiece: index) else { return false }
        let t = min(max(0, seconds), timelineDuration)
        return t - range.start >= Self.minPieceDuration
            && range.end - t >= Self.minPieceDuration
    }

    /// Put a cut at this timeline position, turning the piece it lands in into
    /// two that meet there. Nothing is lost: the two pieces together still
    /// cover exactly what the one did. Refused (and unchanged) at a boundary or
    /// too close to one.
    @discardableResult
    public mutating func split(atTimeline seconds: TimeInterval) -> Bool {
        guard canSplit(atTimeline: seconds),
              let index = pieceIndex(atTimeline: seconds),
              let range = timelineRange(ofPiece: index) else { return false }
        let piece = pieces[index]
        let at = piece.start + (min(max(0, seconds), timelineDuration) - range.start)
        pieces.replaceSubrange(index...index, with: [
            VideoPiece(start: piece.start, end: at),
            VideoPiece(start: at, end: piece.end),
        ])
        return true
    }

    /// Whether this piece can be thrown away. The last one cannot: a recording
    /// has to still be a recording afterwards.
    public func canRemovePiece(at index: Int) -> Bool {
        pieces.count > 1 && pieces.indices.contains(index)
    }

    /// Throw a piece away. Everything after it slides up the timeline, so the
    /// join closes with nothing between the two halves.
    @discardableResult
    public mutating func removePiece(at index: Int) -> Bool {
        guard canRemovePiece(at: index) else { return false }
        pieces.remove(at: index)
        return true
    }

    /// Keep only `from...to` of the timeline, narrowing the pieces that window
    /// crosses and dropping the ones outside it. This is what applying a trim
    /// does once a recording is in pieces. Refused when the window would leave
    /// nothing.
    @discardableResult
    public mutating func keep(fromTimeline from: TimeInterval,
                              toTimeline to: TimeInterval) -> Bool {
        let total = timelineDuration
        let lo = min(max(0, min(from, to)), total)
        let hi = min(max(0, max(from, to)), total)
        guard hi - lo > Self.epsilon else { return false }

        var kept: [VideoPiece] = []
        var elapsed: TimeInterval = 0
        for piece in pieces {
            let pieceStart = elapsed
            let pieceEnd = elapsed + piece.duration
            elapsed = pieceEnd
            let overlapLo = max(pieceStart, lo)
            let overlapHi = min(pieceEnd, hi)
            guard overlapHi - overlapLo > Self.epsilon else { continue }
            kept.append(VideoPiece(start: piece.start + (overlapLo - pieceStart),
                                   end: piece.start + (overlapHi - pieceStart)))
        }
        guard !kept.isEmpty else { return false }
        pieces = kept
        return true
    }
}
