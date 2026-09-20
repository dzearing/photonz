import Foundation

// A clip cut into pieces (`docs/design/video-surface.md` §2, UX-PATTERNS D18).
//
// Cutting is most of editing a recording: split a take where the fumble is,
// throw the bad piece away, slide what is left along, hold on a frame, speed a
// dull stretch up. This file is those rules and nothing else — no timeline, no
// gesture, no player. The timeline will DRIVE this; it does not own it.
//
// **A split adds a piece to a clip, never a second clip.** That is D18 §3 and
// it is the sentence the whole file is built on: a clip is one layer, one row
// and one name however many times it is cut, which is what stops a timeline
// growing a row per cut.
//
// **The pieces of a clip are laid back to back, and a gap between them cannot
// be written down.** Throwing a piece away closes the join by construction and
// making a piece longer pushes the rest along, so there is never a hole to drag
// shut. The recording window's `VideoCutList` already strikes exactly this
// bargain in seconds; this is the same bargain in the document's own
// milliseconds, with the three things a cut list has no way to say — an order
// you choose, a frame held, and a speed.
//
// **Nothing here is ever pixels.** A piece is a window on the one file, so a
// cut copies no frames and a delete throws none away.

/// One piece of a clip: a stretch of the recording, played at a speed.
///
/// Three numbers, and which of them is stored decides what stays exact:
///
/// - `lengthMS` — how long the piece runs for ON THE TIMELINE. Stored, because
///   it is the number a person drags, and a drag must land where it was
///   dropped.
/// - `sourceInMS` — where in the file the piece starts reading.
/// - `speedPercent` — 100 is the speed it was recorded at. Nought is a held
///   frame, which is the one piece that reads no stretch of the file at all.
///
/// What it reads from the file (`sourceOutMS`) follows from those, so a trim
/// pulled in and back out returns the identical piece: both edges move by a
/// delta, and the same delta always maps to the same number of frames.
public struct ClipPiece: Hashable, Codable, Sendable {

    /// The shortest piece there is — the same floor a layer's whole stretch
    /// has, because a piece of no width is one nobody can take hold of again.
    public static let shortestMS = LayerTime.shortestMS

    /// The speed a recording plays at when nobody has retimed it.
    public static let asRecordedPercent = 100

    /// As slow and as fast as a piece may be asked to play. Ten times either
    /// way: past that the sound is no longer sound and the pictures are no
    /// longer a take.
    public static let slowestPercent = 10
    public static let fastestPercent = 1000

    /// Where in the file this piece starts reading.
    public private(set) var sourceInMS: Int
    /// How long it runs for on the timeline.
    public private(set) var lengthMS: Int
    /// How fast it plays: 100 as recorded, 0 while a frame is held.
    public private(set) var speedPercent: Int

    public init(sourceInMS: Int, lengthMS: Int, speedPercent: Int = ClipPiece.asRecordedPercent) {
        self.sourceInMS = max(0, sourceInMS)
        self.lengthMS = max(Self.shortestMS, lengthMS)
        self.speedPercent = speedPercent == 0
            ? 0
            : min(max(Self.slowestPercent, speedPercent), Self.fastestPercent)
    }

    /// A frame held: a piece whose start and end in the recording are the same
    /// moment, on screen for as long as it is given.
    public static func held(atSourceMS ms: Int, forMS length: Int) -> ClipPiece {
        ClipPiece(sourceInMS: ms, lengthMS: length, speedPercent: 0)
    }

    // MARK: - Reading

    /// Whether this piece is a frame held rather than a stretch played.
    public var isHeld: Bool { speedPercent == 0 }

    /// How much of the recording this piece plays: nothing at all while a
    /// frame is held, which is exactly what makes a hold a hold.
    public var sourceLengthMS: Int {
        isHeld ? 0 : Self.scaled(lengthMS, byPercent: speedPercent)
    }

