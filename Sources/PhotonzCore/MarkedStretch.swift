import Foundation

// Extract and Lift: what an In and an Out on the ruler are for.
//
// Cutting a five minute recording down to ninety seconds is mostly throwing
// long stretches away. A Premiere editor marks an In and an Out around each
// one and presses the apostrophe (Extract): the stretch comes out of every
// track and the gap closes. The semicolon (Lift) takes the same stretch out
// and leaves the gap where it was, so nothing after it moves.
//
// Both act on EVERY unlocked track, which is the difference from a ripple
// delete of one piece: music under the stretch is cut too, because the person
// pointed at the time, not at a clip. A locked track, and a locked layer, are
// left exactly as they were.
//
// What each does to a layer, by where it sits against the stretch:
//
// |                       | Extract                        | Lift                          |
// |-----------------------|--------------------------------|-------------------------------|
// | wholly inside         | goes                           | goes                          |
// | across the start      | loses its tail at the In       | the same                      |
// | across the end        | loses its head, lands at the In| loses its head, stays at Out  |
// | across the whole thing| loses the middle, one piece    | cut in two, a gap between     |
// | after it              | moves earlier by its length    | stays                         |
//
// Extract is the recording's own pieces for clips and sounds
// (`ClipPieces.removingStretch`) and `removeTime` for everything else, so a
// caption, a title and a caption's words squeeze exactly as they do when one
// piece is ripple deleted.

extension ClipPieces {

    /// The clip with the stretch from `start` to `end` of its own clock taken
    /// out and the join closed. Nil where nothing of it would be left; the
    /// pieces unchanged where the stretch misses them.
    ///
    /// The join is a hard cut: a transition that arrived at a piece now gone
    /// was paid for with frames that are gone too. A sliver shorter than any
    /// piece may be is dropped rather than kept too short to take hold of.
    public func removingStretch(fromMS start: Int, toMS end: Int) -> ClipPieces? {
        let from = max(0, start)
        let to = min(end, totalLengthMS)
        guard to > from else { return self }
        var kept: [ClipPiece] = []
        var join: Int?
        var elapsed = 0
        for piece in pieces {
            let pieceStart = elapsed
            let pieceEnd = elapsed + piece.lengthMS
            elapsed = pieceEnd
            if pieceEnd <= from || pieceStart >= to {
                if pieceStart >= to, join == nil { join = kept.count }
                kept.append(piece)
                continue
            }
            if from - pieceStart >= ClipPiece.shortestMS {
                kept.append(piece.trimmedEnd(byMS: -(pieceEnd - from)))
            }
            if pieceEnd - to >= ClipPiece.shortestMS {
                join = kept.count
                kept.append(piece.trimmedStart(byMS: to - pieceStart))
            }
        }
        guard !kept.isEmpty else { return nil }
        if let join, kept.indices.contains(join) { kept[join].transitionIn = nil }
        return ClipPieces(pieces: kept, sourceLengthMS: sourceLengthMS)
    }
}

extension PhotonzDocument {

    // MARK: Extract

    /// Take the stretch from `start` to `end` out of every unlocked track and
    /// close the gap: Premiere's Extract. Answers whether anything changed.
    @discardableResult
    public mutating func extractStretch(fromMS start: Int, toMS end: Int) -> Bool {
        let from = max(0, start)
        guard end > from else { return false }
        // Clips and sounds lose the stretch out of their own pieces first.
        // One wholly inside is left for `removeTime`, which drops it.
        var cut: Set<UUID> = []
        let locked = layerIDsOnLockedTracks()
        for layer in allLayers where layer.holdsMedia && takesPart(layer, fromMS: from, toMS: end, locked: locked) {
            guard let time = layer.time, time.inMS < from || time.outMS > end,
                  let pieces = layer.clipPieces,
                  let left = pieces.removingStretch(fromMS: from - time.inMS, toMS: end - time.inMS)
            else { continue }
            updateLayer(id: layer.id) { clip in
                clip.setClipPieces(left)
                // One that started inside the stretch starts at the join.
                clip.time = clip.time?.moved(toInMS: min(time.inMS, from))
            }
            cut.insert(layer.id)
        }
        let rest = removeTime(fromMS: from, toMS: end, exceptLayers: cut)
        if !cut.isEmpty { refreshDuration() }
        return rest || !cut.isEmpty
    }

    /// The apostrophe: extract what the In and the Out enclose. The marks are
    /// spent, since the stretch they named is gone, and every marker moves
    /// with the picture it was dropped on, one inside landing on the join.
    @discardableResult
    public mutating func extractMarkedStretch() -> Bool {
        guard let range = markedRangeMS,
              extractStretch(fromMS: range.lowerBound, toMS: range.upperBound) else { return false }
        let length = range.upperBound - range.lowerBound
        moveMarkers { at in
            at >= range.upperBound ? at - length : min(at, range.lowerBound)
        }
        clearMarkInOut()
        return true
    }

    /// Move every marker to where `move` says, keeping one where two land on
    /// the same frame: two markers on one frame are one marker drawn twice.
    mutating func moveMarkers(_ move: (Int) -> Int) {
        var seen: Set<Int> = []
        markers = markers.compactMap { marker in
            var moved = marker
            moved.atMS = move(marker.atMS)
            return seen.insert(moved.atMS).inserted ? moved : nil
        }
    }

