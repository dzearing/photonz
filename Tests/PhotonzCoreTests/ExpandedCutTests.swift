import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The expanded cut** (`video-transition-wt.html`, `#rowA` and `#rowB`,
/// steps 5 to 9): a cut opened into the two clips it is made of, one row
/// each, so an overlap is literally two clips at the same time.
@Suite("The expanded cut")
struct ExpandedCutTests {

    /// Ten seconds recorded, eight of them used: two seconds spare after.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000, hasSound: true)
    /// Six seconds recorded, read from 1.5s: a second and a half spare before.
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000, hasSound: true)

    /// The recording on V1 from 0 to 8s and b-roll butted onto it to 12s.
    static func edit() throws -> (doc: PhotonzDocument, place: TimelineCutPlace) {
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
        return (doc, .edit(outgoing: take, incoming: broll))
    }

    @Test("A hard cut opens into A ending on the cut and B starting on it, nothing spent")
    func hardCut() throws {
        let (doc, place) = try Self.edit()
        let open = try #require(doc.expandedCut(at: place))
        #expect(open.atMS == 8000)
        #expect(open.a.name == "take" && open.a.startMS == 0 && open.a.endMS == 8000)
        #expect(open.b.name == "b-roll" && open.b.startMS == 8000 && open.b.endMS == 12_000)
        #expect(open.a.spent == nil && open.b.spent == nil)
        #expect(open.a.fade == nil && open.b.fade == nil)
        #expect(open.both == nil && open.hold == nil)
        #expect(open.bothLabel == nil)
    }

    @Test("A 1s cross dissolve: A runs half a second past the cut, B starts half a second early")
    func dissolve() throws {
        var (doc, place) = try Self.edit()
        let did1 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), at: place)
        #expect(did1)
        let open = try #require(doc.expandedCut(at: place))
        // Nothing moved: the clips are where they were cut.
        #expect(open.a.endMS == 8000 && open.b.startMS == 8000)
        #expect(open.a.spent == 8000..<8500)
        #expect(open.b.spent == 7500..<8000)
        #expect(open.both == 7500..<8500)
        #expect(open.bothLabel == "both on screen · 1.0s")
        #expect(open.a.fade == nil && open.b.fade == nil && open.hold == nil)
    }

    @Test("A dissolve placed after the cut spends only the outgoing side's spare")
    func dissolveAfter() throws {
        var (doc, place) = try Self.edit()
        let did2 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600, alignment: .after), at: place)
        #expect(did2)
        let open = try #require(doc.expandedCut(at: place))
        #expect(open.a.spent == 8000..<8600)
        #expect(open.b.spent == nil)
        #expect(open.both == 8000..<8600)
        #expect(open.bothLabel == "both on screen · 0.6s")
    }

    @Test("A dip to black releases the overlap: each side fades inside its own time")
    func dipReleases() throws {
        var (doc, place) = try Self.edit()
        let did3 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), at: place)
        #expect(did3)
        let did4 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), at: place)
        #expect(did4)
        let open = try #require(doc.expandedCut(at: place))
        #expect(open.a.spent == nil && open.b.spent == nil && open.both == nil)
        #expect(open.a.fade == 7500..<8000)
        #expect(open.b.fade == 8000..<8500)
        #expect(open.a.endMS == 8000 && open.b.startMS == 8000)
        #expect(open.hold == nil)
    }

    @Test("A hold on black parts them by the black, and B fades in after it")
    func holdOnBlack() throws {
        var (doc, place) = try Self.edit()
        let did5 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), at: place)
        #expect(did5)
        let did6 = doc.holdOnColour(3000, at: place)
        #expect(did6 == place)
        let open = try #require(doc.expandedCut(at: place))
        #expect(open.a.endMS == 8000)
        #expect(open.hold == 8000..<11_000)
        #expect(open.b.startMS == 11_000 && open.b.endMS == 15_000)
        #expect(open.a.fade == 7500..<8000)
        #expect(open.b.fade == 11_000..<11_500)
        #expect(open.both == nil)
    }

    @Test("A join inside one clip opens into its two pieces, both named by the clip")
    func join() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let did7 = doc.splitClips([take], atMS: 3000)
        #expect(did7)
        let place = TimelineCutPlace.join(clip: take, index: 1)
        let did8 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), at: place)
        #expect(did8)
        let open = try #require(doc.expandedCut(at: place))
        #expect(open.atMS == 3000)
        #expect(open.a.name == "take" && open.b.name == "take")
        #expect(open.a.startMS == 0 && open.a.endMS == 3000)
        #expect(open.b.startMS == 3000 && open.b.endMS == 8000)
        #expect(open.a.spent == 3000..<3500 && open.b.spent == 2500..<3000)
        #expect(open.both == 2500..<3500)
    }

    @Test("A length being dragged is drawn as the hand has it, not as it was written")
    func liveLength() throws {
        var (doc, place) = try Self.edit()
        let did9 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400), at: place)
        #expect(did9)
        let open = try #require(doc.expandedCut(at: place,
                                                drawing: ClipTransition(kind: .dissolve, lengthMS: 1200)))
        #expect(open.both == 7400..<8600)
        #expect(open.bothLabel == "both on screen · 1.2s")
    }

    @Test("A place with no cut opens nothing")
    func noCut() throws {
        let (doc, _) = try Self.edit()
        #expect(doc.expandedCut(at: .edit(outgoing: UUID(), incoming: UUID())) == nil)
        #expect(doc.expandedCut(at: .join(clip: doc.layers[0].id, index: 4)) == nil)
    }
}
