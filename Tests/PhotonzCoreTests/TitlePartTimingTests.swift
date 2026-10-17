import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A title's parts each have their own bar on the timeline, and dragging its
/// ends retimes that part (task
/// `a-title-page-s-parts-each-have-their-own-labelle`).
///
/// Written before the code. A part's bar runs from where its in starts to
/// where its out ends, as the title is compiled (energy and all), so the bar
/// says when the part is really on screen. Dragging an end moves that end and
/// nothing else, through the title's design, so a restyle afterwards keeps it.
@Suite("A title's parts have bars of their own")
struct TitlePartTimingTests {

    static func keynote() throws -> (PhotonzDocument, UUID) {
        try TitleRestyleTests.placed(.keynote)
    }

    static func part(_ doc: PhotonzDocument, _ id: UUID, _ name: String) throws -> TitlePartTiming {
        try #require(doc.titlePartTimings(layerID: id).first { $0.name == name })
    }

    // MARK: - Reading

    @Test("Every part of a title is listed, by the name the Part menu gives it, with its piece")
    func listsEveryPart() throws {
        let (doc, id) = try Self.keynote()
        let parts = doc.titlePartTimings(layerID: id)
        #expect(parts.map(\.name) == ["Background", "Headline", "Subtitle"])
        #expect(parts.map(\.role) == [.background, .headline, .subtitle])
        let subtitle = try #require(TitleRestyleTests.piece(doc, id, "Subtitle"))
        #expect(parts[2].pieceID == subtitle.id)
        #expect(parts.map(\.index) == [0, 1, 2])
    }

    @Test("A part's bar runs from its in's start to its out's end, inside the title")
    func barSpansInToOut() throws {
        let (doc, id) = try Self.keynote()
        // Keynote's subtitle rises in from 1.0 s for 0.6 s and fades out over
        // 0.28 s ending 0.2 s before the 4 s title ends.
        let subtitle = try Self.part(doc, id, "Subtitle")
        #expect(subtitle.inStartMS == 1_000)
        #expect(subtitle.inEndMS == 1_600)
        #expect(subtitle.outStartMS == 3_520)
        #expect(subtitle.outEndMS == 3_800)
        #expect(subtitle.titleInMS == 2_000)
        // A part with no out stays to the title's end.
        let background = try Self.part(doc, id, "Background")
        #expect(background.inStartMS == 0)
        #expect(background.outStartMS == 4_000)
        #expect(background.outEndMS == 4_000)
    }

    @Test("Bars are read as compiled: a calm title's parts come in later")
    func barsFollowEnergy() throws {
        var (doc, id) = try Self.keynote()
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        let subtitle = try Self.part(doc, id, "Subtitle")
        #expect(subtitle.inStartMS == 1_300)
    }

    @Test("Nothing that is not a title has parts")
    func onlyTitles() throws {
        let (doc, _) = try Self.keynote()
        let clip = try #require(doc.layers.first)
        #expect(doc.titlePartTimings(layerID: clip.id).isEmpty)
    }

    // MARK: - Dragging an end

