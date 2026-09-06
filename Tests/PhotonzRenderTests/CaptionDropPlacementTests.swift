import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Where a dragged caption pill comes to rest, measured with the SAME text
/// measurer the rasterizer bakes the pill with. The model's own
/// `estimatedCaptionSize` is a deliberately generous guess — 63pt wide for a
/// two letter label that measures 55, 408 for a sentence that measures 245 —
/// so a drop worked out against the estimate lands the label somewhere the
/// hand never put it.
@Suite("Caption drop lands where the hand let go")
struct CaptionDropPlacementTests {

    private let canvas = CGSize(width: 1440, height: 960)
    private let captions = ["ok", "Save all the changes here"]

    private func arrow(_ caption: String) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        return AnnotationBuilder.layer(content: content, from: CGPoint(x: 700, y: 500),
                                       to: CGPoint(x: 900, y: 500))
    }

    /// The measured pill, and where its centre lands, in document space.
    private func measured(_ layer: Layer) -> (size: CGSize, centre: CGPoint) {
        var probe = layer.annotation!
        probe.start = layer.annotationEndpoint(.start)!
        probe.end = layer.annotationEndpoint(.end)!
        let size = CaptionMetrics.pillSize(for: probe.caption ?? "", in: probe)
        return (size, probe.captionPillCenter(forPillSize: size))
    }

    @Test func aLabelCentresOnTheSpotItWasLetGoOf() {
        for caption in captions {
            let layer = arrow(caption)
            let pill = CaptionMetrics.pillSize(for: caption, in: layer.annotation!)
            let drop = CGPoint(x: 520, y: 720)
            let placed = AnnotationBuilder.placingCaption(layer, at: drop, canvas: canvas,
                                                          captionPillSize: pill)
            let landed = measured(placed).centre
            #expect(abs(landed.x - drop.x) < 1)
            #expect(abs(landed.y - drop.y) < 1)
        }
    }

    @Test func aLabelTuckedAgainstTheEdgeStaysTucked() {
        // A redliner's favourite spot. The estimate used to hold a sentence
        // 157pt off the edge it was aimed at.
        for caption in captions {
            let layer = arrow(caption)
            let pill = CaptionMetrics.pillSize(for: caption, in: layer.annotation!)
            let drop = CGPoint(x: canvas.width - pill.width / 2 - 6, y: 720)
            let placed = AnnotationBuilder.placingCaption(layer, at: drop, canvas: canvas,
                                                          captionPillSize: pill)
            let landed = measured(placed)
            #expect(abs(landed.centre.x - drop.x) < 1)
            #expect(abs(landed.centre.x + landed.size.width / 2 - (canvas.width - 6)) < 1)
        }
    }

    @Test func aLabelDroppedOffThePictureComesBackByItsOwnEdge() {
        for caption in captions {
            let layer = arrow(caption)
            let pill = CaptionMetrics.pillSize(for: caption, in: layer.annotation!)
            let placed = AnnotationBuilder.placingCaption(layer, at: CGPoint(x: 2000, y: 720),
                                                          canvas: canvas, captionPillSize: pill)
            let landed = measured(placed)
            #expect(abs(landed.centre.x + landed.size.width / 2 - canvas.width) < 1)
        }
    }

    @Test func aDroppedLabelHoldsItsSpotWhenTheArrowIsMoved() {
        for caption in captions {
            let layer = arrow(caption)
            let pill = CaptionMetrics.pillSize(for: caption, in: layer.annotation!)
            let drop = CGPoint(x: 520, y: 720)
            let placed = AnnotationBuilder.placingCaption(layer, at: drop, canvas: canvas,
                                                          captionPillSize: pill)
            // Whole arrow dragged 40 right, 20 up: the label goes with it.
            let moved = AnnotationBuilder.planningCaption(
                AnnotationBuilder.updating(placed, start: CGPoint(x: 740, y: 480),
                                           end: CGPoint(x: 940, y: 480)),
                canvas: canvas, captionPillSize: pill)
            let landed = measured(moved).centre
            #expect(abs(landed.x - (drop.x + 40)) < 1)
            #expect(abs(landed.y - (drop.y - 20)) < 1)
            // Head dragged somewhere else entirely: the label does not budge.
            let stretched = AnnotationBuilder.planningCaption(
                AnnotationBuilder.updating(placed, start: CGPoint(x: 700, y: 500),
                                           end: CGPoint(x: 1300, y: 250)),
                canvas: canvas, captionPillSize: pill)
            let held = measured(stretched).centre
            #expect(abs(held.x - drop.x) < 1)
            #expect(abs(held.y - drop.y) < 1)
        }
    }

    @Test func theLabelIsPickedUpByTheLabelAndNotTheRoomAroundIt() {
        for caption in captions {
            let layer = arrow(caption)
            let pill = CaptionMetrics.pillSize(for: caption, in: layer.annotation!)
            let placed = AnnotationBuilder.placingCaption(layer, at: CGPoint(x: 520, y: 720),
                                                          canvas: canvas, captionPillSize: pill)
            let grab = CanvasGrab.captionPillRect(of: placed, captionPillSize: pill)!
            #expect(abs(grab.width - pill.width) < 0.001)
            #expect(abs(grab.midX - measured(placed).centre.x) < 0.001)
        }
    }
}
