import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the W and H fields show once a typed number has landed.
///
/// The panel used to work the answer out BEFORE the change, from the floors it
/// knew about, and a layer that refused for a reason the panel had not heard of
/// left a number in the box that nothing on the canvas had. A group with a
/// smallest width is that layer: it is not a floor on the layer, it is a rule
/// its own flow applies afterwards.
///
/// So the fields read the layers again after the commit. These tests pin what
/// that read has to say, using the very call the panel commits through.
@Suite("What a geometry field reads back after a commit")
struct GeometryReadBackTests {

    private func rectangle(_ frame: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                from: CGPoint(x: frame.minX, y: frame.minY),
                                to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    /// A stack the size of what is in it, held between a smallest and a
    /// largest width — the pair the Layout section's Smallest and Largest rows
    /// set. 200 wide as it stands, and it will not leave 160...260.
    private func heldStack(from: CGFloat = 160, to: CGFloat = 260) -> Layer {
        var content = GroupContent(children: [rectangle(CGRect(x: 0, y: 0, width: 200, height: 60)),
                                              rectangle(CGRect(x: 0, y: 0, width: 200, height: 40))])
        content.layout = GroupLayout(kind: .stack, minWidth: from, maxWidth: to)
        return Layer(name: "Held", content: .group(content),
                     frame: CGRect(x: 10, y: 10, width: 0, height: 0))
    }

    /// The selection the panel builds for these layers: each one read as the
    /// box a person sees.
    private func selection(_ layers: [Layer]) -> LayerGeometrySelection {
        LayerGeometrySelection(layers.map { layer in
            LayerGeometrySelection.Member(id: layer.id,
                                          frame: layer.withoutSlack(layer.shownBox),
                                          editing: LayerGeometryEditing(layer: layer),
                                          slack: layer.boxSlack)
        })
    }

    /// Typing `value` into `field` and letting the document take it, through
    /// the same call `EditorState.commitGeometry` makes.
    private func committing(_ value: CGFloat, into field: LayerGeometryField,
                            _ layers: [Layer]) -> [Layer] {
        let moves = selection(layers).applying(value, to: field)
        return layers.map { layer in
            guard let frame = moves[layer.id] else { return layer }
            return layer.geometrySet(to: frame, canvas: CGSize(width: 900, height: 600),
                                     byHand: true)
        }
    }

    /// What the field shows afterwards: the layers, read again.
    private func readingAfter(_ value: CGFloat, into field: LayerGeometryField,
                              _ layers: [Layer]) -> LayerGeometryReading {
        selection(committing(value, into: field, layers)).reading(field)
    }

    @Test("A width the flow will not go below reads back as the width it kept")
    func refusedWidthReadsBackAsWhatItKept() {
        let stack = heldStack()
        #expect(selection([stack]).reading(.width) == .agreed(200))
        #expect(readingAfter(50, into: .width, [stack]) == .agreed(160))
    }

    @Test("A width past what the flow allows reads back as the width it stopped at")
    func widthPastTheCeilingReadsBackAsTheCeiling() {
        #expect(readingAfter(300, into: .width, [heldStack()]) == .agreed(260))
    }

    @Test("A width the layers accept reads back exactly as typed")
    func acceptedWidthReadsBackAsTyped() {
        #expect(readingAfter(240, into: .width, [heldStack()]) == .agreed(240))
    }

    @Test("One number two layers land differently on reads back as Mixed")
    func differentLandingsReadBackAsMixed() {
        let plain = rectangle(CGRect(x: 0, y: 400, width: 200, height: 40))
        #expect(readingAfter(50, into: .width, [heldStack(), plain]) == .mixed)
    }

    @Test("An arrow key steps from the number on screen, so it steps from what they kept")
    func steppingStartsFromWhatTheyKept() {
        // Held at 160, a step down has nowhere to go and the box holds at 160.
        let held = committing(50, into: .width, [heldStack()])
        #expect(selection(held).reading(.width) == .agreed(160))
        let stepped = selection(held).stepping(.width, direction: -1, coarse: false)
        let after = held.map { layer -> Layer in
            guard let frame = stepped[layer.id] else { return layer }
            return layer.geometrySet(to: frame, canvas: CGSize(width: 900, height: 600),
                                     byHand: true)
        }
        #expect(selection(after).reading(.width) == .agreed(160))
    }
}
