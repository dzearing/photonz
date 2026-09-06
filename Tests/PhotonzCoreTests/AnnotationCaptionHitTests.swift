import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A click only picks up a captioned arrow where the arrow or its label
/// actually is.
///
/// The label's footprint used to be `estimatedCaptionSize`, a deliberately
/// generous reservation that runs 163pt past the far edge of a sentence. That
/// much blank picture answered to the arrow, so a click aimed at the button
/// underneath picked the arrow up instead. Reported on 2026-09-05 while the
/// caption drop was being fixed.
@Suite("Clicking beside an arrow's label")
struct AnnotationCaptionHitTests {

    private let canvas = CGSize(width: 1440, height: 960)
    /// A sentence long enough that the estimate and the measurement diverge.
    private let sentence = "Primary action button label"

    /// A left-growing captioned arrow: the tail is at `tail`, the head 300pt
    /// to its right, so the pill hangs to the LEFT of the tail.
    private func arrow(_ caption: String, tail: CGPoint) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        return AnnotationBuilder.layer(content: content, from: tail,
                                       to: CGPoint(x: tail.x + 300, y: tail.y))
    }

    /// A stand-in for the app's type measurer: a sentence's pill measures a
    /// good deal narrower than the estimate reserves for it.
    private func measurer(_ width: CGFloat, _ height: CGFloat) -> CaptionPillSizing {
        { _ in CGSize(width: width, height: height) }
    }

    @Test func theEstimateReservesFarMoreRoomThanASentenceNeeds() {
        let content = arrow(sentence, tail: CGPoint(x: 700, y: 480)).annotation!
        #expect(content.estimatedCaptionSize.width > 380)
    }

    @Test func aClickPastTheEndOfTheLabelMissesTheArrow() {
        let layer = arrow(sentence, tail: CGPoint(x: 700, y: 480))
        let measured = CGSize(width: 245, height: 46)
        let pill = CanvasGrab.captionPillRect(of: layer, captionPillSize: measured)!
        // 40pt past the pill's far edge: blank picture by eye, and well inside
        // the box the estimate would have reserved.
        let past = CGPoint(x: pill.minX - 40, y: pill.midY)
        #expect(layer.frame.contains(past), "the sloppy box still covers this point")
        #expect(layer.contains(canvasPoint: past,
                               captionPillSize: measurer(245, 46)) == false)
    }

    @Test func aClickOnTheLabelStillPicksUpTheArrow() {
        let layer = arrow(sentence, tail: CGPoint(x: 700, y: 480))
        let pill = CanvasGrab.captionPillRect(of: layer,
                                              captionPillSize: CGSize(width: 245, height: 46))!
        for p in [CGPoint(x: pill.midX, y: pill.midY),
                  CGPoint(x: pill.minX + 4, y: pill.midY),
                  CGPoint(x: pill.maxX - 4, y: pill.midY)] {
            #expect(layer.contains(canvasPoint: p, captionPillSize: measurer(245, 46)),
                    "\(p) is on the label")
        }
    }

    @Test func theShaftIsStillHittableWithAMeasurer() {
        let layer = arrow(sentence, tail: CGPoint(x: 700, y: 480))
        #expect(layer.contains(canvasPoint: CGPoint(x: 850, y: 480),
                               captionPillSize: measurer(245, 46)))
    }

    @Test func aDocumentHitTestTakesTheMeasurerToo() {
        var document = PhotonzDocument(canvasSize: canvas)
        let layer = arrow(sentence, tail: CGPoint(x: 700, y: 480))
        document.layers = [layer]
        let pill = CanvasGrab.captionPillRect(of: layer,
                                              captionPillSize: CGSize(width: 245, height: 46))!
        let past = CGPoint(x: pill.minX - 40, y: pill.midY)
        #expect(document.hitTest(past)?.id == layer.id, "the estimate still swallows it")
        #expect(document.hitTest(past, captionPillSize: measurer(245, 46)) == nil)
        #expect(document.hitTest(CGPoint(x: pill.midX, y: pill.midY),
                                 captionPillSize: measurer(245, 46))?.id == layer.id)
    }

    /// A measurer that has nothing to say about a caption (no label, or a font
    /// it cannot resolve) falls back to the estimate rather than dropping the
    /// label out of the hit test.
    @Test func aMeasurerThatAnswersNilFallsBackToTheEstimate() {
        let layer = arrow(sentence, tail: CGPoint(x: 700, y: 480))
        let anchor = layer.annotation!.captionAnchor()
        let point = CGPoint(x: layer.frame.minX + anchor.x, y: layer.frame.minY + anchor.y)
        let noAnswer: CaptionPillSizing = { _ in nil }
        #expect(layer.contains(canvasPoint: point, captionPillSize: noAnswer))
    }
}
