import Foundation

// A box over the timeline picks everything it touches (`TrackRange.swift`
// picks the clips and pieces): the zoom bars on a recording's Zoom lane and the
// keys on a layer's key lanes too, so a person can box a stretch of an edit and
// move or delete the lot together, the way Premiere and Final Cut marquee
// selection works.
//
// A zoom or a key lives on its clip's own clock, so one on a clip that is
// itself picked rides with the clip: moving the clip moves it and deleting the
// clip takes it. Only the ones on clips left behind are moved or taken on
// their own (`besides`).

/// The zoom bars and keys a box picked, beside the clips and pieces it picked.
public struct TimelineBoxExtras: Hashable, Sendable {
    /// Zoom ids, by the clip they are on.
    public var zooms: [UUID: Set<UUID>]
    /// Keys, by the layer they key.
    public var keys: [UUID: Set<KeyRef>]

    public init(zooms: [UUID: Set<UUID>] = [:], keys: [UUID: Set<KeyRef>] = [:]) {
        self.zooms = zooms
        self.keys = keys
    }

    public var isEmpty: Bool { zoomCount == 0 && keyCount == 0 }
    public var zoomCount: Int { zooms.values.reduce(0) { $0 + $1.count } }
    public var keyCount: Int { keys.values.reduce(0) { $0 + $1.count } }

    /// The ones that do not ride with `layers`: those on any other clip.
    public func besides(_ layers: Set<UUID>) -> TimelineBoxExtras {
        TimelineBoxExtras(zooms: zooms.filter { !layers.contains($0.key) && !$0.value.isEmpty },
                          keys: keys.filter { !layers.contains($0.key) && !$0.value.isEmpty })
    }
}

extension TimelineMarquee {

    /// Whether a box from `span.lowerBound` to `span.upperBound` down the
    /// tracks reaches a row from `minY` to `maxY`.
    public static func reaches(_ span: ClosedRange<Double>, minY: Double, maxY: Double) -> Bool {
        minY <= span.upperBound && maxY >= span.lowerBound
    }
}

extension PhotonzDocument {

    /// Whether nothing on this clip may be picked or changed: it, or its
    /// track, is locked.
    private func isBoxLocked(_ id: UUID) -> Bool {
        guard let layer = layer(id: id) else { return true }
        return layer.isLocked || isClipOnLockedTrack(id)
    }

    // MARK: What a box touches

