import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Roll Edit to Playhead on the cut between two clips** (`TimelineMenuEdits.swift`).
///
/// A join inside one clip already rolled. The cut where one clip ends and the
/// next starts looks the same on the timeline, so it rolls the same way, as it
/// does in Premiere: the clip going out gets longer by exactly what the one
/// coming in gives up, the cut lands on the playhead, and nothing else moves.
@Suite("Rolling the cut between two clips")
struct EditPointRollTests {

    /// Ten seconds recorded, eight of them used: two seconds spare after.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000, hasSound: true)
    /// Six seconds recorded, read from 1.5s: a second and a half spare before.
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000, hasSound: true)

    /// The recording on V1 from 0 to 8s, b-roll butted onto it from 8s to
    /// 12s, both with their own sound, and a title later on the timeline.
    static func edit() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID, title: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Self.broll.frameRef(atSourceMS: 1500)),
                         frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        clip.movie = Self.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1500, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let broll = try #require(landed)
        var title = Layer(name: "Title", content: .image(Self.take.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        title.time = LayerTime(inMS: 9000, outMS: 11_000)
        doc.layers.append(title)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000])
        return (doc, take, broll, title.id)
    }

    @Test("Rolling later: the outgoing clip grows by exactly what the incoming one gives up")
    func rollLater() throws {
        var (doc, take, broll, title) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let tracks = (doc.trackID(ofClip: take), doc.trackID(ofClip: broll))
        let sounds = (doc.linkedSoundTrackID(ofClip: take), doc.linkedSoundTrackID(ofClip: broll))
        #expect(sounds.0 != nil && sounds.1 != nil)
        let titleTime = doc.layer(id: title)?.time
        let duration = doc.durationMS

        #expect(doc.canRollCut(at: place, toMS: 9000))
        let did = doc.rollCut(at: place, toMS: 9000)
        #expect(did)

        let out = try #require(doc.layer(id: take)?.time)
        let into = try #require(doc.layer(id: broll)?.time)
        #expect(out.inMS == 0 && out.outMS == 9000)
        #expect(into.inMS == 9000 && into.outMS == 12_000)
        // The incoming clip reads a second later into its recording, so the
        // frames after the new cut are where they were.
        #expect(doc.layer(id: broll)?.clipPieces?.piece(at: 0)?.sourceInMS == 2500)
        #expect(doc.layer(id: take)?.clipPieces?.pieces.last?.sourceOutMS == 9000)
        // Still one edit point, now on the playhead, with the spare moved.
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 9000)
        #expect(cut.cut.spareAfterOutMS == 1000)
        #expect(cut.cut.spareBeforeInMS == 2500)
        // Nothing else moved: same tracks, sound still linked under each clip,
        // the title where it was, and the document as long as it was.
        #expect(doc.trackID(ofClip: take) == tracks.0 && doc.trackID(ofClip: broll) == tracks.1)
        #expect(doc.linkedSoundTrackID(ofClip: take) == sounds.0)
        #expect(doc.linkedSoundTrackID(ofClip: broll) == sounds.1)
        #expect(doc.layer(id: title)?.time == titleTime)
        #expect(doc.durationMS == duration)
    }

    @Test("Rolling earlier works the other way round")
    func rollEarlier() throws {
        var (doc, take, broll, _) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let did = doc.rollCut(at: place, toMS: 7000)
        #expect(did)
        #expect(doc.layer(id: take)?.time?.outMS == 7000)
        #expect(doc.layer(id: broll)?.time?.inMS == 7000)
        #expect(doc.layer(id: broll)?.time?.outMS == 12_000)
        #expect(doc.layer(id: broll)?.clipPieces?.piece(at: 0)?.sourceInMS == 500)
        #expect(doc.documentCut(at: place)?.atMS == 7000)
    }

    @Test("Refused without the spare footage either side, and onto the cut itself")
    func refusedWithoutSpare() throws {
        let (doc, take, broll, _) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        // The take has two seconds after it, the b-roll a second and a half
        // before it.
        #expect(doc.canRollCut(at: place, toMS: 10_000))
        #expect(!doc.canRollCut(at: place, toMS: 10_001))
        #expect(doc.canRollCut(at: place, toMS: 6500))
        #expect(!doc.canRollCut(at: place, toMS: 6499))
        #expect(!doc.canRollCut(at: place, toMS: 8000))
        var tried = doc
        let did = tried.rollCut(at: place, toMS: 10_500)
        #expect(!did)
        #expect(tried.layers.map(\.time) == doc.layers.map(\.time))
        // Two clips that do not meet have no cut to roll.
        var apart = doc
        apart.moveClip(broll, toInMS: 9000)
        #expect(!apart.canRollCut(at: place, toMS: 8500))
    }

    @Test("A transition on the cut stays on it, and a roll it could not pay for is refused")
    func keepsTheTransition() throws {
        var (doc, take, broll, _) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let dissolve = ClipTransition(kind: .dissolve, lengthMS: 600)
        let put = doc.setTransition(dissolve, at: place)
        #expect(put)
        let did = doc.rollCut(at: place, toMS: 9000)
        #expect(did)
        #expect(doc.documentCut(at: place)?.cut.transition == dissolve)
        #expect(doc.documentCut(at: place)?.atMS == 9000)

        // A long dissolve spends 1.4s from each side; rolling a second either
        // way leaves one side with less than that.
        var (long, take2, broll2, _) = try Self.edit()
        let place2 = TimelineCutPlace.edit(outgoing: take2, incoming: broll2)
        let putLong = long.setTransition(ClipTransition(kind: .dissolve, lengthMS: 2800), at: place2)
        #expect(putLong)
        #expect(!long.canRollCut(at: place2, toMS: 9000))
        #expect(!long.canRollCut(at: place2, toMS: 7000))
        #expect(long.canRollCut(at: place2, toMS: 8400))
    }

    @Test("A dip that holds on its colour keeps its hold through a roll")
    func keepsTheHold() throws {
        var (doc, take, broll, _) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let dip = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 600), at: place)
        #expect(dip)
        let held = doc.holdOnColour(500, at: place)
        #expect(held == place)
        #expect(doc.layer(id: broll)?.time?.inMS == 8500)
        let did = doc.rollCut(at: place, toMS: 9000)
        #expect(did)
        #expect(doc.layer(id: take)?.time?.outMS == 9000)
        #expect(doc.layer(id: broll)?.time?.inMS == 9500)
        #expect(doc.documentCut(at: place)?.cut.transition?.holdMS == 500)
    }

    @Test("A join inside one clip rolls through the same call")
    func joinThroughTheSameCall() {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        let place = TimelineCutPlace.join(clip: clip, index: 1)
        #expect(doc.canRollCut(at: place, toMS: 5000))
        let did = doc.rollCut(at: place, toMS: 5000)
        #expect(did)
        #expect(doc.layer(id: clip)?.clipPieces?.piece(at: 0)?.lengthMS == 5000)
    }
}
