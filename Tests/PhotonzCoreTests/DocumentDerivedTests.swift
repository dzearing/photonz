import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A document works out its tracks once, not once per question**
/// (`DocumentDerived.swift`).
///
/// The answers it keeps have to be exactly the answers worked out afresh, and
/// they have to go the moment anything they were read off changes, in the
/// document written to and never in a copy of it.
@Suite("Answers a document keeps")
struct DocumentDerivedTests {

    static let six = ReferenceEdit.build(minutes: 6)

    /// The same document with nothing kept: a round trip through a fresh
    /// array of the same layers gives it a new, empty store.
    static func fresh(_ doc: PhotonzDocument) -> PhotonzDocument {
        var copy = doc
        copy.layers = Array(doc.layers)
        return copy
    }

    @Test("Kept answers are the answers worked out afresh, on the reference edit")
    func keptMatchesFresh() {
        let doc = Self.six
        _ = doc.timelineTracks
        for track in doc.timelineTracks {
            _ = doc.editPoints(onTrack: track.id)
        }
        for moment in stride(from: 0, to: 360_000, by: 1_700) {
            _ = doc.movieFrames(atTimeMS: moment)
        }
        // Asked twice, the second time from what was kept.
        for track in doc.timelineTracks {
            #expect(doc.editPoints(onTrack: track.id) == Self.fresh(doc).editPoints(onTrack: track.id))
            #expect(doc.clipIDs(onTrack: track.id) == Self.fresh(doc).clipIDs(onTrack: track.id))
        }
        #expect(doc.timelineTracks == Self.fresh(doc).timelineTracks)
        for layer in doc.allLayers {
            #expect(doc.trackID(ofClip: layer.id) == Self.fresh(doc).trackID(ofClip: layer.id))
        }
        for moment in stride(from: 0, to: 360_000, by: 1_700) {
            #expect(doc.movieFrames(atTimeMS: moment) == Self.fresh(doc).movieFrames(atTimeMS: moment))
        }
        #expect(doc.editPointSoundCrossings().map(\.cutAtMS) == Self.fresh(doc).editPointSoundCrossings().map(\.cutAtMS))
        #expect(!doc.editPointSoundCrossings().isEmpty)
    }

    @Test("Every transition the edit draws is found at its own cut")
    func everyTransitionFound() {
        let doc = Self.six
        let arriving = doc.layers.filter { $0.arrivalTransition != nil }
        #expect(arriving.count >= 30)
        var seen = Set<UUID>()
        for clip in arriving {
            guard let track = doc.trackID(ofClip: clip.id),
                  let point = doc.editPoints(onTrack: track).first(where: { $0.incoming == clip.id }),
                  doc.editPointCut(outgoing: point.outgoing, incoming: clip.id)?.drawnTransition != nil
            else { continue }
            let moments = doc.editPointMoments(atMS: point.atMS)
            if moments.contains(where: { $0.onScreen == clip.id || $0.borrowed == clip.id }) {
                seen.insert(clip.id)
            }
        }
        #expect(seen.count >= 30)
    }

    @Test("Moving a clip to another track is seen at once")
    func moveSeen() throws {
        var doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 640, height: 400), durationMS: 10_000), name: "A")
        doc.materializeTracks()
        let a = doc.layers[0].id
        let first = try #require(doc.trackID(ofClip: a))
        let other = doc.addTrack(.video)
        #expect(doc.trackID(ofClip: a) == first)
        #expect(doc.clipIDs(onTrack: other).isEmpty)
        doc.updateLayer(id: a) { $0.trackID = other }
        #expect(doc.trackID(ofClip: a) == other)
        #expect(doc.clipIDs(onTrack: other) == [a])
    }

    @Test("A track renamed or locked is seen at once")
    func trackChangeSeen() throws {
        var doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 640, height: 400), durationMS: 10_000), name: "A")
        doc.materializeTracks()
        let a = doc.layers[0].id
        let track = try #require(doc.trackID(ofClip: a))
        #expect(!doc.isClipOnLockedTrack(a))
        doc.updateTrack(track) { $0.isLocked = true; $0.name = "Main" }
        #expect(doc.isClipOnLockedTrack(a))
        #expect(doc.track(id: track)?.name == "Main")
    }

    @Test("A copy changed leaves the original's answers alone, and the other way round")
    func copiesApart() throws {
        var original = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 640, height: 400), durationMS: 10_000), name: "A")
        original.materializeTracks()
        let a = original.layers[0].id
        let track = try #require(original.trackID(ofClip: a))
        _ = original.timelineTracks
        var copy = original
        copy.updateTrack(track) { $0.name = "Changed" }
        #expect(copy.track(id: track)?.name == "Changed")
        #expect(original.track(id: track)?.name != "Changed")
        // ...and the original changed after the copy asked.
        _ = copy.timelineTracks
        original.updateTrack(track) { $0.name = "Other" }
        #expect(original.track(id: track)?.name == "Other")
        #expect(copy.track(id: track)?.name == "Changed")
    }

    @Test("A cut moved by a trim moves its transition with it")
    func trimSeen() throws {
        var doc = Self.six
        let clip = try #require(doc.layers.first { $0.arrivalTransition != nil })
        let track = try #require(doc.trackID(ofClip: clip.id))
        let point = try #require(doc.editPoints(onTrack: track).first { $0.incoming == clip.id })
        #expect(doc.editPointCut(outgoing: point.outgoing, incoming: clip.id) != nil)
        // Pull the outgoing clip's end back: the two no longer meet, so the
        // edit point and its transition are gone.
        doc.updateLayer(id: point.outgoing) { layer in
            layer.time = layer.time.map { LayerTime(inMS: $0.inMS, outMS: $0.outMS - 500,
                                                    sourceInMS: $0.sourceInMS,
                                                    sourceLengthMS: $0.sourceLengthMS) }
        }
        #expect(!doc.editPoints(onTrack: track).contains { $0.incoming == clip.id })
        #expect(doc.editPointCut(outgoing: point.outgoing, incoming: clip.id) == nil)
        #expect(!doc.editPointMoments(atMS: point.atMS - 1).contains { $0.onScreen == clip.id || $0.borrowed == clip.id })
    }

    @Test("Kept answers take no part in equality, hashing or saving")
    func notContent() throws {
        let asked = Self.six
        _ = asked.timelineTracks
        _ = asked.movieFrames(atTimeMS: 30_000)
        let untouched = Self.fresh(Self.six)
        #expect(asked == untouched)
        #expect(asked.hashValue == untouched.hashValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(asked) == encoder.encode(untouched))
    }
}
