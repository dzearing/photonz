import Foundation

// What a held frame does to everything that is NOT the clip it was taken in
// (`docs/design/mocks/pages/video-freeze-wt.html`, the "The insert pushes"
// row).
//
// Holding a frame INSERTS time: the picture stops, the clock does not, and
// everything after the hold in that clip moves along. The question this file
// answers is whose time was inserted.
//
// - **The picture alone.** The voice on the layer below carries straight on
//   under the frozen frame, which is exactly right when you froze the frame in
//   order to talk over it. The cost is that everything after the hold is now
//   out of step with the picture by the length of the hold, and nothing about
//   the document says so.
// - **Everything.** Time goes into the whole document at that moment: a layer
//   that starts later starts later still, and a layer the hold lands inside
//   pauses and resumes where it left off. The voice stays with the shot it
//   belongs to. The cost is a silence over the frozen frame.
//
// Neither is the right answer, which is why the person says. The default is
// **everything**, because a voice that has quietly slid five seconds out of
// step with the picture is a mistake you find at the end of the edit, while a
// pause over a frozen frame is one you hear immediately and undo with a click.
//
// **Nothing new is written down to make this work.** The silence a hold pushes
// into a voice is an ordinary held piece — a piece that reads no stretch of its
// file, which on a picture is a frozen frame and on a sound is silence — so it
// trims, moves and draws like every other piece.

/// What a hold pushes along with it.
public enum HoldPush: String, Codable, Sendable, CaseIterable {

    /// Time goes into the whole document, so sound and picture stay in step.
    case everything
    /// Only this clip gets longer, so everything else runs on underneath.
    case pictureOnly

    /// What a hold does when nobody has said.
    public static let whenNobodySays: HoldPush = .everything

    /// What the choice is called where it is offered. It says what you would
    /// HEAR rather than what the edit is called: "ripple insert" is the name
    /// of a thing you have to already know.
    public var title: String {
        switch self {
        case .everything: return "Everything waits"
        case .pictureOnly: return "The rest carries on"
        }
    }

    /// The whole of what it means, in one sentence, with the cost in it.
    public func sentence(holdMS: Int) -> String {
        switch self {
        case .everything:
            return "The voice, the music and anything else on the timeline pause with the "
                + "picture, so what was said over a shot stays over that shot."
        case .pictureOnly:
            return "Everything else keeps running under the frozen frame, so you can talk over "
                + "it. What comes after it lands \(ClipSpeed.seconds(holdMS)) out of step with "
                + "the picture."
        }
    }

    /// The shorter form, for a control that has a sentence under it already.
    public var help: String {
        switch self {
        case .everything: return "Hold the whole timeline, not just the picture."
        case .pictureOnly: return "Hold the picture and let everything else run on."
        }
    }
}

/// A layer running under a hold that pushed the picture alone, and how far out
/// of step with the picture it is from there on.
///
/// This is the freeze clickthrough's own closing question answered the narrow
/// way: the drift is drawn only where there IS drift, so a document nobody has
/// frozen, and one frozen with everything waiting, are both left clean.
public struct HoldDrift: Hashable, Sendable {

    /// Where the hold starts, on the document's clock.
    public let atMS: Int
    /// How far out of step everything from here on is: this hold and every
    /// picture-only hold before it, added up.
    public let byMS: Int

    public init(atMS: Int, byMS: Int) {
        self.atMS = max(0, atMS)
        self.byMS = max(0, byMS)
    }

    /// What the timeline writes beside the mark: `5s out`.
    public var label: String { "\(ClipSpeed.seconds(byMS)) out" }

    /// What it means, for the tooltip and for the panel.
    public var sentence: String {
        "The picture was held for \(ClipSpeed.seconds(byMS)) and this was not, so everything "
            + "here is \(ClipSpeed.seconds(byMS)) ahead of the picture it was recorded against."
    }
}

extension PhotonzDocument {

    // MARK: - Changing your mind

    /// What a hold pushes, or nil where that piece is not a hold.
    public func holdPush(_ id: UUID, ofPiece index: Int) -> HoldPush? {
        layer(id: id)?.clipPieces?.piece(at: index)?.holdPush
    }

    /// Make a hold push the other thing, after the fact.
    ///
    /// It is the same edit either way and it is exact: turning it on inserts
    /// the hold's length into everything else at the hold, turning it off
    /// takes that same length back out, and a hold turned on and off again
    /// leaves the document byte for byte as it was.
    @discardableResult
    public mutating func setHoldPush(_ id: UUID, ofPiece index: Int, to push: HoldPush) -> Bool {
        guard let layer = layer(id: id), var pieces = layer.clipPieces,
              let piece = pieces.piece(at: index), let was = piece.holdPush, was != push,
              let start = holdStartMS(id, ofPiece: index) else { return false }
        guard pieces.setHoldPush(ofPiece: index, to: push) else { return false }
        updateLayer(id: id) { $0.setClipPieces(pieces) }
        rippleTime(atMS: start, byMS: push == .everything ? piece.lengthMS : -piece.lengthMS,
                   exceptLayer: id)
        return true
    }

