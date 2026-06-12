import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Layer hit-testing")
struct HitTestTests {
    func makeLayer(_ name: String, frame: CGRect,
                   visible: Bool = true, locked: Bool = false,
                   transform: LayerTransform = .identity) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
              frame: frame, transform: transform, isVisible: visible, isLocked: locked)
    }

    @Test func topmostOverlappingLayerWins() {
        let bottom = makeLayer("bottom", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let top = makeLayer("top", frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200), layers: [bottom, top])
        #expect(doc.hitTest(CGPoint(x: 75, y: 75))?.id == top.id)   // overlap → top
        #expect(doc.hitTest(CGPoint(x: 25, y: 25))?.id == bottom.id) // only bottom
        #expect(doc.hitTest(CGPoint(x: 180, y: 180)) == nil)         // empty space
    }

    @Test func invisibleAndLockedLayersAreSkipped() {
        let base = makeLayer("base", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let hidden = makeLayer("hidden", frame: CGRect(x: 0, y: 0, width: 100, height: 100), visible: false)
        let locked = makeLayer("locked", frame: CGRect(x: 0, y: 0, width: 100, height: 100), locked: true)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200),
                                  layers: [base, hidden, locked])
        #expect(doc.hitTest(CGPoint(x: 50, y: 50))?.id == base.id)
    }

    @Test func rotatedLayerHitsItsTransformedShapeNotItsFrame() {
        // A wide thin bar rotated 90° around its center occupies a vertical strip.
        let bar = makeLayer("bar", frame: CGRect(x: 0, y: 40, width: 100, height: 20),
                            transform: LayerTransform(rotation: .pi / 2))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [bar])
        // Center column is inside both before and after rotation.
        #expect(doc.hitTest(CGPoint(x: 50, y: 50))?.id == bar.id)
        // Far-left of the unrotated frame is empty space after rotation.
        #expect(doc.hitTest(CGPoint(x: 5, y: 50)) == nil)
        // Above the unrotated frame but inside the rotated vertical strip.
        #expect(doc.hitTest(CGPoint(x: 50, y: 10))?.id == bar.id)
    }

    @Test func baseImageLayerIsLockedSoItNeverHitTests() {
        let doc = PhotonzDocument.withBaseImage(ImageRef(pixelSize: CGSize(width: 400, height: 300)))
        #expect(doc.layers[0].isLocked)
        #expect(doc.hitTest(CGPoint(x: 200, y: 150)) == nil)
    }
}

@Suite("Snapping")
struct SnappingTests {
    let canvas = CGSize(width: 1000, height: 800)
    let size = CGSize(width: 100, height: 60)

    @Test func leadingEdgeSnapsToCanvasEdgeWithinTolerance() {
        let r = Snapping.snapFrameOrigin(CGPoint(x: 5, y: 300), size: size, canvas: canvas, zoom: 1)
        #expect(r.origin == CGPoint(x: 0, y: 300))
        #expect(r.guideX == 0)
        #expect(r.guideY == nil)
    }

    @Test func outsideToleranceNothingSnaps() {
        let r = Snapping.snapFrameOrigin(CGPoint(x: 9, y: 300), size: size, canvas: canvas, zoom: 1)
        #expect(r.origin == CGPoint(x: 9, y: 300))
        #expect(r.guideX == nil && r.guideY == nil)
    }

    @Test func toleranceIsInScreenPointsSoZoomingInTightensIt() {
        // 5 doc points off: snaps at 1× (5px on screen) but not at 4× (20px on screen).
        let zoomedIn = Snapping.snapFrameOrigin(CGPoint(x: 5, y: 300), size: size, canvas: canvas, zoom: 4)
        #expect(zoomedIn.guideX == nil)
        // …and zooming out loosens it: 12 doc points at 0.5× is 6 screen px.
        let zoomedOut = Snapping.snapFrameOrigin(CGPoint(x: 12, y: 300), size: size, canvas: canvas, zoom: 0.5)
        #expect(zoomedOut.origin.x == 0)
    }

    @Test func centerSnapsToCanvasCenter() {
        // Canvas center x = 500 → frame midX 500 → origin.x 450. Propose 447.
        let r = Snapping.snapFrameOrigin(CGPoint(x: 447, y: 100), size: size, canvas: canvas, zoom: 1)
        #expect(r.origin.x == 450)
        #expect(r.guideX == 500)
    }

    @Test func trailingEdgeSnapsToCanvasTrailingEdge() {
        // maxX 1000 → origin.x 900. Propose 904 (4 off).
        let r = Snapping.snapFrameOrigin(CGPoint(x: 904, y: 100), size: size, canvas: canvas, zoom: 1)
        #expect(r.origin.x == 900)
        #expect(r.guideX == 1000)
    }

    @Test func axesSnapIndependently() {
        let r = Snapping.snapFrameOrigin(CGPoint(x: 3, y: 736), size: size, canvas: canvas, zoom: 1)
        #expect(r.origin == CGPoint(x: 0, y: 740)) // maxY 796 → snaps to 800
        #expect(r.guideX == 0)
        #expect(r.guideY == 800)
    }

    @Test func nearestCandidateWinsWhenSeveralAreInTolerance() {
        // A frame as wide as the canvas: minX→0 and maxX→1000 both candidates.
        // Propose origin 2: minX is 2 away, maxX is |2+1000-1000| = 2 away too —
        // make it asymmetric: propose 3 with width 998 → minX d=3, maxX d=1.
        let r = Snapping.snapFrameOrigin(CGPoint(x: 3, y: 100),
                                         size: CGSize(width: 998, height: 60),
                                         canvas: canvas, zoom: 1)
        #expect(r.origin.x == 2) // maxX 1001 → 1000 wins (distance 1 < 3)
        #expect(r.guideX == 1000)
    }
}
