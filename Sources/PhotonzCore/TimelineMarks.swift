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

    /// The stretch the marks enclose, or nil where neither is set. Either one
    /// alone runs to the document's own end on its open side.
    public var markedRangeMS: Range<Int>? {
        guard markInMS != nil || markOutMS != nil else { return nil }
        let start = markInMS ?? 0
        let end = markOutMS ?? documentDurationMS
        guard end > start else { return nil }
        return start..<end
    }
}
