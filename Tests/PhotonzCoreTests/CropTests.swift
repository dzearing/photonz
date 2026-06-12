import CoreGraphics
import PhotonzCore
import Testing

@Suite("Crop geometry")
struct CropTests {
    let canvas = CGSize(width: 400, height: 400)

    // MARK: Aspect ratios

    @Test func aspectRatios() {
        let fourThree: CGFloat = 4.0 / 3.0
        let sixteenNine: CGFloat = 16.0 / 9.0
        #expect(CropAspect.free.ratio == nil)
        #expect(CropAspect.square.ratio == 1)
        #expect(CropAspect.fourThree.ratio == fourThree)
        #expect(CropAspect.sixteenNine.ratio == sixteenNine)
    }

    @Test func aspectLabels() {
        #expect(CropAspect.free.label == "Free")
        #expect(CropAspect.square.label == "1:1")
        #expect(CropAspect.fourThree.label == "4:3")
        #expect(CropAspect.sixteenNine.label == "16:9")
    }

    // MARK: Fitting a rect to an aspect

    @Test func fittedFreeReturnsTheRectUnchanged() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
        #expect(Crop.fitted(rect, to: .free) == rect)
    }

    @Test func fittedSquareCentersInsideALandscapeRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(Crop.fitted(rect, to: .square) == CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    @Test func fittedSixteenNineCentersInsideATallRect() {
        let rect = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        #expect(Crop.fitted(rect, to: .sixteenNine) == CGRect(x: 0, y: 150, width: 1600, height: 900))
    }

    // MARK: Free resize

    @Test func freeResizeClampsToCanvas() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 500, y: 500),
                                 aspect: .free, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 300, height: 300))
    }

    @Test func freeResizeNeverInverts() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 0, y: 0),
                                 aspect: .free, canvas: canvas)
        #expect(result.origin == CGPoint(x: 100, y: 100))
        #expect(result.width >= 1 && result.height >= 1)
    }

    // MARK: Ratio-locked corner resize

    @Test func ratioCornerFollowsTheDominantAxis() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 250, y: 220),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 150, height: 150))
    }

    @Test func ratioCornerAnchorsTheOppositeCorner() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .topLeft, to: CGPoint(x: 50, y: 80),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 50, y: 50, width: 150, height: 150))
    }

    @Test func ratioCornerClampsToCanvasKeepingTheRatio() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 300, height: 300))
    }

    @Test func ratioCornerClampWhenOneAxisHitsTheEdgeFirst() {
        // Anchor at (100, 300): 300pt available right, 300 up — but a 16:9 box
        // dragged far right is limited by height: h ≤ 300 → w ≤ 533… no, w ≤ 300.
        let rect = CGRect(x: 100, y: 200, width: 160, height: 90)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .sixteenNine, canvas: canvas)
        // availX = 300, availY = 200 → w = min(300, 200 * 16/9 ≈ 355.6) = 300
        #expect(result.origin == CGPoint(x: 100, y: 200))
        #expect(result.width == 300)
        #expect(abs(result.height - 300 * 9 / 16) < 0.001)
    }

    // MARK: Ratio-locked edge resize

    @Test func ratioEdgeScalesTheCrossAxisAroundItsCenter() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .right, to: CGPoint(x: 260, y: 150),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 70, width: 160, height: 160))
    }

    @Test func ratioEdgeClampsWhenTheCrossAxisHitsTheCanvas() {
        // midY = 60 → centered height can grow to 2 × min(60, 340) = 120.
        let rect = CGRect(x: 100, y: 10, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .right, to: CGPoint(x: 350, y: 60),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 0, width: 120, height: 120))
    }

    @Test func ratioTopEdgeScalesWidthAroundItsCenter() {
        let rect = CGRect(x: 150, y: 150, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .top, to: CGPoint(x: 0, y: 100),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 125, y: 100, width: 150, height: 150))
    }

    // MARK: Moving

    @Test func moveClampsInsideTheCanvas() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.moved(rect, by: CGPoint(x: 50, y: -30), in: canvas)
                == CGRect(x: 150, y: 70, width: 100, height: 100))
        #expect(Crop.moved(rect, by: CGPoint(x: 1000, y: -1000), in: canvas)
                == CGRect(x: 300, y: 0, width: 100, height: 100))
    }

    // MARK: Drag-to-define a fresh rect

    @Test func dragRectStandardizesAndClampsFreeDrags() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 200, y: 200), current: CGPoint(x: -50, y: 100),
                                 aspect: .free, canvas: canvas)
        #expect(rect == CGRect(x: 0, y: 100, width: 200, height: 100))
    }

    @Test func emptyDragYieldsNil() {
        let p = CGPoint(x: 200, y: 200)
        #expect(Crop.dragRect(anchor: p, current: p, aspect: .free, canvas: canvas) == nil)
        #expect(Crop.dragRect(anchor: p, current: p, aspect: .square, canvas: canvas) == nil)
    }

    @Test func ratioDragFollowsTheDominantAxisInTheDragDirection() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 200, y: 200), current: CGPoint(x: 100, y: 140),
                                 aspect: .square, canvas: canvas)
        #expect(rect == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test func ratioDragClampsToTheCanvasCorner() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 350, y: 350), current: CGPoint(x: 600, y: 600),
                                 aspect: .square, canvas: canvas)
        #expect(rect == CGRect(x: 350, y: 350, width: 50, height: 50))
    }

    // MARK: Rule-of-thirds grid

    @Test func thirdsLinesDivideTheRectInThree() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 90)
        let lines = Crop.thirdsLines(in: rect)
        #expect(lines.count == 4)
        #expect(lines.contains { $0.from == CGPoint(x: 100, y: 0) && $0.to == CGPoint(x: 100, y: 90) })
        #expect(lines.contains { $0.from == CGPoint(x: 200, y: 0) && $0.to == CGPoint(x: 200, y: 90) })
        #expect(lines.contains { $0.from == CGPoint(x: 0, y: 30) && $0.to == CGPoint(x: 300, y: 30) })
        #expect(lines.contains { $0.from == CGPoint(x: 0, y: 60) && $0.to == CGPoint(x: 300, y: 60) })
    }
}