    /// Where in the file the piece stops reading. The same moment it started
    /// at, for a held frame.
    public var sourceOutMS: Int { sourceInMS + sourceLengthMS }

    /// Whether there is sound under this piece. A held frame is silent: one
    /// frame has no sound to play.
    public var playsSound: Bool { !isHeld }

    /// How fast the sound runs, which is how fast the picture runs.
    ///
    /// **The sound goes with the picture.** A piece at 200 plays its sound at
    /// 200, so it rises in pitch, and at 50 it falls. Nothing here corrects
    /// it: a control that holds the pitch while the speed changes is a thing
    /// the panel offers later, and it belongs with the rest of a clip's sound.
    public var soundRatePercent: Int { speedPercent }

    /// Which frame of the file plays this far into the piece. The held frame,
    /// wherever you ask, while a frame is held.
    public func sourceMS(atOffsetMS offset: Int) -> Int {
        guard !isHeld else { return sourceInMS }
        let inside = min(max(0, offset), lengthMS)
        return sourceInMS + Self.scaled(inside, byPercent: speedPercent)
    }

    // MARK: - Editing

    /// This piece cut in two where the cut landed, measured from its own
    /// start. Both halves read the same recording, at the same speed, and
    /// together they are exactly what the one was. Nil when either half would
    /// be too short to see or to grab.
    public func split(atOffsetMS offset: Int) -> (ClipPiece, ClipPiece)? {
        guard offset >= Self.shortestMS, lengthMS - offset >= Self.shortestMS else { return nil }
        return (ClipPiece(sourceInMS: sourceInMS, lengthMS: offset, speedPercent: speedPercent),
                ClipPiece(sourceInMS: sourceMS(atOffsetMS: offset),
                          lengthMS: lengthMS - offset, speedPercent: speedPercent))
    }

    /// The same piece with its start edge moved later into the recording by
    /// `delta` (earlier, for a negative one).
    ///
    /// Trimming never destroys anything: the frames either side are still in
    /// the file, they are merely not being played, and moving the edge back
    /// gives back the identical piece.
    public func trimmedStart(byMS delta: Int) -> ClipPiece {
        ClipPiece(sourceInMS: sourceInMS + (isHeld ? 0 : Self.scaled(delta, byPercent: speedPercent)),
                  lengthMS: lengthMS - delta,
                  speedPercent: speedPercent)
    }

    /// The same piece with its end edge moved later by `delta` (earlier, for a
    /// negative one).
    public func trimmedEnd(byMS delta: Int) -> ClipPiece {
        ClipPiece(sourceInMS: sourceInMS, lengthMS: lengthMS + delta, speedPercent: speedPercent)
    }

    /// The same stretch of recording, played at another speed.
    ///
    /// **What a speed does to a piece:** it keeps the frames and changes how
    /// long they take. At 200 the piece is half as long and plays the same
    /// four seconds of file; at 50 it is twice as long. The recording it reads
    /// does not move.
    ///
    /// Honest limit: a length is whole milliseconds, so a piece taken to
    /// double speed and back can come back a millisecond different when its
    /// length was odd — half of an odd number of milliseconds is not one. Where
    /// the piece starts reading never moves.
    public func atSpeed(percent: Int) -> ClipPiece {
        guard !isHeld, percent > 0 else { return self }
        let speed = min(max(Self.slowestPercent, percent), Self.fastestPercent)
        return ClipPiece(sourceInMS: sourceInMS,
                         lengthMS: Self.unscaled(sourceLengthMS, byPercent: speed),
                         speedPercent: speed)
    }

    // MARK: - Two clocks, one conversion

    /// Timeline milliseconds to milliseconds of recording, rounded away from
    /// zero so that scaling a delta and scaling its negative are exact
    /// opposites. That symmetry is the whole reason a trim is reversible.
    static func scaled(_ value: Int, byPercent percent: Int) -> Int {
        let product = value * percent
        return product >= 0 ? (product + 50) / 100 : -((-product + 50) / 100)
    }

