import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Snapping a dragged layer to the other layers")
struct PeerSnappingTests {
    let canvas = CGSize(width: 1000, height: 800)
    let size = CGSize(width: 100, height: 40)
    /// A button already sitting on the canvas, for the dragged one to find.
    let peer = CGRect(x: 300, y: 100, width: 100, height: 40)

    func snap(_ x: CGFloat, _ y: CGFloat, peers: [CGRect]? = nil,
              zoom: CGFloat = 1) -> Snapping.Result {
        Snapping.snapFrameOrigin(CGPoint(x: x, y: y), size: size, canvas: canvas,
                                 peers: peers ?? [peer], zoom: zoom)
    }

    @Test func leftEdgesFindEachOther() {
        let result = snap(304, 300)
        #expect(result.origin.x == 300)
        #expect(result.guideX == 300)
    }

    @Test func rightEdgesFindEachOther() {
        // A wider box dragged so its right edge is 2 away from the peer's:
        // nothing else about it is near anything, so only the right edge can
        // explain the move.
        let wider = Snapping.snapFrameOrigin(CGPoint(x: 250, y: 300),
                                             size: CGSize(width: 148, height: 40),
                                             canvas: canvas, peers: [peer], zoom: 1)
        #expect(wider.origin.x == 252) // right edge lands on 400
        #expect(wider.guideX == 400)
    }

    @Test func centersFindEachOther() {
        // Peer's middle is x 350, so a same-width box centres at 300 too; use a
        // narrower one so only the centre can match.
        let narrow = Snapping.snapFrameOrigin(CGPoint(x: 327, y: 300),
                                              size: CGSize(width: 50, height: 40),
                                              canvas: canvas, peers: [peer], zoom: 1)
        #expect(narrow.origin.x == 325)
        #expect(narrow.guideX == 350)
    }

    @Test func aLayerSitsFlushAgainstAnother() {
        // Dragging up against the peer's right edge: the dragged left edge
        // takes it, so the two boxes touch with no gap.
        let result = snap(403, 300)
        #expect(result.origin.x == 400)
        #expect(result.guideX == 400)
    }

    @Test func topsAndBottomsFindEachOtherToo() {
        #expect(snap(600, 103).origin.y == 100)   // top to top
        #expect(snap(600, 143).origin.y == 140)   // top to the peer's bottom
        #expect(snap(600, 97).guideY == 100)
    }

    @Test func farFromEverythingNothingMoves() {
        let result = snap(600, 500)
        #expect(result.origin == CGPoint(x: 600, y: 500))
        #expect(result.guideX == nil)
        #expect(result.guideY == nil)
    }

    @Test func theCanvasStillAttractsWithNoLayersAround() {
        let result = Snapping.snapFrameOrigin(CGPoint(x: 5, y: 300), size: size,
                                              canvas: canvas, peers: [], zoom: 1)
        #expect(result.origin.x == 0)
        #expect(result.guideX == 0)
    }

    @Test func theNearestMatchWinsWhenBothAreInReach() {
        // The box is dragged to 445, so its middle at 495 is 5 from the canvas
        // middle — in reach. A layer's left edge at 443 is only 2 away, so the
        // layer wins and the canvas does not drag it off by three points.
        let near = CGRect(x: 443, y: 600, width: 20, height: 20)
        let result = Snapping.snapFrameOrigin(CGPoint(x: 445, y: 300), size: size,
                                              canvas: canvas, peers: [near], zoom: 1)
        #expect(result.origin.x == 443)
        #expect(result.guideX == 443)
    }

    @Test func theToleranceIsConstantOnScreenAtAnyZoom() {
        // 4 document points is 4 screen points at 100% and 16 at 400%, so the
        // same gap takes at one zoom and not at the other.
        #expect(snap(304, 300, zoom: 1).origin.x == 300)
        #expect(snap(304, 300, zoom: 4).origin.x == 304)
        // ...and zoomed out, a 20-point gap is 5 screen points, so it takes.
        #expect(snap(320, 300, zoom: 0.25).origin.x == 300)
    }

    // MARK: The line that gets drawn

    @Test func theLineOnlyReachesAcrossTheBoxesItJoins() {
        // Dragged box at y 300…340 lining up with a peer at y 100…140: the
        // line spans 100…340 and no further, rather than the whole picture.
        let span = snap(304, 300).guideXSpan
        #expect(span == Snapping.Span(start: 100, end: 340))
    }

    @Test func aLineThroughSeveralLayersReachesAllOfThem() {
        let others = [peer, CGRect(x: 300, y: 600, width: 60, height: 30)]
        let span = snap(304, 300, peers: others).guideXSpan
        #expect(span == Snapping.Span(start: 100, end: 630))
    }

    @Test func aCanvasLineStillSpansTheWholePicture() {
        let result = Snapping.snapFrameOrigin(CGPoint(x: 5, y: 300), size: size,
                                              canvas: canvas, peers: [], zoom: 1)
        #expect(result.guideX == 0)
        #expect(result.guideXSpan == nil) // nil means "the whole picture"
    }
}

@Suite("Which layers a dragged layer lines up with")
struct SnapPeerTests {
    func rect(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 40, height: 20)
    }

    func layer(_ name: String, _ frame: CGRect, visible: Bool = true,
               children: [Layer] = []) -> Layer {
        guard children.isEmpty else {
            return Layer(name: name, content: .group(GroupContent(children: children)),
                         frame: frame, isVisible: visible)
        }
        return Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
                     frame: frame, isVisible: visible)
    }

    @Test func theDraggedLayerNeverLinesUpWithItself() {
        let a = layer("a", rect(0, 0))
        let b = layer("b", rect(100, 0))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [a, b])
        #expect(doc.snapPeers(excluding: a.id) == [rect(100, 0)])
    }

    @Test func hiddenLayersDoNotAttract() {
        let a = layer("a", rect(0, 0))
        let ghost = layer("ghost", rect(100, 0), visible: false)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [a, ghost])
        #expect(doc.snapPeers(excluding: a.id).isEmpty)
    }

    @Test func aGroupAndItsContentsBothAttract() {
        let inner = layer("inner", rect(10, 10))
        let group = layer("card", CGRect(x: 100, y: 100, width: 0, height: 0), children: [inner])
        let dragged = layer("dragged", rect(0, 0))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [dragged, group])
        let peers = doc.snapPeers(excluding: dragged.id)
        #expect(peers.contains(rect(110, 110)))       // the layer inside, in canvas space
        #expect(peers.contains(CGRect(x: 110, y: 110, width: 40, height: 20))) // the card's own box
    }

    @Test func theGroupYouAreInsideDoesNotChaseYou() {
        let inner = layer("inner", rect(10, 10))
        let sibling = layer("sibling", rect(80, 10))
        let group = layer("card", CGRect(x: 100, y: 100, width: 0, height: 0),
                          children: [inner, sibling])
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        let peers = doc.snapPeers(excluding: inner.id)
        #expect(peers == [rect(180, 110)]) // the sibling only: not the group around them
    }

    @Test func nothingInsideTheDraggedGroupAttracts() {
        let inner = layer("inner", rect(10, 10))
        let group = layer("card", CGRect(x: 100, y: 100, width: 0, height: 0), children: [inner])
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        #expect(doc.snapPeers(excluding: group.id).isEmpty)
    }
}
