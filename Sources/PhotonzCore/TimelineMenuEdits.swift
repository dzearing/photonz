import Foundation

// The edits a timeline's right-click menus reach that no key or gesture did
// before: Ripple Delete, Split Everything Here and Roll Edit to Playhead.
//
// Each one is a Premiere command under Premiere's own name, so an editor who
// knows that tool finds it where they look. The arithmetic of a single clip is
// `ClipPieces`; what is here is the part that has to see the whole document.

extension PhotonzDocument {

    // MARK: Ripple delete

    /// Throw a piece of a clip away and take the same stretch out of the rest
    /// of the document (`StretchRemoval.swift`), so everything stays in step
    /// with the picture: a title over the fifth second of a take is still over
    /// the same frame once a stretch before it has gone, and the captions for
    /// the words that went go with them.
    ///
    /// `removeClipPiece` on its own closes the join inside the clip and moves
    /// nothing else; nothing a person presses reaches it any more, because a
    /// talking recording cut that way leaves every caption after the cut over
    /// the wrong words.
    @discardableResult
    public mutating func rippleDeleteClipPiece(_ id: UUID, at index: Int) -> Bool {
        guard let time = layer(id: id)?.time,
              let range = layer(id: id)?.clipPieces?.rangeMS(ofPiece: index) else { return false }
        guard removeClipPiece(id, at: index) else { return false }
        removeTime(fromMS: time.inMS + range.start, toMS: time.inMS + range.end, exceptLayer: id)
        return true
    }

    /// Take a whole layer away and close the gap it leaves.
    @discardableResult
    public mutating func rippleDeleteLayer(_ id: UUID) -> Bool {
        // A page that opened the recording takes the time before its
        // dissolve with it, so the recording is back at 0:00.
        let opening = openingDissolveStartMS(id)
        guard let time = layer(id: id)?.time, removeLayer(id: id) != nil else { return false }
        if let opening {
            closeGap(endingAtMS: opening, lengthMS: opening, except: id)
        } else {
            closeGap(endingAtMS: time.outMS, lengthMS: time.lengthMS, except: id)
        }
        refreshDuration()
        return true
    }

    /// Everything that starts at or after the end of a stretch that has gone
    /// moves back by the stretch's length.
    ///
    /// Only what starts after it. A layer running across the stretch (music
    /// under the whole take) is left exactly as it was: shortening it would be
    /// cutting something nobody pointed at. A clip on a locked track stays put,
    /// because locking a track is saying exactly that.
    private mutating func closeGap(endingAtMS end: Int, lengthMS: Int, except: UUID) {
        guard lengthMS > 0 else { return }
        let locked = layerIDsOnLockedTracks()
        for layer in allLayers {
            guard layer.id != except, let time = layer.time, time.inMS >= end,
                  !locked.contains(layer.id) else { continue }
            updateLayer(id: layer.id) { $0.time = time.moved(toInMS: max(0, time.inMS - lengthMS)) }
        }
        refreshDuration()
    }

    // MARK: Split everything here

    /// Cut every clip the moment runs through, on every track that is not
    /// locked: Premiere's Add Edit to All Tracks. Answers how many were cut.
    ///
    /// Only clips, meaning layers that play a recording or a sound. A title
    /// has no frames to cut between, and a piece of one would mean nothing.
    /// Whether `splitEveryClip` would cut anything at `ms`, without cutting:
    /// the menu bar asks on every step of the playhead, and cutting a copy of
    /// the document to find out was most of a millisecond per clip.
    public func canSplitEveryClip(atMS ms: Int) -> Bool {
        let locked = layerIDsOnLockedTracks()
        var found = false
        forEachLayer { layer in
            guard !found, layer.holdsMedia, let time = layer.time, ms > time.inMS, ms < time.outMS,
                  !locked.contains(layer.id), var pieces = layer.clipPieces else { return }
            found = pieces.split(atMS: ms - time.inMS)
        }
        return found
    }

