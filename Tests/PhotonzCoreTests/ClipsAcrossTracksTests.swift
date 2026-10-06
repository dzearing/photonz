import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Several picked clips carried up or down the timeline together**
/// (`ClipsAcrossTracks.swift`).
///
/// The clip in the hand says where it is going: onto a track, or onto a new
/// one between two. Every other picked clip goes the same number of tracks the
/// same way, and the same time, as one edit, the way a multi-selection moves in
/// Premiere and Final Cut. If any of them would land on a locked track, a track
/// of the wrong kind or on top of something already there, none of them change
/// track at all.
@Suite("Several clips across tracks")
struct ClipsAcrossTracksTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 6000, hasSound: true)

    /// A recording cut down to its first three seconds on V1 and a second clip
    /// after it on the same track, with V1 the only picture track.
    static func twoOnV1() throws -> (doc: PhotonzDocument, first: UUID, second: UUID, v1: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let first = doc.layers[0].id
        doc.updateLayer(id: first) { $0.time = LayerTime(inMS: 0, outMS: 3000, sourceLengthMS: 6000) }
        let second = doc.addClip(Self.movie, name: "b-roll", atMS: 3000,
                                 frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let v1 = try #require(doc.trackID(ofClip: first))
        let landedOn = try #require(doc.trackID(ofClip: second))
        let moved0 = doc.moveClip(second, toTrack: v1)
        #expect(moved0)
        // The track the second clip arrived on stays behind empty; take it away.
        doc.deleteTrack(landedOn)
        #expect(doc.timelineTracks.filter { $0.kind == .video }.map(\.id) == [v1])
        return (doc, first, second, v1)
    }

    static func title(_ name: String, _ inMS: Int, _ outMS: Int) -> Layer {
        var title = Layer(name: name, content: .text(TextContent(string: name)),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: inMS, outMS: outMS)
        return title
    }

    // MARK: - They go together

    @Test("Two clips on V1 carried above the top track both land on one new track made over it")
    func overTheTopMakesOneTrack() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let before = doc.timelineTracks.count
        #expect(doc.canMoveClips([first, second], carrying: first, to: .newTrack(at: 0)))
        let moved1 = doc.moveClips([first, second], carrying: first, to: .newTrack(at: 0))
        #expect(moved1)
        let tracks = doc.timelineTracks
        #expect(tracks.count == before + 1)
        let top = tracks[0]
        #expect(top.kind == .video)
        #expect(Set(doc.clipIDs(onTrack: top.id)) == [first, second])
        #expect(doc.clipIDs(onTrack: v1).isEmpty)
        // Neither moved in time.
        #expect(doc.layer(id: first)?.time?.inMS == 0)
        #expect(doc.layer(id: second)?.time?.inMS == 3000)
    }

    @Test("Carried onto an empty picture track above, both land on it, and the time moves with them")
    func ontoATrackAndLater() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        let moved2 = doc.moveClips([first, second], carrying: second, to: .onto(v2), byMS: 500)
        #expect(moved2)
        #expect(Set(doc.clipIDs(onTrack: v2)) == [first, second])
        #expect(doc.clipIDs(onTrack: v1).isEmpty)
        #expect(doc.layer(id: first)?.time?.inMS == 500)
        #expect(doc.layer(id: second)?.time?.inMS == 3500)
    }

    @Test("Clips on two tracks go up the same number of tracks, and the top one gets a new track over the top")
    func sameNumberOfTracks() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        // The second clip on its own track over V1, at the same time as the first.
        let v2 = doc.addTrack(.video, at: 0)
        doc.updateLayer(id: second) { $0.time = LayerTime(inMS: 0, outMS: 3000, sourceLengthMS: 6000) }
        let moved3 = doc.moveClip(second, toTrack: v2)
        #expect(moved3)
        // The first clip in the hand, carried up onto V2: the second has to go
        // one up from V2, which is over the top.
        let moved4 = doc.moveClips([first, second], carrying: first, to: .onto(v2))
        #expect(moved4)
        let tracks = doc.timelineTracks
        #expect(doc.trackID(ofClip: first) == v2)
        let made = try #require(doc.trackID(ofClip: second))
        #expect(made != v1 && made != v2)
        #expect(tracks.map(\.id).prefix(3) == [made, v2, v1])
        // Higher up is further forward in the picture.
        let order = doc.layers.map(\.id)
        #expect(try #require(order.firstIndex(of: second)) > #require(order.firstIndex(of: first)))
    }

    @Test("Carried down, clips go down: a title and a clip each one track lower")
    func down() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let title = Self.title("Hello", 0, 2000)
        doc.addLayer(title)
        // The title on a track of its own over V1.
        let titles = try #require(doc.trackID(ofClip: title.id))
        let under = doc.addTrack(.video, at: (doc.timelineTracks.map(\.id).firstIndex(of: v1) ?? 0) + 1)
        // The title over V1 and the first clip on V1, the title in the hand,
        // carried down onto V1: the first clip goes onto the track under V1.
        let moved6 = doc.moveClips([title.id, first], carrying: title.id, to: .onto(v1))
        #expect(moved6)
        #expect(doc.trackID(ofClip: title.id) == v1)
        #expect(doc.trackID(ofClip: first) == under)
        #expect(doc.trackID(ofClip: second) == v1)
        #expect(doc.clipIDs(onTrack: titles).isEmpty)
    }

    @Test("Dropped between two tracks, the hand's track goes to a new track there and the rest keep the same distance")
    func betweenTwo() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        let order = doc.timelineTracks.map(\.id)
        #expect(order.prefix(2) == [v2, v1])
        // A drop between V2 and V1 is one track up from V1.
        let moved7 = doc.moveClips([first, second], carrying: first, to: .newTrack(at: 1))
        #expect(moved7)
        let after = doc.timelineTracks.map(\.id)
        let made = try #require(doc.trackID(ofClip: first))
        #expect(after.prefix(3) == [v2, made, v1])
        #expect(doc.trackID(ofClip: second) == made)
    }

    @Test("Sound carried down past the last track gets a new sound track under it")
    func soundBelowTheBottom() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let music = doc.addSound(SoundRef(durationMS: 2000), name: "music", atMS: 0)
        let sting = doc.addSound(SoundRef(durationMS: 1000), name: "sting", atMS: 3000)
        let musicTrack = try #require(doc.trackID(ofClip: music))
        let moved8 = doc.moveClip(sting, toTrack: musicTrack)
        #expect(moved8)
        let count = doc.timelineTracks.count
        let moved9 = doc.moveClips([music, sting], carrying: music, to: .newTrack(at: count))
        #expect(moved9)
        let tracks = doc.timelineTracks
        #expect(tracks.count == count + 1)
        #expect(tracks.last?.kind == .audio)
        #expect(Set(doc.clipIDs(onTrack: try #require(tracks.last?.id))) == [music, sting])
    }

    // MARK: - Linked sound

    @Test("Each clip's own sound stays linked and comes along in time")
    func linkedSoundFollows() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let soundOfFirst = doc.layer(id: first)?.soundTrackID
        #expect(doc.layer(id: first)?.hasLinkedSound == true)
        let moved10 = doc.moveClips([first, second], carrying: first, to: .newTrack(at: 0), byMS: 1000)
        #expect(moved10)
        #expect(doc.layer(id: first)?.hasLinkedSound == true)
        #expect(doc.layer(id: second)?.hasLinkedSound == true)
        #expect(doc.layer(id: first)?.soundTrackID == soundOfFirst)
        // The sound is the clip's own, so it starts where the picture now does.
        #expect(doc.layer(id: first)?.time?.inMS == 1000)
        let audio = try #require(doc.timelineTracks.first { $0.kind == .audio })
        #expect(doc.linkedSoundClipIDs(onTrack: audio.id).contains(first))
    }

    // MARK: - Refused

    @Test("A locked track in the way stops every clip changing track, and nothing is written")
    func lockedStopsAll() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        doc.updateTrack(v2) { $0.isLocked = true }
        let before = doc
        #expect(!doc.canMoveClips([first, second], carrying: first, to: .onto(v2)))
        let moved11 = doc.moveClips([first, second], carrying: first, to: .onto(v2))
        #expect(!moved11)
        #expect(doc == before)
        #expect(doc.trackID(ofClip: second) == v1)
    }

    @Test("A clip of the wrong kind for its track stops the whole move: picture never lands on sound")
    func wrongKindStopsAll() throws {
        var (doc, first, _, v1) = try Self.twoOnV1()
        let title = Self.title("Hello", 0, 2000)
        doc.addLayer(title)
        // The title in the hand down onto V1, so the first clip would go down
        // onto Audio.
        #expect(doc.timelineTracks.map(\.id).firstIndex(of: v1).map { doc.timelineTracks[$0 + 1].kind } == .audio)
        #expect(!doc.canMoveClips([title.id, first], carrying: title.id, to: .onto(v1)))
    }

    @Test("Something already there on a track below stops the move")
    func occupiedStopsAll() throws {
        var (doc, first, second, v1) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        doc.addLayer(Self.title("In the way", 3500, 4000))
        let inTheWay = try #require(doc.layers.last?.id)
        let moved13 = doc.moveClip(inTheWay, toTrack: v2)
        #expect(moved13)
        #expect(!doc.canMoveClips([first, second], carrying: first, to: .onto(v2)))
        // Later still meets it.
        #expect(!doc.canMoveClips([first, second], carrying: first, to: .onto(v2), byMS: 400))
        #expect(doc.trackID(ofClip: second) == v1)
    }

    @Test("Picked clips moving out of each other's way are not in each other's way")
    func ownClipsDoNotBlock() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let v2 = doc.addTrack(.video, at: 0)
        doc.updateLayer(id: second) { $0.time = LayerTime(inMS: 0, outMS: 3000, sourceLengthMS: 6000) }
        let moved14 = doc.moveClip(second, toTrack: v2)
        #expect(moved14)
        // The first carried up onto V2, where the second sits at the same time
        // but is itself going one track further up.
        #expect(doc.canMoveClips([first, second], carrying: first, to: .onto(v2)))
    }

    @Test("Aimed at its own track, nothing changes track")
    func ownTrackIsNoMove() throws {
        let (doc, first, second, v1) = try Self.twoOnV1()
        #expect(!doc.canMoveClips([first, second], carrying: first, to: .onto(v1)))
    }

    @Test("A move left stops at nought, the way sliding several clips always has")
    func leftStopsAtNought() throws {
        var (doc, first, second, _) = try Self.twoOnV1()
        let moved15 = doc.moveClips([first, second], carrying: second, to: .newTrack(at: 0), byMS: -5000)
        #expect(moved15)
        #expect(doc.layer(id: first)?.time?.inMS == 0)
        #expect(doc.layer(id: second)?.time?.inMS == 3000)
    }
}

/// The walk step that carries a clip up or down tracks as well as along.
@Suite("Several clips across tracks: the walk step")
struct ClipsAcrossTracksWalkStepTests {

    @Test("dragClip takes tracksUp: how many tracks up the hand carries the clip, down when negative")
    func tracksUp() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "dragClip", "clip": "b-roll", "byMS": 500, "tracksUp": 1 },
                     { "do": "dragClip", "clip": "b-roll", "tracksUp": -2 },
                     { "do": "dragClip", "clip": "b-roll", "byMS": 500 } ] }
        """.utf8))
        #expect(script.steps[0] == .dragClip(clip: "b-roll", byMS: 500, modifiers: [], tracksUp: 1))
        #expect(script.steps[1] == .dragClip(clip: "b-roll", byMS: 0, modifiers: [], tracksUp: -2))
        // Left out, the clip stays on its track.
        #expect(script.steps[2] == .dragClip(clip: "b-roll", byMS: 500, modifiers: []))
    }
}
