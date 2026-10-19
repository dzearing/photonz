import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A title part's own movement bars, dragged by hand on the timeline, survive
/// the title being compiled again (task
/// `a-title-part-move-dragged-by-hand-on-the-timelin`).
///
/// Written before the code. A restyle (another part retimed, a theme, an
/// energy, an intensity) compiles every part again; a bar somebody dragged
/// keeps the timing their hand gave it, while its keys still take the new
/// layout. Changing that part's own timing says how it moves now. A chart
/// laid out again from new numbers keeps the keys and effects set by hand on
/// its bars.
@Suite("Bars dragged by hand on a title survive a restyle")
struct TitleHandKeysSurviveRestyleTests {

    static func motion(_ doc: PhotonzDocument, _ id: UUID, _ path: String,
                       _ property: MotionProperty) -> LayerMotion? {
        TitleRestyleTests.piece(doc, id, path)?.motions?.first { $0.property == property }
    }

    /// Drag `path`'s `property` bar along by `byMS`, the way letting go of the
    /// bar on the timeline writes it.
    static func drag(_ doc: inout PhotonzDocument, _ id: UUID, _ path: String,
                     _ property: MotionProperty, byMS: Int) throws -> MotionTiming {
        let piece = try #require(TitleRestyleTests.piece(doc, id, path))
        doc.updateLayer(id: piece.id) { layer in
            guard var motions = layer.motions,
                  let index = motions.firstIndex(where: { $0.property == property }) else { return }
            motions[index] = motions[index].retimed(to: motions[index].timing.shifted(byMS: byMS))
            layer.motions = motions
        }
        return try #require(motion(doc, id, path, property)).timing
    }

    static func subtitleIndex(_ doc: PhotonzDocument, _ id: UUID) throws -> Int {
        try #require(doc.titlePartTimings(layerID: id).first { $0.name == "Subtitle" }).index
    }

    // MARK: - Titles

