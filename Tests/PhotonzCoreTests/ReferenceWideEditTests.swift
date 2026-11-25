import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **The wide reference edit** (`ReferenceWideEdit.swift`, task
/// `an-edit-with-50-tracks-and-100-clips-scrolls-pla`): the shape a person
/// reported as slow on 2026-11-24, fifty tracks and a hundred clips.
@Suite("The wide reference edit")
struct ReferenceWideEditTests {

    static let fifty = ReferenceEdit.buildWide(tracks: 50)

    @Test("It is as tall as it says, with twice as many recordings as tracks", arguments: [50, 100])
    func tallAsItSays(tracks: Int) {
        let doc = tracks == 50 ? Self.fifty : ReferenceEdit.buildWide(tracks: tracks)
        // The tracks made; a track whose recordings speak draws their sound
        // on a row of its own under it, so the timeline is taller still.
        let made = doc.timelineTracks.filter { $0.attachedTo == nil }
        #expect(made.count == tracks)
        #expect(doc.timelineTracks.count > tracks)
        let census = ReferenceEdit.census(of: doc)
        #expect(census.lengthMS == ReferenceEdit.wideLengthMS)
        #expect(census.recordingClips == tracks * 2)
        #expect(census.titles >= 5)
        #expect(census.musicCoverageMS == census.lengthMS)
        #expect(census.transitions.values.reduce(0, +) >= 4)
        #expect(census.clipsWithSound >= tracks / 2)
        // Every track holds something, and some hold just one clip.
        let perTrack = made.map { doc.clipIDs(onTrack: $0.id).count }
        #expect(perTrack.allSatisfy { $0 > 0 })
        #expect(perTrack.contains(1))
        #expect(!doc.clipsOverlapOnATrack)
    }

    @Test("Ten recordings play at once somewhere and never more", arguments: [50, 100])
    func tenAtOnce(tracks: Int) {
        let doc = tracks == 50 ? Self.fifty : ReferenceEdit.buildWide(tracks: tracks)
        let counts = stride(from: 0, to: ReferenceEdit.wideLengthMS, by: 100)
            .map { ReferenceEdit.recordingsPlaying(in: doc, atMS: $0) }
        #expect(counts.max() == ReferenceEdit.wideOverlap)
        #expect(ReferenceEdit.recordingsPlaying(in: doc, atMS: ReferenceEdit.wideBusiestMS.lowerBound + 100)
                == ReferenceEdit.wideOverlap)
        #expect(counts.allSatisfy { $0 >= 1 })
    }

    @Test("Same seed, same document; every clip reads inside its recording")
    func sameSeed() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(Self.fifty) == encoder.encode(ReferenceEdit.buildWide(tracks: 50)))
        for layer in Self.fifty.allLayers {
            guard let movie = layer.movie, let time = layer.time else { continue }
            #expect(time.sourceInMS >= 0 && time.sourceInMS + time.lengthMS <= movie.durationMS)
        }
    }

    @Test("A recording added on a track of its own, and its undo, reach no other track's bars or row")
    func addedClipReachesOnlyItsOwnRow() throws {
        let doc = Self.fifty
        let pictures = doc.timelineTracks.filter { $0.kind == .video }
        let main = try #require(pictures.map { doc.clipIDs(onTrack: $0.id) }.max { $0.count < $1.count })
        let like = try #require(main.compactMap { doc.layer(id: $0) }
            .first { $0.movie != nil && ($0.time?.inMS ?? 0) > 22_000 })
        let time = try #require(like.time)
        var after = doc
        var layer = Layer(name: "Added", content: like.content, frame: like.frame)
        layer.movie = like.movie
        layer.time = LayerTime(inMS: time.inMS, outMS: time.outMS, sourceInMS: time.sourceInMS,
                               sourceLengthMS: like.movie?.durationMS ?? 0)
        let landed = after.land(layer, at: ClipLanding(target: .newTrack(at: 0), startMS: time.inMS,
                                                       lengthMS: time.lengthMS, edit: .overwrite,
                                                       trackName: "Added", allowed: true))
        let added = try #require(landed)
        let track = try #require(after.trackID(ofClip: added))
        for (now, was) in [(after, doc), (doc, after)] {
            let change = now.clipBarsChange(since: was)
            #expect(change == .only([added]))
            // Its own row, and the row of its own sound.
            let sound = (now.timelineTracks + was.timelineTracks).filter { $0.attachedTo == track }.map(\.id)
            #expect(now.tracksDrawn(differentlyBy: change, since: was)?.subtracting([track] + sound).isEmpty == true)
        }
    }

    /// A moment worked out the way it was before 2026-11-24: every layer at
    /// every step, on screen or not.
    static func workedOutInFull(_ doc: PhotonzDocument, atMS ms: Int) -> [Layer] {
        let moment = min(max(0, ms), doc.lastDrawableTimeMS)
        var shown = doc
        shown.layers = doc.layers.map { $0.shownTree(atTimeMS: moment) }
        let off = doc.layersOffScreenByTrack()
        for index in shown.layers.indices where off.contains(shown.layers[index].id) { shown.layers[index].isVisible = false }
        let cycle = max(1, doc.documentDurationMS)
        shown.layers = shown.layers.map { $0.movedTree(atDocumentTimeMS: moment, documentCycleMS: cycle) }
        shown.layers = shown.layers.map { $0.withPictureFadeShown(atDocumentTimeMS: moment) }
        shown.layers = shown.layers.map { $0.withZoomShown(atDocumentTimeMS: moment, origin: .zero, canvas: doc.canvasSize) }
        shown.layers = shown.layers.flatMap { $0.withTransitionDrawn(atTimeMS: moment, projection: doc.projection) }
        shown = doc.withEditPointTransitionsDrawn(shown, atMS: moment, framesInHand: nil)
        return shown.layers.filter(\.isVisible)
    }

    @Test("Leaving out what is off screen changes nothing that is drawn", arguments: [50, 6])
    func drawnTheSame(which: Int) {
        let doc = which == 50 ? Self.fifty : ReferenceEdit.build(minutes: 6)
        let cuts = doc.transitionCuts().prefix(12).map(\.atMS)
        let moments = Array(stride(from: 0, to: doc.documentDurationMS, by: 3700)) + cuts + cuts.map { $0 + 180 }
        for ms in moments {
            let now = doc.drawn(atTimeMS: ms).layers.filter(\.isVisible)
            #expect(now == Self.workedOutInFull(doc, atMS: ms), "at \(ms)")
        }
    }
}
