import CoreGraphics
import Foundation

// A clip let go on the timeline (`docs/design/mocks/pages/video.html`, the
// `.lane.drop` and `.drophint` it lights; `comp-video.html` §02).
//
// Dropping a file on the picture has always landed it at the playhead, on a
// track of its own (`MediaDrop`). The timeline is where an editor actually puts
// b-roll: at the moment under the pointer, on the track under the pointer, and
// whatever was on that track makes room. That is this file.
//
// Two ways of making room, both Premiere's:
//
// - **Overwrite**, what a plain drop does. The new clip covers the stretch it
//   lands on; anything on the same track there is trimmed back to it, split
//   round it, or taken away when it is wholly covered. Nothing else moves.
// - **Insert**, with ⌘ held. Everything on the track from that moment on is
//   pushed along by the new clip's length, splitting the clip it lands inside.
//   Clips on the other tracks that start later go too, so a title stays over
//   the picture it was lined up with; a clip already playing across the
//   moment, like a music bed, plays on where it was. A locked track moves for
//   nothing.
//
// A clip split in two is two layers reading the same file. A clip's pieces can
// never hold a hole (`ClipPieces`), so a gap in the middle of one has to be the
// end of one layer and the start of the next.

/// How a clip let go on a track makes room there.
public enum ClipLandingEdit: String, Hashable, Codable, Sendable, CaseIterable {
    /// The new clip covers what was under it.
    case overwrite
    /// What comes after is pushed along to make room.
    case insert
}

/// Where a clip would land if it were let go of now, which is what the
/// timeline draws while it is still in the air and what the drop then does.
/// One answer, so the ghost and the landing cannot disagree.
public struct ClipLanding: Hashable, Sendable {
    /// The track it lands on, or the place a new one is made.
    public var target: TrackDrop
    /// When it starts, in the document's milliseconds.
    public var startMS: Int
    /// How long it runs.
    public var lengthMS: Int
    public var edit: ClipLandingEdit
    /// The name of the track it ends up on, a new one included.
    public var trackName: String
    /// False when nothing can land there. `isLocked` says why when it is the
    /// lock; otherwise the track holds something with no ends to make room
    /// round.
    public var allowed: Bool
    public var isLocked: Bool

    public init(target: TrackDrop, startMS: Int, lengthMS: Int, edit: ClipLandingEdit,
                trackName: String, allowed: Bool, isLocked: Bool = false) {
        self.target = target
        self.startMS = max(0, startMS)
        self.lengthMS = max(LayerTime.shortestMS, lengthMS)
        self.edit = edit
        self.trackName = trackName
        self.allowed = allowed
        self.isLocked = isLocked
    }

    public var endMS: Int { startMS + lengthMS }

    /// A start pulled onto the nearest edge within reach: where a clip, or
    /// the playhead, already is, so b-roll let go near the end of the
    /// recording butts onto it rather than leaving a sliver of black. The
    /// new clip's END is pulled as well as its start, so it can be let go
    /// to finish where something else begins. Nearest wins; the start wins a
    /// tie.
    public static func snapped(startMS ms: Int, lengthMS: Int, to edges: [Int],
                               withinMS reach: Int) -> Int {
        var best: (distance: Int, start: Int)?
        for edge in edges {
            for start in [edge, edge - lengthMS] where start >= 0 {
                let distance = abs(start - ms)
                guard distance <= reach, distance < (best?.distance ?? Int.max) else { continue }
                best = (distance, start)
            }
        }
        return best?.start ?? max(0, ms)
    }
}

/// Where two clips on one track meet with nothing between them: the cut an
/// editor selects to put a transition on (`comp-video.html` §02).
public struct TimelineEditPoint: Hashable, Sendable, Identifiable {
    public var trackID: UUID
    /// The clip that ends here.
    public var outgoing: UUID
    /// The clip that starts here.
    public var incoming: UUID
    public var atMS: Int

    public init(trackID: UUID, outgoing: UUID, incoming: UUID, atMS: Int) {
        self.trackID = trackID
        self.outgoing = outgoing
        self.incoming = incoming
        self.atMS = atMS
    }

    public var id: String { "\(outgoing.uuidString)>\(incoming.uuidString)" }
}

// MARK: - Where it would land

extension PhotonzDocument {