    @Test("The Headline's Opacity bar dragged earlier stays put when the Subtitle is retimed")
    func survivesAnotherPartRetimed() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let dragged = try Self.drag(&doc, id, "Title", .opacity, byMS: -300)
        #expect(dragged.startMS == 3_200)
        let moved = doc.retimeTitlePart(layerID: id, index: try Self.subtitleIndex(doc, id), grab: .start, byMS: 300)
        #expect(moved)
        #expect(Self.motion(doc, id, "Title", .opacity)?.timing == dragged)
        // The Subtitle really did move.
        #expect(Self.motion(doc, id, "Subtitle", .position)?.timing.startMS == 750)
    }

    @Test("It stays put through a theme, an energy and an intensity")
    func survivesTheKnobs() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let dragged = try Self.drag(&doc, id, "Title", .opacity, byMS: -300)
        TitleRestyleTests.restyle(&doc, id) { $0.theme = TitleTheme.curated[3] }
        #expect(Self.motion(doc, id, "Title", .opacity)?.timing == dragged)
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        #expect(Self.motion(doc, id, "Title", .opacity)?.timing == dragged)
        TitleRestyleTests.restyle(&doc, id) { $0.intensity = 50 }
        #expect(Self.motion(doc, id, "Title", .opacity)?.timing == dragged)
        // The parts nobody touched did take the calmer pace.
        #expect(Self.motion(doc, id, "Subtitle", .position)?.timing.startMS == 585)
    }

    @Test("A dragged slide keeps its timing and still lands where the new layout puts the words")
    func draggedSlideFollowsLayout() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let dragged = try Self.drag(&doc, id, "Subtitle", .position, byMS: 200)
        let swiss = try #require(TitleFontPair.curated.first { $0.id == "swiss" })
        TitleRestyleTests.restyle(&doc, id) { $0.fonts = swiss }
        let slide = try #require(Self.motion(doc, id, "Subtitle", .position))
        #expect(slide.timing == dragged)
        let subtitle = try #require(TitleRestyleTests.piece(doc, id, "Subtitle"))
        #expect(slide.keyframes.last?.value == .point(subtitle.frame.origin))
    }

    @Test("A key moved by hand inside a bar is kept as it was drawn")
    func handKeyValueKept() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let piece = try #require(TitleRestyleTests.piece(doc, id, "Title"))
        doc.updateLayer(id: piece.id) { layer in
            guard var motions = layer.motions,
                  let index = motions.firstIndex(where: { $0.property == .opacity }) else { return }
            motions[index].to = .number(30)
            layer.motions = motions
        }
        let edited = try #require(Self.motion(doc, id, "Title", .opacity))
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .punchy }
        let after = try #require(Self.motion(doc, id, "Title", .opacity))
        #expect(after.to == .number(30))
        #expect(after.timing == edited.timing)
    }

    @Test("Retiming that part's own bar says how it moves now")
    func ownPartRetimedWins() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        _ = try Self.drag(&doc, id, "Title", .opacity, byMS: -300)
        let headline = try #require(doc.titlePartTimings(layerID: id).first { $0.name == "Headline" })
        let moved = doc.retimeTitlePart(layerID: id, index: headline.index, grab: .end, byMS: -100)
        #expect(moved)
        let fade = try #require(Self.motion(doc, id, "Title", .opacity))
        // The design's out, 100 ms earlier: ends at 3 820 - 100.
        #expect(fade.timing.endMS == 3_820)
    }

    @Test("A trimmed title is not mistaken for one dragged by hand: a restyle fits its outs to the new end")
    func trimIsNotAHandDrag() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let time = try #require(doc.layer(id: id)?.time)
        doc.updateLayer(id: id) {
            $0.time = LayerTime(inMS: time.inMS, outMS: time.outMS - 1_000, sourceInMS: time.sourceInMS)
        }
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .normal }
        // Keynote's subtitle fades out ending 0.14 s before a 3 s title ends.
        #expect(Self.motion(doc, id, "Subtitle", .opacity)?.timing.endMS == 2_860)
        #expect(Self.motion(doc, id, "Title", .opacity)?.timing.endMS == 2_920)
    }

    @Test("A title nobody touched restyles exactly as before")
    func untouchedUnchanged() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let fresh = doc.layer(id: id)
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .normal }
        #expect(try TitleRestyleTests.same(doc.layer(id: id), fresh))
    }

    // MARK: - Charts

    @Test("A key and an effect set by hand on a bar survive new numbers and a theme")
    func chartBarKeepsHandWork() throws {
        var (doc, id) = try AnimatedChartTests.placed(.bar)
        let bar = try #require(AnimatedChartTests.piece(doc, id, "Bar 2"))
        let glow = GlowEffect(colorHex: "#FF2D55")
        doc.updateLayer(id: bar.id) { layer in
            layer.motions = (layer.motions ?? []) + [LayerMotion.keyed(.rotation, atMS: 1_500, value: .number(12))]
            layer.style.effects.append(.glow(glow))
        }
        doc.editChart(layerID: id) { $0.rows[1].value *= 2 }
        func check(_ when: Comment) throws {
            let now = try #require(AnimatedChartTests.piece(doc, id, "Bar 2"))
            #expect(now.motions?.contains { $0.property == .rotation } == true, when)
            #expect(now.style.effects.contains(.glow(glow)), when)
            #expect(now.style.effects.filter { $0.glow != nil }.count == 1, when)
        }
        try check("after new numbers")
        doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[3] }
        try check("after a theme")
    }

    @Test("A bar's movement dragged by hand keeps its timing through new numbers")
    func chartBarKeepsHandTiming() throws {
        var (doc, id) = try AnimatedChartTests.placed(.bar)
        let bar = try #require(AnimatedChartTests.piece(doc, id, "Bar 2"))
        let property = try #require(bar.motions?.first?.property)
        let dragged = try Self.drag(&doc, id, "Bar 2", property, byMS: 250)
        doc.editChart(layerID: id) { $0.rows[1].value *= 2 }
        #expect(Self.motion(doc, id, "Bar 2", property)?.timing == dragged)
        doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[3] }
        #expect(Self.motion(doc, id, "Bar 2", property)?.timing == dragged)
    }
}
