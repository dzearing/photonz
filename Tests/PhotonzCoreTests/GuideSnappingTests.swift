import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A pinned guide catches a drag and a resize exactly the way the canvas's own
/// edge does: full-span line, same result field, same release under ⌘ (which is
/// the caller declining to pass any snapping at all).
@Suite("Dragging and resizing catch pinned guides")
struct GuideSnappingTests {
    let canvas = CGSize(width: 1000, height: 800)
    let size = CGSize(width: 100, height: 60)

    private func guide(_ axis: CanvasGuideAxis, _ at: CGFloat) -> CanvasGuide {
        CanvasGuide(axis: axis, position: at)
    }

    @Test func aDraggedLayersLeadingEdgeCatchesAVerticalGuide() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 314, y: 400), size: size, canvas: canvas,
                                           guides: [guide(.vertical, 320)], zoom: 1)
        #expect(out.origin.x == 320)
        #expect(out.guideX == 320)
        // A guide is a full-picture line, like a canvas edge: no span.
        #expect(out.guideXSpan == nil)
    }

    @Test func aDraggedLayersTrailingEdgeCatchesItToo() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 216, y: 400), size: size, canvas: canvas,
                                           guides: [guide(.vertical, 320)], zoom: 1)
        #expect(out.origin.x == 220)
        #expect(out.guideX == 320)
    }

    @Test func aDraggedLayersMiddleCatchesIt() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 273, y: 400), size: size, canvas: canvas,
                                           guides: [guide(.vertical, 320)], zoom: 1)
        #expect(out.origin.x == 270)
        #expect(out.guideX == 320)
    }

    @Test func aHorizontalGuideCatchesTheOtherAxis() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 400, y: 195), size: size, canvas: canvas,
                                           guides: [guide(.horizontal, 200)], zoom: 1)
        #expect(out.origin.y == 200)
        #expect(out.guideY == 200)
        #expect(out.guideX == nil)
    }

    @Test func aResizedEdgeCatchesAGuide() {
        let out = Snapping.snapResizedFrame(CGRect(x: 100, y: 100, width: 217, height: 60),
                                            handle: .right, canvas: canvas,
                                            guides: [guide(.vertical, 320)], zoom: 1)
        #expect(out.frame.maxX == 320)
        #expect(out.guideX == 320)
    }

    /// The whole point of the feature: 16pt in from each side of a space the
    /// grid does not line up with. Two guides, and a box dropped roughly
    /// between them comes to rest exactly on them.
    @Test func twoGuidesMarkAMarginAndABoxLandsInsideIt() {
        let guides = [guide(.vertical, 16), guide(.vertical, 384)]
        let left = Snapping.snapFrameOrigin(CGPoint(x: 19, y: 100),
                                            size: CGSize(width: 368, height: 60),
                                            canvas: canvas, guides: guides, zoom: 1)
        #expect(left.origin.x == 16)
        // ...and its far edge lands on the other one, because it is exactly as
        // wide as the space between them.
        #expect(left.origin.x + 368 == 384)
    }

    /// A guide is not the grid: it catches whether or not the grid is pulling,
    /// because the caller passes it in either way. What the grid still owns is
    /// the quantize underneath, and the two do not fight — a guide inside reach
    /// wins, and away from one the grid is what places the box.
    @Test func aGuideWinsOverTheGridUnderneathIt() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 318, y: 400), size: size, canvas: canvas,
                                           gridSpacing: 8, guides: [guide(.vertical, 322)],
                                           zoom: 1)
        #expect(out.origin.x == 322)
        #expect(out.guideX == 322)
        #expect(out.gridX == nil)
    }

    @Test func awayFromEveryGuideTheGridStillPlacesIt() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 101, y: 400), size: size, canvas: canvas,
                                           gridSpacing: 8, guides: [guide(.vertical, 322)],
                                           zoom: 1)
        #expect(out.origin.x == 104)
        #expect(out.guideX == nil)
        #expect(out.gridX == 104)
    }

    /// Ties go to the guide rather than to another layer: you put the guide
    /// there on purpose, and the layer only happens to be there.
    @Test func aGuideBeatsALayerEdgeOnTheSameNumber() {
        let out = Snapping.snapFrameOrigin(CGPoint(x: 317, y: 400), size: size, canvas: canvas,
                                           peers: [CGRect(x: 320, y: 0, width: 40, height: 40)],
                                           guides: [guide(.vertical, 320)], zoom: 1)
        #expect(out.origin.x == 320)
        // The line drawn runs right across the picture, which is what says
        // "that is the guide" rather than "that is the other box".
        #expect(out.guideXSpan == nil)
    }

    /// With no guides passed in — which is what ⌘ and a document with none look
    /// like from here — every answer is bit for bit what it was before guides
    /// existed.
    @Test func noGuidesChangesNothing() {
        let with = Snapping.snapFrameOrigin(CGPoint(x: 317, y: 400), size: size, canvas: canvas,
                                            gridSpacing: 8, guides: [], zoom: 1)
        let without = Snapping.snapFrameOrigin(CGPoint(x: 317, y: 400), size: size, canvas: canvas,
                                               gridSpacing: 8, zoom: 1)
        #expect(with == without)
    }
}
