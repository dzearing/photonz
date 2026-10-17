import Foundation

// What a held frame does to everything that is NOT the clip it was taken in
// (`docs/design/mocks/pages/video-freeze-wt.html`, the "The insert pushes"
// row).
//
// Holding a frame INSERTS time: the picture stops, the clock does not, and
// everything after the hold in that clip moves along. The question this file
// answers is whose time was inserted.
//
// - **This track.** The clip grows by the hold and the clips after it on its
//   own track move along with it, so nothing on the track is run over. Every
//   other track carries straight on under the frozen frame: the voice on the
//   track below keeps talking, which is exactly right when you froze the frame
//   to talk over it. The cost is that what comes after the hold on the other
//   tracks is now out of step with the picture by the length of the hold, and
//   the timeline says so with a drift mark.
// - **Every track.** Time goes into every unlocked track at that moment: a
//   layer that starts later starts later still, and a layer the hold lands
//   inside pauses and resumes where it left off. The voice stays with the shot
//   it belongs to. The cost is a silence over the frozen frame.
//
// The default is **this track** (the user, 2026-10-17: "by default we'd just
// freeze THAT track, not every track"), and the freeze popover's Freeze every
// track box is the other answer.
//
// **Nothing new is written down to make this work.** The silence a hold pushes
// into a voice is an ordinary held piece — a piece that reads no stretch of its
// file, which on a picture is a frozen frame and on a sound is silence — so it
// trims, moves and draws like every other piece.

/// What a hold pushes along with it.
public enum HoldPush: String, Codable, Sendable, CaseIterable {

    /// Time goes into every unlocked track, so sound and picture stay in step.
    case everything
    /// Only the clip's own track moves along; every other track runs on
    /// underneath. Written as `pictureOnly`, which is what a hold that moved
    /// nothing but its own clip was called before the track came with it.
    case thisTrack = "pictureOnly"

    /// What a hold does when nobody has said.
    public static let whenNobodySays: HoldPush = .thisTrack

    /// What the choice is called where it is offered.
    public var title: String {
        switch self {
        case .everything: return "Every track"
        case .thisTrack: return "This track"
        }
    }

    /// The whole of what it means, in one sentence, with the cost in it.
    public func sentence(holdMS: Int) -> String {
        switch self {
        case .everything:
            return "Every track pauses with the picture, so what was said over a shot stays "
                + "over that shot."
        case .thisTrack:
            return "Only this track moves along. The other tracks keep running under the frozen "
                + "frame and land \(ClipSpeed.seconds(holdMS)) out of step with the picture."
        }
    }

    /// The shorter form, for a control that has a sentence under it already.
    public var help: String {
        switch self {
        case .everything: return "Hold every unlocked track, not just this one."
        case .thisTrack: return "Hold this track and let the others run on."
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
        // The clip's own track moved with the hold either way, so only the
        // other tracks take the time in or give it back.
        rippleTime(atMS: start, byMS: push == .everything ? piece.lengthMS : -piece.lengthMS,
                   except: ownTrackLayerIDs(ofClip: id), sparingLocked: true)
        return true
    }

    /// Move what a hold pushes by `delta`, at the hold's start: the clips
    /// after it on its own track for a hold of this track, every unlocked
    /// track for one of every track. The clip itself has already grown or
    /// shrunk; this is everything else.
    mutating func pushHeldTime(_ id: UUID, _ push: HoldPush, atMS ms: Int, byMS delta: Int) {
        guard delta != 0 else { return }
        switch push {
        case .everything:
            rippleTime(atMS: ms, byMS: delta, except: clipLayerIDs(id), sparingLocked: true)
        case .thisTrack:
            let mine = clipLayerIDs(id)
            let track = ownTrackLayerIDs(ofClip: id).subtracting(mine)
            guard !track.isEmpty else { return }
            rippleTime(atMS: ms, byMS: delta, except: mine, only: track)
        }
    }

    /// The clip and everything inside it.
    func clipLayerIDs(_ id: UUID) -> Set<UUID> {
        layer(id: id).map { Set($0.selfAndDescendants.map(\.id)) } ?? [id]
    }

    /// Everything on the clip's own track, the clip included.
    func ownTrackLayerIDs(ofClip id: UUID) -> Set<UUID> {
        guard let track = trackID(ofClip: id) else { return clipLayerIDs(id) }
        return layerIDs(onTracks: [track]).union(clipLayerIDs(id))
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
    ///
    /// `sparingLocked` leaves a locked layer, and everything on a locked
    /// track, exactly where it was: a ripple drag's way (`RippleEdgeDrag`),
    /// which is Premiere's, where a locked track never moves.
    @discardableResult
    public mutating func rippleTime(atMS ms: Int, byMS delta: Int, exceptLayer keep: UUID?,
                                    sparingLocked: Bool = false) -> Bool {
        rippleTime(atMS: ms, byMS: delta, except: keep.map { [$0] } ?? [], sparingLocked: sparingLocked)
    }

    /// The same, leaving out every layer in `except`, and touching only the
    /// layers in `only` where it is given (a hold of one track's own track).
    @discardableResult
    public mutating func rippleTime(atMS ms: Int, byMS delta: Int, except: Set<UUID>,
                                    only: Set<UUID>? = nil, sparingLocked: Bool = false) -> Bool {
        guard delta != 0 else { return false }
        var moved = false
        let locked = sparingLocked ? layerIDsOnLockedTracks() : []
        for layer in allLayers {
            guard !except.contains(layer.id), only?.contains(layer.id) ?? true,
                  let time = layer.time else { continue }
            if sparingLocked, layer.isLocked || locked.contains(layer.id) { continue }
            if time.inMS >= ms {
                let landing = max(ms, time.inMS + delta)
                guard landing != time.inMS else { continue }
                updateLayer(id: layer.id) { layer in
                    layer.time = layer.time?.moved(toInMS: landing)
                    // A caption's words are on the document's clock, so they
                    // go where the caption goes (`StretchRemoval.swift`).
                    layer.captionWords = layer.captionWords?.map { $0.shifted(byMS: landing - time.inMS) }
                }
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
            found = (0..<pieces.count).contains { pieces.piece(at: $0)?.holdPush == .thisTrack }
        }
        return found
    }

    public func holdDrifts(forLayer id: UUID) -> [HoldDrift] {
        guard let time = layer(id: id)?.time else { return [] }
        var holds: [(atMS: Int, lengthMS: Int)] = []
        forEachLayer { other in
            guard other.id != id, let theirTime = other.time, let pieces = other.clipPieces else { return }
            for index in 0..<pieces.count {
                guard let piece = pieces.piece(at: index), piece.holdPush == .thisTrack,
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
    var holdsMedia: Bool { movie != nil || sound != nil || merged != nil }
}
