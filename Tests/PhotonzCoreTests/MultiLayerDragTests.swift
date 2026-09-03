import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Dragging a multi-selection on the canvas: press on any one of the picked
/// layers and every one of them travels the same distance, as one object.
/// The rule that makes it feel like one object is that the box the SELECTION
/// makes is what moves — so it is that box, not whichever piece happens to be
/// under the pointer, that lines up with the picture and with everything else.
@Suite("Dragging everything you picked")
struct MultiLayerDragTests {

    private func leaf(_ name: String, _ frame: CGRect, locked: Bool = false) -> Layer {
        var layer = Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
                          frame: frame)
        layer.isLocked = locked
        return layer
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    /// Three loose boxes on a 400×400 canvas: "A" at (10, 10) 100×50,
    /// "B" at (200, 30) 60×60, "C" at (40, 300) 80×20.
    private func makeFlat() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                        layers: [leaf("A", CGRect(x: 10, y: 10, width: 100, height: 50)),
                                 leaf("B", CGRect(x: 200, y: 30, width: 60, height: 60)),
                                 leaf("C", CGRect(x: 40, y: 300, width: 80, height: 20))])
    }

    // MARK: What the drag picks up

    @Test func theBoxIsEverythingPickedPutTogether() {
        let doc = makeFlat()
        let drag = doc.multiLayerDrag(moving: [id(doc, "A"), id(doc, "B")])
        // A spans x 10…110, B spans x 200…260; tops 10 and 30, bottoms 60 and 90.
        #expect(drag?.bounds == CGRect(x: 10, y: 10, width: 250, height: 80))
    }

    @Test func everythingPickedTravelsTheSameDistance() {
        let doc = makeFlat()
        let ids = [id(doc, "A"), id(doc, "B"), id(doc, "C")]
        guard let drag = doc.multiLayerDrag(moving: Set(ids)) else {
            Issue.record("expected a drag")
            return
        }
        // The selection's box starts at (10, 10); dragging it to (40, 90) is
        // +30, +80, so every member moves by exactly that.
        let moves = drag.origins(movingBoundsTo: CGPoint(x: 40, y: 90))
        #expect(moves[ids[0]] == CGPoint(x: 40, y: 90))
        #expect(moves[ids[1]] == CGPoint(x: 230, y: 110))
        #expect(moves[ids[2]] == CGPoint(x: 70, y: 380))
    }

    @Test func nothingMovesWhenTheBoxGoesBackWhereItWas() {
        let doc = makeFlat()
        let ids = Set([id(doc, "A"), id(doc, "B")])
        guard let drag = doc.multiLayerDrag(moving: ids) else {
            Issue.record("expected a drag")
            return
        }
        let moves = drag.origins(movingBoundsTo: drag.bounds.origin)
        #expect(moves[id(doc, "A")] == CGRect(x: 10, y: 10, width: 100, height: 50).origin)
        #expect(moves[id(doc, "B")] == CGPoint(x: 200, y: 30))
    }

    @Test func aLockedLayerStaysWhereItIs() {
        var doc = makeFlat()
        doc.updateLayer(id: id(doc, "A")) { $0.isLocked = true }
        let drag = doc.multiLayerDrag(moving: Set(doc.allLayers.map(\.id)))
        #expect(drag?.members.contains { $0.id == id(doc, "A") } == false)
        // …and the box is drawn from what actually moves, so a locked layer
        // cannot drag the rest of the selection off its own edges.
        #expect(drag?.bounds == CGRect(x: 40, y: 30, width: 220, height: 290))
    }

    @Test func aSelectionOfOnlyLockedLayersIsNoDragAtAll() {
        var doc = makeFlat()
        for layer in doc.allLayers { doc.updateLayer(id: layer.id) { $0.isLocked = true } }
        #expect(doc.multiLayerDrag(moving: Set(doc.allLayers.map(\.id))) == nil)
        #expect(doc.multiLayerDrag(moving: []) == nil)
    }

    // MARK: Groups

    /// A group "Card" at (100, 100) holding "Box" at local (0, 0) 120×80, and a
    /// loose "Away" box well clear of it.
    private func makeGrouped() -> PhotonzDocument {
        let box = leaf("Box", CGRect(x: 0, y: 0, width: 120, height: 80))
        let card = Layer(name: "Card", content: .group(GroupContent(children: [box])),
                         frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                               layers: [leaf("Away", CGRect(x: 300, y: 300, width: 40, height: 40)),
                                        card])
    }

    @Test func aPieceInsideAPickedGroupDoesNotMoveTwice() {
        let doc = makeGrouped()
        let drag = doc.multiLayerDrag(moving: [id(doc, "Card"), id(doc, "Box")])
        // The group already carries the piece: listing both would offset it once
        // for the group and again for itself.
        #expect(drag?.members.map(\.id) == [id(doc, "Card")])
    }

    @Test func aGroupMovesByTheBoxItsContentsMake() {
        let doc = makeGrouped()
        guard let drag = doc.multiLayerDrag(moving: [id(doc, "Card"), id(doc, "Away")]) else {
            Issue.record("expected a drag")
            return
        }
        // Card occupies (100, 100)–(220, 180) even though its stored frame is a
        // zero-sized anchor, so the selection's box reaches from 100 to 340.
        #expect(drag.bounds == CGRect(x: 100, y: 100, width: 240, height: 240))
        let moves = drag.origins(movingBoundsTo: CGPoint(x: 110, y: 100))
        #expect(moves[id(doc, "Card")] == CGPoint(x: 110, y: 100))
        #expect(moves[id(doc, "Away")] == CGPoint(x: 310, y: 300))
    }

    @Test func movingTheGroupCarriesWhatIsInsideIt() {
        var doc = makeGrouped()
        guard let drag = doc.multiLayerDrag(moving: [id(doc, "Card"), id(doc, "Away")]) else {
            Issue.record("expected a drag")
            return
        }
        for (layerID, origin) in drag.origins(movingBoundsTo: CGPoint(x: 110, y: 120)) {
            doc.moveLayer(id: layerID, toCanvasOrigin: origin)
        }
        #expect(doc.canvasBounds(of: id(doc, "Box")) ==
                CGRect(x: 110, y: 120, width: 120, height: 80))
        #expect(doc.canvasBounds(of: id(doc, "Away")) ==
                CGRect(x: 310, y: 320, width: 40, height: 40))
    }

    // MARK: What it lines up with

    @Test func nothingBeingDraggedIsSomethingToLineUpWith() {
        let doc = makeFlat()
        let ids = Set([id(doc, "A"), id(doc, "B")])
        let peers = doc.snapPeers(excluding: ids)
        // Only C is left: a member of the selection travels with the drag, so
        // it can never be lined up with.
        #expect(peers == [CGRect(x: 40, y: 300, width: 80, height: 20)])
    }

    @Test func aPickedGroupTakesItsContentsOutOfTheLineUpToo() {
        let doc = makeGrouped()
        let peers = doc.snapPeers(excluding: [id(doc, "Card")])
        #expect(peers == [CGRect(x: 300, y: 300, width: 40, height: 40)])
    }

    @Test func excludingOneLayerIsTheSameAsExcludingASetOfOne() {
        let doc = makeFlat()
        #expect(doc.snapPeers(excluding: id(doc, "A")) ==
                doc.snapPeers(excluding: [id(doc, "A")]))
    }
}
