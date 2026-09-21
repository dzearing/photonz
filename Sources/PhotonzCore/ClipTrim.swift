import Foundation

// Trimming a clip, as a session (`docs/design/video-surface.md` §10).
//
// Trim is a TOOL, in Crop's slot, and it works the way Crop works: you pick it
// up, handles appear on the thing whose bounds you are changing, a glass
// capsule says the numbers, and ⏎ commits while ⎋ throws the session away.
//
// The session is held to one side while it runs and only lands on the document
// when it is committed, exactly as a crop rectangle is. That is what makes ⎋
// free: nothing was written, so there is nothing to put back.
//
// **Nothing is ever thrown away.** A trim moves a clip's in and out; the frames
// outside them stay in the document, which is what lets the strip draw the
// spare at each end and what lets a second trim give the whole recording back.

/// A trim in progress on one clip.
///
/// Everything is measured in the clip's OWN milliseconds: nought is the first
/// frame of the recording behind it and `wholeLengthMS` is the last, whatever
/// the clip has already been trimmed to and wherever it sits in the document.
/// That is the coordinate the handles and the spare are drawn in, and it is the
/// only one in which "give me the whole recording back" is a sentence.
public struct ClipTrimSession: Hashable, Sendable {

    /// The clip being trimmed.
    public let layerID: UUID
    /// Everything this clip could play, end to end: what a trim put out of
    /// play at the front, what it is playing, and what it put out of play at
    /// the back.
    public let wholeLengthMS: Int
    /// The kept window when the session opened. What ⎋ goes back to, and what
    /// a commit measures its change against.
    public let openedInMS: Int
    public let openedOutMS: Int

    /// The kept window as the handles have it right now.
    public private(set) var keepInMS: Int
    public private(set) var keepOutMS: Int

    /// Opens a session on a clip. Nil for a layer that occupies no time:
    /// there is no in and out to move.
    public init?(layer: Layer) {
        guard let time = layer.time else { return nil }
        layerID = layer.id
        let before = time.spareBeforeMS
        wholeLengthMS = before + time.lengthMS + time.spareAfterMS
        openedInMS = before
        openedOutMS = before + time.lengthMS
        keepInMS = openedInMS
        keepOutMS = openedOutMS
    }

    /// How long the trim keeps.
    public var keptMS: Int { keepOutMS - keepInMS }
    /// The frames before the in point: still in the document, not being played.
    public var spareBeforeMS: Int { keepInMS }
    /// The frames after the out point, the same way.
    public var spareAfterMS: Int { max(0, wholeLengthMS - keepOutMS) }

    /// Whether the handles have moved since the session opened, which is what
    /// decides whether committing writes anything at all.
    public var isChanged: Bool { keepInMS != openedInMS || keepOutMS != openedOutMS }

    /// Whether there is anything for Reset to give back.
    public var canReset: Bool { keepInMS != 0 || keepOutMS != wholeLengthMS }

    /// Drag the in handle. It never crosses the out handle and never leaves
    /// the recording.
    public mutating func dragIn(toMS ms: Int) {
        keepInMS = min(max(0, ms), max(0, keepOutMS - LayerTime.shortestMS))
    }

    /// Drag the out handle, the same way round.
    public mutating func dragOut(toMS ms: Int) {
        keepOutMS = max(min(wholeLengthMS, ms), min(wholeLengthMS, keepInMS + LayerTime.shortestMS))
    }

    /// Give the whole recording back, without leaving the session.
    public mutating func reset() {
        keepInMS = 0
        keepOutMS = wholeLengthMS
    }

    /// The clip as this trim leaves it, or nil where nothing moved or the clip
    /// cannot take it.
    ///
    /// The clip stays where it was put and shortens or lengthens from its end,
    /// which is the rule `Layer.setClipPieces` already holds every other edit
    /// to: a trim is not a reason for a clip to walk away from what somebody
    /// lined it up with.
    public func applied(to layer: Layer) -> Layer? {
        guard layer.id == layerID, isChanged, var pieces = layer.clipPieces else { return nil }
        let atTheFront = keepInMS - openedInMS
        let atTheBack = keepOutMS - openedOutMS
        if atTheFront != 0, !pieces.trimStart(ofPiece: 0, byMS: atTheFront) { return nil }
        if atTheBack != 0, !pieces.trimEnd(ofPiece: pieces.count - 1, byMS: atTheBack) { return nil }
        var next = layer
        next.setClipPieces(pieces)
        return next
    }
}