    /// Where a clip of `kind`, `lengthMS` long, let go at `ms` over `pointed`
    /// would land.
    ///
    /// A track of the wrong kind is not a refusal: a sound let go over the
    /// picture goes to the nearest sound track, the way Premiere puts audio on
    /// the audio track that matches, and a new one is made under the picture
    /// when there is none. Nil for `pointed` is the space past the tracks,
    /// which is a new track of that kind in the usual place.
    public func clipLanding(kind: DocumentTrack.Kind, lengthMS: Int, atMS ms: Int,
                            over pointed: TrackDrop?, edit: ClipLandingEdit) -> ClipLanding {
        let tracks = timelineTracks
        let used = Set(tracks.map(\.name))
        func newTrack(at index: Int) -> ClipLanding {
            ClipLanding(target: .newTrack(at: index), startMS: ms, lengthMS: lengthMS, edit: edit,
                        trackName: Self.freeTrackName(kind, used: used), allowed: true)
        }
        let defaultPlace = kind == .audio ? tracks.count : 0
        guard let pointed else { return newTrack(at: defaultPlace) }
        switch pointed {
        case .newTrack(let index):
            return newTrack(at: min(max(0, index), tracks.count))
        case .onto(let id):
            guard let index = tracks.firstIndex(where: { $0.id == id }) else {
                return newTrack(at: defaultPlace)
            }
            let chosen: DocumentTrack
            if tracks[index].kind.accepts(kind) {
                chosen = tracks[index]
            } else {
                // The nearest track that takes it, that is not locked, and
                // that is not carrying a clip's own sound at that moment: a
                // sound let go over the picture is new sound, not a
                // replacement for the recording's.
                let fits = tracks.indices.filter {
                    tracks[$0].kind.accepts(kind) && !tracks[$0].isLocked
                        && !linkedSound(onTrack: tracks[$0].id, overlapsMS: ms..<(ms + max(1, lengthMS)))
                }
                guard let nearest = fits.min(by: { abs($0 - index) < abs($1 - index) }) else {
                    return newTrack(at: defaultPlace)
                }
                chosen = tracks[nearest]
            }
            let allowed = !chosen.isLocked && !holdsTimelessClip(onTrack: chosen.id)
            return ClipLanding(target: .onto(chosen.id), startMS: ms, lengthMS: lengthMS, edit: edit,
                               trackName: chosen.name, allowed: allowed, isLocked: chosen.isLocked)
        }
    }

    /// Whether a track carries a layer that is there the whole way through,
    /// which has no ends to trim or push and so leaves no room for anything.
    private func holdsTimelessClip(onTrack id: UUID) -> Bool {
        clipIDs(onTrack: id).contains { layer(id: $0)?.time == nil }
    }

    /// Every moment a clip starts or ends, which is what a clip in the air
    /// snaps to.
    public var timelineEdgesMS: [Int] {
        var edges: Set<Int> = [0]
        for id in timelineClipLayers.map(\.id) {
            guard let time = layer(id: id)?.time else { continue }
            edges.insert(time.inMS)
            edges.insert(time.outMS)
        }
        return edges.sorted()
    }

    // MARK: - Landing it

    /// Put a clip on the timeline where `landing` says, making room on its
    /// track the way the landing's edit says. The layer arrives starting at
    /// the landing's moment whatever its own time said, as long as it was.
    ///
    /// Nil, and nothing changed, where the landing is refused or the layer
    /// has no time of its own to place.
    @discardableResult
    public mutating func land(_ layer: Layer, at landing: ClipLanding) -> UUID? {
        guard landing.allowed, let time = layer.time else { return nil }
        let placed = time.moved(toInMS: landing.startMS)
        materializeTracks()
        let trackID: UUID
        switch landing.target {
        case .onto(let id):
            guard let track = track(id: id), !track.isLocked,
                  track.kind.accepts(layer.clipTrackKind) else { return nil }
            trackID = id
        case .newTrack(let index):
            trackID = addTrack(layer.clipTrackKind, at: index)
        }
        switch landing.edit {
        case .overwrite: clearTrack(trackID, from: placed.inMS, to: placed.outMS)
        case .insert: pushAlong(trackID, atMS: placed.inMS, byMS: placed.lengthMS)
        }
        var arriving = layer
        arriving.time = placed
        arriving.trackID = trackID
        let id = arriving.id
        addLayer(arriving)
        restackByTracks()
        // A document that knows how long it is grows to hold what landed, and
        // what an insert pushed past its end.
        if let written = durationMS {
            durationMS = max(written, allLayers.compactMap { $0.time?.outMS }.max() ?? written)
        }
        return id
    }

    /// Make room for a clip from `start` to `end` on one track: trim what
    /// overlaps an end, split what spans both, take away what is covered.
    private mutating func clearTrack(_ trackID: UUID, from start: Int, to end: Int) {
        for id in clipIDs(onTrack: trackID) {
            guard let clip = layer(id: id), let time = clip.time,
                  time.inMS < end, start < time.outMS else { continue }
            let before = time.inMS < start ? clip.clipPart(fromMS: time.inMS, toMS: start) : nil
            let after = end < time.outMS ? clip.clipPart(fromMS: end, toMS: time.outMS) : nil
            replace(id, with: [before, after].compactMap { $0 })
        }
    }

