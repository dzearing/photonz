import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A document asked for the same layers over and over (every clip bar and cut
/// on an hour-long timeline asks on every frame) keeps an index of where each
/// layer is, and the index always answers what the walk would have
/// (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
@Suite("Finding a layer by id, many times")
struct LayerLookupIndexTests {
    static func box(_ name: String) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#00FF00")),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    static func document() -> PhotonzDocument {
        let inner = Self.box("Inner")
        let deeper = Layer(name: "Deeper", content: .group(GroupContent(children: [Self.box("Deepest")])),
                           frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner, deeper])),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let loose = (0..<40).map { Self.box("Box \($0)") }
        return PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: loose + [group])
    }

    static func everyID(_ layers: [Layer]) -> [UUID] {
        layers.flatMap { [$0.id] + everyID($0.children) }
    }

    @Test("Asked many times, every layer, nested or not, is found and nothing else is")
    func manyTimes() {
        let document = Self.document()
        let ids = Self.everyID(document.layers)
        for _ in 0..<3 {
            for id in ids { #expect(document.layer(id: id)?.id == id) }
        }
        #expect(document.layer(id: UUID()) == nil)
        #expect(document.layer(id: ids.last ?? UUID())?.name == "Deepest")
    }

    @Test("After an edit the answers are the edited document's")
    func afterAnEdit() {
        var document = Self.document()
        let ids = Self.everyID(document.layers)
        for id in ids { _ = document.layer(id: id) }
        // Renamed in place, deep inside a group.
        let last = document.layers.count - 1
        document.layers[last].children[1].children[0].name = "Renamed"
        #expect(document.layer(id: ids.last ?? UUID())?.name == "Renamed")
        // Removed: no longer found, and the rest still are.
        let gone = document.layers[0].id
        document.layers.remove(at: 0)
        #expect(document.layer(id: gone) == nil)
        for id in ids.dropFirst() { #expect(document.layer(id: id)?.id == id) }
        // Moved: found where it went.
        document.layers.swapAt(0, document.layers.count - 1)
        for id in ids.dropFirst() { #expect(document.layer(id: id)?.id == id) }
    }

    @Test("A copy edited apart answers for itself")
    func copies() {
        let original = Self.document()
        let ids = Self.everyID(original.layers)
        for id in ids { _ = original.layer(id: id) }
        var copy = original
        copy.layers[0].name = "Copy's"
        #expect(copy.layer(id: ids[0])?.name == "Copy's")
        #expect(original.layer(id: ids[0])?.name == "Box 0")
    }
}