    // MARK: Lift

    /// Take the stretch from `start` to `end` out of every unlocked track and
    /// leave the gap: Premiere's Lift. Nothing after it moves. A clip or a
    /// title across the whole stretch becomes two, on the same track, with
    /// the gap between them. Answers whether anything changed.
    @discardableResult
    public mutating func liftStretch(fromMS start: Int, toMS end: Int) -> Bool {
        let from = max(0, start)
        guard end > from else { return false }
        let locked = layerIDsOnLockedTracks()
        let hit = allLayers.filter { takesPart($0, fromMS: from, toMS: end, locked: locked) }
        guard !hit.isEmpty else { return false }
        // A clip cut in two stays on its own track only once the tracks are
        // written down: a clip on no track is given one of its own.
        if hit.contains(where: { $0.time.map { $0.inMS < from && $0.outMS > end } ?? false }) {
            materializeTracks()
        }
        var gone: Set<UUID> = []
        for layer in hit {
            guard let time = layer.time else { continue }
            if time.inMS >= from, time.outMS <= end {
                gone.insert(layer.id)
                continue
            }
            if time.inMS < from, time.outMS > end, let copy = duplicateLayer(id: layer.id) {
                if !keep(copy.id, fromMS: end, toMS: time.outMS) { gone.insert(copy.id) }
            }
            let keepFrom = time.inMS < from ? time.inMS : end
            let keepTo = time.inMS < from ? from : time.outMS
            if !keep(layer.id, fromMS: keepFrom, toMS: keepTo) { gone.insert(layer.id) }
        }
        removeLayersEmptyingCaptions(gone)
        refreshDuration()
        return true
    }

    /// The semicolon: lift what the In and the Out enclose, spending the marks.
    @discardableResult
    public mutating func liftMarkedStretch() -> Bool {
        guard let range = markedRangeMS,
              liftStretch(fromMS: range.lowerBound, toMS: range.upperBound) else { return false }
        clearMarkInOut()
        return true
    }

    // MARK: Whether there is anything to take

    /// Whether Extract or Lift would take anything out of the stretch: some
    /// unlocked layer on an unlocked track runs into it. The same answer a
    /// trial Lift gives, from one pass over the layers and without copying
    /// the document, because the menu bar asks it on every redraw.
    public func canTakeOutStretch(fromMS start: Int, toMS end: Int) -> Bool {
        let from = max(0, start)
        guard end > from else { return false }
        let locked = layerIDsOnLockedTracks()
        return layers.contains { top in
            top.containsSelfOrDescendant { takesPart($0, fromMS: from, toMS: end, locked: locked) }
        }
    }

    /// The same for what the In and the Out enclose. False with nothing marked.
    public var canTakeOutMarkedStretch: Bool {
        guard let range = markedRangeMS else { return false }
        return canTakeOutStretch(fromMS: range.lowerBound, toMS: range.upperBound)
    }

    // MARK: Pieces of the work

    /// Whether a layer is touched by a stretch: it runs into it, and nothing
    /// has locked it. `locked` is `layerIDsOnLockedTracks()`, asked once by
    /// the caller rather than once per layer.
    private func takesPart(_ layer: Layer, fromMS from: Int, toMS end: Int, locked: Set<UUID>) -> Bool {
        guard !layer.isLocked, let time = layer.time, time.inMS < end, time.outMS > from else { return false }
        return !locked.contains(layer.id)
    }

    /// Cut a layer down to the part of it between two moments of the
    /// document, where it stays. False where nothing of it is left to show:
    /// a caption whose every word was inside the stretch.
    private mutating func keep(_ id: UUID, fromMS keepFrom: Int, toMS keepTo: Int) -> Bool {
        guard let layer = layer(id: id), let time = layer.time else { return false }
        if layer.holdsMedia {
            guard var pieces = layer.clipPieces else { return false }
            // The tail first, so the head's offsets still read the same.
            if keepTo < time.outMS {
                guard let left = pieces.removingStretch(fromMS: keepTo - time.inMS, toMS: time.lengthMS)
                else { return false }
                pieces = left
            }
            if keepFrom > time.inMS {
                guard let left = pieces.removingStretch(fromMS: 0, toMS: keepFrom - time.inMS)
                else { return false }
                pieces = left
            }
            updateLayer(id: id) { clip in
                clip.setClipPieces(pieces)
                clip.time = clip.time?.moved(toInMS: keepFrom)
            }
            return true
        }
        let words = layer.captionWords?.compactMap { word -> TranscribedWord? in
            guard word.endMS > keepFrom, word.startMS < keepTo else { return nil }
            return word.retimed(startMS: max(word.startMS, keepFrom), endMS: min(word.endMS, keepTo))
        }
        if let words, words.isEmpty { return false }
        updateLayer(id: id) { cut in
            cut.time = LayerTime(inMS: keepFrom, outMS: keepTo,
                                 sourceInMS: time.sourceInMS, sourceLengthMS: time.sourceLengthMS)
            if let words { cut.captionWords = words }
        }
        refitFade(id)
        return true
    }
}
