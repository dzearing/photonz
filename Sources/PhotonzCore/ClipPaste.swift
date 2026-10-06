import CoreGraphics
import Foundation

// A copied clip pasted at the playhead (Edit ▸ Paste on a video), the way
// Premiere's ⌘V pastes one.
//
// It starts at the playhead, on the track it was copied off where that stretch
// of the track is free, and on a new track straight over it where it is not,
// so a paste never covers anything already cut. Its own sound comes in with
// it, linked under it, because the timeline lays a clip's sound out wherever
// there is room (`DocumentTracks.swift`). A copy whose track this document
// does not have (it was cut, or copied in another window) lands the way Add
// Media at Playhead puts a recording down (`pictureLandingAtPlayhead`).

extension PhotonzDocument {

    /// Where `layer`, a copy of a clip that sat on `source`, lands when it is
    /// pasted with the playhead at `ms`. Nil for a layer with no time of its
    /// own, and for lines of captions, which paste as a range does.
    public func pasteLanding(for layer: Layer, fromTrack source: UUID?, atMS ms: Int) -> ClipLanding? {
        guard let time = layer.time else { return nil }
        let kind = layer.clipTrackKind
        guard kind != .captions else { return nil }
        let length = time.lengthMS
        let start = ClipLanding.snapped(startMS: max(0, ms), lengthMS: length, to: timelineEdgesMS,
                                        withinMS: ClipLanding.playheadReachMS)
        let span = start..<(start + max(LayerTime.shortestMS, length))
        let tracks = timelineTracks
        guard let source, let index = tracks.firstIndex(where: { $0.id == source }),
              tracks[index].kind.accepts(kind) else {
            return kind == .audio
                ? clipLanding(kind: .audio, lengthMS: length, atMS: start, over: nil, edit: .overwrite)
                : pictureLandingAtPlayhead(lengthMS: length, atMS: start)
        }
        let track = tracks[index]
        if !track.isLocked, !track.isHidden, isFree(track, over: span) {
            return ClipLanding(target: .onto(track.id), startMS: start, lengthMS: length,
                               edit: .overwrite, trackName: track.name, allowed: true)
        }
        // A new picture track goes over the one it came off, so the copy is
        // seen; a new sound track goes under it, where sound tracks are added.
        let place = kind == .audio ? index + 1 : index
        return ClipLanding(target: .newTrack(at: place), startMS: start, lengthMS: length,
                           edit: .overwrite,
                           trackName: Self.freeTrackName(kind, used: Set(tracks.map(\.name))),
                           allowed: true)
    }

    /// Paste `layer` at the playhead where `pasteLanding` says. The id it
    /// landed under, or nil where it has no landing.
    @discardableResult
    public mutating func pasteClip(_ layer: Layer, fromTrack source: UUID?, atMS ms: Int) -> UUID? {
        guard let landing = pasteLanding(for: layer, fromTrack: source, atMS: ms) else { return nil }
        return land(layer, at: landing)
    }

    /// Whether nothing on `track` plays anywhere in `span`, a clip's own
    /// linked sound included. A layer there the whole way through fills it.
    private func isFree(_ track: DocumentTrack, over span: Range<Int>) -> Bool {
        let busy = clipIDs(onTrack: track.id).contains { id in
            guard let time = layer(id: id)?.time else { return true }
            return time.inMS < span.upperBound && span.lowerBound < time.outMS
        }
        return !busy && !(track.kind == .audio && linkedSound(onTrack: track.id, overlapsMS: span))
    }
}