    @discardableResult
    public mutating func splitEveryClip(atMS ms: Int) -> Int {
        var cut = 0
        let locked = layerIDsOnLockedTracks()
        for layer in allLayers where layer.holdsMedia {
            guard let time = layer.time, ms > time.inMS, ms < time.outMS,
                  !locked.contains(layer.id) else { continue }
            if splitClip(layer.id, atMS: ms) { cut += 1 }
        }
        return cut
    }

    // MARK: Roll edit

    /// Move a join to a moment of the document, keeping the clip exactly as
    /// long as it was: the piece before the join gets longer by what the piece
    /// after it loses, or the other way round. Premiere's roll edit, and its
    /// Extend Edit to Playhead.
    ///
    /// Refused where either side has no recording left to give, where it
    /// would leave a piece too short to hold, and where a transition on the
    /// join could no longer be paid for.
    @discardableResult
    public mutating func rollClipCut(_ id: UUID, atCut index: Int, toMS ms: Int) -> Bool {
        guard let time = layer(id: id)?.time,
              var pieces = layer(id: id)?.clipPieces,
              let cut = pieces.cut(at: index) else { return false }
        let delta = ms - time.inMS - cut.atMS
        guard delta != 0, pieces.trimEnd(ofPiece: index - 1, byMS: delta),
              pieces.trimStart(ofPiece: index, byMS: delta) else { return false }
        if let transition = cut.transition,
           let rolled = pieces.cut(at: index),
           rolled.longestMS(for: transition) < transition.lengthMS { return false }
        updateLayer(id: id) { $0.setClipPieces(pieces) }
        return true
    }

    /// Roll any cut to a moment of the document: a join inside one clip, or
    /// the edit point where one clip ends and the next starts. The two look
    /// the same on the timeline, so they roll the same way.
    @discardableResult
    public mutating func rollCut(at place: TimelineCutPlace, toMS ms: Int) -> Bool {
        switch place {
        case let .join(clip, index):
            return rollClipCut(clip, atCut: index, toMS: ms)
        case let .edit(outgoing, incoming):
            return rollEditPoint(outgoing: outgoing, incoming: incoming, toMS: ms)
        }
    }

    /// Whether `rollCut` would roll, without rolling: a menu row asks.
    public func canRollCut(at place: TimelineCutPlace, toMS ms: Int) -> Bool {
        var trial = self
        return trial.rollCut(at: place, toMS: ms)
    }

    /// The edit point between two clips, rolled: the outgoing clip's last
    /// piece gets longer by what the incoming clip's first piece gives up, and
    /// the incoming clip starts that much later (or the other way round), so
    /// the frames either side of the old cut stay where they were and nothing
    /// after the two clips moves. A dip holding on its colour keeps its hold,
    /// since both clips move by the same amount.
    ///
    /// Refused on the same grounds as a join's roll: no recording left on
    /// one side, a piece left too short to hold, or a transition on the cut
    /// that could no longer be paid for.
    private mutating func rollEditPoint(outgoing: UUID, incoming: UUID, toMS ms: Int) -> Bool {
        guard let cut = editPointCut(outgoing: outgoing, incoming: incoming),
              let into = layer(id: incoming)?.time,
              var outPieces = layer(id: outgoing)?.clipPieces,
              var inPieces = layer(id: incoming)?.clipPieces else { return false }
        let delta = ms - cut.atMS
        guard delta != 0, outPieces.trimEnd(ofPiece: outPieces.count - 1, byMS: delta),
              inPieces.trimStart(ofPiece: 0, byMS: delta) else { return false }
        var trial = self
        trial.updateLayer(id: outgoing) { $0.setClipPieces(outPieces) }
        trial.updateLayer(id: incoming) { clip in
            clip.setClipPieces(inPieces)
            clip.time = clip.time?.moved(toInMS: into.inMS + delta)
        }
        if let transition = cut.transition {
            guard let rolled = trial.editPointCut(outgoing: outgoing, incoming: incoming),
                  rolled.longestMS(for: transition) >= transition.lengthMS else { return false }
        }
        self = trial
        return true
    }
}