    /// Milliseconds of recording to timeline milliseconds.
    static func unscaled(_ value: Int, byPercent percent: Int) -> Int {
        guard percent > 0 else { return value }
        let product = value * 100
        return product >= 0 ? (product + percent / 2) / percent : -((-product + percent / 2) / percent)
    }

    /// The most timeline milliseconds `sourceMS` of recording can pay for at
    /// this speed — never one more than there really is, whatever the
    /// rounding, because this is what a trim is stopped by.
    static func timelineMS(forSourceMS sourceMS: Int, atPercent percent: Int) -> Int {
        guard percent > 0, sourceMS > 0 else { return 0 }
        var timeline = (sourceMS * 100) / percent
        while scaled(timeline + 1, byPercent: percent) <= sourceMS { timeline += 1 }
        while timeline > 0, scaled(timeline, byPercent: percent) > sourceMS { timeline -= 1 }
        return timeline
    }

    // MARK: - Written down

    private enum CodingKeys: String, CodingKey {
        case sourceInMS, lengthMS, speedPercent
    }

    /// A piece playing at the speed it was recorded writes two numbers. The
    /// third is only written when somebody has retimed it or held it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceInMS, forKey: .sourceInMS)
        try c.encode(lengthMS, forKey: .lengthMS)
        if speedPercent != Self.asRecordedPercent { try c.encode(speedPercent, forKey: .speedPercent) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sourceInMS: try c.decode(Int.self, forKey: .sourceInMS),
                  lengthMS: try c.decode(Int.self, forKey: .lengthMS),
                  speedPercent: try c.decodeIfPresent(Int.self, forKey: .speedPercent)
                      ?? Self.asRecordedPercent)
    }
}

/// One piece as a player or an exporter needs it: where it lands, how long it
/// runs, and what to read for it. The whole list, in play order, is everything
/// there is to know about what a clip does.
public struct ClipPlayback: Hashable, Sendable {
    /// Where the piece starts, measured from the clip's own start.
    public let startMS: Int
    /// How long it runs for there.
    public let lengthMS: Int
    /// Where in the file to read from.
    public let sourceInMS: Int
    /// How much file to read: nothing at all for a frame held.
    public let sourceLengthMS: Int
    /// How fast to play it: 100 as recorded, 0 for a frame held.
    public let speedPercent: Int

    public init(startMS: Int, lengthMS: Int, sourceInMS: Int,
                sourceLengthMS: Int, speedPercent: Int) {
        self.startMS = startMS
        self.lengthMS = lengthMS
        self.sourceInMS = sourceInMS
        self.sourceLengthMS = sourceLengthMS
        self.speedPercent = speedPercent
    }

    public var isHeld: Bool { speedPercent == 0 }
    public var playsSound: Bool { !isHeld }
}

/// A clip's pieces, in play order, laid back to back.
///
/// The list is never empty, because a clip with nothing in it is not a clip.
/// A piece's place on the timeline is never stored, only its length — which is
/// what makes the one gap rule true by construction rather than by
/// housekeeping:
///
/// **Take a piece out and everything after it slides up; make a piece longer
/// and everything after it moves along.** The join closes itself, and the same
/// rule holds wherever a piece is removed, trimmed, retimed or reordered. A
/// hole inside a clip cannot be written down at all.
///
/// Where the clip itself sits in the document is the layer's business
/// (`LayerTime`), not this list's, so everything here is measured from the
/// clip's own start.
public struct ClipPieces: Hashable, Codable, Sendable {

    /// The pieces, in the order they play. Never empty.
    public private(set) var pieces: [ClipPiece]

    /// How long the whole recording is, where the clip has one. Nil for a
    /// layer with no source behind it, and then nothing stops a trim but the
    /// shortest a piece may be.
    public private(set) var sourceLengthMS: Int?

