import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A transition on the cut between two clips** (`EditPointTransitions.swift`).
///
/// The cut inside one clip already had transitions; this is the cut an editor
/// actually makes, where one recording ends on a track and the next one starts
/// on the same millisecond (`comp-video.html` §02). Same rules as inside a
/// clip: it is paid for with spare media either side, nothing moves, and what
/// is on screen is answered once for the canvas and the exporter.
@Suite("A transition on the cut between two clips")
struct EditPointTransitionTests {

    /// Ten seconds recorded, eight of them used: two seconds spare after.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000)
    /// Six seconds recorded, read from 1.5s: a second and a half spare before.
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000)

    /// The recording on V1 from 0 to 8s, and b-roll butted onto it from 8s to
    /// 12s: one edit point, at 8s.
    static func edit() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID) {
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
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000])
        return (doc, take, broll)
    }

    // MARK: - The six kinds

    @Test("Six kinds, and the four that put both shots on screen need an overlap")
    func sixKinds() {
        #expect(ClipTransitionKind.allCases.map(\.title)
                == ["Cross dissolve", "Dip to black", "Dip to white", "Push", "Wipe", "Blur through"])
        #expect(ClipTransitionKind.allCases.filter(\.needsOverlap)
                == [.dissolve, .push, .wipe, .blurThrough])
        #expect(ClipTransitionKind.push.note == "needs overlap")
        #expect(ClipTransitionKind.dipToWhite.note == "no overlap")
    }

    // MARK: - What the cut can afford

    @Test("The cut between two clips knows each side's spare media")
    func spareEitherSide() throws {
        let (doc, take, broll) = try Self.edit()
        let cut = try #require(doc.documentCut(at: .edit(outgoing: take, incoming: broll)))
        #expect(cut.atMS == 8000)
        #expect(cut.outgoingName == "take")
        #expect(cut.incomingName == "b-roll")
        #expect(cut.cut.spareAfterOutMS == 2000)
        #expect(cut.cut.spareBeforeInMS == 1500)
        // Twice the smaller spare, since a dissolve across the cut spends
        // half its length from each side.
        #expect(cut.cut.longestMS(of: .dissolve) == 3000)
        #expect(cut.cut.longestMS(of: .push) == 3000)
        // A dip spends none, so only the middles of the clips limit it.
        #expect(cut.cut.longestMS(of: .dipToBlack) == 4000)
        #expect(cut.cut.transition == nil)
        #expect(ClipTransitionCopy.spareShort(cut.cut) == "spare 2.0s / 1.5s")
    }

    @Test("Two clips that do not meet have no cut to put anything on")
    func noCutWithoutAnEditPoint() throws {
        var (doc, take, broll) = try Self.edit()
        let moved = doc.moveClip(broll, toInMS: 9000)
        #expect(moved)
        #expect(doc.documentCut(at: .edit(outgoing: take, incoming: broll)) == nil)
        let did = doc.setTransition(ClipTransition(kind: .dissolve), at: .edit(outgoing: take, incoming: broll))
        #expect(did == false)
    }

    // MARK: - Putting one on

    @Test("A dissolve between two clips moves nothing and is carried by the incoming clip")
    func putADissolveOn() throws {
        var (doc, take, broll) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let before = doc.layers.map(\.time)
        let did = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600), at: place)
        #expect(did)
        #expect(doc.layers.map(\.time) == before)
        #expect(doc.layer(id: broll)?.arrivalTransition == ClipTransition(kind: .dissolve, lengthMS: 600))
        #expect(doc.documentCut(at: place)?.cut.transition?.kind == .dissolve)
        #expect(doc.documentCut(at: place)?.cut.spentEachSideMS == 300)
        #expect(ClipTransitionCopy.paidWith(try #require(doc.documentCut(at: place)).cut)
                == "0.3s + 0.3s of spare")
    }

    @Test("Longer than the spare can pay for is refused, and a dip still fits")
    func refusedPastTheSpare() throws {
        var (doc, take, broll) = try Self.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let tooLong = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 3500), at: place)
        #expect(tooLong == false)
        let dip = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 3500), at: place)
        #expect(dip)
        let off = doc.setTransition(nil, at: place)
        #expect(off)
        #expect(doc.layer(id: broll)?.arrivalTransition == nil)
    }

    @Test("A cut between two sounds takes no picture transition")
    func notOnSound() throws {
        var doc = try Self.edit().doc
        let first = doc.addSound(SoundRef(durationMS: 4000), name: "one", atMS: 0)
        let track = try #require(doc.trackID(ofClip: first))
        let second = doc.clipLanding(kind: .audio, lengthMS: 4000, atMS: 4000,
                                     over: .onto(track), edit: .overwrite)
        var sound = try #require(doc.layer(id: first))
        sound = sound.duplicated()
        sound.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 4000)
        let landed = doc.land(sound, at: second)
        let secondID = try #require(landed)
        #expect(doc.editPoints(onTrack: track).count == 1)
        #expect(doc.documentCut(at: .edit(outgoing: first, incoming: secondID)) == nil)
    }

    // MARK: - What is on screen

    @Test("Before the cut the outgoing clip is on screen with the incoming one reading early over it")
    func beforeTheCut() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        // 250ms into a second-long dissolve that starts at 7.5s.
        let shown = doc.drawn(atTimeMS: 7750)
        let partner = try #require(shown.layers.first { $0.id != take && $0.id != broll && $0.isVisible })
        #expect(partner.style.opacity == 0.25)
        let requests = doc.movieFrames(atTimeMS: 7750)
        // The take's own frame, and b-roll a quarter second before its in point.
        #expect(requests.contains { $0.movie == Self.take && abs($0.sourceMS - 7750) < 40 })
        #expect(requests.contains { $0.movie == Self.broll && abs($0.sourceMS - 1250) < 40 })
        #expect(requests.contains { $0.layerID == partner.id })
    }

    @Test("After the cut the incoming clip is on screen and the outgoing one runs on under it")
    func afterTheCut() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        let shown = doc.drawn(atTimeMS: 8250)
        let order = shown.layers.filter(\.isVisible).map(\.id)
        let brollAt = try #require(order.firstIndex(of: broll))
        // The outgoing picture is drawn straight under the incoming one.
        #expect(brollAt > 0)
        #expect(shown.layers.first { $0.id == broll }?.style.opacity == 0.75)
        let requests = doc.movieFrames(atTimeMS: 8250)
        #expect(requests.contains { $0.movie == Self.take && abs($0.sourceMS - 8250) < 40 })
        #expect(requests.contains { $0.movie == Self.broll && abs($0.sourceMS - 1750) < 40 })
    }

    @Test("A dip between two clips spends nothing and is all colour on the cut")
    func dipBetweenClips() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        let shown = doc.drawn(atTimeMS: 8000)
        let dip = try #require(shown.layers.last { $0.isVisible })
        #expect(dip.style.opacity == 1)
        if case .annotation(let shape) = dip.content {
            #expect(shape.fillColorHex == "#FFFFFF")
        } else {
            Issue.record("the dip is not a panel of colour")
        }
        // Only one frame fetched: nobody reads into the spare for a dip.
        #expect(doc.movieFrames(atTimeMS: 8000).count == 1)
    }

    @Test("Half way through a push each shot has half the frame, and nothing spills out of it")
    func pushSlices() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .push, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        let shown = doc.drawn(atTimeMS: 8000)
        let visible = shown.layers.filter(\.isVisible)
        #expect(visible.count == 2)
        let frames = visible.map(\.frame).sorted { $0.minX < $1.minX }
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 50, height: 60))
        #expect(frames[1] == CGRect(x: 50, y: 0, width: 50, height: 60))
        // Each is a window that cuts off what leaves it, holding the whole
        // shot moved along: the outgoing one half off to the left, the
        // incoming one half in from the right.
        let left = try #require(visible.first { $0.frame.minX == 0 })
        let right = try #require(visible.first { $0.frame.minX == 50 })
        #expect(left.clipsToBounds && right.clipsToBounds)
        #expect(left.children.first?.frame == CGRect(x: -50, y: 0, width: 100, height: 60))
        #expect(right.children.first?.frame == CGRect(x: 0, y: 0, width: 100, height: 60))
    }

    @Test("A wipe draws the incoming shot over the left of the outgoing one")
    func wipeSlices() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .wipe, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        let shown = doc.drawn(atTimeMS: 7750)
        let visible = shown.layers.filter(\.isVisible)
        #expect(visible.count == 2)
        #expect(visible[0].frame == CGRect(x: 0, y: 0, width: 100, height: 60))
        #expect(visible[1].frame == CGRect(x: 0, y: 0, width: 25, height: 60))
    }

    @Test("Blur through softens both shots most at the cut")
    func blurThrough() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .blurThrough, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        let onCut = doc.drawn(atTimeMS: 8000).layers.filter(\.isVisible)
        #expect(onCut.count == 2)
        #expect(onCut.allSatisfy { $0.style.blurRadius > 0 })
        let early = doc.drawn(atTimeMS: 7600).layers.filter(\.isVisible)
        #expect(early.allSatisfy { $0.style.blurRadius < onCut[0].style.blurRadius })
    }

    // MARK: - Keeping it honest

    @Test("Parted clips draw nothing of the transition")
    func partedDrawsNothing() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                              at: .edit(outgoing: take, incoming: broll))
        _ = doc.moveClip(broll, toInMS: 9000)
        #expect(doc.drawn(atTimeMS: 7800).layers.filter(\.isVisible).count == 1)
        #expect(doc.movieFrames(atTimeMS: 7800).count == 1)
    }

    @Test("A clip split in two by an overwrite does not hand its arrival to the second half")
    func splitDoesNotCopyTheArrival() throws {
        var (doc, take, broll) = try Self.edit()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600),
                              at: .edit(outgoing: take, incoming: broll))
        let v1 = try #require(doc.trackID(ofClip: broll))
        var short = Layer(name: "insert", content: .image(Self.broll.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        short.movie = Self.broll
        short.time = LayerTime(inMS: 0, outMS: 1000, sourceInMS: 0, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 1000, atMS: 9500,
                                      over: .onto(v1), edit: .overwrite)
        _ = doc.land(short, at: landing)
        let brolls = doc.layers.filter { $0.name == "b-roll" }
        #expect(brolls.count == 2)
        #expect(brolls.filter { $0.arrivalTransition != nil }.count == 1)
        #expect(brolls.first { $0.time?.inMS == 8000 }?.arrivalTransition != nil)
    }

    @Test("It is written down with the document and read back, and a clip without one writes nothing")
    func codable() throws {
        var (doc, take, broll) = try Self.edit()
        let plain = try JSONEncoder().encode(try #require(doc.layer(id: take)))
        #expect(String(decoding: plain, as: UTF8.self).contains("arrivalTransition") == false)
        _ = doc.setTransition(ClipTransition(kind: .wipe, lengthMS: 800),
                              at: .edit(outgoing: take, incoming: broll))
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: broll)?.arrivalTransition == ClipTransition(kind: .wipe, lengthMS: 800))
    }

    @Test("A join inside one clip is reachable through the same place type")
    func joinsToo() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let id = doc.layers[0].id
        _ = doc.splitClip(id, atMS: 3000)
        _ = doc.trimClipStart(id, ofPiece: 1, byMS: 1000)
        let place = TimelineCutPlace.join(clip: id, index: 1)
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 3000)
        #expect(cut.outgoingName == "Piece 1")
        #expect(cut.incomingName == "Piece 2")
        let did = doc.setTransition(ClipTransition(kind: .push, lengthMS: 400), at: place)
        #expect(did)
        #expect(doc.documentCut(at: place)?.cut.transition?.kind == .push)
    }
}
