import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Which clip bars an edit changed** (`ClipBarsChange.swift`): a bar on the
/// timeline is built again only for an edit that changes what it draws, so a
/// trim on one clip does not rebuild every bar in sight.
@Suite("Which clip bars an edit changed")
struct ClipBarsChangeTests {

    /// take 0-8s and b-roll 8-12s meeting on V1, and a third clip at 20-24s.
    static func edit() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID, far: UUID) {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "far", content: .image(EditPointTransitionTests.broll.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: EditPointTransitionTests.broll.pixelSize))
        clip.movie = EditPointTransitionTests.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 20_000, over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let far = try #require(landed)
        return (doc, take, broll, far)
    }

    @Test("The same document changes no bar")
    func sameDocument() throws {
        let (doc, _, _, _) = try Self.edit()
        #expect(doc.clipBarsChange(since: doc) == .none)
    }

    @Test("A trim on a clip nothing touches changes only its own bar")
    func trimAlone() throws {
        let (doc, take, broll, far) = try Self.edit()
        var trimmed = doc
        trimmed.updateLayer(id: far) {
            $0.time = LayerTime(inMS: 20_000, outMS: 23_000, sourceInMS: 0, sourceLengthMS: 6000)
        }
        let change = trimmed.clipBarsChange(since: doc)
        #expect(change == .only([far]))
        #expect(!change.contains(take))
        #expect(!change.contains(broll))
    }

    @Test("A trim on a clip that meets another changes both bars, and not one far off")
    func trimAtAnEditPoint() throws {
        let (doc, take, broll, far) = try Self.edit()
        var trimmed = doc
        trimmed.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 7000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let change = trimmed.clipBarsChange(since: doc)
        #expect(change.contains(take))
        #expect(change.contains(broll))
        #expect(!change.contains(far))
    }

    @Test("A name changes only that bar")
    func rename() throws {
        let (doc, _, _, far) = try Self.edit()
        var renamed = doc
        renamed.updateLayer(id: far) { $0.name = "far away" }
        #expect(renamed.clipBarsChange(since: doc) == .only([far]))
    }

    @Test("A clip added or taken away changes its own bar and the ones it meets, and not one far off")
    func clipAddedOrRemoved() throws {
        let (doc, take, broll, far) = try Self.edit()
        var fewer = doc
        fewer.layers.removeAll { $0.id == take }
        for change in [fewer.clipBarsChange(since: doc), doc.clipBarsChange(since: fewer)] {
            #expect(change == .only([take, broll]))
            #expect(!change.contains(far))
        }
    }

    @Test("A clip added on a track of its own, and its undo, change no other bar")
    func clipOnANewTrack() throws {
        let (doc, _, _, far) = try Self.edit()
        var clip = try #require(doc.layer(id: far))
        clip = Layer(name: "added", content: clip.content, frame: clip.frame)
        clip.movie = EditPointTransitionTests.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 6000)
        var more = doc
        // The tracks are written down on the first that is added, which is a
        // change to them, so both documents have theirs.
        var base = doc
        base.addTrack(.video)
        more = base
        let landed = more.land(clip, at: ClipLanding(target: .newTrack(at: 0), startMS: 0, lengthMS: 4000,
                                                     edit: .overwrite, trackName: "Added", allowed: true))
        let added = try #require(landed)
        #expect(more.clipBarsChange(since: base) == .only([added]))
        #expect(base.clipBarsChange(since: more) == .only([added]))
    }

    @Test("An empty track added or taken away changes no bar")
    func emptyTrack() throws {
        var (doc, _, _, _) = try Self.edit()
        doc.addTrack(.video)
        var more = doc
        more.addTrack(.video)
        #expect(more.clipBarsChange(since: doc) == .none)
        #expect(doc.clipBarsChange(since: more) == .none)
    }

    @Test("A trim reaches the row of its own track, and no other track's")
    func trimReachesItsRow() throws {
        let (base, _, _, far) = try Self.edit()
        var doc = base
        doc.addTrack(.video)
        let v1 = try #require(doc.trackID(ofClip: far))
        var trimmed = doc
        trimmed.updateLayer(id: far) {
            $0.time = LayerTime(inMS: 20_000, outMS: 23_000, sourceInMS: 0, sourceLengthMS: 6000)
        }
        let change = trimmed.clipBarsChange(since: doc)
        #expect(trimmed.tracksDrawn(differentlyBy: change, since: doc) == [v1])
    }

    @Test("A clip that moves to another track reaches the row it left and the one it landed on")
    func moveReachesBothRows() throws {
        let (base, _, _, far) = try Self.edit()
        var doc = base
        let v1 = try #require(doc.trackID(ofClip: far))
        let other = doc.addTrack(.video)
        var moved = doc
        let landed = moved.moveClip(far, toTrack: other)
        try #require(landed && moved.trackID(ofClip: far) == other)
        let change = moved.clipBarsChange(since: doc)
        let rows = moved.tracksDrawn(differentlyBy: change, since: doc)
        #expect(rows == nil || rows.map { $0.contains(v1) && $0.contains(other) } == true)
    }

    @Test("An empty track reaches no row, and a change to every bar reaches every row")
    func rowsOfEveryBar() throws {
        var (doc, _, _, _) = try Self.edit()
        doc.addTrack(.video)
        var added = doc
        added.addTrack(.video)
        #expect(added.tracksDrawn(differentlyBy: added.clipBarsChange(since: doc), since: doc) == [])
        #expect(doc.tracksDrawn(differentlyBy: .every, since: doc) == nil)
    }

    @Test("Layers put in another order change every bar")
    func reordered() throws {
        let (doc, _, _, _) = try Self.edit()
        var other = doc
        other.layers.reverse()
        #expect(other.clipBarsChange(since: doc) == .every)
    }

    @Test("A change to a track changes every bar")
    func trackChanged() throws {
        let (doc, _, _, _) = try Self.edit()
        var locked = doc
        locked.tracks = doc.timelineTracks.map { var track = $0; track.isLocked = true; return track }
        #expect(locked.clipBarsChange(since: doc) == .every)
    }

    @Test("A hold that pushes only the picture changes every bar, since others drift under it")
    func pictureOnlyHold() throws {
        let (doc, clip, voice) = HoldPushTests.withVoice()
        var held = doc
        let did = held.holdFrame(clip, atMS: 4000, forMS: 2000, push: .thisTrack)
        #expect(did)
        #expect(!held.holdDrifts(forLayer: voice).isEmpty)
        #expect(held.clipBarsChange(since: doc) == .every)
    }
}
