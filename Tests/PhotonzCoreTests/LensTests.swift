import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Lens layers")
struct LensTests {

    private let canvas = CGSize(width: 400, height: 300)

    // MARK: - The adjustment and its one setting

    @Test func everyAdjustmentSaysItsName() {
        for adjustment in LensAdjustment.allCases {
            #expect(!adjustment.title.isEmpty)
        }
        #expect(LensAdjustment.blur.title == "Blur")
        #expect(LensAdjustment.pixelate.title == "Pixelate")
        #expect(LensAdjustment.greyscale.title == "Greyscale")
        #expect(LensAdjustment.invert.title == "Invert")
        #expect(LensAdjustment.brightness.title == "Brightness")
    }

    /// Four of the five carry a number you can pull; Invert is the one that
    /// has nothing to set, and the panel must be able to ask rather than know.
    @Test func onlyInvertHasNoSetting() {
        for adjustment in LensAdjustment.allCases where adjustment != .invert {
            #expect(adjustment.settingTitle != nil)
            #expect(adjustment.range.lowerBound < adjustment.range.upperBound)
        }
        #expect(LensAdjustment.invert.settingTitle == nil)
    }

    @Test func brightnessGoesBothWays() {
        #expect(LensAdjustment.brightness.range.lowerBound < 0)
        #expect(LensAdjustment.brightness.range.upperBound > 0)
    }

    @Test func lengthSettingsAreTheOnesMeasuredInPoints() {
        #expect(LensAdjustment.blur.isLength)
        #expect(LensAdjustment.pixelate.isLength)
        #expect(!LensAdjustment.greyscale.isLength)
        #expect(!LensAdjustment.invert.isLength)
        #expect(!LensAdjustment.brightness.isLength)
    }

    @Test func everyDefaultSitsInsideItsOwnRange() {
        for adjustment in LensAdjustment.allCases {
            #expect(adjustment.range.contains(adjustment.defaultAmount))
        }
    }

    @Test func readoutsReadLikeTheirUnit() {
        #expect(LensAdjustment.blur.label(8) == "8 pt")
        #expect(LensAdjustment.pixelate.label(12) == "12 pt")
        #expect(LensAdjustment.greyscale.label(1) == "100%")
        #expect(LensAdjustment.brightness.label(0.35) == "+35%")
        #expect(LensAdjustment.brightness.label(-0.35) == "-35%")
        #expect(LensAdjustment.invert.label(0) == "")
    }

    // MARK: - The content

    @Test func aFreshLensBlurs() {
        let lens = LensContent()
        #expect(lens.adjustment == .blur)
        #expect(lens.amount == LensAdjustment.blur.defaultAmount)
    }

    /// Each adjustment keeps its OWN number, so switching to Pixelate and back
    /// hands your blur strength back rather than a block size in its place.
    @Test func eachAdjustmentRemembersItsOwnNumber() {
        var lens = LensContent()
        lens.amount = 20
        lens.adjustment = .pixelate
        #expect(lens.amount == LensAdjustment.pixelate.defaultAmount)
        lens.amount = 40
        lens.adjustment = .blur
        #expect(lens.amount == 20)
        lens.adjustment = .pixelate
        #expect(lens.amount == 40)
    }

    @Test func aNumberOutsideTheRangeIsPulledBackIn() {
        var lens = LensContent()
        lens.amount = 10_000
        #expect(lens.amount == LensAdjustment.blur.range.upperBound)
        lens.amount = -5
        #expect(lens.amount == LensAdjustment.blur.range.lowerBound)
        lens.adjustment = .brightness
        lens.amount = -9
        #expect(lens.amount == LensAdjustment.brightness.range.lowerBound)
    }

    @Test func aNonsenseNumberFallsBackToTheDefault() {
        var lens = LensContent()
        lens.amount = .nan
        #expect(lens.amount == LensAdjustment.blur.defaultAmount)
    }

    /// Blur and pixelate read pixels from outside the box they cover, so the
    /// renderer has to be told how far outside to sample. Nothing else does.
    @Test func onlyNeighbourhoodAdjustmentsReachPastTheBox() {
        var lens = LensContent(adjustment: .blur)
        lens.amount = 10
        #expect(lens.sampleReach == 30)
        lens.adjustment = .pixelate
        lens.amount = 16
        #expect(lens.sampleReach == 16)
        lens.adjustment = .greyscale
        #expect(lens.sampleReach == 0)
        lens.adjustment = .invert
        #expect(lens.sampleReach == 0)
        lens.adjustment = .brightness
        #expect(lens.sampleReach == 0)
    }

