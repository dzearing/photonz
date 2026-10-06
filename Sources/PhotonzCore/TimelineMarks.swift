import Foundation

// Markers and the In and Out marks on a timeline's ruler.
//
// A Premiere editor drops a marker with M to remember a moment, and marks a
// stretch with I and O. Here both hang off the ruler's right-click menu (and
// the keys, once the timeline owns them), and both are the document's own
// facts: they save with it and undo like everything else.
//
// They are marks, not edits. Nothing about what plays or what is drawn depends
// on them, so a marker can never be the reason a picture changed.

/// One marker on the ruler.
public struct TimelineMarker: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    /// The moment of the document it marks.
    public var atMS: Int

    public init(id: UUID = UUID(), atMS: Int) {
        self.id = id
        self.atMS = atMS
    }
}

extension PhotonzDocument {

    /// A moment clamped onto the document, so a mark never sits off either
    /// end of the ruler it is drawn on.
    private func onTheRuler(_ ms: Int) -> Int {
        min(max(0, ms), documentDurationMS)
    }

    // MARK: Markers

    /// Drop a marker at a moment. Nil, and nothing written, where there is one
    /// there already: two markers on one frame are one marker drawn twice.
    @discardableResult
    public mutating func addMarker(atMS ms: Int) -> UUID? {
        let at = onTheRuler(ms)
        guard !markers.contains(where: { $0.atMS == at }) else { return nil }
        let marker = TimelineMarker(atMS: at)
        markers.append(marker)
        markers.sort { $0.atMS < $1.atMS }
        return marker.id
    }

