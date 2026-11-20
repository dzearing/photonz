import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A spotlight: the lens kind that leaves its own area alone and dims, blurs or
/// both everything else on the picture, so the eye lands on that area.
@Suite("Spotlight lens")
struct SpotlightTests {

    private let canvas = CGSize(width: 400, height: 300)

    private func spotlight(_ configure: (inout LensContent) -> Void = { _ in },
                           frame: CGRect = CGRect(x: 100, y: 100, width: 80, height: 40)) -> Layer {
        var lens = LensContent(adjustment: .spotlight)
        configure(&lens)
        return Layer(name: "Spotlight", content: .lens(lens), frame: frame)
    }

    // MARK: - What it is

    @Test func spotlightIsTheLastKindTheLensToolOffers() {
        #expect(LensKind.allCases.last == .spotlight)
        #expect(LensKind.spotlight.title == "Spotlight")
        #expect(LensKind.spotlight.adjustment == .spotlight)
        #expect(LensAdjustment.spotlight.title == "Spotlight")
    }

    /// It has several numbers of its own rather than one, so it has no single
    /// slider for the panel or the capsule to draw.
    @Test func spotlightHasNoSingleSetting() {
        #expect(LensAdjustment.spotlight.settingTitle == nil)
        #expect(LensAdjustment.spotlight.label(0) == "")
    }

    @Test func aFreshSpotlightDimsAndBlursWithAHardEdge() {
        let lens = LensContent(adjustment: .spotlight)
        #expect(lens.spotlightDim == 0.5)
        #expect(lens.spotlightBlur > 0)
        #expect(lens.spotlightFeather == 0)
        #expect(lens.spotlightShape == .rectangle)
        #expect(!lens.isIdentity)
    }

    @Test func eachNumberIsHeldInsideItsRange() {
        var lens = LensContent(adjustment: .spotlight)
        lens.setSpotlightDim(3)
        #expect(lens.spotlightDim == 1)
        lens.setSpotlightDim(-1)
        #expect(lens.spotlightDim == 0)
        lens.setSpotlightBlur(500)
        #expect(lens.spotlightBlur == LensContent.spotlightBlurRange.upperBound)
        lens.setSpotlightBlur(-4)
        #expect(lens.spotlightBlur == 0)
        lens.setSpotlightFeather(900)
        #expect(lens.spotlightFeather == LensContent.spotlightFeatherRange.upperBound)
        lens.setSpotlightFeather(.nan)
        #expect(lens.spotlightFeather == 0)
    }

    /// Dim and blur each go to nought on their own: dim only and blur only are
    /// both real spotlights. Only with both at nought does it change nothing.
    @Test func dimAndBlurEachTurnOffOnTheirOwn() {
        var lens = LensContent(adjustment: .spotlight)
        lens.setSpotlightDim(0)
        #expect(!lens.isIdentity)
        lens.setSpotlightBlur(0)
        #expect(lens.isIdentity)
        lens.setSpotlightDim(0.3)
        #expect(!lens.isIdentity)
    }

    @Test func readoutsReadLikeTheirUnit() {
        #expect(LensContent.dimLabel(0.5) == "50%")
        #expect(LensContent.lengthLabel(6) == "6 pt")
        #expect(SpotlightShape.rectangle.title == "Rectangle")
        #expect(SpotlightShape.ellipse.title == "Ellipse")
    }

    // MARK: - Saving