    @Test func anAdjustmentTurnedAllTheWayDownChangesNothing() {
        var lens = LensContent(adjustment: .greyscale)
        lens.amount = 0
        #expect(lens.isIdentity)
        lens.amount = 1
        #expect(!lens.isIdentity)
        lens.adjustment = .brightness
        lens.amount = 0
        #expect(lens.isIdentity)
        lens.adjustment = .invert
        #expect(!lens.isIdentity)
    }

    // MARK: - Codable

    @Test func roundTripsThroughCodable() throws {
        var lens = LensContent(adjustment: .pixelate)
        lens.amount = 24
        lens.adjustment = .brightness
        lens.amount = -0.5
        let layer = Layer(name: "Pixelate", content: .lens(lens),
                          frame: CGRect(x: 10, y: 20, width: 100, height: 40),
                          style: LayerStyle(cornerRadius: 6))
        let data = try JSONEncoder().encode(layer)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back == layer)
        #expect(back.lens?.adjustment == .brightness)
        #expect(back.lens?.amount == -0.5)
        #expect(back.lens?.amount(for: .pixelate) == 24)
    }

    /// A lens saved by an older build has none of the numbers a later one
    /// added, and must still open as a working lens rather than throw.
    @Test func decodesFromTheSmallestPayloadThatNamesAnAdjustment() throws {
        let json = Data(#"{"adjustment":"invert"}"#.utf8)
        let lens = try JSONDecoder().decode(LensContent.self, from: json)
        #expect(lens.adjustment == .invert)
        #expect(lens.amount(for: .blur) == LensAdjustment.blur.defaultAmount)
    }

    // MARK: - A lens is a layer

    @Test func aDragMakesALensTheSizeYouDrew() {
        let layer = LensBuilder.layer(from: CGPoint(x: 80, y: 90), to: CGPoint(x: 20, y: 30),
                                      canvas: canvas, adjustment: .pixelate)
        #expect(layer?.frame == CGRect(x: 20, y: 30, width: 60, height: 60))
        #expect(layer?.lens?.adjustment == .pixelate)
        #expect(layer?.name == "Pixelate")
    }

    @Test func aStrayClickMakesNothing() {
        #expect(LensBuilder.layer(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 21, y: 31),
                                  canvas: canvas) == nil)
    }

    @Test func aLensDrawnOffTheEdgeIsCutToTheCanvas() {
        let layer = LensBuilder.layer(from: CGPoint(x: -40, y: -40), to: CGPoint(x: 60, y: 60),
                                      canvas: canvas)
        #expect(layer?.frame == CGRect(x: 0, y: 0, width: 60, height: 60))
    }

    /// A lens is the one kind of layer whose picture is not its own: only what
    /// is composited BELOW it. The renderer, the drag preview and the dirty
    /// region all ask this one question.
    @Test func aLensSaysItReadsWhatIsBelowIt() {
        let lens = Layer(name: "Blur", content: .lens(LensContent()),
                         frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(lens.readsBackdrop)
        let callout = Layer(name: "Zoom",
                            content: .zoomCallout(ZoomCalloutContent(sourceRect: .zero)),
                            frame: .zero)
        #expect(callout.readsBackdrop)
        #expect(!Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                       frame: .zero).readsBackdrop)
    }

    /// What has to change on the canvas before this layer must be drawn again:
    /// the region it magnifies for a callout, and for a lens its own box grown
    /// by however far the adjustment reaches.
    @Test func theRegionALensWatchesIsItsBoxPlusItsReach() {
        var lens = LensContent(adjustment: .blur)
        lens.amount = 4
        let layer = Layer(name: "Blur", content: .lens(lens),
                          frame: CGRect(x: 50, y: 50, width: 100, height: 40))
        #expect(layer.backdropSource == CGRect(x: 38, y: 38, width: 124, height: 64))
        let flat = Layer(name: "Grey", content: .lens(LensContent(adjustment: .greyscale)),
                         frame: CGRect(x: 50, y: 50, width: 100, height: 40))
        #expect(flat.backdropSource == CGRect(x: 50, y: 50, width: 100, height: 40))
    }

    /// Resizing a lens shows MORE of the picture underneath, it does not
    /// stretch what was already there, so a start-frame sprite is never right.
    @Test func aLensNeverScalesASprite() {
        #expect(!LayerContent.lens(LensContent()).scalesUniformlyOnResize)
    }

    // MARK: - Zoom

    /// A blur strength and a block size are stated in DOCUMENT POINTS, so a
    /// render at 2x has to restate them in output pixels or a 12pt block comes
    /// out half the size it should be. The amounts that are not lengths (a
    /// greyscale mix, a brightness shift) mean the same thing at any zoom.
    @Test func lengthsGrowWithTheDocumentAndMixesDoNot() {
        var lens = LensContent(adjustment: .blur)
        lens.amount = 10
        lens.adjustment = .pixelate
        lens.amount = 16
        lens.adjustment = .greyscale
        lens.amount = 0.5
        let layer = Layer(name: "Grey", content: .lens(lens),
                          frame: CGRect(x: 10, y: 10, width: 100, height: 50))
        let big = layer.magnified(by: 2)
        #expect(big.lens?.amount(for: .blur) == 20)
        #expect(big.lens?.amount(for: .pixelate) == 32)
        #expect(big.lens?.amount(for: .greyscale) == 0.5)
        #expect(big.frame == CGRect(x: 20, y: 20, width: 200, height: 100))
    }

    /// Magnifying can push a length past the range a person may type, and
    /// clamping it there would silently soften a 2x export. The clamp belongs
    /// to what somebody SETS, not to what the renderer is handed.
    @Test func magnifyingIsNotClampedToTheSliderRange() {
        var lens = LensContent(adjustment: .blur)
        lens.amount = LensAdjustment.blur.range.upperBound
        let layer = Layer(name: "Blur", content: .lens(lens), frame: .zero).magnified(by: 4)
        #expect(layer.lens?.amount == LensAdjustment.blur.range.upperBound * 4)
    }

    // MARK: - The tool

    @Test func theLensToolDrawsNoAnnotationAndPaintsNoColor() {
        #expect(Tool.lens.annotationShape == nil)
        #expect(Tool.lens.colorControl == .hidden)
        #expect(!Tool.lens.paints)
        #expect(Tool.lens.shortcutKey == "k")
    }

    @Test func theLensToolJoinsTheBarNextToTheZoomCallout() {
        let bar = ToolBarLayout.bar(withFrame: false, withLens: true)
        #expect(bar.entries.contains(.tool(.lens)))
        let drawing = bar.families[1]
        let callout = drawing.firstIndex(of: .tool(.zoomCallout))
        let lens = drawing.firstIndex(of: .tool(.lens))
        #expect(callout != nil && lens != nil)
        if let callout, let lens { #expect(lens == callout + 1) }
        #expect(!ToolBarLayout.bar(withFrame: false, withLens: false).entries.contains(.tool(.lens)))
    }

    /// Every tool that draws by dragging gets its choices in the capsule over
    /// the tool bar, so hiding the panel never takes them away.
    @Test func theCapsuleCarriesWhatTheNextLensWillDo() {
        let settings = ToolSettingsBar.settings(for: .lens, availability: .all)
        #expect(settings == [.lensAdjustment, .lensAmount])
        // The lens tool is itself behind a flag, so its two settings need no
        // flag of their own: a tool you cannot pick up shows no capsule.
        #expect(ToolSettingsBar.settings(for: .lens, availability: .none) == settings)
    }

    // MARK: - Redrawing

    /// A lens shows the picture below it, so anything that changes under it
    /// has to redraw it too — the same rule a zoom callout already follows.
    @Test func changingWhatIsUnderALensRedrawsTheLens() {
        let picture = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle)),
                            frame: CGRect(x: 20, y: 20, width: 40, height: 40))
        let lens = Layer(name: "Blur", content: .lens(LensContent(adjustment: .greyscale)),
                         frame: CGRect(x: 200, y: 200, width: 80, height: 80))
        let before = PhotonzDocument(canvasSize: canvas, layers: [picture, lens])
        var after = before
        after.layers[0].frame = CGRect(x: 210, y: 210, width: 40, height: 40)
        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: before, to: after) else {
            Issue.record("expected a dirty rect")
            return
        }
        #expect(dirty.contains(CGRect(x: 200, y: 200, width: 80, height: 80)))
    }
}
