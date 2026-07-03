import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func annotationLayer(name: String, frame: CGRect,
                             visible: Bool = true, locked: Bool = false) -> Layer {
    Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
          frame: frame, isVisible: visible, isLocked: locked)
}

@Suite("Marquee layer multi-select")
struct MarqueeLayerSelectTests {

    private let canvas = CGSize(width: 1000, height: 800)

    @Test func selectsLayersFullyInsideTheRect() {
        var doc = PhotonzDocument(canvasSize: canvas)
        let a = annotationLayer(name: "A", frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        let b = annotationLayer(name: "B", frame: CGRect(x: 200, y: 150, width: 40, height: 40))
        doc.addLayer(a)
        doc.addLayer(b)
        let ids = doc.layerIDs(fullyInside: CGRect(x: 50, y: 50, width: 300, height: 300))
        #expect(ids == [a.id, b.id])
    }

    @Test func excludesLayersMerelyIntersectingTheRect() {
        // A long arrow sweeping through the marquee shouldn't be grabbed.
        var doc = PhotonzDocument(canvasSize: canvas)
        let inside = annotationLayer(name: "In", frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        let crossing = annotationLayer(name: "Crossing", frame: CGRect(x: 0, y: 120, width: 900, height: 20))
        doc.addLayer(inside)
        doc.addLayer(crossing)
        let ids = doc.layerIDs(fullyInside: CGRect(x: 50, y: 50, width: 200, height: 200))
        #expect(ids == [inside.id])
    }

    @Test func excludesLockedAndInvisibleLayers() {
        // The locked background image never joins a rubber-band selection, and
        // hidden layers can't be deleted by something the user can't see.
        var doc = PhotonzDocument(canvasSize: canvas)
        let locked = annotationLayer(name: "Locked", frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                                     locked: true)
        let hidden = annotationLayer(name: "Hidden", frame: CGRect(x: 40, y: 40, width: 20, height: 20),
                                     visible: false)
        let normal = annotationLayer(name: "Normal", frame: CGRect(x: 70, y: 70, width: 20, height: 20))
        doc.addLayer(locked)
        doc.addLayer(hidden)
        doc.addLayer(normal)
        let ids = doc.layerIDs(fullyInside: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(ids == [normal.id])
    }

    @Test func rotatedLayerContainmentUsesItsTransformedBounds() {
        // A 45°-rotated square's corners poke outside its frame; a rect that
        // holds the frame but not the rotated bounds must NOT capture it.
        var doc = PhotonzDocument(canvasSize: canvas)
        var rotated = annotationLayer(name: "R", frame: CGRect(x: 100, y: 100, width: 100, height: 100))
        rotated.transform = LayerTransform(rotation: .pi / 4)
        doc.addLayer(rotated)
        let tight = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(doc.layerIDs(fullyInside: tight).isEmpty)
        // Diagonal ≈ 141.4 centered on (150,150) → generous rect captures it.
        let generous = CGRect(x: 75, y: 75, width: 150, height: 150)
        #expect(doc.layerIDs(fullyInside: generous) == [rotated.id])
    }

    @Test func emptyRectSelectsNothing() {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.addLayer(annotationLayer(name: "A", frame: CGRect(x: 100, y: 100, width: 50, height: 50)))
        #expect(doc.layerIDs(fullyInside: .zero).isEmpty)
        #expect(doc.layerIDs(fullyInside: CGRect(x: 500, y: 500, width: 10, height: 10)).isEmpty)
    }
}

@Suite("Batch layer removal")
struct RemoveLayersTests {

    private let canvas = CGSize(width: 1000, height: 800)

    @Test func removesAllGivenLayersInOneMutation() {
        var doc = PhotonzDocument(canvasSize: canvas)
        let a = annotationLayer(name: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let b = annotationLayer(name: "B", frame: CGRect(x: 20, y: 0, width: 10, height: 10))
        let keep = annotationLayer(name: "Keep", frame: CGRect(x: 40, y: 0, width: 10, height: 10))
        doc.addLayer(a)
        doc.addLayer(keep)
        doc.addLayer(b)
        doc.removeLayers(ids: [a.id, b.id])
        #expect(doc.layers.map(\.id) == [keep.id])
    }

    @Test func unknownIDsAreIgnored() {
        var doc = PhotonzDocument(canvasSize: canvas)
        let a = annotationLayer(name: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.addLayer(a)
        doc.removeLayers(ids: [UUID(), a.id])
        #expect(doc.layers.isEmpty)
    }
}
