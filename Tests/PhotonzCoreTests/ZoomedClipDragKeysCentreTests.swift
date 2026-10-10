import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Dragging a zoomed-in recording keys where it is centred (task
/// `dragging-a-zoomed-in-recording-keys-where-it-is`).
///
/// The zoom walkthrough's step 6 (`video-zoom-wt.html`): with Scale keyed 100%
/// at 0:03 and 220% at 0:05, dragging the picture at 0:05 to frame the button
/// writes Centre keys at 0:03 and 0:05, four keys in all. The wide shot stays
/// exactly where it was and only the zoom pans. Before this a drag moved the
/// whole clip, so the wide shot slid off and showed the canvas at its edge.
@Suite("Dragging a zoomed-in recording keys where it is centred")
struct ZoomedClipDragKeysCentreTests {

    static func zoomed(keys: [(Int, Double)] = [(3000, 100), (5000, 220)]) -> (PhotonzDocument, UUID) {
        var document = ClipReframeTests.document(ClipReframeTests.clip())
        guard let id = document.layers.first?.id else { return (document, UUID()) }
        for (ms, percent) in keys {
            document.setKeyedValue(.number(percent), layerID: id, .motion(.scale), atDocumentTimeMS: ms)
        }
        return (document, id)
    }

    /// The hand drags the picture as it is posed at `ms`, by `by`.
    static func drag(_ document: inout PhotonzDocument, _ id: UUID, atMS ms: Int, by: CGPoint) {
        document.editPosedForCanvas(layerID: id, atDocumentTimeMS: ms) { doc in
            doc.updateLayer(id: id) { $0.frame = $0.frame.offsetBy(dx: by.x, dy: by.y) }
        }
    }

    static func drawnFrame(_ document: PhotonzDocument, _ id: UUID, atMS ms: Int) -> CGRect? {
        document.drawn(atTimeMS: ms).layer(id: id)?.frame.standardized
    }

    static func positionMoments(_ document: PhotonzDocument, _ id: UUID) -> [Int] {
        document.layer(id: id)?.keyedMotion(.position)?.keyframes.map(\.atMS) ?? []
    }

    @Test("Framing the zoom keys Centre at both Scale keys and leaves the wide shot where it was")
    func framingTheZoomKeysCentre() {
        var (document, id) = Self.zoomed()
        let stored = document.layer(id: id)
        let wideBefore = Self.drawnFrame(document, id, atMS: 3000)
        let tightBefore = Self.drawnFrame(document, id, atMS: 5000)

        Self.drag(&document, id, atMS: 5000, by: CGPoint(x: -300, y: -200))

        // Four keys in all, as the walkthrough counts: two Scale, two Centre.
        #expect(document.keyCount(layerID: id, .motion(.scale)) == 2)
        #expect(Self.positionMoments(document, id) == [3000, 5000])
        // The wide shot has not moved a point...
        #expect(Self.drawnFrame(document, id, atMS: 3000) == wideBefore)
        // ...and the zoom went where the hand took it.
        #expect(Self.drawnFrame(document, id, atMS: 5000) == tightBefore?.offsetBy(dx: -300, dy: -200))
        // The clip itself stays where it is laid out; the keys say the rest.
        #expect(document.layer(id: id)?.frame == stored?.frame)
    }

    @Test("Framing again at the same moment rewrites the Centre key there")
    func framingAgainRewrites() {
        var (document, id) = Self.zoomed()
        let wideBefore = Self.drawnFrame(document, id, atMS: 3000)
        Self.drag(&document, id, atMS: 5000, by: CGPoint(x: -300, y: -200))
        let tight = Self.drawnFrame(document, id, atMS: 5000)

        Self.drag(&document, id, atMS: 5000, by: CGPoint(x: 40, y: 10))

        #expect(Self.positionMoments(document, id) == [3000, 5000])
        #expect(Self.drawnFrame(document, id, atMS: 3000) == wideBefore)
        #expect(Self.drawnFrame(document, id, atMS: 5000) == tight?.offsetBy(dx: 40, dy: 10))
    }

    @Test("Dragging on the wide key moves the wide shot and leaves the zoom where it was")
    func draggingTheWideKeyLeavesTheZoom() {
        var (document, id) = Self.zoomed()
        let tightBefore = Self.drawnFrame(document, id, atMS: 5000)
        let wideBefore = Self.drawnFrame(document, id, atMS: 3000)

        Self.drag(&document, id, atMS: 3000, by: CGPoint(x: 50, y: 0))

        #expect(Self.positionMoments(document, id) == [3000, 5000])
        #expect(Self.drawnFrame(document, id, atMS: 3000) == wideBefore?.offsetBy(dx: 50, dy: 0))
        #expect(Self.drawnFrame(document, id, atMS: 5000) == tightBefore)
    }

    @Test("Dragging after the zoom has landed pans from the last Scale key, leaving the wide shot alone")
    func draggingAfterTheZoomPansFromTheLastKey() {
        var (document, id) = Self.zoomed()
        let wideBefore = Self.drawnFrame(document, id, atMS: 3000)
        let tightBefore = Self.drawnFrame(document, id, atMS: 5000)

        Self.drag(&document, id, atMS: 8000, by: CGPoint(x: -100, y: 0))

        #expect(Self.positionMoments(document, id) == [5000, 8000])
        #expect(Self.drawnFrame(document, id, atMS: 3000) == wideBefore)
        #expect(Self.drawnFrame(document, id, atMS: 5000) == tightBefore)
        #expect(Self.drawnFrame(document, id, atMS: 8000) == tightBefore?.offsetBy(dx: -100, dy: 0))
    }

    @Test("A Scale with only one key is not a move yet, so a drag still just moves the clip")
    func oneScaleKeyStillMoves() {
        var (document, id) = Self.zoomed(keys: [(3000, 100)])
        let stored = document.layer(id: id)

        Self.drag(&document, id, atMS: 3000, by: CGPoint(x: 50, y: 20))

        #expect(document.keyCount(layerID: id, .motion(.position)) == 0)
        #expect(document.layer(id: id)?.frame == stored?.frame.offsetBy(dx: 50, dy: 20))
    }

    @Test("A clip with Centre already keyed gets one more Centre key, as before")
    func keyedCentreGetsOneKey() {
        var (document, id) = Self.zoomed()
        document.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)

        Self.drag(&document, id, atMS: 5000, by: CGPoint(x: -300, y: -200))

        #expect(Self.positionMoments(document, id) == [1000, 5000])
    }

    @Test("A click that never travelled writes no keys")
    func aClickWritesNothing() {
        var (document, id) = Self.zoomed()
        let before = document
        Self.drag(&document, id, atMS: 5000, by: .zero)
        #expect(document == before)
    }

    @Test("Growing the zoom by a corner keeps the wide shot where it was")
    func resizingKeepsTheWideShot() {
        var (document, id) = Self.zoomed()
        let wideBefore = Self.drawnFrame(document, id, atMS: 3000)

        document.editPosedForCanvas(layerID: id, atDocumentTimeMS: 5000) { doc in
            doc.updateLayer(id: id) { layer in
                // Pulled out from the top-left corner, the bottom-right held.
                let box = layer.frame.standardized
                layer.frame = CGRect(x: box.minX - 128, y: box.minY - 72,
                                     width: box.width + 128, height: box.height + 72)
            }
        }

        #expect(Self.positionMoments(document, id) == [3000, 5000])
        #expect(Self.drawnFrame(document, id, atMS: 3000) == wideBefore)
        #expect(ClipReframeTests.scalePercent(of: id, in: document, atMS: 5000) > 220)
    }
}