    /// Where a piece of a clip starts on the DOCUMENT's clock, for a piece
    /// that holds a frame. Nil for anything else.
    func holdStartMS(_ id: UUID, ofPiece index: Int) -> Int? {
        guard let layer = layer(id: id), let time = layer.time,
              let pieces = layer.clipPieces, pieces.piece(at: index)?.isHeld == true
        else { return nil }
        return time.inMS + pieces.startMS(ofPiece: index)
    }

    /// Where the hold nearest a moment starts, on the document's clock.
    ///
    /// A hold taken too near a cut to split anything lands ON that cut rather
    /// than where the playhead was, so the piece under the moment may be the
    /// one before the hold. Both are looked at, and neither is guessed at.
    func heldPieceStartMS(_ id: UUID, nearMS ms: Int) -> Int? {
        guard let layer = layer(id: id), let time = layer.time,
              let pieces = layer.clipPieces,
              let index = pieces.pieceIndex(atMS: ms - time.inMS) else { return nil }
        for candidate in [index, index + 1] where pieces.piece(at: candidate)?.isHeld == true {
            return time.inMS + pieces.startMS(ofPiece: candidate)
        }
        return nil
    }

    // MARK: - Time in and out of the whole document

    /// Put `delta` of time into every layer but one, at a moment of the
    /// document's clock, or take it out again with a negative one.
    ///
    /// Three things can happen to a layer and which one depends only on where
    /// it sits:
    ///
    /// - **It starts at or after the moment**: it starts that much later.
    /// - **The moment falls inside it and it carries media**: it pauses there
    ///   and resumes where it left off, which on a sound is silence and on a
    ///   picture is a frozen frame.
    /// - **The moment falls inside it and it carries no media** — words, a
    ///   shape, an arrow: it stays on screen through the pause, because it
    ///   arrived on a frame of the picture and should leave on the same one.
    ///
    /// A layer that is over before the moment is not touched at all.
    @discardableResult
    public mutating func rippleTime(atMS ms: Int, byMS delta: Int, exceptLayer keep: UUID?) -> Bool {
        guard delta != 0 else { return false }
        var moved = false
        for layer in allLayers {
            guard layer.id != keep, let time = layer.time else { continue }
            if time.inMS >= ms {
                let landing = max(ms, time.inMS + delta)
                guard landing != time.inMS else { continue }
                updateLayer(id: layer.id) { $0.time = $0.time?.moved(toInMS: landing) }
                moved = true
            } else if ms < time.outMS {
                if layer.holdsMedia, var pieces = layer.clipPieces {
                    let offset = ms - time.inMS
                    let did = delta > 0
                        ? pieces.insertHeldTime(atMS: offset, forMS: delta)
                        : pieces.removeHeldTime(atMS: offset, forMS: -delta)
                    // A layer somebody has re-cut since is left exactly as they
                    // left it rather than cut again on a guess.
                    guard did else { continue }
                    updateLayer(id: layer.id) { $0.setClipPieces(pieces) }
                    moved = true
                } else {
                    let out = max(time.inMS + LayerTime.shortestMS, time.outMS + delta)
                    guard out != time.outMS else { continue }
                    updateLayer(id: layer.id) { $0.time = $0.time?.withOut(out) }
                    moved = true
                }
            }
        }
        if moved { refreshDuration() }
        return moved
    }

    // MARK: - What the timeline says about it

    /// Where this layer runs under a hold that pushed the picture alone, and
    /// how far out of step it is from each of them on.
    ///
    /// Only a layer the hold lands INSIDE drifts. A sound dropped on the
    /// timeline after the freeze was put where somebody wanted it, so there is
    /// nothing to warn them about.
    /// Whether any hold anywhere pushed the picture alone, which is the only
    /// thing that can give a bar a drift mark. Asked once per draw of the
    /// timeline, so the 170 bars of a captioned talk need not each ask
    /// `holdDrifts` when the answer is none.
    public var hasPictureOnlyHolds: Bool {
        var found = false
        forEachLayer { layer in
            guard !found, let pieces = layer.clipPieces else { return }
            found = (0..<pieces.count).contains { pieces.piece(at: $0)?.holdPush == .pictureOnly }
        }
        return found
    }

    public func holdDrifts(forLayer id: UUID) -> [HoldDrift] {
        guard let time = layer(id: id)?.time else { return [] }
        var holds: [(atMS: Int, lengthMS: Int)] = []
        forEachLayer { other in
            guard other.id != id, let theirTime = other.time, let pieces = other.clipPieces else { return }
            for index in 0..<pieces.count {
                guard let piece = pieces.piece(at: index), piece.holdPush == .pictureOnly,
                      let range = pieces.rangeMS(ofPiece: index) else { continue }
                let start = theirTime.inMS + range.start
                guard start > time.inMS, start < time.outMS else { continue }
                holds.append((start, piece.lengthMS))
            }
        }
        var running = 0
        return holds.sorted { $0.atMS < $1.atMS }.map { hold in
            running += hold.lengthMS
            return HoldDrift(atMS: hold.atMS, byMS: running)
        }
    }
}

extension Layer {

    /// Whether this layer has a file behind it, which is what decides whether
    /// time inserted into it is a pause in what it is playing or simply more
    /// of it being on screen.
    var holdsMedia: Bool { movie != nil || sound != nil }
}
