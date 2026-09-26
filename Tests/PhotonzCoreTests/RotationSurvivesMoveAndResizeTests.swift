import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A turned layer keeps its turn when it is moved or resized.
///
/// Reported 2026-09-26: "I rotate a rectangle. Then I move it or scale it and
/// it loses its rotation." Photoshop and every other editor keep the angle
/// through both, and so must we, on a picture and on a video, with keys and
/// without.
@Suite("Rotation survives move and resize")
struct RotationSurvivesMoveAndResizeTests {

    private static let turn = LayerAngle.radians(fromDegrees: 30)

    private static func turned(_ layer: Layer) -> Layer {
        var layer = layer
        layer.transform.rotation = turn
        return layer
    }

    /// A shape as the tool draws it: dragged corner to corner across `box`.
    private static func drawn(_ shape: AnnotationShape, _ box: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: shape),
                                from: CGPoint(x: box.minX, y: box.minY),
                                to: CGPoint(x: box.maxX, y: box.maxY))
    }

    /// One of every kind of thing a person can turn and then drag about.
    private static func everyKind() -> [Layer] {
        let box = CGRect(x: 100, y: 100, width: 200, height: 100)
        let path = PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                         PathAnchor(point: CGPoint(x: 200, y: 0)),
                                         PathAnchor(point: CGPoint(x: 100, y: 100))],
                               isClosed: true)
        let child = Layer(name: "Piece", content: .annotation(AnnotationContent(shape: .rectangle)),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 40))
        return [
            drawn(.rectangle, box), drawn(.ellipse, box), drawn(.line, box), drawn(.arrow, box),
            Layer(name: "Path", content: .path(path), frame: box),
            Layer(name: "Text", content: .text(TextContent(string: "Hello", fontSize: 32)), frame: box),
            Layer(name: "Image", content: .image(ImageRef(pixelSize: box.size)), frame: box),
            Layer(name: "Group", content: .group(GroupContent(children: [child])),
                  frame: CGRect(origin: box.origin, size: .zero)),
        ].map(turned)
    }

    // MARK: - The model: a new box never touches the angle

    @Test("Moving any kind of layer keeps its angle exactly")
    func moveKeepsAngle() {
        for layer in Self.everyKind() {
            let moved = layer.resized(to: layer.frame.offsetBy(dx: 140, dy: -60), chosenByHand: true)
            #expect(moved.transform == layer.transform, "\(layer.name) lost its angle on a move")
        }
    }

    @Test("Resizing any kind of layer keeps its angle exactly")
    func resizeKeepsAngle() {
        for layer in Self.everyKind() {
            let box = layer.localBounds
            let grown = CGRect(x: box.minX - 10, y: box.minY, width: max(box.width, 1) * 1.5,
                               height: max(box.height, 1) * 0.75)
            let resized = layer.resized(to: grown, chosenByHand: true)
            #expect(resized.transform == layer.transform, "\(layer.name) lost its angle on a resize")
        }
    }

    // MARK: - On a video: keys at the playhead

    /// A rectangle on a ten second video, living from 0 to 10s.
    private static func onAVideo(turned isTurned: Bool = true) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var shape = drawn(.rectangle, CGRect(x: 400, y: 300, width: 300, height: 150))
        if isTurned { shape.transform.rotation = turn }
        shape.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers = [shape]
        doc.durationMS = 10_000
        return (doc, shape.id)
    }

    /// What the canvas does with a hand's edit (`EditorState.foldingIntoKeys`):
    /// the layer is edited as posed at the playhead and whatever is keyed
    /// becomes keys there. The new box is worked out from the pose, the way
    /// the canvas works it out from the handles it drew round the pose.
    private static func canvasEdit(_ doc: inout PhotonzDocument, _ id: UUID, atMS ms: Int,
                                   _ box: (CGRect) -> CGRect) {
        guard let posed = doc.posedForCanvas(atTimeMS: ms).layer(id: id) else {
            Issue.record("no layer"); return
        }
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: ms) { doc in
            doc.updateLayer(id: id) { $0 = $0.resized(to: box(posed.frame), chosenByHand: true) }
        }
    }

    private static func angle(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> CGFloat {
        LayerAngle.degrees(fromRadians: doc.drawn(atTimeMS: ms).layer(id: id)?.transform.rotation ?? .nan)
    }

    @Test("A move at a new moment on a layer with a keyed place keeps the turn")
    func keyedPlaceMoveKeepsTurn() {
        var (doc, id) = Self.onAVideo()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        Self.canvasEdit(&doc, id, atMS: 4000) { $0.offsetBy(dx: 200, dy: 80) }
        #expect(doc.keyCount(layerID: id, .motion(.position)) == 2)
        #expect(abs(Self.angle(doc, id, atMS: 4000) - 30) < 0.001)
        #expect(abs(Self.angle(doc, id, atMS: 1000) - 30) < 0.001)
    }

    @Test("A resize at a new moment on a layer with a keyed size keeps the turn")
    func keyedSizeResizeKeepsTurn() {
        var (doc, id) = Self.onAVideo()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 1000)
        Self.canvasEdit(&doc, id, atMS: 4000) { $0.insetBy(dx: -30, dy: -15) }
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 2)
        #expect(abs(Self.angle(doc, id, atMS: 4000) - 30) < 0.001)
    }

    @Test("A move where the keys have turned the layer keeps the keyed turn, never writing 0")
    func keyedTurnSurvivesAMove() {
        // Upright as drawn; its keys turn it to 30 degrees by 3s.
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        #expect(abs(Self.angle(doc, id, atMS: 5000) - 30) < 0.001)

        Self.canvasEdit(&doc, id, atMS: 5000) { $0.offsetBy(dx: 120, dy: 40) }

        #expect(abs(Self.angle(doc, id, atMS: 5000) - 30) < 0.001,
                "the move wrote an angle of \(Self.angle(doc, id, atMS: 5000)) at 5s")
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 2,
                "a move must not add a rotation key")
    }

    @Test("A resize where the keys have turned the layer keeps the keyed turn")
    func keyedTurnSurvivesAResize() {
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 1000)

        Self.canvasEdit(&doc, id, atMS: 5000) { $0.insetBy(dx: -30, dy: -15) }

        #expect(abs(Self.angle(doc, id, atMS: 5000) - 30) < 0.001)
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 2)
    }

    @Test("A move with ONLY the turn keyed moves the layer and keeps the keyed turn")
    func onlyTurnKeyedMove() {
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        guard let before = doc.layer(id: id) else { Issue.record("no layer"); return }

        Self.canvasEdit(&doc, id, atMS: 5000) { $0.offsetBy(dx: 120, dy: 40) }

        #expect(doc.layer(id: id)?.frame.origin == before.frame.origin.applying(
            CGAffineTransform(translationX: 120, y: 40)))
        #expect(abs(Self.angle(doc, id, atMS: 5000) - 30) < 0.001)
        #expect(abs(Self.angle(doc, id, atMS: 1000) - 0) < 0.001)
    }

    @Test("A turn by the knob on a keyed turn still becomes a key")
    func knobStillKeys() {
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: 5000) { doc in
            doc.updateLayer(id: id) { $0.transform.rotation = LayerAngle.radians(fromDegrees: 45) }
        }
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 2)
        #expect(abs(Self.angle(doc, id, atMS: 5000) - 45) < 0.001)
    }

    @Test("Turning a keyed layer back to its stored angle is still a key")
    func turnBackToStoredAngleKeys() {
        // Stored upright, keyed to 30 by 3s. At 5s the knob, snapped, turns it
        // back to 0, which happens to be the stored angle: that is still a
        // turn the hand made and must land as a key of 0 at 5s.
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: 5000) { doc in
            doc.updateLayer(id: id) { $0.transform.rotation = 0 }
        }
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 3)
        #expect(abs(Self.angle(doc, id, atMS: 5000)) < 0.001)
        #expect(abs(Self.angle(doc, id, atMS: 3000) - 30) < 0.001)
    }

    @Test("Undo of a move on a keyed layer is the document as it was")
    func editIsOneReversibleChange() {
        var (doc, id) = Self.onAVideo(turned: false)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        let before = doc
        // An Escape: the hand let go where it took hold.
        Self.canvasEdit(&doc, id, atMS: 5000) { $0 }
        #expect(doc == before, "an edit that changed nothing must leave nothing behind")
    }
}
