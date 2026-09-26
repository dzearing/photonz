import Foundation

// **A shape's bar never vanishes from its track, and an empty track can take
// one back** (`a-shape-s-bar-never-vanishes-from-its-track-and`).
//
// A layer is on the timeline while it has time or something moving, and the
// tracks are written down apart from it, so a track can outlive what was on
// it. The user met that as a Rectangle track with nothing on it and nothing to
// do with it but delete it. Three rules close it:
//
// - **A track the app made for a shape, a title or a group goes when an edit
//   empties it.** The tracks the app writes down for loose clips carry their
//   clip's id, so a track whose id was a layer's id is the app's. A track made
//   for a recording or a sound (V1, Audio) stays, as it does in every editor. Delete, ripple delete, lift
//   or extract over the layer, grouping it, carrying it to another track: the
//   edit takes the track with it, in the same step. A track somebody added by
//   hand is theirs and stays, empty, until they delete it.
// - **An empty track can take a layer**: `putOnTimeline` gives a layer on the
//   canvas and on no track a stretch from the playhead, and lands it (or one
//   already on the timeline) on the track it is put on.
// - **Delete Empty Tracks** clears every empty one at once, Premiere's command.

extension PhotonzDocument {

    /// The tracks with nothing on them, top to bottom. The Audio track a
    /// silent recording keeps waiting under its picture is not one of them:
    /// it is the app's place for the music, not something left behind.
    public var emptyTrackIDs: [UUID] {
        let layout = trackLayout()
        return layout.tracks.map(\.id).filter { id in
            id != Self.waitingAudioTrackID && (layout.clips[id] ?? []).isEmpty
                && (layout.linked[id] ?? []).isEmpty
        }
    }

    /// Take every empty track away: Premiere's Delete Empty Tracks.
    @discardableResult
    public mutating func deleteEmptyTracks() -> Bool {
        let empty = Set(emptyTrackIDs)
        guard !empty.isEmpty else { return false }
        materializeTracks()
        tracks.removeAll { empty.contains($0.id) }
        dropEmptyTrackGroupsLeftBehind()
        return true
    }

    /// After an edit, take away every track the app made for a layer that the
    /// edit left with nothing on it. `before` is the document as it was before
    /// the edit. Answers whether a track went.
    @discardableResult
    public mutating func dropTracksEmptied(since before: PhotonzDocument) -> Bool {
        guard !tracks.isEmpty, tracks.contains(where: { before.layer(id: $0.id) != nil }) else { return false }
        // Cheap first: nothing about which layer is on which track changed.
        guard tracks != before.tracks || timelineSignature != before.timelineSignature else { return false }
        let was = before.trackLayout()
        let now = trackLayout()
        let held = { (layout: TrackLayout, id: UUID) in
            !(layout.clips[id] ?? []).isEmpty || !(layout.linked[id] ?? []).isEmpty
        }
        // Only a track made for something drawn or written: V1 is where the
        // recording goes, and an editor keeps it when the recording is carried
        // off it, the way every editor does.
        let emptied = Set(tracks.map(\.id).filter { id in
            before.layer(id: id).map { !$0.holdsMedia } == true && held(was, id) && !held(now, id)
        })
        guard !emptied.isEmpty else { return false }
        tracks.removeAll { emptied.contains($0.id) }
        for layer in allLayers where layer.trackID.map(emptied.contains) == true {
            updateLayer(id: layer.id) { $0.trackID = nil }
        }
        dropEmptyTrackGroupsLeftBehind()
        return true
    }

    /// Which top level layer is on the timeline, and on which written track.
    private var timelineSignature: [TimelineSignatureEntry] {
        guard hasTime else { return [] }
        return layers.map { TimelineSignatureEntry(id: $0.id, trackID: $0.trackID, on: $0.isOnTheTimeline) }
    }

    private struct TimelineSignatureEntry: Equatable {
        var id: UUID
        var trackID: UUID?
        var on: Bool
    }

    private mutating func dropEmptyTrackGroupsLeftBehind() {
        let inUse = Set(tracks.compactMap(\.groupID))
        trackGroups.removeAll { !inUse.contains($0.id) }
    }

    // MARK: Putting a layer on the timeline