    /// How long a frame is held for when nobody has said: two seconds, which
    /// is long enough to read and short enough to drag out rather than in.
    public static let defaultHoldMS = 2000

    public init(pieces: [ClipPiece], sourceLengthMS: Int? = nil) {
        self.pieces = pieces.isEmpty
            ? [ClipPiece(sourceInMS: 0, lengthMS: ClipPiece.shortestMS)]
            : pieces
        self.sourceLengthMS = sourceLengthMS.map { max(0, $0) }
    }

    /// The one-piece clip a layer's stretch describes: uncut, at the speed it
    /// was recorded. This is what every clip in every document is until
    /// somebody cuts it.
    public init(single time: LayerTime) {
        self.init(pieces: [ClipPiece(sourceInMS: time.sourceInMS, lengthMS: time.lengthMS)],
                  sourceLengthMS: time.sourceLengthMS)
    }

    /// A recording already cut in the recording window, said in the document's
    /// own milliseconds (`VideoCuts.swift`). Same pieces, same order, same
    /// lengths — the two models meet here and neither owns the other's
    /// arithmetic.
    public init(cutList: VideoCutList) {
        self.init(pieces: cutList.pieces.map { piece in
            let start = VideoCutList.ms(piece.start)
            return ClipPiece(sourceInMS: start, lengthMS: VideoCutList.ms(piece.end) - start)
        }, sourceLengthMS: VideoCutList.ms(cutList.sourceDuration))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pieces: try c.decode([ClipPiece].self, forKey: .pieces),
                  sourceLengthMS: try c.decodeIfPresent(Int.self, forKey: .sourceLengthMS))
    }

    private enum CodingKeys: String, CodingKey {
        case pieces, sourceLengthMS
    }

    // MARK: - Reading

    /// How many pieces the clip is in.
    public var count: Int { pieces.count }

    /// A piece by its place in play order, nil for an index that is not there.
    public func piece(at index: Int) -> ClipPiece? {
        pieces.indices.contains(index) ? pieces[index] : nil
    }

    /// How long the clip runs for: its pieces, back to back.
    public var totalLengthMS: Int { pieces.reduce(0) { $0 + $1.lengthMS } }

    /// Whether this is a clip nobody has touched: one piece, at the speed it
    /// was recorded. Such a clip says nothing a layer's stretch does not
    /// already say, which is why it is never written down separately.
    public var isOnePlainPiece: Bool {
        pieces.count == 1 && pieces[0].speedPercent == ClipPiece.asRecordedPercent
    }

    /// Where a piece starts, measured from the clip's own start.
    public func startMS(ofPiece index: Int) -> Int {
        guard pieces.indices.contains(index) else { return 0 }
        return pieces[..<index].reduce(0) { $0 + $1.lengthMS }
    }

    /// Where a piece begins and ends, or nil for an index that is not there.
    public func rangeMS(ofPiece index: Int) -> (start: Int, end: Int)? {
        guard pieces.indices.contains(index) else { return nil }
        let start = startMS(ofPiece: index)
        return (start, start + pieces[index].lengthMS)
    }

    /// The piece a moment falls in. A moment exactly on a cut belongs to the
    /// piece that STARTS there — the playhead has arrived at the new piece —
    /// and the very end belongs to the last piece rather than to nothing, so
    /// there is never a moment with no piece under it.
    public func pieceIndex(atMS ms: Int) -> Int? {
        guard !pieces.isEmpty else { return nil }
        let moment = min(max(0, ms), totalLengthMS)
        var elapsed = 0
        for (index, piece) in pieces.enumerated() {
            let next = elapsed + piece.lengthMS
            if moment < next { return index }
            elapsed = next
        }
        return pieces.count - 1
    }

    /// Which frame of the recording plays at a moment of the clip.
    public func sourceMS(atMS ms: Int) -> Int? {
        guard let index = pieceIndex(atMS: ms) else { return nil }
        let moment = min(max(0, ms), totalLengthMS)
        return pieces[index].sourceMS(atOffsetMS: moment - startMS(ofPiece: index))
    }

    /// What plays, and what an export would write: one entry per piece, in
    /// play order, each knowing where it lands and what to read for it.
    public var playback: [ClipPlayback] {
        var written: [ClipPlayback] = []
        var cursor = 0
        for piece in pieces {
            written.append(ClipPlayback(startMS: cursor, lengthMS: piece.lengthMS,
                                        sourceInMS: piece.sourceInMS,
                                        sourceLengthMS: piece.sourceLengthMS,
                                        speedPercent: piece.speedPercent))
            cursor += piece.lengthMS
        }
        return written
    }

    // MARK: - Editing

    /// Cut the clip at a moment, turning the piece it lands in into two that
    /// meet there. Nothing is lost and nothing is copied: the two pieces
    /// together still read exactly what the one did. Refused, and unchanged,
    /// on top of an existing cut or too close to one.
    @discardableResult
    public mutating func split(atMS ms: Int) -> Bool {
        guard let index = pieceIndex(atMS: ms) else { return false }
        let moment = min(max(0, ms), totalLengthMS)
        guard let (head, tail) = pieces[index].split(atOffsetMS: moment - startMS(ofPiece: index))
        else { return false }
        pieces.replaceSubrange(index...index, with: [head, tail])
        return true
    }

    /// Whether a piece can be thrown away. The last one cannot: a clip has to
    /// still be a clip afterwards.
    public func canRemove(at index: Int) -> Bool {
        pieces.count > 1 && pieces.indices.contains(index)
    }

    /// Throw a piece away. Everything after it slides up, so the join closes
    /// with nothing between the two halves.
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard canRemove(at: index) else { return false }
        pieces.remove(at: index)
        return true
    }

    /// Put a piece somewhere else in the order. What plays and what an export
    /// would write follow it, and there is nothing else to change, because a
    /// piece's place is never stored.
    ///
    /// `to` is where the piece lands in the list once it has been taken out of
    /// it, which is what every list in the app already means by moving a row.
    @discardableResult
    public mutating func move(from: Int, to: Int) -> Bool {
        guard pieces.indices.contains(from), pieces.indices.contains(to), from != to
        else { return false }
        pieces.insert(pieces.remove(at: from), at: to)
        return true
    }

    /// How far a piece's start edge may be moved: how far it can be pulled in
    /// before the piece is too short to grab, and how far it can be pulled
    /// back out before the recording runs out behind it.
    ///
    /// `out` is nil when nothing stops it going that way at all — a held frame
    /// can be held as long as you like, and a layer with no recording behind
    /// it has no end to run out of.
    ///
    /// **A gesture clamps with this and then asks.** The edits themselves
    /// refuse rather than guess, so a drag that would go too far is stopped
    /// here, where the drag knows where the pointer is, rather than silently
    /// landing somewhere nobody chose.
    public func trimStartRange(ofPiece index: Int) -> (out: Int?, in: Int)? {
        guard let piece = piece(at: index) else { return nil }
        let out: Int? = piece.isHeld
            ? nil
            : -ClipPiece.timelineMS(forSourceMS: piece.sourceInMS, atPercent: piece.speedPercent)
        return (out, piece.lengthMS - ClipPiece.shortestMS)
    }

    /// How far a piece's end edge may be moved, the same way round: `in` pulls
    /// it back in, `out` pulls it out into the recording still there after it,
    /// and nil is nothing stopping it.
    public func trimEndRange(ofPiece index: Int) -> (in: Int, out: Int?)? {
        guard let piece = piece(at: index) else { return nil }
        var out: Int?
        if !piece.isHeld, let sourceLengthMS {
            out = ClipPiece.timelineMS(forSourceMS: max(0, sourceLengthMS - piece.sourceOutMS),
                                       atPercent: piece.speedPercent)
        }
        return (-(piece.lengthMS - ClipPiece.shortestMS), out)
    }

    /// Move a piece's start edge later into the recording by `delta`, or
    /// earlier by a negative one. The piece gets shorter or longer and
    /// everything after it follows, by the one gap rule.
    ///
    /// Refused when there is not that much recording to pull back out into, or
    /// when it would leave a piece too short to grab. A gesture clamps before
    /// it asks; this says no rather than guessing what was meant.
    @discardableResult
    public mutating func trimStart(ofPiece index: Int, byMS delta: Int) -> Bool {
        guard let piece = piece(at: index), delta != 0 else { return false }
        guard delta <= piece.lengthMS - ClipPiece.shortestMS else { return false }
        if delta < 0, !piece.isHeld {
            let spare = ClipPiece.timelineMS(forSourceMS: piece.sourceInMS,
                                             atPercent: piece.speedPercent)
            guard -delta <= spare else { return false }
        }
        pieces[index] = piece.trimmedStart(byMS: delta)
        return true
    }

    /// Move a piece's end edge later by `delta`, or earlier by a negative one.
    @discardableResult
    public mutating func trimEnd(ofPiece index: Int, byMS delta: Int) -> Bool {
        guard let piece = piece(at: index), delta != 0 else { return false }
        guard -delta <= piece.lengthMS - ClipPiece.shortestMS else { return false }
        if delta > 0, !piece.isHeld, let sourceLengthMS {
            let spare = ClipPiece.timelineMS(forSourceMS: max(0, sourceLengthMS - piece.sourceOutMS),
                                             atPercent: piece.speedPercent)
            guard delta <= spare else { return false }
        }
        pieces[index] = piece.trimmedEnd(byMS: delta)
        return true
    }

    /// Hold on the frame that plays at this moment, for as long as asked.
    ///
    /// The clip is cut there if it is not already, and the held frame takes
    /// its place in the order like any other piece: it can be moved, thrown
    /// away, made longer, cut in two. Everything after it moves along, by the
    /// one gap rule.
    @discardableResult
    public mutating func holdFrame(atMS ms: Int, forMS length: Int = ClipPieces.defaultHoldMS) -> Bool {
        guard let index = pieceIndex(atMS: ms) else { return false }
        let moment = min(max(0, ms), totalLengthMS)
        let offset = moment - startMS(ofPiece: index)
        let piece = pieces[index]
        let held = ClipPiece.held(atSourceMS: piece.sourceMS(atOffsetMS: offset), forMS: length)
        if let (head, tail) = piece.split(atOffsetMS: offset) {
            pieces.replaceSubrange(index...index, with: [head, held, tail])
        } else {
            // Too near an edge to cut: the hold goes at the edge it is nearest,
            // which is the cut the person was aiming at anyway.
            pieces.insert(held, at: offset * 2 < piece.lengthMS ? index : index + 1)
        }
        return true
    }

    /// Give a piece a speed. It keeps the frames it reads and changes how long
    /// they take, so everything after it moves along.
    ///
    /// Refused for a held frame, which reads no stretch of the recording and
    /// so has no speed to give, and for a speed of nought, because a frame
    /// held is made by holding a frame. A speed outside what the player can do
    /// is brought back inside it rather than refused.
    @discardableResult
    public mutating func setSpeed(ofPiece index: Int, percent: Int) -> Bool {
        guard let piece = piece(at: index), !piece.isHeld, percent > 0 else { return false }
        let retimed = piece.atSpeed(percent: percent)
        guard retimed != piece else { return false }
        pieces[index] = retimed
        return true
    }
}

