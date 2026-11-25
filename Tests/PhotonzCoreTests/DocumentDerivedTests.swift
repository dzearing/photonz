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

    @Test("The sound plan kept is the plan worked out afresh, and is kept")
    func soundPlanKept() {
        let doc = Self.six
        let first = doc.audioMix()
        #expect(!first.isEmpty)
        #expect(doc.audioMix() == Self.fresh(doc).audioMix())
        #expect(doc.derived.keptAudioMix != nil)
        for moment in stride(from: 0, to: 360_000, by: 7_300) {
            #expect(doc.audioMix(atMS: moment) == Self.fresh(doc).audioMix(atMS: moment))
        }
    }

    @Test("A trim, a level or a muted track is heard at once")
    func soundPlanChangeSeen() throws {
        var doc = Self.six
        let before = doc.audioMix()
        let heard = try #require(before.first)
        // A trim: the clip's sound ends half a second sooner.
        doc.updateLayer(id: heard.layerID) { layer in
            layer.time = layer.time.map { LayerTime(inMS: $0.inMS, outMS: $0.outMS - 500,
                                                    sourceInMS: $0.sourceInMS,
                                                    sourceLengthMS: $0.sourceLengthMS) }
        }
        #expect(doc.audioMix() != before)
        #expect(doc.audioMix() == Self.fresh(doc).audioMix())
        // A level pulled all the way down: nothing of that layer is heard.
        doc.updateLayer(id: heard.layerID) { layer in
            var level = layer.soundLevel ?? AudioLevel()
            level.gain = 0
            level.points = []
            layer.soundLevel = level
        }
        #expect(!doc.audioMix().contains { $0.layerID == heard.layerID })
        // A muted track: nothing on it is heard.
        let soundTrack = try #require(doc.timelineTracks.first { $0.kind == .audio && !doc.clipIDs(onTrack: $0.id).isEmpty })
        let onIt = Set(doc.clipIDs(onTrack: soundTrack.id))
        #expect(doc.audioMix().contains { onIt.contains($0.layerID) })
        doc.updateTrack(soundTrack.id) { $0.isMuted = true }
        #expect(!doc.audioMix().contains { onIt.contains($0.layerID) })
    }

    @Test("What the tree holds (fades, zooms, click effects) is kept, and a change to a layer is seen at once")
    func treeFactsKept() throws {
        // A copy of its own: the edit's answers are shared with every test.
        var doc = Self.fresh(Self.six)
        #expect(doc.derived.keptTreeFacts == nil)
        let first = (doc.hasPictureFades, doc.hasZooms, doc.hasClickEffects)
        #expect(doc.derived.keptTreeFacts != nil)
        let fresh = Self.fresh(doc)
        #expect(first == (fresh.allLayers.contains { $0.pictureFade != nil },
                          fresh.allLayers.contains { $0.zooms?.isEmpty == false },
                          fresh.allLayers.contains { $0.clickEffect?.isOn == true }))
        // Every zoom taken off: the next question says so.
        #expect(doc.hasZooms)
        for layer in doc.allLayers where layer.zooms?.isEmpty == false {
            doc.updateLayer(id: layer.id) { $0.zooms = nil }
        }
        #expect(doc.derived.keptTreeFacts == nil)
        #expect(!doc.hasZooms)
        // A fade put on one clip, and a click effect turned on on another.
        let clips = doc.allLayers.filter { $0.movie != nil && $0.time != nil }
        let faded = try #require(clips.first { $0.pictureFade == nil })
        let didFade = doc.setPictureFade(faded.id, .in, toMS: 400)
        #expect(didFade)
        #expect(doc.hasPictureFades)
        let clicked = try #require(clips.last)
        doc.setClickEffect(onClip: clicked.id, recorded: nil) { $0.isOn = true }
        #expect(doc.hasClickEffects)
        // And a copy keeps its own answers once either is written to.
        var copy = doc
        for layer in copy.allLayers where layer.clickEffect?.isOn == true {
            copy.setClickEffect(onClip: layer.id, recorded: nil) { $0.isOn = false }
        }
        #expect(!copy.hasClickEffects)
        #expect(doc.hasClickEffects)
    }

    @Test("A new canvas size or pixel scale starts the kept answers again")
    func canvasChangeForgets() {
        var doc = Self.six
        _ = doc.audioMix()
        #expect(doc.derived.keptAudioMix != nil)
        doc.canvasSize = CGSize(width: doc.canvasSize.width + 2, height: doc.canvasSize.height)
        #expect(doc.derived.keptAudioMix == nil)
        _ = doc.audioMix()
        doc.pixelScale += 1
        #expect(doc.derived.keptAudioMix == nil)
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

    @Test("Gaps kept per track are the gaps worked out afresh, and go with a write")
    func gapsKept() throws {
        var doc = Self.six
        let tracks = doc.timelineTracks.filter { $0.kind != .captions }
        for track in tracks {
            #expect(doc.gaps(onTrack: track.id) == Self.fresh(doc).gaps(onTrack: track.id))
            #expect(doc.gaps(onTrack: track.id) == Self.fresh(doc).gaps(onTrack: track.id))
        }
        #expect(doc.derived.keptGapTracks == Set(tracks.map(\.id)))
        // Take a clip away: the hole it leaves is a gap at once.
        let track = try #require(tracks.first { doc.clipIDs(onTrack: $0.id).count > 2 })
        let middle = doc.clipIDs(onTrack: track.id)[1]
        let before = doc.gaps(onTrack: track.id)
        doc.layers.removeAll { $0.id == middle }
        #expect(doc.derived.keptGapTracks.isEmpty)
        #expect(doc.gaps(onTrack: track.id) != before)
        #expect(doc.gaps(onTrack: track.id) == Self.fresh(doc).gaps(onTrack: track.id))
    }

    @Test("Part marks kept per clip are the marks worked out afresh, and go with a write")
    func childMarksKept() {
        var doc = Self.six
        let clips = doc.timelineTracks.flatMap { doc.clipIDs(onTrack: $0.id) }
        var marked = 0
        for id in clips {
            let asked = doc.timelineChildMarks(of: id)
            #expect(doc.timelineChildMarks(of: id) == asked)
            #expect(asked == Self.fresh(doc).timelineChildMarks(of: id))
            if !asked.isEmpty { marked += 1 }
        }
        #expect(doc.derived.keptChildMarkCount == clips.count)
        doc.layers = Array(doc.layers)
        #expect(doc.derived.keptChildMarkCount == 0)
        _ = marked
    }

    /// The app keeps answers of its own beside a document (the timeline's
    /// painted bars, `TimelinePaintedFacts`) and needs to know, cheaply,
    /// whether the document in hand is the one they were read off.
    @Test("A copy shares its worked-out answers until either has its layers or tracks written")
    func sharesAnswersUntilWritten() {
        let doc = Self.six
        var copy = doc
        #expect(doc.sharesWorkedOutAnswers(with: copy))
        #expect(copy.sharesWorkedOutAnswers(with: doc))
        // Content no answer is read off leaves them shared.
        copy.camera = nil
        #expect(doc.sharesWorkedOutAnswers(with: copy))
        copy.layers = Array(doc.layers)
        #expect(!doc.sharesWorkedOutAnswers(with: copy))
        var tracked = doc
        tracked.tracks = Array(doc.tracks)
        #expect(!doc.sharesWorkedOutAnswers(with: tracked))
        // Equal content read afresh is not the same answers.
        #expect(!doc.sharesWorkedOutAnswers(with: Self.fresh(doc)))
    }

    @Test("Where each layer sits is answered from the kept index once it is built, and a move is seen at once")
    func pathsFromTheIndex() throws {
        var doc = Self.six
        let ids = doc.allLayers.map(\.id)
        // Asked the way a walk would answer, before any index exists.
        let walked = ids.map { Self.fresh(doc).path(of: $0) }
        // Asked often enough that the index is built, the answers are the same.
        for _ in 0...DocumentDerived.lookupsBeforeIndex { _ = doc.path(of: ids[0]) }
        #expect(doc.derived.hasLayerIndex)
        #expect(ids.map { doc.path(of: $0) } == walked)
        #expect(doc.path(of: UUID()) == nil)
        // The top layer moved to the bottom: the next answer follows it.
        let moved = try #require(doc.layers.last)
        doc.layers = [moved] + doc.layers.dropLast()
        #expect(!doc.derived.hasLayerIndex)
        #expect(doc.path(of: moved.id) == [0])
    }
}