    @Test("Dragging a part's start later makes it arrive later, and nothing else moves")
    func startLater() throws {
        var (doc, id) = try Self.keynote()
        let before = doc.titlePartTimings(layerID: id)
        let subtitle = try Self.part(doc, id, "Subtitle")
        let moved = doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .start, byMS: 500)
        #expect(moved)
        let after = try Self.part(doc, id, "Subtitle")
        #expect(after.inStartMS == 1_500)
        #expect(after.outEndMS == 3_800)
        // The others are untouched.
        let others = doc.titlePartTimings(layerID: id).filter { $0.name != "Subtitle" }
        #expect(others == before.filter { $0.name != "Subtitle" })
        // ...and the canvas agrees: the subtitle's own in starts there now.
        let piece = try #require(TitleRestyleTests.piece(doc, id, "Subtitle"))
        let arrival = try #require(doc.titlePartArrival(layerID: id, pieceID: piece.id))
        #expect(arrival.lowerBound == 1_500)
        // Kept in the design, so a restyle after it keeps the new timing.
        TitleRestyleTests.restyle(&doc, id) { $0.intensity = 80 }
        #expect(try Self.part(doc, id, "Subtitle").inStartMS == 1_500)
    }

    @Test("Dragging a part's end earlier makes it leave earlier")
    func endEarlier() throws {
        var (doc, id) = try Self.keynote()
        let subtitle = try Self.part(doc, id, "Subtitle")
        let moved = doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .end, byMS: -300)
        #expect(moved)
        let after = try Self.part(doc, id, "Subtitle")
        #expect(after.outEndMS == 3_500)
        #expect(after.outStartMS == 3_220)
        #expect(after.inStartMS == 1_000)
    }

    @Test("Dragging the bar's middle slides the part, keeping its length")
    func bodySlides() throws {
        var (doc, id) = try Self.keynote()
        let subtitle = try Self.part(doc, id, "Subtitle")
        let moved = doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .body, byMS: -200)
        #expect(moved)
        let after = try Self.part(doc, id, "Subtitle")
        #expect(after.inStartMS == 800)
        #expect(after.outEndMS == 3_600)
    }

    @Test("An end stays inside the half of the title it lives in")
    func endsStayInTheirHalf() throws {
        var (doc, id) = try Self.keynote()
        let subtitle = try Self.part(doc, id, "Subtitle")
        doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .start, byMS: 5_000)
        let late = try Self.part(doc, id, "Subtitle")
        #expect(late.inStartMS < 2_000)
        doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .end, byMS: -5_000)
        let early = try Self.part(doc, id, "Subtitle")
        #expect(early.outEndMS > 2_000)
        doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .start, byMS: -5_000)
        #expect(try Self.part(doc, id, "Subtitle").inStartMS == 0)
    }

    @Test("A part with no out is given a cut where its end is dragged to")
    func endWithoutAnOut() throws {
        var (doc, id) = try Self.keynote()
        let background = try Self.part(doc, id, "Background")
        let moved = doc.retimeTitlePart(layerID: id, index: background.index, grab: .end, byMS: -1_000)
        #expect(moved)
        let after = try Self.part(doc, id, "Background")
        #expect(after.outEndMS == 3_000)
        // Gone after it: drawn at 3.5 s into the title, the Background is clear.
        let drawn = doc.drawn(atTimeMS: 2_000 + 3_500)
        let piece = try #require(drawn.layer(id: id).flatMap { TitleDesign.find("Background", in: $0) })
        #expect(piece.style.opacity < 0.01)
    }

    @Test("A drag on a calm title moves the bar by what the hand moved")
    func dragFollowsTheHandOnACalmTitle() throws {
        var (doc, id) = try Self.keynote()
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        let subtitle = try Self.part(doc, id, "Subtitle")
        doc.retimeTitlePart(layerID: id, index: subtitle.index, grab: .start, byMS: 300)
        let after = try Self.part(doc, id, "Subtitle")
        #expect(abs(after.inStartMS - (subtitle.inStartMS + 300)) <= 1)
    }

    @Test("A drag that goes nowhere changes nothing")
    func nothingMoved() throws {
        var (doc, id) = try Self.keynote()
        let stayed = doc.retimeTitlePart(layerID: id, index: 2, grab: .start, byMS: 0)
        #expect(!stayed)
        let noSuchPart = doc.retimeTitlePart(layerID: id, index: 9, grab: .start, byMS: 400)
        #expect(!noSuchPart)
    }

    // MARK: - Catching

    @Test("An end catches on the nearest moment within reach, and only within it")
    func snaps() {
        #expect(TitlePartTiming.snapped(1_480, to: [1_000, 1_500, 2_000], withinMS: 40) == 1_500)
        #expect(TitlePartTiming.snapped(1_430, to: [1_000, 1_500, 2_000], withinMS: 40) == 1_430)
        #expect(TitlePartTiming.snapped(1_490, to: [1_470, 1_500], withinMS: 40) == 1_500)
    }
}
