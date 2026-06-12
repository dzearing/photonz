import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The layers panel lists layers top-down (visual index 0 = topmost = last in
/// `layers`). Reorders arrive in SwiftUI `onMove` semantics: source offsets and
/// a destination expressed against the pre-removal visual array.
@Suite("Layer reorder & duplicate")
struct LayerReorderTests {

    private func makeDocument() -> PhotonzDocument {
        // Bottom → top: A, B, C. Visual (panel) order: C, B, A.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        for name in ["A", "B", "C"] {
            doc.addLayer(Layer(name: name, content: .text(TextContent(string: name)),
                               frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        }
        return doc
    }

    @Test func moveTopmostBelowNext() {
        var doc = makeDocument()
        // Visual [C, B, A]: drag row 0 (C) to sit after row 1 (B) → destination 2.
        doc.moveLayers(visualSources: IndexSet(integer: 0), visualDestination: 2)
        #expect(doc.layers.map(\.name) == ["A", "C", "B"])
    }

    @Test func moveBottomToTop() {
        var doc = makeDocument()
        // Visual [C, B, A]: drag row 2 (A) to the top → destination 0.
        // New visual order [A, C, B] = layers [B, C, A] bottom-up.
        doc.moveLayers(visualSources: IndexSet(integer: 2), visualDestination: 0)
        #expect(doc.layers.map(\.name) == ["B", "C", "A"])
    }

    @Test func moveToSamePlaceIsANoOp() {
        var doc = makeDocument()
        // SwiftUI reports a no-move drag as destination == source or source+1.
        doc.moveLayers(visualSources: IndexSet(integer: 1), visualDestination: 1)
        #expect(doc.layers.map(\.name) == ["A", "B", "C"])
        doc.moveLayers(visualSources: IndexSet(integer: 1), visualDestination: 2)
        #expect(doc.layers.map(\.name) == ["A", "B", "C"])
    }

    @Test func moveMultipleRowsKeepsTheirRelativeOrder() {
        var doc = makeDocument()
        // Visual [C, B, A]: drag rows {0, 2} (C and A) to destination 1 (after C's
        // removal slot) → visual [C, A, B]... per onMove semantics the moved block
        // lands where destination 1 falls after removals: [B] with C,A inserted at 0.
        doc.moveLayers(visualSources: IndexSet([0, 2]), visualDestination: 1)
        #expect(doc.layers.map(\.name) == ["B", "A", "C"])
    }

    @Test func outOfRangeDestinationClamps() {
        var doc = makeDocument()
        doc.moveLayers(visualSources: IndexSet(integer: 0), visualDestination: 99)
        #expect(doc.layers.map(\.name) == ["C", "A", "B"])
    }

    @Test func duplicatedLayerGetsFreshIdentityAndOffset() {
        let original = Layer(name: "Note", content: .text(TextContent(string: "hi")),
                             frame: CGRect(x: 10, y: 20, width: 50, height: 30))
        let copy = original.duplicated(offsetBy: CGPoint(x: 16, y: 16))
        #expect(copy.id != original.id)
        #expect(copy.name == "Note copy")
        #expect(copy.frame == CGRect(x: 26, y: 36, width: 50, height: 30))
        #expect(copy.content == original.content)
        #expect(copy.style == original.style)
    }

    @Test func duplicateInDocumentInsertsDirectlyAbove() {
        var doc = makeDocument()
        let b = doc.layers[1]
        let copy = doc.duplicateLayer(id: b.id)
        #expect(copy != nil)
        #expect(doc.layers.map(\.name) == ["A", "B", "B copy", "C"])
    }
}