// MARK: - What a layer says about its pieces

extension Layer {

    /// The pieces this layer is cut into, in play order, or nil for a layer
    /// that does not occupy time at all.
    ///
    /// A clip nobody has cut answers one piece, which is exactly what its
    /// stretch already said, so every layer with time has pieces and only a
    /// cut one carries them.
    public var clipPieces: ClipPieces? {
        guard let time else { return nil }
        return cuts ?? ClipPieces(single: time)
    }

    /// Put new pieces on the layer, keeping its stretch in step.
    ///
    /// The pieces are the truth about what plays; `time` is where the row sits
    /// and how long it runs for, and it is written here so the two can never
    /// disagree. **The clip stays where it is and shortens or lengthens from
    /// its end**, because a cut inside a clip is not a reason for the clip to
    /// move away from what a person lined it up with.
    ///
    /// A clip back down to one plain piece stops carrying pieces at all: it is
    /// an ordinary stretch again, and it is written down as one.
    public mutating func setClipPieces(_ pieces: ClipPieces) {
        guard let time else { return }
        let start = time.inMS
        let first = pieces.piece(at: 0)
        self.time = LayerTime(inMS: start, outMS: start + pieces.totalLengthMS,
                              sourceInMS: first?.sourceInMS ?? time.sourceInMS,
                              sourceLengthMS: pieces.sourceLengthMS)
        cuts = pieces.isOnePlainPiece ? nil : pieces
    }
}

