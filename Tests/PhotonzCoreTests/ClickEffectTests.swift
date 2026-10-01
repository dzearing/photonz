import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A click in a recording can show an effect on the picture: a ring that
/// spreads, a soft dot, or the picture dimmed round the spot, for a moment at
/// each click (`ClickEffect.swift`).
@Suite("An effect at each click of a recording")
struct ClickEffectTests {

    static let movieID = UUID(uuidString: "C11C0001-1111-2222-3333-444444444444")!

    static func movie() -> MovieRef {
        MovieRef(id: movieID, pixelSize: CGSize(width: 2000, height: 1000), durationMS: 12_000)
    }

    /// A recording laid out at half its size, filling a 1000 x 500 frame.
    static func clip(inMS: Int = 0) -> Layer {
        let reel = movie()
        var layer = Layer(name: "screen-recording",
                          content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        layer.movie = reel
        layer.time = LayerTime(inMS: inMS, outMS: inMS + 12_000, sourceInMS: 0, sourceLengthMS: 12_000)
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 500), layers: [layer])
        document.durationMS = layer.time?.outMS
        return document
    }

    /// Two recorded clicks: at 2 s on the right of the picture, at 5 s low on the left.
    static let first = PointerClick(downMS: 2000, upMS: 2080, point: CGPoint(x: 1500, y: 400), button: .left)
    static let second = PointerClick(downMS: 5000, upMS: 5080, point: CGPoint(x: 400, y: 800), button: .left)
    static let recorded = [first, second]

    /// The document with a ripple turned on, the recorded clicks kept.
    static func rippling(_ layer: Layer = clip(), style: ClickEffectStyle = .ripple) -> (PhotonzDocument, UUID) {
        var document = document(layer)
        document.setClickEffect(onClip: layer.id, recorded: recorded) {
            $0.isOn = true
            $0.style = style
        }
        return (document, layer.id)
    }

    /// What the drawn document adds for clicks at a moment.
    static func marks(_ document: PhotonzDocument, at ms: Int, clip: UUID) -> [Layer] {
        document.drawn(atTimeMS: ms).layers.filter { $0.id != clip }
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.5) -> Bool { abs(a - b) <= slack }

    // MARK: - Which clicks

    @Test func theClicksAreTheRecordedAndTheAddedInOrder() {
        var layer = Self.clip()
        let added = PointerClick(downMS: 3000, upMS: nil, point: CGPoint(x: 10, y: 10), button: .left)
        layer.addedClicks = [added]
        let marks = layer.clickMarks(recorded: Self.recorded)
        #expect(marks.map(\.click.downMS) == [2000, 3000, 5000])
        #expect(marks.allSatisfy { !$0.isHidden })
    }

    @Test func aHiddenClickIsStillMarkedButSaysSo() {
        var (document, id) = Self.rippling()
        document.setClickHidden(onClip: id, clickID: Self.first.id, true)
        let marks = document.layer(id: id)?.clickMarks(recorded: nil) ?? []
        #expect(marks.count == 2)
        #expect(marks.first { $0.click.id == Self.first.id }?.isHidden == true)
        document.setClickHidden(onClip: id, clickID: Self.first.id, false)
        #expect(document.layer(id: id)?.clickMarks(recorded: nil).allSatisfy { !$0.isHidden } == true)
    }

    @Test func aMovedClickHappensAtItsNewMomentAndKeepsItsOrder() {
        var (document, id) = Self.rippling()
        document.moveClick(onClip: id, clickID: Self.first.id, toSourceMS: 6000)
        let marks = document.layer(id: id)?.clickMarks(recorded: nil) ?? []
        #expect(marks.map(\.click.id) == [Self.second.id, Self.first.id])
        #expect(marks.last?.click.downMS == 6000)
        // ...never off the end of what the clip plays.
        document.moveClick(onClip: id, clickID: Self.first.id, toSourceMS: 50_000)
        #expect(document.layer(id: id)?.clickMarks(recorded: nil).last?.click.downMS == 12_000)
    }

    @Test func turningItOnKeepsTheRecordedClicksInTheDocument() {
        let (document, id) = Self.rippling()
        let effect = document.layer(id: id)?.clickEffect
        #expect(effect?.recorded?.map(\.id) == Self.recorded.map(\.id))
        // Read with nothing beside the file, the clicks are still there.
        #expect(document.layer(id: id)?.clickMarks(recorded: nil).count == 2)
    }

    @Test func itIsOffUntilTurnedOnAndTheLooksStartSensible() {
        let effect = ClickEffect()
        #expect(effect.isOn == false)
        #expect(effect.style == .ripple)
        #expect(effect.size == .medium)
        #expect(effect.colorHex.hasPrefix("#"))
        #expect(ClickEffect.lengthMS == 400)
    }

    // MARK: - Drawn at the click

    @Test func nothingIsDrawnBeforeAfterOrWhileOff() {
        var (document, id) = Self.rippling()
        #expect(Self.marks(document, at: 1990, clip: id).isEmpty)
        #expect(Self.marks(document, at: 2000 + ClickEffect.lengthMS, clip: id).isEmpty)
        #expect(Self.marks(document, at: 2100, clip: id).count == 1)
        document.setClickEffect(onClip: id, recorded: nil) { $0.isOn = false }
        #expect(Self.marks(document, at: 2100, clip: id).isEmpty)
    }

    @Test func aRippleIsCentredOnTheClickAboveTheClipAndSpreadsAsItFades() throws {
        let (document, id) = Self.rippling()
        let drawn = document.drawn(atTimeMS: 2050)
        #expect(drawn.layers.first?.id == id, "the mark draws over the clip")
        let early = try #require(Self.marks(document, at: 2050, clip: id).first)
        let late = try #require(Self.marks(document, at: 2300, clip: id).first)
        // The click is at 1500, 400 of a 2000 x 1000 picture laid out at half size.
        for mark in [early, late] {
            #expect(near(mark.frame.midX, 750) && near(mark.frame.midY, 200), "centred at \(mark.frame)")
            #expect(near(mark.frame.width, mark.frame.height))
        }
        #expect(late.frame.width > early.frame.width + 5)
        #expect(late.style.opacity < early.style.opacity)
        // A ring: an edge, not a filled dot.
        if case .annotation(let shape) = late.content {
            #expect(shape.shape == .ellipse)
            #expect(shape.fill == nil)
        } else {
            Issue.record("the ripple is not a shape")
        }
        #expect(late.style.effects.contains { if case .border = $0 { true } else { false } })
    }

    @Test func aBiggerSizeDrawsABiggerRing() throws {
        var (document, id) = Self.rippling()
        let medium = try #require(Self.marks(document, at: 2300, clip: id).first).frame.width
        document.setClickEffect(onClip: id, recorded: nil) { $0.size = .large }
        let large = try #require(Self.marks(document, at: 2300, clip: id).first).frame.width
        document.setClickEffect(onClip: id, recorded: nil) { $0.size = .small }
        let small = try #require(Self.marks(document, at: 2300, clip: id).first).frame.width
        #expect(small < medium && medium < large)
    }

    @Test func aPulseIsASoftFilledDotInTheChosenColour() throws {
        var (document, id) = Self.rippling(style: .pulse)
        document.setClickEffect(onClip: id, recorded: nil) { $0.colorHex = "#FF9500" }
        let mark = try #require(Self.marks(document, at: 2150, clip: id).first)
        guard case .annotation(let shape) = mark.content else {
            Issue.record("the pulse is not a shape")
            return
        }
        #expect(shape.shape == .ellipse)
        #expect(shape.fill?.hex == "#FF9500")
        #expect(mark.style.opacity > 0 && mark.style.opacity < 1)
    }

    @Test func aSpotlightDimsTheWholeClipButTheSpot() throws {
        let (document, id) = Self.rippling(style: .spotlight)
        let mark = try #require(Self.marks(document, at: 2200, clip: id).first)
        #expect(mark.frame == CGRect(x: 0, y: 0, width: 1000, height: 500))
        guard case .annotation(let shape) = mark.content, let paint = shape.fill else {
            Issue.record("the spotlight is not a filled shape")
            return
        }
        #expect(paint.kind == .radial)
        #expect(near(paint.center.x, 0.75, 0.001) && near(paint.center.y, 0.4, 0.001))
        let stops = paint.orderedStops
        #expect(stops.first?.hex.count == 9, "the middle is see-through")
        #expect(stops.last?.hex.hasPrefix("#000000") == true)
        #expect(mark.style.opacity > 0.2)
    }

    @Test func aHiddenClickDrawsNothing() {
        var (document, id) = Self.rippling()
        document.setClickHidden(onClip: id, clickID: Self.first.id, true)
        #expect(Self.marks(document, at: 2100, clip: id).isEmpty)
        #expect(Self.marks(document, at: 5100, clip: id).count == 1)
    }

    @Test func theClickFollowsTheClipAlongTheTimeline() {
        let (document, id) = Self.rippling(Self.clip(inMS: 1000))
        #expect(Self.marks(document, at: 2100, clip: id).isEmpty)
        #expect(Self.marks(document, at: 3100, clip: id).count == 1)
    }

    @Test func aSpedUpStretchStillShowsTheWholeEffect() {
        var layer = Self.clip()
        // The first 4 s of the recording at double speed: the click at 2 s
        // plays one second in.
        layer.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 2000, speedPercent: 200),
                                                ClipPiece(sourceInMS: 4000, lengthMS: 8000)]))
        let (document, id) = Self.rippling(layer)
        #expect(Self.marks(document, at: 990, clip: id).isEmpty)
        #expect(Self.marks(document, at: 1010, clip: id).count == 1)
        #expect(Self.marks(document, at: 1350, clip: id).count == 1, "the effect runs on the video's clock")
        #expect(Self.marks(document, at: 1410, clip: id).isEmpty)
    }

    @Test func aClickInAStretchCutOutShowsNothing() {
        var layer = Self.clip()
        // 1.5 s to 3 s cut out: the click at 2 s is gone.
        layer.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 1500),
                                                ClipPiece(sourceInMS: 3000, lengthMS: 9000)]))
        let (document, id) = Self.rippling(layer)
        for ms in stride(from: 1400, through: 1900, by: 50) {
            #expect(Self.marks(document, at: ms, clip: id).isEmpty, "at \(ms)")
        }
    }

    @Test func insideAZoomTheEffectLandsWhereTheClickIsInTheZoomedPicture() throws {
        var layer = Self.clip()
        // Held on the top-right quarter of the picture from 1 s to 4 s.
        layer.zooms = [ClipZoom(startMS: 1000, endMS: 4000, easeInMS: 0, easeOutMS: 0,
                                scale: 2, center: CGPoint(x: 0.75, y: 0.25))]
        let (document, id) = Self.rippling(layer)
        let zoomed = try #require(Self.marks(document, at: 2200, clip: id).first)
        // The click at 0.75, 0.4 of the picture is at 0.5, 0.8 of the zoomed window.
        #expect(near(zoomed.frame.midX, 500) && near(zoomed.frame.midY, 400), "at \(zoomed.frame)")
        var plain = Self.clip()
        plain.zooms = nil
        let (flat, flatID) = Self.rippling(plain)
        let whole = try #require(Self.marks(flat, at: 2200, clip: flatID).first)
        #expect(near(zoomed.frame.width, whole.frame.width * 2, 1), "it grows with the picture")
    }

    @Test func aClickTheZoomHasFramedOutDrawsNothing() {
        var layer = Self.clip()
        layer.zooms = [ClipZoom(startMS: 1000, endMS: 7000, easeInMS: 0, easeOutMS: 0,
                                scale: 2, center: CGPoint(x: 0.75, y: 0.25))]
        let (document, id) = Self.rippling(layer)
        // The click at 5 s is low on the left, well outside the top-right quarter.
        #expect(Self.marks(document, at: 5100, clip: id).isEmpty)
    }

    @Test func aClipOffScreenDrawsNoClicks() {
        var (document, id) = Self.rippling()
        document.updateLayer(id: id) { $0.isVisible = false }
        #expect(Self.marks(document, at: 2100, clip: id).isEmpty)
    }

    // MARK: - Kept

    @Test func itIsWrittenDownAndReadBack() throws {
        var (document, id) = Self.rippling(style: .pulse)
        document.setClickHidden(onClip: id, clickID: Self.second.id, true)
        document.moveClick(onClip: id, clickID: Self.first.id, toSourceMS: 2500)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: id)?.clickEffect == document.layer(id: id)?.clickEffect)
        #expect(back.layer(id: id)?.clickMarks(recorded: nil).first?.click.downMS == 2500)
    }

    @Test func aCopyOfTheClipShowsTheSameClicks() {
        let (document, id) = Self.rippling()
        let copy = document.layer(id: id)?.duplicated()
        #expect(copy?.clickEffect == document.layer(id: id)?.clickEffect)
    }

    @Test func aClipWithNoClicksHasNothingToShow() {
        let layer = Self.clip()
        #expect(layer.clickMarks(recorded: nil).isEmpty)
        #expect(!layer.hasClicksToShow(recorded: nil))
        #expect(layer.hasClicksToShow(recorded: Self.recorded))
    }

    @Test func whereEachClickLandsOnTheTimeline() {
        let (document, id) = Self.rippling(Self.clip(inMS: 1000))
        let layer = document.layer(id: id)
        #expect(layer?.timelineMS(ofClickAtSourceMS: 2000) == 3000)
        #expect(layer?.sourceMS(ofClickAtTimelineMS: 4000) == 3000)
    }
}
