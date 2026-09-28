import Foundation

// Copy, cut and paste a range of time
// (task `copy-cut-and-paste-a-range-of-time`).
//
// With a range drawn on the ruler, ⌘C takes that stretch of every track, the
// way Final Cut copies a range: the parts of the clips, titles, sounds and
// captions inside it, each cut to it and counted from its start, each
// remembering the track it came off. ⌘X takes the same and closes the gap
// (Extract). ⌘V lays the stretch back in at the playhead, each clip on the
// track it came from, covering whatever was there, the way Premiere pastes in
// overwrite. Nothing on any other track moves.
//
// A copy is made the way the range's own Delete and Ripple Delete make their
// cuts, so a caption, a clip cut into pieces and a title across an end come
// out exactly as Lift and Extract would leave them: on a trial document,
// everything after the range is lifted away and everything before it is
// extracted, which leaves what was inside starting at nought.
//
// Captions are one layer holding every line on its track, so pasted lines join
// the Captions layer already on that track, taking the place of the lines
// under them, rather than landing as a second Captions layer over the first.

/// A stretch of every track, on the clipboard.
public struct CopiedRange: Hashable, Codable, Sendable {
    /// How long the stretch is.
    public var lengthMS: Int
    /// What was in it, bottom of the stack first, each timed from the
    /// stretch's start and carrying the track it came off.
    public var clips: [Layer]
    /// The window it was copied in. Clips read pictures and recordings that
    /// only that window holds, so it pastes back there and nowhere else.
    public var origin: UUID?

    public init(lengthMS: Int, clips: [Layer], origin: UUID? = nil) {
        self.lengthMS = lengthMS
        self.clips = clips
        self.origin = origin
    }

    /// The pasteboard type the app writes these under, so copying anything
    /// else in any app replaces them the way a clipboard should.
    public static let pasteboardType = "com.dzearing.photonz.range"
}

extension PhotonzDocument {

    // MARK: Copy

    /// The part of every unlocked track inside `range`, counted from its
    /// start. Nil where the range has no length or nothing runs through it.
    public func copyRange(_ range: Range<Int>) -> CopiedRange? {
        let from = max(0, range.lowerBound)
        let to = range.upperBound
        guard to > from else { return nil }
        var trial = self
        trial.materializeTracks()
        let locked = trial.layerIDsOnLockedTracks()
        let last = trial.allLayers.compactMap { $0.time?.outMS }.max() ?? to
        if last > to { trial.liftStretch(fromMS: to, toMS: last) }
        if from > 0 { trial.extractStretch(fromMS: 0, toMS: from) }
        let length = to - from
        let clips = trial.layers.filter { layer in
            guard !layer.isLocked, !locked.contains(layer.id) else { return false }
            if layer.isCaptionsLayer {
                return layer.children.contains { $0.time.map { $0.outMS <= length } ?? false }
            }
            guard let time = layer.time else { return false }
            return time.outMS <= length && time.lengthMS > 0
        }
        guard !clips.isEmpty else { return nil }
        return CopiedRange(lengthMS: length, clips: clips)
    }

    // MARK: Cut

    /// ⌘X on a marked range: what the In and the Out enclose is copied, then
    /// taken out of every unlocked track with the gap closed, as Extract does.
    /// The tracks are written down first, so a track whose only clip went
    /// stays on the timeline for the paste to land on. Nil, and nothing
    /// changed, where there is nothing to take.
    public mutating func cutMarkedStretch() -> CopiedRange? {
        guard let range = markedRangeMS, canTakeOutMarkedStretch,
              let copied = copyRange(range) else { return nil }
        var trial = self
        trial.materializeTracks()
        guard trial.extractMarkedStretch() else { return nil }
        self = trial
        return copied
    }

    // MARK: Paste

    /// Lay a copied stretch in starting at `ms`: every clip on the track it
    /// came off, covering what was there. A track that has gone, is locked,
    /// or no longer takes that kind of clip is stood in for by a new one.
    /// Answers the layers that landed, captions joining lines already there
    /// excepted.
    @discardableResult
    public mutating func pasteRange(_ copied: CopiedRange, atMS ms: Int) -> [UUID] {
        guard !copied.clips.isEmpty else { return [] }
        let start = max(0, ms)
        materializeTracks()
        var standIns: [UUID: UUID] = [:]
        var landed: [UUID] = []
        for clip in copied.clips {
            let track = pasteTrack(for: clip, standIns: &standIns)
            if clip.isCaptionsLayer {
                if let id = pasteCaptions(clip, onTrack: track, atMS: start, lengthMS: copied.lengthMS) {
                    landed.append(id)
                }
                continue
            }
            guard let time = clip.time else { continue }
            var arriving = clip.duplicated()
            arriving.name = clip.name
            arriving.captionWords = arriving.captionWords?.map { $0.shifted(byMS: start) }
            let landing = ClipLanding(target: .onto(track), startMS: start + time.inMS,
                                      lengthMS: time.lengthMS, edit: .overwrite,
                                      trackName: "", allowed: true)
            if let id = land(arriving, at: landing) { landed.append(id) }
        }
        return landed
    }

    /// The track a pasted clip goes on: the one it came off where it can
    /// still take it, else one new track per track that could not.
    private mutating func pasteTrack(for clip: Layer, standIns: inout [UUID: UUID]) -> UUID {
        let kind = clip.clipTrackKind
        if let wanted = clip.trackID {
            if let track = track(id: wanted), !track.isLocked, track.kind.accepts(kind) { return wanted }
            if let standIn = standIns[wanted] { return standIn }
        }
        let made = addTrack(kind)
        if let wanted = clip.trackID { standIns[wanted] = made }
        return made
    }

    /// Pasted lines join the Captions layer on their track, taking the place
    /// of the lines under them. A track with no Captions layer left on it gets
    /// one. Answers the Captions layer made, nil where the lines joined one.
    private mutating func pasteCaptions(_ captions: Layer, onTrack track: UUID,
                                        atMS start: Int, lengthMS: Int) -> UUID? {
        let cues = captions.children.compactMap { cue -> Layer? in
            guard let time = cue.time else { return nil }
            var moved = cue.duplicated()
            moved.name = cue.name
            moved.time = time.moved(toInMS: time.inMS + start)
            moved.captionWords = moved.captionWords?.map { $0.shifted(byMS: start) }
            return moved
        }
        guard !cues.isEmpty else { return nil }
        let host = clipIDs(onTrack: track).first { layer(id: $0)?.isCaptionsLayer == true }
        if let host, let lines = layer(id: host)?.children.map(\.id), !lines.isEmpty {
            liftStretch(fromMS: start, toMS: start + lengthMS, onlyLayers: Set(lines))
        }
        if let host, layer(id: host) != nil {
            updateLayer(id: host) { group in
                group.children = (group.children + cues).sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
            }
            holdEverything()
            return nil
        }
        var group = captions.duplicated()
        group.name = captions.name
        group.children = cues
        group.trackID = track
        addLayer(group)
        restackByTracks()
        holdEverything()
        return group.id
    }

    /// A document that knows how long it is grows to hold what landed.
    private mutating func holdEverything() {
        guard let written = durationMS else { return }
        durationMS = max(written, allLayers.compactMap { $0.time?.outMS }.max() ?? written)
    }
}