    /// The zooms on `clip` whose bar overlaps `range` of the timeline, earliest
    /// first. A bar that only meets the box at an edge is not touched.
    public func marqueeZooms(within range: Range<Int>, onClip clip: UUID) -> [UUID] {
        guard !range.isEmpty, !isBoxLocked(clip), let layer = layer(id: clip),
              let zooms = layer.zooms else { return [] }
        return zooms.compactMap { zoom -> (Int, UUID)? in
            guard let span = layer.timelineSpanMS(of: zoom.id),
                  span.start < range.upperBound, span.end > range.lowerBound else { return nil }
            return (span.start, zoom.id)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    /// The keys on these lanes of a layer that stand inside `range`, either
    /// edge included: a key is a moment, and a box drawn up to it means it.
    public func marqueeKeys(within range: Range<Int>, layerID: UUID, motionIDs: Set<UUID>) -> Set<KeyRef> {
        guard !motionIDs.isEmpty, !isBoxLocked(layerID) else { return [] }
        var picked = Set<KeyRef>()
        for lane in keyLanes(layerID: layerID) where motionIDs.contains(lane.motionID) {
            for key in lane.keys where key.documentMS >= range.lowerBound && key.documentMS <= range.upperBound {
                picked.insert(key.ref)
            }
        }
        return picked
    }

    // MARK: Acting on them

    /// Every zoom and key in `extras` moved `delta` ms along the timeline, each
    /// kept inside its clip. Answers the extras as they landed: a key is named
    /// by where it sits, so a moved key has a new name.
    @discardableResult
    public mutating func shiftBoxExtras(_ extras: TimelineBoxExtras, byMS delta: Int) -> TimelineBoxExtras {
        guard delta != 0 else { return extras }
        var landed = extras
        for (clip, ids) in extras.zooms where !isBoxLocked(clip) {
            guard let layer = layer(id: clip) else { continue }
            // The one leading the way goes first, so none stops against a
            // neighbour that is about to move out of its way.
            let order = (layer.zooms ?? []).map(\.id).filter { ids.contains($0) }
            for id in delta > 0 ? order.reversed() : order {
                guard let now = self.layer(id: clip), let span = now.timelineSpanMS(of: id),
                      let zoom = now.zooms?.first(where: { $0.id == id }) else { continue }
                let start = now.motionClockMS(atDocumentTimeMS: span.start + delta)
                let length = zoom.lengthMS
                updateZoom(onClip: clip, id: id) {
                    $0.startMS = start
                    $0.endMS = start + length
                }
            }
        }
        for (layerID, refs) in extras.keys where !isBoxLocked(layerID) {
            landed.keys[layerID] = moveKeys(layerID: layerID, refs, byMS: delta, copying: false)
        }
        return landed
    }

    /// How far, in ms of the timeline, every zoom and key in `extras` can move
    /// together before one of them meets its clip's end or a zoom that is not
    /// moving with it: earliest back to furthest on. A group carried further
    /// would leave that one behind, so the hand stops there instead.
    public func boxExtrasRoom(_ extras: TimelineBoxExtras) -> ClosedRange<Int> {
        var low = Int.min, high = Int.max
        for (clip, ids) in extras.zooms where !isBoxLocked(clip) {
            guard let layer = layer(id: clip), let time = layer.time else { continue }
            let spans = (layer.zooms ?? []).compactMap { zoom in
                layer.timelineSpanMS(of: zoom.id).map { (id: zoom.id, start: $0.start, end: $0.end) }
            }
            for span in spans where ids.contains(span.id) {
                let floor = spans.filter { !ids.contains($0.id) && $0.end <= span.start }.map(\.end).max()
                    ?? time.inMS
                let ceiling = spans.filter { !ids.contains($0.id) && $0.start >= span.end }.map(\.start).min()
                    ?? time.outMS
                low = max(low, floor - span.start)
                high = min(high, ceiling - span.end)
            }
        }
        for (layerID, refs) in extras.keys where !isBoxLocked(layerID) {
            guard let time = layer(id: layerID)?.time else { continue }
            for lane in keyLanes(layerID: layerID) {
                for key in lane.keys where refs.contains(key.ref) {
                    low = max(low, time.inMS - key.documentMS)
                    high = min(high, time.outMS - key.documentMS)
                }
            }
        }
        return min(low, 0)...max(high, 0)
    }

    /// Every zoom and key in `extras` taken away. Answers whether anything went.
    @discardableResult
    public mutating func removeBoxExtras(_ extras: TimelineBoxExtras) -> Bool {
        var changed = false
        for (clip, ids) in extras.zooms where !isBoxLocked(clip) {
            if removeZooms(onClip: clip, ids: ids) > 0 { changed = true }
        }
        for (layerID, refs) in extras.keys where !isBoxLocked(layerID) && !refs.isEmpty {
            if removeKeys(layerID: layerID, refs) { changed = true }
        }
        return changed
    }

    /// ⇧⌫ on a box's pick: the clips and pieces go and their gaps close on
    /// their own tracks, and the zooms and keys picked beside them on clips
    /// left in place go too, as one change for the caller to make one step.
    /// Answers whether anything went.
    @discardableResult
    public mutating func rippleDeleteBoxPick(_ picks: [TimelinePick], extras: TimelineBoxExtras) -> Bool {
        // The zooms and keys first: a key is named by where it sits, and the
        // ripple may move the clip it is on.
        let rest = extras.besides(Set(picks.filter { $0.piece == nil }.map(\.layerID)))
        let removed = removeBoxExtras(rest)
        let rippled = rippleDeletePicks(picks)
        return removed || rippled
    }

    // MARK: Copying them

    /// Every shift, in ms of the timeline, at which a copy of every zoom and
    /// key in `extras` lands inside its clip, and every zoom's copy clear of
    /// every zoom already on its clip (meeting one is fine): earliest first.
    /// Nothing to copy fits anywhere.
    public func boxExtrasCopyRoom(_ extras: TimelineBoxExtras) -> [ClosedRange<Int>] {
        var room = [Int.min...Int.max]
        func keep(_ allowed: ClosedRange<Int>) {
            room = room.compactMap { range in
                let low = max(range.lowerBound, allowed.lowerBound), high = min(range.upperBound, allowed.upperBound)
                return low <= high ? low...high : nil
            }
        }
        // Takes out every shift strictly between `low` and `high`.
        func refuse(_ low: Int, _ high: Int) {
            guard low < high - 1 else { return }
            room = room.flatMap { range -> [ClosedRange<Int>] in
                var kept: [ClosedRange<Int>] = []
                if range.lowerBound <= low { kept.append(range.lowerBound...min(range.upperBound, low)) }
                if range.upperBound >= high { kept.append(max(range.lowerBound, high)...range.upperBound) }
                return kept
            }
        }
        for (clip, ids) in extras.zooms where !isBoxLocked(clip) && !ids.isEmpty {
            guard let layer = layer(id: clip), let time = layer.time else { return [] }
            let spans = (layer.zooms ?? []).compactMap { layer.timelineSpanMS(of: $0.id) }
            for id in ids {
                guard let span = layer.timelineSpanMS(of: id) else { continue }
                keep((time.inMS - span.start)...(time.outMS - span.end))
                // Overlapping a zoom is a shift between its start less this
                // one's end and its end less this one's start.
                for other in spans { refuse(other.start - span.end, other.end - span.start) }
            }
        }
        for (layerID, refs) in extras.keys where !isBoxLocked(layerID) && !refs.isEmpty {
            guard let time = layer(id: layerID)?.time else { return [] }
            for lane in keyLanes(layerID: layerID) {
                for key in lane.keys where refs.contains(key.ref) {
                    keep((time.inMS - key.documentMS)...(time.outMS - key.documentMS))
                }
            }
        }
        return room
    }

    /// The shift nearest `wanted` at which copies of everything in `extras`
    /// fit (`boxExtrasCopyRoom`). Nil where they fit nowhere.
    public func boxExtrasCopyShift(_ extras: TimelineBoxExtras, nearest wanted: Int) -> Int? {
        boxExtrasCopyRoom(extras)
            .map { min(max(wanted, $0.lowerBound), $0.upperBound) }
            .min { abs($0 - wanted) < abs($1 - wanted) }
    }

    /// A copy of every zoom and key in `extras`, `delta` ms along the
    /// timeline on the clip it is on, the originals left where they are. A
    /// zoom that follows the pointer follows it again where its copy lands,
    /// from `pointerTracks` (by clip). Answers the copies; nil, with nothing
    /// changed, where any one of them would not fit.
    @discardableResult
    public mutating func copyBoxExtras(_ extras: TimelineBoxExtras, byMS delta: Int,
                                       pointerTracks: [UUID: PointerTrack] = [:]) -> TimelineBoxExtras? {
        guard delta != 0, boxExtrasCopyRoom(extras).contains(where: { $0.contains(delta) }) else { return nil }
        var trial = self
        var made = TimelineBoxExtras()
        for (clip, ids) in extras.zooms where !trial.isBoxLocked(clip) {
            guard let layer = trial.layer(id: clip), let range = layer.zoomSourceRange else { return nil }
            var zooms = layer.zooms ?? []
            var copies: [ClipZoom] = []
            for zoom in zooms where ids.contains(zoom.id) {
                guard let span = layer.timelineSpanMS(of: zoom.id) else { return nil }
                var copy = zoom
                copy.id = UUID()
                copy.startMS = layer.motionClockMS(atDocumentTimeMS: span.start + delta)
                copy.endMS = copy.startMS + zoom.lengthMS
                guard copy.startMS >= range.lowerBound, copy.endMS <= range.upperBound,
                      !zooms.contains(where: { $0.startMS < copy.endMS && $0.endMS > copy.startMS })
                else { return nil }
                if copy.followsCursor, let track = pointerTracks[clip] { copy.bakeCursor(from: track) }
                copies.append(copy)
            }
            guard !copies.isEmpty else { continue }
            zooms += copies
            trial.updateLayer(id: clip) { $0.zooms = zooms.sorted { $0.startMS < $1.startMS } }
            made.zooms[clip] = Set(copies.map(\.id))
        }
        for (layerID, refs) in extras.keys where !trial.isBoxLocked(layerID) && !refs.isEmpty {
            let landed = trial.moveKeys(layerID: layerID, refs, byMS: delta, copying: true)
            if landed != refs { made.keys[layerID] = landed }
        }
        guard !made.isEmpty else { return nil }
        self = trial
        return made
    }
}

/// What the panel says about several things picked on the timeline at once: how
/// many, and how many of each kind, in the words the panel's kind chip uses
/// (`ClipLine.kind(of:)`). Nil for one thing or none, which the rest of the
/// panel already describes.
public struct TimelinePickSummary: Hashable, Sendable {
    public let count: Int
    /// "6 picked".
    public let title: String
    /// "2 clips, 1 title, 1 sound, 2 zooms".
    public let detail: String

    /// Each kind's word, one and many, in the order the line names them.
    private static let words: [(kind: String, one: String, many: String)] = [
        ("Clip", "clip", "clips"),
        ("Title", "title", "titles"),
        ("Graphic", "graphic", "graphics"),
        ("Instance", "instance", "instances"),
        ("Audio", "sound", "sounds"),
        ("Captions", "captions track", "captions tracks"),
        ("Caption", "caption", "captions"),
    ]

    public init?(kinds: [String], pieces: Int, zooms: Int, keys: Int) {
        var counts: [String: Int] = [:]
        for kind in kinds { counts[kind, default: 0] += 1 }
        var parts: [String] = []
        for word in Self.words {
            guard let n = counts.removeValue(forKey: word.kind), n > 0 else { continue }
            parts.append("\(n) \(n == 1 ? word.one : word.many)")
        }
        // Anything the list has no word for is still counted.
        let rest = counts.values.reduce(0, +)
        if rest > 0 { parts.append("\(rest) other") }
        for (n, one, many) in [(pieces, "piece", "pieces"), (zooms, "zoom", "zooms"), (keys, "key", "keys")]
        where n > 0 {
            parts.append("\(n) \(n == 1 ? one : many)")
        }
        let count = kinds.count + pieces + zooms + keys
        guard count >= 2 else { return nil }
        self.count = count
        self.title = "\(count) picked"
        self.detail = parts.joined(separator: ", ")
    }
}