    @discardableResult
    public mutating func removeMarker(_ id: UUID) -> Bool {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return false }
        markers.remove(at: index)
        return true
    }

    /// Move a marker to another moment, kept on the ruler and the markers kept
    /// in order. Dropped on another marker the two become one, the way two
    /// markers on one frame always are. False where nothing changed.
    @discardableResult
    public mutating func moveMarker(_ id: UUID, toMS ms: Int) -> Bool {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return false }
        let at = onTheRuler(ms)
        guard markers[index].atMS != at else { return false }
        if markers.contains(where: { $0.id != id && $0.atMS == at }) {
            markers.remove(at: index)
            return true
        }
        markers[index].atMS = at
        markers.sort { $0.atMS < $1.atMS }
        return true
    }

    /// What a playhead dragged along the ruler catches on: every key on these
    /// layers (every layer where nil) and every marker.
    public func playheadSnapMoments(keysOf layerIDs: [UUID]?) -> [Int] {
        Array(Set(keyMoments(layerIDs: layerIDs)).union(markers.map(\.atMS))).sorted()
    }

    /// What a marker dragged along the ruler catches on: every edit point,
    /// both ends of the video and the playhead. Never another marker, which it
    /// would only become.
    public func markerSnapMoments(playheadMS: Int?) -> [Int] {
        var moments = Set(editPointMoments())
        moments.insert(0)
        moments.insert(documentDurationMS)
        if let playheadMS { moments.insert(playheadMS) }
        return moments.sorted()
    }

    /// The marker the playhead is standing on: the nearest one within
    /// `withinMS` of `ms`, nil when none is that close. What Sequence ▸ Remove
    /// Marker takes away, the menu bar having no pointer to aim with.
    public func marker(nearMS ms: Int, withinMS reach: Int) -> UUID? {
        markers.filter { abs($0.atMS - ms) <= reach }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }?.id
    }

    @discardableResult
    public mutating func removeAllMarkers() -> Bool {
        guard !markers.isEmpty else { return false }
        markers = []
        return true
    }

    // MARK: In and Out

    /// Set the In mark. An In at or after the Out lets the Out go, the way
    /// Premiere does: the newest mark is the one you meant.
    public mutating func setMarkIn(atMS ms: Int) {
        let at = onTheRuler(ms)
        if let out = markOutMS, out <= at { markOutMS = nil }
        markInMS = at
    }

    /// Set the Out mark, letting an In at or after it go.
    public mutating func setMarkOut(atMS ms: Int) {
        let at = onTheRuler(ms)
        if let mark = markInMS, mark >= at { markInMS = nil }
        markOutMS = at
    }

    @discardableResult
    public mutating func clearMarkInOut() -> Bool {
        guard markInMS != nil || markOutMS != nil else { return false }
        markInMS = nil
        markOutMS = nil
        return true
    }

    /// ⌥I, Premiere's Clear In: the Out stays where it is.
    @discardableResult
    public mutating func clearMarkIn() -> Bool {
        guard markInMS != nil else { return false }
        markInMS = nil
        return true
    }

    /// ⌥O, Premiere's Clear Out.
    @discardableResult
    public mutating func clearMarkOut() -> Bool {
        guard markOutMS != nil else { return false }
        markOutMS = nil
        return true
    }

    // MARK: Mark Clip

    /// The clip X marks at a moment: the picked one where the playhead is on
    /// it, else the topmost picture under the playhead, else the topmost
    /// sound. A caption or a title is not a clip. Nil where nothing with media
    /// runs through the moment.
    public func markClipTarget(pickedLayerID: UUID?, atMS ms: Int) -> UUID? {
        func underThePlayhead(_ layer: Layer) -> Bool {
            guard layer.holdsMedia, layer.clipPieces != nil, let time = layer.time else { return false }
            return time.inMS <= ms && ms < time.outMS
        }
        if let pickedLayerID, let picked = layer(id: pickedLayerID), underThePlayhead(picked) {
            return pickedLayerID
        }
        let clips = allLayers.filter(underThePlayhead)
        return (clips.last { $0.movie != nil || $0.merged != nil } ?? clips.last)?.id
    }

    /// Where X puts the In and the Out: the start and end of the piece under
    /// the playhead in that clip, on the document's clock. On a cut the
    /// playhead belongs to the piece that starts there.
    public func markClipRangeMS(pickedLayerID: UUID?, atMS ms: Int) -> Range<Int>? {
        guard let id = markClipTarget(pickedLayerID: pickedLayerID, atMS: ms),
              let layer = layer(id: id), let time = layer.time, let pieces = layer.clipPieces,
              let index = pieces.pieceIndex(atMS: ms - time.inMS),
              let range = pieces.rangeMS(ofPiece: index) else { return nil }
        let start = onTheRuler(time.inMS + range.start)
        let end = onTheRuler(time.inMS + range.end)
        return end > start ? start..<end : nil
    }

    /// X, Premiere's Mark Clip: the In and the Out round the clip under the
    /// playhead, both at once, whatever was marked before. False where there
    /// is no clip there or the marks already sit round it.
    @discardableResult
    public mutating func markClip(pickedLayerID: UUID?, atMS ms: Int) -> Bool {
        guard let range = markClipRangeMS(pickedLayerID: pickedLayerID, atMS: ms),
              markInMS != range.lowerBound || markOutMS != range.upperBound else { return false }
        markInMS = range.lowerBound
        markOutMS = range.upperBound
        return true
    }

    /// The stretch the marks enclose, or nil where neither is set. Either one
    /// alone runs to the document's own end on its open side.
    public var markedRangeMS: Range<Int>? {
        guard markInMS != nil || markOutMS != nil else { return nil }
        let start = markInMS ?? 0
        let end = markOutMS ?? documentDurationMS
        guard end > start else { return nil }
        return start..<end
    }

    /// Where Premiere's Play In to Out starts and stops: the In (or the start)
    /// to the Out (or the end), never past the last frame there is to show.
    /// Nil where nothing is marked.
    public func playInToOutMS(lastFrameMS: Int) -> ClosedRange<Int>? {
        guard let range = markedRangeMS, range.lowerBound < lastFrameMS else { return nil }
        return range.lowerBound...min(range.upperBound, lastFrameMS)
    }
}
