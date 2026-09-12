import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A layer with nothing painted on it has no box, and everything that asks a
/// layer for its box has to cope with that: handles, snapping, and the
/// Position & Size fields.
@Suite("A layer with nothing on it")
struct EmptyLayerBoxTests {

    private func emptyLayer() -> Layer {
        Layer(name: "Layer", content: .image(ImageRef(pixelSize: CGSize(width: 1, height: 1))),
              frame: .zero)
    }

    private func paintedLayer(_ frame: CGRect) -> Layer {
        Layer(name: "Layer", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    // MARK: The state itself

    @Test func aFreshImageLayerWithNoFrameHasNothingOnIt() {
        #expect(emptyLayer().hasNothingOnIt)
    }

    @Test func aPaintedLayerHasSomethingOnIt() {
        #expect(!paintedLayer(CGRect(x: 10, y: 10, width: 40, height: 30)).hasNothingOnIt)
    }

    @Test func aLineDrawnFlatStillHasSomethingOnIt() {
        // A line's box is flat on purpose: it is drawn between two ends, so a
        // zero height there is the shape, not an absence of one.
        let annotation = AnnotationContent(shape: .line, start: .zero,
                                           end: CGPoint(x: 100, y: 0))
        let line = Layer(name: "Line", content: .annotation(annotation),
                         frame: CGRect(x: 0, y: 50, width: 100, height: 0))
        #expect(!line.hasNothingOnIt)
    }

    // MARK: Handles

    @Test func anEmptyBoxOffersNoHandles() {
        #expect(Handles.layout(in: .zero, zoom: 1).handles.isEmpty)
    }

    @Test func nothingCanBeGrabbedOnAnEmptyBox() {
        #expect(Handles.hit(at: .zero, frame: .zero, zoom: 1) == nil)
        #expect(Handles.hit(at: CGPoint(x: 2, y: 2), frame: .zero, zoom: 1) == nil)
        #expect(Handles.hit(at: .zero, frame: .zero, zoom: 1, edgeGrab: true) == nil)
    }

    @Test func aRealBoxStillOffersItsHandles() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(!Handles.layout(in: frame, zoom: 1).handles.isEmpty)
        #expect(Handles.hit(at: CGPoint(x: 100, y: 100), frame: frame, zoom: 1) == .topLeft)
    }

    // MARK: Snapping

    @Test func anEmptyLayerIsNotSomethingToLineUpWith() {
        let empty = emptyLayer()
        let painted = paintedLayer(CGRect(x: 200, y: 200, width: 100, height: 100))
        let dragged = paintedLayer(CGRect(x: 0, y: 0, width: 50, height: 50))
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [empty, painted, dragged])
        let peers = document.snapPeers(excluding: dragged.id)
        #expect(peers == [CGRect(x: 200, y: 200, width: 100, height: 100)])
    }

    // MARK: Position & Size

    @Test func noneOfTheFourNumbersTakesTyping() {
        let editing = LayerGeometryEditing(layer: emptyLayer())
        for field in LayerGeometryField.allCases {
            #expect(!editing.allows(field))
            #expect(!editing.shows(field))
        }
    }

    @Test func everyFieldSaysWhyThereIsNoNumber() {
        let editing = LayerGeometryEditing(layer: emptyLayer())
        for field in LayerGeometryField.allCases {
            #expect(editing.fixedReason(for: field) == LayerGeometryEditing.nothingOnItReason)
        }
    }

    @Test func theFieldsReadBlankRatherThanZero() {
        let layer = emptyLayer()
        let selection = LayerGeometrySelection([
            LayerGeometrySelection.Member(id: layer.id, frame: layer.frame,
                                          editing: LayerGeometryEditing(layer: layer))
        ])
        for field in LayerGeometryField.allCases {
            #expect(selection.reading(field) == .empty)
            #expect(selection.reading(field).readoutText == LayerGeometrySelection.blankText)
        }
    }

    @Test func theLineUnderTheFieldsSaysToPaintSomething() {
        let layer = emptyLayer()
        let selection = LayerGeometrySelection([
            LayerGeometrySelection.Member(id: layer.id, frame: layer.frame,
                                          editing: LayerGeometryEditing(layer: layer))
        ])
        #expect(selection.caption == LayerGeometryEditing.nothingOnItReason)
    }

    @Test func aPaintedLayerStillTypesItsNumbers() {
        let layer = paintedLayer(CGRect(x: 10, y: 20, width: 40, height: 30))
        let editing = LayerGeometryEditing(layer: layer)
        #expect(editing.allows(.x))
        #expect(editing.allows(.width))
        #expect(editing.fixedReason(for: .width) == nil)
    }
}