    /// Push everything from `ms` on along by `delta`: on the landing track the
    /// clip the moment falls inside is split there; on every other unlocked
    /// track only what starts at or after it moves.
    private mutating func pushAlong(_ trackID: UUID, atMS ms: Int, byMS delta: Int) {
        for track in timelineTracks where !track.isLocked {
            for id in clipIDs(onTrack: track.id) {
                guard let clip = layer(id: id), let time = clip.time else { continue }
                // A clip starting a sliver before the moment is a clip starting
                // at it: splitting off a few milliseconds would leave a piece
                // nobody could see or take hold of.
                if time.inMS > ms - LayerTime.shortestMS {
                    updateLayer(id: id) { $0.time = time.moved(toInMS: time.inMS + delta) }
                } else if track.id == trackID, ms < time.outMS {
                    let before = clip.clipPart(fromMS: time.inMS, toMS: ms)
                    var after = clip.clipPart(fromMS: ms, toMS: time.outMS)
                    if let moved = after?.time { after?.time = moved.moved(toInMS: moved.inMS + delta) }
                    replace(id, with: [before, after].compactMap { $0 })
                }
            }
        }
    }

    /// Put `parts` where one clip was: the first keeps the clip's identity, so
    /// whatever was picked or pointed at it still is, and each after it is a
    /// new layer just above, on the same track, called the same.
    private mutating func replace(_ id: UUID, with parts: [Layer]) {
        guard let first = parts.first else {
            removeLayers(ids: [id])
            return
        }
        updateLayer(id: id) { $0 = first }
        guard parts.count > 1, let index = layers.firstIndex(where: { $0.id == id }) else { return }
        for (offset, part) in parts.dropFirst().enumerated() {
            var copy = part.duplicated()
            copy.name = part.name
            layers.insert(copy, at: index + 1 + offset)
        }
    }

    // MARK: - Edit points

    /// Every place on a track where one clip ends and the next starts on the
    /// same millisecond, left to right.
    public func editPoints(onTrack id: UUID) -> [TimelineEditPoint] {
        let clips = clipIDs(onTrack: id)
            .compactMap { clip -> (id: UUID, time: LayerTime)? in
                layer(id: clip)?.time.map { (clip, $0) }
            }
            .sorted { $0.time.inMS < $1.time.inMS }
        return zip(clips, clips.dropFirst()).compactMap { a, b in
            a.time.outMS == b.time.inMS
                ? TimelineEditPoint(trackID: id, outgoing: a.id, incoming: b.id, atMS: b.time.inMS)
                : nil
        }
    }
}

// MARK: - Part of a clip

extension Layer {

    /// The part of this clip between two moments of the document, as the same
    /// layer with that stretch: the pieces it is cut into, cut again at the
    /// two moments, reading exactly the frames they read before. Nil where
    /// that part is too short to be a clip at all.
    func clipPart(fromMS from: Int, toMS to: Int) -> Layer? {
        guard let time else { return nil }
        let lo = max(from, time.inMS), hi = min(to, time.outMS)
        guard hi - lo >= LayerTime.shortestMS else { return nil }
        if lo == time.inMS, hi == time.outMS { return self }
        var part = self
        // Only the part that still starts where the clip started arrives at
        // the cut the clip arrived at; a later part arrives at nothing yet.
        if lo > time.inMS { part.arrivalTransition = nil }
        // Words, a shape, an arrow: a place in time and nothing to read.
        guard holdsMedia, let pieces = clipPieces else {
            part.time = LayerTime(inMS: lo, outMS: hi)
            return part
        }
        var kept: [ClipPiece] = []
        var cursor = time.inMS
        for piece in pieces.pieces {
            let start = cursor, end = cursor + piece.lengthMS
            cursor = end
            let a = max(start, lo), b = min(end, hi)
            guard b - a >= ClipPiece.shortestMS else { continue }
            var cut = piece
            if a > start { cut = cut.trimmedStart(byMS: a - start) }
            if b < end { cut = cut.trimmedEnd(byMS: b - end) }
            kept.append(cut)
        }
        guard let first = kept.first else { return nil }
        part.time = LayerTime(inMS: lo, outMS: hi, sourceInMS: first.sourceInMS,
                              sourceLengthMS: time.sourceLengthMS)
        part.setClipPieces(ClipPieces(pieces: kept, sourceLengthMS: pieces.sourceLengthMS))
        return part
    }
}