    @Test func roundTripsThroughCodable() throws {
        var lens = LensContent(adjustment: .spotlight)
        lens.setSpotlightDim(0.7)
        lens.setSpotlightBlur(12)
        lens.setSpotlightFeather(20)
        lens.spotlightShape = .ellipse
        let layer = Layer(name: "Spotlight", content: .lens(lens),
                          frame: CGRect(x: 1, y: 2, width: 30, height: 40))
        let data = try JSONEncoder().encode(layer)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back == layer)
        #expect(back.lens?.spotlightShape == .ellipse)
    }

    /// A lens saved before spotlights existed opens with the spotlight's own
    /// defaults rather than throwing.
    @Test func aLensSavedBeforeSpotlightsExistedStillOpens() throws {
        let json = #"{"adjustment":"blur","blurRadius":9}"#
        let lens = try JSONDecoder().decode(LensContent.self, from: Data(json.utf8))
        #expect(lens.adjustment == .blur)
        #expect(lens.blurRadius == 9)
        #expect(lens.spotlightDim == 0.5)
        #expect(lens.spotlightShape == .rectangle)
    }

    // MARK: - Drawing one

    @Test func aDragMakesASpotlightRoundTheBoxYouDrew() {
        let layer = LensBuilder.layer(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 150, y: 100),
                                      canvas: canvas, adjustment: .spotlight)
        #expect(layer?.frame == CGRect(x: 50, y: 60, width: 100, height: 40))
        #expect(layer?.lens?.adjustment == .spotlight)
        #expect(layer?.name == "Spotlight")
    }

    /// Switching a blur lens to Spotlight keeps the box where it is: it is
    /// the area somebody was looking at.
    @Test func switchingALensToSpotlightKeepsItsBox() {
        let blur = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                         frame: CGRect(x: 40, y: 40, width: 60, height: 30))
        let lit = LensConversion.layer(blur, becoming: .spotlight, canvas: canvas)
        #expect(lit.frame == blur.frame)
        #expect(lit.lens?.adjustment == .spotlight)
        #expect(lit.name == "Spotlight")
    }

    // MARK: - Zoom

    /// Blur and feather are lengths and grow with a magnified render; the dim
    /// is a share of the light and means the same at any zoom.
    @Test func lengthsGrowWithTheDocumentAndTheDimDoesNot() {
        var lens = LensContent(adjustment: .spotlight)
        lens.setSpotlightDim(0.4)
        lens.setSpotlightBlur(5)
        lens.setSpotlightFeather(10)
        let big = lens.magnified(by: 2)
        #expect(big.spotlightBlur == 10)
        #expect(big.spotlightFeather == 20)
        #expect(big.spotlightDim == 0.4)
    }

    // MARK: - Redrawing

    /// The spotlight's picture is the whole canvas outside its area, so it
    /// reads the whole canvas.
    @Test func aSpotlightReadsTheWholeCanvas() {
        let layer = spotlight()
        #expect(layer.readsBackdrop)
        let source = layer.backdropSource
        #expect(source?.contains(CGRect(origin: .zero, size: canvas)) == true)
    }

    /// Moving the spotlight's area changes the dim everywhere it was and is,
    /// and the blur edge round both, so it redraws the whole picture rather
    /// than only its box.
    @Test func movingTheSpotlightRedrawsTheWholePicture() {
        let before = PhotonzDocument(canvasSize: canvas, layers: [spotlight()])
        var after = before
        after.layers[0].frame = CGRect(x: 120, y: 100, width: 80, height: 40)
        let dirty = RenderDiff.dirtyRegion(from: before, to: after)
        guard case .rect(let rect) = dirty else {
            #expect(dirty == .full)
            return
        }
        #expect(rect == CGRect(origin: .zero, size: canvas))
    }

    @Test func retuningTheDimRedrawsTheWholePicture() {
        let before = PhotonzDocument(canvasSize: canvas, layers: [spotlight()])
        var after = before
        after.layers[0].content = .lens(LensContent(adjustment: .spotlight).with { $0.setSpotlightDim(0.8) })
        let dirty = RenderDiff.dirtyRegion(from: before, to: after)
        if case .rect(let rect) = dirty {
            #expect(rect == CGRect(origin: .zero, size: canvas))
        } else {
            #expect(dirty == .full)
        }
    }

    /// Something changing far from the area, under the dim, redraws the dim
    /// over it: the picture there is the dimmed version of what changed.
    @Test func changingWhatIsUnderTheDimRedrawsIt() {
        let box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                        frame: CGRect(x: 300, y: 220, width: 40, height: 40))
        let before = PhotonzDocument(canvasSize: canvas, layers: [box, spotlight()])
        var after = before
        after.layers[0].frame = CGRect(x: 310, y: 230, width: 40, height: 40)
        let dirty = RenderDiff.dirtyRegion(from: before, to: after)
        if case .rect(let rect) = dirty {
            #expect(rect.contains(CGRect(x: 300, y: 220, width: 50, height: 50)))
        }
    }
}

private extension LensContent {
    func with(_ change: (inout LensContent) -> Void) -> LensContent {
        var copy = self
        change(&copy)
        return copy
    }
}