// MARK: - Cutting a clip in the document

extension PhotonzDocument {

    /// Cut a clip at a moment of the DOCUMENT's own clock — where the playhead
    /// is. Refused for a moment outside the clip, and for a layer that does
    /// not occupy time.
    @discardableResult
    public mutating func splitClip(_ id: UUID, atMS ms: Int) -> Bool {
        editClip(id) { pieces, time in
            guard ms > time.inMS, ms < time.outMS else { return false }
            return pieces.split(atMS: ms - time.inMS)
        }
    }

    /// Throw a piece of a clip away. The gap closes.
    @discardableResult
    public mutating func removeClipPiece(_ id: UUID, at index: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.remove(at: index) }
    }

    /// Put a piece of a clip somewhere else in the order.
    @discardableResult
    public mutating func moveClipPiece(_ id: UUID, from: Int, to: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.move(from: from, to: to) }
    }

    /// Move a piece's start edge later into the recording, or earlier by a
    /// negative amount.
    @discardableResult
    public mutating func trimClipStart(_ id: UUID, ofPiece index: Int, byMS delta: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.trimStart(ofPiece: index, byMS: delta) }
    }

    /// Move a piece's end edge later, or earlier by a negative amount.
    @discardableResult
    public mutating func trimClipEnd(_ id: UUID, ofPiece index: Int, byMS delta: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.trimEnd(ofPiece: index, byMS: delta) }
    }

    /// Hold on the frame under the playhead, for as long as asked.
    @discardableResult
    public mutating func holdFrame(_ id: UUID, atMS ms: Int,
                                   forMS length: Int = ClipPieces.defaultHoldMS) -> Bool {
        editClip(id) { pieces, time in
            guard ms >= time.inMS, ms < time.outMS else { return false }
            return pieces.holdFrame(atMS: ms - time.inMS, forMS: length)
        }
    }

    /// Give a piece of a clip a speed.
    @discardableResult
    public mutating func setClipSpeed(_ id: UUID, ofPiece index: Int, percent: Int) -> Bool {
        editClip(id) { pieces, _ in pieces.setSpeed(ofPiece: index, percent: percent) }
    }

    /// One edit to one clip's pieces: read them, change them, write them back
    /// with the layer's stretch kept in step. Nothing is written when the edit
    /// refuses, so a refused cut is not an undo step that does nothing.
    private mutating func editClip(_ id: UUID,
                                   _ edit: (inout ClipPieces, LayerTime) -> Bool) -> Bool {
        guard let layer = layer(id: id), let time = layer.time,
              var pieces = layer.clipPieces else { return false }
        guard edit(&pieces, time) else { return false }
        updateLayer(id: id) { $0.setClipPieces(pieces) }
        return true
    }
}