// MARK: - Landing one on the document

extension PhotonzDocument {

    /// Commit a trim. False where nothing moved or the clip would not take it,
    /// so a session closed without touching a handle is not an undo step that
    /// does nothing.
    @discardableResult
    public mutating func applyTrim(_ session: ClipTrimSession) -> Bool {
        guard let layer = layer(id: session.layerID),
              let trimmed = session.applied(to: layer) else { return false }
        updateLayer(id: session.layerID) { $0 = trimmed }
        // A document that was told how long it runs for is told again, because
        // the thing it was measuring just got shorter. A recording trimmed to
        // its middle four seconds IS four seconds long, in the transport, on
        // the ruler and everywhere else that reads the clock.
        if durationMS != nil {
            durationMS = allLayers.compactMap { $0.time?.outMS }.max()
        }
        return true
    }

    /// The document as it looks WHILE a trim is running: the clip laid out at
    /// its full length, so everything a trim could give back is on the
    /// timeline and can be scrubbed to and looked at.
    ///
    /// Nothing is written down. This is a picture of what the document would be
    /// if the trim were undone entirely, handed to the canvas and the strip for
    /// as long as the session lasts, which is what lets the handles bracket the
    /// kept part of the WHOLE recording rather than of what is left of it. The
    /// clip keeps the start it was given, so the spare at the front is laid
    /// forward from there rather than before the first frame of the document.
    public func openedForTrim(_ session: ClipTrimSession) -> PhotonzDocument {
        guard let layer = layer(id: session.layerID), let time = layer.time,
              var pieces = layer.clipPieces,
              session.wholeLengthMS > time.lengthMS else { return self }
        if session.openedInMS > 0,
           !pieces.trimStart(ofPiece: 0, byMS: -session.openedInMS) { return self }
        let atTheBack = session.wholeLengthMS - session.openedOutMS
        if atTheBack > 0,
           !pieces.trimEnd(ofPiece: pieces.count - 1, byMS: atTheBack) { return self }
        var opened = self
        opened.updateLayer(id: session.layerID) { $0.setClipPieces(pieces) }
        if opened.durationMS != nil {
            opened.durationMS = opened.allLayers.compactMap { $0.time?.outMS }.max()
        }
        return opened
    }

    /// Whether opening this document should put Trim straight in your hand.
    ///
    /// The fast lane, kept by what the window opens as rather than by a second
    /// view (`docs/design/video-surface.md` §10.3): a recording that is one
    /// clip and has never been edited opens with the clip picked and Trim in
    /// hand, so trim-and-send is still drag a handle, ⏎, export. More than one
    /// layer, or anything already done to it, and it opens with Select like
    /// every other document.
    public var opensWithTrimInHand: Bool {
        guard hasTime, layers.count == 1, let only = layers.first, only.isClip,
              only.clipPieces?.isOnePlainPiece == true else { return false }
        // A clip already trimmed has been edited, whatever else has happened
        // to it, so it opens the ordinary way.
        return only.time?.spareBeforeMS == 0 && only.time?.spareAfterMS == 0
    }

    /// The clip a trim should open on: the one already picked when it occupies
    /// time, else the topmost thing with time under the playhead.
    ///
    /// The second half is what makes the fast lane free. A recording that has
    /// just been opened is one clip and the playhead is on it, so picking Trim
    /// up needs no click first (`docs/design/video-surface.md` §10.5).
    /// **A layer that plays nothing is never a clip in hand**, however much time
    /// it occupies (`TitleTime.swift`). A title and a mark on a held frame have
    /// an in and an out and no frames behind them, so a trim, a split, a speed,
    /// a held frame, a transition and a punch-in all mean nothing for one.
    ///
    /// Picking one leaves NOTHING in hand rather than quietly handing back the
    /// clip underneath: the panel speaks for what you picked, and a Reframe
    /// section pointed at the shot while the words are selected is a control
    /// that does something other than what it appears to be about. The clip
    /// comes back the moment the clip is picked, or nothing is.
    public func clipToTrim(pickedLayerID: UUID?, atTimeMS ms: Int) -> UUID? {
        if let pickedLayerID, let picked = layer(id: pickedLayerID), picked.time != nil {
            return picked.isPlacedInTime ? nil : pickedLayerID
        }
        return allLayers.last { $0.time?.contains(ms: ms) == true && !$0.isPlacedInTime }?.id
    }
}