    /// The top level layers on the canvas and on no track, in a document with
    /// time: what Put on Timeline can offer. Topmost first, the way the
    /// layers list reads.
    public var layersOffTheTimeline: [Layer] {
        guard hasTime else { return [] }
        return layers.reversed().filter { canPutOnTimeline($0.id) }
    }

    /// Whether a layer is on the canvas and on no track, so Put on Timeline
    /// has something to do: a top level layer of a document with time, with no
    /// time of its own, nothing moving in it, no recording behind it, and not
    /// locked.
    public func canPutOnTimeline(_ id: UUID) -> Bool {
        guard hasTime, let layer = layers.first(where: { $0.id == id }) else { return false }
        return !layer.isOnTheTimeline && !layer.isLocked && !layer.hasMediaBehindIt
            && layer.clipTrackKind == .video
    }

    /// The stretch Put on Timeline gives a layer put at `ms`: five seconds from
    /// there, or, where less than half a second of the film is left, the last
    /// five seconds ending at its end, so it is on screen where it was put.
    func putSpan(atMS ms: Int) -> LayerTime {
        let end = max(documentDurationMS, LayerTime.shortestMS)
        let start = min(max(0, ms), end)
        let until = min(end, start + DrawnTime.atTheEndMS)
        if until - start >= DrawnTime.nearTheEndMS { return LayerTime(inMS: start, outMS: until) }
        return LayerTime(inMS: max(0, end - DrawnTime.atTheEndMS), outMS: end)
    }

    /// Put a layer on the timeline at `ms`, onto `trackID` when one is given.
    ///
    /// A layer on no track is given five seconds from there (`putSpan`); one
    /// already on the timeline keeps its length and moves to start there. On a
    /// track it must fit: the right kind, not locked, and nothing already on
    /// it at that time. Without a track it gets a row of its own, the way
    /// anything drawn on a video does.
    @discardableResult
    public mutating func putOnTimeline(_ id: UUID, atMS ms: Int, onTrack trackID: UUID? = nil) -> Bool {
        guard hasTime, let layer = layers.first(where: { $0.id == id }), !layer.isLocked,
              !layer.hasMediaBehindIt || trackID != nil else { return false }
        let span: LayerTime
        if let time = layer.time {
            span = time.moved(toInMS: max(0, ms))
        } else if layer.isOnTheTimeline {
            // Keyed but with no stretch of its own: it already covers the film.
            guard trackID != nil else { return false }
            span = putSpan(atMS: ms)
        } else {
            span = putSpan(atMS: ms)
        }
        if let trackID {
            guard let target = track(id: trackID), !target.isLocked,
                  target.kind.accepts(layer.clipTrackKind), !isClipOnLockedTrack(id) else { return false }
            let lands = span.inMS..<max(span.inMS + 1, span.outMS)
            let taken = clipIDs(onTrack: trackID).contains { other in
                guard other != id, let theirs = self.layer(id: other) else { return false }
                let range = theirs.time.map { $0.inMS..<max($0.inMS + 1, $0.outMS) }
                    ?? 0..<max(1, documentDurationMS)
                return lands.lowerBound < range.upperBound && range.lowerBound < lands.upperBound
            }
            guard !taken else { return false }
            let was = self
            materializeTracks()
            updateLayer(id: id) {
                $0.time = span
                $0.trackID = trackID
            }
            restackByTracks()
            // Writing the tracks down gave a loose layer a row of its own a
            // moment ago; it has just left it, so that row goes too.
            dropTracksEmptied(since: was)
        } else {
            guard layer.time != span else { return false }
            updateLayer(id: id) { $0.time = span }
        }
        refreshDuration()
        return true
    }

    /// Land every top level layer an edit added onto `trackID` at `ms`: what
    /// Add Rectangle, Add Text and Paste Here on a track's menu do with the
    /// layer they make, in the same step as making it. `before` is the
    /// document as it was before the edit. One that will not fit there keeps
    /// the row it was given.
    @discardableResult
    public mutating func landNewLayers(since before: PhotonzDocument, onTrack trackID: UUID, atMS ms: Int) -> Bool {
        let old = Set(before.layers.map(\.id))
        var landed = false
        for layer in layers.reversed() where !old.contains(layer.id) {
            landed = putOnTimeline(layer.id, atMS: ms, onTrack: trackID) || landed
        }
        return landed
    }
}
